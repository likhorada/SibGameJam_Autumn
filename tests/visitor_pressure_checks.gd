extends Node
var game: Node3D
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("PRESSURE: " + message)


func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().physics_frame


func setup() -> void:
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
	await frames()


func hide(id: StringName) -> void:
	game.player.position = Vector3(-1.85, 0.03, 1.35) if id == &"hide_wardrobe" else Vector3(-0.55, 0.03, 4.5)
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	expect(game.enter_hiding(game.hiding_spots[id]), "Player enters " + String(id))


func start(id: StringName) -> ThreatEvent:
	if id == &"psych_neighbor":
		game.room_door.set_open(true)
	expect(game.threats.request_event(id, true), "Start " + String(id))
	game.threats.advance(12.0 if id == &"police_raid" else 5.0)
	if id == &"psych_neighbor":
		game.threats.advance(game.neighbor.settings.attack_delay)
	return game.police if id == &"police_raid" else game.neighbor


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/pressure_" + name + ".png")


func searching(id: StringName, visitor: ThreatEvent) -> bool:
	return visitor.visit == (PoliceRaid.Visit.SEARCHING if id == &"police_raid" else PsychNeighbor.Visit.SEARCHING)


func _run() -> void:
	for id: StringName in [&"police_raid", &"psych_neighbor"]:
		for spot_id: StringName in [&"hide_wardrobe", &"hide_bed"]:
			await setup()
			hide(spot_id)
			var visitor: ThreatEvent = start(id)
			var pressure: VisitorPressure = visitor.pressure
			var began: float = game.threats.run_seconds
			for index: int in 240:
				game.threats.advance(0.05)
				if pressure.holding or not searching(id, visitor):
					break
			expect(pressure.used and pressure.holding, "One listening stop starts: " + String(id) + "/" + String(spot_id))
			if not pressure.holding:
				continue
			var stopped: Vector3 = visitor.visual.global_position
			var spot: HidingSpot = game.hiding_spot
			expect(stopped.distance_to(spot.pressure_point.global_position) < 0.01, "Uses the authored safe stop")
			var visible_point := stopped + Vector3.UP * (1.45 if spot_id == &"hide_wardrobe" else 0.25)
			expect(game.transition_camera.is_position_in_frustum(visible_point), "Stop is in the actual hiding-camera frustum")
			expect(not visitor.footsteps_audio.playing and game.is_hidden(), "Footsteps stop while hiding remains safe")
			var travel_clock := pressure.movement_elapsed
			var old_head: Vector3 = visitor.visual.get_node("Head").rotation
			for index: int in 20:
				game.threats.advance(0.05)
			expect(is_equal_approx(pressure.movement_elapsed, travel_clock) and visitor.visual.global_position.is_equal_approx(stopped), "Listening pauses travel, not the run clock")
			expect(not visitor.visual.get_node("Head").rotation.is_equal_approx(old_head), "Head actually scans during listening")
			expect(not visitor.footsteps_audio.playing and game.capture_reason.is_empty(), "Listening is quiet and never detects a hidden player")
			game.shift._begin_route(game.shift.location.route())
			game.shift.advance(0.5)
			expect(game.shift.step_time > 0.4 and pressure.holding, "Observation timeline can progress during pressure")
			await capture(String(id) + "_" + String(spot_id))
			for index: int in 200:
				var previous: Vector3 = visitor.visual.global_position
				game.threats.advance(0.05)
				expect(previous.distance_to(visitor.visual.global_position) < 0.16, "No teleport or excessive sprint on detour")
				if not searching(id, visitor):
					break
			expect(pressure.used and not pressure.holding and pressure.finished, "Listening completes only once")
			expect(absf(game.threats.run_seconds - began - visitor.settings.search_seconds - visitor.settings.pressure_seconds) < 0.11, "Exactly four seconds added to search")
			# Leaving/re-entering after the episode cannot restart it during departure.
			for index: int in 50:
				if not game.enemy_blocks_exit(spot.get_node("Exits").get_child(0).global_position):
					break
				game.threats.advance(0.05)
			expect(game.leave_hiding(false), "Exit is available once the visitor clears it")
			expect(game.enter_hiding(spot), "Can re-enter the same hiding spot")
			var hold_time := pressure.hold_elapsed
			game.threats.advance(0.05)
			expect(is_equal_approx(pressure.hold_elapsed, hold_time) and not pressure.holding, "Rehiding does not retrigger listening")
			for index: int in 100:
				if not game.threats.is_busy():
					break
				game.threats.advance(0.05)
			expect(not game.run_ended and game.is_hidden() and not game.threats.is_busy(), "Patient hiding survives the complete visit")
		# No changes to the search when the player never hides.
		await setup()
		game.player.position = Vector3(4.2, 0.03, 6.4)
		var visitor: ThreatEvent = start(id)
		game.threats.advance(visitor.settings.search_seconds)
		expect(not visitor.pressure.used and not searching(id, visitor), "No extra delay without hiding")
		# A blocked detour is skipped, not traversed through architecture.
		await setup()
		var wall := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.2, 2.5, 1.4)
		collision.shape = box
		wall.add_child(collision)
		game.add_child(wall)
		wall.position = Vector3(-0.4, 1.2, 1.35)
		await frames()
		hide(&"hide_wardrobe")
		visitor = start(id)
		game.threats.advance(visitor.settings.search_seconds)
		expect(not visitor.pressure.used and not game.run_ended, "Blocked path falls back to ordinary safe search")
		# Disabling a listening visitor restores pose and clears the one-shot state.
		await setup()
		hide(&"hide_bed")
		visitor = start(id)
		game.threats.advance(visitor.settings.search_seconds)
		expect(visitor.pressure.holding, "Bedside pause starts at the route end")
		game.threats.set_event_enabled(id, false)
		expect(not visitor.pressure.used and not visitor.pressure.holding and game.is_hidden(), "Cancellation clears pressure without exposing player")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("VISITOR PRESSURE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
