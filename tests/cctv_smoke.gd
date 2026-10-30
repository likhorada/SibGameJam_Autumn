extends SceneTree
## godot [--headless] --path . --script res://tests/cctv_smoke.gd
## Optional: -- --capture-dir=C:/existing/folder

var failures: int = 0
var game: Node3D
var system: CCTVSystem
var desktop: TerminalDesktop
var app: CCTVApp


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	game.observation_shift_enabled = false
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.02
	system = game.cctv_system
	desktop = game.terminal_ui
	app = desktop.cctv
	await _frames(4)
	_expect(system.cameras.size() == 4, "Two locations automatically register four cameras")
	_expect(app.directory.item_count == 4, "All cameras available in app")
	_expect(not system.watching and system.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "No hidden feed rendering at startup")
	_expect(system.viewport.own_world_3d and system.viewport.size == Vector2i(480, 270), "Isolated low-resolution world")
	var visitor: Node3D = system.viewport.get_node("Locations/Shop/Visitor")
	var before: float = visitor.elapsed
	await create_timer(0.15).timeout
	_expect(visitor.elapsed > before, "Location actions advance while player is away")
	game.enter_computer()
	await create_timer(0.15).timeout
	desktop.launch_app(&"cctv")
	await create_timer(0.65).timeout
	_expect(system.watching and app.image.visible, "Launching CCTV connects feed")
	_expect(app.input_enabled, "Active CCTV receives controls")
	_expect(_count_viewports(game) == 1, "Exactly one feed SubViewport")
	var combinations: Dictionary = {}
	for index: int in system.cameras.size():
		app.directory.select(index)
		app._select(index)
		_expect(not app.image.visible, "Switch hides stale camera frame")
		await create_timer(0.65).timeout
		var camera := system.selected
		combinations["%s/%s" % [camera.monochrome, camera.has_microphone]] = true
		_expect(system.viewport.get_camera_3d() == camera.lens, "Selected lens is sole current viewport camera")
		_expect(app._material.get_shader_parameter("monochrome") == camera.monochrome, "Color mode follows selected camera")
		_expect(app.properties.text.contains("MIC +") == camera.has_microphone, "Microphone indicator follows camera property")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check_render(camera.monochrome)
		await _capture("camera_%d" % index)
	_expect(combinations.size() == 4, "All four color/microphone combinations represented")
	# Deterministic motor test independent of render rate.
	system.set_process(false)
	var camera := system.selected
	camera.reset_view()
	camera.command(1.0, 0.0)
	camera.advance_motor(0.1)
	_expect(camera.pan_degrees == 0.0, "Motor startup delay")
	for index: int in 60:
		camera.advance_motor(0.016)
	_expect(camera.pan_degrees > 2.0, "Held command pans after delay")
	var pan_before := camera.pan_degrees
	camera.command(0.0, 0.0)
	camera.advance_motor(0.05)
	_expect(camera.pan_degrees > pan_before, "Motor coasts after release")
	camera.command(1.0, 1.0)
	for index: int in 1000:
		camera.advance_motor(0.016)
	_expect(is_equal_approx(camera.pan_degrees, camera.pan_limit_degrees), "Pan limit enforced")
	_expect(is_equal_approx(camera.zoom, camera.max_zoom) and camera.lens.fov < camera.base_fov, "Optical zoom and upper bound")
	camera.command(-1.0, -1.0)
	for index: int in 1000:
		camera.advance_motor(0.016)
	_expect(is_equal_approx(camera.pan_degrees, -camera.pan_limit_degrees), "Opposite pan limit enforced")
	_expect(camera.zoom == 1.0, "Zoom lower bound")
	app._select(0)
	app._select(3)
	_expect(system.selected.pan_degrees == 0.0 and system.selected.zoom == 1.0, "Switching back resets original pose and zoom")
	system.set_process(true)
	await create_timer(0.65).timeout
	# Actual GUI hold and release outside window.
	var point: Vector2 = app.buttons[&"left"].get_global_rect().get_center()
	_mouse(point, true)
	await create_timer(0.8).timeout
	_expect(system.selected.pan_degrees > 1.0, "GUI hold controls selected camera")
	_mouse(Vector2(1250, 650), false)
	await create_timer(0.7).timeout
	_expect(absf(system.selected.velocity) < 0.01, "Release outside button stops motor after coast")
	# Note taking keeps visible feed alive, but never leaves a motor command latched.
	desktop.launch_app(&"notepad")
	_expect(not app.input_enabled and system.watching, "Inactive visible CCTV still renders; controls released")
	desktop.notepad.editor.insert_text_at_caret("CCTV note")
	_expect(desktop.notepad.editor.text == "CCTV note", "Notes usable alongside CCTV")
	await _capture("with_notes")
	desktop.activate_window(&"cctv")
	app._start_command(1.0, 0.0)
	desktop._clear_active()
	_expect(system.selected.velocity == 0.0 and not app.input_enabled, "Desktop click cancels camera input")
	desktop.activate_window(&"cctv")
	# Explicit menu toggle mirrors button state.
	desktop.start_button.set_pressed_no_signal(true)
	desktop._toggle_start()
	_expect(not app.input_enabled, "Start menu cancels camera controls")
	desktop._close_start()
	_expect(app.input_enabled, "Closing Start restores CCTV controls")
	app._start_command(1.0, 0.0)
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(system.selected.velocity == 0.0 and app._pan == 0.0, "Application focus loss cancels command")
	desktop.windows[&"cctv"].minimize()
	_expect(not system.watching and system.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Minimized feed stops rendering")
	before = visitor.elapsed
	await create_timer(0.15).timeout
	_expect(visitor.elapsed > before, "Location continues while minimized")
	desktop.launch_app(&"cctv")
	await create_timer(0.65).timeout
	_expect(system.selected.pan_degrees == 0.0 and system.selected.zoom == 1.0, "Restoring reconnects at original pose")
	desktop.windows[&"cctv"].close_window()
	_expect(not system.watching, "Closed feed stops rendering")
	desktop.launch_app(&"cctv")
	await create_timer(0.65).timeout
	# Resize at the supported minimum logical workspace.
	desktop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	desktop.size = Vector2(640, 360)
	await _frames(4)
	_expect(app.buttons[&"in"].get_global_rect().end.y <= 316.0, "Controls reachable in 640x360 desktop")
	await _capture("small")
	desktop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(3)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	# Separate popup viewport routes Esc to game, just like Notepad's context menu.
	app.directory.get_popup().window_input.emit(escape)
	_expect(game.mode == game.Mode.LEAVING and not system.watching, "Esc from camera picker immediately leaves PC and stops rendering")
	await create_timer(0.15).timeout
	game.enter_computer()
	await create_timer(0.65).timeout
	_expect(system.watching and app.input_enabled, "Re-entering resumes CCTV and controls")
	root.push_input(escape)
	_expect(game.mode == game.Mode.LEAVING and not system.watching, "Esc in CCTV app immediately exits")
	await create_timer(0.15).timeout
	game.queue_free()
	await _frames(2)
	await _test_empty_system()
	await _test_custom_location()
	print("CCTV SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_empty_system() -> void:
	var empty := CCTVSystem.new()
	root.add_child(empty)
	empty.set_watching(true)
	empty.select_camera(-1)
	_expect(empty.cameras.is_empty() and not empty.can_show_feed(), "Empty location list handled safely")
	empty.queue_free()
	await process_frame


func _test_custom_location() -> void:
	# Reproduce the editor contract: ordinary scene + camera instance + Inspector properties.
	var location := Node3D.new()
	location.name = "CustomLocation"
	var camera: CCTVCamera = load("res://scenes/cctv/cctv_camera.tscn").instantiate()
	camera.camera_id = &"custom_camera"
	camera.display_name = "CUSTOM"
	camera.location_label = "CUSTOM LOCATION"
	camera.has_microphone = true
	camera.monochrome = true
	location.add_child(camera)
	camera.owner = location
	var packed := PackedScene.new()
	_expect(packed.pack(location) == OK, "Custom location packs without a custom script")
	location.free()
	var custom := CCTVSystem.new()
	custom.locations = [packed]
	root.add_child(custom)
	_expect(custom.cameras.size() == 1 and custom.cameras[0].camera_id == &"custom_camera", "New location camera auto-registers from exported scene list")
	_expect(custom.cameras[0].has_microphone and custom.cameras[0].monochrome, "Inspector properties survive scene instantiation")
	custom.queue_free()
	await process_frame


func _check_render(monochrome: bool) -> void:
	var screenshot := root.get_texture().get_image()
	var rect := app.image.get_global_rect()
	var colored: int = 0
	var lit: int = 0
	for x: int in range(int(rect.position.x + 20), int(rect.end.x - 20), 8):
		for y: int in range(int(rect.position.y + 20), int(rect.end.y - 20), 8):
			var pixel := screenshot.get_pixel(x, y)
			if pixel.r + pixel.g + pixel.b > 0.25:
				lit += 1
			if absf(pixel.r - pixel.g) + absf(pixel.g - pixel.b) > 0.06:
				colored += 1
	_expect(lit > 30, "Rendered feed contains visible geometry")
	_expect(colored == 0 if monochrome else colored > 20, "Rendered monochrome/color matches property")


func _mouse(point: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event)


func _count_viewports(node: Node) -> int:
	var count := 1 if node is SubViewport else 0
	for child: Node in node.get_children():
		count += _count_viewports(child)
	return count


func _frames(count: int) -> void:
	for index: int in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CCTV: " + message)


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			var directory := argument.trim_prefix("--capture-dir=")
			root.get_texture().get_image().save_png(directory.path_join("cctv_" + name + ".png"))
