class_name IdiotPopup
extends Control
## A painted, fictional browser INSIDE the game. No Window, web view or URL handling.
signal close_attempted(popup: IdiotPopup)

const BASE_SIZE := Vector2(320, 220)
var velocity := Vector2.ZERO
var draggable: bool = true
var close_button: Button
var _dragging: bool = false
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = ""
	close_button.add_theme_font_override("font", _font)
	close_button.add_theme_font_size_override("font_size", 15)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("a0a0a0") if state in ["pressed", "hover_pressed"] else Color("c0c0c0")
		style.border_color = Color("606060")
		style.set_border_width_all(1)
		style.set_content_margin_all(0.0)
		close_button.add_theme_stylebox_override(state, style)
	close_button.add_theme_color_override("font_color", Color.BLACK)
	close_button.add_theme_color_override("font_pressed_color", Color.BLACK)
	close_button.pressed.connect(func(): close_attempted.emit(self))
	add_child(close_button)
	resized.connect(_fit_close_button)
	visibility_changed.connect(cancel_drag)
	_fit_close_button()


func _fit_close_button() -> void:
	if is_instance_valid(close_button):
		var scale_factor := size / BASE_SIZE
		close_button.add_theme_font_size_override("font_size", maxi(8, int(15 * minf(scale_factor.x, scale_factor.y))))
		close_button.position = Vector2(294, 5) * scale_factor
		close_button.size = Vector2(20, 19) * scale_factor
	queue_redraw()


func fit_to_area(area: Vector2) -> void:
	size = BASE_SIZE.min(area.max(Vector2.ONE))
	position = position.clamp(Vector2.ZERO, (area - size).max(Vector2.ZERO))


func advance(delta: float, area: Vector2) -> void:
	if not is_visible_in_tree():
		cancel_drag()
	if velocity == Vector2.ZERO:
		return
	position += velocity * delta
	var limit := (area - size).max(Vector2.ZERO)
	if position.x <= 0.0:
		velocity.x = absf(velocity.x)
	elif position.x >= limit.x:
		velocity.x = -absf(velocity.x)
	if position.y <= 0.0:
		velocity.y = absf(velocity.y)
	elif position.y >= limit.y:
		velocity.y = -absf(velocity.y)
	position = position.clamp(Vector2.ZERO, limit)


func cancel_drag() -> void:
	_dragging = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and draggable and event.position.y <= size.y * 29.0 / BASE_SIZE.y:
			_dragging = true
		elif not event.pressed:
			cancel_drag()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if not draggable or not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			cancel_drag()
			return
		position = (position + event.relative).clamp(Vector2.ZERO, (get_parent_control().size - size).max(Vector2.ZERO))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_drag()


func _draw() -> void:
	# Fixed reference canvas scales down only if the desktop becomes very small.
	draw_set_transform(Vector2.ZERO, 0.0, size / BASE_SIZE)
	draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), Color("c0c0c0"))
	draw_rect(Rect2(Vector2.ONE, BASE_SIZE - Vector2(2, 2)), Color.WHITE, false, 1.0)
	draw_line(Vector2(1, 219), Vector2(319, 219), Color("404040"))
	draw_line(Vector2(319, 1), Vector2(319, 219), Color("404040"))
	draw_rect(Rect2(4, 4, 312, 22), Color("000080"))
	draw_circle(Vector2(15, 15), 6, Color("7fbee5"))
	draw_arc(Vector2(15, 15), 5, 0, TAU, 20, Color.WHITE, 1.0)
	draw_string(_font, Vector2(27, 20), "Internet Browser", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_string(_font, Vector2(9, 41), "File   Edit   View   Favorites   Help", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	draw_line(Vector2(5, 46), Vector2(315, 46), Color("808080"))
	draw_string(_font, Vector2(10, 62), "< Back    Forward >    Stop    Home", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("303030"))
	draw_string(_font, Vector2(8, 82), "Address", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	draw_rect(Rect2(55, 68, 256, 19), Color("808080"))
	draw_rect(Rect2(56, 69, 254, 17), Color.WHITE)
	draw_string(_font, Vector2(60, 82), "about:blank", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
	draw_rect(Rect2(6, 92, 308, 108), Color.WHITE)
	draw_string(_font, Vector2(8, 123), "you are an idiot", HORIZONTAL_ALIGNMENT_CENTER, 304, 25, Color.BLACK)
	for x: float in [80.0, 160.0, 240.0]:
		var center := Vector2(x, 164)
		draw_circle(center, 21, Color.BLACK, false, 2.0, true)
		draw_circle(center + Vector2(-7, -6), 2.5, Color.BLACK)
		draw_circle(center + Vector2(7, -6), 2.5, Color.BLACK)
		draw_arc(center, 13, PI * 0.12, PI * 0.88, 20, Color.BLACK, 2.0, true)
	draw_string(_font, Vector2(9, 214), "Done", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("303030"))
