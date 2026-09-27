class_name PublicRoomRegistry
extends RefCounted

## Process-local room directory for the future authoritative room service.
## This class does not provide network transport or durable storage.

const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6
const MAX_PLAYERS_PER_ROOM := 4
const MAX_CODE_GENERATION_ATTEMPTS := 16
const MIN_NAME_LENGTH := 2
const MAX_NAME_LENGTH := 18

var _rooms: Dictionary = {}
var _next_player_id := 1
var _code_generator: Callable
var _crypto := Crypto.new()

func _init(code_generator: Callable = Callable()) -> void:
	_code_generator = code_generator if code_generator.is_valid() else Callable(self, "_generate_room_code")

func create_room(display_name: String) -> Dictionary:
	var clean_name := _normalize_name(display_name)
	var name_error := _validate_name(clean_name)
	if not name_error.is_empty():
		return {"ok": false, "error": name_error}

	var room_code := ""
	for _attempt in MAX_CODE_GENERATION_ATTEMPTS:
		var candidate := String(_code_generator.call()).strip_edges().to_upper()
		if _is_valid_room_code(candidate) and not _rooms.has(candidate):
			room_code = candidate
			break
	if room_code.is_empty():
		return {"ok": false, "error": "room_code_unavailable"}

	var player := _make_player(clean_name)
	_rooms[room_code] = {"players": [player]}
	return {"ok": true, "room_code": room_code, "player_id": player.id, "room": get_public_room(room_code)}

func join_room(room_code: String, display_name: String) -> Dictionary:
	var normalized_code := room_code.strip_edges().to_upper()
	if not _is_valid_room_code(normalized_code) or not _rooms.has(normalized_code):
		return {"ok": false, "error": "invalid_room_code"}

	var clean_name := _normalize_name(display_name)
	var name_error := _validate_name(clean_name)
	if not name_error.is_empty():
		return {"ok": false, "error": name_error}

	var room: Dictionary = _rooms[normalized_code]
	var room_players: Array = room.players
	if room_players.size() >= MAX_PLAYERS_PER_ROOM:
		return {"ok": false, "error": "room_full"}
	for player in room_players:
		if player.name.to_lower() == clean_name.to_lower():
			return {"ok": false, "error": "duplicate_name"}

	var player := _make_player(clean_name)
	room_players.append(player)
	room.players = room_players
	_rooms[normalized_code] = room
	return {"ok": true, "room_code": normalized_code, "player_id": player.id, "room": get_public_room(normalized_code)}

func get_public_room(room_code: String) -> Dictionary:
	var normalized_code := room_code.strip_edges().to_upper()
	if not _rooms.has(normalized_code):
		return {}
	var room: Dictionary = _rooms[normalized_code]
	var names: Array[String] = []
	for player in room.players:
		names.append(player.name)
	return {
		"room_code": normalized_code,
		"player_names": names,
		"player_count": names.size(),
		"max_players": MAX_PLAYERS_PER_ROOM,
	}

func room_count() -> int:
	return _rooms.size()

func _make_player(display_name: String) -> Dictionary:
	var player := {"id": _next_player_id, "name": display_name}
	_next_player_id += 1
	return player

func _normalize_name(display_name: String) -> String:
	return display_name.strip_edges()

func _validate_name(display_name: String) -> String:
	if display_name.length() < MIN_NAME_LENGTH or display_name.length() > MAX_NAME_LENGTH:
		return "invalid_player_name"
	return ""

func _is_valid_room_code(room_code: String) -> bool:
	if room_code.length() != ROOM_CODE_LENGTH:
		return false
	for character in room_code:
		if not ROOM_CODE_ALPHABET.contains(character):
			return false
	return true

func _generate_room_code() -> String:
	var random_bytes := _crypto.generate_random_bytes(ROOM_CODE_LENGTH)
	if random_bytes.size() != ROOM_CODE_LENGTH:
		return ""
	var code := ""
	for random_byte in random_bytes:
		# The alphabet contains 32 characters, so byte modulo 32 is unbiased.
		code += ROOM_CODE_ALPHABET[random_byte % ROOM_CODE_ALPHABET.length()]
	return code
