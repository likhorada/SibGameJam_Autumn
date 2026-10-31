extends SceneTree
## Repeated run teardown with live threats and result overlays must not orphan nodes.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("THREAT LIFECYCLE: " + message)


func settle() -> void:
	for frame: int in 4:
		await process_frame


func _run() -> void:
	await settle()
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var baseline_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var scene := load("res://scenes/main.tscn") as PackedScene
	var events: Array[StringName] = [&"psych_neighbor", &"police_raid", &"power_outage"]
	for cycle: int in 12:
		var game := scene.instantiate()
		root.add_child(game)
		current_scene = game
		game.threats.set_process(false)
		game.shift.set_process(false)
		game.ambient.random_chance = 0.0
		await physics_frame
		var event_id: StringName = events[cycle % events.size()]
		expect(game.threats.request_event(event_id, true), "Threat starts in fresh run: " + str(event_id))
		if cycle % 2 == 0:
			game.fail_from_threat("ENTITY_DEATH")
			expect(not game.threats.is_busy(), "Death clears active reservation")
			expect(not game.neighbor.footsteps_audio.playing and not game.police.footsteps_audio.playing and not game.outage.entity.footsteps_audio.playing, "Death stops threat footsteps")
		var previous: WeakRef = weakref(game)
		game.queue_free()
		game = null
		await settle()
		expect(previous.get_ref() == null, "Run freed after teardown")
		expect(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == baseline_nodes, "Node count returns to baseline after cycle %d" % cycle)
		expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == baseline_orphans, "No orphan nodes after cycle %d" % cycle)
	# AudioServer releases stopped voices on its mixing thread, not process_frame.
	await create_timer(0.2).timeout
	print("THREAT LIFECYCLE SMOKE: %s (%d failures, 12 run teardowns)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
