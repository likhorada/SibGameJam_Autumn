extends Node
## Shared deterministic suite for the power outage slot and the corridor entity.
## Headless runs the whole scenario; the native run adds real F-key input.

var game: Node3D
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("OUTAGE: " + message)


func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().physics_frame


func wait_mode(expected: int) -> void:
	for index: int in 60:
		if game.mode == expected:
			return
		await get_tree().process_frame
	expect(false, "Camera transition did not reach mode %d" % expected)


func setup() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.04
	game.threats.set_process(false)
	game.threats.set_event_enabled(&"psych_neighbor", false)
	game.threats.set_event_enabled(&"police_raid", false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	await frames()


func native_input() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless"


func key_press(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func direct_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._input(event)
	event = event.duplicate()
	event.pressed = false
	game._input(event)


func walk_to(position: Vector3) -> void:
	game.player.global_position = Vector3(position.x, 0.03, position.z)
	game.player.stop_motion(true)
	await frames()


func capture(name: String) -> void:
	if not native_input():
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/outage_" + name + ".png")


func start_outage() -> void:
	expect(game.threats.request_event(&"power_outage", true), "Forced outage starts")
	expect(not game.power.powered and game.threats.active_id == &"power_outage", "Blackout owns the threat slot")


func start_encounter(player_point: Vector3 = Vector3(4.1, 0, -2.0)) -> void:
	await walk_to(player_point)
	var entity: CorridorEntity = game.outage.entity
	expect(entity.in_corridor(), "Player stands inside the corridor zone")
	entity.repeat_left = 0.0
	game.threats.advance(0.05)
	expect(entity.phase == CorridorEntity.Phase.WARNING and entity.visual.visible, "Encounter warns from a preset corridor route")
	var distance: float = Vector2(entity._from.x - player_point.x, entity._from.z - player_point.z).length()
	expect(distance >= entity.settings.min_spawn_distance and distance <= entity.settings.max_spawn_distance, "Spawn keeps its distance from the player")
	expect(entity.warning_audio.playing and not entity.footsteps_audio.playing, "Only the warning plays at first")


func danger_window(settings: CorridorEntityConfig) -> void:
	var entity: CorridorEntity = game.outage.entity
	game.threats.advance(entity.warning_duration + 0.02)
	expect(entity.phase == CorridorEntity.Phase.ACTIVE, "Warning turns into the danger window")
	expect(entity.duration >= settings.min_encounter_seconds and entity.duration <= settings.max_encounter_seconds, "Danger lasts a random 3-5 seconds")
	expect(entity.footsteps_audio.playing and not entity.warning_audio.playing, "Footsteps replace the warning")


func _run() -> void:
	TranslationServer.set_locale("ru")
	await setup()
	var manager: ThreatManager = game.threats
	var outage: PowerOutage = game.outage
	var entity: CorridorEntity = outage.entity
	var settings: CorridorEntityConfig = outage.settings
	expect(is_instance_valid(entity) and entity.get_parent() == outage, "Production outage adapter carries its entity")
	expect(game.get_node("Apartment/CorridorEncounters/Routes").get_child_count() >= 3, "Preset corridor routes exist")
	var entity_scene_check: Node3D = entity.visual.get_node("Body")
	expect(entity_scene_check != null and entity_scene_check is MeshInstance3D, "Entity keeps its placeholder body")
	# The scheduled path needs the desktop; the forced path does not.
	expect(not outage.can_schedule(), "Random outage cannot start while walking")
	expect(not manager.request_event(&"power_outage"), "Random request outside the PC is rejected")
	await walk_to(Vector3(0, 0, 1.0))
	expect(not entity.in_corridor(), "Room is outside the corridor zone")
	start_outage()
	expect(game.power.flashlight.visible and game.power.flashlight_on, "Blackout enables the emergency flashlight")
	expect(not manager.request_event(&"psych_neighbor", true) and not manager.request_event(&"power_outage", true), "No stacked threats during the slot")
	game.enter_computer()
	expect(game.mode == game.Mode.WALKING, "Dead PC rejects entry")
	game.threats.advance(5.0)
	expect(entity.phase == CorridorEntity.Phase.WAITING and not entity.visual.visible, "Entity stays patient while the player is away")
	await capture("blackout")
	# First encounter: warning, then a quiet freeze survives.
	await start_encounter()
	danger_window(settings)
	game.dev_menu.set_debug_hud_enabled(true)
	game.dev_menu._process(0.0)
	var debug_text: String = game.dev_menu._debug_hud_label.text
	expect(debug_text.contains("ACTIVE") and debug_text.contains(tr("DEBUG_HUD_DANGER")) and debug_text.contains("0.00"), "Debug HUD marks the entity's active danger window and error budget")
	game.dev_menu.set_debug_hud_enabled(false)
	await capture("entity")
	game.power.set_flashlight_enabled(false)
	while entity.phase == CorridorEntity.Phase.ACTIVE:
		game.threats.advance(0.2)
	game.threats.advance(settings.retreat_seconds)
	expect(entity.phase == CorridorEntity.Phase.WAITING and not game.run_ended, "Freezing without the beam survives the window")
	expect(entity.repeat_left >= settings.min_repeat_seconds and entity.repeat_left <= settings.max_repeat_seconds, "The next encounter waits 15-25 seconds")
	expect(not entity.footsteps_audio.playing and entity.departure_audio.playing and not entity.visual.visible, "Departure plays and cleans the figure")
	await capture("passed")
	# A repeat needs the corridor again; the room stays calm.
	await walk_to(Vector3(0, 0, 1.0))
	entity.repeat_left = 0.2
	game.threats.advance(0.5)
	expect(entity.phase == CorridorEntity.Phase.WAITING, "Room time cannot trigger an encounter")
	game.threats.advance(settings.max_repeat_seconds + 1.0)
	expect(entity.phase == CorridorEntity.Phase.WAITING, "Corridor absence also blocks repeats")
	await start_encounter()
	entity.repeat_left = 0.0
	game.threats.advance(settings.warning_seconds + 1.0)
	expect(entity.phase == CorridorEntity.Phase.WARNING or entity.phase == CorridorEntity.Phase.ACTIVE, "Corridor time resumes after the quiet pause")
	game.disable_threats()
	await setup()
	start_outage()
	await start_encounter()
	danger_window(settings)
	var active: CorridorEntity = game.outage.entity
	var spawn: Vector3 = active.global_position
	game.power.set_flashlight_enabled(false)
	game.player.global_position = Vector3(spawn.x, 0.03, spawn.z - 1.5)
	active._last_player_position = game.player.global_position
	game.player.global_position = Vector3(spawn.x, 0.03, spawn.z - 0.9)
	game.threats.advance(0.1)
	expect(not game.run_ended and active.error_seconds > 0.0 and active.error_seconds < settings.error_budget_seconds, "Partial movement exposure is survivable")
	active._from = active.global_position
	active._to = active.global_position
	game.power.set_flashlight_enabled(true)
	aim_at_entity(active)
	expect(active.beam_hits(), "Flashlight cone reaches the figure after partial movement exposure")
	var remaining_budget := settings.error_budget_seconds - active.error_seconds + 0.01
	for sample: int in ceili(remaining_budget / 0.1):
		game.threats.advance(0.1)
	expect(active.is_chasing and not game.run_ended and active.error_seconds >= settings.error_budget_seconds, "Movement and flashlight exposure together provoke a chase without instant death")
	game.dev_menu.set_debug_hud_enabled(true)
	game.dev_menu._process(0.0)
	expect(game.dev_menu._debug_hud_label.text.contains(tr("DEBUG_HUD_CHASING")), "Debug HUD reports when the creature is pursuing")
	game.dev_menu.set_debug_hud_enabled(false)
	var distance_before_chase := Vector2(game.player.global_position.x - active.global_position.x, game.player.global_position.z - active.global_position.z).length()
	await frames(2)
	var distance_during_chase := Vector2(game.player.global_position.x - active.global_position.x, game.player.global_position.z - active.global_position.z).length()
	expect(distance_during_chase < distance_before_chase and not game.run_ended, "Pursuing entity closes distance before contact")
	for index: int in 120:
		if not game.capture_reason.is_empty():
			break
		await get_tree().physics_frame
	expect(game.capture_reason == "ENTITY_DEATH" and not game.run_ended, "Contact starts a long monster defeat scene before result")
	if is_instance_valid(game.capture_cutscene):
		game._process(game.capture_cutscene.duration_seconds + 0.1)
	expect(game.run_ended and game.failure_reason == "ENTITY_DEATH" and game.process_mode == Node.PROCESS_MODE_DISABLED, "Contact during pursuit causes entity death")
	expect(not active.visual.visible and not active.footsteps_audio.playing, "Death cleans the encounter")
	var death_text := ""
	for label: Label in game.find_children("*", "Label", true, false):
		death_text += label.text
	expect(death_text.contains(tr("ENTITY_DEATH")), "Result screen shows the entity reason")
	await capture("death")
	var restart: Button = get_viewport().gui_get_focus_owner()
	expect(restart != null and restart.text == tr("CHAT_RESTART"), "Death focuses the restart button")
	restart.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	game = get_tree().current_scene
	game.threats.set_process(false)
	game.threats.set_event_enabled(&"police_raid", false)
	game.threats.set_event_enabled(&"psych_neighbor", false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	expect(game.power.powered and not game.run_ended and not game.room_door.is_open and game.outage.entity.phase == CorridorEntity.Phase.DORMANT, "Real restart resets power, entity and door")
	# A flashlight alone can provoke the chase, but does not kill at a distance.
	await setup()
	start_outage()
	await start_encounter()
	danger_window(settings)
	game.power.set_flashlight_enabled(true)
	aim_at_entity(game.outage.entity)
	expect(game.outage.entity.beam_hits(), "Flashlight cone reaches the figure")
	game.outage.entity.error_seconds = settings.error_budget_seconds - 0.01
	game.threats.advance(0.05)
	expect(game.outage.entity.is_chasing and not game.run_ended, "Holding the beam provokes pursuit without causing a ranged death")
	# A disabled flashlight cannot satisfy the beam part of exposure.
	await setup()
	start_outage()
	await start_encounter()
	danger_window(settings)
	game.power.set_flashlight_enabled(false)
	expect(not game.outage.entity.beam_hits(), "Flashlight off never satisfies the beam check")
	game.disable_threats()
	# Repair mid-window saves instantly and clears the slot.
	await setup()
	game.enter_computer()
	await wait_mode(game.Mode.COMPUTER)
	start_outage()
	await wait_mode(game.Mode.WALKING)
	await start_encounter(Vector3(4.3, 0, -4.6))
	danger_window(settings)
	var board: ApartmentFusebox = game.power.board
	board.set_active(true, game.transition_camera)
	for index: int in 4:
		board.begin_hold(index)
		board.advance(3.5)
	expect(game.power.powered and not game.power.flashlight.visible, "Four latched levers restore light")
	expect(not game.threats.is_busy() and game.threats.state == ThreatManager.State.IDLE, "Repair releases the outage slot at once")
	expect(game.outage.entity.phase == CorridorEntity.Phase.DORMANT and not game.outage.entity.visual.visible and not game.outage.entity.footsteps_audio.playing, "Light instantly removes the creature")
	# F paths: powered apartments ignore the flashlight key; PC typing is safe.
	await setup()
	direct_key(KEY_F)
	expect(not game.power.flashlight.visible and not game.power.flashlight_on, "F cannot light a powered apartment")
	game.enter_computer()
	await wait_mode(game.Mode.COMPUTER)
	direct_key(KEY_F)
	expect(game.mode == game.Mode.COMPUTER and not game.power.flashlight_on, "Typing F in the PC never toggles the flashlight")
	game.leave_computer(false)
	await wait_mode(game.Mode.WALKING)
	start_outage()
	if native_input():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await frames()
		await key_press(KEY_F)
		expect(not game.power.flashlight_on, "Real F turns the light off while walking")
		await key_press(KEY_F)
		expect(game.power.flashlight_on, "Real F turns it back on")
	else:
		game.power.toggle_flashlight()
		game.power.toggle_flashlight()
		expect(game.power.flashlight_on, "Toggle pairs stay neutral headless")
	await start_encounter(Vector3(4.2, 0, -5.0))
	game.threats.advance(0.02)
	expect(game.mode == game.Mode.WALKING, "Walking keeps moving keys ready")
	game.enter_fusebox()
	await wait_mode(game.Mode.FUSEBOX)
	var fusebox_light: bool = game.power.flashlight_on
	direct_key(KEY_F)
	expect(game.power.flashlight_on != fusebox_light and game.mode == game.Mode.FUSEBOX, "F works from the fusebox without leaving")
	if OS.has_feature("web"):
		# Synthetic WASD has no browser gesture behind the pointer re-capture.
		game.leave_fusebox(false)
	else:
		direct_key(KEY_W)
	await wait_mode(game.Mode.WALKING)
	game.disable_threats()
	game.queue_free()
	await get_tree().process_frame
	print("OUTAGE SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)


func start_outage_and_encounter(settings: CorridorEntityConfig) -> void:
	start_outage()
	await start_encounter()
	danger_window(settings)


func aim_at_entity(entity: CorridorEntity) -> void:
	# Camera motion smoothing could lag behind rotations: snap the real camera ray.
	game.player.camera_motion.set_process(false)
	var eye: Vector3 = game.player.global_position + Vector3(0, 1.6, 0)
	var target: Vector3 = entity.visual.global_position + Vector3(0, 1.2, 0)
	game.player.camera.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	game.player.stop_motion(true)
	game.power.update_flashlight()
