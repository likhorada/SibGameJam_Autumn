extends SceneTree
var failures: int = 0
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("SHIFT: " + message)

func drain(session: ChatSession) -> void:
	while not session.pending.is_empty():
		session.deliver_next()

func answer(session: ChatSession, key: String) -> void:
	drain(session)
	session.select_reply(key)
	for i: int in tr(key).length():
		session.type_character(tr(key).length())
	expect(session.submit(tr(key).length()), "Reply submits")

func capture(name: String, camera_index: int = 0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.terminal_ui.cctv.directory.select(camera_index)
	game.terminal_ui.cctv._select(camera_index)
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/shift_" + name + ".png")

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.atmosphere_config = AtmosphereConfig.new()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.04
	var shift: ShiftDirector = game.shift
	shift.set_process(false)
	expect(shift.location.scene_file_path.ends_with("office.tscn"), "Office is loaded from an editable scene")
	expect(shift.location.route().size() == 3 and game.cctv_system.cameras.size() == 2, "Office scene supplies route and CCTV cameras")
	expect(game.terminal_ui.cctv.directory.item_count == 2, "Scene cameras appear in PC directory")
	expect(not game.threats.random_allowed and not game.threats.is_busy(), "Random threats blocked before alarm")
	expect(shift.code.length() == 4 and shift.branch == -1, "Code generated; street branch not chosen early")
	game.enter_computer()
	await create_timer(0.4).timeout
	game.terminal_ui.launch_app(&"cctv")
	await capture("office")
	var session: ChatSession = game.terminal_ui.chat.session
	answer(session, "CHAT_REPLY_1")
	answer(session, "CHAT_REPLY_3")
	answer(session, "CHAT_REPLY_4")
	expect(shift.state == ShiftDirector.State.DEADLINE, "Last intro answer starts deadline")
	shift.advance(59)
	expect(is_equal_approx(shift.seconds_left, 1), "Deadline advances independently of chat")
	shift.start_alarm()
	await physics_frame
	await physics_frame
	expect(shift.state == ShiftDirector.State.ROUTE and game.threats.random_allowed, "Alarm starts route and enables random threats")
	shift.advance(20)
	expect(shift.state == ShiftDirector.State.ROUTE and game.mode == game.Mode.COMPUTER, "Empty atmosphere pool never ejects player or inserts a pause")
	expect(shift.stage == 1, "Shop starts immediately with no content")
	expect(shift.location.scene_file_path.ends_with("/shop.tscn") and shift.location.route().size() == 8, "Authored shop includes collection before exit")
	expect(game.cctv_system.cameras.size() == 3, "Only new camera set is registered")
	expect(game.terminal_ui.cctv.directory.item_count == 3, "PC directory follows scene replacement")
	game.power.trigger_outage()
	shift.advance(30)
	expect(is_instance_valid(shift.location.bottle), "Timeline and purchase continue during blackout")
	game.power.restore_power()
	game.enter_computer()
	await create_timer(0.3).timeout
	game.terminal_ui.launch_app(&"cctv")
	await capture("shelf", 1)
	shift.advance(14)
	await capture("checkout", 2)
	game.power.trigger_outage()
	game.mode = game.Mode.FUSEBOX
	game.power.board.set_active(true, game.transition_camera)
	game.power.board.latched[0] = true
	game.power.board.begin_hold(1)
	shift.advance(30)
	expect(shift.state == ShiftDirector.State.WAITING_EVENT and game.power.board.held == 1, "Event waits for blackout without interrupting repair")
	expect(game.power.board.latched[0], "Scare preserves latched breakers")
	game.power.restore_power()
	game.power.board.set_active(false)
	game.mode = game.Mode.WALKING
	shift._process(0)
	expect(shift.state == ShiftDirector.State.ROUTE and game.power.board.held == -1, "Empty event is skipped only after repair and stable context")
	expect(shift.stage == 2 and shift.branch == -1, "Street starts before branch selection")
	expect(shift.location.scene_file_path.ends_with("street.tscn") and shift.location.route().size() == 1, "Street scene supplies its route")
	for index: int in game.cctv_system.cameras.size():
		var lens: Camera3D = game.cctv_system.cameras[index].lens
		expect(not lens.is_position_in_frustum(Vector3(0, 1, 0)), "Junction remains outside branch camera")
		expect(lens.is_position_in_frustum(shift.location.exit_point(index) + Vector3(0, 1, 0)), "Branch destination is visible")
	shift.advance(12)
	expect(shift.branch in [0, 1, 2], "Branch chosen at junction")
	game.power.restore_power()
	game.enter_computer()
	await create_timer(0.3).timeout
	game.terminal_ui.launch_app(&"cctv")
	shift.advance(28)
	await capture("street", shift.branch)
	shift.advance(20)
	expect(shift.state == ShiftDirector.State.REPORT, "Street ends in report task")
	game.power.trigger_outage()
	shift._process(0)
	expect(not session.quiz_started, "Report waits for powered PC")
	game.power.restore_power()
	game.enter_computer()
	await create_timer(0.3).timeout
	shift._process(0)
	expect(session.quiz_started and session.questions.size() == 3, "Report opens automatically at powered PC")
	expect(session.questions[1].answers == ["OBS_WINE", "OBS_GIN", "OBS_VODKA"], "Only wine, gin and vodka offered")
	expect(session.history.all(func(item: Dictionary): return item.text != "CHAT_TEST_FACTS"), "Live briefing does not reveal placeholder answers")
	for question: Dictionary in session.questions:
		answer(session, question.correct)
	drain(session)
	expect(session.score == 3 and game.process_mode == Node.PROCESS_MODE_DISABLED, "Real evidence wins at 3/3")
	game.queue_free()
	await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.shift._begin_deadline()
	game.shift.advance(60)
	expect(game.process_mode == Node.PROCESS_MODE_DISABLED, "Missed alarm deadline ends run")
	game.queue_free()
	await create_timer(0.1).timeout
	print("SHIFT SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
