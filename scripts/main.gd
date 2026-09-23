extends Control

const GameState = preload("res://scripts/game_state.gd")

var game := GameState.new()
var rng := RandomNumberGenerator.new()
var reveal_index := 0
var role_is_visible := false

var title_label: Label
var subtitle_label: Label
var content: VBoxContainer
var status_label: Label
var name_input: LineEdit
var roster: VBoxContainer
var start_button: Button
var vote_index := 0
var latest_result: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	_build_shell()
	_show_lobby()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("101522")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 56)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	title_label = Label.new()
	title_label.text = "PROMPT HEIST"
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", Color("f4c95d"))
	page.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "TRUST NO ONE"
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", Color("8fa3bf"))
	page.add_child(subtitle_label)

	page.add_child(HSeparator.new())
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	page.add_child(content)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("ef6f6c"))
	status_label.add_theme_font_size_override("font_size", 16)
	page.add_child(status_label)

func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()
	status_label.text = ""

func _show_lobby() -> void:
	_clear_content()
	subtitle_label.text = "LOCAL PROTOTYPE • LOBBY"

	var instruction := Label.new()
	instruction.text = "Add 3–6 players. Four or more activates the hidden Informant."
	instruction.add_theme_font_size_override("font_size", 20)
	content.add_child(instruction)

	var entry_row := HBoxContainer.new()
	entry_row.add_theme_constant_override("separation", 12)
	content.add_child(entry_row)

	name_input = LineEdit.new()
	name_input.placeholder_text = "Player name"
	name_input.max_length = 18
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry_row.add_child(name_input)

	var add_button := Button.new()
	add_button.text = "Add player"
	entry_row.add_child(add_button)

	roster = VBoxContainer.new()
	roster.add_theme_constant_override("separation", 8)
	content.add_child(roster)

	start_button = Button.new()
	start_button.text = "Start heist"
	start_button.disabled = not game.can_start()
	content.add_child(start_button)

	add_button.pressed.connect(_add_player)
	name_input.text_submitted.connect(func(_value: String) -> void: _add_player())
	start_button.pressed.connect(_start_match)
	_refresh_roster()
	name_input.grab_focus()

func _refresh_roster() -> void:
	for child in roster.get_children():
		child.queue_free()
	for player in game.players:
		var player_label := Label.new()
		player_label.text = "• %s" % player.name
		player_label.add_theme_font_size_override("font_size", 22)
		roster.add_child(player_label)
	start_button.disabled = not game.can_start()

func _add_player() -> void:
	var result := game.add_player(name_input.text)
	if not result.ok:
		status_label.text = result.error
		return
	name_input.clear()
	status_label.text = ""
	_refresh_roster()
	name_input.grab_focus()

func _start_match() -> void:
	var result := game.start_match(rng)
	if not result.ok:
		status_label.text = result.error
		return
	reveal_index = 0
	role_is_visible = false
	_show_role_reveal()

func _show_role_reveal() -> void:
	_clear_content()
	subtitle_label.text = "PRIVATE ROLE REVEAL"
	var player: Dictionary = game.players[reveal_index]

	var privacy := Label.new()
	privacy.text = "Pass the screen to %s. Everyone else: look away." % player.name
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	privacy.add_theme_font_size_override("font_size", 26)
	content.add_child(privacy)

	var role_card := Label.new()
	role_card.text = "ROLE HIDDEN"
	role_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_card.custom_minimum_size = Vector2(0, 230)
	role_card.add_theme_font_size_override("font_size", 34)
	role_card.add_theme_color_override("font_color", Color("f4c95d"))
	content.add_child(role_card)

	var action_button := Button.new()
	action_button.text = "Reveal my role"
	content.add_child(action_button)

	action_button.pressed.connect(_handle_role_reveal.bind(player, role_card, action_button))

func _handle_role_reveal(player: Dictionary, role_card: Label, action_button: Button) -> void:
	if not role_is_visible:
		role_is_visible = true
		role_card.text = "%s\n\n%s" % [player.role, player.ability]
		action_button.text = "Hide and pass"
		return

	role_is_visible = false
	reveal_index += 1
	if reveal_index >= game.players.size():
		game.advance_to_briefing()
		_show_briefing()
	else:
		_show_role_reveal()

func _show_briefing() -> void:
	_clear_content()
	subtitle_label.text = "MISSION BRIEFING"

	var mission_title := Label.new()
	mission_title.text = game.mission.title
	mission_title.add_theme_font_size_override("font_size", 34)
	mission_title.add_theme_color_override("font_color", Color("f4c95d"))
	content.add_child(mission_title)

	var objective := Label.new()
	objective.text = "OBJECTIVE\n%s" % game.mission.objective
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 22)
	content.add_child(objective)

	var complication := Label.new()
	complication.text = "KNOWN COMPLICATION\n%s" % game.mission.complication
	complication.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	complication.add_theme_font_size_override("font_size", 22)
	complication.add_theme_color_override("font_color", Color("ef6f6c"))
	content.add_child(complication)

	var next_step := Label.new()
	next_step.text = "Three decisions stand between the crew and a clean extraction. Every vote matters."
	next_step.add_theme_font_size_override("font_size", 18)
	next_step.add_theme_color_override("font_color", Color("8fa3bf"))
	content.add_child(next_step)

	var continue_button := Button.new()
	continue_button.text = "Continue to planning"
	continue_button.pressed.connect(_begin_planning)
	content.add_child(continue_button)

func _begin_planning() -> void:
	game.begin_planning()
	_show_planning()

func _add_meters() -> void:
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 24)
	content.add_child(meters)
	meters.add_child(_make_meter("TIME", game.time_remaining, GameState.MAX_TIME, Color("56cfe1")))
	meters.add_child(_make_meter("SUSPICION", game.suspicion, GameState.MAX_SUSPICION, Color("ef6f6c")))
	meters.add_child(_make_meter("RESOURCES", game.resources, GameState.MAX_RESOURCES, Color("f4c95d")))

func _make_meter(label_text: String, value: int, maximum: int, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "%s  %d/%d" % [label_text, value, maximum]
	label.add_theme_color_override("font_color", color)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	box.add_child(bar)
	return box

func _show_planning() -> void:
	_clear_content()
	subtitle_label.text = "ROUND %d OF %d • PLANNING" % [game.current_round, GameState.TOTAL_ROUNDS]
	_add_meters()

	var prompt := Label.new()
	prompt.text = "Review the options together. Costs always apply; risk shapes suspicion."
	prompt.add_theme_font_size_override("font_size", 18)
	content.add_child(prompt)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	for plan in game.get_current_plans():
		cards.add_child(_make_plan_card(plan, false))

	var vote_button := Button.new()
	vote_button.text = "Begin private voting"
	vote_button.pressed.connect(_begin_voting)
	content.add_child(vote_button)

func _make_plan_card(plan: Dictionary, voting: bool) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.text = plan.title
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("f4c95d"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(heading)
	var description := Label.new()
	description.text = plan.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(description)
	var costs := Label.new()
	costs.text = "Time −%d  •  Resources −%d  •  Risk %d" % [plan.time_cost, plan.resource_cost, plan.risk]
	costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	costs.add_theme_color_override("font_color", Color("8fa3bf"))
	card.add_child(costs)
	if voting:
		var choose := Button.new()
		choose.text = "Vote for this plan"
		choose.pressed.connect(_cast_vote.bind(plan.id))
		card.add_child(choose)
	return card

func _begin_voting() -> void:
	game.begin_voting()
	vote_index = 0
	_show_voting()

func _show_voting() -> void:
	_clear_content()
	subtitle_label.text = "ROUND %d • SECRET BALLOT" % game.current_round
	var voter: Dictionary = game.players[vote_index]
	var instruction := Label.new()
	instruction.text = "Pass the screen to %s. Choose one plan; votes stay hidden until everyone finishes." % voter.name
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 21)
	content.add_child(instruction)
	if game.is_informant(voter.id) and not game.informant_sabotage_used:
		var sabotage := Button.new()
		sabotage.text = "Sabotage this round"
		sabotage.add_theme_color_override("font_color", Color("ef6f6c"))
		sabotage.pressed.connect(_arm_sabotage.bind(voter.id, sabotage))
		content.add_child(sabotage)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	for plan in game.get_current_plans():
		cards.add_child(_make_plan_card(plan, true))

func _arm_sabotage(player_id: int, button: Button) -> void:
	var result := game.arm_informant_sabotage(player_id)
	if not result.ok:
		status_label.text = result.error
		return
	button.text = "Sabotage armed"
	button.disabled = true

func _cast_vote(plan_id: String) -> void:
	var voter: Dictionary = game.players[vote_index]
	var result := game.cast_vote(voter.id, plan_id)
	if not result.ok:
		status_label.text = result.error
		return
	vote_index += 1
	if result.complete:
		latest_result = game.resolve_vote()
		_show_resolution()
	else:
		_show_voting()

func _show_resolution() -> void:
	_clear_content()
	subtitle_label.text = "ROUND %d • MISSION CONSEQUENCES" % latest_result.round
	_add_meters()
	var outcome := Label.new()
	outcome.text = "SUCCESS" if latest_result.success else "FAILURE"
	outcome.add_theme_font_size_override("font_size", 36)
	outcome.add_theme_color_override("font_color", Color("62d6a7") if latest_result.success else Color("ef6f6c"))
	content.add_child(outcome)

	var selected := Label.new()
	selected.text = "Selected plan: %s  •  Deterministic score: %d/100" % [latest_result.plan.title, latest_result.score]
	selected.add_theme_font_size_override("font_size", 22)
	content.add_child(selected)
	var tally := Label.new()
	var tally_parts: Array[String] = []
	for plan in game.get_current_plans():
		tally_parts.append("%s: %d" % [plan.title, latest_result.tallies[plan.id]])
	tally.text = "Vote tally — %s" % "  •  ".join(tally_parts)
	tally.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(tally)
	if latest_result.was_tie:
		var tie_note := Label.new()
		tie_note.text = "Tie resolved by the standing rule: lowest-risk tied plan, then card order."
		tie_note.add_theme_color_override("font_color", Color("f4c95d"))
		content.add_child(tie_note)
	var consequence := Label.new()
	consequence.text = latest_result.consequence
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	consequence.add_theme_font_size_override("font_size", 20)
	content.add_child(consequence)
	if latest_result.mission_failed:
		var failure := Label.new()
		failure.text = latest_result.failure_reason
		failure.add_theme_font_size_override("font_size", 20)
		failure.add_theme_color_override("font_color", Color("ef6f6c"))
		content.add_child(failure)

	var continue_button := Button.new()
	continue_button.text = "Continue to round %d" % (game.current_round + 1) if game.current_round < GameState.TOTAL_ROUNDS and not game.mission_failed else "View mission outcome"
	continue_button.pressed.connect(_continue_after_resolution)
	content.add_child(continue_button)

func _continue_after_resolution() -> void:
	if game.advance_after_resolution():
		_show_planning()
	else:
		_show_mission_summary()

func _show_mission_summary() -> void:
	_clear_content()
	subtitle_label.text = "MISSION COMPLETE • %d ROUND%s RESOLVED" % [game.round_history.size(), "" if game.round_history.size() == 1 else "S"]
	_add_meters()
	var won := game.mission_succeeded()
	var headline := Label.new()
	headline.text = "THE CREW ESCAPES" if won else "THE HEIST COLLAPSES"
	headline.add_theme_font_size_override("font_size", 36)
	headline.add_theme_color_override("font_color", Color("62d6a7") if won else Color("ef6f6c"))
	content.add_child(headline)
	var summary := Label.new()
	summary.text = "%d of %d plans succeeded. Final time: %d. Final suspicion: %d. Resources left: %d." % [game.successful_rounds(), GameState.TOTAL_ROUNDS, game.time_remaining, game.suspicion, game.resources]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 21)
	content.add_child(summary)
	var rule := Label.new()
	rule.text = game.failure_reason if game.mission_failed else "Victory requires at least two successful rounds without crossing a mission-failure threshold."
	rule.add_theme_color_override("font_color", Color("8fa3bf"))
	content.add_child(rule)

	var new_game_button := Button.new()
	new_game_button.text = "Start a new game"
	new_game_button.pressed.connect(_start_new_game)
	content.add_child(new_game_button)

func _start_new_game() -> void:
	game.reset_game()
	reveal_index = 0
	role_is_visible = false
	vote_index = 0
	latest_result.clear()
	_show_lobby()
