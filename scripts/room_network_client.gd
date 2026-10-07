class_name RoomNetworkClient
extends Node

signal connected(connection_generation: int)
signal disconnected(message: String)
signal command_succeeded(command: String, payload: Dictionary)
signal room_snapshot_received(snapshot: Dictionary)
signal request_failed(code: String, message: String)
signal shutdown_announced(message: String)
signal protocol_warning(message: String)
signal recovery_started()
signal left_room()

const Protocol = preload("res://scripts/room_protocol.gd")
const DefaultTransport = preload("res://scripts/websocket_transport.gd")
const REQUEST_TIMEOUT_MS := 10000
const RECOVERY_STORAGE_KEY := "prompt_heist_room_recovery_v1"

var player_id := ""
var session_id := ""
var active_room_code := ""
var reconnect_token := ""
var reconnect_room_code := ""
var connection_generation := 0
var _last_revision := 0

var _transport: RefCounted
var _pending: Dictionary = {}
var _request_counter := 0
var _connecting := false
var _connected := false
var _closing := false
var _endpoint := ""

func _init(transport: RefCounted = null) -> void:
	_transport = transport if transport != null else DefaultTransport.new()
	_load_recovery()

func _ready() -> void:
	set_process(true)

func connect_to_service(endpoint: String) -> bool:
	if _closing:
		_transport.poll()
		if _transport.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			disconnected.emit("The previous connection is closing. Please try again in a moment.")
			return false
		_closing = false
	if _connecting or _connected:
		return false
	var endpoint_error := Protocol.validate_endpoint(endpoint)
	if not endpoint_error.is_empty():
		disconnected.emit(endpoint_error)
		return false
	connection_generation += 1
	_endpoint = endpoint.strip_edges()
	_connecting = true
	if _transport.connect_to_url(_endpoint) != OK:
		_connecting = false
		_clear_session()
		disconnected.emit("Could not start a connection to the room service.")
		return false
	return true

func _process(_delta: float) -> void:
	poll_transport()

func poll_transport() -> void:
	if _closing:
		_transport.poll()
		if _transport.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing = false
		return
	if not _connecting and not _connected:
		return
	_transport.poll()
	var state: int = _transport.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connecting = false
			_connected = true
			if has_recovery():
				recovery_started.emit()
				if not _send_command("resume_room", {"room_code": reconnect_room_code, "reconnect_token": reconnect_token, "sync": true}):
					disconnect_from_service(false)
					disconnected.emit("Could not request room recovery. Connect again to retry.")
			else:
				connected.emit(connection_generation)
		while _transport.get_available_packet_count() > 0:
			var packet: Dictionary = _transport.read_text()
			if not packet.get("ok", false):
				protocol_warning.emit("The room service sent an unsupported binary message.")
				continue
			ingest_server_text(str(packet.get("text", "")), connection_generation)
		_expire_pending_request()
	elif state == WebSocketPeer.STATE_CLOSED:
		var had_connection := _connecting or _connected
		_connecting = false
		_connected = false
		if had_connection:
			var reason: String = _transport.get_close_reason()
			_handle_disconnect("The room service disconnected. Retry to recover your reserved seat." if reason.is_empty() else "The room service disconnected. Retry to recover your reserved seat.")

func create_room(display_name: String) -> bool:
	return _send_command("create_room", {"display_name": Protocol.normalize_name(display_name), "reconnect": true, "sync": true})

func join_room(room_code: String, display_name: String) -> bool:
	return _send_command("join_room", {
		"room_code": Protocol.normalize_room_code(room_code),
		"display_name": Protocol.normalize_name(display_name),
		"reconnect": true,
		"sync": true,
	})

func leave_room() -> bool:
	if active_room_code.is_empty():
		return false
	return _send_command("leave_room", {})

func has_recovery() -> bool:
	return not reconnect_token.is_empty() and not reconnect_room_code.is_empty()

func has_pending_request() -> bool:
	return not _pending.is_empty()

func is_connected_to_service() -> bool:
	return _connected

func disconnect_from_service(clear_recovery: bool = true) -> void:
	if _connecting or _connected:
		_transport.close()
		_closing = _transport.get_ready_state() != WebSocketPeer.STATE_CLOSED
	_connecting = false
	_connected = false
	_clear_session()
	if clear_recovery:
		_clear_recovery()

func ingest_server_text(text: String, generation: int) -> void:
	if generation != connection_generation or not _connected:
		return
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		protocol_warning.emit("The room service sent malformed data.")
		return
	var parsed: Dictionary = parser.data
	if parsed.keys().size() != 4 or parsed.get("version") != Protocol.VERSION or not parsed.get("type") is String or not parsed.has("request_id") or not parsed.get("payload") is Dictionary:
		protocol_warning.emit("The room service sent an invalid protocol message.")
		return
	var message_type: String = parsed.type
	match message_type:
		"command_result": _handle_command_result(parsed)
		"room_snapshot": _handle_snapshot(parsed)
		"error": _handle_error(parsed)
		"server_shutdown": _handle_shutdown(parsed)
		_: protocol_warning.emit("The room service sent an unsupported response.")

func _send_command(command: String, payload: Dictionary) -> bool:
	if not _connected or has_pending_request():
		return false
	var request_id := _next_request_id()
	_pending[request_id] = {
		"command": command,
		"generation": connection_generation,
		"room_code": payload.get("room_code", ""),
		"deadline_ms": Time.get_ticks_msec() + REQUEST_TIMEOUT_MS,
	}
	var envelope := Protocol.make_envelope(command, request_id, payload)
	if _transport.send_text(JSON.stringify(envelope)) != OK:
		_pending.erase(request_id)
		request_failed.emit("transport_error", "The request could not be sent. Please try again.")
		return false
	return true

func _handle_command_result(message: Dictionary) -> void:
	var request_id: Variant = message.request_id
	if not Protocol.is_safe_request_id(request_id) or not _pending.has(request_id):
		return
	var pending: Dictionary = _pending[request_id]
	if pending.generation != connection_generation:
		return
	var payload: Dictionary = message.payload
	var expected := ["command", "room_code"] if pending.command == "leave_room" else ["command", "room_code", "player_id", "session_id", "reconnect_token"]
	if payload.keys().size() != expected.size():
		_reject_invalid_result(request_id)
		return
	for key in expected:
		if not payload.has(key) or not payload[key] is String or payload[key].is_empty():
			_reject_invalid_result(request_id)
			return
	if payload.command != pending.command or Protocol.validate_room_code(payload.room_code) != "" \
			or payload.room_code != Protocol.normalize_room_code(payload.room_code) \
			or (pending.command in ["join_room", "resume_room"] and payload.room_code != pending.room_code) \
			or (pending.command == "leave_room" and payload.room_code != active_room_code) \
			or (pending.command != "leave_room" and not _valid_reconnect_token(payload.reconnect_token)):
		_reject_invalid_result(request_id)
		return
	_pending.erase(request_id)
	if pending.command == "leave_room":
		disconnect_from_service()
		left_room.emit()
		return
	player_id = payload.player_id
	session_id = payload.session_id
	active_room_code = payload.room_code
	_last_revision = 0
	reconnect_token = payload.reconnect_token
	reconnect_room_code = payload.room_code
	_save_recovery()
	command_succeeded.emit(payload.command, {
		"command": payload.command,
		"room_code": payload.room_code,
	})

func _reject_invalid_result(request_id: String) -> void:
	_pending.erase(request_id)
	protocol_warning.emit("The room service returned an invalid command result.")
	disconnect_from_service()
	disconnected.emit("The room service returned an invalid command result. Connect again to continue.")

func _handle_snapshot(message: Dictionary) -> void:
	if message.request_id != null or not Protocol.validate_snapshot(message.payload):
		protocol_warning.emit("The room service returned an invalid room snapshot.")
		return
	var snapshot: Dictionary = Protocol.normalized_snapshot(message.payload)
	if active_room_code.is_empty() or snapshot.room_code != active_room_code:
		protocol_warning.emit("A snapshot outside the active room was ignored.")
		return
	if snapshot.revision <= _last_revision:
		return
	_last_revision = snapshot.revision
	room_snapshot_received.emit(snapshot.duplicate(true))

func _handle_error(message: Dictionary) -> void:
	var payload: Dictionary = message.payload
	if payload.keys().size() != 1 or not payload.has("code") or not payload.code is String:
		protocol_warning.emit("The room service returned an invalid error.")
		return
	var request_id: Variant = message.request_id
	if request_id == null:
		protocol_warning.emit("The room service reported a protocol error.")
		return
	if not Protocol.is_safe_request_id(request_id) or not _pending.has(request_id):
		return
	var pending: Dictionary = _pending[request_id]
	if pending.generation != connection_generation:
		return
	_pending.erase(request_id)
	if pending.command == "resume_room":
		if payload.code in ["invalid_reconnect", "unknown_room"]:
			_clear_recovery()
			request_failed.emit(payload.code, Protocol.error_message(payload.code))
			connected.emit(connection_generation)
			return
		disconnect_from_service(false)
		disconnected.emit(Protocol.error_message(payload.code))
		return
	if pending.command == "leave_room":
		disconnect_from_service(false)
		disconnected.emit(Protocol.error_message(payload.code))
		return
	request_failed.emit(payload.code, Protocol.error_message(payload.code))

func _handle_shutdown(message: Dictionary) -> void:
	if message.request_id != null or message.payload.keys().size() != 1 or message.payload.get("reason") != "service_restart":
		protocol_warning.emit("The room service returned an invalid shutdown notice.")
		return
	shutdown_announced.emit("The room service is restarting. Its rooms have been cleared; create or join again.")
	_transport.close()
	_closing = _transport.get_ready_state() != WebSocketPeer.STATE_CLOSED
	_connecting = false
	_connected = false
	_clear_session()
	_clear_recovery()

func _handle_disconnect(message: String) -> void:
	_clear_session()
	disconnected.emit(message)

func _clear_session() -> void:
	player_id = ""
	session_id = ""
	active_room_code = ""
	_last_revision = 0
	_pending.clear()

func _expire_pending_request() -> void:
	if _pending.is_empty():
		return
	var request_id: String = _pending.keys()[0]
	if Time.get_ticks_msec() < int(_pending[request_id].deadline_ms):
		return
	disconnect_from_service(false)
	disconnected.emit("The room service did not answer in time. Connect again to retry.")

func _valid_reconnect_token(value: Variant) -> bool:
	if not value is String or value.length() != 43:
		return false
	for character in value:
		if not (character >= "A" and character <= "Z") and not (character >= "a" and character <= "z") \
				and not (character >= "0" and character <= "9") and character != "_" and character != "-":
			return false
	return true

func _clear_recovery() -> void:
	reconnect_token = ""
	reconnect_room_code = ""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { sessionStorage.removeItem('%s'); } catch (e) {}" % RECOVERY_STORAGE_KEY)

func _save_recovery() -> void:
	if not OS.has_feature("web"):
		return
	var serialized := JSON.stringify({"room_code": reconnect_room_code, "reconnect_token": reconnect_token})
	JavaScriptBridge.eval("try { sessionStorage.setItem('%s', %s); } catch (e) {}" % [RECOVERY_STORAGE_KEY, JSON.stringify(serialized)])

func _load_recovery() -> void:
	if not OS.has_feature("web"):
		return
	var serialized: Variant = JavaScriptBridge.eval("try { sessionStorage.getItem('%s') || ''; } catch (e) { ''; }" % RECOVERY_STORAGE_KEY)
	if not serialized is String or serialized.is_empty():
		return
	var parsed: Variant = JSON.parse_string(serialized)
	if parsed is Dictionary and parsed.keys().size() == 2 and parsed.has("room_code") and parsed.has("reconnect_token") \
			and parsed.room_code is String and parsed.room_code == Protocol.normalize_room_code(parsed.room_code) \
			and Protocol.validate_room_code(parsed.room_code) == "" and _valid_reconnect_token(parsed.reconnect_token):
		reconnect_room_code = parsed.room_code
		reconnect_token = parsed.reconnect_token
	else:
		_clear_recovery()

func _next_request_id() -> String:
	_request_counter += 1
	var random_bytes := Crypto.new().generate_random_bytes(8)
	return "godot-%d-%d-%s" % [connection_generation, _request_counter, random_bytes.hex_encode()]
