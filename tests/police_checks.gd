extends Node
## Shared deterministic integration suite; native also checks real E and mouse input.
var game: Node3D
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("POLICE: " + message)


func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().physics_frame


func wait_mode(expected: int) -> void:
	for index: int in 60:
		if game.mode == expected:
			return
		await get_tree().process_frame
	expect(false, "Camera transition did not reach mode %d" % expected)


func setup() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.02
	game.threats.set_event_enabled(&"power_outage", false)
	game.threats.set_process(false)
	game.threats.set_event_enabled(&"psych_neighbor", false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	await frames()


func aim_at_spot(id: StringName) -> void:
	var position := Vector3(-1.85, 0.03, 1.35) if id == &"hide_wardrobe" else Vector3(-0.55, 0.03, 4.5)
	var target := Vector3(-1.85, 1.3, 2.55) if id == &"hide_wardrobe" else Vector3(-1.7, 0.48, 4.5)
	game.player.position = position
	var direction := target - (position + Vector3(0, 1.6, 0))
	game.player.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	game.player.head.rotation = Vector3(atan2(direction.y, Vector2(direction.x, direction.z).length()), 0, 0)
	game.player.stop_motion(true)
	await frames()
	expect(game.player.find_interaction() == id, "Existing interaction ray finds " + String(id))


func native_input() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless"


func key_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	# The initial native frame can run several catch-up physics ticks before input.
	await get_tree().process_frame
	await get_tree().process_frame


func hide(id: StringName) -> void:
	await aim_at_spot(id)
	if native_input():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await frames()
		await key_e()
		await frames()
	else:
		expect(game.enter_hiding(game.hiding_spots[id]), "Shared world enters " + String(id))
	expect(game.is_hidden() and not game.player.controls_enabled and game.transition_camera.current, "Hiding activates fixed-position camera and disables walking")


func capture(name: String) -> void:
	if not native_input():
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/police_" + name + ".png")


func _run() -> void:
	TranslationServer.set_locale("ru")
	await setup()
	expect(game.get_node("Apartment/Wardrobe/Shell/Left").position.x < -0.7 and game.get_node("Apartment/Wardrobe/Shell/Back").position.z > 0.29, "Wardrobe shell leaves actual camera space and a front viewing gap")
	# Hiding can be tested without an enemy and cannot bypass other interaction modes.
	for id: StringName in [&"hide_wardrobe", &"hide_bed"]:
		await hide(id)
		var body_pose: Transform3D = game.player.global_transform
		var view_position: Vector3 = game.transition_camera.global_position
		Input.action_press("move_forward")
		await frames(8)
		expect(game.player.global_transform.is_equal_approx(body_pose), "WASD cannot move hidden player")
		if native_input():
			var motion := InputEventMouseMotion.new()
			motion.screen_relative = Vector2(100000, 100000)
			game._unhandled_input(motion)
			expect(absf(game._hidden_look.x) <= deg_to_rad(game.hiding_spot.max_yaw_degrees) + 0.0001 and absf(game._hidden_look.y) <= deg_to_rad(game.hiding_spot.max_pitch_degrees) + 0.0001, "Hidden mouse look is clamped")
			expect(game.transition_camera.global_position.is_equal_approx(view_position), "Looking never moves hiding camera through furniture")
			motion.screen_relative = Vector2(-100000, -100000)
			game._unhandled_input(motion)
			motion.screen_relative = Vector2(100000, 100000)
			game._unhandled_input(motion)
			# Restore neutral view for the screenshot.
			game._hidden_look = Vector2.ZERO
			game._update_hiding_view()
		game.enter_computer()
		game.enter_fusebox()
		expect(game.is_hidden(), "PC/fusebox cannot hijack hiding camera")
		await capture(String(id))
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		expect(game.is_hidden(), "Focus loss releases pointer but never exposes player")
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		if native_input():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			await key_e()
			await frames()
		else:
			expect(game.leave_hiding(false), "Shared world exits hiding")
		expect(not game.is_hidden() and game.player.controls_enabled and game.player.camera.current, "Exit restores walking camera and controls")
		expect(not Input.is_action_pressed("move_forward"), "Exit clears held movement keys")
	# An obstructed preferred exit falls back to the alternate marker.
	await hide(&"hide_wardrobe")
	var spot: HidingSpot = game.hiding_spot
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.0, 0.8)
	collision.shape = box
	blocker.add_child(collision)
	game.add_child(blocker)
	blocker.global_position = spot.get_node("Exits/Front").global_position + Vector3(0, 1.0, 0)
	await frames()
	expect(game.leave_hiding(false), "Blocked preferred exit does not trap player")
	expect(game.player.global_position.distance_to(spot.get_node("Exits/Side").global_position) < 0.05, "Alternate exit is used after capsule collision check")
	blocker.queue_free()
	await frames()
	# Both spots survive the full raid. First also starts from the real PC.
	for id: StringName in [&"hide_wardrobe", &"hide_bed"]:
		await setup()
		if id == &"hide_wardrobe":
			game.enter_computer()
			await wait_mode(game.Mode.COMPUTER)
			game.terminal_ui.notepad.editor.text = "evidence survives"
		expect(game.trigger_police(), "Forced raid starts before random scheduling is allowed")
		expect(game.mode == game.Mode.WALKING and game.police.visual.visible, "Arrival is visible and ejects the PC")
		expect(game.police.knock_audio.playing and game.threats.phase_seconds_left == 12.0, "First knock starts full 12-second warning")
		expect(
			game.police.ambush_audio.playing
			and game.police.ambush_audio.stream.resource_path == "res://assets/audio/police_aimbush.wav",
			"police_aimbush.wav plays with the first knock, before the door opens",
		)
		game.threats.advance(0.9)
		expect(game.police.voice_audio.playing and game.police.voice_audio.stream.resource_path == "res://assets/audio/heavy_knock.wav", "Warning uses heavy_knock.wav")
		if game.mode == game.Mode.COMPUTER:
			game.leave_computer(false)
			await wait_mode(game.Mode.WALKING)
			expect(game.terminal_ui.notepad.editor.text == "evidence survives", "Police warning preserves PC notes")
		await hide(id)
		game.threats.set_event_enabled(&"psych_neighbor", true)
		expect(not game.trigger_neighbor(), "Neighbor cannot overlap police warning")
		game.power.trigger_outage()
		expect(game.power.powered, "Real outage cannot overlap police warning")
		game.threats.advance(11.11)
		expect(not game.run_ended and game.police.visit == PoliceRaid.Visit.SEARCHING and game.room_door.is_open, "Hidden player survives entry; police opens closed door")
		game.ambient._process(0.1)
		expect(not game.ambient.suspense_audio.playing, "Police search does not start pursuit music before detection")
		game.shift._finish_stage()
		expect(game.shift.state == ShiftDirector.State.WAITING_EVENT, "Event queues behind inspection")
		game.threats.advance(game.police.settings.search_seconds + game.police.settings.pressure_seconds)
		expect(game.police.visit == PoliceRaid.Visit.DEPARTING and game.is_hidden(), "Search includes one listening pause then departure begins")
		game.ambient._process(1.0)
		expect(not game.ambient.suspense_audio.playing, "Pursuit suspense ends when police leaves search")
		expect(game.police.voice_audio.stream.resource_path == "res://assets/audio/steps.wav", "Departure uses steps.wav")
		await capture("inspection_" + String(id))
		game.threats.advance(2.99)
		expect(game.police.visit == PoliceRaid.Visit.DEPARTING and not game.run_ended, "Last part of three-second departure is still dangerous")
		game.threats.advance(0.02)
		expect(game.threats.state == ThreatManager.State.RESOLVED and not game.police.visual.visible and not game.police.footsteps_audio.playing, "Departure ends with visible/audio cleanup")
		game.threats.advance(1.0)
		game.shift._process(0.0)
		expect(game.shift.state == ShiftDirector.State.WAITING_EVENT and game.is_hidden() and not game.player.controls_enabled, "Queued event waits without pulling survivor out of hiding")
		expect(game.leave_hiding(false) and not game.run_ended and game.room_door.is_open, "After departure exit is safe and door stays open")
		game.shift._process(0.0)
		if id == &"hide_bed":
			game.room_door.set_open(false)
		game.trigger_neighbor()
		game.threats.advance(5.0)
		game.threats.advance(3.0)
		if id == &"hide_wardrobe":
			expect(game.neighbor.visit == PsychNeighbor.Visit.SEARCHING and not game.run_ended, "Open door starts neighbor search, not global death")
		else:
			expect(not game.run_ended, "Closing police-opened door protects against next neighbor")
	# Being at the PC or in the corridor instead of hiding loses after warning.
	for at_pc: bool in [true, false]:
		await setup()
		if at_pc:
			game.enter_computer()
			await wait_mode(game.Mode.COMPUTER)
		else:
			game.player.position = Vector3(4.2, 0.03, -5.0)
		game.trigger_police()
		game.threats.advance(11.9)
		expect(not game.run_ended, "Unhidden player keeps full reaction window")
		game.threats.advance(0.11)
		expect(not game.run_ended and game.police.visual.visible, "Deadline opens the door without invisible global death")
		game.player.position = Vector3(0, 0.03, 1.1)
		game.police.visual.global_position = Vector3(1.4, 0, 1.1)
		game.police.visual.look_at(Vector3(0, 0, 1.1), Vector3.UP)
		for sample: int in 11:
			game.threats.advance(0.1)
		expect(game.capture_reason == "POLICE_DEATH" and not game.run_ended, "Confirmed sight starts visible capture before result")
		expect(
			game.threats.detected_audio.playing
			and game.threats.detected_audio.stream.resource_path == "res://assets/audio/detected.wav",
			"Police detection plays the shared detected cue",
		)
		game.ambient._process(0.1)
		expect(not game.ambient.suspense_audio.playing, "Pursuit music waits until the detected cue finishes")
		game._process(game.capture_cutscene.duration_seconds + 0.1)
		expect(game.run_ended and game.failure_reason == "POLICE_DEATH", "Capture finishes with police result")
		expect(game.police.visit == PoliceRaid.Visit.DORMANT and not game.police.knock_audio.playing and not game.police.voice_audio.playing and not game.police.footsteps_audio.playing, "Police death cleans all event state and audio")
		await capture("death")
	# Early exit alone is not a global detection check.
	for during_departure: bool in [false, true]:
		await setup()
		await hide(&"hide_wardrobe")
		game.trigger_police()
		game.threats.advance(12.0)
		if during_departure:
			game.threats.advance(game.police.settings.search_seconds + game.police.settings.pressure_seconds)
		game.leave_hiding(false)
		expect(not game.run_ended and game.capture_reason.is_empty(), "Leaving during search/departure requires real sight")
	game.fail_from_threat("POLICE_DEATH")
	# Actual scene restart resets hide/raid state and the door.
	var restart: Button = get_viewport().gui_get_focus_owner()
	restart.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	game = get_tree().current_scene
	game.threats.set_process(false)
	game.threats.set_event_enabled(&"power_outage", false)
	expect(not game.is_hidden() and game.hiding_spot == null and not game.run_ended and game.police.visit == PoliceRaid.Visit.DORMANT and not game.room_door.is_open, "Real restart clears hiding, police, death and opened door")
	# Disabling a raid is safe and never forcibly exposes the player.
	await setup()
	await hide(&"hide_wardrobe")
	game.dev_menu._holding = true
	game.dev_menu._process(game.dev_menu.hold_seconds + 0.1)
	expect(game.dev_menu.is_open and game.is_hidden(), "F7 hold can open dev menu while hiding without exposing player")
	game.dev_menu.close_menu()
	expect(game.is_hidden() and not game.player.controls_enabled and game.transition_camera.current, "Closing dev overlay preserves hidden view and movement lock")
	game.trigger_police()
	game.threats.set_event_enabled(&"police_raid", false)
		expect(
			game.is_hidden()
			and not game.threats.is_busy()
			and not game.police.knock_audio.playing
			and not game.police.ambush_audio.playing
			and not game.trigger_police(),
			"Per-threat disable cancels warning sounds without leaving hiding",
		)
	game.threats.set_event_enabled(&"police_raid", true)
	game.trigger_police()
	game.threats.advance(12.0)
	game.disable_threats()
	expect(game.is_hidden() and not game.police.visual.visible and not game.police.footsteps_audio.playing and not game.threats.enabled, "DisableThreats cancels active inspection without forced exit")
	expect(game.leave_hiding(false) and not game.run_ended, "Exit after cancellation is safe")
	# Real random scheduling and debug buttons use the registered handler.
	await setup()
	game.threats.run_seconds = 46.0
	game.threats.wait_seconds_left = 0.1
	game._physics_process(0.0)
	game.threats.advance(1.0)
	expect(not game.threats.is_busy(), "No random police during opening briefing")
	game.shift.state = ShiftDirector.State.ROUTE
	game._physics_process(0.0)
	game.threats.advance(1.0)
	expect(game.police.visit == PoliceRaid.Visit.WARNING, "Eligible scheduler selects real PoliceRaid")
	game.threats.set_event_enabled(&"police_raid", false)
	game.threats.set_event_enabled(&"police_raid", true)
	game.shift.state = ShiftDirector.State.INTRO
	game.dev_menu.open_menu()
	await get_tree().process_frame
	var trigger: Button
	for button: Button in game.dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "TriggerPolice":
			trigger = button
	expect(trigger != null, "Dev menu exposes TriggerPolice")
	trigger.pressed.emit()
	expect(not game.dev_menu.is_open and game.police.visit == PoliceRaid.Visit.WARNING, "Dev command launches real raid and closes overlay")
	game.disable_threats()
	game.queue_free()
	await get_tree().process_frame
	# AudioServer releases stopped playbacks on its mixing thread, not this frame.
	await get_tree().create_timer(0.2).timeout
	print("POLICE SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
