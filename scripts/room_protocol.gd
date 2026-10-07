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
}

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
	var expected := ["room_code", "player_names", "player_count", "max_players"]
	if payload.keys().size() != expected.size():
		return false
	for key in expected:
		if not payload.has(key):
			return false
	if not payload.room_code is String or validate_room_code(payload.room_code) != "":
		return false
	if not payload.player_names is Array or not _is_integral_number(payload.player_count) or not _is_integral_number(payload.max_players):
		return false
	var player_count := int(payload.player_count)
	var max_players := int(payload.max_players)
	if player_count != payload.player_names.size() or max_players != 4:
		return false
	if player_count < 0 or player_count > max_players:
		return false
	for player_name in payload.player_names:
		if not player_name is String or validate_name(player_name) != "":
			return false
	return true

static func normalized_snapshot(payload: Dictionary) -> Dictionary:
	var snapshot := payload.duplicate(true)
	snapshot.player_count = int(snapshot.player_count)
	snapshot.max_players = int(snapshot.max_players)
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
