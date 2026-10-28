class_name RoomProtocol
extends RefCounted

const VERSION := 1
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6
const MIN_NAME_LENGTH := 2
const MAX_NAME_LENGTH := 18

const ERROR_MESSAGES := {
	"invalid_name": "Names must contain 2–18 characters.",
	"unknown_room": "That room was not found. Check the code and try again.",
	"duplicate_name": "That name is already in the room. Choose another name.",
	"room_full": "That room is full. All four seats are occupied.",
	"connection_already_joined": "This connection has already joined a room. Return to entry and reconnect.",
	"rate_limited": "Too many requests. Wait a moment before trying again.",
	"unsupported_version": "This client is incompatible with the room service. Refresh or update the game.",
	"invalid_message": "The room service returned a protocol error. Please try again.",
	"invalid_reconnect": "That reserved seat has expired or was already recovered. Create or join a room again.",
	"not_in_room": "This connection is no longer in a room. Connect again to continue.",
	"reconnect_token_unavailable": "The room service could not issue a recovery credential. Please try again.",
	"match_in_progress": "A heist is already underway in that room.",
	"not_enough_players": "At least three players are needed to start the heist.",
	"players_disconnected": "Everyone must be connected before the heist can start.",
	"incompatible_client": "A player in this room is using an older version of the game. Ask them to refresh.",
	"no_active_match": "There is no heist in progress.",
	"not_in_match": "You are not part of this heist.",
	"stale_action": "The heist has already moved on. Your screen is catching up.",
	"already_acted": "You have already made that choice.",
	"invalid_plan": "That plan is not available this round.",
	"sabotage_unavailable": "Sabotage is not available.",
	"not_eligible": "Only the crew can vote in the accusation.",
	"invalid_suspect": "Choose another player to accuse.",
}

const MATCH_PHASES := ["role_reveal", "briefing", "planning", "voting", "resolution", "accusation", "finished", "abandoned", "closed"]
const PACING_PHASES := ["role_reveal", "briefing", "planning", "resolution"]
## Steps a player acknowledges with `ready`; "finished" asks to return to the waiting room.
const READY_PHASES := ["role_reveal", "briefing", "planning", "resolution", "finished"]
## Terminal notices that return players to the waiting room.
const ROOM_RETURN_PHASES := ["abandoned", "closed"]
const MATCH_SNAPSHOT_KEYS := ["room_code", "revision", "phase", "mode", "round", "total_rounds", "meters", "mission", "plans", "seats", "progress", "last_result", "outcome", "notice"]
const MATCH_PRIVATE_KEYS := ["room_code", "revision", "seat", "role", "ability", "sabotage_available", "vote", "accusation"]
const METER_KEYS := ["time", "max_time", "suspicion", "max_suspicion", "failure_suspicion", "resources", "max_resources"]
const PLAN_KEYS := ["id", "title", "description", "time_cost", "resource_cost", "risk"]
const SEAT_KEYS := ["seat", "name", "connected", "ready", "acted"]
const RESULT_KEYS := ["round", "plan_id", "plan_title", "tallies", "was_tie", "score", "success", "sabotage_applied", "consequence", "mission_failed", "failure_reason"]
const OUTCOME_KEYS := ["winner", "mission_failed", "failure_reason", "successful_rounds", "sabotage_used", "roles", "history", "accusation"]

static func normalize_name(value: String) -> String:
	# Godot does not expose general Unicode normalization. Normalize the NFKC
	# compatibility forms users most commonly enter in names; the server remains
	# authoritative and applies complete Unicode NFKC normalization.
	var trimmed := value.strip_edges()
	var normalized := ""
	for index in trimmed.length():
		var codepoint := trimmed.unicode_at(index)
		if codepoint >= 0xFF01 and codepoint <= 0xFF5E:
			normalized += String.chr(codepoint - 0xFEE0)
		elif codepoint == 0x3000:
			normalized += " "
		else:
			normalized += String.chr(codepoint)
	return normalized.strip_edges()

static func validate_name(value: String) -> String:
	var normalized := normalize_name(value)
	if normalized.length() < MIN_NAME_LENGTH or normalized.length() > MAX_NAME_LENGTH:
		return "invalid_name"
	return ""

static func normalize_room_code(value: String) -> String:
	return value.strip_edges().to_upper()

static func validate_room_code(value: String) -> String:
	var normalized := normalize_room_code(value)
	if normalized.length() != ROOM_CODE_LENGTH:
		return "invalid_room_code"
	for character in normalized:
		if not ROOM_CODE_ALPHABET.contains(character):
			return "invalid_room_code"
	return ""

static func validate_endpoint(endpoint: String) -> String:
	var value := endpoint.strip_edges()
	if value.is_empty():
		return "The room-service endpoint is not configured."
	var secure := value.to_lower().begins_with("wss://")
	if not secure and not value.to_lower().begins_with("ws://"):
		return "The room-service endpoint must use secure WebSockets."
	var remainder := value.substr(6 if secure else 5)
	var slash := remainder.find("/")
	if slash <= 0 or remainder.substr(slash) != "/ws":
		return "The room-service endpoint must end in /ws."
	var authority := remainder.substr(0, slash).to_lower()
	if authority.contains("@") or authority.contains("?") or authority.contains("#") or authority.contains(" "):
		return "The room-service endpoint has an invalid host."
	var host := authority
	var port := ""
	var has_port := false
	if authority.begins_with("["):
		var bracket := authority.find("]")
		if bracket < 0:
			return "The room-service endpoint has an invalid host."
		host = authority.substr(0, bracket + 1)
		var suffix := authority.substr(bracket + 1)
		if not suffix.is_empty():
			if not suffix.begins_with(":"):
				return "The room-service endpoint has an invalid host."
			has_port = true
			port = suffix.substr(1)
	elif authority.contains(":"):
		if authority.count(":") != 1:
			return "The room-service endpoint has an invalid host."
		host = authority.get_slice(":", 0)
		has_port = true
		port = authority.get_slice(":", 1)
	if host.is_empty() or has_port and (port.is_empty() or not port.is_valid_int() or int(port) < 1 or int(port) > 65535):
		return "The room-service endpoint has an invalid host."
	if not secure and not _is_loopback_host(host):
		return "Unencrypted WebSockets are allowed only for loopback development."
	return ""

static func error_message(code: String) -> String:
	return ERROR_MESSAGES.get(code, "The room service could not complete that request. Please try again.")

static func make_envelope(message_type: String, request_id: String, payload: Dictionary) -> Dictionary:
	return {
		"version": VERSION,
		"type": message_type,
		"request_id": request_id,
		"payload": payload.duplicate(true),
	}

static func is_safe_request_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	for character in value:
		var valid: bool = character.to_lower() >= "a" and character.to_lower() <= "z"
		valid = valid or (character >= "0" and character <= "9") or "._:-".contains(character)
		if not valid:
			return false
	return true

static func validate_snapshot(payload: Variant) -> bool:
	if not payload is Dictionary:
		return false
	var expected := ["room_code", "player_names", "player_count", "max_players", "revision"]
	if payload.keys().size() != expected.size():
		return false
	for key in expected:
		if not payload.has(key):
			return false
	if not payload.room_code is String or validate_room_code(payload.room_code) != "":
		return false
	if not payload.player_names is Array or not _is_integral_number(payload.player_count) or not _is_integral_number(payload.max_players) or not _is_integral_number(payload.revision):
		return false
	var player_count := int(payload.player_count)
	var max_players := int(payload.max_players)
	if player_count != payload.player_names.size() or max_players != 4:
		return false
	if player_count < 0 or player_count > max_players:
		return false
	if int(payload.revision) < 1:
		return false
	for player_name in payload.player_names:
		if not player_name is String or validate_name(player_name) != "":
			return false
	return true

static func validate_match_snapshot(payload: Variant) -> bool:
	if not _has_exact_keys(payload, MATCH_SNAPSHOT_KEYS):
		return false
	if not payload.room_code is String or validate_room_code(payload.room_code) != "":
		return false
	if not _is_count(payload.revision, 1, 1000000000) or not payload.phase is String or not MATCH_PHASES.has(payload.phase):
		return false
	if not payload.mode in ["cooperative", "social"] or not _is_count(payload.total_rounds, 1, 9) or not _is_count(payload.round, 1, int(payload.total_rounds)):
		return false
	if not _has_exact_keys(payload.meters, METER_KEYS):
		return false
	for key in METER_KEYS:
		if not _is_count(payload.meters[key], 0, 100):
			return false
	if not _has_exact_keys(payload.mission, ["title", "objective", "complication"]) or not _all_strings(payload.mission.values()):
		return false
	if not payload.plans is Array or payload.plans.is_empty():
		return false
	for plan in payload.plans:
		if not _has_exact_keys(plan, PLAN_KEYS) or not _all_strings([plan.id, plan.title, plan.description]):
			return false
		if not _is_count(plan.time_cost, 0, 100) or not _is_count(plan.resource_cost, 0, 100) or not _is_count(plan.risk, 0, 100):
			return false
	if not payload.seats is Array or payload.seats.size() < 3 or payload.seats.size() > 4:
		return false
	for index in payload.seats.size():
		var seat: Variant = payload.seats[index]
		if not _has_exact_keys(seat, SEAT_KEYS) or not _is_count(seat.seat, index, index):
			return false
		if not seat.name is String or validate_name(seat.name) != "":
			return false
		if not seat.connected is bool or not seat.ready is bool or not seat.acted is bool:
			return false
	if not _has_exact_keys(payload.progress, ["done", "needed"]) or not _is_count(payload.progress.needed, 0, 4) or not _is_count(payload.progress.done, 0, int(payload.progress.needed)):
		return false
	if payload.last_result != null and not _valid_result(payload.last_result):
		return false
	if payload.phase == "finished":
		if not _valid_outcome(payload.outcome, payload.seats.size()):
			return false
	elif payload.outcome != null:
		return false
	if ROOM_RETURN_PHASES.has(payload.phase):
		return payload.notice is String and not payload.notice.is_empty()
	return payload.notice == null

static func validate_match_private(payload: Variant) -> bool:
	if not _has_exact_keys(payload, MATCH_PRIVATE_KEYS):
		return false
	if not payload.room_code is String or validate_room_code(payload.room_code) != "":
		return false
	if not _is_count(payload.revision, 1, 1000000000) or not _is_count(payload.seat, 0, 3):
		return false
	if not _all_strings([payload.role, payload.ability]) or not payload.sabotage_available is bool:
		return false
	if payload.vote != null and not payload.vote is String:
		return false
	return payload.accusation == null or _is_count(payload.accusation, 0, 3)

## Converts JSON numbers (always floats after parsing) into ints for UI use.
static func normalized_match_snapshot(payload: Dictionary) -> Dictionary:
	var snapshot := payload.duplicate(true)
	for key in ["revision", "round", "total_rounds"]:
		snapshot[key] = int(snapshot[key])
	for key in METER_KEYS:
		snapshot.meters[key] = int(snapshot.meters[key])
	for plan in snapshot.plans:
		for key in ["time_cost", "resource_cost", "risk"]:
			plan[key] = int(plan[key])
	for seat in snapshot.seats:
		seat.seat = int(seat.seat)
	snapshot.progress.done = int(snapshot.progress.done)
	snapshot.progress.needed = int(snapshot.progress.needed)
	if snapshot.last_result != null:
		snapshot.last_result.round = int(snapshot.last_result.round)
		snapshot.last_result.score = int(snapshot.last_result.score)
		for plan_id in snapshot.last_result.tallies.keys():
			snapshot.last_result.tallies[plan_id] = int(snapshot.last_result.tallies[plan_id])
	if snapshot.outcome != null:
		snapshot.outcome.successful_rounds = int(snapshot.outcome.successful_rounds)
		for role in snapshot.outcome.roles:
			role.seat = int(role.seat)
		for entry in snapshot.outcome.history:
			entry.round = int(entry.round)
			entry.score = int(entry.score)
		if snapshot.outcome.accusation != null:
			var totals: Array = []
			for total in snapshot.outcome.accusation.totals:
				totals.append(int(total))
			snapshot.outcome.accusation.totals = totals
			if snapshot.outcome.accusation.accused_seat != null:
				snapshot.outcome.accusation.accused_seat = int(snapshot.outcome.accusation.accused_seat)
	return snapshot

static func normalized_match_private(payload: Dictionary) -> Dictionary:
	var state := payload.duplicate(true)
	state.revision = int(state.revision)
	state.seat = int(state.seat)
	if state.accusation != null:
		state.accusation = int(state.accusation)
	return state

static func _valid_result(result: Variant) -> bool:
	if not _has_exact_keys(result, RESULT_KEYS):
		return false
	if not _all_strings([result.plan_id, result.plan_title, result.consequence, result.failure_reason]):
		return false
	if not _is_count(result.round, 1, 9) or not _is_count(result.score, 0, 100):
		return false
	if not result.was_tie is bool or not result.success is bool or not result.sabotage_applied is bool or not result.mission_failed is bool:
		return false
	if not result.tallies is Dictionary:
		return false
	for count in result.tallies.values():
		if not _is_count(count, 0, 4):
			return false
	return true

static func _valid_outcome(outcome: Variant, seat_count: int) -> bool:
	if not _has_exact_keys(outcome, OUTCOME_KEYS):
		return false
	if not outcome.winner in ["Crew", "Informant", "Everyone", "Nobody"] or not outcome.failure_reason is String:
		return false
	if not outcome.mission_failed is bool or not outcome.sabotage_used is bool or not _is_count(outcome.successful_rounds, 0, 9):
		return false
	if not outcome.roles is Array or outcome.roles.size() != seat_count:
		return false
	for index in seat_count:
		var role: Variant = outcome.roles[index]
		if not _has_exact_keys(role, ["seat", "role"]) or not _is_count(role.seat, index, index) or not role.role is String:
			return false
	if not outcome.history is Array:
		return false
	for entry in outcome.history:
		if not _has_exact_keys(entry, ["round", "plan_title", "success", "score"]) or not entry.plan_title is String or not entry.success is bool:
			return false
		if not _is_count(entry.round, 1, 9) or not _is_count(entry.score, 0, 100):
			return false
	if outcome.accusation == null:
		return true
	var accusation: Variant = outcome.accusation
	if not _has_exact_keys(accusation, ["totals", "tied", "accused_seat"]) or not accusation.tied is bool:
		return false
	if not accusation.totals is Array or accusation.totals.size() != seat_count:
		return false
	for total in accusation.totals:
		if not _is_count(total, 0, 4):
			return false
	return accusation.accused_seat == null or _is_count(accusation.accused_seat, 0, seat_count - 1)

static func _has_exact_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.keys().size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func _all_strings(values: Array) -> bool:
	for value in values:
		if not value is String:
			return false
	return true

static func _is_count(value: Variant, minimum: int, maximum: int) -> bool:
	return _is_integral_number(value) and int(value) >= minimum and int(value) <= maximum

static func normalized_snapshot(payload: Dictionary) -> Dictionary:
	var snapshot := payload.duplicate(true)
	snapshot.player_count = int(snapshot.player_count)
	snapshot.max_players = int(snapshot.max_players)
	snapshot.revision = int(snapshot.revision)
	return snapshot

static func _is_loopback_host(host: String) -> bool:
	if host == "localhost" or host == "[::1]":
		return true
	var octets := host.split(".")
	if octets.size() != 4 or octets[0] != "127":
		return false
	for octet in octets:
		if octet.is_empty() or not octet.is_valid_int() or int(octet) < 0 or int(octet) > 255:
			return false
	return true

static func _is_integral_number(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, round(value)))
