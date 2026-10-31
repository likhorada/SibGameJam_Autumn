extends Node
## Shared native/Web world checks. Only native requests synthetic pointer capture.

var failures: int = 0
var game: Node3D


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("NEIGHBOR: " + message)


func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().physics_frame


func setup() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.02
	game.threats.set_event_enabled(&"power_outage", false)
	game.threats.set_process(false)
	game.threats.set_event_enabled(&"police_raid", false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	await frames()


func key_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func can_capture() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless"


func place(position: Vector3, yaw: float) -> void:
	game.player.position = position
	game.player.rotation = Vector3(0, yaw, 0)
	game.player.head.rotation = Vector3.ZERO
	game.player.stop_motion(true)
	await frames()


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/neighbor_" + name + ".png")


func finish_closed_visit() -> void:
	game.threats.advance(game.neighbor.settings.rattle_seconds)
	expect(game.neighbor.visit == PsychNeighbor.Visit.DEPARTING, "Closed door sends neighbor away")
	game.threats.advance(game.neighbor.settings.departure_seconds)
	expect(game.threats.state == ThreatManager.State.RESOLVED and not game.neighbor.visual.visible, "Neighbor disappears only after leaving")
	game.threats.advance(1.0)
	expect(not game.threats.is_busy() and game.threats.safe_seconds_left == 20.0, "Finished visit returns to idle and safety interval")


func _run() -> void:
	TranslationServer.set_locale("ru")
	await setup()
	var manager: ThreatManager = game.threats
	var neighbor: PsychNeighbor = game.neighbor
	var door: RoomDoor = game.room_door
	expect(not door.is_open and not neighbor.visual.visible, "New run starts with closed door and no visible neighbor")
	expect(door.open_sound != null and door.open_sound.resource_path == "res://assets/audio/door_click.wav" and door.close_sound != null and door.close_sound.resource_path == "res://assets/audio/door_click.wav", "Door opening and closing use door_click.wav")
	await place(Vector3(1.5, 0.02, 1.1), -PI * 0.5)
	expect(game.player.find_interaction() == &"room_door", "Existing physical interaction ray finds closed door")
	await capture("closed_door")
	if can_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await frames()
		key_e()
		await frames()
		expect(door.is_open, "Real E input opens door through existing interaction")
	else:
		expect(door.set_open(true), "Door opens in shared world")
	await place(Vector3(2.3, 0.02, 0.6), PI)
	expect(game.player.find_interaction() == &"room_door", "Open door remains reachable by interaction ray")
	if can_capture():
		key_e()
		await frames()
		expect(not door.is_open, "Real E input closes open leaf")
	else:
		door.set_open(false)
	await place(Vector3(1.5, 0.02, 1.1), -PI * 0.5)
	if can_capture():
		Input.action_press("move_forward")
		await frames(35)
		Input.action_release("move_forward")
		expect(game.player.position.x < 2.75, "Closed door physically blocks walking into corridor")
	await place(Vector3(1.5, 0.02, 1.1), -PI * 0.5)
	expect(door.set_open(true), "Door opens without trapping the player")
	if can_capture():
		Input.action_press("move_forward")
		await frames(60)
		Input.action_release("move_forward")
		expect(game.player.position.x > 3.3, "Open doorway permits walking to corridor")
	await place(Vector3(3.0, 0.02, 1.1), 0.0)
	expect(not door.set_open(false) and door.is_open and door.blocked_seconds_left > 0.0, "Door refuses to close through player standing in threshold")
	await place(Vector3(1.5, 0.02, 1.1), -PI * 0.5)
	expect(door.set_open(false), "Door closes normally after stepping away")
	expect(game.trigger_neighbor(), "Forced command starts visit during protected briefing")
	expect(manager.state == ThreatManager.State.WARNING and neighbor.footsteps_audio.playing, "Approach starts audible footsteps before danger")
	manager.advance(5.0)
	expect(manager.state == ThreatManager.State.ACTIVE and neighbor.visit == PsychNeighbor.Visit.RATTLING, "Closed door leads to handle attempt, not death")
	var handle_path := ""
	if neighbor.handle_audio.stream != null:
		handle_path = neighbor.handle_audio.stream.resource_path
	expect(
		neighbor.handle_audio.playing
		and handle_path in ["res://assets/audio/scratchin1.wav", "res://assets/audio/scratchin2.wav"],
		"Handle warning randomly uses one of the scratch WAVs"
	)
	game.power.trigger_outage()
	expect(game.power.powered, "Neighbor reserves slot against real power outages")
	finish_closed_visit()
	expect(not game.run_ended, "Closed door protects player")
	expect(game.trigger_neighbor(), "Visit can repeat after earlier departure")
	manager.advance(5.0)
	door.set_open(true)
	expect(neighbor.visit == PsychNeighbor.Visit.ENTERING, "Opening while neighbor rattles starts entry")
	manager.advance(2.9)
	expect(not game.run_ended, "Full three-second last-chance window is available")
	await capture("last_chance")
	door.set_open(false)
	expect(neighbor.visit == PsychNeighbor.Visit.RATTLING and neighbor.entry_seconds == 0.0, "Last-moment close cancels entry")
	manager.advance(neighbor.settings.rattle_seconds)
	expect(neighbor.visit == PsychNeighbor.Visit.DEPARTING, "Rescued visit continues to departure")
	door.set_open(true)
	expect(neighbor.visit == PsychNeighbor.Visit.ENTERING, "Reopening before steps are gone remains dangerous")
	door.set_open(false)
	finish_closed_visit()
	expect(not game.run_ended, "Rescue survives through the entire visit")
	game.trigger_neighbor()
	manager.set_event_enabled(&"psych_neighbor", false)
	expect(not manager.is_busy() and not neighbor.visual.visible and not neighbor.footsteps_audio.playing and not neighbor.handle_audio.playing, "Per-threat disable cleans warning, silhouette and sounds")
	expect(not game.trigger_neighbor(), "Disabled neighbor cannot be forced")
	manager.set_event_enabled(&"psych_neighbor", true)
	expect(game.trigger_neighbor(), "Re-enabled neighbor can be tested again")
	game.disable_threats()
	expect(not manager.is_busy() and not neighbor.visual.visible and not neighbor.footsteps_audio.playing, "DisableThreats safely cancels active visit")
	# Virtual note uses its own read-only app, preserving the player's editable notes.
	game.terminal_ui.notepad.editor.text = "my evidence"
	game.enter_computer()
	await get_tree().create_timer(0.1).timeout
	game.terminal_ui.launch_app(&"night_note")
	expect(game.terminal_ui.night_note.text.contains("сосед") and game.terminal_ui.night_note.text.contains("полиция") and game.terminal_ui.night_note.text.contains("фонарь"), "Atmospheric TXT describes all three agreed threats")
	expect(game.terminal_ui.notepad.editor.text == "my evidence", "Reading TXT never overwrites player notes")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	expect(game.terminal_ui.night_note.text.contains("neighbor") and game.terminal_ui.night_note.text.contains("police"), "TXT updates on language change")
	await capture("night_txt")
	TranslationServer.set_locale("ru")
	game.queue_free()
	await get_tree().process_frame
	await setup()
	manager = game.threats
	neighbor = game.neighbor
	door = game.room_door
	await place(Vector3(4.3, 0.02, -4.0), PI - 0.08)
	door.set_open(true)
	game.trigger_neighbor()
	manager.advance(5.0)
	await capture("silhouette")
	manager.advance(3.0)
	expect(game.run_ended and game.failure_reason == "NEIGHBOR_DEATH" and game.process_mode == Node.PROCESS_MODE_DISABLED, "Open door kills at threshold, even when player is outside room")
	expect(not neighbor.visual.visible and not neighbor.footsteps_audio.playing and not manager.is_busy(), "Death cleans neighbor and audio")
	var death_text := ""
	for label: Label in game.find_children("*", "Label", true, false):
		death_text += label.text
	expect(death_text.contains(tr("NEIGHBOR_DEATH")) and not death_text.contains(tr("CHAT_RESULT") % [0, 3]), "Existing result screen shows death cause, not quiz score")
	await capture("death")
	var restart: Button = get_viewport().gui_get_focus_owner()
	expect(restart != null and restart.text == tr("CHAT_RESTART"), "Death focuses existing restart button")
	restart.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	game = get_tree().current_scene
	game.threats.set_process(false)
	game.threats.set_event_enabled(&"police_raid", false)
	game.threats.set_event_enabled(&"power_outage", false)
	expect(not game.run_ended and game.failure_reason.is_empty() and not game.room_door.is_open and game.neighbor.visit == PsychNeighbor.Visit.DORMANT and not game.threats.is_busy(), "Real restart creates closed door, clean neighbor and fresh run")
	game.shift.set_process(false)
	game.threats.run_seconds = 46.0
	game.threats.wait_seconds_left = 0.1
	game._physics_process(0.0)
	game.threats.advance(1.0)
	expect(not game.threats.is_busy(), "Real neighbor cannot randomly appear before ALARM.sh")
	game.shift.state = ShiftDirector.State.ROUTE
	game._physics_process(0.0)
	game.threats.advance(1.0)
	expect(game.threats.active_id == &"psych_neighbor" and game.neighbor.visit == PsychNeighbor.Visit.APPROACHING, "Eligible random scheduler selects real neighbor after ALARM.sh")
	game.threats.set_event_enabled(&"psych_neighbor", false)
	game.threats.set_event_enabled(&"psych_neighbor", true)
	game.shift.state = ShiftDirector.State.INTRO
	game._physics_process(0.0)
	game.dev_menu.open_menu()
	await get_tree().process_frame
	if not OS.has_feature("web"):
		var previous_size := get_tree().root.size
		get_tree().root.size = Vector2i(640, 360)
		await frames()
		var menu_rect: Rect2 = game.dev_menu._scroll.get_global_rect()
		# canvas_items keeps 1280x720 logical coordinates in the half-size window.
		expect(menu_rect.position.y >= 0.0 and menu_rect.end.y <= get_viewport().get_visible_rect().size.y, "Scrollable dev panel stays within resized 640x360 viewport")
		get_tree().root.size = previous_size
		await frames()
	var trigger: Button
	var disable: Button
	for button: Button in game.dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "TriggerNeighbor":
			trigger = button
		elif button.text == "DisableThreats":
			disable = button
	expect(trigger != null and disable != null, "Dev menu exposes both required test commands")
	trigger.pressed.emit()
	expect(not game.dev_menu.is_open and game.threats.active_id == &"psych_neighbor", "Dev trigger closes overlay and starts real neighbor")
	game.dev_menu.open_menu()
	disable.pressed.emit()
	expect(not game.threats.enabled and not game.threats.is_busy(), "Dev DisableThreats cleans real event")
	game.queue_free()
	await get_tree().process_frame
	print("NEIGHBOR SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
