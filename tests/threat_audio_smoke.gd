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

	if failures == 0:
		print("THREAT AUDIO SMOKE: PASS (0 failures)")
	else:
		print("THREAT AUDIO SMOKE: FAIL (%d failures)" % failures)
	quit(0 if failures == 0 else 1)
