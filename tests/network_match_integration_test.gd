extends SceneTree

## Three real Godot clients play a complete cooperative heist against the real
## Node room authority. Run with TEST_WS_URL pointing at a running service.

const ClientScript = preload("res://scripts/room_network_client.gd")
const PLANS := ["ghost", "social", "rooftop"]
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
	var ada = _new_client()
	var ben = _new_client()
	var cy = _new_client()
	for client in clients:
		_check(client.connect_to_service(endpoint), "Each Godot client should start connecting")
	if not await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return client.get_meta("connected", false))):
		await _finish("All Godot clients should connect to Node")
		return

	ada.create_room("Ada")
	if not await _wait_until(func() -> bool: return not ada.active_room_code.is_empty()):
		await _finish("Ada should create a room")
		return
	var room_code: String = ada.active_room_code
	ben.join_room(room_code, "Ben")
	await _wait_until(func() -> bool: return not ben.active_room_code.is_empty())
	cy.join_room(room_code, "Cy")
	if not await _wait_until(func() -> bool: return not cy.active_room_code.is_empty()):
		await _finish("Ben and Cy should join the room")
		return

	_check(cy.start_match(), "Any seated member should be able to start")
	if not await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return _phase(client) == "role_reveal" and not _private(client).is_empty())):
		await _finish("Every client should receive the opening heist view and its private role")
		return
	var seats := []
	for client in clients:
		var private_state: Dictionary = _private(client)
		seats.append(int(private_state.seat))
		_check(private_state.role != "Informant", "A three-player heist has no Informant")
		var events: String = JSON.stringify(client.get_meta("public_updates"))
		for other in clients:
			if other != client:
				_check(not events.contains(other.session_id) and not events.contains(other.player_id), "Public heist updates must not carry another player's identity")
	_check(seats == [0, 1, 2], "Seats follow the room roster order")

	for step in [["role_reveal", 1], ["briefing", 1], ["planning", 1]]:
		if not await _everyone_ready(step[0], step[1]):
			await _finish("Every client should advance past %s" % step[0])
			return
	for round_number in range(1, 4):
		if round_number > 1 and not await _everyone_ready("planning", round_number):
			await _finish("Every client should reach round %d voting" % round_number)
			return
		if not await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return _phase(client) == "voting" and int(_snapshot(client).round) == round_number)):
			await _finish("Voting should open for round %d" % round_number)
			return
		for client in clients:
			_check(client.cast_vote(round_number, PLANS[round_number - 1]), "Each client should vote")
			await _wait_until(func() -> bool: return not client.has_pending_request())
		if not await _everyone_ready("resolution", round_number):
			await _finish("Round %d should resolve and advance" % round_number)
			return

	if not await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return _phase(client) == "finished")):
		await _finish("Every client should reach the recap")
		return
	var recap: Dictionary = _snapshot(ada)
	_check(recap.outcome.winner == "Everyone", "Three successful plans should win the cooperative heist")
	_check(recap.outcome.successful_rounds == 3 and recap.outcome.accusation == null, "Cooperative recaps skip the accusation")
	for client in clients:
		_check(_snapshot(client) == recap, "Every client should show an identical recap")
	await _finish("")

func _everyone_ready(phase: String, round_number: int) -> bool:
	if not await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return _phase(client) == phase and int(_snapshot(client).round) == round_number)):
		return false
	for client in clients:
		_check(client.ready_step(phase, round_number), "Each client should acknowledge %s" % phase)
		await _wait_until(func() -> bool: return not client.has_pending_request())
	return await _wait_until(func() -> bool: return clients.all(func(client: Node) -> bool: return _phase(client) != phase or int(_snapshot(client).round) != round_number))

func _new_client() -> Node:
	var client = ClientScript.new()
	client.set_meta("connected", false)
	client.set_meta("match", {})
	client.set_meta("private", {})
	client.set_meta("public_updates", [])
	client.connected.connect(func(_generation: int) -> void: client.set_meta("connected", true))
	client.match_snapshot_received.connect(func(snapshot: Dictionary) -> void:
		client.set_meta("match", snapshot)
		var updates: Array = client.get_meta("public_updates")
		updates.append(snapshot)
	)
	client.match_private_received.connect(func(state: Dictionary) -> void: client.set_meta("private", state))
	client.request_failed.connect(func(code: String, _message: String) -> void: _fail("Unexpected heist error: %s" % code))
	root.add_child(client)
	clients.append(client)
	return client

func _snapshot(client: Node) -> Dictionary:
	return client.get_meta("match")

func _private(client: Node) -> Dictionary:
	return client.get_meta("private")

func _phase(client: Node) -> String:
	return str(_snapshot(client).get("phase", ""))

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

func _finish(failure: String) -> void:
	if not failure.is_empty():
		_fail(failure)
	for client in clients:
		client.disconnect_from_service()
	for _index in 3:
		await process_frame
	if failures.is_empty():
		print("Godot/Node heist integration passed: start, private roles, readiness, three voting rounds, identical recap")
	quit(1 if not failures.is_empty() else 0)
