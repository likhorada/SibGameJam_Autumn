extends SceneTree
## Native visual acceptance: live skeletal motion + captures at key stages.

var game: Node3D
var shift: ShiftDirector


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	game.atmosphere_config = AtmosphereConfig.new()
	root.add_child(game)
	current_scene = game
	shift = game.shift
	shift.set_process(false)
	game.threats.set_process(false)
	game.power.set_process(false)
	game.transition_seconds = 0.02
	game.enter_computer()
	await create_timer(0.2).timeout
	game.terminal_ui.launch_app(&"cctv")
	await create_timer(0.7).timeout
	await _capture("work")
	shift.state = ShiftDirector.State.DEADLINE
	shift.start_alarm()
	await _advance(0.7)
	await _capture("standing_up")
	await _advance(1.2)
	await _capture("first_steps")
	await _advance(14.5)
	await _capture("exit", 1)
	await _advance(2.2)
	# Skip the uneventful first two shop segments, but sample real-time pickup/carry.
	shift.advance(29.8)
	await _advance(0.5)
	await _capture("pickup", 1)
	await _advance(6.3)
	await _capture("carrying", 2)
	shift.advance(8.0)
	await _advance(0.6)
	await _capture("checkout", 2)
	shift.advance(30.0)
	shift.advance(12.0)
	await _advance(23.0)
	await _capture("decoys", maxi(shift.branch, 0))
	game.queue_free()
	await process_frame
	await process_frame
	print("CCTV ANIMATION VISUAL: complete; inspect cctv_anim_*.png")
	quit()


func _advance(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame
		shift.advance(root.get_process_delta_time())


func _capture(label: String, camera: int = 0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.terminal_ui.cctv.directory.select(camera)
	game.terminal_ui.cctv._select(camera)
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA").path_join("Temp/opencode/cctv_anim_" + label + ".png"))
