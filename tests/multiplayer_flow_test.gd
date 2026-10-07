extends RefCounted

const ClientScript = preload("res://scripts/room_network_client.gd")
const FlowScript = preload("res://scripts/multiplayer_flow.gd")
const Protocol = preload("res://scripts/room_protocol.gd")
const MainScript = preload("res://scripts/main.gd")
var failures: Array[String] = []
var allocated_nodes: Array[Node] = []

class FakeTransport:
	extends RefCounted
	var state := WebSocketPeer.STATE_CLOSED
	var sent: Array[String] = []
	func connect_to_url(_endpoint: String) -> Error:
		state = WebSocketPeer.STATE_CONNECTING
		return OK
	func poll() -> void: pass
	func get_ready_state() -> int: return state
	func get_available_packet_count() -> int: return 0
	func read_text() -> Dictionary: return {}
	func send_text(message: String) -> Error:
		sent.append(message)
		return OK
	func close() -> void: state = WebSocketPeer.STATE_CLOSED
	func get_close_reason() -> String: return ""

func run() -> void:
	_test_input_boundaries_and_normalization()
	_test_submit_once_and_pending_controls()
	_test_error_mapping()
	_test_authoritative_lobby_progression_and_full_error()
	_test_disconnect_and_local_navigation()
	_test_recovery_and_acknowledged_leave()
	allocated_nodes.reverse()
	for node in allocated_nodes:
		node.free()
	if failures.is_empty():
		print("MultiplayerFlow tests passed: 6 cases")
	else:
		for failure in failures:
			push_error(failure)

func _test_input_boundaries_and_normalization() -> void:
	_check(Protocol.validate_name("") != "", "Empty name must be invalid")
	_check(Protocol.validate_name("   ") != "", "Whitespace-only name must be invalid")
	_check(Protocol.validate_name("A") != "", "One-character name must be invalid")
	_check(Protocol.validate_name("AB") == "", "Two-character name must be valid")
	_check(Protocol.validate_name("123456789012345678") == "", "18-character name must be valid")
	_check(Protocol.validate_name("1234567890123456789") != "", "19-character name must be invalid")
	_check(Protocol.normalize_name(" Ａｄａ ") == "Ada", "Common NFKC full-width forms must normalize")
	_check(Protocol.normalize_room_code(" abc234 ") == "ABC234", "Lowercase room code must normalize")
	_check(Protocol.validate_room_code("ABC23") != "", "Five-character code must be invalid")
	_check(Protocol.validate_room_code("ABC234") == "", "Six-character code must be valid")
	_check(Protocol.validate_room_code("ABC2345") != "", "Seven-character code must be invalid")
	for ambiguous in ["A0CD23", "A1CD23", "AICD23", "AOCD23"]:
		_check(Protocol.validate_room_code(ambiguous) != "", "Ambiguous room-code characters must be rejected")

func _test_submit_once_and_pending_controls() -> void:
	var fixture := _flow_fixture()
	_check(fixture.flow.can_create("Ada"), "Valid connected entry should enable create")
	_check(fixture.flow.submit_create("Ada"), "First create submission should succeed")
	_check(fixture.flow.state == FlowScript.State.SUBMITTING, "Submission must enter Submitting state")
	_check(not fixture.flow.submit_create("Ada"), "Double-click create must submit only once")
	_check(not fixture.flow.can_create("Ada") and not fixture.flow.can_join("Ada", "ABC234"), "Controls must remain disabled while pending")
	_check(fixture.transport.sent.size() == 1, "Only one command may be serialized")

func _test_error_mapping() -> void:
	var expected := {
		"invalid_name": "2–18",
		"unknown_room": "not found",
		"duplicate_name": "another name",
		"room_full": "four seats",
		"connection_already_joined": "already joined",
		"rate_limited": "Wait",
		"unsupported_version": "incompatible",
		"invalid_message": "protocol error",
	}
	for code in expected:
		_check(Protocol.error_message(code).contains(expected[code]), "Error %s must map to readable UI text" % code)
	_check(Protocol.error_message("future_error").contains("could not complete"), "Unknown errors need a safe generic fallback")

func _test_authoritative_lobby_progression_and_full_error() -> void:
	var fixture := _flow_fixture()
	fixture.flow.submit_create("Ada")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	fixture.client.ingest_server_text(_command_result(request.request_id), fixture.client.connection_generation)
	_check(fixture.flow.state == FlowScript.State.LOBBY and fixture.flow.lobby_snapshot.is_empty(), "Lobby must wait for an authoritative snapshot")
	for count in range(1, 5):
		var names: Array = ["Ada", "Ben", "Cy", "Dee"].slice(0, count)
		fixture.client.ingest_server_text(_snapshot("ABC234", names), fixture.client.connection_generation)
		_check(fixture.flow.lobby_snapshot.player_count == count, "Snapshot progression must update authoritative count %d" % count)
	var before: Dictionary = fixture.flow.lobby_snapshot.duplicate(true)
	fixture.client.request_failed.emit("room_full", Protocol.error_message("room_full"))
	_check(fixture.flow.lobby_snapshot == before, "Fifth-player room_full must not change the four-player snapshot")

func _test_disconnect_and_local_navigation() -> void:
	var fixture := _flow_fixture()
	fixture.flow.submit_create("Ada")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	fixture.client.ingest_server_text(_command_result(request.request_id), fixture.client.connection_generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"]), fixture.client.connection_generation)
	fixture.transport.state = WebSocketPeer.STATE_CLOSED
	fixture.client.poll_transport()
	_check(fixture.flow.state == FlowScript.State.DISCONNECTED, "Transport disconnect must enter Disconnected state")
	_check(fixture.flow.lobby_snapshot.is_empty(), "Disconnect must clear lobby state")
	_check(fixture.client.player_id.is_empty() and fixture.client.session_id.is_empty(), "Disconnect must clear private identity")
	_check(not fixture.flow.submit_create("Ada"), "Disconnected state must block room actions")
	var main = MainScript.new()
	allocated_nodes.append(main)
	_check(main.has_method("_show_lobby") and main.has_method("_show_mode_selection"), "Existing pass-and-play navigation must remain available")

func _test_recovery_and_acknowledged_leave() -> void:
	var fixture := _flow_fixture()
	fixture.flow.submit_create("Ada")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	fixture.client.ingest_server_text(_command_result(request.request_id), fixture.client.connection_generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"]), fixture.client.connection_generation)
	fixture.transport.state = WebSocketPeer.STATE_CLOSED
	fixture.client.poll_transport()
	_check(fixture.client.has_recovery() and fixture.flow.state == FlowScript.State.DISCONNECTED, "Transient disconnect must retain private recovery data")
	_check(fixture.flow.connect_service("ws://127.0.0.1:3000/ws"), "Retry should start a new connection")
	fixture.transport.state = WebSocketPeer.STATE_OPEN
	fixture.client.poll_transport()
	_check(fixture.flow.state == FlowScript.State.RECOVERING, "Connection with a token must request server recovery")
	var resume_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(resume_request.type == "resume_room" and resume_request.payload.room_code == "ABC234", "Recovery must target the server-owned room")
	fixture.client.ingest_server_text(_command_result(resume_request.request_id, "resume_room"), fixture.client.connection_generation)
	_check(fixture.flow.state == FlowScript.State.LOBBY and fixture.flow.lobby_snapshot.is_empty(), "Resume must wait for a fresh authoritative snapshot")
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"]), fixture.client.connection_generation)
	fixture.flow.leave_lobby()
	_check(fixture.flow.state == FlowScript.State.LEAVING and fixture.client.has_recovery(), "Leave must wait for server acknowledgement before clearing the token")
	var leave_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(leave_request.type == "leave_room", "Explicit leave must send the authoritative leave command")
	fixture.client.ingest_server_text(JSON.stringify({"version": 1, "type": "command_result", "request_id": leave_request.request_id, "payload": {"command": "leave_room", "room_code": "ABC234"}}), fixture.client.connection_generation)
	_check(fixture.flow.state == FlowScript.State.DISCONNECTED and not fixture.client.has_recovery(), "Acknowledged leave must clear recovery and return to disconnected state")

func _flow_fixture() -> Dictionary:
	var transport := FakeTransport.new()
	var client = ClientScript.new(transport)
	var flow = FlowScript.new(client)
	allocated_nodes.append(client)
	allocated_nodes.append(flow)
	flow.bind_client(client)
	_check(flow.connect_service("ws://127.0.0.1:3000/ws"), "Fixture flow should start connecting")
	transport.state = WebSocketPeer.STATE_OPEN
	client.poll_transport()
	_check(flow.state == FlowScript.State.ENTRY, "Connected fixture should enter Entry")
	return {"transport": transport, "client": client, "flow": flow}

func _command_result(request_id: String, command: String = "create_room") -> String:
	return JSON.stringify({
		"version": 1, "type": "command_result", "request_id": request_id,
		"payload": {"command": command, "room_code": "ABC234", "player_id": "player-a", "session_id": "private-session", "reconnect_token": "B".repeat(43) if command == "resume_room" else "A".repeat(43)},
	})

func _snapshot(room_code: String, names: Array) -> String:
	return JSON.stringify({
		"version": 1, "type": "room_snapshot", "request_id": null,
		"payload": {"room_code": room_code, "player_names": names, "player_count": names.size(), "max_players": 4, "revision": names.size()},
	})

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
