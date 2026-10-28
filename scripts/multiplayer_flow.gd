class_name MultiplayerFlow
extends Node

signal state_changed(state: int)
signal feedback_changed(message: String)
signal lobby_changed(snapshot: Dictionary)
signal match_changed()

const Protocol = preload("res://scripts/room_protocol.gd")

enum State { DISCONNECTED, CONNECTING, ENTRY, SUBMITTING, LOBBY, RECOVERING, LEAVING, MATCH }

var state: State = State.DISCONNECTED
var feedback := ""
var lobby_snapshot: Dictionary = {}
## Latest authoritative public heist view and this player's private seat view.
var match_snapshot: Dictionary = {}
var match_private: Dictionary = {}
var endpoint := ""
var client: Node

func _init(network_client: Node = null) -> void:
	client = network_client

func _ready() -> void:
	if client != null:
		bind_client(client)

func bind_client(network_client: Node) -> void:
	client = network_client
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.command_succeeded.connect(_on_command_succeeded)
	client.room_snapshot_received.connect(_on_snapshot)
	client.request_failed.connect(_on_request_failed)
	client.shutdown_announced.connect(_on_shutdown)
	client.protocol_warning.connect(_on_protocol_warning)
	client.recovery_started.connect(_on_recovery_started)
	client.left_room.connect(_on_left_room)
	client.match_snapshot_received.connect(_on_match_snapshot)
	client.match_private_received.connect(_on_match_private)

func connect_service(service_endpoint: String) -> bool:
	if state != State.DISCONNECTED:
		return false
	endpoint = service_endpoint.strip_edges()
	_set_feedback("")
	_set_state(State.CONNECTING)
	if not client.connect_to_service(endpoint):
		_set_state(State.DISCONNECTED)
		return false
	return true

func submit_create(display_name: String) -> bool:
	if state != State.ENTRY or not can_create(display_name):
		return false
	_set_feedback("")
	_set_state(State.SUBMITTING)
	if not client.create_room(display_name):
		_set_state(State.ENTRY)
		return false
	return true

func submit_join(display_name: String, room_code: String) -> bool:
	if state != State.ENTRY or not can_join(display_name, room_code):
		return false
	_set_feedback("")
	_set_state(State.SUBMITTING)
	if not client.join_room(room_code, display_name):
		_set_state(State.ENTRY)
		return false
	return true

func can_create(display_name: String) -> bool:
	return state == State.ENTRY and Protocol.validate_name(display_name) == "" and not client.has_pending_request()

func can_join(display_name: String, room_code: String) -> bool:
	return can_create(display_name) and Protocol.validate_room_code(room_code) == ""

func leave_lobby() -> void:
	if state != State.LOBBY and state != State.MATCH:
		return
	var previous := state
	_set_state(State.LEAVING)
	if not client.leave_room():
		_set_state(previous)
		_set_feedback("Could not send the leave request. Please try again.")

func can_start_match() -> bool:
	return state == State.LOBBY and not client.has_pending_request() \
		and int(lobby_snapshot.get("player_count", 0)) >= 3

func start_match() -> bool:
	if not can_start_match():
		return false
	_set_feedback("")
	return client.start_match()

## True while this player still owes the current step an action.
func can_act() -> bool:
	return state == State.MATCH and not match_snapshot.is_empty() and not client.has_pending_request()

func ready_current_step() -> bool:
	if not can_act() or not Protocol.PACING_PHASES.has(match_snapshot.phase) or is_ready():
		return false
	_set_feedback("")
	return client.ready_step(match_snapshot.phase, match_snapshot.round)

func vote(plan_id: String, sabotage: bool = false) -> bool:
	if not can_act() or match_snapshot.phase != "voting" or has_voted():
		return false
	if sabotage and not bool(match_private.get("sabotage_available", false)):
		return false
	_set_feedback("")
	return client.cast_vote(match_snapshot.round, plan_id, sabotage)

func accuse(suspect_seat: int) -> bool:
	if not can_act() or match_snapshot.phase != "accusation" or is_informant() or has_accused():
		return false
	if suspect_seat == my_seat():
		return false
	_set_feedback("")
	return client.accuse(suspect_seat)

func my_seat() -> int:
	return int(match_private.get("seat", -1))

func is_informant() -> bool:
	return match_private.get("role", "") == "Informant"

func is_ready() -> bool:
	var seat := my_seat()
	if seat < 0 or match_snapshot.is_empty() or seat >= match_snapshot.seats.size():
		return false
	return bool(match_snapshot.seats[seat].ready)

func has_voted() -> bool:
	return match_private.get("vote") != null

func has_accused() -> bool:
	return match_private.get("accusation") != null

func _on_connected(_generation: int) -> void:
	if state == State.CONNECTING:
		_set_state(State.ENTRY)

func _on_recovery_started() -> void:
	if state == State.CONNECTING:
		_set_state(State.RECOVERING)

func _on_left_room() -> void:
	lobby_snapshot.clear()
	_clear_match()
	_set_feedback("You left the room. Connect again to create or join another room.")
	_set_state(State.DISCONNECTED)

func _on_disconnected(message: String) -> void:
	lobby_snapshot.clear()
	_clear_match()
	_set_feedback(message)
	_set_state(State.DISCONNECTED)

func _on_command_succeeded(_command: String, _payload: Dictionary) -> void:
	if state in [State.SUBMITTING, State.RECOVERING]:
		_set_state(State.LOBBY)

func _on_snapshot(snapshot: Dictionary) -> void:
	if state != State.LOBBY and state != State.MATCH:
		return
	lobby_snapshot = snapshot.duplicate(true)
	lobby_changed.emit(lobby_snapshot.duplicate(true))

func _on_match_snapshot(snapshot: Dictionary) -> void:
	if state != State.LOBBY and state != State.MATCH:
		return
	if snapshot.phase == "abandoned":
		var was_playing := state == State.MATCH
		_clear_match()
		if was_playing:
			_set_feedback(snapshot.notice)
			_set_state(State.LOBBY)
		return
	match_snapshot = snapshot.duplicate(true)
	if state == State.LOBBY:
		_set_state(State.MATCH)
	match_changed.emit()

func _on_match_private(private_state: Dictionary) -> void:
	if state != State.LOBBY and state != State.MATCH:
		return
	match_private = private_state.duplicate(true)
	if state == State.MATCH:
		match_changed.emit()

func _clear_match() -> void:
	match_snapshot.clear()
	match_private.clear()

func _on_request_failed(_code: String, message: String) -> void:
	_set_feedback(message)
	if state in [State.SUBMITTING, State.RECOVERING]:
		_set_state(State.ENTRY)

func _on_shutdown(message: String) -> void:
	lobby_snapshot.clear()
	_clear_match()
	_set_feedback(message)
	_set_state(State.DISCONNECTED)

func _on_protocol_warning(message: String) -> void:
	_set_feedback(message)

func _set_state(value: State) -> void:
	state = value
	state_changed.emit(state)

func _set_feedback(value: String) -> void:
	feedback = value
	feedback_changed.emit(feedback)
