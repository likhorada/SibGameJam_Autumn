extends Node
var failures: int = 0
var game: Node3D
var director: AtmosphereDirector
var residents: AtmosphereResidents


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("RESIDENTS: " + message)


func frames(count: int = 3) -> void:
	for i: int in count:
		await get_tree().process_frame


func physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func make_game() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.02
	game.shift.set_process(false)
	game.threats.set_process(false)
	director = game.atmosphere
	director.set_process(false)
	residents = director.residents


func sit() -> void:
	game.enter_computer()
	await get_tree().create_timer(0.2).timeout
	expect(game.mode == game.Mode.COMPUTER, "Seat transition completes")
	game.terminal_ui.launch_app(&"notepad")
	await frames()


func mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_tree().root.push_input(event)


func motion(at: Vector2, relative: Vector2 = Vector2.ZERO, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_tree().root.push_input(event)


func close_question() -> void:
	await frames(2)
	var at := residents.question.close_button.get_global_rect().get_center()
	motion(at)
	mouse(at, true)
	mouse(at, false)
	await frames()


func aim(origin: Vector3, target: Vector3, yaw: float = 0.0) -> void:
	game.mode = game.Mode.WALKING
	game.player.set_process(false)
	game.player.set_physics_process(false)
	var camera: Camera3D = game.player.camera
	camera.make_current()
	camera.global_position = origin
	camera.look_at(target)
	camera.global_basis = Basis(Vector3.UP, yaw) * camera.global_basis
	game.visual_effects._process(0)


func capture(name: String) -> Image:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return null
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/residents_" + name + ".png")
	return image


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	make_game()
	expect(director.event_ids().size() == 4 and residents.remaining_questions.size() == 12, "Production registers four events and twelve questions")
	expect(not director.request_event(&"question_popup", true), "Question cannot start while walking")
	await sit()
	game.terminal_ui.notepad.editor.text = "evidence is preserved"
	var seen: Array[StringName] = []
	for index: int in 12:
		TranslationServer.set_locale("ru" if index % 2 == 0 else "en")
		expect(director.request_event(&"question_popup", true), "Question starts from remaining deck")
		await frames(2)
		var popup := residents.question
		expect(is_instance_valid(popup) and not director.is_busy() and game.threats.can_start_external_event(), "Popup outlives spawn event without holding threat slot")
		expect(popup.question_key not in seen and popup.body.text == tr(popup.question_key) and popup.body.text != String(popup.question_key), "Unique translated question")
		seen.append(popup.question_key)
		expect(not director.request_event(&"question_popup", true), "No second concurrent question, even forced")
		expect(&"question_popup" not in director._candidates(false, true, false), "Open popup is excluded from random selection")
		if index == 0:
			var old := popup.position
			var header := popup.global_position + Vector2(100, 20)
			motion(header)
			mouse(header, true)
			motion(header + Vector2(55, 25), Vector2(55, 25), true)
			mouse(header + Vector2(55, 25), false)
			await frames()
			expect(popup.position.distance_to(old) > 20, "Question title really drags")
			expect(game.terminal_ui.active_app == &"notepad", "Popup does not activate app below")
			director.advance(300)
			expect(residents.question == popup, "No auto-dismiss timeout")
			await capture("question")
		await close_question()
		expect(not is_instance_valid(residents.question), "Cross removes question")
		if index < 11:
			expect(&"question_popup" in director._candidates(false, true, false), "Repeatable profile remains eligible after close")
	expect(seen.size() == 12 and not director.request_event(&"question_popup", true), "Exhausted deck never repeats a text")
	expect(game.terminal_ui.notepad.editor.text == "evidence is preserved", "Questions do not touch notes")
	game.queue_free()
	await frames()

	make_game()
	await sit()
	expect(residents.remaining_questions.size() == 12 and director.used.is_empty(), "Restart creates fresh deck/state")
	director.request_event(&"question_popup", true)
	expect(director.request_event(&"firewall_breach", true), "Other event can start over persistent question")
	expect(not is_instance_valid(residents.question), "Firewall start removes question")
	director.cancel()
	expect(residents.remaining_questions.size() == 11, "Removal does not recycle consumed question")
	await frames()
	director.start_run()
	director.clear_cooldown()
	director.random_limit = 2
	game.shift.state = ShiftDirector.State.ROUTE
	# Keep this test's random selection focused on the repeatable question profile.
	for profile: AtmosphereProfile in game.atmosphere_config.events:
		if profile.id != &"question_popup":
			director.set_event_condition(profile.id, func() -> bool: return false)
	director.advance(1)
	expect(is_instance_valid(residents.question) and director.random_count == 1, "Instant random event counts exactly once")
	await close_question()
	director.clear_cooldown()
	director.advance(1)
	expect(is_instance_valid(residents.question) and director.random_count == 2, "Repeat uses normal random budget")
	director.clear_cooldown()
	await close_question()
	director.advance(100)
	expect(not is_instance_valid(residents.question) and director.random_count == 2, "No quota bypass")
	# Restore the world event's real availability check.
	director.set_event_condition(&"bathroom_apparition", residents.can_place_figure)

	expect(director.request_event(&"bathroom_apparition", true), "Figure can spawn while at PC")
	var figure := residents.figure
	expect(not director.is_busy() and not is_instance_valid(figure.audio), "Figure releases slot and has no synthetic/missing audio")
	expect(figure.visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "Visual has no collision")
	await physics()
	figure._on_frame_post_draw()
	expect(residents.figure == figure, "PC view does not count as seeing apartment")
	expect(not director.request_event(&"bathroom_apparition", true), "No duplicate figure")
	game.leave_computer(false)
	await get_tree().create_timer(0.2).timeout
	var point: Vector3 = game.get_node("Apartment/BathroomApparitionPoint").global_position
	aim(Vector3(0, 1.6, 2.8), point + Vector3.UP * 1.3)
	await physics()
	figure._on_frame_post_draw()
	expect(residents.figure == figure and not figure.visible_in_physics, "Looking through bathroom wall never dismisses figure")
	aim(Vector3(0, 1.6, 0), Vector3(0, 1.6, -10))
	await physics()
	figure._on_frame_post_draw()
	expect(residents.figure == figure, "Off-screen figure remains")
	# Freeze sensing only for a deterministic native before/after pixel capture.
	figure.set_physics_process(false)
	figure.visible_in_physics = false
	aim(Vector3(0, 1.6, 0), point + Vector3.UP * 1.3, deg_to_rad(50))
	await frames()
	var screen_point: Vector2 = game.player.camera.unproject_position(point + Vector3.UP * 1.3)
	expect(screen_point.x < 200 or screen_point.x > 1080, "Figure is genuinely peripheral, not centered")
	await capture("peripheral_figure")
	figure.set_physics_process(true)
	await physics()
	# Dummy renderer has no post-draw; explicitly exercise the same confirmation there.
	if DisplayServer.get_name() == "headless":
		aim(Vector3(0, 1.6, 0), Vector3(0, 1.6, -10))
		figure._on_frame_post_draw()
		expect(residents.figure == figure, "A camera turn after physics cannot confirm an off-screen render")
		aim(Vector3(0, 1.6, 0), point + Vector3.UP * 1.3, deg_to_rad(50))
		figure._on_frame_post_draw()
	await frames()
	expect(not is_instance_valid(residents.figure), "First rendered peripheral glimpse removes figure")
	await capture("peripheral_empty")

	aim(Vector3(0, 1.6, 0), point + Vector3.UP * 1.3)
	await physics()
	expect(not director.request_event(&"bathroom_apparition", true), "Even dev cannot materialize figure in visible spawn")
	aim(Vector3(0, 1.6, 0), Vector3(0, 1.6, -10))
	await physics()
	expect(director.request_event(&"bathroom_apparition", true), "Hidden spawn is available again to dev")
	expect(game.trigger_neighbor(), "Unseen resident never blocks a real threat")
	expect(not is_instance_valid(residents.figure), "Threat warning removes decorative figure synchronously")
	game.disable_threats()
	game.queue_free()
	await frames()

	make_game()
	await sit()
	director.request_event(&"question_popup", true)
	director.request_event(&"bathroom_apparition", true)
	game.shift.state = ShiftDirector.State.REPORT
	game.shift._process(0)
	expect(game.terminal_ui.chat.session.quiz_started and not is_instance_valid(residents.question) and not is_instance_valid(residents.figure), "Report cleans both residents")
	game.queue_free()
	await frames()
	make_game()
	await sit()
	director.request_event(&"question_popup", true)
	director.request_event(&"bathroom_apparition", true)
	var question_ref: WeakRef = weakref(residents.question)
	var figure_ref: WeakRef = weakref(residents.figure)
	director.enabled = false
	expect(not is_instance_valid(residents.question) and not is_instance_valid(residents.figure), "Disable clears residents without active spawn event")
	game.queue_free()
	await frames()
	expect(question_ref.get_ref() == null and figure_ref.get_ref() == null, "No leaked resident objects")
	make_game()
	await sit()
	# Exercise the future supplied-sound path with an existing test-only click asset.
	residents.bathroom_settings = residents.bathroom_settings.duplicate()
	residents.bathroom_settings.loop_sound = load("res://assets/audio/mouse_click1.wav")
	director.request_event(&"question_popup", true)
	director.request_event(&"bathroom_apparition", true)
	figure = residents.figure
	expect(is_instance_valid(figure.audio) and figure.audio.playing, "Assigned audio is spatial and starts")
	figure.audio.stop()
	figure.audio.finished.emit()
	expect(figure.audio.playing, "Assigned sound repeats on one source")
	var audio_ref: WeakRef = weakref(figure.audio)
	question_ref = weakref(residents.question)
	figure_ref = weakref(figure)
	game.queue_free()
	await frames()
	expect(audio_ref.get_ref() == null and question_ref.get_ref() == null and figure_ref.get_ref() == null, "Live teardown cleans question, figure and optional sound")
	print("RESIDENTS SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(0 if failures == 0 else 1)
