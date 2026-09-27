extends SceneTree

const RoomRegistryTests = preload("res://tests/public_room_registry_test.gd")

func _init() -> void:
	var tests = RoomRegistryTests.new()
	tests.run()
	quit(1 if not tests.failures.is_empty() else 0)
