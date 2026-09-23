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

var phase: Phase = Phase.LOBBY
var players: Array[Dictionary] = []
var informant_player_id := -1
var mission := {
	"title": "The Neon Vault",
	"objective": "Recover a stolen prototype from a private technology expo.",
	"complication": "Security changes its patrol pattern every sixty seconds.",
}

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

func is_informant(player_id: int) -> bool:
	return player_id == informant_player_id

