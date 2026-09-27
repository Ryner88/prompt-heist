extends SceneTree

const RoomRegistryTests = preload("res://tests/public_room_registry_test.gd")
const GameStateRegressionTests = preload("res://tests/game_state_regression_test.gd")

func _init() -> void:
	var suites = [RoomRegistryTests.new(), GameStateRegressionTests.new()]
	var failed := false
	for suite in suites:
		suite.run()
		failed = failed or not suite.failures.is_empty()
	quit(1 if failed else 0)
