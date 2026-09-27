extends RefCounted

const RoomRegistry = preload("res://scripts/public_room_registry.gd")
var code_sources: Array[RefCounted] = []
var failures: Array[String] = []

class SequenceCodeSource:
	extends RefCounted
	var codes: Array[String]
	var next_index := 0

	func _init(values: Array[String]) -> void:
		codes = values

	func next_code() -> String:
		if next_index >= codes.size():
			return codes.back()
		var value := codes[next_index]
		next_index += 1
		return value

func run() -> void:
	_test_create_and_join_public_snapshot()
	_test_duplicate_names_and_room_capacity()
	_test_collision_retry_and_exhaustion()
	_test_invalid_codes_and_names()
	if failures.is_empty():
		print("PublicRoomRegistry tests passed: 4 cases")
	else:
		for failure in failures:
			push_error(failure)

func _test_create_and_join_public_snapshot() -> void:
	var registry = _registry(["ABCD23"])
	var created: Dictionary = registry.create_room(" Ada ")
	_check(created.get("ok", false), "Room creation should succeed")
	_check(created.get("room_code", "") == "ABCD23", "Injected room code should be used")
	_check(created.get("room", {}).get("player_names", []) == ["Ada"], "Created room should contain the normalized host name")
	_check(created.get("room", {}).get("player_count", 0) == 1, "Created room count should be one")
	_check(created.get("room", {}).get("max_players", 0) == 4, "Public room capacity should be four")
	_check(not created.get("room", {}).has("role"), "Public snapshot must not expose roles")
	_check(not created.get("room", {}).has("players"), "Public snapshot must not expose internal player records")
	var joined: Dictionary = registry.join_room(" abcd23 ", "Ben")
	_check(joined.get("ok", false), "Joining an existing room should succeed")
	_check(joined.get("room", {}).get("player_names", []) == ["Ada", "Ben"], "Join snapshot should contain both names")
	_check(joined.get("room", {}).get("player_count", 0) == 2, "Join snapshot should report two players")
	_check(registry.room_count() == 1, "Joining should not create a second room")

	var secure_registry = RoomRegistry.new()
	var secure_room: Dictionary = secure_registry.create_room("Nia")
	var secure_code: String = secure_room.get("room_code", "")
	_check(secure_room.get("ok", false), "Default CSPRNG code source should create a room")
	_check(secure_code.length() == RoomRegistry.ROOM_CODE_LENGTH, "Generated room code should have six characters")
	for character in secure_code:
		_check(RoomRegistry.ROOM_CODE_ALPHABET.contains(character), "Generated code should use only the unambiguous alphabet")

func _test_duplicate_names_and_room_capacity() -> void:
	var registry = _registry(["RAAM23"])
	var created: Dictionary = registry.create_room("Ada")
	_check(created.get("ok", false), "Room for duplicate-name test should be created")
	_check(registry.join_room("RAAM23", "Ben").get("ok", false), "Second player should join")
	var duplicate: Dictionary = registry.join_room("RAAM23", "aDA")
	_check(not duplicate.get("ok", true) and duplicate.get("error", "") == "duplicate_name", "Names should be unique without case sensitivity")
	_check(registry.join_room("RAAM23", "Cy").get("ok", false), "Third player should join")
	_check(registry.join_room("RAAM23", "Dee").get("ok", false), "Fourth player should join")
	var full: Dictionary = registry.join_room("RAAM23", "Eli")
	_check(not full.get("ok", true) and full.get("error", "") == "room_full", "Fifth player should be rejected")
	_check(registry.get_public_room("RAAM23").get("player_names", []) == ["Ada", "Ben", "Cy", "Dee"], "Full room should retain its four original players")

func _test_collision_retry_and_exhaustion() -> void:
	var retry_registry = _registry(["ABC234", "ABC234", "XYZ789"])
	_check(retry_registry.create_room("Ada").get("room_code", "") == "ABC234", "First code should be allocated")
	var second: Dictionary = retry_registry.create_room("Ben")
	_check(second.get("ok", false) and second.get("room_code", "") == "XYZ789", "A code collision should retry and allocate a fresh code")

	var exhausted_registry = _registry(["ABC234"])
	_check(exhausted_registry.create_room("Ada").get("ok", false), "Initial room should be created")
	var exhausted: Dictionary = exhausted_registry.create_room("Ben")
	_check(not exhausted.get("ok", true) and exhausted.get("error", "") == "room_code_unavailable", "Repeated collisions should fail safely")
	_check(exhausted_registry.room_count() == 1, "Failed room creation must not modify the room directory")

func _test_invalid_codes_and_names() -> void:
	var registry = _registry(["ABC234"])
	var too_short: Dictionary = registry.create_room("A")
	_check(not too_short.get("ok", true) and too_short.get("error", "") == "invalid_player_name", "Short names should be rejected")
	var too_long: Dictionary = registry.create_room("1234567890123456789")
	_check(not too_long.get("ok", true) and too_long.get("error", "") == "invalid_player_name", "Long names should be rejected")
	var invalid_code: Dictionary = registry.join_room("bad!", "Ben")
	_check(not invalid_code.get("ok", true) and invalid_code.get("error", "") == "invalid_room_code", "Malformed room codes should be rejected")
	var missing_code: Dictionary = registry.join_room("ABC234", "Ben")
	_check(not missing_code.get("ok", true) and missing_code.get("error", "") == "invalid_room_code", "Unknown room codes should be rejected")

func _registry(codes: Array[String]) -> RefCounted:
	var source := SequenceCodeSource.new(codes)
	code_sources.append(source)
	return RoomRegistry.new(Callable(source, "next_code"))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
