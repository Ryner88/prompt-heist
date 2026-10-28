extends RefCounted

const GameState = preload("res://scripts/game_state.gd")
var failures: Array[String] = []

func run() -> void:
	_test_lobby_validation_and_start_boundary()
	_test_role_assignment_modes_and_phase_transitions()
	_test_voting_validation_and_deterministic_tie()
	_test_sabotage_authorization_and_single_use()
	_test_invalid_phase_and_incomplete_actions()
	_test_terminal_meter_thresholds()
	_test_three_round_cooperative_win_and_failure()
	_test_accusation_outcomes()
	_test_accusation_validation()
	_test_reset_restores_initial_state()
	_test_private_information_abilities()
	_test_protective_and_resource_abilities()
	if failures.is_empty():
		print("HeistGameState regression tests passed: 12 cases")
	else:
		for failure in failures:
			push_error(failure)

func _test_lobby_validation_and_start_boundary() -> void:
	var game = GameState.new()
	_check(not game.add_player("A").ok, "One-character names must be rejected")
	_check(not game.add_player("1234567890123456789").ok, "Names over 18 characters must be rejected")
	_check(game.add_player("  Ada  ").ok, "A valid trimmed name should be accepted")
	_check(game.players[0].name == "Ada", "Names should be trimmed")
	_check(not game.add_player("aDA").ok, "Duplicate names should be rejected without case sensitivity")
	_check(game.add_player("Ben").ok, "A second player should be accepted")
	_check(not game.can_start(), "Two players must not be enough to start")
	_check(game.add_player("Cy").ok and game.can_start(), "Exactly three players should be enough to start")
	_check(game.add_player("Dee").ok, "A fourth player should be accepted")
	_check(game.add_player("Eli").ok, "A fifth player should be accepted")
	_check(game.add_player("Flo").ok, "Exactly six players should be accepted")
	_check(not game.add_player("Gus").ok, "A seventh player must be rejected")

func _test_role_assignment_modes_and_phase_transitions() -> void:
	var cooperative = _started_game(3)
	_check(cooperative.informant_player_id == -1, "Three-player mode must not assign an Informant")
	_check(cooperative.phase == GameState.Phase.ROLE_REVEAL, "Starting must enter role reveal")
	cooperative.advance_to_briefing()
	_check(cooperative.phase == GameState.Phase.BRIEFING, "Role reveal must advance to briefing")
	cooperative.begin_planning()
	_check(cooperative.phase == GameState.Phase.PLANNING, "Briefing must advance to planning")
	cooperative.begin_voting()
	_check(cooperative.phase == GameState.Phase.VOTING, "Planning must advance to voting")

	var social = _started_game(4)
	_check(social.informant_player_id >= 1 and social.informant_player_id <= 4, "Four-player mode must assign exactly one Informant")
	var informants := 0
	for player in social.players:
		if player.role == "Informant":
			informants += 1
	_check(informants == 1, "Social mode must contain one Informant role")

func _test_voting_validation_and_deterministic_tie() -> void:
	var game = _voting_game(4)
	_check(not game.cast_vote(1, "missing").ok, "An unavailable plan must be rejected")
	_check(game.cast_vote(1, "ghost").ok, "A valid vote should be accepted")
	_check(not game.cast_vote(1, "spoof").ok, "A duplicate vote must be rejected")
	_check(game.cast_vote(2, "spoof").ok, "Second vote should be accepted")
	_check(game.cast_vote(3, "ghost").ok, "Third vote should be accepted")
	var last_vote: Dictionary = game.cast_vote(4, "spoof")
	_check(last_vote.ok and last_vote.complete, "Final vote should mark voting complete")
	var result: Dictionary = game.resolve_vote()
	_check(result.ok and result.was_tie, "A 2–2 vote should resolve as a tie")
	_check(result.plan.id == "ghost", "A tied vote must select the lower-risk plan")
	_check(game.phase == GameState.Phase.RESOLUTION, "Vote resolution must enter resolution phase")
	_check(game.advance_after_resolution(), "A nonterminal first round should advance")
	_check(game.current_round == 2 and game.phase == GameState.Phase.PLANNING, "Round advance must enter the next planning phase")

func _test_sabotage_authorization_and_single_use() -> void:
	var game = _voting_game(4)
	var informant_id: int = game.informant_player_id
	var crew_id := 1 if informant_id != 1 else 2
	_check(not game.arm_informant_sabotage(crew_id).ok, "Crew must not be allowed to sabotage")
	_check(game.arm_informant_sabotage(informant_id).ok, "The Informant should be allowed one sabotage")
	_check(not game.arm_informant_sabotage(informant_id).ok, "A second sabotage must be rejected")
	for player in game.players:
		game.cast_vote(player.id, "ghost")
	var before: int = game.suspicion
	var result: Dictionary = game.resolve_vote()
	_check(result.sabotage_applied, "Armed sabotage must be applied at resolution")
	_check(before == 1 and game.suspicion == 2, "Sabotage must add exactly two after the selected plan's one-point reduction")

func _test_invalid_phase_and_incomplete_actions() -> void:
	var lobby = GameState.new()
	_check(not lobby.start_match(RandomNumberGenerator.new()).ok, "A match below minimum players must not start")
	_check(not lobby.cast_vote(1, "ghost").ok, "Voting outside the voting phase must be rejected")
	_check(not lobby.arm_informant_sabotage(1).ok, "Sabotage outside voting must be rejected")
	_check(not lobby.resolve_vote().ok, "Resolution outside voting must be rejected")
	_check(not lobby.advance_after_resolution(), "Only the resolution phase may advance a round")

	var started = _started_game(3)
	_check(not started.add_player("Late Player").ok, "Players must not join after a match starts")
	started.advance_to_briefing()
	started.begin_planning()
	started.begin_voting()
	started.cast_vote(1, "ghost")
	_check(not started.resolve_vote().ok, "A partial vote must not resolve")

func _test_terminal_meter_thresholds() -> void:
	var time_game = _voting_game(3)
	time_game.time_remaining = 3
	_resolve_unanimous(time_game, "ghost")
	_check(time_game.mission_failed and time_game.failure_reason == "The crew ran out of time.", "Time at zero must fail immediately")

	var suspicion_game = _voting_game(3)
	suspicion_game.suspicion = 6
	_resolve_unanimous(suspicion_game, "blackout")
	_check(suspicion_game.mission_failed and suspicion_game.suspicion >= 7, "Suspicion at the threshold must fail immediately")

	var resource_game = _voting_game(3)
	resource_game.resources = 1
	_resolve_unanimous(resource_game, "ghost")
	_check(resource_game.mission_failed and resource_game.resources == 0, "Resources at zero must fail immediately")

func _test_three_round_cooperative_win_and_failure() -> void:
	var winning = _voting_game(3)
	_resolve_unanimous(winning, "ghost")
	winning.advance_after_resolution()
	winning.begin_voting()
	_resolve_unanimous(winning, "social")
	winning.advance_after_resolution()
	winning.begin_voting()
	_resolve_unanimous(winning, "rooftop")
	winning.advance_after_resolution()
	_check(winning.phase == GameState.Phase.FINISHED, "Cooperative game must finish after round three")
	_check(winning.winner == "Everyone" and winning.roles_revealed, "Two or more successful rounds must produce a cooperative win")
	_check(not winning.advance_after_resolution(), "An attempted extra round must not advance")

	var losing = _voting_game(3)
	losing.round_history.assign([{"success": false}, {"success": false}, {"success": true}])
	losing.current_round = 3
	losing.phase = GameState.Phase.RESOLUTION
	losing.advance_after_resolution()
	_check(losing.mission_failed and losing.winner == "Nobody", "Fewer than two successes must lose cooperative mode")

	var exact_threshold = _started_game(3)
	exact_threshold.round_history.assign([{"success": true}, {"success": false}, {"success": true}])
	exact_threshold.current_round = 3
	exact_threshold.phase = GameState.Phase.RESOLUTION
	exact_threshold.advance_after_resolution()
	_check(exact_threshold.winner == "Everyone", "Exactly two successful rounds must meet the win threshold")

func _test_accusation_outcomes() -> void:
	var caught = _accusation_game()
	var informant: int = caught.informant_player_id
	var voters: Array[Dictionary] = caught.get_accusation_voters()
	for voter in voters:
		_check(caught.cast_accusation_vote(voter.id, informant).ok, "Eligible crew accusation should be accepted")
	var caught_result: Dictionary = caught.resolve_accusation()
	_check(caught_result.correct and caught_result.winner == "Crew", "Correct accusation must award the Crew victory")

	var escaped = _accusation_game()
	var escaped_informant: int = escaped.informant_player_id
	var suspects: Array[int] = []
	for player in escaped.players:
		if player.id != escaped_informant:
			suspects.append(player.id)
	var escaped_voters: Array[Dictionary] = escaped.get_accusation_voters()
	_check(not escaped.cast_accusation_vote(escaped_informant, suspects[0]).ok, "Informant accusation votes must be rejected")
	for index in escaped_voters.size():
		var voter: Dictionary = escaped_voters[index]
		var suspect: int = suspects[(index + 1) % suspects.size()]
		if suspect == voter.id:
			suspect = suspects[(index + 2) % suspects.size()]
		escaped.cast_accusation_vote(voter.id, suspect)
	var escaped_result: Dictionary = escaped.resolve_accusation()
	_check(not escaped_result.correct and escaped_result.winner == "Informant", "An incorrect or tied accusation must award the Informant victory")

func _test_accusation_validation() -> void:
	var game = _accusation_game()
	var informant: int = game.informant_player_id
	var crew: Array[Dictionary] = game.get_accusation_voters()
	_check(not game.cast_accusation_vote(crew[0].id, crew[0].id).ok, "Players must not accuse themselves")
	_check(not game.cast_accusation_vote(999, informant).ok, "Unknown voters must be rejected")
	_check(not game.cast_accusation_vote(crew[0].id, 999).ok, "Unknown suspects must be rejected")
	_check(game.cast_accusation_vote(crew[0].id, informant).ok, "A valid accusation should be accepted")
	_check(not game.cast_accusation_vote(crew[0].id, crew[1].id).ok, "Duplicate accusations must be rejected")
	_check(not game.resolve_accusation().ok, "A partial accusation vote must not resolve")

func _test_reset_restores_initial_state() -> void:
	var game = _voting_game(4)
	game.informant_sabotage_used = true
	game.winner = "Informant"
	game.reset_game()
	_check(game.phase == GameState.Phase.LOBBY and game.players.is_empty(), "Reset must restore an empty lobby")
	_check(game.current_round == 1 and game.time_remaining == GameState.MAX_TIME, "Reset must restore round and time")
	_check(game.suspicion == 1 and game.resources == 7, "Reset must restore team meters")
	_check(not game.informant_sabotage_used and game.winner.is_empty(), "Reset must clear secret actions and outcome")

func _test_private_information_abilities() -> void:
	var mastermind = _voting_game(3)
	mastermind.players[0].role = "Mastermind"
	var revealed: Dictionary = mastermind.use_ability(1)
	_check(revealed.ok and revealed.details.contains("base success 68/100"), "Mastermind should learn current base scores")
	_check(not mastermind.use_ability(1).ok, "Mastermind ability must be single use")
	var agent = _voting_game(3)
	agent.players[0].role = "Inside Agent"
	var clue: Dictionary = agent.use_ability(1)
	_check(clue.ok and clue.details.contains("Blackout loses 8 score"), "Inside Agent should reveal this round's hidden complication")
	var hidden_result: Dictionary = _resolve_unanimous(agent, "blackout")
	_check(hidden_result.score == 87 and hidden_result.consequence.contains("Backup lighting"), "The hidden complication must affect resolution")
	var hacker = _voting_game(3)
	hacker.players[0].role = "Hacker"
	_check(not hacker.use_ability(1, "ghost").ok, "Hacker must target a digital plan")
	_check(hacker.use_ability(1, "spoof").ok and hacker.effective_risk(hacker.get_plan("spoof")) == 1, "Hacker should reduce targeted risk")
	_resolve_unanimous(hacker, "spoof")
	_check(hacker.suspicion == 0 and hacker.effective_risk(hacker.get_plan("spoof")) == 2, "Hacker risk reduction must end after this round")

func _test_protective_and_resource_abilities() -> void:
	var fixer = _voting_game(3)
	fixer.players[0].role = "Fixer"
	_check(fixer.use_ability(1).ok and fixer.resources == 8, "Fixer should restore one resource before the vote")
	_check(_resolve_unanimous(fixer, "ghost").score == 88, "Recovered resource must affect scoring")
	var specialist = _voting_game(3)
	specialist.players[0].role = "Security Specialist"
	_check(specialist.use_ability(1).ok, "Security Specialist should be usable during voting")
	_resolve_unanimous(specialist, "blackout")
	_check(specialist.suspicion == 1, "Security Specialist should block one suspicion gained")
	var driver = _voting_game(3)
	driver.players[0].role = "Driver"
	_check(not driver.use_ability(1).ok, "Driver ability must wait for the final vote")
	driver.current_round = 3
	driver.resources = 4
	driver.suspicion = 4
	driver.time_remaining = 5
	_check(driver.use_ability(1).ok, "Driver should protect the final escape")
	var result: Dictionary = _resolve_unanimous(driver, "motorcade")
	_check(not result.success and driver.resources == 1 and result.consequence.contains("Driver prevents"), "Driver should prevent the failure's extra resource and suspicion")

func _started_game(player_count: int):
	var game = GameState.new()
	for index in player_count:
		game.add_player("Player %d" % (index + 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var started: Dictionary = game.start_match(rng)
	_check(started.ok, "Fixture game should start")
	return game

func _voting_game(player_count: int):
	var game = _started_game(player_count)
	game.advance_to_briefing()
	game.begin_planning()
	game.begin_voting()
	return game

func _resolve_unanimous(game, plan_id: String) -> Dictionary:
	for player in game.players:
		game.cast_vote(player.id, plan_id)
	return game.resolve_vote()

func _accusation_game():
	var game = _started_game(4)
	game.phase = GameState.Phase.ACCUSATION
	return game

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
