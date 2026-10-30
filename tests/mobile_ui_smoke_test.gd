extends SceneTree

const MainScript = preload("res://scripts/main.gd")
const RoomNetworkClientScript = preload("res://scripts/room_network_client.gd")
const MultiplayerFlowScript = preload("res://scripts/multiplayer_flow.gd")

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Control = MainScript.new()
	root.add_child(main)
	var client: Node = RoomNetworkClientScript.new()
	root.add_child(client)
	var flow: Node = MultiplayerFlowScript.new(client)
	root.add_child(flow)
	main.multiplayer_flow = flow
	main.room_client = client
	flow.state = MultiplayerFlowScript.State.MATCH
	flow.match_private = {"seat": 0, "role": "Informant", "ability": "Sabotage once"}
	flow.match_snapshot = {"phase": "role_reveal", "round": 1, "seats": [{"ready": false}]}
	main._clear_content()
	main._show_online_role({"mode": "social"})
	var role_card: Label = null
	var reveal_button: Button = null
	for child in main.content.get_children():
		if child is Label and child.text == "ROLE HIDDEN":
			role_card = child
		if child is Button and child.text == "Hold to reveal role":
			reveal_button = child
	_assert(role_card != null and reveal_button != null, "Online role starts covered")
	reveal_button.button_down.emit()
	await create_timer(0.2).timeout
	_assert(role_card.text == "ROLE HIDDEN", "Short press does not reveal role")
	await create_timer(0.35).timeout
	_assert(role_card.text == "Informant", "Holding reveals role")
	reveal_button.button_up.emit()
	_assert(role_card.text == "ROLE HIDDEN", "Releasing covers role again")
	_assert(main._clean_room_code("a!b-c234") == "ABC234", "Room code input strips unsupported characters")
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/match_contract.json"))
	flow.match_private = contract.valid_private.crew.payload.duplicate(true)
	flow.match_snapshot = contract.valid_public.social_voting.payload.duplicate(true)
	main.privacy_mode = true
	main._render_multiplayer_state()
	_assert(not main.content.visible and main.privacy_notice.visible, "Privacy shroud covers private voting screen")
	_assert(main.subtitle_label.text == "ONLINE • PRIVACY SHROUD" and main.match_dashboard.find_children("*", "ProgressBar", true, false).is_empty(), "Privacy shroud covers phase and meters")
	main.privacy_mode = false
	main.notes_open = true
	main._render_multiplayer_state()
	_assert(main.content.visible and main.match_dashboard.visible, "Dashboard and notes render while voting")
	flow.match_private = contract.valid_private.informant.payload.duplicate(true)
	flow.match_private.sabotage_available = true
	main.notes_open = false
	main._render_multiplayer_state()
	var sabotage_buttons: Array = main.content.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Arm sabotage • +2 suspicion")
	_assert(sabotage_buttons.size() == 1 and sabotage_buttons[0].custom_minimum_size.y >= 60, "Informant sabotage has a large action target")
	sabotage_buttons[0].toggled.emit(true)
	_assert(main.online_sabotage_armed and sabotage_buttons[0].text.begins_with("Sabotage armed"), "Sabotage toggle clearly shows its armed state")
	flow.match_private = contract.valid_private.crew.payload.duplicate(true)
	main.online_sabotage_armed = false
	main.notes_open = true
	main._render_multiplayer_state()
	var note_buttons: Array = main.content.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "+ Suspicious action")
	_assert(not note_buttons.is_empty(), "One-tap deduction tags are available")
	note_buttons[0].pressed.emit()
	_assert(main.accusation_notes.get(0, []) == ["Suspicious action"], "A deduction tag stays on the selected suspect")
	flow.state = MultiplayerFlowScript.State.RECOVERING
	main._on_online_state_changed(flow.state)
	_assert(main.accusation_notes.size() == 1, "A brief reconnect preserves local notes")
	flow.state = MultiplayerFlowScript.State.MATCH
	main._on_online_state_changed(flow.state)
	flow.match_snapshot.phase = "accusation"
	main._render_multiplayer_state()
	var suspects: Array = main.content.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text.begins_with("◉"))
	_assert(suspects.size() == 3, "Accusation grid has three other players")
	suspects[0].pressed.emit()
	var confirmation_overlay: ColorRect = main.active_overlay
	var confirm_labels: Array = confirmation_overlay.find_children("*", "Label", true, false)
	_assert(confirm_labels.any(func(label: Label) -> bool: return label.text.begins_with("Accuse ")), "Accusation requires a readable in-game confirmation")
	var cancel_buttons: Array = confirmation_overlay.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "No")
	_assert(cancel_buttons.size() == 1, "Accusation confirmation has a No control")
	cancel_buttons[0].pressed.emit()
	await process_frame
	flow.match_snapshot = contract.valid_public.cooperative_resolution_failed.payload.duplicate(true)
	main.notes_open = false
	main._render_multiplayer_state()
	var complication_overlay: ColorRect = main.active_overlay
	var acknowledge: Array = complication_overlay.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Acknowledge")
	_assert(acknowledge.size() == 1, "Triggered complication has a visible acknowledgment control")
	await process_frame
	var button_bounds: Rect2 = acknowledge[0].get_global_rect()
	var viewport_bounds: Rect2 = main.get_viewport_rect()
	_assert(viewport_bounds.encloses(button_bounds), "Complication acknowledgment fits inside the viewport")
	main._render_multiplayer_state()
	_assert(main.active_overlay == complication_overlay, "Complication alert is not repeated on room revision")
	acknowledge[0].pressed.emit()
	_assert(main.active_overlay == null, "Acknowledgment clears the complication overlay")
	flow.state = MultiplayerFlowScript.State.LOBBY
	main._on_online_state_changed(flow.state)
	_assert(main.accusation_notes.is_empty(), "Returning to the waiting room clears local notes")
	main.game.add_player("Ada")
	main.game.add_player("Ben")
	main.game.add_player("Cy")
	main.game.start_match(main.rng)
	main.reveal_index = 0
	main._show_role_reveal()
	await process_frame
	var local_role_card: Label = null
	var local_reveal: Button = null
	for child in main.content.get_children():
		if child is Label and child.text == "ROLE HIDDEN":
			local_role_card = child
		if child is Button and child.text == "Hold to reveal my role":
			local_reveal = child
	_assert(local_role_card != null and local_reveal != null, "Pass-and-play role starts covered")
	local_reveal.button_down.emit()
	await create_timer(0.5).timeout
	_assert(local_role_card.text == "%s\n\n%s" % [main.game.players[0].role, main.game.players[0].ability], "Pass-and-play hold reveals only current role and ability")
	local_reveal.button_up.emit()
	_assert(local_role_card.text == "ROLE HIDDEN", "Pass-and-play release covers role")
	main.queue_free()
	client.queue_free()
	flow.queue_free()
	if failures == 0:
		print("Mobile UI smoke test passed")
	quit(1 if failures > 0 else 0)

func _assert(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)
		quit(1)
