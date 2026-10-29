extends SceneTree
## Run after import: godot --path . --script res://tests/prototype_smoke.gd
## Needs a real display: the headless DisplayServer cannot capture a pointer.
## Optional screenshots: -- --capture --capture-dir=<existing directory>

var failures: int = 0
var game: Node3D
var player: ApartmentPlayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a real display for this input/collision suite (omit --headless).")
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	player = game.get_node("Player")
	game.transition_seconds = 0.02
	await _frames(3)
	_expect(game.mode == game.Mode.WALKING, "Starts walking")
	_expect(player.camera.current, "Player camera starts current")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Starts with click-to-capture")
	_expect(InputMap.action_has_event("sprint", _shift_event()), "Sprint is bound to Shift")

	# Clear standing space and floors in every accessible zone.
	for point: Vector3 in [Vector3(1.3, 0.02, -1), Vector3(1.2, 0.02, 4.7), Vector3(-4, 0.02, -0.5), Vector3(4.2, 0.02, -5.8)]:
		player.position = point
		player.velocity = Vector3.ZERO
		await _frames(12)
		_expect(_standing_space_is_clear(), "Capsule clear at %s" % point)
		_expect(player.is_on_floor(), "Floor at %s" % point)

	# Openings must accommodate the actual capsule, not just a thin ray.
	await _walk(Vector3(1.2, 0.02, 2.3), 0.0, "move_backward", 45)
	_expect(player.position.z > 3.8, "Bedroom doorway traversable")
	await _walk(Vector3(-2.3, 0.02, -0.5), 0.0, "move_left", 40)
	_expect(player.position.x < -3.6, "Bathroom doorway traversable")
	await _walk(Vector3(2.3, 0.02, 1.1), 0.0, "move_right", 35)
	_expect(player.position.x > 3.5, "Corridor doorway traversable")
	await _walk(Vector3(4.2, 0.02, -5.7), 0.0, "move_forward", 60)
	_expect(player.position.z > -6.7, "Corridor end wall blocks movement")
	await _walk(Vector3(4.2, 0.02, 1.1), 0.0, "move_right", 40)
	_expect(player.position.x < 5.1, "Corridor side wall blocks movement")

	# Compare walk and sprint in an unobstructed corridor segment.
	await _walk(Vector3(4.2, 0.02, 1.1), 0.0, "move_forward", 30)
	var walk_distance: float = 1.1 - player.position.z
	_expect(walk_distance > 0.8, "Walk actually moves the player")
	Input.action_press("sprint")
	await _walk(Vector3(4.2, 0.02, 1.1), 0.0, "move_forward", 30)
	Input.action_release("sprint")
	var sprint_distance: float = 1.1 - player.position.z
	_expect(sprint_distance > walk_distance * 1.5, "Sprint faster than walk")

	# Movement stops and camera ignores mouse input when pointer is released.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var before := player.position
	Input.action_press("move_forward")
	await _frames(10)
	Input.action_release("move_forward")
	_expect(player.position.distance_to(before) < 0.05, "Released mouse stops movement")

	# Ten enter/exit cycles using both Esc and the UI button, including repeated input.
	for cycle: int in range(10):
		player.position = Vector3(0, 0.02, -0.55)
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3(-0.18, 0, 0)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await _frames(3)
		_expect(player.interaction_id == &"computer", "Computer ray available, cycle %d" % cycle)
		game._unhandled_input(_action("interact"))
		_expect(game.mode == game.Mode.ENTERING, "Entering mode")
		if game.mode != game.Mode.ENTERING:
			quit(1)
			return
		var active_tween: Tween = game.transition
		game.enter_computer() # Must not start a second tween.
		_expect(game.transition == active_tween, "Repeated enter ignored")
		_expect(not player.controls_enabled, "Movement disabled during transition")
		await create_timer(0.12).timeout
		_expect(game.mode == game.Mode.COMPUTER, "Computer mode")
		_expect(game.terminal_ui.visible, "Full-screen UI visible")
		_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Computer cursor visible")
		_expect(game.transition_camera.current, "Transition camera remains at monitor")
		if cycle % 2 == 0:
			game._input(_action("back"))
		else:
			game.exit_button.pressed.emit()
		game.leave_computer() # Repeated exit must be ignored.
		_expect(game.mode == game.Mode.LEAVING, "Leaving mode")
		await create_timer(0.12).timeout
		await _frames(3)
		_expect(game.mode == game.Mode.WALKING, "Walking restored")
		_expect(not game.terminal_ui.visible, "Desktop hidden")
		_expect(player.controls_enabled and player.camera.current, "Player control/camera restored")
		_expect(_standing_space_is_clear(), "Exit point clear")
		_expect(player.position.distance_to(game.terminal.get_node("ExitPoint").global_position) < 0.1, "Returns beside chair")

	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Focus loss releases mouse")
	_expect(player.velocity == Vector3.ZERO, "Focus loss clears velocity")

	# Optional real-render captures for visual inspection (not available headless).
	if "--capture" in OS.get_cmdline_user_args():
		player.position = Vector3(1.9, 0.02, 1.8)
		player.rotation = Vector3(0, 0.35, 0)
		player.head.rotation = Vector3(-0.12, 0, 0)
		await _capture("room")
		player.position = Vector3(4.2, 0.02, 2.7)
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3.ZERO
		await _capture("corridor")
		game.enter_computer()
		await create_timer(0.12).timeout
		await _capture("desktop")

	print("PROTOTYPE SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _walk(start: Vector3, yaw: float, action: StringName, frames: int) -> void:
	player.position = start
	player.rotation = Vector3(0, yaw, 0)
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(2)


func _standing_space_is_clear() -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.73
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(0, 0.89, 0))
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query).is_empty()


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _shift_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("SMOKE: " + message)


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var directory := OS.get_user_data_dir()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	var output := directory.path_join("prototype_%s.png" % label)
	image.save_png(output)
	print("CAPTURE: " + output)
