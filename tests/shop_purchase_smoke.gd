extends SceneTree
## Deterministic end-to-end checks for all three actual purchases and quiz answers.

var failures := 0
const DATA := preload("res://data/observation/shift.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for choice: int in DATA.DRINKS.size():
		var game: Node3D = load("res://scenes/main.tscn").instantiate()
		game.atmosphere_config = AtmosphereConfig.new()
		root.add_child(game)
		current_scene = game
		game.threats.set_process(false)
		game.power.set_process(false)
		var shift: ShiftDirector = game.shift
		shift.set_process(false)
		shift.drink = choice
		shift.stage = 1
		shift._load_stage()
		var shop: ObservationLocation = shift.location
		var actor: Node3D = shop.get_node("Target/Guy")
		actor.set_process(false)
		actor.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_expect(shop.scene_file_path == "res://scenes/cctv/locations/shop.tscn", "One authored shop is used by the shift")
		var item: Node3D = shop.get_node(shop.drink_paths[choice])
		var model: Node3D = item.get_node("Model")
		var model_scale := model.scale
		var original_position := item.global_position
		shift._begin_route(shop.route())
		if DisplayServer.get_name() != "headless":
			game.transition_seconds = 0.02
			game.enter_computer()
			await create_timer(0.2).timeout
			game.terminal_ui.launch_app(&"cctv")
		var saw_pickup := false
		var saw_carry := false
		var saw_checkout := false
		var wrist_error := INF
		for frame: int in 1860:
			var before := actor.global_position
			shift.advance(1.0 / 30.0)
			if shift.stage != 1:
				break
			actor.advance_motion(1.0 / 30.0, actor.global_position - before)
			actor.player.advance(1.0 / 30.0)
			if frame == 898:
				await _capture(game, choice, "shelf", 1)
			elif frame == 932:
				await _capture(game, choice, "held", 1)
			elif frame == 1180:
				await _capture(game, choice, "carry", 2)
			if is_instance_valid(actor.carrying):
				saw_pickup = true
				_expect(actor.carrying == item, "Actor holds the selected real bottle")
				_expect(item.global_basis.y.dot(Vector3.UP) > 0.99, "Bottle stays upright after animation updates")
				if actor.activity == "carry_walk":
					saw_carry = true
			if frame in range(908, 916):
				var wrist: Vector3 = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("DEF-hand.R")).origin
				wrist_error = minf(wrist_error, wrist.distance_to(original_position + Vector3(0, 0.24, 0)))
			if saw_pickup and actor.carrying == null and item.get_parent() == shop:
				saw_checkout = true
				await _capture(game, choice, "checkout", 2)
				break
		_expect(saw_pickup and saw_carry and saw_checkout, "Shelf → hand → carry → checkout completed")
		_expect(wrist_error < 0.18, "Wrist reaches actual shelf bottle, not old placeholder coordinates")
		_expect(model.scale.is_equal_approx(model_scale), "Reparenting preserves real bottle scale")
		_expect(item.position.is_equal_approx(shop.get_node("CheckoutItem").position), "Bottle rests at the authored checkout marker")
		_expect(item.get_meta(&"evidence_id") == DATA.DRINKS[choice], "Visible item and evidence ID agree")
		var question: Dictionary = shift.report_questions()[1]
		_expect(question.correct == item.get_meta(&"evidence_id") and question.answers == DATA.DRINKS, "Final quiz derives the answer from the same run's purchase")
		for response: String in DATA.DRINKS:
			var report := ChatSession.new()
			report.questions = [question]
			report.live_report = true
			report.start_quiz()
			while not report.pending.is_empty():
				report.deliver_next()
			report.select_reply(response)
			for letter: int in tr(response).length():
				report.type_character(tr(response).length())
			_expect(report.submit(tr(response).length()), "Quiz accepts localized alcohol reply")
			_expect(report.score == (1 if response == DATA.DRINKS[choice] else 0), "Only the purchased alcohol scores a point")
		for language: String in ["ru", "en"]:
			TranslationServer.set_locale(language)
			for option: String in question.answers:
				_expect(tr(option) != option, "Alcohol answer has a " + language + " translation")
		game.queue_free()
		await process_frame
		await process_frame
	print("SHOP PURCHASE SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("SHOP: " + message)


func _capture(game: Node3D, choice: int, phase: String, camera: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.terminal_ui.cctv.directory.select(camera)
	game.terminal_ui.cctv._select(camera)
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA").path_join("Temp/opencode/shop_%d_%s.png" % [choice, phase]))
