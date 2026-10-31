extends Node
## Deterministic native/Web regression checks for the agreed fairness contract.
var game: Node3D
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIRNESS: " + message)


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
	game.ambient.random_chance = 0.0
	game.transition_seconds = 0.02
	await frames()


func tick(seconds: float) -> void:
	for index: int in ceili(seconds / 0.05):
		game.threats.advance(0.05)


func face_player(observer: Node3D) -> void:
	observer.look_at(Vector3(game.player.global_position.x, observer.global_position.y, game.player.global_position.z), Vector3.UP)


func wall_at(position: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 2.5, 2.0)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = position
	return wall


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/fairness_" + name + ".png")


func _run() -> void:
	await setup()
	for locale: String in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		expect(tr("THREAT_HIDE") == ("ПРЯЧЬСЯ" if locale == "ru" else "HIDE"), "Localized police warning")
		expect(tr("THREAT_FREEZE") == ("ЗАМРИ" if locale == "ru" else "FREEZE"), "Localized entity warning")
	# Arrival while entering PC cancels the tween, preserves text and clears keys.
	game.terminal_ui.notepad.editor.text = "keep my evidence"
	game.enter_computer()
	Input.action_press("move_forward")
	expect(game.trigger_police(), "Police starts during PC transition")
	expect(game.mode == game.Mode.WALKING and game.player.camera.current, "Forced exit restores the body camera immediately")
	expect(not Input.is_action_pressed("move_forward"), "Forced exit clears stale WASD")
	expect(game.terminal_ui.notepad.editor.text == "keep my evidence", "Forced exit preserves notes")
	expect(game.police.visual.visible and game.police.settings.arrival_sound == null, "Visible arrival works without optional WAV")
	expect(game.hud.warning_key() == "THREAT_HIDE", "Hide warning independent of stamina alpha")
	await frames()
	expect(game.mode == game.Mode.WALKING, "Cancelled PC tween cannot reclaim the camera")
	await capture("arrival")
	game.threats.advance(12.0)
	expect(not game.run_ended and game.capture_reason.is_empty(), "Warning expiry never globally kills")
	expect(game.room_door.held_by_police and not game.room_door.set_open(false), "Police holds the open door")
	# Sight accumulates on body points, not on the displaced camera.
	game.player.position = Vector3(0, 0.03, 1.1)
	game.police.visual.global_position = Vector3(1.4, 0, 1.1)
	face_player(game.police.visual)
	var sight: ThreatAwareness = game.police.awareness
	var camera_pose: Transform3D = game.player.camera.global_transform
	game.player.camera.global_position = Vector3(-2, 1.6, 5)
	sight.advance(game, game.police.visual, 0.1)
	expect(sight.visible_now, "Moving camera behind geometry does not hide the exposed body")
	game.player.camera.global_transform = camera_pose
	sight.suspicion = 0.0
	game.police.visual.rotate_y(PI)
	sight.advance(game, game.police.visual, 0.1)
	expect(not sight.visible_now and sight.suspicion == 0.0, "Visitor does not see through the back of its head")
	face_player(game.police.visual)
	for index: int in 7:
		sight.advance(game, game.police.visual, 0.1)
	expect(is_equal_approx(sight.suspicion, 0.7), "Partial sight does not capture")
	var wall := wall_at(Vector3(0.7, 1.2, 1.1))
	await frames()
	sight.advance(game, game.police.visual, 0.1)
	expect(not sight.visible_now and sight.suspicion < 0.7 and sight.suspicion > 0.0, "Wall blocks sight; suspicion decays instead of resetting")
	for index: int in 20:
		sight.advance(game, game.police.visual, 0.1)
	expect(sight.suspicion == 0.0, "Two seconds safe restores calm")
	wall.queue_free()
	await frames()
	# Authoritative hiding defeats the external capsule, not just the camera ray.
	expect(game.enter_hiding(game.hiding_spots[&"hide_wardrobe"]), "Enter authoritative hiding")
	expect(game.threat_target_points().is_empty() and game.hud.warning_key().is_empty(), "Hidden body is not exposed and hide warning disappears")
	sight.advance(game, game.police.visual, 0.1)
	expect(not sight.visible_now, "Observer ignores the capsule left outside hiding")
	game.police.visual.global_position = game.hiding_spot.get_node("Exits/Front").global_position
	expect(not game.leave_hiding(false) and game.is_hidden(), "Enemy at main exit refuses exit instead of teleporting to alternate")
	game.police.visual.global_position = Vector3(1.4, 0, 1.1)
	expect(game.leave_hiding(false), "Exit resumes once main exit clears")
	expect(game.hud.warning_key() == "THREAT_HIDE", "Early exit restores police warning")
	game.player.position = Vector3(0, 0.03, 1.1)
	face_player(game.police.visual)
	tick(1.1)
	expect(game.capture_reason == "POLICE_DEATH" and not game.run_ended, "One second sight confirms staged capture")
	expect(not game.enter_hiding(game.hiding_spots[&"hide_bed"]), "Confirmed capture cannot be cancelled by hiding")
	game.threats.advance(100.0)
	expect(game.police.visual.visible and game.threats.capture_in_progress, "Watchdog cannot delete confirmed attacker")
	game._process(0.7)
	await capture("capture")
	game._process(0.6)
	expect(game.run_ended and game.failure_reason == "POLICE_DEATH", "Capture ends once with the right reason")
	# Forced door opening safely displaces a blocking player.
	await setup()
	game.player.position = Vector3(2.3, 0.03, 1.76)
	await frames()
	expect(game.room_door.force_open(game), "Forced opening handles a player in the leaf pose")
	expect(game.room_door.is_open and game.room_door.held_by_police, "Forced door enters held state")
	game.room_door.held_by_police = false
	game.room_door.set_open(false)
	# An unseen hidden player survives the full neighbor search and departure.
	await setup()
	game.player.position = Vector3(-1.85, 0.03, 1.35)
	game.enter_hiding(game.hiding_spots[&"hide_wardrobe"])
	game.room_door.set_open(true)
	game.trigger_neighbor()
	game.threats.advance(5.0)
	game.threats.advance(3.0)
	expect(game.neighbor.visit == PsychNeighbor.Visit.SEARCHING and not game.run_ended, "Neighbor entry starts search")
	game.threats.advance(game.neighbor.settings.search_seconds)
	game.threats.advance(game.neighbor.settings.departure_seconds)
	expect(not game.run_ended and game.neighbor.visit == PsychNeighbor.Visit.DORMANT, "Hidden player survives neighbor search")
	# Entity at fusebox: eject, retain lever progress, fixed warning bonus.
	await setup()
	game.trigger_power_outage()
	game.player.position = Vector3(4.2, 0.03, -5.0)
	await frames()
	game.enter_fusebox()
	await frames(5)
	game.power.board.latched[0] = true
	Input.action_press("move_forward")
	var entity: CorridorEntity = game.outage.entity
	expect(entity._try_encounter(), "Free corridor route can spawn near fusebox")
	expect(game.mode == game.Mode.WALKING and not game.power.board.active, "Entity interrupts fusebox including transitions")
	expect(entity.warning_duration == 4.0 and game.power.board.latched[0], "Warning includes fixed exit allowance; latched lever survives")
	expect(not Input.is_action_pressed("move_forward"), "Fusebox exit clears stale movement")
	expect(game.hud.warning_key() == "THREAT_FREEZE", "Entity shows freeze warning")
	game.power.set_flashlight_enabled(false)
	entity.advance(entity.warning_duration)
	entity.error_seconds = 0.7
	entity.advance(0.2)
	expect(entity.error_seconds < 0.7 and not entity.is_chasing, "Safe behavior gradually forgives entity exposure")
	# Chase owns a new full clock even when the encounter was nearly over.
	entity.elapsed = entity.duration - 0.01
	entity.is_chasing = true
	entity.chase_elapsed = 0.0
	entity.advance(0.1)
	expect(entity.is_chasing and entity.phase == CorridorEntity.Phase.ACTIVE, "Chase ignores the old encounter deadline")
	entity.advance(5.8)
	expect(entity.is_chasing, "Chase lasts six seconds")
	entity.advance(0.11)
	expect(entity.phase == CorridorEntity.Phase.RETREATING and entity.visual.visible, "Chase ends with visible retreat")
	entity.advance(entity.settings.retreat_seconds)
	expect(entity.phase == CorridorEntity.Phase.WAITING and not entity.visual.visible, "Retreat completes before repeat cooldown")
	# Hidden capsules cannot take entity contact damage.
	game.player.position = Vector3(-1.85, 0.03, 1.35)
	game.enter_hiding(game.hiding_spots[&"hide_wardrobe"])
	entity.global_position = game.player.global_position
	expect(not entity._touching_player(), "Entity contact ignores authoritative hiding")
	game.power.restore_power()
	expect(not game.threats.is_busy() and entity.phase == CorridorEntity.Phase.DORMANT, "Repair clears all entity phases")
	# A real closed leaf blocks both exposure and physical pursuit into the room.
	await setup()
	game.trigger_power_outage()
	game.power.set_flashlight_enabled(false)
	entity = game.outage.entity
	entity.set_physics_process(false)
	game.player.position = Vector3(1.8, 0.03, 1.1)
	entity.global_position = Vector3(3.8, 0, 1.1)
	entity.phase = CorridorEntity.Phase.ACTIVE
	entity.duration = 5.0
	entity.visual.show()
	await frames()
	entity.advance(0.1)
	expect(entity.error_seconds == 0.0, "Movement behind closed door does not provoke creature")
	entity.is_chasing = true
	for index: int in 10:
		entity._pursue_player(0.05)
	expect(not game.run_ended and entity.global_position.x > 3.1, "Closed door physically blocks chase and contact death")
	expect(game.room_door.set_open(true), "Room door can open after creature was blocked")
	await frames()
	for index: int in 3:
		entity._pursue_player(0.1)
	expect(entity.global_position.x < 3.0, "Creature can cross an open doorway into apartment")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("THREAT FAIRNESS: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
