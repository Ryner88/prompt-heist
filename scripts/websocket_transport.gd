class_name RoomWebSocketTransport
extends RefCounted

var _peer := WebSocketPeer.new()

func connect_to_url(endpoint: String) -> Error:
	# Passing no TLSOptions preserves Godot's default certificate and hostname
	# verification for secure WebSocket endpoints.
	return _peer.connect_to_url(endpoint)

func poll() -> void:
	_peer.poll()

func get_ready_state() -> int:
	return _peer.get_ready_state()

func get_available_packet_count() -> int:
	return _peer.get_available_packet_count()

func read_text() -> Dictionary:
	var packet := _peer.get_packet()
	return {"ok": _peer.was_string_packet(), "text": packet.get_string_from_utf8()}

func send_text(message: String) -> Error:
	return _peer.send_text(message)

func close() -> void:
	if _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close(1000, "client leaving")
		# Godot sends the close frame during poll; leaving the flow stops normal
		# polling, so flush it before dropping the client session.
		_peer.poll()

func get_close_reason() -> String:
	return _peer.get_close_reason()
