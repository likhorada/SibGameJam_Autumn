extends SceneTree
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("CHAT: " + message)

func drain(session: ChatSession) -> void:
	while not session.pending.is_empty():
		session.deliver_next()

func reply(session: ChatSession, key: String) -> void:
	drain(session)
	session.select_reply(key)
	var length := tr(key).length()
	for index: int in length:
		session.type_character(length)
	expect(session.submit(length), "Complete selected reply submits")

func key(code: Key, unicode: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func _run() -> void:
	TranslationServer.set_locale("ru")
	for perfect: bool in [true, false]:
		var session := ChatSession.new()
		var result: Array = []
		session.finished.connect(func(won: bool, score: int): result.assign([won, score]))
		session.start()
		session.select_reply("CHAT_REPLY_1")
		expect(session.selected.is_empty(), "Cannot answer while handler is typing")
		reply(session, "CHAT_REPLY_1")
		reply(session, "CHAT_REPLY_3")
		reply(session, "CHAT_REPLY_4")
		drain(session)
		expect(session.intro_step == 3 and session.choices.is_empty(), "Tutorial completed")
		session.start_quiz()
		reply(session, "CHAT_A_VIKTOR" if perfect else "CHAT_A_ANTON")
		reply(session, "CHAT_A_COFFEE")
		reply(session, "CHAT_A_ANNA")
		expect(result.is_empty(), "Final message delivered before result")
		drain(session)
		expect(result == [perfect, 3 if perfect else 2], "Exactly three correct answers required")
		expect(session.answers.size() == 3, "Answers recorded by stable question IDs")
		session.start_quiz()
		expect(session.ended and session.question_index == 3, "Ended session cannot retry")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	root.size = Vector2i(1280, 720)
	game.transition_seconds = 0.04
	game.power.random_outages_enabled = false
	game.enter_computer()
	await create_timer(0.2).timeout
	var desktop: TerminalDesktop = game.terminal_ui
	var chat: ChatApp = desktop.chat
	var session := chat.session
	expect(desktop.active_app == &"chat" and session.intro_step == 0, "Chat auto-opens on first PC login")
	drain(session)
	chat.options.get_child(0).pressed.emit()
	await process_frame
	expect(root.gui_get_focus_owner() == chat.composer, "Choosing answer focuses composer")
	key(KEY_ENTER)
	await process_frame
	expect(session.intro_step == 0, "Enter cannot send an incomplete answer")
	var before: int = desktop.input_audio.presses_played
	key(KEY_Z, 122)
	await process_frame
	expect(session.typed == 2 and chat.composer.text.contains(tr(session.selected).left(2)), "Arbitrary key types selected text not literal key")
	expect(desktop.input_audio.presses_played == before + 1, "One keyboard audio trigger per physical press")
	desktop.launch_app(&"notepad")
	key(KEY_Z, 122)
	expect(session.typed == 2, "Inactive chat ignores input")
	desktop.launch_app(&"chat")
	desktop.windows[&"chat"].close_window()
	desktop.launch_app(&"chat")
	expect(session.typed == 2, "Draft survives window close")
	game.power.trigger_outage()
	await process_frame
	expect(session.typed == 2 and not desktop.input_audio.enabled, "Power outage preserves draft and suspends audio")
	before = desktop.input_audio.presses_played
	key(KEY_Z, 122)
	expect(desktop.input_audio.presses_played == before, "No desktop sounds while walking")
	game.power.restore_power()
	game.enter_computer()
	await create_timer(0.2).timeout
	expect(session.intro_step == 0 and session.typed == 2, "Returning to PC does not restart tutorial")
	game.leave_computer(false)
	await create_timer(0.2).timeout
	game.dev_menu.open_menu()
	await process_frame
	expect(not chat.input_enabled and not desktop.input_audio.enabled, "Dev overlay suspends chat and desktop sounds")
	for button: Button in game.dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "DEV_CHAT_REPORT":
			button.pressed.emit()
	await create_timer(0.2).timeout
	expect(session.quiz_started and desktop.active_app == &"chat" and not game.dev_menu.is_open and game.mode == game.Mode.COMPUTER, "Dev command seats walking player and opens report")
	drain(session)
	if DisplayServer.get_name() != "headless":
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/chat_native.png")
	reply(session, "CHAT_A_VIKTOR")
	reply(session, "CHAT_A_COFFEE")
	reply(session, "CHAT_A_ANNA")
	drain(session)
	expect(game.process_mode == Node.PROCESS_MODE_DISABLED, "Result freezes entire run")
	expect(not desktop.input_audio.enabled, "Result stops desktop sound")
	var restart: Button = root.gui_get_focus_owner()
	expect(restart != null and restart.text == tr("CHAT_RESTART"), "Result focuses new run button")
	restart.pressed.emit()
	await process_frame
	await process_frame
	var fresh := current_scene
	expect(fresh != game and not fresh.terminal_ui.chat.session.quiz_started, "New run loads fresh scene and session")
	fresh.power.random_outages_enabled = false
	fresh.transition_seconds = 0.04
	fresh.enter_computer()
	await create_timer(0.2).timeout
	expect(fresh.terminal_ui.chat.session.intro_step == 0, "New run starts tutorial again")
	fresh._finish_report(false, 0)
	for button: Button in fresh.find_children("*", "Button", true, false):
		if button.text == tr("CHAT_MENU"):
			button.pressed.emit()
			break
	await process_frame
	await process_frame
	expect(current_scene.scene_file_path == "res://scenes/menu/menu.tscn", "Result can return to main menu")
	current_scene.queue_free()
	await process_frame
	print("CHAT SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
