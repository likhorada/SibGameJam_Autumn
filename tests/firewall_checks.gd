extends Node
var failures: int = 0
var game: Node3D
var director: AtmosphereDirector
var outcomes: Array[StringName] = []


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FIREWALL: " + message)


func frames(count: int = 3) -> void:
	for i: int in count:
		await get_tree().process_frame


func test_model() -> void:
	var config := FirewallBreachConfig.new()
	var puzzle := FirewallRound.new()
	puzzle.begin(config, 42)
	expect(puzzle.ports.size() == 9 and puzzle.open_count() == 6, "Six unique random open ports")
	var same := FirewallRound.new()
	same.begin(config, 42)
	expect(same.ports == puzzle.ports, "Seeded reproduction")
	expect(not puzzle.block_connection(), "Cannot block with red ports")
	var green := puzzle.ports.find(false)
	puzzle.toggle_port(green)
	expect(puzzle.open_count() == 7, "Clicking green opens it")
	puzzle.toggle_port(green)
	expect(puzzle.open_count() == 6, "Clicking red closes it")
	expect(not puzzle.toggle_port(-1) and not puzzle.toggle_port(9), "Reject invalid indices")
	var early := puzzle.interval_range()
	puzzle.elapsed = 14.9
	var late := puzzle.interval_range()
	expect(early == Vector2(1, 2) and late.x < early.x and late.y < early.y, "Attack ranges accelerate")
	puzzle.begin(config, 1)
	puzzle.attack_wait = 0.1
	for i: int in 9:
		if puzzle.ports[i]:
			puzzle.toggle_port(i)
	puzzle.advance(0.69)
	expect(puzzle.open_count() == 0, "Last closed port guarantees grace")
	puzzle.advance(0.02)
	expect(puzzle.open_count() == 1, "Hack resumes after grace")
	puzzle.toggle_port(puzzle.ports.find(true))
	expect(puzzle.block_connection() and puzzle.state == FirewallRound.State.WON, "All green plus explicit BLOCK wins")
	puzzle.advance(100)
	expect(puzzle.state == FirewallRound.State.WON and not puzzle.toggle_port(0), "Result is latched")
	puzzle.begin(config, 1)
	puzzle.advance(7)
	expect(puzzle.open_count() == 7, "Long frame opens only one port")
	puzzle.advance(-1)
	expect(puzzle.elapsed == 7, "Negative delta ignored")
	puzzle.advance(8)
	expect(puzzle.state == FirewallRound.State.LOST, "Deadline loses without BLOCK")
	config.initial_open_ports = 0
	puzzle.begin(config)
	puzzle.advance(15)
	expect(puzzle.state == FirewallRound.State.LOST, "All-green is not automatic victory")
	config.duration_seconds = 100
	puzzle.begin(config)
	expect(puzzle.duration == 19, "Round plus result cannot exceed twenty seconds")
	config.initial_open_ports = 9
	puzzle.begin(config)
	puzzle.advance(3)
	expect(puzzle.open_count() == 9, "No closed candidates is safe")


func make_game() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	var config := AtmosphereConfig.new()
	config.events.append(load("res://data/atmosphere/firewall_breach.tres"))
	game.atmosphere_config = config
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.02
	game.shift.set_process(false)
	game.threats.set_process(false)
	director = game.atmosphere
	director.set_process(false)
	director.event_finished.connect(func(id: StringName, outcome: StringName):
		if id == &"firewall_breach":
			outcomes.append(outcome))


func sit() -> void:
	game.enter_computer()
	await get_tree().create_timer(0.2).timeout
	expect(game.mode == game.Mode.COMPUTER, "Seat transition completes")
	await frames()


func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_tree().root.push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_tree().root.push_input(event)
	await frames(1)


func key(code: Key, unicode: int = 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = unicode if pressed else 0
		event.pressed = pressed
		get_tree().root.push_input(event)


func close_red_ports(event: FirewallBreach) -> void:
	for i: int in 9:
		if event.round_state.ports[i]:
			await click(event.view.port_buttons[i].get_global_rect().get_center())


func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/firewall_" + name + ".png")


func start_event() -> FirewallBreach:
	expect(director.request_event(&"firewall_breach", true), "Safe forced start succeeds")
	return director._active as FirewallBreach


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	test_model()
	make_game()
	var production: AtmosphereConfig = load("res://data/atmosphere/default.tres")
	expect(production.events.size() == 2 and production.events[0].weight == production.events[1].weight, "Production pool has equal weights")
	expect(not director.request_event(&"firewall_breach", true), "Walking cannot start PC puzzle")
	await sit()
	var ui: TerminalDesktop = game.terminal_ui
	ui.launch_app(&"calculator")
	ui.calculator.press("7")
	ui.calculator.press("3")
	ui.launch_app(&"cctv")
	ui.launch_app(&"notepad")
	ui.notepad.editor.text = "Preserve my evidence"
	var editor_id := ui.notepad.editor.get_instance_id()
	var marker := {"sender": "you", "text": "preserve chat history"}
	ui.chat.session.history.append(marker)
	ui.chat.session.answers["evidence"] = "kept"
	var trigger: Button
	for button: Button in game.dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "TriggerFirewallBreach":
			trigger = button
	expect(trigger != null, "Dedicated dev button exists")
	game.dev_menu.open_menu()
	trigger.pressed.emit()
	await frames()
	var event := director._active as FirewallBreach
	expect(event != null and ui.has_modal() and not game.dev_menu.is_open, "Dev starts modal puzzle")
	if event == null:
		get_tree().quit(1)
		return
	expect(event.round_state.open_count() == 6 and event.view.block_button.disabled, "Six red ports and disabled BLOCK")
	expect(not ui.notepad.editor.has_focus() and not ui.chat.input_enabled and not ui.cctv.input_enabled, "Underlying input is suspended")
	key(KEY_X, 120)
	await click(ui.start_button.get_global_rect().get_center())
	await click(ui.task_buttons[&"calculator"].get_global_rect().get_center())
	ui.launch_app(&"chat")
	expect(not ui.start_menu.visible and ui.active_app == &"notepad", "Shield and API prevent app/taskbar activation")
	expect(ui.notepad.editor.text == "Preserve my evidence" and ui.calculator.model.entry == "73", "Keys cannot edit hidden apps")
	expect(not game.trigger_police() and not game.trigger_power_outage(), "Threats cannot overlap")
	await snapshot("active")
	var green := event.round_state.ports.find(false)
	await click(event.view.port_buttons[green].get_global_rect().get_center())
	expect(event.round_state.open_count() == 7, "Real GUI green click opens port")
	event.round_state.attack_wait = 0.1
	await close_red_ports(event)
	expect(not event.view.block_button.disabled and event.round_state.open_count() == 0, "Real GUI clears grid and enables BLOCK")
	director.advance(0.69)
	expect(event.round_state.open_count() == 0, "UI grace window stays green")
	director.advance(0.02)
	expect(event.round_state.open_count() == 1 and event.view.block_button.disabled, "Reopening disables BLOCK")
	await close_red_ports(event)
	await snapshot("ready")
	await click(event.view.block_button.get_global_rect().get_center())
	expect(event.round_state.state == FirewallRound.State.WON and ui.has_modal(), "BLOCK wins and shows result")
	await snapshot("won")
	director.advance(0.99)
	expect(director.is_busy(), "Confirmation lasts one second")
	director.advance(0.02)
	expect(not director.is_busy() and outcomes.back() == &"won" and not ui.has_modal(), "Won result reaches director and unlocks PC")
	expect(ui.windows[&"notepad"].opened and ui.notepad.editor.has_focus(), "Victory restores existing apps and focus")
	await frames()

	event = start_event()
	ui.windows[&"calculator"].minimize()
	director.advance(15)
	expect(outcomes.back() == &"lost" and not ui.has_modal(), "Timeout publishes lost and unlocks PC")
	for window: DesktopAppWindow in ui.windows.values():
		expect(not window.opened and not window.visible and not window.minimized, "Loss closes all apps including minimized ones")
	expect(ui.notepad.editor.get_instance_id() == editor_id and ui.notepad.editor.text == "Preserve my evidence", "Loss preserves editor instance and text")
	expect(ui.calculator.model.entry == "73" and ui.chat.session.history.has(marker) and ui.chat.session.answers.evidence == "kept", "Loss preserves calculator/chat data")
	ui.launch_app(&"notepad")
	expect(ui.windows[&"notepad"].opened, "Apps reopen immediately after loss")
	await snapshot("lost")

	event = start_event()
	key(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	expect(game.mode == game.Mode.WALKING and not event.overlay.is_visible_in_tree(), "Esc leaves PC without ending event")
	var count := event.round_state.open_count()
	event.view.port_pressed.emit(0)
	expect(event.round_state.open_count() == count, "Hidden puzzle does not accept clicks")
	director.advance(1)
	expect(event.round_state.elapsed == 1 and director.is_busy(), "Clock continues while walking")
	await sit()
	expect(ui.has_modal() and event.overlay.is_visible_in_tree() and not ui.notepad.editor.has_focus(), "Return stays locked to puzzle")
	game.leave_computer(false)
	await get_tree().create_timer(0.2).timeout
	director.advance(14)
	expect(outcomes.back() == &"lost" and not ui.windows[&"notepad"].opened, "Outside-PC timeout also closes apps")
	await sit()
	ui.launch_app(&"notepad")

	for cancellation: StringName in [&"cancelled", &"quiz_started", &"disabled", &"timeout"]:
		event = start_event()
		director.cancel(cancellation)
		expect(not ui.has_modal() and ui.windows[&"notepad"].opened and ui.notepad.editor.text == "Preserve my evidence", "Technical cancellation never applies loss penalty")
		await frames()
	event = start_event()
	game.shift._begin_route(ShiftDirector.DATA.OFFICE)
	var position_before: Vector3 = game.shift.location.target.position
	game.shift.advance(0.5)
	expect(game.shift.location.target.position != position_before and director.is_busy(), "Observation route continues during puzzle")
	game.shift._finish_stage()
	expect(game.shift.state == ShiftDirector.State.EVENT, "Active puzzle fulfils transition")
	director.advance(15)
	game.shift._process(0)
	expect(game.shift.stage == 1 and not director.transition_pending, "Loss also releases next route")
	ui.launch_app(&"notepad")
	director.used.clear()
	director.start_run()
	# Emulate a freed transition reservation so the real handler enters random selection.
	director.reserves = [&"", &""]
	director.random_limit = 1
	director.clear_cooldown()
	director.advance(0.1)
	expect(director.active_id == &"firewall_breach" and director.random_count == 1, "Real firewall handler supports random scheduling")
	director.cancel()
	event = start_event()
	game.shift.state = ShiftDirector.State.REPORT
	game.shift._process(0)
	expect(not ui.has_modal() and ui.windows[&"notepad"].opened and ui.chat.session.quiz_started, "Actual report cancels without closing apps")
	game.queue_free()
	await frames()

	make_game()
	await sit()
	event = start_event()
	var overlay_ref: WeakRef = weakref(event.overlay)
	var audio_ref: WeakRef = weakref(event.audio)
	game._finish_report(false, 0)
	expect(not director.is_busy() and not game.terminal_ui.has_modal(), "Run end cleans modal before freezing")
	game.queue_free()
	await frames()
	expect(overlay_ref.get_ref() == null and audio_ref.get_ref() == null, "Teardown frees all event nodes")
	print("FIREWALL SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(0 if failures == 0 else 1)
