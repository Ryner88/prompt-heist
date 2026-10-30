extends RefCounted

const ClientScript = preload("res://scripts/room_network_client.gd")
const Protocol = preload("res://scripts/room_protocol.gd")
var failures: Array[String] = []
var allocated_nodes: Array[Node] = []

class FakeTransport:
	extends RefCounted
	var state := WebSocketPeer.STATE_CLOSED
	var sent: Array[String] = []
	var packets: Array[Dictionary] = []
	var connect_calls := 0
	var delay_close := false
	var close_polls := 0
	var endpoint := ""
	var close_reason := ""

	func connect_to_url(value: String) -> Error:
		connect_calls += 1
		endpoint = value
		state = WebSocketPeer.STATE_CONNECTING
		return OK

	func poll() -> void:
		if state == WebSocketPeer.STATE_CLOSING:
			close_polls += 1
			if close_polls >= 2:
				state = WebSocketPeer.STATE_CLOSED

	func get_ready_state() -> int:
		return state

	func get_available_packet_count() -> int:
		return packets.size()

	func read_text() -> Dictionary:
		return packets.pop_front()

	func send_text(message: String) -> Error:
		sent.append(message)
		return OK

	func close() -> void:
		state = WebSocketPeer.STATE_CLOSING if delay_close else WebSocketPeer.STATE_CLOSED

	func get_close_reason() -> String:
		return close_reason

	func open() -> void:
		state = WebSocketPeer.STATE_OPEN

func run() -> void:
	_test_endpoint_security_and_connection_guard()
	_test_create_join_envelopes_and_unique_ids()
	_test_response_correlation_identity_and_privacy()
	_test_untrusted_messages_and_stale_generation()
	_test_snapshot_validation_and_room_isolation()
	_test_resume_rotation_and_invalid_credential()
	_test_match_contract_validation()
	_test_match_messages_and_commands()
	_test_old_server_upgrade_error()
	for node in allocated_nodes:
		node.free()
	if failures.is_empty():
		print("RoomNetworkClient tests passed: 9 cases")
	else:
		for failure in failures:
			push_error(failure)

func _test_endpoint_security_and_connection_guard() -> void:
	_check(Protocol.validate_endpoint("") != "", "Missing endpoint must be rejected")
	_check(Protocol.validate_endpoint("http://example.com/ws") != "", "HTTP endpoint must be rejected")
	_check(Protocol.validate_endpoint("ws://example.com/ws") != "", "Non-loopback insecure endpoint must be rejected")
	_check(Protocol.validate_endpoint("ws://127.0.0.1:3000/ws") == "", "Loopback development endpoint should be accepted")
	_check(Protocol.validate_endpoint("ws://[::1]:3000/ws") == "", "IPv6 loopback development endpoint should be accepted")
	_check(Protocol.validate_endpoint("ws://127.evil.example/ws") != "", "Lookalike 127 host must not bypass TLS")
	_check(Protocol.validate_endpoint("ws://[::1]evil.example/ws") != "", "IPv6 loopback prefix must not bypass TLS")
	_check(Protocol.validate_endpoint("wss:///ws") != "", "A secure endpoint still requires a host")
	_check(Protocol.validate_endpoint("wss://rooms.example.com:/ws") != "", "An empty port must be rejected")
	_check(Protocol.validate_endpoint("wss://rooms.example.com/ws") == "", "Secure production endpoint should be accepted")
	_check(Protocol.validate_endpoint("wss://rooms.example.com/socket") != "", "Endpoint must use the documented /ws path")
	var fixture := _connected_client()
	_check(not fixture.client.connect_to_service("ws://127.0.0.1:3000/ws"), "A simultaneous connection attempt must be rejected")
	_check(fixture.transport.connect_calls == 1, "Only one transport connection should be attempted")
	fixture.transport.delay_close = true
	fixture.client.disconnect_from_service()
	_check(not fixture.client.connect_to_service("ws://127.0.0.1:3000/ws"), "Immediate retry must wait for close handshake")
	fixture.client.poll_transport()
	_check(fixture.client.connect_to_service("ws://127.0.0.1:3000/ws"), "Retry should succeed after close handshake")

func _test_create_join_envelopes_and_unique_ids() -> void:
	var fixture := _connected_client()
	_check(fixture.client.create_room("  Ada  "), "Create should send when connected")
	_check(not fixture.client.create_room("Ada"), "A second submission while pending must be rejected")
	var create_message: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	_check(create_message.version == 2 and create_message.type == "create_room", "Create must use protocol-v2 envelope")
	_check(create_message.payload == {"display_name": "Ada", "reconnect": true, "sync": true, "game": true, "presence": true}, "Create name and capabilities must be normalized")
	_check(Protocol.is_safe_request_id(create_message.request_id), "Create request ID must be safe")
	fixture.client.ingest_server_text(_error(create_message.request_id, "unknown_room"), fixture.client.connection_generation)
	_check(fixture.client.join_room(" abc234 ", " Ａｄａ "), "Join should send after the first request resolves")
	var join_message: Dictionary = JSON.parse_string(fixture.transport.sent[1])
	_check(join_message.type == "join_room", "Join must use the join command")
	_check(join_message.payload == {"room_code": "ABC234", "display_name": "Ada", "reconnect": true, "sync": true, "game": true, "presence": true}, "Join code, name, and capabilities must be normalized")
	_check(create_message.request_id != join_message.request_id, "Every command must receive a unique request ID")

func _test_response_correlation_identity_and_privacy() -> void:
	var fixture := _connected_client()
	var public_results: Array[Dictionary] = []
	fixture.client.command_succeeded.connect(func(_command: String, payload: Dictionary) -> void: public_results.append(payload))
	fixture.client.create_room("Ada")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	fixture.client.ingest_server_text(_command_result("not-pending", "create_room", "ABC234", "player-x", "session-x"), fixture.client.connection_generation)
	_check(fixture.client.player_id.is_empty(), "Uncorrelated responses must not store identity")
	fixture.client.ingest_server_text(_command_result(request.request_id, "create_room", "ABC234", "player-a", "session-secret"), fixture.client.connection_generation)
	_check(fixture.client.player_id == "player-a" and fixture.client.session_id == "session-secret" and fixture.client.has_recovery(), "Correlated success must store private identity and recovery credential in memory")
	_check(public_results.size() == 1 and public_results[0] == {"command": "create_room", "room_code": "ABC234"}, "Neither player nor session identity may be exposed through UI-facing signals")
	_check(fixture.client.create_room("Ada"), "A later command should be permitted after success")
	var second_request: Dictionary = JSON.parse_string(fixture.transport.sent[1])
	var invalid_result: Dictionary = JSON.parse_string(_command_result(second_request.request_id, "create_room", "ABC234", "player-b", "session-b"))
	invalid_result.payload["authoritative_state"] = true
	fixture.client.ingest_server_text(JSON.stringify(invalid_result), fixture.client.connection_generation)
	_check(not fixture.client.has_pending_request(), "A malformed correlated result must release the pending request")
	_check(fixture.client.session_id.is_empty() and not fixture.client.is_connected_to_service(), "A malformed correlated result must close the uncertain server session")
	fixture.client.disconnect_from_service()
	_check(fixture.client.player_id.is_empty() and fixture.client.session_id.is_empty(), "Disconnect must clear all identity")
	_check(not fixture.client.has_pending_request(), "Disconnect must clear pending requests")
	var timeout_fixture := _connected_client()
	var disconnect_messages: Array[String] = []
	timeout_fixture.client.disconnected.connect(func(message: String) -> void: disconnect_messages.append(message))
	timeout_fixture.client.create_room("Ada")
	var timeout_request: Dictionary = JSON.parse_string(timeout_fixture.transport.sent[0])
	timeout_fixture.client._pending[timeout_request.request_id].deadline_ms = Time.get_ticks_msec() - 1
	timeout_fixture.client.poll_transport()
	_check(not timeout_fixture.client.is_connected_to_service() and not timeout_fixture.client.has_pending_request(), "A timed-out command must close the uncertain server session")
	_check(disconnect_messages.size() == 1 and disconnect_messages[0].contains("did not answer"), "Command timeout must offer a safe retry message")

func _test_untrusted_messages_and_stale_generation() -> void:
	var fixture := _connected_client()
	var warnings: Array[String] = []
	fixture.client.protocol_warning.connect(func(message: String) -> void: warnings.append(message))
	fixture.client.ingest_server_text("{", fixture.client.connection_generation)
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "mystery", "request_id": null, "payload": {}}), fixture.client.connection_generation)
	_check(warnings.size() == 2, "Malformed and unknown server messages must be handled safely")
	fixture.client.create_room("Ada")
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "error", "request_id": null, "payload": {"code": "invalid_message"}}), fixture.client.connection_generation)
	_check(fixture.client.has_pending_request(), "Uncorrelated errors must not resolve a pending request")
	_check(warnings.size() == 3, "Uncorrelated errors should produce safe protocol warnings")
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "room_snapshot", "request_id": null, "payload": {}, "internal": true}), fixture.client.connection_generation)
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "server_shutdown", "request_id": null, "payload": {"reason": "other"}}), fixture.client.connection_generation)
	_check(warnings.size() == 5 and fixture.client.is_connected_to_service(), "Extra envelope fields and malformed shutdown notices must be ignored")
	var old_generation: int = fixture.client.connection_generation
	fixture.client.disconnect_from_service()
	_check(fixture.client.connect_to_service("ws://127.0.0.1:3000/ws"), "A new connection should start after disconnect")
	fixture.transport.open()
	fixture.client.poll_transport()
	fixture.client.ingest_server_text(_command_result("old", "create_room", "ABC234", "stale", "stale-secret"), old_generation)
	_check(fixture.client.player_id.is_empty(), "A stale response from a prior connection must be ignored")

func _test_snapshot_validation_and_room_isolation() -> void:
	var fixture := _connected_client()
	var snapshots: Array[Dictionary] = []
	var warnings: Array[String] = []
	fixture.client.room_snapshot_received.connect(func(snapshot: Dictionary) -> void: snapshots.append(snapshot))
	fixture.client.protocol_warning.connect(func(message: String) -> void: warnings.append(message))
	fixture.client.create_room("Ada")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent[0])
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"], 1), fixture.client.connection_generation)
	_check(snapshots.is_empty(), "Snapshots before a correlated room result must not be exposed")
	fixture.client.ingest_server_text(_command_result(request.request_id, "create_room", "ABC234", "player-a", "secret"), fixture.client.connection_generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"], 1), fixture.client.connection_generation)
	_check(snapshots.size() == 1 and snapshots[0].player_count == 1, "Unsolicited snapshot with null request ID must be accepted")
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada", "Ben"], 2, 2), fixture.client.connection_generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"], 1), fixture.client.connection_generation)
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada", "Ben"], 2, 2), fixture.client.connection_generation)
	_check(snapshots.size() == 2 and snapshots.back().player_count == 2, "Older and duplicate revisions must not roll the lobby back")
	var presence_snapshot: Dictionary = JSON.parse_string(_snapshot("ABC234", ["Ada", "Ben"], 2, 3))
	presence_snapshot.payload.connected = [true, false]
	fixture.client.ingest_server_text(JSON.stringify(presence_snapshot), fixture.client.connection_generation)
	_check(snapshots.size() == 3 and snapshots.back().connected == [true, false], "Opted-in lobby snapshots must show disconnected seats")
	var bad_presence: Dictionary = presence_snapshot.duplicate(true)
	bad_presence.payload.revision = 4
	bad_presence.payload.connected = [true, "false"]
	fixture.client.ingest_server_text(JSON.stringify(bad_presence), fixture.client.connection_generation)
	_check(snapshots.size() == 3, "Non-boolean presence must be rejected")
	fixture.client.ingest_server_text(_snapshot("ABC234", ["Ada"], 2), fixture.client.connection_generation)
	var invalid_type: Dictionary = JSON.parse_string(_snapshot("ABC234", ["Ada"], 1))
	invalid_type.payload.room_code = 123456
	fixture.client.ingest_server_text(JSON.stringify(invalid_type), fixture.client.connection_generation)
	var invalid_revision: Dictionary = JSON.parse_string(_snapshot("ABC234", ["Ada"], 1))
	invalid_revision.payload.revision = -1
	fixture.client.ingest_server_text(JSON.stringify(invalid_revision), fixture.client.connection_generation)
	fixture.client.ingest_server_text(_snapshot("XYZ789", ["Mallory"], 1), fixture.client.connection_generation)
	_check(snapshots.size() == 3, "Invalid and different-room snapshots must not alter the active lobby")
	_check(warnings.size() == 6, "Rejected snapshots should produce safe protocol warnings")
	fixture.client.ingest_server_text(JSON.stringify({"version": 2, "type": "server_shutdown", "request_id": null, "payload": {"reason": "service_restart"}}), fixture.client.connection_generation)
	_check(not fixture.client.is_connected_to_service() and fixture.client.session_id.is_empty(), "Valid shutdown must clear private identity")
	var join_fixture := _connected_client()
	join_fixture.client.join_room("ABC234", "Ben")
	var join_request: Dictionary = JSON.parse_string(join_fixture.transport.sent[0])
	join_fixture.client.ingest_server_text(_command_result(join_request.request_id, "join_room", "DEF234", "player-b", "secret-b"), join_fixture.client.connection_generation)
	_check(not join_fixture.client.is_connected_to_service() and join_fixture.client.active_room_code.is_empty(), "A correlated join result for another room must close the connection")
	var case_fixture := _connected_client()
	case_fixture.client.create_room("Ada")
	var case_request: Dictionary = JSON.parse_string(case_fixture.transport.sent[0])
	case_fixture.client.ingest_server_text(_command_result(case_request.request_id, "create_room", "abc234", "player-a", "secret-a"), case_fixture.client.connection_generation)
	_check(not case_fixture.client.is_connected_to_service(), "A non-canonical result code must not establish a room that rejects its snapshots")

func _test_resume_rotation_and_invalid_credential() -> void:
	var fixture := _connected_client()
	var public_results: Array[Dictionary] = []
	fixture.client.command_succeeded.connect(func(_command: String, payload: Dictionary) -> void: public_results.append(payload))
	fixture.client.create_room("Ada")
	var create_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(_command_result(create_request.request_id, "create_room", "ABC234", "player-a", "session-a"), fixture.client.connection_generation)
	fixture.transport.state = WebSocketPeer.STATE_CLOSED
	fixture.client.poll_transport()
	_check(fixture.client.has_recovery() and fixture.client.player_id.is_empty(), "Transport loss must retain only recovery state")
	fixture.client.connect_to_service("ws://127.0.0.1:3000/ws")
	fixture.transport.open()
	fixture.client.poll_transport()
	var resume_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(resume_request.type == "resume_room" and resume_request.payload.reconnect_token == "A".repeat(43), "Resume must send the private token only to the authority")
	_check(resume_request.payload.get("game") == true, "Resume must keep receiving heist state for a recovered seat")
	var rotated: Dictionary = JSON.parse_string(_command_result(resume_request.request_id, "resume_room", "ABC234", "player-a", "session-b"))
	rotated.payload.reconnect_token = "B".repeat(43)
	fixture.client.ingest_server_text(JSON.stringify(rotated), fixture.client.connection_generation)
	_check(fixture.client.reconnect_token == "B".repeat(43) and fixture.client.session_id == "session-b", "Resume must replace both private credentials")
	_check(public_results.back() == {"command": "resume_room", "room_code": "ABC234"}, "Rotated credentials must stay out of public signals")
	fixture.transport.state = WebSocketPeer.STATE_CLOSED
	fixture.client.poll_transport()
	fixture.client.connect_to_service("ws://127.0.0.1:3000/ws")
	fixture.transport.open()
	fixture.client.poll_transport()
	var failed_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(_error(failed_request.request_id, "invalid_reconnect"), fixture.client.connection_generation)
	_check(not fixture.client.has_recovery() and fixture.client.is_connected_to_service(), "Invalid recovery must clear the token and allow fresh entry")

func _test_match_contract_validation() -> void:
	var contract := _match_contract()
	if contract.is_empty():
		return
	for label in contract.valid_public:
		var message: Dictionary = contract.valid_public[label]
		_check(Protocol.validate_match_snapshot(message.payload), "Server match snapshot '%s' must pass client validation" % label)
	for label in contract.valid_private:
		var message: Dictionary = contract.valid_private[label]
		_check(Protocol.validate_match_private(message.payload), "Server private state '%s' must pass client validation" % label)
	var voting: Dictionary = contract.valid_public.social_voting.payload
	var finished: Dictionary = contract.valid_public.social_finished_crew_wins.payload
	var role_leak: Dictionary = voting.duplicate(true)
	role_leak.seats[0]["role"] = "Informant"
	_check(not Protocol.validate_match_snapshot(role_leak), "A public seat carrying a role must be rejected")
	var early_outcome: Dictionary = voting.duplicate(true)
	early_outcome.outcome = finished.outcome.duplicate(true)
	_check(not Protocol.validate_match_snapshot(early_outcome), "A recap before the match ends must be rejected")
	var missing_outcome: Dictionary = finished.duplicate(true)
	missing_outcome.outcome = null
	_check(not Protocol.validate_match_snapshot(missing_outcome), "A finished match must carry its recap")
	var bad_phase: Dictionary = voting.duplicate(true)
	bad_phase.phase = "heist_over"
	_check(not Protocol.validate_match_snapshot(bad_phase), "Unknown phases must be rejected")
	var bad_revision: Dictionary = voting.duplicate(true)
	bad_revision.revision = 0
	_check(not Protocol.validate_match_snapshot(bad_revision), "Match revisions start at one")
	var reordered: Dictionary = voting.duplicate(true)
	reordered.seats[1].seat = 3
	_check(not Protocol.validate_match_snapshot(reordered), "Seats must be listed in seat order")
	var extra_top: Dictionary = voting.duplicate(true)
	extra_top["informant_seat"] = 0
	_check(not Protocol.validate_match_snapshot(extra_top), "Unknown public fields must be rejected")
	var private_identity: Dictionary = contract.valid_private.crew.payload.duplicate(true)
	private_identity["player_id"] = "player-b"
	_check(not Protocol.validate_match_private(private_identity), "Private state must not accept identity fields")
	var bad_seat: Dictionary = contract.valid_private.crew.payload.duplicate(true)
	bad_seat.seat = 7
	_check(not Protocol.validate_match_private(bad_seat), "Private seat indexes are bounded by room capacity")
	var normalized: Dictionary = Protocol.normalized_match_snapshot(finished)
	_check(normalized.revision is int and normalized.meters.time is int and normalized.outcome.accusation.totals[0] is int, "Match numbers must normalize to integers for the UI")

func _test_match_messages_and_commands() -> void:
	var contract := _match_contract()
	if contract.is_empty():
		return
	var fixture := _connected_client()
	var generation: int = fixture.client.connection_generation
	var public_updates: Array[Dictionary] = []
	var private_updates: Array[Dictionary] = []
	var results: Array[String] = []
	var errors: Array[String] = []
	fixture.client.match_snapshot_received.connect(func(snapshot: Dictionary) -> void: public_updates.append(snapshot))
	fixture.client.match_private_received.connect(func(state: Dictionary) -> void: private_updates.append(state))
	fixture.client.command_succeeded.connect(func(command: String, _payload: Dictionary) -> void: results.append(command))
	fixture.client.request_failed.connect(func(code: String, _message: String) -> void: errors.append(code))
	fixture.client.ingest_server_text(JSON.stringify(contract.valid_public.social_role_reveal), generation)
	_check(public_updates.is_empty(), "Heist updates before joining a room must be ignored")
	_check(not fixture.client.start_match() and not fixture.client.ready_step("briefing", 1), "Heist commands require an active room")
	fixture.client.create_room("Ada")
	var create_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(_command_result(create_request.request_id, "create_room", "ABC234", "player-a", "session-a"), generation)

	_check(fixture.client.start_match(), "Start should send from inside a room")
	var start_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(start_request.type == "start_match" and start_request.payload.is_empty(), "Start must not let the client choose roles or seats")
	fixture.client.ingest_server_text(_match_result(start_request.request_id, "start_match"), generation)
	_check(results.back() == "start_match" and not fixture.client.has_pending_request(), "A start result must resolve the pending command")

	fixture.client.ingest_server_text(JSON.stringify(contract.valid_public.social_voting), generation)
	fixture.client.ingest_server_text(JSON.stringify(contract.valid_public.social_role_reveal), generation)
	fixture.client.ingest_server_text(JSON.stringify(contract.valid_public.social_voting), generation)
	_check(public_updates.size() == 1 and public_updates[0].phase == "voting", "Older and duplicate heist revisions must not roll the screen back")
	_check(public_updates[0].revision is int and public_updates[0].round is int, "Heist numbers reach the UI as integers")
	var other_room: Dictionary = contract.valid_public.social_resolution_sabotaged.duplicate(true)
	other_room.payload.room_code = "XYZ789"
	fixture.client.ingest_server_text(JSON.stringify(other_room), generation)
	var correlated: Dictionary = contract.valid_public.social_resolution_sabotaged.duplicate(true)
	correlated.request_id = "unsolicited"
	fixture.client.ingest_server_text(JSON.stringify(correlated), generation)
	_check(public_updates.size() == 1, "Heist updates for another room or with a request ID must be ignored")
	fixture.client.ingest_server_text(JSON.stringify(contract.valid_private.informant_voted), generation)
	fixture.client.ingest_server_text(JSON.stringify(contract.valid_private.informant), generation)
	_check(private_updates.size() == 1 and private_updates[0].vote == "ghost" and private_updates[0].seat is int, "Private state follows the same revision ordering")

	_check(fixture.client.cast_vote(1, "ghost", true), "Vote should send")
	var vote_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(vote_request.type == "cast_vote" and vote_request.payload.plan_id == "ghost" and int(vote_request.payload.round) == 1 and vote_request.payload.sabotage == true, "Vote must carry round, plan, and the sabotage flag")
	fixture.client.ingest_server_text(_error(vote_request.request_id, "already_acted"), generation)
	_check(errors.back() == "already_acted" and fixture.client.is_connected_to_service(), "Rejected heist actions surface an error without dropping the seat")
	_check(fixture.client.cast_vote(1, "ghost"), "A plain vote should send")
	var plain_vote: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(not plain_vote.payload.has("sabotage"), "A crew vote must not mention sabotage")
	fixture.client.ingest_server_text(_match_result(plain_vote.request_id, "cast_vote"), generation)
	_check(fixture.client.accuse(2), "Accusation should send")
	var accuse_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(accuse_request.type == "accuse" and int(accuse_request.payload.suspect_seat) == 2 and accuse_request.payload.size() == 1, "Accusation sends only a seat index")
	fixture.client.ingest_server_text(_match_result(accuse_request.request_id, "accuse"), generation)

	_check(not fixture.client.ready_step("voting", 1), "Only pacing steps accept readiness")
	_check(fixture.client.ready_step("resolution", 1), "Readiness should send for a pacing step")
	var ready_request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	_check(ready_request.payload.phase == "resolution" and int(ready_request.payload.round) == 1, "Readiness names the step it acknowledges")
	var enriched: Dictionary = JSON.parse_string(_match_result(ready_request.request_id, "ready"))
	enriched.payload["player_id"] = "player-b"
	fixture.client.ingest_server_text(JSON.stringify(enriched), generation)
	_check(not fixture.client.is_connected_to_service(), "A heist result carrying identity is invalid and closes the uncertain session")

func _match_contract() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/match_contract.json"))
	if not parsed is Dictionary:
		_check(false, "The shared match contract fixture must be readable")
		return {}
	return parsed

func _test_old_server_upgrade_error() -> void:
	var fixture := _connected_client()
	var errors: Array[String] = []
	fixture.client.request_failed.connect(func(code: String, _message: String) -> void: errors.append(code))
	_check(fixture.client.create_room("Ada"), "A version 2 client should send a create request")
	var request: Dictionary = JSON.parse_string(fixture.transport.sent.back())
	fixture.client.ingest_server_text(JSON.stringify({"version": 1, "type": "error", "request_id": request.request_id, "payload": {"code": "unsupported_version"}}), fixture.client.connection_generation)
	_check(errors == ["unsupported_version"] and not fixture.client.has_pending_request(), "An old service's upgrade error should be readable and release the request")

func _match_result(request_id: String, command: String) -> String:
	return JSON.stringify({"version": 2, "type": "command_result", "request_id": request_id, "payload": {"command": command, "room_code": "ABC234"}})

func _connected_client() -> Dictionary:
	var transport := FakeTransport.new()
	var client = ClientScript.new(transport)
	allocated_nodes.append(client)
	_check(client.connect_to_service("ws://127.0.0.1:3000/ws"), "Fixture connection should start")
	transport.open()
	client.poll_transport()
	return {"client": client, "transport": transport}

func _command_result(request_id: String, command: String, room_code: String, player_id: String, session_id: String) -> String:
	return JSON.stringify({
		"version": 2,
		"type": "command_result",
		"request_id": request_id,
		"payload": {"command": command, "room_code": room_code, "player_id": player_id, "session_id": session_id, "reconnect_token": "A".repeat(43)},
	})

func _error(request_id: String, code: String) -> String:
	return JSON.stringify({"version": 2, "type": "error", "request_id": request_id, "payload": {"code": code}})

func _snapshot(room_code: String, names: Array, count: int, revision: int = 1) -> String:
	return JSON.stringify({
		"version": 2,
		"type": "room_snapshot",
		"request_id": null,
		"payload": {"room_code": room_code, "player_names": names, "player_count": count, "max_players": 4, "revision": revision},
	})

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
