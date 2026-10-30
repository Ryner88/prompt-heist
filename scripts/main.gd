extends Control

const GameState = preload("res://scripts/game_state.gd")
const RoomNetworkClientScript = preload("res://scripts/room_network_client.gd")
const MultiplayerFlowScript = preload("res://scripts/multiplayer_flow.gd")
const RoomProtocolScript = preload("res://scripts/room_protocol.gd")

var game := GameState.new()
var rng := RandomNumberGenerator.new()
var reveal_index := 0
var role_is_visible := false

var title_label: Label
var subtitle_label: Label
var content: VBoxContainer
var content_scroll: ScrollContainer
var match_dashboard: VBoxContainer
var privacy_notice: Label
var status_label: Label
var name_input: LineEdit
var roster: VBoxContainer
var start_button: Button
var vote_index := 0
var latest_result: Dictionary = {}
var accusation_index := 0
var room_client: Node
var multiplayer_flow: Node
var online_name := ""
var online_room_code := ""
var online_endpoint := ""
var online_create_button: Button
var online_join_button: Button
var online_validation_label: Label
var online_sabotage_armed := false
var online_screen_key := ""
var online_scroll_reset_pending := false
var privacy_mode := false
var notes_open := false
var accusation_notes: Dictionary = {}
var last_haptic_turn := ""
var shown_complication_round := -1
var discussion_timer: Timer
var countdown_label: Label
var countdown_phase_key := ""
var countdown_started_ms := 0
var active_overlay: ColorRect
const NOTE_TAGS := ["Suspicious action", "Blew resources", "Failed ability"]

func _ready() -> void:
	rng.randomize()
	if OS.has_feature("web"):
		_initialize_web_keyboard_attributes()
	_build_shell()
	_show_mode_selection()
	if OS.has_feature("web"):
		var linked_code: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''")
		if linked_code is String and RoomProtocolScript.validate_room_code(linked_code) == "":
			online_room_code = linked_code.to_upper()
			_show_online_multiplayer()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("101522")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
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
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", Color("8fa3bf"))
	page.add_child(subtitle_label)

	page.add_child(HSeparator.new())
	match_dashboard = VBoxContainer.new()
	match_dashboard.visible = false
	page.add_child(match_dashboard)
	discussion_timer = Timer.new()
	discussion_timer.wait_time = 1.0
	discussion_timer.timeout.connect(_update_countdown)
	add_child(discussion_timer)
	privacy_notice = Label.new()
	privacy_notice.text = "Privacy shroud is on. Tap Privacy to view this screen."
	privacy_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy_notice.visible = false
	privacy_notice.add_theme_color_override("font_color", Color("f4c95d"))
	page.add_child(privacy_notice)
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.follow_focus = true
	page.add_child(content_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	content_scroll.add_child(content)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color", Color("ef6f6c"))
	status_label.add_theme_font_size_override("font_size", 16)
	page.add_child(status_label)

func _clear_content() -> void:
	content_scroll.scroll_vertical = 0
	content.visible = true
	privacy_notice.visible = false
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	status_label.text = ""

func _show_mode_selection() -> void:
	_clear_content()
	match_dashboard.visible = false
	subtitle_label.text = "CHOOSE HOW TO PLAY"
	var intro := Label.new()
	intro.text = "Three rounds. One hidden Informant. Trust your crew—or betray them."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 18)
	content.add_child(intro)

	_online_heading("JOIN A ROOM", Color("f4c95d"), 25)
	var quick_code := LineEdit.new()
	quick_code.placeholder_text = "ROOM CODE"
	quick_code.max_length = RoomProtocolScript.ROOM_CODE_LENGTH
	quick_code.text = online_room_code
	quick_code.custom_minimum_size = Vector2(0, 64)
	quick_code.add_theme_font_size_override("font_size", 30)
	quick_code.text_changed.connect(func(value: String) -> void:
		var cleaned := _clean_room_code(value)
		online_room_code = cleaned
		if quick_code.text != cleaned:
			quick_code.text = cleaned
			quick_code.caret_column = cleaned.length()
	)
	quick_code.focus_entered.connect(_configure_web_code_input)
	content.add_child(quick_code)
	var online_button := Button.new()
	online_button.text = "Join online room"
	online_button.custom_minimum_size = Vector2(0, 56)
	online_button.pressed.connect(func() -> void:
		online_room_code = _clean_room_code(quick_code.text)
		_show_online_multiplayer()
	)
	content.add_child(online_button)
	var create_button := Button.new()
	create_button.text = "Create online room"
	create_button.custom_minimum_size = Vector2(0, 56)
	create_button.pressed.connect(func() -> void:
		online_room_code = ""
		_show_online_multiplayer()
	)
	content.add_child(create_button)
	_online_text("Use touch or mouse. Create a room and share its code, or enter a friend's six-character code to join.", Color("8fa3bf"), 16)
	quick_code.grab_focus()

	var local_button := Button.new()
	local_button.text = "Local pass-and-play"
	local_button.custom_minimum_size = Vector2(0, 56)
	local_button.pressed.connect(_show_lobby)
	content.add_child(local_button)

	var guide_button := Button.new()
	guide_button.text = "How to play"
	guide_button.custom_minimum_size = Vector2(0, 48)
	guide_button.pressed.connect(_show_how_to_play)
	content.add_child(guide_button)

func _show_how_to_play() -> void:
	_clear_content()
	subtitle_label.text = "HOW TO PLAY"
	_online_heading("The heist", Color("f4c95d"), 28)
	_online_text("Online rooms take 3–4 players; local pass-and-play takes 3–6. Three players cooperate. With four or more, one hidden Informant tries to make the crew fail or escape accusation.")
	_online_heading("Each round", Color("f4c95d"), 25)
	_online_text("Review three plans and their time, resource, and risk costs. When everyone is ready, each player votes privately. Most votes wins; ties choose the lowest-risk plan, then card order. Costs always apply. A score of 70 or more succeeds. Hidden complications can lower a plan's score.")
	_online_heading("How to win", Color("f4c95d"), 25)
	_online_text("The crew needs at least two successful plans across three rounds. Running out of time or resources, or reaching seven suspicion, ends the mission immediately. In a social match, a successful mission leads to a private accusation. The crew wins only if one suspect leads and that suspect is the Informant; otherwise the Informant wins.")
	_online_heading("Secret roles", Color("f4c95d"), 25)
	_online_text("Specialists may use their ability once, before casting a private vote. You may skip it. Its effect is confirmed on your screen. The Informant can instead add two suspicion once by checking sabotage when voting; it is revealed after resolution.")
	_online_heading("Phone controls", Color("f4c95d"), 25)
	_online_text("Hold your role card to see it and release to hide it. Use Privacy to cover your match screen, and Deduction notes to tag other players privately on this device. The planning and voting countdowns are discussion aids; everyone still needs to act before the room advances. Confirm an accusation before it is sent.")
	for role in GameState.ROLE_TEMPLATES:
		_online_text("%s • %s" % [role.role, role.ability], Color("e6ebf2"), 16)
	var back := Button.new()
	back.text = "Back to play modes"
	back.pressed.connect(_show_mode_selection)
	content.add_child(back)

func _show_online_multiplayer() -> void:
	_initialize_multiplayer()
	online_endpoint = _configured_room_endpoint()
	multiplayer_flow.connect_service(online_endpoint)
	_render_multiplayer_state()

func _initialize_multiplayer() -> void:
	if multiplayer_flow != null:
		return
	room_client = RoomNetworkClientScript.new()
	add_child(room_client)
	multiplayer_flow = MultiplayerFlowScript.new(room_client)
	add_child(multiplayer_flow)
	multiplayer_flow.state_changed.connect(_on_online_state_changed)
	multiplayer_flow.feedback_changed.connect(func(message: String) -> void:
		status_label.text = message
	)
	multiplayer_flow.lobby_changed.connect(func(_snapshot: Dictionary) -> void:
		if multiplayer_flow.state != MultiplayerFlowScript.State.MATCH:
			_render_multiplayer_state()
	)
	multiplayer_flow.match_changed.connect(_render_multiplayer_state)
	room_client.request_failed.connect(_on_online_request_failed)

func _on_online_state_changed(_state: int) -> void:
	online_sabotage_armed = false
	if _state in [MultiplayerFlowScript.State.ENTRY, MultiplayerFlowScript.State.LOBBY, MultiplayerFlowScript.State.LEAVING]:
		privacy_mode = false
		notes_open = false
		accusation_notes.clear()
		last_haptic_turn = ""
		shown_complication_round = -1
		countdown_phase_key = ""
		discussion_timer.stop()
	_render_multiplayer_state()

func _on_online_request_failed(_code: String, _message: String) -> void:
	if multiplayer_flow.state == MultiplayerFlowScript.State.LOBBY or multiplayer_flow.state == MultiplayerFlowScript.State.MATCH:
		_render_multiplayer_state()

func _configured_room_endpoint() -> String:
	var environment_endpoint := OS.get_environment("PROMPT_HEIST_WS_URL").strip_edges()
	if not environment_endpoint.is_empty():
		return environment_endpoint
	if OS.has_feature("web"):
		var web_host: Variant = JavaScriptBridge.eval("window.location.hostname")
		var web_origin: Variant = JavaScriptBridge.eval("window.location.host")
		if web_host is String and web_origin is String and web_host not in ["localhost", "127.0.0.1", "[::1]"]:
			return "wss://%s/ws" % web_origin
	return str(ProjectSettings.get_setting("network/room_service_url", "ws://127.0.0.1:3000/ws")).strip_edges()

func _render_multiplayer_state() -> void:
	if multiplayer_flow == null:
		return
	var screen_key := str(multiplayer_flow.state)
	if multiplayer_flow.state == MultiplayerFlowScript.State.MATCH and not multiplayer_flow.match_snapshot.is_empty():
		screen_key += ":%s:%d" % [multiplayer_flow.match_snapshot.phase, multiplayer_flow.match_snapshot.round]
	if screen_key != online_screen_key:
		online_scroll_reset_pending = true
		if active_overlay != null and is_instance_valid(active_overlay):
			active_overlay.queue_free()
			active_overlay = null
	var previous_scroll := content_scroll.scroll_vertical if not online_scroll_reset_pending else 0
	online_screen_key = screen_key
	_clear_content()
	status_label.text = multiplayer_flow.feedback
	match_dashboard.visible = multiplayer_flow.state == MultiplayerFlowScript.State.MATCH
	for child in match_dashboard.get_children():
		match_dashboard.remove_child(child)
		child.queue_free()
	match multiplayer_flow.state:
		MultiplayerFlowScript.State.CONNECTING:
			_show_online_connecting()
		MultiplayerFlowScript.State.RECOVERING:
			_show_online_recovering()
		MultiplayerFlowScript.State.ENTRY, MultiplayerFlowScript.State.SUBMITTING:
			_show_online_entry(multiplayer_flow.state == MultiplayerFlowScript.State.SUBMITTING)
		MultiplayerFlowScript.State.LOBBY, MultiplayerFlowScript.State.LEAVING:
			_show_online_lobby()
		MultiplayerFlowScript.State.MATCH:
			_show_online_match()
		_:
			_show_online_disconnected()
	if multiplayer_flow.state == MultiplayerFlowScript.State.MATCH:
		content.visible = not privacy_mode
		privacy_notice.visible = privacy_mode
		if privacy_mode:
			subtitle_label.text = "ONLINE • PRIVACY SHROUD"
	if online_scroll_reset_pending:
		call_deferred("_finish_online_scroll_reset", screen_key)
	elif previous_scroll > 0:
		content_scroll.set_deferred("scroll_vertical", previous_scroll)

func _finish_online_scroll_reset(expected_key: String) -> void:
	if online_screen_key != expected_key:
		return
	content_scroll.scroll_vertical = 0
	online_scroll_reset_pending = false

func _show_online_connecting() -> void:
	subtitle_label.text = "ONLINE • CONNECTING"
	var label := Label.new()
	label.text = "Connecting securely to the room service…"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	content.add_child(label)

func _show_online_recovering() -> void:
	subtitle_label.text = "ONLINE • RECOVERING ROOM"
	var label := Label.new()
	label.text = "Checking your reserved seat with the room service…"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)

func _show_online_disconnected() -> void:
	subtitle_label.text = "ONLINE • DISCONNECTED"
	var notice := Label.new()
	notice.text = "The service is not connected. Retry to recover a reserved seat, or create or join another room."
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(notice)
	var retry := Button.new()
	retry.text = "Retry service connection"
	retry.pressed.connect(func() -> void: multiplayer_flow.connect_service(online_endpoint))
	content.add_child(retry)
	var back := Button.new()
	back.text = "Back to play modes"
	back.pressed.connect(func() -> void:
		room_client.disconnect_from_service()
		_show_mode_selection()
	)
	content.add_child(back)

func _show_online_entry(pending: bool) -> void:
	subtitle_label.text = "ONLINE • CREATE OR JOIN"
	var connection := Label.new()
	connection.text = "● Connected to room service"
	connection.add_theme_color_override("font_color", Color("62d6a7"))
	content.add_child(connection)

	var code_label := Label.new()
	code_label.text = "JOIN WITH ROOM CODE"
	content.add_child(code_label)
	var code_input := LineEdit.new()
	code_input.placeholder_text = "ABC234"
	code_input.max_length = RoomProtocolScript.ROOM_CODE_LENGTH
	code_input.custom_minimum_size = Vector2(0, 64)
	code_input.add_theme_font_size_override("font_size", 30)
	code_input.text = online_room_code
	code_input.editable = not pending
	code_input.text_changed.connect(func(value: String) -> void:
		online_room_code = _clean_room_code(value)
		if code_input.text != online_room_code:
			code_input.text = online_room_code
			code_input.caret_column = online_room_code.length()
		_refresh_online_entry_buttons()
	)
	code_input.focus_entered.connect(_configure_web_code_input)
	content.add_child(code_input)
	var name_label := Label.new()
	name_label.text = "YOUR DISPLAY NAME"
	content.add_child(name_label)
	var online_name_input := LineEdit.new()
	online_name_input.placeholder_text = "2–18 characters"
	online_name_input.max_length = RoomProtocolScript.MAX_NAME_LENGTH
	online_name_input.custom_minimum_size = Vector2(0, 56)
	online_name_input.text = online_name
	online_name_input.editable = not pending
	online_name_input.text_changed.connect(func(value: String) -> void:
		online_name = value
		_refresh_online_entry_buttons()
	)
	online_name_input.focus_entered.connect(_configure_web_name_input)
	content.add_child(online_name_input)

	online_join_button = Button.new()
	online_join_button.text = "Joining room…" if pending else "Join Room"
	online_join_button.custom_minimum_size = Vector2(0, 56)
	online_join_button.pressed.connect(func() -> void:
		online_name = online_name_input.text
		online_room_code = code_input.text
		multiplayer_flow.submit_join(online_name, online_room_code)
	)
	content.add_child(online_join_button)
	_online_text("OR CREATE A NEW ROOM", Color("8fa3bf"), 16)
	online_create_button = Button.new()
	online_create_button.text = "Creating room…" if pending else "Create Room"
	online_create_button.custom_minimum_size = Vector2(0, 56)
	online_create_button.pressed.connect(func() -> void:
		online_name = online_name_input.text
		multiplayer_flow.submit_create(online_name)
	)
	content.add_child(online_create_button)

	online_validation_label = Label.new()
	online_validation_label.add_theme_color_override("font_color", Color("8fa3bf"))
	online_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(online_validation_label)
	_refresh_online_entry_buttons()
	if not pending:
		if online_room_code.is_empty():
			code_input.grab_focus()
		else:
			online_name_input.grab_focus()

func _clean_room_code(value: String) -> String:
	var cleaned := ""
	for character in value.to_upper():
		if RoomProtocolScript.ROOM_CODE_ALPHABET.contains(character):
			cleaned += character
	return cleaned.substr(0, RoomProtocolScript.ROOM_CODE_LENGTH)

func _configure_web_code_input() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__promptHeistKeyboardMode = 'code'; window.__promptHeistApplyKeyboardMode(); setTimeout(window.__promptHeistApplyKeyboardMode, 100)")

func _configure_web_name_input() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__promptHeistKeyboardMode = 'name'; window.__promptHeistApplyKeyboardMode(); setTimeout(window.__promptHeistApplyKeyboardMode, 100)")

func _initialize_web_keyboard_attributes() -> void:
	JavaScriptBridge.eval("""
		window.__promptHeistKeyboardMode = 'code';
		window.__promptHeistApplyKeyboardMode = () => {
			const input = document.activeElement;
			if (!input || !(input instanceof HTMLInputElement || input.isContentEditable)) return;
			const code = window.__promptHeistKeyboardMode === 'code';
			input.setAttribute('autocorrect', code ? 'off' : 'on');
			input.setAttribute('autocapitalize', code ? 'characters' : 'sentences');
			input.setAttribute('spellcheck', code ? 'false' : 'true');
		};
		document.addEventListener('focusin', window.__promptHeistApplyKeyboardMode, true);
	""")

func _refresh_online_entry_buttons() -> void:
	if online_create_button == null or not is_instance_valid(online_create_button):
		return
	var pending: bool = multiplayer_flow.state == MultiplayerFlowScript.State.SUBMITTING
	online_create_button.disabled = pending or not multiplayer_flow.can_create(online_name)
	online_join_button.disabled = pending or not multiplayer_flow.can_join(online_name, online_room_code)
	var name_error := RoomProtocolScript.validate_name(online_name)
	var code_error := RoomProtocolScript.validate_room_code(online_room_code)
	if not name_error.is_empty():
		online_validation_label.text = "Enter a display name containing 2–18 characters."
	elif not online_room_code.is_empty() and not code_error.is_empty():
		online_validation_label.text = "Room codes contain six unambiguous letters or numbers."
	else:
		online_validation_label.text = "Create a new room or enter an existing six-character code."

func _show_online_lobby() -> void:
	subtitle_label.text = "ONLINE • WAITING ROOM"
	var snapshot: Dictionary = multiplayer_flow.lobby_snapshot
	if snapshot.is_empty():
		var waiting := Label.new()
		waiting.text = "Waiting for the authoritative room snapshot…"
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(waiting)
		return
	var room_heading := Label.new()
	room_heading.text = "ROOM %s" % snapshot.room_code
	room_heading.add_theme_font_size_override("font_size", 36)
	room_heading.add_theme_color_override("font_color", Color("f4c95d"))
	content.add_child(room_heading)
	var copy_button := Button.new()
	copy_button.text = "Copy room code"
	copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(snapshot.room_code)
		status_label.text = "Room code copied when clipboard access is available."
	)
	content.add_child(copy_button)
	if OS.has_feature("web"):
		var page_url: Variant = JavaScriptBridge.eval("window.location.origin + window.location.pathname")
		if page_url is String and RoomProtocolScript.validate_room_code(snapshot.room_code) == "":
			var invite_url: String = page_url + "?room=" + snapshot.room_code
			var invite_button := Button.new()
			invite_button.text = "Copy invite link"
			invite_button.pressed.connect(func() -> void:
				DisplayServer.clipboard_set(invite_url)
				status_label.text = "Invite link copied when clipboard access is available."
			)
			content.add_child(invite_button)
	var count := Label.new()
	count.text = "%d / %d players" % [snapshot.player_count, snapshot.max_players]
	count.add_theme_font_size_override("font_size", 22)
	content.add_child(count)
	for player_name in snapshot.player_names:
		var player_label := Label.new()
		player_label.text = "• %s" % player_name
		player_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		player_label.add_theme_font_size_override("font_size", 21)
		content.add_child(player_label)
	var can_start: bool = snapshot.player_count >= 3
	var waiting_status := Label.new()
	if snapshot.player_count == snapshot.max_players:
		waiting_status.text = "Room full. Anyone can start the heist; four players adds a hidden Informant."
	elif can_start:
		waiting_status.text = "Ready for a cooperative heist, or wait for a fourth player to add a hidden Informant."
	else:
		waiting_status.text = "Waiting for more players… At least three are needed."
	waiting_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waiting_status.add_theme_color_override("font_color", Color("62d6a7") if can_start else Color("8fa3bf"))
	content.add_child(waiting_status)
	var start_heist := Button.new()
	start_heist.text = "Start heist"
	start_heist.custom_minimum_size = Vector2(0, 48)
	start_heist.disabled = not multiplayer_flow.can_start_match()
	start_heist.pressed.connect(func() -> void:
		start_heist.disabled = true
		start_heist.text = "Starting…"
		if not multiplayer_flow.start_match():
			start_heist.disabled = false
			start_heist.text = "Start heist"
	)
	content.add_child(start_heist)
	var connection := Label.new()
	connection.text = "● Connected"
	connection.add_theme_color_override("font_color", Color("62d6a7"))
	content.add_child(connection)
	var leave := Button.new()
	leave.text = "Leaving room…" if multiplayer_flow.state == MultiplayerFlowScript.State.LEAVING else "Leave room and return"
	leave.disabled = multiplayer_flow.state == MultiplayerFlowScript.State.LEAVING
	leave.pressed.connect(func() -> void: multiplayer_flow.leave_lobby())
	content.add_child(leave)

func _show_online_match() -> void:
	var snapshot: Dictionary = multiplayer_flow.match_snapshot
	if snapshot.is_empty():
		return
	_add_match_dashboard(snapshot)
	_maybe_alert_turn(snapshot)
	var phase: String = snapshot.phase
	if notes_open and phase not in ["role_reveal", "finished"]:
		_add_accusation_notes(snapshot)
	match phase:
		"role_reveal":
			_show_online_role(snapshot)
		"briefing":
			_show_online_briefing(snapshot)
		"planning":
			_show_online_planning(snapshot)
		"voting":
			_show_online_voting(snapshot)
		"resolution":
			_show_online_resolution(snapshot)
		"accusation":
			_show_online_accusation(snapshot)
		"finished":
			_show_online_recap(snapshot)
	_add_online_presence(snapshot)
	if phase == "resolution":
		_maybe_show_complication(snapshot)

func _add_match_dashboard(snapshot: Dictionary) -> void:
	if privacy_mode:
		var uncover := Button.new()
		uncover.text = "Privacy: ON • Show match"
		uncover.custom_minimum_size = Vector2(0, 48)
		uncover.pressed.connect(func() -> void:
			privacy_mode = false
			_render_multiplayer_state()
		)
		match_dashboard.add_child(uncover)
		return
	var top := HBoxContainer.new()
	match_dashboard.add_child(top)
	var phase: String = snapshot.phase
	var phase_name := phase.capitalize()
	var phase_label := Label.new()
	phase_label.text = "ROUND %d/%d • %s" % [snapshot.round, snapshot.total_rounds, phase_name]
	phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_label.add_theme_color_override("font_color", Color("f4c95d"))
	top.add_child(phase_label)
	var countdown_seconds := _countdown_duration(phase)
	if countdown_seconds > 0:
		var phase_key := "%s:%d:%s" % [snapshot.room_code, snapshot.round, phase]
		if phase_key != countdown_phase_key:
			countdown_phase_key = phase_key
			countdown_started_ms = Time.get_ticks_msec()
			discussion_timer.start()
		countdown_label = Label.new()
		countdown_label.add_theme_color_override("font_color", Color("56cfe1"))
		countdown_label.add_theme_font_size_override("font_size", 16)
		top.add_child(countdown_label)
		_update_countdown()
	else:
		countdown_label = null
		discussion_timer.stop()
	var controls := HBoxContainer.new()
	match_dashboard.add_child(controls)
	var privacy_button := Button.new()
	privacy_button.text = "Privacy: ON" if privacy_mode else "Privacy: OFF"
	privacy_button.custom_minimum_size = Vector2(112, 48)
	privacy_button.pressed.connect(func() -> void:
		privacy_mode = not privacy_mode
		_render_multiplayer_state()
	)
	controls.add_child(privacy_button)
	var meters_data: Dictionary = snapshot.meters
	var bars := GridContainer.new()
	bars.columns = 3
	bars.add_theme_constant_override("h_separation", 8)
	match_dashboard.add_child(bars)
	bars.add_child(_make_meter("TIME", meters_data.time, meters_data.max_time, Color("56cfe1"), true))
	bars.add_child(_make_meter("SUSPICION", meters_data.suspicion, meters_data.max_suspicion, Color("ef6f6c"), true))
	bars.add_child(_make_meter("RESOURCES", meters_data.resources, meters_data.max_resources, Color("f4c95d"), true))
	if phase not in ["role_reveal", "finished"]:
		var notes_button := Button.new()
		notes_button.text = "Hide notes" if notes_open else "Deduction notes"
		notes_button.custom_minimum_size = Vector2(0, 44)
		notes_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		notes_button.pressed.connect(func() -> void:
			notes_open = not notes_open
			_render_multiplayer_state()
		)
		controls.add_child(notes_button)
	if countdown_seconds > 0:
		var timer_note := Label.new()
		timer_note.text = "Timer on this device only • the phase advances when everyone acts"
		timer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		timer_note.add_theme_font_size_override("font_size", 12)
		timer_note.add_theme_color_override("font_color", Color("8fa3bf"))
		match_dashboard.add_child(timer_note)

func _countdown_duration(phase: String) -> int:
	if phase == "planning":
		return 90
	if phase == "voting":
		return 60
	return 0

func _update_countdown() -> void:
	if countdown_label == null or not is_instance_valid(countdown_label):
		return
	var phase: String = str(multiplayer_flow.match_snapshot.get("phase", ""))
	var elapsed := maxi(0, int((Time.get_ticks_msec() - countdown_started_ms) / 1000))
	var remaining := maxi(0, _countdown_duration(phase) - elapsed)
	countdown_label.text = "Timer %02d:%02d" % [int(remaining / 60), remaining % 60]
	countdown_label.tooltip_text = "Visual discussion timer. The room advances when every player acts."
	if remaining == 0:
		discussion_timer.stop()

func _maybe_alert_turn(snapshot: Dictionary) -> void:
	var phase: String = snapshot.phase
	var action_due := false
	if phase in RoomProtocolScript.READY_PHASES:
		action_due = not multiplayer_flow.is_ready()
	elif phase == "voting":
		action_due = not multiplayer_flow.has_voted()
	elif phase == "accusation":
		action_due = not multiplayer_flow.is_informant() and not multiplayer_flow.has_accused()
	var turn_key := "%s:%d:%s" % [snapshot.room_code, snapshot.round, phase]
	if action_due and turn_key != last_haptic_turn:
		last_haptic_turn = turn_key
		_vibrate(40)

func _vibrate(milliseconds: int) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (navigator.vibrate) navigator.vibrate(%d)" % milliseconds)

func _maybe_show_complication(snapshot: Dictionary) -> void:
	var result: Dictionary = snapshot.last_result
	if privacy_mode or result.is_empty() or shown_complication_round == int(result.round):
		return
	if not str(result.consequence).contains("Base score fell by"):
		return
	shown_complication_round = int(result.round)
	_vibrate(90)
	_show_mobile_overlay("Hidden complication triggered", "%s hit a hidden complication. Read the full consequence on the resolution screen." % result.plan_title, "Acknowledge", Callable())

func _show_mobile_overlay(heading: String, message: String, confirm_text: String, on_confirm: Callable, cancel_text: String = "") -> void:
	if active_overlay != null and is_instance_valid(active_overlay):
		active_overlay.queue_free()
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.06, 0.93)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	active_overlay = overlay
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 32, 360), 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2638")
	style.border_color = Color("f4c95d")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var padding := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(padding)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	padding.add_child(body)
	var title_text := Label.new()
	title_text.text = heading
	title_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_text.add_theme_font_size_override("font_size", 24)
	title_text.add_theme_color_override("font_color", Color("f4c95d"))
	body.add_child(title_text)
	var details := Label.new()
	details.text = message
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 18)
	body.add_child(details)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	body.add_child(buttons)
	var dismiss := func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
		if active_overlay == overlay:
			active_overlay = null
	if not cancel_text.is_empty():
		var cancel := Button.new()
		cancel.text = cancel_text
		cancel.custom_minimum_size = Vector2(0, 52)
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.pressed.connect(dismiss)
		buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = confirm_text
	confirm.custom_minimum_size = Vector2(0, 52)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func() -> void:
		dismiss.call()
		if on_confirm.is_valid():
			on_confirm.call()
	)
	buttons.add_child(confirm)

func _add_accusation_notes(snapshot: Dictionary) -> void:
	_online_heading("Private deduction notes", Color("f4c95d"), 21)
	_online_text("These tags stay on this device and reset for the next match.", Color("8fa3bf"), 14)
	for seat in snapshot.seats:
		if seat.seat == multiplayer_flow.my_seat():
			continue
		var seat_number: int = seat.seat
		_online_text(seat.name, Color("e6ebf2"), 17)
		var tags := GridContainer.new()
		tags.columns = 1 if size.x < 700 else 3
		content.add_child(tags)
		for tag in NOTE_TAGS:
			var current_tag: String = tag
			var selected: Array = accusation_notes.get(seat_number, [])
			var tag_button := Button.new()
			tag_button.text = ("✓ " if selected.has(current_tag) else "+ ") + current_tag
			tag_button.custom_minimum_size = Vector2(0, 44)
			tag_button.pressed.connect(func() -> void:
				var updated: Array = accusation_notes.get(seat_number, []).duplicate()
				if updated.has(current_tag):
					updated.erase(current_tag)
				else:
					updated.append(current_tag)
				accusation_notes[seat_number] = updated
				_render_multiplayer_state()
			)
			tags.add_child(tag_button)

func _online_heading(text: String, color: Color = Color("f4c95d"), size: int = 30) -> Label:
	var heading := Label.new()
	heading.text = text
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", size)
	heading.add_theme_color_override("font_color", color)
	content.add_child(heading)
	return heading

func _online_text(text: String, color: Color = Color("e6ebf2"), size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	content.add_child(label)
	return label

## The shared "continue" control for steps that advance once every seat is ready.
func _add_ready_button(label_text: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 48)
	if multiplayer_flow.is_ready():
		button.text = "Waiting for the crew…"
		button.disabled = true
	else:
		button.text = label_text
		button.disabled = not multiplayer_flow.can_act()
	button.pressed.connect(func() -> void:
		button.disabled = true
		if not multiplayer_flow.ready_current_step():
			button.disabled = false
	)
	content.add_child(button)

func _add_online_presence(snapshot: Dictionary) -> void:
	var phase: String = snapshot.phase
	var progress: Dictionary = snapshot.progress
	var lines: Array[String] = []
	if RoomProtocolScript.READY_PHASES.has(phase) or phase == "voting":
		var waiting: Array[String] = []
		for seat in snapshot.seats:
			var done: bool = seat.ready if phase != "voting" else seat.acted
			if not done:
				waiting.append(seat.name)
		var verb := "voted" if phase == "voting" else "ready"
		if phase == "finished":
			verb = "back to the waiting room"
		lines.append("%d of %d %s%s" % [progress.done, progress.needed, verb, "" if waiting.is_empty() else " • waiting for " + ", ".join(waiting)])
	elif phase == "accusation":
		lines.append("%d of %d accusations cast" % [progress.done, progress.needed])
	var offline: Array[String] = []
	for seat in snapshot.seats:
		if not seat.connected:
			offline.append(seat.name)
	if not offline.is_empty():
		lines.append("Reconnecting: %s. Their seat is held for 30 seconds." % ", ".join(offline))
	if not lines.is_empty():
		_online_text("\n".join(lines), Color("8fa3bf"), 15)
	var leave := Button.new()
	leave.text = "Leave room" if phase == "finished" else "Leave heist (ends it for everyone)"
	leave.pressed.connect(func() -> void: multiplayer_flow.leave_lobby())
	content.add_child(leave)

func _show_online_role(snapshot: Dictionary) -> void:
	subtitle_label.text = "ONLINE • YOUR SECRET ROLE"
	var private_state: Dictionary = multiplayer_flow.match_private
	if private_state.is_empty():
		_online_text("Receiving your role…")
		return
	_online_text("Keep your screen to yourself. Hold the button to view your role; release to hide it.", Color("8fa3bf"))
	var is_informant: bool = multiplayer_flow.is_informant()
	var role_card := _online_heading("ROLE HIDDEN", Color("f4c95d"), 34)
	role_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_card.custom_minimum_size = Vector2(0, 130)
	var role_detail := _online_text("Hold to reveal", Color("8fa3bf"), 20)
	role_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var reveal := Button.new()
	reveal.text = "Hold to reveal role"
	reveal.custom_minimum_size = Vector2(0, 72)
	content.add_child(reveal)
	var hold_timer := Timer.new()
	hold_timer.one_shot = true
	hold_timer.wait_time = 0.45
	reveal.add_child(hold_timer)
	var holding := [false]
	reveal.button_down.connect(func() -> void:
		holding[0] = true
		hold_timer.start()
	)
	reveal.button_up.connect(func() -> void:
		holding[0] = false
		hold_timer.stop()
		if is_instance_valid(role_card):
			role_card.text = "ROLE HIDDEN"
			role_card.add_theme_color_override("font_color", Color("f4c95d"))
			role_detail.text = "Hold to reveal"
	)
	hold_timer.timeout.connect(func() -> void:
		if holding[0] and is_instance_valid(role_card):
			role_card.text = private_state.role
			role_card.add_theme_color_override("font_color", Color("ef6f6c") if is_informant else Color("f4c95d"))
			role_detail.text = private_state.ability
			_vibrate(35)
	)
	var mode_note := "This is a cooperative heist: there is no Informant." if snapshot.mode == "cooperative" else "One player is a hidden Informant."
	_online_text(mode_note, Color("8fa3bf"))
	_add_ready_button("I've seen my role; continue")

func _show_online_briefing(snapshot: Dictionary) -> void:
	subtitle_label.text = "ONLINE • MISSION BRIEFING"
	var mission: Dictionary = snapshot.mission
	_online_heading(mission.title, Color("f4c95d"), 34)
	_online_text("OBJECTIVE\n%s" % mission.objective, Color("e6ebf2"), 21)
	_online_text("KNOWN COMPLICATION\n%s" % mission.complication, Color("ef6f6c"), 21)
	_online_text("Three decisions stand between the crew and a clean extraction. Every vote matters.", Color("8fa3bf"))
	_add_ready_button("Continue to planning")

func _show_online_planning(snapshot: Dictionary) -> void:
	subtitle_label.text = "ONLINE • ROUND %d OF %d • PLANNING" % [snapshot.round, snapshot.total_rounds]
	_online_text("Talk it through. Costs always apply; risk shapes suspicion.")
	_add_online_plan_cards(snapshot, false)
	_add_ready_button("Ready to vote")

func _show_online_voting(snapshot: Dictionary) -> void:
	subtitle_label.text = "ONLINE • ROUND %d • SECRET BALLOT" % snapshot.round
	if multiplayer_flow.has_voted():
		_online_text("Your vote is locked in. Votes stay hidden until everyone has chosen.", Color("62d6a7"))
	else:
		_online_text("Choose one plan. Votes stay hidden until everyone has chosen.")
	_add_online_ability_controls(snapshot)
	if bool(multiplayer_flow.match_private.get("sabotage_available", false)):
		var sabotage := Button.new()
		sabotage.toggle_mode = true
		sabotage.text = "Sabotage armed • +2 suspicion" if online_sabotage_armed else "Arm sabotage • +2 suspicion"
		sabotage.custom_minimum_size = Vector2(0, 64)
		sabotage.add_theme_color_override("font_color", Color("ef6f6c"))
		sabotage.button_pressed = online_sabotage_armed
		sabotage.toggled.connect(func(pressed: bool) -> void:
			online_sabotage_armed = pressed
			sabotage.text = "Sabotage armed • +2 suspicion" if pressed else "Arm sabotage • +2 suspicion"
		)
		content.add_child(sabotage)
		_online_text("Available once per match, before your vote.", Color("ef6f6c"), 16)
	_add_online_plan_cards(snapshot, not multiplayer_flow.has_voted())

func _add_online_ability_controls(snapshot: Dictionary) -> void:
	var private_state: Dictionary = multiplayer_flow.match_private
	if private_state.is_empty() or multiplayer_flow.is_informant():
		return
	if not str(private_state.get("ability_details", "")).is_empty():
		_online_text("YOUR ABILITY: %s" % private_state.ability_details, Color("62d6a7"), 16)
	if not bool(private_state.get("ability_available", false)):
		_online_text("ABILITY CHARGE 0/1 • Used", Color("8fa3bf"), 16)
		return
	_online_text("ABILITY CHARGE 1/1 • %s" % private_state.ability, Color("f4c95d"), 16)
	var ability_icon := _ability_icon(private_state.role)
	if private_state.role == "Hacker":
		for plan in snapshot.plans:
			if not GameState.DIGITAL_PLAN_IDS.has(plan.id):
				continue
			var target_id: String = plan.id
			var target_button := Button.new()
			target_button.text = "%s Hack %s" % [ability_icon, plan.title]
			target_button.custom_minimum_size = Vector2(0, 60)
			target_button.pressed.connect(func() -> void:
				target_button.disabled = true
				if not multiplayer_flow.use_ability(target_id):
					target_button.disabled = false
			)
			content.add_child(target_button)
	else:
		var ability_button := Button.new()
		ability_button.text = "%s Use %s ability" % [ability_icon, private_state.role]
		ability_button.custom_minimum_size = Vector2(0, 60)
		ability_button.pressed.connect(func() -> void:
			ability_button.disabled = true
			if not multiplayer_flow.use_ability():
				ability_button.disabled = false
		)
		content.add_child(ability_button)

func _ability_icon(role: String) -> String:
	match role:
		"Hacker": return "⌘"
		"Driver": return "➜"
		"Inside Agent": return "◆"
		"Security Specialist": return "◈"
		"Fixer": return "✦"
	return "●"

func _add_online_plan_cards(snapshot: Dictionary, voting: bool) -> void:
	var cards := GridContainer.new()
	cards.columns = 1 if size.x < 700 else 3
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	var my_vote: Variant = multiplayer_flow.match_private.get("vote")
	for plan in snapshot.plans:
		var card: VBoxContainer = _make_plan_card(plan, false)
		if voting:
			var choose := Button.new()
			choose.text = "Vote for this plan"
			choose.custom_minimum_size = Vector2(0, 56)
			choose.disabled = not multiplayer_flow.can_act()
			var plan_id: String = plan.id
			choose.pressed.connect(func() -> void:
				choose.disabled = true
				var sabotage_available: bool = bool(multiplayer_flow.match_private.get("sabotage_available", false))
				if not multiplayer_flow.vote(plan_id, online_sabotage_armed and sabotage_available):
					choose.disabled = false
			)
			card.add_child(choose)
		elif my_vote != null and my_vote == plan.id:
			var chosen := Label.new()
			chosen.text = "✓ Your vote"
			chosen.add_theme_color_override("font_color", Color("62d6a7"))
			card.add_child(chosen)
		cards.add_child(card)

func _show_online_resolution(snapshot: Dictionary) -> void:
	online_sabotage_armed = false
	var result: Dictionary = snapshot.last_result
	subtitle_label.text = "ONLINE • ROUND %d • MISSION CONSEQUENCES" % result.round
	_online_heading("SUCCESS" if result.success else "FAILURE", Color("62d6a7") if result.success else Color("ef6f6c"), 36)
	_online_text("Selected plan: %s  •  Deterministic score: %d/100" % [result.plan_title, result.score], Color("e6ebf2"), 22)
	var tally_parts: Array[String] = []
	for plan in snapshot.plans:
		tally_parts.append("%s: %d" % [plan.title, result.tallies.get(plan.id, 0)])
	if snapshot.round == result.round:
		_online_text("Vote tally — %s" % "  •  ".join(tally_parts))
	if result.was_tie:
		_online_text("Tie resolved by the standing rule: lowest-risk tied plan, then card order.", Color("f4c95d"))
	_online_text(result.consequence, Color("e6ebf2"), 20)
	if result.mission_failed:
		_online_text(result.failure_reason, Color("ef6f6c"), 20)
	var label_text: String = "Continue to round %d" % (int(snapshot.round) + 1)
	if result.mission_failed or snapshot.round >= snapshot.total_rounds:
		label_text = "View mission outcome"
	_add_ready_button(label_text)

func _show_online_accusation(snapshot: Dictionary) -> void:
	subtitle_label.text = "ONLINE • FINAL ACCUSATION • PRIVATE VOTE"
	if multiplayer_flow.is_informant():
		_online_heading("The crew is deciding who betrayed them.", Color("ef6f6c"), 26)
		_online_text("Stay calm. You do not vote in the accusation.", Color("8fa3bf"))
		return
	if multiplayer_flow.has_accused():
		var accused: int = int(multiplayer_flow.match_private.accusation)
		_online_heading("You accused %s." % snapshot.seats[accused].name, Color("f4c95d"), 26)
		_online_text("Waiting for the rest of the crew to decide.", Color("8fa3bf"))
		return
	_online_heading("Who was the Informant?", Color("f4c95d"), 30)
	_online_text("Your accusation is private. You cannot vote for yourself.", Color("8fa3bf"))
	var suspects := GridContainer.new()
	suspects.columns = 2 if size.x < 700 else 3
	content.add_child(suspects)
	for seat in snapshot.seats:
		var suspect_seat: int = seat.seat
		if suspect_seat == multiplayer_flow.my_seat():
			continue
		var accuse := Button.new()
		var suspect_name: String = seat.name
		accuse.text = "◉ %s\n%s" % [suspect_name.substr(0, 1).to_upper(), suspect_name]
		accuse.custom_minimum_size = Vector2(0, 84)
		accuse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accuse.disabled = not multiplayer_flow.can_act()
		accuse.pressed.connect(func() -> void:
			_show_mobile_overlay("Confirm private accusation", "Accuse %s of being the Informant?" % suspect_name, "Yes, accuse", func() -> void:
				if not multiplayer_flow.accuse(suspect_seat):
					status_label.text = "Could not submit that accusation. Please try again."
			, "No")
		)
		suspects.add_child(accuse)

func _show_online_recap(snapshot: Dictionary) -> void:
	var outcome: Dictionary = snapshot.outcome
	subtitle_label.text = "ONLINE • MISSION COMPLETE • %d ROUND%s RESOLVED" % [outcome.history.size(), "" if outcome.history.size() == 1 else "S"]
	var winner: String = outcome.winner
	var headline := "THE CREW LOSES"
	match winner:
		"Crew": headline = "THE CREW WINS"
		"Informant": headline = "THE INFORMANT WINS"
		"Everyone": headline = "EVERYONE WINS"
	_online_heading(headline, Color("62d6a7") if winner == "Crew" or winner == "Everyone" else Color("ef6f6c"), 36)
	var meters_data: Dictionary = snapshot.meters
	_online_text("%d of %d plans succeeded. Final time: %d. Final suspicion: %d. Resources left: %d." % [outcome.successful_rounds, snapshot.total_rounds, meters_data.time, meters_data.suspicion, meters_data.resources], Color("e6ebf2"), 21)
	var lines: Array[String] = []
	lines.append("WINNING SIDE: %s" % winner.to_upper())
	lines.append("MISSION: Collapsed — %s" % outcome.failure_reason if outcome.mission_failed else "MISSION: Completed")
	lines.append("SABOTAGE USED: %s" % ("Yes" if outcome.sabotage_used else "No"))
	lines.append("")
	lines.append("ROLES")
	for role in outcome.roles:
		var you := " (you)" if role.seat == multiplayer_flow.my_seat() else ""
		lines.append("• %s%s — %s" % [snapshot.seats[role.seat].name, you, role.role])
	lines.append("")
	lines.append("MISSION RESULTS")
	for entry in outcome.history:
		lines.append("• Round %d: %s — %s (%d/100)" % [entry.round, entry.plan_title, "Success" if entry.success else "Failure", entry.score])
	lines.append("")
	lines.append("ACCUSATION TOTALS")
	if outcome.accusation == null:
		lines.append("• Skipped")
	else:
		var accusation: Dictionary = outcome.accusation
		for seat in snapshot.seats:
			lines.append("• %s: %d" % [seat.name, accusation.totals[seat.seat]])
		if accusation.tied:
			lines.append("Result: Tie — accusation failed")
		else:
			lines.append("Accused: %s" % snapshot.seats[int(accusation.accused_seat)].name)
	_online_text("\n".join(lines), Color("e6ebf2"), 15)
	_add_ready_button("Back to the waiting room")

func _show_lobby() -> void:
	_clear_content()
	subtitle_label.text = "LOCAL PROTOTYPE • LOBBY"

	var instruction := Label.new()
	instruction.text = "Add 3–6 players. Four or more activates the hidden Informant."
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_font_size_override("font_size", 20)
	content.add_child(instruction)

	var entry_row := GridContainer.new()
	entry_row.columns = 1 if size.x < 700 else 2
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
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	privacy.add_theme_font_size_override("font_size", 26)
	content.add_child(privacy)

	var role_card := Label.new()
	role_card.text = "ROLE HIDDEN"
	role_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_card.custom_minimum_size = Vector2(0, 230)
	role_card.add_theme_font_size_override("font_size", 34)
	role_card.add_theme_color_override("font_color", Color("f4c95d"))
	content.add_child(role_card)

	var action_button := Button.new()
	action_button.text = "Hold to reveal my role"
	action_button.custom_minimum_size = Vector2(0, 72)
	content.add_child(action_button)
	var next_button := Button.new()
	next_button.text = "Hide and pass"
	next_button.disabled = true
	content.add_child(next_button)
	var hold_timer := Timer.new()
	hold_timer.one_shot = true
	hold_timer.wait_time = 0.45
	action_button.add_child(hold_timer)
	action_button.button_down.connect(func() -> void:
		role_is_visible = true
		hold_timer.start()
	)
	action_button.button_up.connect(func() -> void:
		role_is_visible = false
		hold_timer.stop()
		if is_instance_valid(role_card):
			role_card.text = "ROLE HIDDEN"
	)
	hold_timer.timeout.connect(func() -> void:
		if role_is_visible and is_instance_valid(role_card):
			role_card.text = "%s\n\n%s" % [player.role, player.ability]
			next_button.disabled = false
			_vibrate(35)
	)
	next_button.pressed.connect(_advance_role_reveal)

func _advance_role_reveal() -> void:
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
	mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	next_step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var meters := GridContainer.new()
	meters.columns = 1 if size.x < 700 else 3
	meters.add_theme_constant_override("separation", 24)
	content.add_child(meters)
	meters.add_child(_make_meter("TIME", game.time_remaining, GameState.MAX_TIME, Color("56cfe1")))
	meters.add_child(_make_meter("SUSPICION", game.suspicion, GameState.MAX_SUSPICION, Color("ef6f6c")))
	meters.add_child(_make_meter("RESOURCES", game.resources, GameState.MAX_RESOURCES, Color("f4c95d")))

func _make_meter(label_text: String, value: int, maximum: int, color: Color, compact: bool = false) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "%s\n%d/%d" % [label_text, value, maximum] if compact else "%s  %d/%d" % [label_text, value, maximum]
	if compact:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10 if compact else 16)
	box.add_child(bar)
	return box

func _show_planning() -> void:
	_clear_content()
	subtitle_label.text = "ROUND %d OF %d • PLANNING" % [game.current_round, GameState.TOTAL_ROUNDS]
	_add_meters()

	var prompt := Label.new()
	prompt.text = "Review the options together. Costs always apply; risk shapes suspicion."
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 18)
	content.add_child(prompt)

	var cards := GridContainer.new()
	cards.columns = 1 if size.x < 700 else 3
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
	costs.text = "Time −%d  •  Resources −%d  •  Risk %d" % [plan.time_cost, plan.resource_cost, game.effective_risk(plan)]
	costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	costs.add_theme_color_override("font_color", Color("8fa3bf"))
	card.add_child(costs)
	if voting:
		var choose := Button.new()
		choose.text = "Vote for this plan"
		choose.custom_minimum_size = Vector2(0, 56)
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
	_add_meters()
	var instruction := Label.new()
	instruction.text = "Pass the screen to %s. Choose one plan; votes stay hidden until everyone finishes." % voter.name
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 21)
	content.add_child(instruction)
	_add_local_ability_controls(voter)
	if game.is_informant(voter.id) and not game.informant_sabotage_used:
		var sabotage := Button.new()
		sabotage.text = "Sabotage this round"
		sabotage.custom_minimum_size = Vector2(0, 56)
		sabotage.add_theme_color_override("font_color", Color("ef6f6c"))
		sabotage.pressed.connect(_arm_sabotage.bind(voter.id, sabotage))
		content.add_child(sabotage)
	var cards := GridContainer.new()
	cards.columns = 1 if size.x < 700 else 3
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	for plan in game.get_current_plans():
		cards.add_child(_make_plan_card(plan, true))

func _add_local_ability_controls(voter: Dictionary) -> void:
	if game.is_informant(voter.id):
		return
	if int(voter.get("ability_round", -1)) == game.current_round and not str(voter.get("ability_details", "")).is_empty():
		_online_text("YOUR ABILITY: %s" % voter.ability_details, Color("62d6a7"), 16)
	if not game.ability_available(voter.id):
		_online_text("ABILITY CHARGE 0/1 • Used", Color("8fa3bf"), 16)
		return
	_online_text("ABILITY CHARGE 1/1 • %s" % voter.ability, Color("f4c95d"), 16)
	var ability_icon := _ability_icon(voter.role)
	if voter.role == "Hacker":
		for plan in game.get_current_plans():
			if not GameState.DIGITAL_PLAN_IDS.has(plan.id):
				continue
			var target_id: String = plan.id
			var target_button := Button.new()
			target_button.text = "%s Hack %s" % [ability_icon, plan.title]
			target_button.custom_minimum_size = Vector2(0, 60)
			target_button.pressed.connect(_use_local_ability.bind(voter.id, target_id))
			content.add_child(target_button)
	else:
		var ability_button := Button.new()
		ability_button.text = "%s Use %s ability" % [ability_icon, voter.role]
		ability_button.custom_minimum_size = Vector2(0, 60)
		ability_button.pressed.connect(_use_local_ability.bind(voter.id, ""))
		content.add_child(ability_button)

func _use_local_ability(player_id: int, target_plan_id: String) -> void:
	var result := game.use_ability(player_id, target_plan_id)
	if not result.ok:
		status_label.text = result.error
		return
	_show_voting()

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
	selected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		tie_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		failure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		failure.add_theme_font_size_override("font_size", 20)
		failure.add_theme_color_override("font_color", Color("ef6f6c"))
		content.add_child(failure)

	var continue_button := Button.new()
	if game.current_round < GameState.TOTAL_ROUNDS and not game.mission_failed:
		continue_button.text = "Continue to round %d" % (game.current_round + 1)
	elif game.informant_player_id != -1 and game.mission_succeeded():
		continue_button.text = "Proceed to accusation"
	else:
		continue_button.text = "View mission outcome"
	continue_button.pressed.connect(_continue_after_resolution)
	content.add_child(continue_button)

func _continue_after_resolution() -> void:
	if game.advance_after_resolution():
		_show_planning()
	elif game.phase == GameState.Phase.ACCUSATION:
		accusation_index = 0
		_show_accusation()
	else:
		_show_mission_summary()

func _show_accusation() -> void:
	_clear_content()
	subtitle_label.text = "FINAL ACCUSATION • PRIVATE VOTE"
	var voters := game.get_accusation_voters()
	var voter: Dictionary = voters[accusation_index]
	var instruction := Label.new()
	instruction.text = "Pass the screen to %s. Who was the Informant?" % voter.name
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 24)
	content.add_child(instruction)

	var privacy := Label.new()
	privacy.text = "Your accusation is private. You cannot vote for yourself."
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	privacy.add_theme_color_override("font_color", Color("8fa3bf"))
	content.add_child(privacy)

	var suspects := GridContainer.new()
	suspects.columns = 2 if size.x < 700 else 3
	content.add_child(suspects)
	for suspect in game.players:
		if suspect.id == voter.id:
			continue
		var suspect_name: String = suspect.name
		var suspect_id: int = suspect.id
		var accuse_button := Button.new()
		accuse_button.text = "◉ %s\n%s" % [suspect_name.substr(0, 1).to_upper(), suspect_name]
		accuse_button.custom_minimum_size = Vector2(0, 84)
		accuse_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accuse_button.pressed.connect(func() -> void:
			_show_mobile_overlay("Confirm private accusation", "Accuse %s of being the Informant?" % suspect_name, "Yes, accuse", func() -> void:
				_cast_accusation(voter.id, suspect_id)
			, "No")
		)
		suspects.add_child(accuse_button)

func _cast_accusation(voter_id: int, suspect_id: int) -> void:
	var result := game.cast_accusation_vote(voter_id, suspect_id)
	if not result.ok:
		status_label.text = result.error
		return
	accusation_index += 1
	if result.complete:
		game.resolve_accusation()
		_show_mission_summary()
	else:
		_show_accusation()

func _show_mission_summary() -> void:
	_clear_content()
	subtitle_label.text = "MISSION COMPLETE • %d ROUND%s RESOLVED" % [game.round_history.size(), "" if game.round_history.size() == 1 else "S"]
	_add_meters()
	var headline := Label.new()
	match game.winner:
		"Crew": headline.text = "THE CREW WINS"
		"Informant": headline.text = "THE INFORMANT WINS"
		"Everyone": headline.text = "EVERYONE WINS"
		_: headline.text = "THE CREW LOSES"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.add_theme_font_size_override("font_size", 36)
	headline.add_theme_color_override("font_color", Color("62d6a7") if game.winner == "Crew" or game.winner == "Everyone" else Color("ef6f6c"))
	content.add_child(headline)
	var summary := Label.new()
	summary.text = "%d of %d plans succeeded. Final time: %d. Final suspicion: %d. Resources left: %d." % [game.successful_rounds(), GameState.TOTAL_ROUNDS, game.time_remaining, game.suspicion, game.resources]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 21)
	content.add_child(summary)
	var recap_lines: Array[String] = []
	recap_lines.append("WINNING SIDE: %s" % game.winner.to_upper())
	if game.mission_failed:
		recap_lines.append("MISSION: Collapsed — %s" % game.failure_reason)
	else:
		recap_lines.append("MISSION: Completed")
	recap_lines.append("SABOTAGE USED: %s" % ("Yes" if game.informant_sabotage_used else "No"))
	recap_lines.append("")
	recap_lines.append("ROLES")
	for player in game.players:
		recap_lines.append("• %s — %s" % [player.name, player.role])
	recap_lines.append("")
	recap_lines.append("MISSION RESULTS")
	for result in game.round_history:
		recap_lines.append("• Round %d: %s — %s (%d/100)" % [result.round, result.plan.title, "Success" if result.success else "Failure", result.score])
	recap_lines.append("")
	recap_lines.append("ACCUSATION TOTALS")
	if game.accusation_totals.is_empty():
		recap_lines.append("• Skipped")
	else:
		for player in game.players:
			recap_lines.append("• %s: %d" % [player.name, game.accusation_totals.get(player.id, 0)])
		if game.accusation_tied:
			recap_lines.append("Result: Tie — accusation failed")
		else:
			recap_lines.append("Accused: %s" % game.get_player(game.accused_player_id).name)
	var recap := Label.new()
	recap.text = "\n".join(recap_lines)
	recap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recap.add_theme_font_size_override("font_size", 15)
	content.add_child(recap)

	var new_game_button := Button.new()
	new_game_button.text = "Start a new game"
	new_game_button.pressed.connect(_start_new_game)
	content.add_child(new_game_button)

func _start_new_game() -> void:
	game.reset_game()
	reveal_index = 0
	role_is_visible = false
	vote_index = 0
	accusation_index = 0
	latest_result.clear()
	_show_lobby()
