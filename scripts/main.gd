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
	next_step.text = "Milestone complete: lobby → role assignment → private reveal → briefing."
	next_step.add_theme_font_size_override("font_size", 18)
	next_step.add_theme_color_override("font_color", Color("8fa3bf"))
	content.add_child(next_step)
