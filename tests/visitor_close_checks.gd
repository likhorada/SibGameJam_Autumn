extends Node
## Regression for circling through a visitor during supposedly safe approach/entry.
var game: Node3D
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("VISITOR CLOSE: " + message)


func setup(id: StringName) -> ThreatEvent:
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.threats.set_process(false)
	game.shift.set_process(false)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.ambient.random_chance = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect(game.threats.request_event(id, true), "Visitor starts: " + String(id))
	return game.police if id == &"police_raid" else game.neighbor


func enter_phase(id: StringName, phase: String) -> void:
	if id == &"police_raid":
		if phase != "warning":
			game.threats.advance(12.0)
		if phase == "departure":
			game.threats.advance(game.police.settings.search_seconds)
	else:
		if phase == "approach":
			return
		game.threats.advance(5.0)
		if phase in ["entry", "retreat", "search"]:
			game.room_door.set_open(true)
		if phase == "retreat":
			game.threats.advance(0.5)
			game.room_door.set_open(false)
		elif phase == "search":
			game.threats.advance(game.neighbor.settings.attack_delay)
		elif phase == "departure":
			game.threats.advance(game.neighbor.settings.rattle_seconds)


func walk_into_visitor(id: StringName) -> void:
	var visitor: ThreatEvent = await setup(id)
	game.player.position = Vector3(4.5, 0.03, 5.7)
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO
	game.player.stop_motion(true)
	game.player.set_physics_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("move_forward")
	game.threats.set_process(true)
	for index: int in 90:
		if not game.capture_reason.is_empty():
			break
		await get_tree().physics_frame
	Input.action_release("move_forward")
	game.threats.set_process(false)
	expect(not game.capture_reason.is_empty() and game.threats.state == ThreatManager.State.WARNING, "Actual walking from behind is caught during approach: " + String(id))
	expect(not game.player.controls_enabled and game.player.global_position.z > visitor.visual.global_position.z, "Capture stops walking before passing through visitor")


func _run() -> void:
	for id: StringName in [&"police_raid", &"psych_neighbor"]:
		var phases: Array = ["warning", "search", "departure"] if id == &"police_raid" else ["approach", "rattle", "entry", "retreat", "search", "departure"]
		for phase: String in phases:
			var visitor: ThreatEvent = await setup(id)
			enter_phase(id, phase)
			# Arrange an unobstructed room point, not an illegal position inside a wall.
			visitor.visual.global_position = Vector3(0, 0, 1.1)
			visitor.visual.rotation = Vector3.ZERO
			# Start behind, cross the side, then pass straight through the mesh.
			for offset: Vector3 in [Vector3(0, 0, 0.75), Vector3(0.7, 0, 0.1)]:
				game.player.global_position = visitor.visual.global_position + offset + Vector3.UP * 0.03
				game.threats.advance(0.1)
				expect(game.capture_reason.is_empty(), "Short reaction before capture: " + phase)
			game.player.global_position = visitor.visual.global_position + Vector3.UP * 0.03
			game.threats.advance(0.05)
			var reason := "POLICE_DEATH" if id == &"police_raid" else "NEIGHBOR_DEATH"
			expect(game.capture_reason == reason and not game.run_ended, "Circling/overlap captures at 0.25s during " + String(id) + "/" + phase)
			expect(game.capture_cutscene != null and game.capture_cutscene.duration_seconds >= 5.0, "Close capture keeps full unskippable scene")
		# An open entrance and a clear view should turn the visitor into a pursuer
		# immediately, even during the warning/approach phase.
		var chase_visitor: ThreatEvent = await setup(id)
		expect(game.room_door.set_open(true), "Door opens for the chase test")
		chase_visitor.visual.global_position = Vector3(1.2, 0, 1.1)
		game.player.global_position = Vector3(0, 0.03, 1.1)
		chase_visitor.visual.look_at(game.player.global_position, Vector3.UP)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var previous_distance: float = chase_visitor.visual.global_position.distance_to(game.player.global_position)
		game.threats.advance(0.1)
		var chasing: bool = game.police.visit == PoliceRaid.Visit.CHASING if id == &"police_raid" else game.neighbor.visit == PsychNeighbor.Visit.CHASING
		expect(chasing, "Visible visitor starts chasing through an open door: " + String(id))
		expect(chase_visitor.visual.global_position.distance_to(game.player.global_position) < previous_distance, "Chaser immediately moves toward the player: " + String(id))
		# Unit boundaries and recovery use the same actual visitor awareness object.
		var visitor: ThreatEvent = await setup(id)
		var spawn: Vector3 = game.room_door.get_node("Approach").global_position
		game.player.global_position = spawn + Vector3(0, 0.03, 0.4)
		expect(not visitor.can_schedule() and visitor.can_start(), "Random visit cannot spawn on player; forced debug remains available")
		game.player.global_position = spawn + Vector3(0, 0.03, -2.0)
		expect(visitor.can_schedule(), "Spawn margin does not disable distant visitors")
		visitor.visual.global_position = Vector3(0, 0, 1.1)
		var awareness: ThreatAwareness = visitor.awareness
		for angle: float in [0.0, PI / 2.0, PI, PI * 1.5]:
			awareness.reset()
			visitor.visual.rotation = Vector3.ZERO
			game.player.global_position = visitor.visual.global_position + Vector3(sin(angle) * 0.8, 0.03, cos(angle) * 0.8)
			awareness.advance_close(game, visitor.visual, 0.1)
			awareness.advance_close(game, visitor.visual, 0.1)
			expect(awareness.advance_close(game, visitor.visual, 0.05), "Close zone sees every direction")
		awareness.reset()
		game.player.position = Vector3(0, 0.03, 1.85)
		expect(not awareness.advance_close(game, visitor.visual, 3.0), "One stalled frame does not confirm instant close capture")
		awareness.reset()
		game.player.position = Vector3(0, 0.03, 2.15)
		for index: int in 20:
			awareness.advance_close(game, visitor.visual, 0.05)
		expect(awareness.close_suspicion == 0.0, "Outside one meter does not accumulate close capture")
		game.player.position = Vector3(0, 0.03, 1.85)
		awareness.advance_close(game, visitor.visual, 0.1)
		expect(awareness.close_suspicion > 0.0 and (-visitor.visual.global_basis.z).dot(Vector3.FORWARD * -1) > 0.9, "Visitor turns towards nearby player during reaction")
		game.player.position = Vector3(0, 0.03, 2.3)
		awareness.advance_close(game, visitor.visual, 0.1)
		expect(awareness.close_suspicion == 0.0, "Backing away quickly clears partial close exposure")
		# A wall blocks close capture even when distance is less than one meter.
		var wall := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1, 2.5, 1.0)
		collision.shape = box
		wall.add_child(collision)
		game.add_child(wall)
		wall.position = Vector3(0.4, 1.2, 1.1)
		game.player.position = Vector3(0.8, 0.03, 1.1)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for index: int in 10:
			awareness.advance_close(game, visitor.visual, 0.05)
		expect(not awareness.close_now and awareness.close_suspicion == 0.0, "Wall protects at close distance")
		wall.queue_free()
		await get_tree().physics_frame
		# Closed entrance protects; opening it exposes the same positions.
		visitor.visual.global_position = Vector3(3.6, 0, 1.1)
		game.player.position = Vector3(2.68, 0.03, 1.1)
		awareness.reset()
		for index: int in 10:
			awareness.advance_close(game, visitor.visual, 0.05)
		expect(awareness.close_suspicion == 0.0, "Closed door protects inside one meter")
		game.room_door.set_open(true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for index: int in 5:
			awareness.advance_close(game, visitor.visual, 0.05)
		expect(awareness.close_suspicion >= 0.99999, "Open doorway allows close capture")
		# Authoritative hiding removes the external capsule from close exposure too.
		game.player.position = Vector3(-1.85, 0.03, 1.35)
		expect(game.enter_hiding(game.hiding_spots[&"hide_wardrobe"]), "Enter hiding before confirmation")
		visitor.visual.global_position = game.player.global_position
		awareness.advance_close(game, visitor.visual, 0.1)
		expect(not awareness.close_now and awareness.close_suspicion == 0.0, "Hidden capsule clears close exposure")
		# The original distant warning window remains available.
		visitor = await setup(id)
		game.threats.advance(11.9 if id == &"police_raid" else 4.9)
		expect(game.capture_reason.is_empty() and game.threats.state == ThreatManager.State.WARNING, "Distant player keeps original warning")
		# No stored exposure on cancellation or the next visit.
		visitor.visual.global_position = Vector3(0, 0, 1.1)
		game.player.position = Vector3(0, 0.03, 1.85)
		game.threats.advance(0.05)
		expect(visitor.awareness.close_suspicion > 0.0, "Partial close exposure before cancellation")
		game.threats.set_event_enabled(id, false)
		expect(visitor.awareness.close_suspicion == 0.0, "Cancellation clears close exposure")
		game.threats.set_event_enabled(id, true)
		game.threats.request_event(id, true)
		expect(visitor.awareness.close_suspicion == 0.0, "New visit starts without stored exposure")
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		for id: StringName in [&"police_raid", &"psych_neighbor"]:
			await walk_into_visitor(id)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("VISITOR CLOSE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
