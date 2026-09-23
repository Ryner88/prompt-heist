class_name HeistGameState
extends RefCounted

enum Phase {
	LOBBY,
	ROLE_REVEAL,
	BRIEFING,
	PLANNING,
	VOTING,
	RESOLUTION,
	ACCUSATION,
	FINISHED,
}

const MIN_PLAYERS := 3
const MAX_PLAYERS := 6
const TOTAL_ROUNDS := 3
const MAX_TIME := 12
const MAX_SUSPICION := 10
const MAX_RESOURCES := 8

var phase: Phase = Phase.LOBBY
var players: Array[Dictionary] = []
var informant_player_id := -1
var current_round := 1
var time_remaining := 12
var suspicion := 1
var resources := 7
var votes: Dictionary = {}
var round_history: Array[Dictionary] = []
var informant_sabotage_used := false
var informant_sabotage_pending := false
var mission_failed := false
var failure_reason := ""
var accusation_votes: Dictionary = {}
var accusation_totals: Dictionary = {}
var accused_player_id := -1
var accusation_tied := false
var winner := ""
var roles_revealed := false
var mission := {
	"title": "The Neon Vault",
	"objective": "Recover a stolen prototype from a private technology expo.",
	"complication": "Security changes its patrol pattern every sixty seconds.",
}

var round_plans: Array[Array] = [
	[
		{"id": "ghost", "title": "Ghost the Service Hall", "description": "Slip through staff corridors while the expo changes shifts.", "time_cost": 3, "resource_cost": 1, "base_success": 68, "risk": 1},
		{"id": "spoof", "title": "Spoof a Vendor Badge", "description": "Clone credentials and walk through the front checkpoint.", "time_cost": 2, "resource_cost": 2, "base_success": 72, "risk": 2},
		{"id": "blackout", "title": "Stage a Blackout", "description": "Cut local power and move under emergency lighting.", "time_cost": 1, "resource_cost": 3, "base_success": 78, "risk": 3},
	],
	[
		{"id": "drone", "title": "Hijack the Camera Drone", "description": "Loop its feed and use it to scout the prototype floor.", "time_cost": 2, "resource_cost": 2, "base_success": 73, "risk": 2},
		{"id": "decoy", "title": "Trigger a Decoy Alarm", "description": "Pull security toward the loading bay before crossing the atrium.", "time_cost": 1, "resource_cost": 3, "base_success": 76, "risk": 3},
		{"id": "social", "title": "Work the VIP Crowd", "description": "Blend in, trade favors, and learn the vault access phrase.", "time_cost": 3, "resource_cost": 1, "base_success": 70, "risk": 1},
	],
	[
		{"id": "freight", "title": "Escape via Freight Lift", "description": "Move the prototype inside a sealed equipment case.", "time_cost": 2, "resource_cost": 2, "base_success": 74, "risk": 2},
		{"id": "rooftop", "title": "Take the Rooftop Route", "description": "Climb above the patrol grid and cross to the parking tower.", "time_cost": 3, "resource_cost": 1, "base_success": 69, "risk": 1},
		{"id": "motorcade", "title": "Bluff the Motorcade", "description": "Spend the last favors on an official-looking extraction.", "time_cost": 1, "resource_cost": 3, "base_success": 79, "risk": 3},
	],
]

func reset_game() -> void:
	phase = Phase.LOBBY
	players.clear()
	informant_player_id = -1
	current_round = 1
	time_remaining = MAX_TIME
	suspicion = 1
	resources = 7
	votes.clear()
	round_history.clear()
	informant_sabotage_used = false
	informant_sabotage_pending = false
	mission_failed = false
	failure_reason = ""
	accusation_votes.clear()
	accusation_totals.clear()
	accused_player_id = -1
	accusation_tied = false
	winner = ""
	roles_revealed = false

func add_player(display_name: String) -> Dictionary:
	var clean_name := display_name.strip_edges()
	if phase != Phase.LOBBY:
		return {"ok": false, "error": "The match has already started."}
	if players.size() >= MAX_PLAYERS:
		return {"ok": false, "error": "The lobby is full."}
	if clean_name.length() < 2 or clean_name.length() > 18:
		return {"ok": false, "error": "Names must contain 2–18 characters."}
	for player in players:
		if player.name.to_lower() == clean_name.to_lower():
			return {"ok": false, "error": "That name is already in the lobby."}

	var player := {
		"id": players.size() + 1,
		"name": clean_name,
		"role": "Crew",
		"ability": "Contribute a plan and vote on the team's next move.",
	}
	players.append(player)
	return {"ok": true, "player": player}

func can_start() -> bool:
	return phase == Phase.LOBBY and players.size() >= MIN_PLAYERS

func start_match(rng: RandomNumberGenerator) -> Dictionary:
	if not can_start():
		return {"ok": false, "error": "At least three players are required."}

	var role_templates := [
		{"role": "Mastermind", "ability": "Once per match, reveal the risk level of every proposed plan."},
		{"role": "Hacker", "ability": "Once per match, reduce digital-security risk by one level."},
		{"role": "Driver", "ability": "Once per match, cancel a failed escape consequence."},
		{"role": "Inside Agent", "ability": "Once per match, reveal one hidden mission complication."},
		{"role": "Security Specialist", "ability": "Once per match, block one point of suspicion."},
		{"role": "Fixer", "ability": "Once per match, recover one spent team resource."},
	]
	role_templates.shuffle()
	for index in players.size():
		players[index].role = role_templates[index].role
		players[index].ability = role_templates[index].ability

	# Four or more players creates the social-deduction version of the match.
	if players.size() >= 4:
		var informant_index := rng.randi_range(0, players.size() - 1)
		informant_player_id = players[informant_index].id
		players[informant_index].role = "Informant"
		players[informant_index].ability = "Secretly increase suspicion while appearing to help the crew."

	phase = Phase.ROLE_REVEAL
	return {"ok": true}

func advance_to_briefing() -> void:
	if phase == Phase.ROLE_REVEAL:
		phase = Phase.BRIEFING

func begin_planning() -> void:
	if phase == Phase.BRIEFING or phase == Phase.RESOLUTION:
		phase = Phase.PLANNING

func get_current_plans() -> Array:
	return round_plans[current_round - 1]

func begin_voting() -> void:
	if phase == Phase.PLANNING:
		votes.clear()
		phase = Phase.VOTING

func cast_vote(player_id: int, plan_id: String) -> Dictionary:
	if phase != Phase.VOTING:
		return {"ok": false, "error": "Voting is not active."}
	if votes.has(player_id):
		return {"ok": false, "error": "That player has already voted."}
	if get_plan(plan_id).is_empty():
		return {"ok": false, "error": "That plan is not available."}
	votes[player_id] = plan_id
	return {"ok": true, "complete": votes.size() == players.size()}

func arm_informant_sabotage(player_id: int) -> Dictionary:
	if phase != Phase.VOTING:
		return {"ok": false, "error": "Sabotage is only available during private planning."}
	if not is_informant(player_id):
		return {"ok": false, "error": "Only the Informant can sabotage the mission."}
	if informant_sabotage_used:
		return {"ok": false, "error": "Sabotage has already been used this match."}
	informant_sabotage_used = true
	informant_sabotage_pending = true
	return {"ok": true}

func resolve_vote() -> Dictionary:
	if phase != Phase.VOTING or votes.size() != players.size():
		return {"ok": false, "error": "Every player must vote before resolution."}

	var tallies: Dictionary = {}
	for plan in get_current_plans():
		tallies[plan.id] = 0
	for plan_id in votes.values():
		tallies[plan_id] += 1

	var highest_votes := 0
	var leaders: Array[String] = []
	for plan in get_current_plans():
		var count: int = tallies[plan.id]
		if count > highest_votes:
			highest_votes = count
			leaders.assign([plan.id])
		elif count == highest_votes:
			leaders.append(plan.id)

	# Ties are deterministic: the lowest-risk tied plan wins, then card order.
	var selected_id: String = leaders[0]
	for plan in get_current_plans():
		if plan.id in leaders and plan.risk < get_plan(selected_id).risk:
			selected_id = plan.id

	var selected_plan := get_plan(selected_id)
	var score: int = selected_plan.base_success + resources * 3 - suspicion * 4
	if resources < selected_plan.resource_cost:
		score -= (selected_plan.resource_cost - resources) * 15
	if time_remaining < selected_plan.time_cost:
		score -= (selected_plan.time_cost - time_remaining) * 20
	score = clampi(score, 5, 95)
	var succeeded := score >= 70

	time_remaining = maxi(0, time_remaining - selected_plan.time_cost)
	resources = maxi(0, resources - selected_plan.resource_cost)
	if succeeded:
		suspicion = maxi(0, suspicion + selected_plan.risk - 2)
	else:
		suspicion = mini(MAX_SUSPICION, suspicion + selected_plan.risk + 1)
		resources = maxi(0, resources - 1)

	var sabotage_applied := informant_sabotage_pending
	if sabotage_applied:
		suspicion = mini(MAX_SUSPICION, suspicion + 2)
		informant_sabotage_pending = false

	_evaluate_mission_failure()
	var consequence := _build_consequence(selected_plan, succeeded)
	if sabotage_applied:
		consequence += " An unexplained complication raises suspicion by 2."

	var result := {
		"ok": true,
		"round": current_round,
		"plan": selected_plan,
		"tallies": tallies,
		"was_tie": leaders.size() > 1,
		"score": score,
		"success": succeeded,
		"sabotage_applied": sabotage_applied,
		"consequence": consequence,
		"mission_failed": mission_failed,
		"failure_reason": failure_reason,
	}
	round_history.append(result)
	phase = Phase.RESOLUTION
	return result

func advance_after_resolution() -> bool:
	if phase != Phase.RESOLUTION:
		return false
	if mission_failed:
		winner = "Informant" if informant_player_id != -1 else "Nobody"
		roles_revealed = true
		phase = Phase.FINISHED
		return false
	if current_round >= TOTAL_ROUNDS:
		if not mission_succeeded():
			mission_failed = true
			failure_reason = "The crew failed too many mission plans."
			winner = "Informant" if informant_player_id != -1 else "Nobody"
			roles_revealed = true
			phase = Phase.FINISHED
		elif informant_player_id != -1:
			accusation_votes.clear()
			accusation_totals.clear()
			phase = Phase.ACCUSATION
		else:
			winner = "Everyone"
			roles_revealed = true
			phase = Phase.FINISHED
		return false
	current_round += 1
	begin_planning()
	return true

func get_accusation_voters() -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	for player in players:
		if not is_informant(player.id):
			eligible.append(player)
	return eligible

func cast_accusation_vote(voter_id: int, suspect_id: int) -> Dictionary:
	if phase != Phase.ACCUSATION:
		return {"ok": false, "error": "Accusation voting is not active."}
	if is_informant(voter_id):
		return {"ok": false, "error": "The Informant cannot cast an accusation vote."}
	if voter_id == suspect_id:
		return {"ok": false, "error": "Players cannot accuse themselves."}
	if get_player(voter_id).is_empty() or get_player(suspect_id).is_empty():
		return {"ok": false, "error": "That player is not in this match."}
	if accusation_votes.has(voter_id):
		return {"ok": false, "error": "That player has already voted."}
	accusation_votes[voter_id] = suspect_id
	return {"ok": true, "complete": accusation_votes.size() == get_accusation_voters().size()}

func resolve_accusation() -> Dictionary:
	if phase != Phase.ACCUSATION or accusation_votes.size() != get_accusation_voters().size():
		return {"ok": false, "error": "Every eligible player must vote before resolution."}

	accusation_totals.clear()
	for player in players:
		accusation_totals[player.id] = 0
	for suspect_id in accusation_votes.values():
		accusation_totals[suspect_id] += 1

	var highest_votes := 0
	var leaders: Array[int] = []
	for player in players:
		var total: int = accusation_totals[player.id]
		if total > highest_votes:
			highest_votes = total
			leaders.assign([player.id])
		elif total == highest_votes and total > 0:
			leaders.append(player.id)

	accusation_tied = leaders.size() != 1
	accused_player_id = -1 if accusation_tied else leaders[0]
	var correct := not accusation_tied and accused_player_id == informant_player_id
	winner = "Crew" if correct else "Informant"
	roles_revealed = true
	phase = Phase.FINISHED
	return {
		"ok": true,
		"tied": accusation_tied,
		"accused_player_id": accused_player_id,
		"correct": correct,
		"winner": winner,
		"totals": accusation_totals.duplicate(),
	}

func get_plan(plan_id: String) -> Dictionary:
	for plan in get_current_plans():
		if plan.id == plan_id:
			return plan
	return {}

func successful_rounds() -> int:
	var total := 0
	for result in round_history:
		if result.success:
			total += 1
	return total

func mission_succeeded() -> bool:
	return not mission_failed and successful_rounds() >= 2

func get_player(player_id: int) -> Dictionary:
	for player in players:
		if player.id == player_id:
			return player
	return {}

func _evaluate_mission_failure() -> void:
	if time_remaining <= 0:
		mission_failed = true
		failure_reason = "The crew ran out of time."
	elif suspicion >= 7:
		mission_failed = true
		failure_reason = "Security identified the crew."
	elif resources <= 0:
		mission_failed = true
		failure_reason = "The crew exhausted its operational resources."
	if mission_failed:
		winner = "Informant" if informant_player_id != -1 else "Nobody"

func _build_consequence(plan: Dictionary, succeeded: bool) -> String:
	if succeeded:
		return "%s works. The crew stays ahead of security and preserves momentum." % plan.title
	return "%s breaks down under pressure. Security closes in and an extra resource is lost." % plan.title

func is_informant(player_id: int) -> bool:
	return player_id == informant_player_id
