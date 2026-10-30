class_name CalculatorApp
extends VBoxContainer

var model := DesktopCalculator.new()
var display: Label
var status: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 52
	add_child(panel)
	display = Label.new()
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	display.add_theme_font_size_override("font_size", 28)
	panel.add_child(display)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.custom_minimum_size.y = 20
	add_child(status)
	var clear_row := HBoxContainer.new()
	add_child(clear_row)
	_button(clear_row, "BS", "BACK").tooltip_text = tr("Удалить последнюю цифру [Backspace]")
	_button(clear_row, "CE", "CE")
	_button(clear_row, "C", "C")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(grid)
	var tokens := ["7", "8", "9", "/", "4", "5", "6", "*", "1", "2", "3", "-", "SIGN", "0", ".", "+"]
	for token: String in tokens:
		var label := token
		match token:
			"SIGN": label = "±"
			"/": label = "÷"
			"*": label = "×"
			".": label = ","
		_button(grid, label, token)
	_button(self, "=", "=").size_flags_vertical = Control.SIZE_FILL
	_refresh()


func _button(parent: Control, label: String, token: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(44, 36)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(press.bind(token))
	parent.add_child(button)
	return button


func press(token: String) -> void:
	model.press(token)
	_refresh()


func _refresh() -> void:
	display.text = tr(model.entry) if model.entry == "Ошибка" else model.entry.replace(".", ",")
	status.text = tr(model.error_message) if not model.error_message.is_empty() else ""


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	var token := ""
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_EQUAL: token = "="
		KEY_BACKSPACE: token = "BACK"
		KEY_DELETE: token = "CE"
		KEY_C: token = "C"
		KEY_F9: token = "SIGN"
		KEY_KP_0: token = "0"
		KEY_KP_1: token = "1"
		KEY_KP_2: token = "2"
		KEY_KP_3: token = "3"
		KEY_KP_4: token = "4"
		KEY_KP_5: token = "5"
		KEY_KP_6: token = "6"
		KEY_KP_7: token = "7"
		KEY_KP_8: token = "8"
		KEY_KP_9: token = "9"
		KEY_KP_PERIOD: token = "."
		KEY_KP_ADD: token = "+"
		KEY_KP_SUBTRACT: token = "-"
		KEY_KP_MULTIPLY: token = "*"
		KEY_KP_DIVIDE: token = "/"
	if event.unicode > 0:
		var character := String.chr(event.unicode)
		if character in "0123456789+-*/.,=":
			token = character
	if token.is_empty():
		return false
	press(token)
	return true
