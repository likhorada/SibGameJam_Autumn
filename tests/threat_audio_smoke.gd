extends SceneTree
## godot --headless --path . --script res://tests/threat_audio_smoke.gd

var failures: int = 0


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("THREAT AUDIO: " + message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.02
	game.threats.set_process(false)
	game.shift.set_process(false)
	game.threats.set_event_enabled(&"power_outage", false)
	game.threats.set_event_enabled(&"psych_neighbor", false)
	for _frame: int in 4:
		await process_frame

	expect(game.trigger_police(), "Police raid starts")
	expect(
		game.police.footsteps_audio.playing
		and game.police.footsteps_audio.stream.resource_path == "res://assets/audio/police_steps.wav"
		and game.police.settings.departure_sound.resource_path == "res://assets/audio/police_steps.wav",
		"Police approach and departure use police_steps.wav",
	)
	expect(
		game.police.ambush_audio.playing
		and game.police.ambush_audio.stream.resource_path == "res://assets/audio/police_aimbush.wav"
		and game.police.knock_audio.playing
		and not game.room_door.is_open,
		"police_aimbush.wav plays with the initial knock before the door opens",
	)

	game.police._begin_chase()
	expect(
		game.threats.detected_audio.playing
		and game.threats.detected_audio.stream.resource_path == "res://assets/audio/detected.wav",
		"Police discovery plays detected.wav",
	)
	game.ambient._process(0.1)
	expect(not game.ambient.suspense_audio.playing, "Pursuit music waits during the detected cue")
	await create_timer(game.threats.detected_audio.stream.get_length() + 0.1).timeout
	game.ambient._process(0.1)
	expect(game.ambient.suspense_audio.playing, "Pursuit music starts after detected.wav finishes")

	game.ambient.suspense_audio.stop()
	game.threats.detected_audio.stop()
	game.police.visit = PoliceRaid.Visit.DORMANT
	game.neighbor.visit = PsychNeighbor.Visit.SEARCHING
	game.neighbor._begin_chase()
	expect(
		game.threats.detected_audio.playing
		and game.threats.detected_audio.stream.resource_path == "res://assets/audio/detected.wav",
		"Neighbor discovery uses the same detected cue",
	)

	game.disable_threats()
	game.threats.enabled = true
	game.threats.set_event_enabled(&"power_outage", true)
	expect(game.trigger_power_outage(), "Outage starts after police slot is released")
	expect(
		game.outage.spark_audio.playing
		and game.outage.spark_audio.stream.resource_path == "res://assets/audio/spark.wav"
		and game.outage.spark_audio.global_position.is_equal_approx(game.power.board.global_position),
		"Fusebox failure plays spark.wav at the board",
	)
	game.outage.spark_audio.stop()
	expect(not game.trigger_power_outage() and not game.outage.spark_audio.playing, "Rejected outage does not replay sparks")
	game.disable_threats()
	var previous_run: WeakRef = weakref(game)
	game.queue_free()
	# Let scene teardown and the audio server release their playback references.
	await process_frame
	await create_timer(0.2).timeout
	expect(previous_run.get_ref() == null, "Run is freed before shutting down the audio server")
	if failures == 0:
		print("THREAT AUDIO SMOKE: PASS (0 failures)")
	else:
		print("THREAT AUDIO SMOKE: FAIL (%d failures)" % failures)
	quit(0 if failures == 0 else 1)
