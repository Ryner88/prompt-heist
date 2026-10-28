extends SceneTree

const ClientScript = preload("res://scripts/room_network_client.gd")
var clients: Array[Node] = []
var failures: Array[String] = []
var endpoint := ""

func _initialize() -> void:
	endpoint = OS.get_environment("TEST_WS_URL").strip_edges()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ws-url="):
			endpoint = argument.trim_prefix("--ws-url=").strip_edges()
	if endpoint.is_empty():
		push_error("TEST_WS_URL is required")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	var ada = _new_client("ada")
	var ben = _new_client("ben")
	var cy = _new_client("cy")
	var dee = _new_client("dee")
	var eli = _new_client("eli")
	var duplicate = _new_client("duplicate")
	var missing = _new_client("missing")
	var zoe = _new_client("zoe")
	for client in clients:
		_check(client.connect_to_service(endpoint), "Each real Godot client should start connecting")
	if not await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return client.get_meta("connected", false))):
		_fail("All real Godot clients should connect to Node")
		await _finish()
		return

	ada.create_room("Ada")
	if not await _wait_until(func() -> bool: return not ada.active_room_code.is_empty() and _latest_count(ada) == 1):
		_fail("First client should create a room and receive the one-player snapshot")
		await _finish()
		return
	var room_code: String = ada.active_room_code
	_check(room_code.length() == 6, "Real service should return a six-character room code")

	ben.join_room(room_code.to_lower(), "Ben")
	if not await _wait_until(func() -> bool: return _latest_count(ada) == 2 and _latest_count(ben) == 2):
		_fail("Lowercase join should synchronize an identical two-player snapshot")
		await _finish()
		return
	_check(_latest_snapshot(ada) == _latest_snapshot(ben), "Creator and joiner snapshots should be identical")
	duplicate.join_room(room_code, "  aDA  ")
	await _wait_until(func() -> bool: return _last_error(duplicate) == "duplicate_name")
	_check(_last_error(duplicate) == "duplicate_name", "Normalized duplicate name should be rejected")

	cy.join_room(room_code, "Cy")
	await _wait_until(func() -> bool: return _latest_count(ada) == 3 and _latest_count(cy) == 3)
	dee.join_room(room_code, "Dee")
	await _wait_until(func() -> bool: return _latest_count(ada) == 4 and _latest_count(dee) == 4)
	_check(_latest_count(ada) == 4, "Third and fourth clients should fill the room")

	eli.join_room(room_code, "Eli")
	await _wait_until(func() -> bool: return _last_error(eli) == "room_full")
	_check(_last_error(eli) == "room_full", "Fifth client should receive room_full")
	_check(_latest_count(ada) == 4, "Fifth join must not change the four-player snapshot")

	missing.join_room("ZZZ999", "Mia")
	await _wait_until(func() -> bool: return _last_error(missing) == "unknown_room")
	_check(_last_error(missing) == "unknown_room", "Unknown room should be rejected")

	zoe.create_room("Zoe")
	await _wait_until(func() -> bool: return not zoe.active_room_code.is_empty() and _latest_count(zoe) == 1)
	_check(zoe.active_room_code != room_code, "Second room should receive an isolated code")
	_check(_latest_snapshot(zoe).player_names == ["Zoe"], "Second room should contain only its own player")
	_check(_latest_count(ada) == 4, "Second-room changes must not alter the first room")

	var ben_private: String = ben.session_id
	var ada_events: String = JSON.stringify(ada.get_meta("events"))
	_check(not ben_private.is_empty() and not ada_events.contains(ben_private), "Godot must never expose another player's private session identity")
	_check(_snapshot_is_public(_latest_snapshot(ada)), "Real public snapshot must contain only allowlisted fields")

	var old_token: String = ben.reconnect_token
	ben._transport.close()
	await _wait_until(func() -> bool: return not ben.is_connected_to_service())
	_check(ben.has_recovery() and _latest_count(ada) == 4, "Transient disconnect should reserve the seat without exposing a token")
	_check(ben.connect_to_service(endpoint), "Disconnected client should reconnect to the authority")
	await _wait_until(func() -> bool: return ben.is_connected_to_service() and ben.reconnect_token != old_token and _latest_count(ben) == 4)
	_check(ben.active_room_code == room_code and ben.reconnect_token != old_token, "Resume should rotate the private credential and recover the same room")
	_check(ben.leave_room(), "Explicit leave should send an authoritative command")
	await _wait_until(func() -> bool: return _latest_count(ada) == 3 and not ben.has_recovery())
	_check(_latest_count(ada) == 3, "Acknowledged leave should release the seat immediately")
	await _finish()

func _new_client(label: String) -> Node:
	var client = ClientScript.new()
	client.set_meta("label", label)
	client.set_meta("connected", false)
	client.set_meta("events", [])
	client.connected.connect(func(_generation: int) -> void: client.set_meta("connected", true))
	client.command_succeeded.connect(func(command: String, payload: Dictionary) -> void:
		var events: Array = client.get_meta("events")
		events.append({"type": "command", "command": command, "payload": payload.duplicate(true)})
	)
	client.room_snapshot_received.connect(func(snapshot: Dictionary) -> void:
		var events: Array = client.get_meta("events")
		events.append({"type": "snapshot", "payload": snapshot.duplicate(true)})
	)
	client.request_failed.connect(func(code: String, _message: String) -> void:
		var events: Array = client.get_meta("events")
		events.append({"type": "error", "code": code})
	)
	root.add_child(client)
	clients.append(client)
	return client

func _latest_snapshot(client: Node) -> Dictionary:
	var events: Array = client.get_meta("events")
	for index in range(events.size() - 1, -1, -1):
		if events[index].type == "snapshot":
			return events[index].payload
	return {}

func _latest_count(client: Node) -> int:
	return int(_latest_snapshot(client).get("player_count", -1))

func _last_error(client: Node) -> String:
	var events: Array = client.get_meta("events")
	for index in range(events.size() - 1, -1, -1):
		if events[index].type == "error":
			return events[index].code
	return ""

func _snapshot_is_public(snapshot: Dictionary) -> bool:
	var keys := snapshot.keys()
	keys.sort()
	return keys == ["max_players", "player_count", "player_names", "revision", "room_code"]

func _wait_until(predicate: Callable, timeout_ms := 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _finish() -> void:
	for client in clients:
		client.disconnect_from_service()
	for _index in 3:
		await process_frame
	if failures.is_empty():
		print("Godot/Node real-service integration passed: create, join, capacity, errors, isolation, privacy, resume, leave")
	quit(1 if not failures.is_empty() else 0)
