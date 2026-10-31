extends SceneTree
## Run without --headless for real rendered-pixel checks.
var failures: int = 0
var game: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = load("res://tests/visual_effects_fixture.tscn").instantiate()
	game.observation_shift_enabled = false
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.02
	var effects: VisualEffects = game.visual_effects
	await _frames(5)
	effects._sync_camera()
	_expect(effects.viewport.size == Vector2i(256, 144), "Apartment renders at 256x144")
	_expect(root.disable_3d and effects.viewport.world_3d == game.get_world_3d(), "Only low-res viewport renders the shared apartment world")
	_expect(effects.image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Nearest upscale")
	_expect(game.cctv_system.viewport.size == Vector2i(480, 270), "CCTV stays at 480x270")
	_expect(not effects.crt.visible and not game.hud.fatigue.visible, "No CRT or smear at rest")
	# Freeze the actual rendered camera so pixel differences cannot be camera motion.
	game.player.set_physics_process(false)
	await _frames(4)
	var clean: Image
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		clean = root.get_texture().get_image()
		_capture(clean, "world_clean")
	effects.trigger_scare()
	effects.set_process(false)
	for index: int in 20:
		effects._process(1.0 / 60.0)
		game.hud._process(1.0 / 60.0)
	await _frames(4)
	_expect(effects.anxiety > 0.5 and game.hud.fatigue.visible, "Scare creates stationary double image")
	_expect(game.player.stamina.value == 1.0, "Anxiety never changes stamina")
	if clean != null:
		await RenderingServer.frame_post_draw
		var anxious := root.get_texture().get_image()
		_expect(_different_pixels(clean, anxious) > 50, "Stationary anxiety changes real world pixels")
		_capture(anxious, "world_anxiety")
	for index: int in 200:
		effects._process(1.0 / 60.0)
	await _frames(3)
	_expect(effects.anxiety == 0.0 and not game.hud.fatigue.visible, "Scare fully clears after recovery")
	game.neighbor.visit = PsychNeighbor.Visit.APPROACHING
	game.player.global_position = Vector3(0, 0.03, 1.1)
	game.neighbor.visual.global_position = game.player.global_position + Vector3(2, 0, 0)
	var near := effects._proximity()
	game.neighbor.visual.global_position += Vector3(20, 0, 0)
	_expect(near > 0.3 and near <= 0.45 and effects._proximity() == 0.0, "Visible enemy proximity is capped so silhouettes remain readable")
	game.neighbor.visit = PsychNeighbor.Visit.DORMANT
	effects.set_process(true)
	game.player.set_physics_process(true)
	game.enter_computer()
	await create_timer(0.2).timeout
	_expect(effects.crt.visible, "CRT only while seated")
	_expect(effects.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Apartment rendering stops behind desktop")
	if DisplayServer.get_name() != "headless":
		await _test_crt(effects)
	game.terminal_ui.launch_app(&"cctv")
	effects.trigger_scare()
	await create_timer(0.65).timeout
	_expect(not game.hud.fatigue.visible, "World smear cannot blur desktop text")
	_expect(float(game.terminal_ui.cctv._material.get_shader_parameter("anxiety")) > 0.0, "CCTV receives anxiety independently of text")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_capture(root.get_texture().get_image(), "desktop_crt_anxiety")
	game.leave_computer(false)
	await create_timer(0.2).timeout
	_expect(not effects.crt.visible and effects.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Exit restores world rendering and removes CRT")
	game.enter_hiding(game.hiding_spots[&"hide_bed"])
	effects._sync_camera()
	_expect(effects.camera.global_transform.is_equal_approx(game.transition_camera.global_transform), "Hidden view uses correct source camera")
	game.queue_free()
	await _frames(3)
	_expect(not root.disable_3d, "Scene teardown restores root rendering for menus/restart")
	print("VISUAL EFFECTS SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for index: int in count:
		await physics_frame


func _test_crt(effects: VisualEffects) -> void:
	effects.set_process(false)
	var material: ShaderMaterial = effects.crt.material
	var original_shader := material.shader
	var diagnostic := Shader.new()
	diagnostic.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR = vec4(1.0, 0.0, 0.0, 1.0); }"
	material.shader = diagnostic
	effects.crt.show()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var red := root.get_texture().get_image().get_pixel(1150, 300)
	_expect(red.r > 0.95 and red.g < 0.05, "CRT layer really draws over desktop")
	material.shader = original_shader
	material.set_shader_parameter("strength", effects.crt_strength)
	effects.crt.hide()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var without := root.get_texture().get_image()
	_capture(without, "desktop_crt_off")
	effects.crt.show()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var with_crt := root.get_texture().get_image()
	_capture(with_crt, "desktop_crt_on")
	var minimum := 1.0
	var maximum := 0.0
	for y: int in range(240, 480):
		var ratio := with_crt.get_pixel(1150, y).r / maxf(without.get_pixel(1150, y).r, 0.001)
		minimum = minf(minimum, ratio)
		maximum = maxf(maximum, ratio)
	print("CRT rendered brightness range: ", minimum, "..", maximum)
	_expect(maximum - minimum > 0.035, "CRT has visible scanline contrast, not a flat tint")
	effects.set_process(true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("EFFECTS: " + message)


func _different_pixels(a: Image, b: Image) -> int:
	var changed := 0
	for y: int in range(100, 600, 3):
		for x: int in range(100, 1180, 3):
			var difference := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.025:
				changed += 1
	return changed


func _capture(image: Image, label: String) -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			image.save_png(argument.trim_prefix("--capture-dir=").path_join("effects_" + label + ".png"))
