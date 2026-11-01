class_name QuestionPopup
extends DesktopAppWindow
## Non-modal and silent. Only drag and close; no answer or minimize-to-nowhere.
signal dismissed
var question_key: StringName
var body: Label
var close_button: Button


func _ready() -> void:
	window_title = "AQ_TITLE"
	minimum_window_size = Vector2(300, 180)
	super._ready()
	for child: Node in title_bar.get_child(0).get_children():
		if child is Button:
			if child.text == "×":
				close_button = child
			else:
				child.hide()
	resize_grip.hide()
	body = Label.new()
	body.text = tr(question_key)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_size_override("font_size", 22)
	content.add_theme_constant_override("margin_left", 18)
	content.add_theme_constant_override("margin_right", 18)
	content.add_theme_constant_override("margin_top", 12)
	content.add_theme_constant_override("margin_bottom", 12)
	content.add_child(body)
	size = Vector2(500, 230)
	open_window()
	set_active(true)


func close_window() -> void:
	if not opened:
		return
	super.close_window()
	dismissed.emit()


func _edges_at(_point: Vector2) -> Vector2i:
	return Vector2i.ZERO


func _title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_gesture(true, Vector2i.ZERO, _point_in_parent(title_bar, event.position))
		accept_event()
