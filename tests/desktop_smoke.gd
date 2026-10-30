extends SceneTree
## godot --headless --path . --script res://tests/desktop_smoke.gd
## Omit --headless and add -- --capture-dir=<existing folder> for screenshots.

var failures: int = 0
var desktop: TerminalDesktop
var _mouse_position := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_calculator()
	root.size = Vector2i(1280, 720)
	desktop = load("res://scenes/ui/terminal_ui.tscn").instantiate()
	root.add_child(desktop)
	await _frames(4)
	_expect(desktop.windows.size() == 5, "Five applications including RELAY and ALARM.sh")
	_expect(desktop.active_app.is_empty(), "No app starts open")
	_expect(desktop.clock.text == "09:00", "Clock starts at fictional 09:00")
	var note: DesktopAppWindow = desktop.windows[&"notepad"]
	var calc: DesktopAppWindow = desktop.windows[&"calculator"]
	_click(Vector2(70, 70))
	await _frames(2)
	_expect(not note.opened, "Single click only selects an icon")
	_click(Vector2(70, 70), true)
	await _frames(3)
	_expect(note.opened and note.visible and desktop.active_app == &"notepad", "Double click opens Notepad")
	_expect(root.gui_get_focus_owner() == desktop.notepad.editor, "Notepad receives keyboard focus")
	_text("Test 123")
	await _frames(2)
	_expect(desktop.notepad.editor.text == "Test 123", "Text input reaches Notepad")
	_key(KEY_A, 0, true)
	_key(KEY_X, 0, true)
	await _frames(2)
	_expect(desktop.notepad.editor.text.is_empty(), "Ctrl+A / Ctrl+X")
	_key(KEY_Z, 0, true)
	await _frames(2)
	_expect(desktop.notepad.editor.text == "Test 123", "Undo restores text")
	if DisplayServer.get_name() != "headless":
		_key(KEY_A, 0, true)
		_key(KEY_C, 0, true)
		await create_timer(0.15).timeout
		_key(KEY_END)
		_key(KEY_V, 0, true)
		await _frames(2)
		_expect(desktop.notepad.editor.text == "Test 123Test 123", "Native Ctrl+C / Ctrl+V")
		_key(KEY_Z, 0, true)
		await _frames(2)
	var original_note := note
	desktop.launch_app(&"notepad")
	_expect(desktop.windows[&"notepad"] == original_note, "Relaunch reuses one instance")
	note.close_window()
	_expect(not desktop.task_buttons[&"notepad"].visible, "Closing removes task button")
	desktop.launch_app(&"notepad")
	_expect(desktop.notepad.editor.text == "Test 123", "Closing preserves the note")
	desktop.launch_app(&"calculator")
	await _frames(3)
	_expect(desktop.active_app == &"calculator", "Calculator activates")
	_expect(root.gui_get_focus_owner() != desktop.notepad.editor, "Calculator releases Notepad focus")
	_key(KEY_2, 50)
	_key(KEY_PLUS, 43)
	_key(KEY_3, 51)
	_key(KEY_ENTER)
	await _frames(2)
	_expect(desktop.calculator.model.entry == "5", "Keyboard arithmetic in active calculator")
	_expect(desktop.notepad.editor.text == "Test 123", "Calculator input does not change notes")
	# A click in the exposed editor raises the back window and routes input to it.
	_click(note.global_position + Vector2(40, 90))
	await _frames(3)
	_expect(desktop.active_app == &"notepad", "Click raises inactive window")
	_expect(note.get_index() > calc.get_index(), "Active window is visually on top")
	_key(KEY_9, 57)
	await _frames(2)
	_expect(desktop.calculator.model.entry == "5", "Inactive calculator ignores keys")
	# Header dragging goes through real GUI events, not just direct setters.
	var before_drag := note.position
	var title_point := note.global_position + Vector2(50, 18)
	_move_mouse(title_point)
	_mouse_button(true)
	_move_mouse(title_point + Vector2(100, 65), true)
	_mouse_button(false)
	await _frames(2)
	_expect(note.position.distance_to(before_drag + Vector2(100, 65)) < 1.0, "Title bar dragging")
	# Border resize; minimum size and bounds are enforced.
	var before_size := note.size
	_move_mouse(note.global_position + note.size - Vector2(2, 2))
	_mouse_button(true)
	_move_mouse(_mouse_position + Vector2(60, 30), true)
	_mouse_button(false)
	await _frames(2)
	_expect(note.size.x > before_size.x + 50, "Resize grip works")
	note._begin_gesture(false, Vector2i(-1, -1))
	note.move_gesture(Vector2(10000, 10000))
	note.cancel_gesture()
	_expect(note.size.x >= note.minimum_window_size.x and note.size.y >= note.minimum_window_size.y, "Resize respects minimum")
	note._begin_gesture(true, Vector2i.ZERO)
	note.move_gesture(Vector2(-10000, -10000))
	note.cancel_gesture()
	_expect(note.position == Vector2.ZERO, "Dragging cannot lose the title off-screen")
	var restored := Rect2(note.position, note.size)
	note.toggle_maximized()
	_expect(note.position == Vector2.ZERO and note.size.is_equal_approx(note.work_size), "Maximize fills work area, not taskbar")
	note.toggle_maximized()
	_expect(Rect2(note.position, note.size).is_equal_approx(restored), "Restore returns previous geometry")
	_click(desktop.task_buttons[&"notepad"].get_global_rect().get_center())
	await _frames(2)
	_expect(note.minimized and not note.visible, "Taskbar minimizes active window")
	_click(desktop.task_buttons[&"notepad"].get_global_rect().get_center())
	await _frames(2)
	_expect(not note.minimized and note.visible and desktop.active_app == &"notepad", "Taskbar restores window")
	_click(desktop.start_button.get_global_rect().get_center())
	await _frames(2)
	_expect(desktop.start_menu.visible, "Start menu opens")
	_click(desktop.start_button.get_global_rect().get_center())
	await _frames(2)
	_expect(not desktop.start_menu.visible and root.gui_get_focus_owner() == desktop.notepad.editor, "Toggling Start restores editor focus")
	_click(desktop.start_button.get_global_rect().get_center())
	_click(Vector2(1100, 40))
	await _frames(2)
	_expect(not desktop.start_menu.visible, "Outside click dismisses Start")
	# Shrinking the workspace keeps windows recoverable; then restore normal size.
	desktop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	desktop.size = Vector2(640, 360)
	await _frames(3)
	for window: DesktopAppWindow in desktop.windows.values():
		_expect(Rect2(Vector2.ZERO, Vector2(640, 316)).encloses(Rect2(window.position, window.size)), "Window stays inside smaller desktop")
	desktop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(3)
	# Hiding/re-entering the desktop preserves state but cancels drags and focus.
	var text_before := desktop.notepad.editor.text
	note._begin_gesture(true, Vector2i.ZERO)
	desktop.suspend_desktop()
	desktop.hide()
	await _frames(2)
	_expect(not note._dragging, "Leaving cancels an unfinished drag")
	_expect(root.gui_get_focus_owner() != desktop.notepad.editor, "Leaving releases editor focus")
	desktop.show()
	desktop.resume_desktop()
	await _frames(2)
	_expect(desktop.notepad.editor.text == text_before, "Returning preserves notes")
	# Make a representative desktop for optional visual inspection.
	note.position = Vector2(160, 90)
	note.size = Vector2(560, 400)
	desktop.launch_app(&"notepad")
	desktop.notepad.editor.text = ""
	desktop.notepad.focus_editor()
	_text("Наблюдение\n\n09:10 — проверить коридор.\n\nЭто только локальные заметки.")
	_expect(desktop.notepad.editor.text.begins_with("Наблюдение\n"), "Cyrillic and multiline input")
	calc.position = Vector2(760, 170)
	calc.size = Vector2(330, 420)
	desktop.launch_app(&"calculator")
	await _frames(4)
	await _capture()
	desktop.queue_free()
	await process_frame
	await _test_game_integration()
	print("DESKTOP SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_game_integration() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.transition_seconds = 0.02
	game.enter_computer()
	await create_timer(0.12).timeout
	# Initial audio/font loading can consume the timer's first frame before the tween advances.
	for frame: int in 20:
		if game.mode == game.Mode.COMPUTER:
			break
		await _frames(1)
	var ui: TerminalDesktop = game.terminal_ui
	ui.launch_app(&"notepad")
	_text("Keep")
	_key(KEY_W, 119)
	_key(KEY_E, 101)
	await _frames(3)
	_expect(ui.notepad.editor.text == "Keepwe", "W/E type in Notepad instead of moving or interacting: " + ui.notepad.editor.text)
	_expect(game.mode == game.Mode.COMPUTER and game.player.velocity == Vector3.ZERO, "Typing leaves player disabled")
	_click(ui.start_button.get_global_rect().get_center())
	_expect(ui.start_menu.visible, "Start opened while using PC")
	_key(KEY_ESCAPE)
	_expect(game.mode == game.Mode.LEAVING, "Esc exits immediately even with Start open")
	await create_timer(0.12).timeout
	var saved := ui.notepad.editor.text
	_key(KEY_9, 57)
	_expect(ui.notepad.editor.text == saved, "Hidden desktop ignores keyboard")
	ui._boot_msec -= 61000
	await _frames(2)
	_expect(ui.clock.text == "09:01", "Fictional clock continues outside PC")
	game.enter_computer()
	await create_timer(0.12).timeout
	_expect(ui.notepad.editor.text == saved and ui.windows[&"notepad"].opened, "Re-entering preserves app and note")
	ui.notepad.focus_editor()
	_key(KEY_ESCAPE)
	_expect(game.mode == game.Mode.LEAVING, "Esc exits while editing text")
	await create_timer(0.12).timeout
	game.enter_computer()
	await create_timer(0.12).timeout
	var popup_escape := InputEventKey.new()
	popup_escape.keycode = KEY_ESCAPE
	popup_escape.physical_keycode = KEY_ESCAPE
	popup_escape.pressed = true
	ui.notepad.editor.get_menu().window_input.emit(popup_escape)
	_expect(game.mode == game.Mode.LEAVING, "Text context-menu Esc routes back to game")
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame


func _test_calculator() -> void:
	_calculation(["2", "+", "3", "="], "5")
	_calculation(["2", "+", "3", "=", "="], "8")
	_calculation(["2", "+", "3", "*", "4", "="], "20")
	_calculation(["2", "+", "*", "3", "="], "6")
	_calculation(["0", ".", "1", "+", "0", ",", "2", "="], "0.3")
	_calculation(["5", "+", "3", "3", "CE", "2", "="], "7")
	_calculation(["1", "2", "BACK"], "1")
	_calculation(["9", "SIGN", "/", "3", "="], "-3")
	_calculation(["9", "/", "3", "=", "="], "1")
	_calculation(["2", "+", "="], "4")
	_calculation(["8", "/", "0", "=", "3"], "3")
	_calculation(["4", "+", "5", "C"], "0")
	var model := DesktopCalculator.new()
	for token: String in ["8", "/", "0", "="]:
		model.press(token)
	_expect(model.error and model.entry == "Ошибка", "Division by zero handled")
	model.clear()
	for index: int in range(20):
		model.press("9")
	_expect(model.entry.length() == 14, "Entry length is bounded")
	for token: String in ["*", "9", "="]:
		model.press(token)
	_expect(model.error, "Overflow handled")


func _calculation(tokens: Array, expected: String) -> void:
	var model := DesktopCalculator.new()
	for token: String in tokens:
		model.press(token)
	_expect(model.entry == expected, "Calculator %s = %s (got %s)" % [tokens, expected, model.entry])


func _key(code: Key, unicode: int = 0, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode
	event.ctrl_pressed = ctrl
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)


func _text(text: String) -> void:
	for character: String in text:
		if character == "\n":
			_key(KEY_ENTER)
		else:
			_key(KEY_NONE, character.unicode_at(0))


func _move_mouse(at: Vector2, holding: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - _mouse_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if holding else 0
	_mouse_position = at
	root.push_input(event)


func _mouse_button(pressed: bool, double: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = _mouse_position
	event.global_position = _mouse_position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event)


func _click(at: Vector2, double: bool = false) -> void:
	_move_mouse(at)
	_mouse_button(true, double)
	_mouse_button(false)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("DESKTOP: " + message)


func _capture() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var directory := argument.trim_prefix("--capture-dir=")
			root.get_texture().get_image().save_png(directory.path_join("desktop_windows.png"))
