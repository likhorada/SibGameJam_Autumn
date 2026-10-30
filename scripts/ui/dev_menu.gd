extends CanvasLayer
## Deliberately available in release. Disable Enabled on the scene node for publishing.
signal opened
signal closed

@export var enabled: bool = true
@export_range(0.1, 10.0) var hold_seconds: float = 5.0
var game: Node3D
var is_open: bool = false
var _holding: bool = false
var _held_seconds: float = 0.0
var _overlay: ColorRect
var _status: Label
var _unlimited: CheckButton
var _close_button: Button


func bind(value: Node3D) -> void:
	game = value
	layer = 30
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.85)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu_theme := Theme.new()
	# Same artist font as the menu; the desktop apps keep their own fonts.
	menu_theme.default_font = preload("res://assets/fonts/static/Handjet-SemiBold.ttf")
	_overlay.theme = menu_theme
	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "DEV MENU"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(420, 65)
	column.add_child(_status)
	_unlimited = CheckButton.new()
	_unlimited.text = "DEV_UNLIMITED"
	_unlimited.toggled.connect(func(value_enabled: bool): game.player.stamina.set_unlimited(value_enabled))
	column.add_child(_unlimited)
	_button(column, "DEV_POWER_OFF", func(): game.power.trigger_outage())
	_button(column, "DEV_POWER_ON", func(): game.power.restore_power())
	_button(column, "DEV_CLEAR_COOLDOWN", func(): game.power.clear_cooldown())
	_button(column, "OBS_DEV_NEXT", func():
		close_menu()
		if not is_instance_valid(game.shift):
			return
		if game.shift.state == ShiftDirector.State.ROUTE:
			game.shift.advance(300.0)
		elif game.shift.state == ShiftDirector.State.SCARE:
			game.shift.complete_scare())
	_button(column, "DEV_CHAT_REPORT", func():
		if not game.power.powered or game.mode not in [game.Mode.WALKING, game.Mode.COMPUTER]:
			return
		close_menu()
		if is_instance_valid(game.shift):
			game.shift.state = ShiftDirector.State.ENDED
		game.terminal_ui.chat.session.live_report = false
		game.terminal_ui.chat.session.start_quiz()
		game.terminal_ui.launch_app(&"chat")
		if game.mode == game.Mode.WALKING:
			game.enter_computer())
	_close_button = _button(column, "BACK", close_menu)
	_overlay.hide()


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_F7:
		if not event.echo:
			_holding = event.pressed and enabled and not is_open
			_held_seconds = 0.0
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("back"):
		close_menu()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not enabled:
		_holding = false
		_held_seconds = 0.0
		if is_open:
			close_menu()
		return
	if _holding:
		_held_seconds += delta
		if _held_seconds >= hold_seconds and game.mode in [game.Mode.WALKING, game.Mode.COMPUTER, game.Mode.FUSEBOX]:
			open_menu()
	if is_open:
		_status.text = tr("DEV_STATUS") % ["POWER_ON" if game.power.powered else "POWER_OFF", game.power.cooldown_left, str(game.power.board.latched)]
		_unlimited.set_pressed_no_signal(game.player.stamina.unlimited)


func open_menu() -> void:
	if not enabled or is_open:
		return
	_holding = false
	_held_seconds = 0.0
	is_open = true
	_overlay.show()
	opened.emit()
	_close_button.grab_focus()


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	_holding = false
	_held_seconds = 0.0
	_overlay.hide()
	closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_holding = false
		_held_seconds = 0.0
