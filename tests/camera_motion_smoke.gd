extends SceneTree
## godot --path . --script res://tests/camera_motion_smoke.gd
## Needs a real display for captured-mouse input, just like prototype_smoke.gd.

var failures: int = 0
var game: Node3D
var player: ApartmentPlayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Omit --headless for camera/input tests.")
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.08
	player = game.player
	_spawn(Vector3(4.2, 0.02, 3.5))
	await _frames(12)

	Input.action_press("move_forward")
	await _frames(3)
	var initial_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_expect(initial_speed > 0.1 and initial_speed < player.walk_speed, "Short acceleration, not instant full speed")
	await _frames(20)
	_expect(is_equal_approx(player.velocity.length(), player.walk_speed), "Walk reaches configured speed")
	_expect(player.camera_motion.position.length() > 0.002, "Walking produces bob")
	Input.action_release("move_forward")
	await _frames(2)
	_expect(player.velocity.length() > 0.05 and player.velocity.length() < player.walk_speed, "Short braking, not instant stop")
	await _frames(45)
	_expect(player.velocity.length() < 0.01, "Braking settles to rest")
	_expect(player.camera_motion.position.length() < 0.001, "Bob settles to neutral")
	_expect(player.camera_motion.rotation.length() < 0.001, "Acceleration tilt settles")

	_spawn(Vector3(4.2, 0.02, 3.5))
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await _frames(18)
	_expect(Vector2(player.velocity.x, player.velocity.z).length() <= player.walk_speed + 0.01, "Diagonal input is normalized")
	_expect(player.camera_motion.rotation.z < -0.005, "Strafing banks the camera")
	Input.action_release("move_forward")
	Input.action_release("move_right")

	_spawn(Vector3(4.2, 0.02, 3.5))
	Input.action_press("sprint")
	await _frames(25)
	_expect(absf(player.camera.fov - 75.0) < 0.01, "Shift alone does not change FOV")
	Input.action_press("move_forward")
	await _frames(45)
	_expect(player.camera.fov > 79.0 and player.camera.fov <= 80.01, "Actual sprint widens FOV")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _frames(60)
	_expect(absf(player.camera.fov - 75.0) < 0.01, "Sprint FOV returns at rest")

	_spawn(Vector3(5.02, 0.02, 1.1))
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _frames(60)
	var phase_at_wall: float = player.camera_motion.step_phase
	await _frames(30)
	_expect(absf(player.camera_motion.step_phase - phase_at_wall) < 0.001, "No footsteps while pushing against a wall")
	_expect(player.camera_motion.position.length() < 0.001, "No stationary wall bob")
	_expect(absf(player.camera.fov - 75.0) < 0.01, "No sprint FOV against a wall")
	Input.action_release("move_right")
	Input.action_release("sprint")

	_spawn(Vector3(4.2, 0.02, 1.1))
	var mouse := InputEventMouseMotion.new()
	mouse.screen_relative = Vector2(20, 0)
	player._unhandled_input(mouse)
	_expect(absf(player.rotation.y) < 0.001, "Small mouse input starts with a bounded look lag")
	await _frames(3)
	_expect(player.rotation.y < -0.001 and player.rotation.y > -0.044, "Look smoothly catches up")
	_expect(absf(player.camera_motion.rotation.z) > 0.0001, "Turning gives visual roll")
	await _frames(40)
	_expect(absf(player.rotation.y + 0.044) < 0.001, "Smoothed look preserves total mouse input")
	mouse.screen_relative = Vector2(0, -20000)
	player._unhandled_input(mouse)
	await _frames(3)
	_expect(player.head.rotation.x <= deg_to_rad(80.0) + 0.0001, "Pitch remains clamped on large flicks")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var released_yaw := player.rotation.y
	await _frames(20)
	_expect(is_equal_approx(player.rotation.y, released_yaw), "No delayed look after focus loss")
	_expect(player.velocity == Vector3.ZERO, "Focus loss stops motion immediately")

	# Isolated numerical check: visual response at 30, 60 and 144 render updates/sec.
	player.set_process(false)
	player.set_physics_process(false)
	var pose_30 := _simulate_visuals(30)
	var pose_60 := _simulate_visuals(60)
	var pose_144 := _simulate_visuals(144)
	_expect(pose_30.origin.distance_to(pose_144.origin) < 0.006, "Bob is consistent at 30/144 FPS")
	_expect(pose_60.origin.distance_to(pose_144.origin) < 0.003, "Bob is consistent at 60/144 FPS")
	_expect(pose_30.basis.get_euler().distance_to(pose_144.basis.get_euler()) < 0.002, "Roll smoothing is frame-rate independent")
	player.camera_motion.effect_strength = 0.0
	_simulate_visuals(60)
	_expect(player.camera_motion.position.length() < 0.0001, "Zero strength removes offsets")
	_expect(player.camera_motion.rotation.length() < 0.0001, "Zero strength removes roll/pitch")
	_expect(absf(player.camera.fov - 75.0) < 0.001, "Zero strength removes sprint FOV")
	player.camera_motion.effect_strength = 1.0
	player.set_process(true)
	player.set_physics_process(true)

	# Enter from a non-neutral rendered pose and FOV, without a handoff jump.
	_spawn(Vector3(0, 0.02, -0.55))
	player.camera_motion.position = Vector3(0.02, 0.03, 0)
	player.camera_motion.rotation = Vector3(0.01, 0, 0.03)
	player.camera.fov = 79.0
	var source_pose := player.camera.global_transform
	game.enter_computer()
	_expect(game.transition_camera.global_transform.is_equal_approx(source_pose), "PC inherits the exact rendered pose")
	_expect(is_equal_approx(game.transition_camera.fov, 79.0), "PC inherits sprint FOV before resetting")
	_expect(player.camera_motion.transform.is_equal_approx(Transform3D.IDENTITY), "Hidden player feedback resets")
	Input.action_press("move_forward")
	await create_timer(0.2).timeout
	_expect(game.mode == game.Mode.COMPUTER, "PC transition still completes")
	_expect(absf(game.transition_camera.fov - 75.0) < 0.001, "PC smoothly returns to base FOV")
	_expect(player.camera_motion.transform.is_equal_approx(Transform3D.IDENTITY), "No feedback behind the desktop")
	Input.action_release("move_forward")
	game.leave_computer()
	await create_timer(0.2).timeout
	_expect(game.mode == game.Mode.WALKING and player.camera.current, "Return to walking camera")
	_expect(absf(player.camera.fov - 75.0) < 0.001, "No FOV jump on return")
	_expect(player.camera_motion.position.length() < 0.001, "Return starts at neutral pose")

	print("CAMERA MOTION SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _simulate_visuals(fps: int) -> Transform3D:
	player.camera_motion.reset_motion()
	for index: int in range(fps):
		player.camera_motion.update_feedback(
			1.0 / fps, Vector3(1.5, 0, -4), Vector3.ZERO, Vector2(0.5, 0),
			true, true, true, player.walk_speed, player.sprint_speed
		)
	return player.camera_motion.transform


func _spawn(point: Vector3) -> void:
	player.position = point
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.stop_motion(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CAMERA: " + message)
