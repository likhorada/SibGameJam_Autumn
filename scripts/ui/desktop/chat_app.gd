class_name ChatApp
extends PanelContainer
signal finished(won: bool, score: int)
var session := ChatSession.new()
var input_enabled: bool = false
var transcript: RichTextLabel
var composer: Button
var options: VBoxContainer
var status: Label
var _delay: float = 0.0
var _blink: float = 0.0


func _ready() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("0b100e")
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	add_theme_stylebox_override("panel", panel)
	# Artist-supplied pixel font (Handjet) covers Latin and Cyrillic.
	var font := preload("res://assets/fonts/static/Handjet-SemiBold.ttf")
	var terminal_theme := Theme.new()
	terminal_theme.default_font = font
	terminal_theme.default_font_size = 20
	terminal_theme.set_color("font_color", "Label", Color("9ab69f"))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("1e3227") if state in ["hover", "pressed"] else Color("101b15")
		style.border_color = Color("7caa83") if state == "focus" else Color("38543f")
		style.set_border_width_all(1)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		terminal_theme.set_stylebox(state, "Button", style)
	for color: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		terminal_theme.set_color(color, "Button", Color("b6d4b9"))
	theme = terminal_theme
	add_theme_font_override("font", font)
	add_theme_color_override("font_color", Color("a6c7ad"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var title := Label.new()
	title.text = "RELAY / PRIVATE SESSION / 01"
	title.add_theme_color_override("font_color", Color("86aa8d"))
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	transcript = RichTextLabel.new()
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript.custom_minimum_size.y = 75
	transcript.add_theme_font_override("normal_font", font)
	transcript.add_theme_color_override("default_color", Color("b4c6b5"))
	transcript.add_theme_font_size_override("normal_font_size", 21)
	transcript.scroll_following = true
	transcript.selection_enabled = true
	column.add_child(transcript)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	options = VBoxContainer.new()
	column.add_child(options)
	composer = Button.new()
	composer.alignment = HORIZONTAL_ALIGNMENT_LEFT
	composer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	composer.custom_minimum_size.y = 48
	composer.pressed.connect(composer.grab_focus)
	composer.gui_input.connect(_composer_input)
	column.add_child(composer)
	session.changed.connect(_refresh)
	session.finished.connect(func(won: bool, score: int): finished.emit(won, score))
	_refresh()


func begin() -> void:
	session.start()


func focus_composer() -> void:
	if input_enabled and is_visible_in_tree() and not session.selected.is_empty():
		composer.grab_focus()


func set_input_enabled(value: bool) -> void:
	input_enabled = value


func _process(delta: float) -> void:
	if not input_enabled or not is_visible_in_tree():
		return
	_blink += delta
	_update_composer()
	if not session.pending.is_empty():
		_delay -= delta
		if _delay <= 0.0:
			_delay = 0.65
			session.deliver_next()


func _refresh() -> void:
	transcript.clear()
	for message: Dictionary in session.history:
		transcript.add_text(("< YOU\n" if message.sender == "you" else "> HANDLER\n") + tr(message.text) + "\n\n")
	for child: Node in options.get_children():
		options.remove_child(child)
		child.queue_free()
	if session.pending.is_empty() and not session.ended:
		for key: String in session.choices:
			var button := Button.new()
			button.text = tr(key)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(func():
				session.select_reply(key)
				focus_composer())
			options.add_child(button)
	status.text = tr("CHAT_RECEIVING" if not session.pending.is_empty() else "CHAT_TYPE_HELP" if not session.selected.is_empty() else "CHAT_CHOOSE" if not session.choices.is_empty() else "CHAT_IDLE")
	_update_composer()


func _update_composer() -> void:
	composer.text = "> " + tr(session.selected).left(session.typed) + ("_" if fmod(_blink, 1.0) < 0.5 else " ")


func _composer_input(event: InputEvent) -> void:
	if not input_enabled or session.selected.is_empty() or not event is InputEventKey or not event.pressed:
		return
	if event.is_action_pressed("back"):
		return
	var length := tr(session.selected).length()
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if not event.echo:
			session.submit(length)
		accept_event()
	elif event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if not event.echo:
			session.type_character(length)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(transcript):
		# Never allow a language change to submit a previously partial reply.
		session.typed = 0
		_refresh()
