extends Node
var failures: int = 0
var game: Node3D


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("DEFEAT: " + message)


func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().process_frame


func setup() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames()
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.threats.set_process(false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	await frames()
	game.set_process(false)


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/defeat_" + name + ".png")


func _run() -> void:
	for reason: String in ["POLICE_DEATH", "NEIGHBOR_DEATH", "ENTITY_DEATH"]:
		await setup()
		game.terminal_ui.notepad.editor.text = "retain evidence"
		var source: Node3D = game.police.visual if reason == "POLICE_DEATH" else game.neighbor.visual if reason == "NEIGHBOR_DEATH" else game.outage.entity.visual
		source.show()
		source.global_position = Vector3(1.2, 0, 1.1)
		expect(game.begin_threat_capture(reason, source), "Capture begins: " + reason)
		var scene: DefeatCutscene = game.capture_cutscene
		expect(
			scene.jumpscare_audio.playing
			and scene.jumpscare_audio.stream.resource_path == "res://assets/audio/jumpscare.wav",
			"Every enemy capture starts jumpscare.wav",
		)
		expect(scene.on_location and scene.global_position.y > -1.0, "Scene stays in the apartment")
		expect(not scene.get_node("Floor").visible and not scene.get_node("BackWall").visible and scene.view.environment == null, "Real room replaces preview geometry and environment")
		scene.seek(0.4)
		expect(scene.view.global_position.distance_to(game.transition_camera.global_position) < 0.02, "Camera switch preserves capture eye position")
		expect(not source.visible, "Original visitor is replaced, not duplicated")
		scene.seek(0.0)
		expect(scene.duration_seconds >= 5.0 and scene.duration_seconds <= 7.0, "Long full scene duration")
		expect(scene.actor.skeleton != null and scene.actor.skeleton.find_bone("DEF-hand.L") >= 0, "Actual GuyRig skeleton is bound")
		expect(scene.actor.model.scene_file_path == "res://assets/models/GuyRig.glb", "Uses replaceable GuyRig, not placeholder")
		expect(scene.cue_sounds.is_empty(), "No created or placeholder audio")
		expect(not game.begin_threat_capture("POLICE_DEATH", source), "No second attack can replace capture")
		expect(game.player.process_mode == Node.PROCESS_MODE_DISABLED and game.power.process_mode == Node.PROCESS_MODE_DISABLED, "Body and power clocks frozen")
		var clock: float = game.shift.step_time
		var stamina: float = game.player.stamina.value
		var points: Array[float] = [0.85, 1.45, 1.85, 2.75, 3.85, 5.4]
		for time: float in points:
			game._process(time - scene.elapsed)
			await frames()
			expect(not game.run_ended and game.mode == game.Mode.CAPTURED, "Result cannot appear during choreography")
			expect(scene.view.current and scene.view.near <= 0.02, "Staging camera active with close-up clipping allowance")
			expect(scene.actor.transform.is_finite() and scene.view.transform.is_finite(), "Finite rig and camera poses")
			expect(game.shift.step_time == clock and game.player.stamina.value == stamina, "World remains frozen")
			expect(not game.hud.fatigue.visible and not game.visual_effects.crt.visible, "Legacy effects do not obscure choreography")
			await capture(reason.to_lower() + "_" + str(roundi(time * 100)))
		if reason == "POLICE_DEATH":
			expect(scene.view.position.y < 0.3 and scene.view.rotation_degrees.x > 55.0, "Police pins the face-up camera to the floor")
		elif reason == "NEIGHBOR_DEATH":
			expect(scene._emitted.has(&"hit_1") and scene._emitted.has(&"hit_2") and scene._emitted.has(&"hit_3"), "Neighbor delivers three separate impacts")
		else:
			expect(scene.actor.position.z > 0.8 and scene._emitted.has(&"face"), "Entity holds a face-filling close-up")
		var escaped := InputEventKey.new()
		escaped.physical_keycode = KEY_ESCAPE
		escaped.pressed = true
		game._input(escaped)
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		expect(not game.run_ended and game.mode == game.Mode.CAPTURED, "Esc and focus changes cannot skip")
		game._process(scene.duration_seconds - scene.elapsed - 0.05)
		expect(not game.run_ended, "Last hold is mandatory")
		game._process(0.06)
		expect(game.run_ended and game.failure_reason == reason, "Ends once with correct reason")
		expect(game.terminal_ui.notepad.editor.text == "retain evidence", "Notes survive full sequence")
		var restart := get_viewport().gui_get_focus_owner() as Button
		expect(restart != null, "Result focuses restart")
		restart.pressed.emit()
		await frames()
		game = get_tree().current_scene
		game.threats.set_process(false)
		game.shift.set_process(false)
		expect(game.capture_reason.is_empty() and game.mode == game.Mode.WALKING, "Restart restores normal gameplay")
		expect(game.player.process_mode != Node.PROCESS_MODE_DISABLED and game.capture_cutscene == null, "No frozen body or stage after restart")
	# Different rooms, attack bearings and tight spaces keep the real environment.
	for location: Dictionary in [
		{"name": "room_wall", "position": Vector3(-2.65, 0.03, 0.2), "direction": Vector3.RIGHT},
		{"name": "bedroom", "position": Vector3(0.7, 0.03, 4.4), "direction": Vector3.FORWARD},
		{"name": "corridor", "position": Vector3(4.2, 0.03, -2.0), "direction": Vector3.BACK},
	]:
		for reason: String in ["POLICE_DEATH", "NEIGHBOR_DEATH", "ENTITY_DEATH"]:
			await setup()
			game.player.set_physics_process(false)
			game.player.global_position = location.position
			await get_tree().physics_frame
			await get_tree().physics_frame
			var source: Node3D = game.police.visual
			source.global_position = location.position + location.direction * 0.7
			source.show()
			expect(game.begin_threat_capture(reason, source), "Location capture begins")
			var scene: DefeatCutscene = game.capture_cutscene
			var eye: Vector3 = game.transition_camera.global_position
			for time: float in [0.4, 0.85, 1.85, 2.75, 3.85, 5.4]:
				scene.seek(time)
				expect(scene.view.global_position.distance_to(eye) < 1.8, "Camera remains at the actual attack site")
				var shape := SphereShape3D.new()
				shape.radius = 0.075
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = shape
				query.transform.origin = scene.view.global_position
				query.collision_mask = 1
				query.exclude = [game.player.get_rid()]
				expect(game.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Camera does not enter room geometry: " + location.name)
				await frames()
				if is_equal_approx(time, 2.75):
					await capture(location.name + "_" + reason.to_lower())
	# Monster contact uses the same pipeline rather than a direct result.
	await setup()
	game.trigger_power_outage()
	game.player.position = Vector3(4.2, 0.03, -2.0)
	var entity: CorridorEntity = game.outage.entity
	entity.global_position = game.player.global_position
	entity.phase = CorridorEntity.Phase.ACTIVE
	entity.is_chasing = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if game.capture_reason.is_empty():
		entity._pursue_player(0.01)
	expect(game.capture_reason == "ENTITY_DEATH" and not game.run_ended, "Physical monster contact starts a long scene")
	game.queue_free()
	await frames()
	await get_tree().create_timer(0.2).timeout
	print("DEFEAT CUTSCENES: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
