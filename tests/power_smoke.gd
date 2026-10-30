extends SceneTree
## Native additionally captures the real blackout and 3D fusebox view.
var failures: int = 0
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("POWER: " + message)

func frames(count: int = 3) -> void:
	for index: int in count:
		await physics_frame

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.04
	await frames()
	var power: ApartmentPower = game.power
	var board: ApartmentFusebox = power.board
	power.set_process(false)
	board.set_physics_process(false)
	expect(power.powered and not power.flashlight.visible, "Starts powered without flashlight")
	expect(not power.flashlight_spill.visible, "Near spill starts disabled")
	expect(power.cooldown_left > 119.0 and power.cooldown_left <= 120.0, "Initial 120-second protection")
	power.cooldown_left = 120.0
	power._check_time = 0.0
	power.outage_chance_per_second = 1.0
	power.advance_outage_timer(119.5)
	expect(power.powered, "Protection prevents even guaranteed random outage")
	power.advance_outage_timer(0.5)
	expect(power.powered, "End of protection does not force outage")
	power.advance_outage_timer(0.99)
	expect(power.powered, "One-second checks, not per-frame chance")
	power.advance_outage_timer(0.02)
	expect(not power.powered and power.flashlight.visible, "Eligible chance triggers outage and flashlight")
	expect(power.flashlight_spill.visible, "Outage enables broad near spill")
	for light: Light3D in power._lights:
		expect(not light.visible, "Apartment light goes dark")
	expect(power._environment.ambient_light_energy < 0.02, "Ambient is darkened too")
	game.enter_computer()
	expect(game.mode == game.Mode.WALKING, "Computer cannot be entered without power")
	board.set_active(true, game.transition_camera)
	board.begin_hold(0)
	board.advance(1.75)
	expect(is_equal_approx(board.progress[0], 0.5), "Halfway after 1.75 seconds")
	board.cancel_hold()
	board.advance(0.3)
	expect(is_equal_approx(board.progress[0], 0.25), "Falls faster at full range / 1.2 sec")
	board.begin_hold(0)
	board.advance(3.5)
	expect(board.latched[0], "Complete lever latches")
	board.set_active(false)
	board.advance(10.0)
	expect(board.latched[0] and board.progress[0] == 1.0, "Latched lever persists while away")
	board.set_active(true, game.transition_camera)
	for index: int in range(1, 4):
		board.begin_hold(index)
		board.advance(3.5)
	expect(power.powered and not power.flashlight.visible, "Four latched levers restore power")
	expect(not power.flashlight_spill.visible, "Repair disables near spill too")
	expect(power.cooldown_left == 120.0, "Repair resets protection")
	for light: Light3D in power._lights:
		expect(light.visible, "Light restored")
	# Cancel PC camera transitions safely on either side of the seated state.
	for stage: String in ["entering", "seated", "leaving"]:
		game.enter_computer()
		if stage != "entering":
			await create_timer(0.12).timeout
			game.terminal_ui.notepad.editor.text = "remember me"
			if stage == "leaving":
				game.leave_computer(false)
		power.trigger_outage()
		await create_timer(0.12).timeout
		expect(game.mode == game.Mode.WALKING and game.player.camera.current, "Outage safely exits PC: " + stage)
		expect(not game.terminal_ui.visible and not game.cctv_system.watching, "Desktop/CCTV rendering disabled")
		if stage != "entering":
			expect(game.terminal_ui.notepad.editor.text == "remember me", "Notes survive outage")
		power.restore_power()
	# Actual fusebox camera, E target and escape/progress persistence.
	power.trigger_outage()
	game.player.position = Vector3(4.2, 0.02, -5.3)
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO
	game.player.stop_motion(true)
	await frames(5)
	expect(game.player.find_interaction() == &"fusebox", "Existing interaction ray finds physical fusebox")
	game.enter_fusebox()
	await create_timer(0.12).timeout
	var move_event := InputEventKey.new()
	move_event.physical_keycode = KEY_W
	move_event.pressed = true
	game._input(move_event)
	await create_timer(0.12).timeout
	expect(game.mode == game.Mode.WALKING, "WASD also exits fusebox")
	game.enter_fusebox()
	await create_timer(0.12).timeout
	expect(game.mode == game.Mode.FUSEBOX and board.active, "Close view activates physical levers")
	board.begin_hold(2)
	board.advance(3.5)
	board.begin_hold(1)
	board.advance(1.0)
	game.leave_fusebox(false)
	board.advance(2.0)
	await create_timer(0.12).timeout
	expect(game.mode == game.Mode.WALKING and not board.active, "Exit returns to walking")
	expect(board.latched[2] and board.progress[1] == 0.0, "Exit preserves latched, drops partial")
	game.enter_fusebox()
	await create_timer(0.12).timeout
	# Move out of the pick target while pressed: physical-process validation releases it.
	board.begin_hold(1)
	board._physics_process(0.016)
	expect(board.held == -1, "Released mouse / invalid hover cancels hold")
	board.begin_hold(1)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(board.held == -1 and not power._interacting, "Focus loss cancels hold and behind audio")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	# Five-second hotkey and early-release reset.
	var f7 := InputEventKey.new()
	f7.physical_keycode = KEY_F7
	f7.pressed = true
	game.dev_menu._input(f7)
	await create_timer(0.1).timeout
	f7.pressed = false
	game.dev_menu._input(f7)
	expect(not game.dev_menu.is_open and game.dev_menu._held_seconds == 0.0, "Early F7 release resets countdown")
	f7.pressed = true
	game.dev_menu._input(f7)
	await create_timer(4.7).timeout
	expect(not game.dev_menu.is_open, "F7 does not open before five seconds")
	await create_timer(0.4).timeout
	expect(game.dev_menu.is_open and not board.active, "Five seconds opens dev and suspends board")
	game.player.stamina.set_unlimited(true)
	game.player.stamina.advance(20.0, true, true)
	expect(game.player.stamina.value == 1.0 and game.player.stamina.fatigue_amount() == 0.0, "Unlimited stamina fills and clears fatigue")
	game.player.stamina.set_unlimited(false)
	game.player.stamina.advance(1.5, true, true)
	expect(is_equal_approx(game.player.stamina.value, 0.5), "Disabling unlimited restores drain")
	power.clear_cooldown()
	expect(power.cooldown_left == 0.0, "Dev clears cooldown")
	power.restore_power()
	await create_timer(0.12).timeout
	expect(game.dev_menu.is_open and not game.player.controls_enabled, "Dev repair exits board without restoring walking input under overlay")
	game.dev_menu.close_menu()
	expect(game.player.controls_enabled and game.mode == game.Mode.WALKING, "Closing dev restores correct mode")
	game.dev_menu.enabled = false
	game.dev_menu.open_menu()
	expect(not game.dev_menu.is_open, "Export flag disables developer menu")
	if DisplayServer.get_name() != "headless":
		power.trigger_outage()
		power.set_process(true)
		game.enter_fusebox()
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/fusebox.png")
	game.queue_free()
	await process_frame
	print("POWER SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
