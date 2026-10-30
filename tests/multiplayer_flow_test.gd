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
	_test_expired_recovery_returns_to_entry()
	_test_match_progression_and_abandonment()
	_test_online_controls_recover_after_match_and_start_error()
	_test_disconnected_lobby_start_controls()
	allocated_nodes.reverse()
	for node in allocated_nodes:
		node.free()
	if failures.is_empty():
		print("MultiplayerFlow tests passed: 10 cases")
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
	_check(main.has_method("_show_online_match") and main.has_method("_show_online_recap"), "Online heist screens must be available")

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
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "command_result", "request_id": leave_request.request_id, "payload": {"command": "leave_room", "room_code": "ABC234"}}), fixture.client.connection_generation)
	_check(fixture.flow.state == FlowScript.State.DISCONNECTED and not fixture.client.has_recovery(), "Acknowledged leave must clear recovery and return to disconnected state")

func _test_expired_recovery_returns_to_entry() -> void:
	var fixture := _flow_fixture()
	fixture.flow.submit_create("Ada")
	var create_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(_command_result(create_request.request_id), fixture.client.connection_generation)
	fixture.transport.state = WebSocketPeer.STATE_CLOSED
	fixture.client.poll_transport()
	_check(fixture.client.has_recovery(), "Disconnected fixture should retain recovery data")
	fixture.flow.connect_service("ws://127.0.0.1:3000/ws")
	fixture.transport.state = WebSocketPeer.STATE_OPEN
	fixture.client.poll_transport()
	_check(fixture.flow.state == FlowScript.State.RECOVERING, "Saved seat should enter recovery")
	var resume_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "error", "request_id": resume_request.request_id, "payload": {"code": "invalid_reconnect"}}), fixture.client.connection_generation)
	_check(fixture.flow.state == FlowScript.State.ENTRY and not fixture.client.has_recovery(), "Expired recovery must offer create and join with no stale token")
	_check(fixture.flow.feedback.contains("expired"), "Expired recovery must explain what happened")

func _test_match_progression_and_abandonment() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/match_contract.json"))
	var fixture := _flow_fixture()
	var generation: int = fixture.client.connection_generation
	fixture.flow.submit_create("Ada")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	fixture.client.ingest_server_text(_command_result(request.request_id), generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada", "Ben"]), generation)
	_check(not fixture.flow.can_start_match() and not fixture.flow.start_match(), "Two players cannot start a heist")
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada", "Ben", "Cy", "Dee"]), generation)
	_check(fixture.flow.can_start_match(), "Three or more players can start")
	_check(fixture.flow.start_match(), "Start should send")
	_check(not fixture.flow.can_start_match() and not fixture.flow.start_match(), "A pending start blocks a second click")
	var start_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(_match_result(start_request.request_id, "start_match"), generation)
	_check(fixture.flow.state == FlowScript.State.LOBBY, "The start acknowledgement alone does not change screens")

	fixture.client.ingest_server_text(JSON.stringify(contract.valid_public.social_role_reveal), generation)
	_check(fixture.flow.state == FlowScript.State.MATCH and fixture.flow.match_snapshot.phase == "role_reveal", "The authoritative heist snapshot moves every member into the match")
	_check(fixture.flow.my_seat() == -1 and not fixture.flow.is_ready(), "Seat-specific state waits for the private update")
	fixture.client.ingest_server_text(JSON.stringify(contract.valid_private.crew), generation)
	_check(fixture.flow.my_seat() == 1 and not fixture.flow.is_informant(), "The private update identifies only this player's seat and role")
	_check(not fixture.flow.vote("ghost") and not fixture.flow.accuse(0), "Votes and accusations are closed during role reveal")
	_check(fixture.flow.ready_current_step(), "Readiness should send during role reveal")
	var ready_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(ready_request.type == "ready" and ready_request.payload.phase == "role_reveal" and int(ready_request.payload.round) == 1, "Readiness must name the current step")
	_check(not fixture.flow.ready_current_step(), "A pending readiness blocks a duplicate click")
	fixture.client.ingest_server_text(_match_result(ready_request.request_id, "ready"), generation)

	fixture.client.ingest_server_text(JSON.stringify(contract.valid_public.social_voting), generation)
	_check(not fixture.flow.ready_current_step(), "Voting is not a readiness step")
	_check(not fixture.flow.vote("ghost", true), "Crew cannot request sabotage")
	_check(fixture.flow.vote("ghost"), "A crew member can vote once")
	var vote_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(vote_request.type == "cast_vote" and not vote_request.payload.has("sabotage"), "A crew vote carries no sabotage flag")
	fixture.client.ingest_server_text(_match_result(vote_request.request_id, "cast_vote"), generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada", "Ben", "Cy", "Dee"], 9), generation)
	_check(fixture.flow.state == FlowScript.State.MATCH, "Room roster updates during a heist keep the match screen")

	var abandoned: Dictionary = contract.valid_public.abandoned.duplicate(true)
	abandoned.payload.revision = 99
	fixture.client.ingest_server_text(JSON.stringify(abandoned), generation)
	_check(fixture.flow.state == FlowScript.State.LOBBY and fixture.flow.match_snapshot.is_empty() and fixture.flow.match_private.is_empty(), "An abandoned heist returns everyone to the waiting room and clears private state")
	_check(fixture.flow.feedback.contains("left the room"), "Players learn why the heist ended")
	abandoned.payload.revision = 100
	fixture.client.ingest_server_text(JSON.stringify(abandoned), generation)
	_check(fixture.flow.state == FlowScript.State.LOBBY, "An abandoned notice outside a match is ignored")

	var finished: Dictionary = contract.valid_public.social_finished_crew_wins.duplicate(true)
	finished.payload.revision = 101
	fixture.client.ingest_server_text(JSON.stringify(finished), generation)
	_check(fixture.flow.state == FlowScript.State.MATCH and fixture.flow.match_snapshot.outcome.winner == "Crew", "A recovered seat in a finished room shows the recap")
	_check(fixture.flow.ready_current_step(), "Players can ask to return to the waiting room from the recap")
	var return_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(return_request.type == "ready" and return_request.payload.phase == "finished" and int(return_request.payload.round) == 3, "Returning acknowledges the finished recap")
	fixture.client.ingest_server_text(_match_result(return_request.request_id, "ready"), generation)
	var pending_return: Dictionary = contract.valid_public.social_finished_rematch_pending.duplicate(true)
	pending_return.payload.revision = 102
	fixture.client.ingest_server_text(JSON.stringify(pending_return), generation)
	_check(fixture.flow.state == FlowScript.State.MATCH and fixture.flow.match_snapshot.progress.done == 1, "The recap stays open until everyone has returned")
	var closed: Dictionary = contract.valid_public.closed.duplicate(true)
	closed.payload.revision = 103
	fixture.client.ingest_server_text(JSON.stringify(closed), generation)
	_check(fixture.flow.state == FlowScript.State.LOBBY and fixture.flow.match_snapshot.is_empty(), "A closed heist returns everyone to the waiting room")
	_check(fixture.flow.feedback.contains("waiting room"), "Players learn the room is open again")
	_check(fixture.flow.can_start_match(), "A new heist can start from the reopened room")

	finished.payload.revision = 104
	fixture.client.ingest_server_text(JSON.stringify(finished), generation)
	fixture.flow.leave_lobby()
	_check(fixture.flow.state == FlowScript.State.LEAVING, "Players can leave from the heist screens")

func _test_online_controls_recover_after_match_and_start_error() -> void:
	var main = MainScript.new()
	allocated_nodes.append(main)
	main._build_shell()
	main._initialize_multiplayer()
	main.multiplayer_flow.state = FlowScript.State.LOBBY
	main.multiplayer_flow.lobby_snapshot = {
		"room_code": "ABC234", "player_names": ["Ada", "Ben", "Cy"],
		"player_count": 3, "max_players": 4,
	}
	main._render_multiplayer_state()
	var start_button: Button = _active_start_button(main)
	_check(start_button != null and not start_button.disabled, "Three connected seats enable Start heist")
	if start_button != null:
		start_button.disabled = true
		start_button.text = "Starting…"
	main.room_client.request_failed.emit("player_disconnected", "Wait for everyone to reconnect.")
	start_button = _active_start_button(main)
	_check(start_button != null and not start_button.disabled and start_button.text == "Start heist", "Rejected start restores the Start heist control without a room revision")
	main.online_sabotage_armed = true
	main.multiplayer_flow.state = FlowScript.State.MATCH
	main.multiplayer_flow.state_changed.emit(FlowScript.State.MATCH)
	_check(not main.online_sabotage_armed, "Starting a new heist clears an old sabotage choice")
	main.online_sabotage_armed = true
	main.multiplayer_flow.state = FlowScript.State.LOBBY
	main.multiplayer_flow.state_changed.emit(FlowScript.State.LOBBY)
	_check(not main.online_sabotage_armed, "Leaving a heist clears an unspent sabotage choice")
	var fixture := _flow_fixture()
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/match_contract.json"))
	main.multiplayer_flow = fixture.flow
	fixture.client.active_room_code = "ABC234"
	fixture.flow.state = FlowScript.State.MATCH
	fixture.flow.match_snapshot = contract.valid_public.social_voting.payload.duplicate(true)
	fixture.flow.match_private = {"vote": null, "sabotage_available": false}
	main.online_sabotage_armed = true
	main._clear_content()
	main._add_online_plan_cards(fixture.flow.match_snapshot, true)
	for button in main.content.find_children("*", "Button", true, false):
		if button.text == "Vote for this plan":
			button.pressed.emit()
			break
	_check(not fixture.transport.sent.is_empty(), "A stale sabotage choice does not block a crew vote")
	if not fixture.transport.sent.is_empty():
		var vote_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
		_check(vote_request.type == "cast_vote" and not vote_request.payload.has("sabotage"), "A crew vote does not include the stale sabotage choice")

func _test_disconnected_lobby_start_controls() -> void:
	var main = MainScript.new()
	allocated_nodes.append(main)
	main._build_shell()
	main._initialize_multiplayer()
	main.multiplayer_flow.state = FlowScript.State.LOBBY
	main.multiplayer_flow.lobby_snapshot = {
		"room_code": "ABC234", "player_names": ["Ada", "Ben", "Cy", "Dee"],
		"player_count": 4, "max_players": 4, "connected": [true, true, true, false],
	}
	main._render_multiplayer_state()
	_check(not main.multiplayer_flow.can_start_match() and main.multiplayer_flow.can_start_match(true), "A disconnected fourth seat blocks four-player start but allows an explicit three-player start")
	var start_button: Button = _active_start_button(main)
	_check(start_button != null and start_button.disabled, "Normal Start heist stays disabled while a seat is disconnected")
	var connected_buttons: Array = main.content.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Start with 3 connected players")
	_check(connected_buttons.size() == 1, "Lobby offers a clear three-player start option")
	var offline_labels: Array = main.content.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.text.contains("Dee (disconnected)"))
	_check(offline_labels.size() == 1, "Lobby identifies the disconnected player")
	main.multiplayer_flow.lobby_snapshot.connected = [true, true, false, false]
	main._render_multiplayer_state()
	_check(not main.multiplayer_flow.can_start_match(true), "Fewer than three online players cannot start")

func _active_start_button(main: Control) -> Button:
	for child in main.content.get_children():
		if child is Button and child.text == "Start heist" and not child.is_queued_for_deletion():
			return child
	return null

func _match_result(request_id: String, command: String) -> String:
	return JSON.stringify({"version": 2, "type": "command_result", "request_id": request_id, "payload": {"command": command, "room_code": "ABC234"}})

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
		"version": 2, "type": "command_result", "request_id": request_id,
		"payload": {"command": command, "room_code": "ABC234", "player_id": "player-a", "session_id": "private-session", "reconnect_token": "B".repeat(43) if command == "resume_room" else "A".repeat(43)},
	})

func _snapshot(room_code: String, names: Array, revision: int = -1) -> String:
	return JSON.stringify({
		"version": 2, "type": "room_snapshot", "request_id": null,
		"payload": {"room_code": room_code, "player_names": names, "player_count": names.size(), "max_players": 4, "revision": names.size() if revision < 0 else revision},
	})

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
