class_name DesktopAppWindow
extends Control

signal state_changed
signal focus_requested

const MAXIMIZE_ICON := preload("res://assets/ui/window_maximize.svg")
const RESTORE_ICON := preload("res://assets/ui/window_restore.svg")
const GRIP_ICON := preload("res://assets/ui/window_grip.svg")

@export var window_title: String = "Приложение"
@export var minimum_window_size := Vector2(300, 240)

var opened: bool = false
var minimized: bool = false
var maximized: bool = false
var work_size := Vector2(1280, 676)
var restore_rect := Rect2()
var content: Control
var title_bar: Panel
var title_label: Label
var maximize_button: Button
var resize_grip: Control
var _dragging: bool = false
var _resize_edges := Vector2i.ZERO
var _start_mouse := Vector2.ZERO
var _start_rect := Rect2()


func _ready() -> void:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 5
	column.offset_top = 5
	column.offset_right = -5
	column.offset_bottom = -5
	title_bar = Panel.new()
	title_bar.custom_minimum_size.y = 32
	title_bar.gui_input.connect(_title_input)
	column.add_child(title_bar)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.offset_left = 8
	header.offset_top = 2
	header.offset_right = -2
	header.offset_bottom = -2
	title_label = Label.new()
	title_label.text = tr(window_title)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_label)
	_header_button(header, "_", tr("Свернуть"), minimize)
	maximize_button = _header_button(header, "", tr("Развернуть / восстановить"), toggle_maximized)
	maximize_button.icon = MAXIMIZE_ICON
	_header_button(header, "×", tr("Закрыть"), close_window)
	content = MarginContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(content)
	var grip := Control.new()
	resize_grip = grip
	grip.name = "ResizeGrip"
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	add_child(grip)
	grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.offset_left = -16
	grip.offset_top = -16
	grip.gui_input.connect(_grip_input.bind(grip))
	var grip_image := TextureRect.new()
	grip_image.texture = GRIP_ICON
	grip_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.add_child(grip_image)
	grip_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(cancel_gesture)
	set_active(false)
	hide()


func _header_button(parent: Control, text: String, tip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size.x = 30
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func set_active(active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("475b70") if active else Color("7a838c")
	style.border_width_bottom = 1
	style.border_color = Color("313d49")
	title_bar.add_theme_stylebox_override("panel", style)
	title_label.add_theme_color_override("font_color", Color("f0f2f4") if active else Color("d3d7db"))


func open_window() -> void:
	opened = true
	minimized = false
	show()
	fit_to_area(work_size)
	state_changed.emit()


func close_window() -> void:
	opened = false
	minimized = false
	cancel_gesture()
	hide()
	state_changed.emit()


func minimize() -> void:
	minimized = true
	cancel_gesture()
	hide()
	state_changed.emit()


func toggle_maximized() -> void:
	cancel_gesture()
	if maximized:
		maximized = false
		_apply_rect(restore_rect)
	else:
		restore_rect = Rect2(position, size)
		maximized = true
		position = Vector2.ZERO
		size = work_size
	maximize_button.icon = RESTORE_ICON if maximized else MAXIMIZE_ICON
	resize_grip.visible = not maximized
	state_changed.emit()


func fit_to_area(area_size: Vector2) -> void:
	work_size = area_size.max(Vector2.ONE)
	cancel_gesture()
	if maximized:
		position = Vector2.ZERO
		size = work_size
	else:
		_apply_rect(Rect2(position, size))


func _apply_rect(rect: Rect2) -> void:
	size = rect.size.clamp(minimum_window_size.min(work_size), work_size)
	position = rect.position.clamp(Vector2.ZERO, (work_size - size).max(Vector2.ZERO))


func _title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		focus_requested.emit()
		if event.double_click:
			toggle_maximized()
		elif not maximized:
			_begin_gesture(true, Vector2i.ZERO, _point_in_parent(title_bar, event.position))
		accept_event()


func _grip_input(event: InputEvent, grip: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not maximized:
		focus_requested.emit()
		_begin_gesture(false, Vector2i.ONE, _point_in_parent(grip, event.position))
		accept_event()


func _gui_input(event: InputEvent) -> void:
	if maximized:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	if event is not InputEventMouse:
		return
	var edges := _edges_at(event.position)
	if event is InputEventMouseMotion:
		if edges.x != 0 and edges.y != 0:
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if edges.x == edges.y else Control.CURSOR_BDIAGSIZE
		elif edges.x != 0:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		elif edges.y != 0:
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and edges != Vector2i.ZERO:
		focus_requested.emit()
		_begin_gesture(false, edges, _point_in_parent(self, event.position))
		accept_event()


func _edges_at(point: Vector2) -> Vector2i:
	var edges := Vector2i.ZERO
	if point.x < 5:
		edges.x = -1
	elif point.x >= size.x - 5:
		edges.x = 1
	if point.y < 5:
		edges.y = -1
	elif point.y >= size.y - 5:
		edges.y = 1
	return edges


func _begin_gesture(drag: bool, edges: Vector2i, mouse: Vector2 = Vector2.ZERO) -> void:
	_dragging = drag
	_resize_edges = edges
	_start_mouse = mouse
	_start_rect = Rect2(position, size)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (not _dragging and _resize_edges == Vector2i.ZERO):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel_gesture()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mouse: Vector2 = get_parent().get_global_transform_with_canvas().affine_inverse() * event.position
		move_gesture(mouse - _start_mouse)
		get_viewport().set_input_as_handled()


func move_gesture(delta: Vector2) -> void:
	if _dragging:
		_apply_rect(Rect2(_start_rect.position + delta, _start_rect.size))
	elif _resize_edges != Vector2i.ZERO:
		var minimum := minimum_window_size.min(work_size)
		var start := _start_rect.position
		var end := _start_rect.end
		if _resize_edges.x < 0:
			start.x = clampf(start.x + delta.x, 0.0, end.x - minimum.x)
		elif _resize_edges.x > 0:
			end.x = clampf(end.x + delta.x, start.x + minimum.x, work_size.x)
		if _resize_edges.y < 0:
			start.y = clampf(start.y + delta.y, 0.0, end.y - minimum.y)
		elif _resize_edges.y > 0:
			end.y = clampf(end.y + delta.y, start.y + minimum.y, work_size.y)
		_apply_rect(Rect2(start, end - start))


func cancel_gesture() -> void:
	_dragging = false
	_resize_edges = Vector2i.ZERO


func _point_in_parent(source: Control, point: Vector2) -> Vector2:
	return get_parent().get_global_transform_with_canvas().affine_inverse() * source.get_global_transform_with_canvas() * point


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_gesture()
