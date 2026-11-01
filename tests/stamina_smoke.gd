extends SceneTree
## godot [--headless] --path . --script res://tests/stamina_smoke.gd
## Native mode additionally checks real movement and rendered smear/HUD pixels.
## Optional screenshots: -- --capture-dir=C:/existing/folder

var failures: int = 0
var game: Node3D
var player: ApartmentPlayer
var hud: PlayerHUD
var origin := Vector3(100, 0.02, 100)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_model()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.02
	player = game.player
	hud = game.hud
	await _frames(4)
	_expect(player.footsteps_audio.stream.resource_path == "res://assets/audio/player_steps.wav", "Player loads the authored footstep sound")
	_expect(is_equal_approx(hud.visual_ratio(0.5), 0.75), "Half real stamina displays as 75 percent")
	_expect(hud.visual_ratio(0.0) == 0.0 and hud.visual_ratio(1.0) == 1.0, "Visual curve endpoints")
	_expect(hud.visual_ratio(0.9) - hud.visual_ratio(0.8) < hud.visual_ratio(0.2) - hud.visual_ratio(0.1), "Visual depletion accelerates near empty")
	var rect := hud.bar.get_global_rect()
	_expect(is_equal_approx(rect.get_center().x, root.get_visible_rect().size.x * 0.5), "Bar strictly centered horizontally")
	_expect(rect.size == Vector2(160, 3), "Thin 160x3 design-size bar")
	_expect(not hud.fatigue.visible, "No screen effect at full stamina")
	if DisplayServer.get_name() != "headless":
		await _test_movement()
		await _test_render()
	else:
		print("STAMINA: headless skips captured-mouse movement and real pixel checks")
	await _test_pc()
	_release_actions()
	game.queue_free()
	await process_frame
	print("STAMINA SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_model() -> void:
	var state := PlayerStamina.new()
	var exhaustion_events := [0]
	state.became_exhausted.connect(func(): exhaustion_events[0] += 1)
	state.advance(1.5, true, true)
	_expect(is_equal_approx(state.value, 0.5), "Real consumption is linear")
	state.advance(0.49, false, false)
	_expect(is_equal_approx(state.value, 0.5), "Recovery delay respected")
	state.advance(0.05, false, false)
	_expect(is_equal_approx(state.value, 0.51), "Only time after delay contributes to recovery")
	_expect(state.can_sprint(), "Voluntary stop does not lock remaining stamina")
	state.reset()
	state.advance(2.5, true, true)
	_expect(state.fatigue_amount() > 0.0 and state.fatigue_amount() < 0.22, "Gentle warning below 20 percent")
	state.advance(0.5, true, true)
	_expect(state.value == 0.0 and state.exhausted and not state.can_sprint(), "Three seconds fully exhaust and lock sprint")
	_expect(exhaustion_events[0] == 1, "Exhaustion event fires once at zero stamina")
	state.advance(0.2, true, true)
	_expect(exhaustion_events[0] == 1, "Exhaustion event does not repeat while empty")
	_expect(state.fatigue_amount() == 1.0, "Full fatigue on exhaustion")
	state.advance(0.3 + 4.0 * 0.34, false, false)
	_expect(not state.can_sprint(), "Cannot restart below 35 percent")
	state.advance(0.041, false, false)
	_expect(state.can_sprint() and state.fatigue_latched, "35 percent unlocks, residual fatigue remains")
	state.advance(0.4, false, false)
	_expect(not state.fatigue_latched and state.fatigue_amount() == 0.0, "Fatigue clears at 45 percent recovery")
	state.reset()
	state.advance(3.0, true, true)
	_expect(exhaustion_events[0] == 2, "Exhaustion event can trigger again after stamina resets")
	state.reset()
	state.advance(3.0, true, true)
	state.advance(4.5, false, false)
	_expect(is_equal_approx(state.value, 1.0), "Rest and PC recover fully after 0.5 + 4 seconds")
	state.reset()
	state.advance(3.0, true, true)
	state.advance(3.5, false, true)
	_expect(is_equal_approx(state.value, 0.5), "Walking recovery uses six seconds")
	state.advance(3.0, false, true)
	_expect(state.value == 1.0, "Walking recovery reaches full")
	for fps: int in [30, 60, 144]:
		state.reset()
		for frame: int in fps * 3:
			state.advance(1.0 / fps, true, true)
		_expect(state.exhausted and state.value == 0.0, "Exhaustion timing at %d updates/sec" % fps)
		for frame: int in int(fps * 4.5):
			state.advance(1.0 / fps, false, false)
		_expect(is_equal_approx(state.value, 1.0), "Recovery timing at %d updates/sec" % fps)
	state.free()


func _test_movement() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.2, 80)
	shape.shape = box
	floor_body.add_child(shape)
	game.add_child(floor_body)
	floor_body.position = origin + Vector3(0, -0.12, 0)
	_spawn()
	await _frames(6)
	Input.action_press("sprint")
	await _frames(20)
	_expect(player.stamina.value == 1.0 and not player.is_sprinting, "Shift alone consumes nothing")
	Input.action_press("move_backward")
	await _frames(24)
	_expect(player.velocity.length() <= player.walk_speed + 0.02 and player.stamina.value == 1.0, "Backward movement cannot sprint")
	Input.action_release("move_backward")
	Input.action_press("move_right")
	await _frames(24)
	_expect(player.velocity.length() <= player.walk_speed + 0.02 and player.stamina.value == 1.0, "Sideways movement cannot sprint")
	Input.action_press("move_forward")
	await _frames(24)
	_expect(player.is_sprinting and player.stamina.value < 0.95, "Forward diagonal sprints")
	_expect(Vector2(player.velocity.x, player.velocity.z).length() <= player.sprint_speed + 0.02, "Sprint diagonal normalized")
	_spawn()
	await _frames(5)
	var footstep_samples_finished := [0]
	player.footsteps_audio.finished.connect(func(): footstep_samples_finished[0] += 1)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(90)
	_expect(footstep_samples_finished[0] > 0, "Walking and sprinting play the authored footstep sound")
	_expect(absf(player.stamina.value - 0.5) < 0.04, "Actual movement consumes about half in 1.5 seconds")
	_expect(hud.displayed_ratio > player.stamina.value + 0.15 and hud.bar_alpha > 0.9, "Visible bar is smoothed and deceptive")
	await _capture("half")
	await _frames(100)
	_expect(player.stamina.exhausted and not player.is_sprinting, "Exhaustion automatically ends sprint")
	_expect(player.velocity.length() <= player.walk_speed + 0.02, "Exhausted player returns to walking speed")
	_expect(player.camera.fov < 76.5, "Sprint FOV fades after exhaustion despite held Shift")
	var restarted := false
	for frame: int in 190:
		await _frames(1)
		if player.is_sprinting:
			restarted = true
			break
	_expect(restarted and player.stamina.value > 0.32 and player.stamina.value <= 0.36, "Held Shift resumes at 35 percent, not sooner")
	_expect(player.stamina.fatigue_amount() > 0.0, "Restart leaves mild fatigue until 45 percent")
	_release_actions()
	_spawn()
	# Real wall: no stamina drain, sprint FOV, or footsteps while stationary.
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(10, 3, 0.2)
	collision.shape = wall_box
	wall.add_child(collision)
	game.add_child(wall)
	wall.position = origin + Vector3(0, 1.4, -1)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(40)
	player.stamina.reset()
	await _frames(50)
	_expect(player.stamina.value == 1.0 and not player.is_sprinting, "No drain pushing a wall")
	_expect(player.camera.fov < 75.1, "No sprint FOV pushing a wall")
	_expect(not player.footsteps_audio.playing, "No footsteps while blocked against a wall")
	_release_actions()
	wall.queue_free()
	await _frames(2)


func _test_render() -> void:
	_spawn()
	await _frames(4)
	player.set_process(false)
	player.set_physics_process(false)
	hud.set_process(false)
	# Static contrast chart isolates the shader from real world motion in pixel comparisons.
	for index: int in 30:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 3, 0.1)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("b7b9af") if index % 2 == 0 else Color("242b29")
		box.material = material
		mesh.mesh = box
		game.add_child(mesh)
		mesh.position = origin + Vector3((index - 15) * 0.16, 1.5, -5)
	hud.clear_smear()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var clean := root.get_texture().get_image()
	await _capture("clean")
	for frame: int in 90:
		hud.update_smear(1.0 / 60.0, 1.0, Basis(Vector3.UP, frame * 0.02), true)
	_expect(hud.fatigue.visible and hud.smear_uv.length() > 0.001, "Turning while exhausted activates directional smear")
	_expect((hud.smear_uv * root.get_visible_rect().size).length() <= hud.max_smear_pixels + 0.01, "Smear has a bounded displacement")
	await _frames(4)
	await RenderingServer.frame_post_draw
	var blurred := root.get_texture().get_image()
	var changed: int = 0
	for x: int in range(300, 980, 4):
		for y: int in range(150, 550, 8):
			var difference := clean.get_pixel(x, y) - blurred.get_pixel(x, y)
			if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.03:
				changed += 1
	_expect(changed > 100, "Shader changes rendered world pixels")
	var sharp: int = 0
	for x: int in range(628, 652):
		for y: int in range(346, 374):
			var pixel := clean.get_pixel(x, y)
			if pixel.r > 0.995 and pixel.g > 0.995 and pixel.b > 0.995:
				sharp += 1
				_expect(pixel.is_equal_approx(blurred.get_pixel(x, y)), "Crosshair core pixels remain sharp over smear")
	_expect(sharp > 2, "Crosshair pixels found for HUD isolation check")
	await _capture("smear")
	hud.update_smear(1.0 / 60.0, 0.0, Basis(Vector3.UP, 1.8), true)
	_expect(hud.fatigue_blend == 0.0 and not hud.fatigue.visible, "Recovery to clear threshold leaves no smoothing tail")
	for frame: int in 90:
		hud.update_smear(1.0 / 60.0, 1.0, Basis(Vector3.UP, 89 * 0.02), true)
	_expect(not hud.fatigue.visible, "Stationary camera clears blur even while exhausted")
	hud.fatigue_strength = 0.0
	hud.update_smear(0.016, 1.0, Basis.IDENTITY, true)
	_expect(not hud.fatigue.visible and hud.fatigue_blend == 0.0, "Comfort setting fully disables screen effect")
	hud.fatigue_strength = 1.0
	hud.set_process(true)
	player.set_process(true)
	player.set_physics_process(true)


func _test_pc() -> void:
	player.stamina.reset()
	player.stamina.advance(3.0, true, true)
	_expect(
		player.exhaustion_audio.playing
		and player.exhaustion_audio.stream.resource_path == "res://assets/audio/exausted.wav",
		"Zero stamina plays exausted.wav",
	)
	game.enter_computer()
	_expect(not hud.visible and not hud.fatigue.visible and player.stamina.value == 0.0, "PC hides all effects without resetting stamina")
	await create_timer(0.8).timeout
	_expect(game.mode == game.Mode.COMPUTER and player.stamina.value > 0.04 and player.stamina.value < 0.16, "Stamina regenerates while seated at rest rate")
	game.terminal_ui.launch_app(&"cctv")
	await create_timer(0.1).timeout
	_expect(not hud.fatigue.visible, "CCTV and desktop never receive fatigue shader")
	var before := player.stamina.value
	game.leave_computer(false)
	await create_timer(0.15).timeout
	_expect(player.stamina.value >= before and player.stamina.value < 0.3, "Returning preserves recovering stamina instead of refill")
	_expect(not hud.fatigue.visible, "Camera transition does not create a stale smear")


func _spawn() -> void:
	_release_actions()
	player.position = origin
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.stop_motion(true)
	player.stamina.reset()
	hud.clear_smear()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_actions() -> void:
	for action: String in ["sprint", "move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)


func _frames(count: int) -> void:
	for index: int in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("STAMINA: " + message)


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(argument.trim_prefix("--capture-dir=").path_join("stamina_" + name + ".png"))
