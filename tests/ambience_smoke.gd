extends SceneTree
## godot --headless --path . --script res://tests/ambience_smoke.gd
## Verifies player volume and fusebox playback state, not subjective sound quality.

var failures: int = 0
var game: Node3D

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("AMBIENCE: " + message)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 3) -> void:
	for index: int in count:
		await physics_frame

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.04
	await frames()
	var ambient: AmbientDirector = game.ambient
	expect(ambient != null and ambient.game == game, "Ambient director bound to run")
	# Importer option 2 maps to AudioStreamWAV.LOOP_FORWARD.
	expect(ambient.noise_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Base hum is a forward loop")
	expect(ambient.near_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Approach hum is a forward loop")
	expect(ambient.event_audio.stream == null, "No random sound until its timer fires")
	await create_timer(0.6).timeout
	expect(ambient.noise_audio.playing, "Base hum plays while powered")
	expect(ambient.noise_audio.volume_db > -13.0 and ambient.noise_audio.volume_db <= -11.0, "Base hum near export volume")
	var board: ApartmentFusebox = game.power.board
	# Random one-shots need a manual chance; impossible scheduling keeps it silent otherwise.
	ambient.random_chance = 1.0
	ambient.random_min_interval = 0.2
	ambient.random_max_interval = 0.2
	ambient._schedule_event()
	await create_timer(0.5).timeout
	expect(ambient.event_audio.playing, "Watched apartment plays random scratch/knock")
	ambient.event_audio.stop()
	game.mode = game.Mode.COMPUTER
	ambient._event_left = 0.0
	ambient._tick_events(1.0)
	expect(not ambient.event_audio.playing, "No random events at the PC")
	game.mode = game.Mode.WALKING
	game.dev_menu.is_open = true
	ambient._tick_events(1.0)
	expect(not ambient.event_audio.playing, "No random events in the dev menu")
	game.dev_menu.is_open = false
	game.mode = game.Mode.FUSEBOX
	ambient._tick_events(1.0)
	expect(not ambient.event_audio.playing, "No random events at the fusebox")
	game.mode = game.Mode.WALKING
	ambient.random_chance = 0.0
	ambient.random_min_interval = 10.0
	ambient.random_max_interval = 20.0
	ambient.powered = true
	ambient.noise_audio.play()
	# Held fusebox lever: electric buzz plays, release is silent.
	game.power.trigger_outage()
	await create_timer(0.6).timeout
	expect(not ambient.noise_audio.playing and not ambient.near_audio.playing, "Outage fades both hums to stop")
	expect(ambient.powered == false, "Director follows the power signal")
	ambient.random_chance = 1.0
	ambient._event_left = 0.0
	ambient._tick_events(1.0)
	expect(not ambient.event_audio.playing, "No random events during blackout")
	ambient.random_chance = 0.0
	board.set_active(true, game.transition_camera)
	board.set_physics_process(false)
	board.begin_hold(0)
	expect(board.motion_audio.playing and board.motion_audio.stream == preload("res://assets/audio/elecric_fixing.wav"), "Held lever plays elecric_fixing")
	await create_timer(0.2).timeout
	expect(board.motion_audio.playing, "Loop keeps buzzing through the hold")
	board.cancel_hold()
	expect(not board.motion_audio.playing, "Released lever stays silent")
	expect(not game.power.powered, "Fixing alone does not restore power")
	game.power.restore_power()
	await create_timer(0.6).timeout
	expect(ambient.noise_audio.playing, "Power restore returns base hum")
	# Distance drives the approach loop: full near the monitor, silent far away.
	game.power.trigger_outage()
	await create_timer(0.6).timeout
	expect(not ambient.noise_audio.playing and not ambient.near_audio.playing, "Outage silences both loops again")
	game.power.restore_power()
	var monitor: Node3D = game.terminal.get_node("MonitorView")
	game.player.global_position = monitor.global_position + Vector3(0.8, 0.0, 0.0)
	await create_timer(0.6).timeout
	expect(ambient.near_audio.playing and ambient.near_audio.volume_db > -20.0, "Near the PC the approach loop is loud")
	game.player.global_position = monitor.global_position + Vector3(12.0, 1.0, 0.0)
	await create_timer(1.4).timeout
	expect(not ambient.near_audio.playing, "Far away the approach loop faded out and stopped")
	game.player.global_position = monitor.global_position + Vector3(0.8, 0.0, 0.0)
	await create_timer(0.6).timeout
	expect(ambient.near_audio.playing and ambient.near_audio.volume_db > -20.0, "Walking back returns the approach loop")
	# Final drift check: the result screen kills every ambient voice.
	game._finish_report(false, 0)
	await frames()
	expect(ambient.powered == false, "Result disables the director")
	expect(not ambient.noise_audio.playing and not ambient.near_audio.playing and not ambient.event_audio.playing, "Result stops all ambience")
	game.queue_free()
	await frames()
	print("AMBIENCE SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
