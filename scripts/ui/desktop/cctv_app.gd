class_name CCTVApp
extends VBoxContainer

signal leave_requested

const FEED_SHADER := preload("res://assets/shaders/cctv_feed.gdshader")

var system: CCTVSystem
var directory: OptionButton
var image: TextureRect
var status: Label
var properties: Label
var telemetry: Label
var connection: Label
var buttons: Dictionary = {}
var input_enabled: bool = false
var _pan: float = 0.0
var _zoom: float = 0.0
var _material: ShaderMaterial


func _ready() -> void:
	directory = OptionButton.new()
	directory.name = "CameraDirectory"
	directory.focus_mode = Control.FOCUS_NONE
	directory.fit_to_longest_item = false
	directory.item_selected.connect(_select)
	directory.get_popup().window_input.connect(_popup_input)
	add_child(directory)
	properties = Label.new()
	properties.add_theme_font_size_override("font_size", 13)
	add_child(properties)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(240, 100)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var black := StyleBoxFlat.new()
	black.bg_color = Color("080e10")
	panel.add_theme_stylebox_override("panel", black)
	add_child(panel)
	image = TextureRect.new()
	image.name = "Feed"
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = FEED_SHADER
	image.material = _material
	panel.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection = Label.new()
	connection.text = "НЕТ КАМЕР"
	connection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	connection.add_theme_color_override("font_color", Color("aebeb6"))
	connection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(connection)
	connection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	telemetry = Label.new()
	telemetry.add_theme_font_size_override("font_size", 13)
	add_child(telemetry)
	var controls := HBoxContainer.new()
	add_child(controls)
	_control(controls, &"left", "<", "Повернуть влево · удерживать", 1.0, 0.0)
	_control(controls, &"right", ">", "Повернуть вправо · удерживать", -1.0, 0.0)
	_control(controls, &"out", "ZOOM -", "Отдалить · удерживать", 0.0, -1.0)
	_control(controls, &"in", "ZOOM +", "Приблизить · удерживать", 0.0, 1.0)
	status = Label.new()
	status.text = "LOCAL CCTV / OFFLINE NETWORK"
	status.add_theme_font_size_override("font_size", 12)
	add_child(status)
	visibility_changed.connect(_visibility_changed)
	_refresh_directory()


func _control(row: Control, id: StringName, text: String, tip: String, pan: float, zoom_direction: float) -> void:
	var button := Button.new()
	button.name = String(id).capitalize()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.button_down.connect(_start_command.bind(pan, zoom_direction))
	button.button_up.connect(release_controls)
	row.add_child(button)
	buttons[id] = button


func bind_system(value: CCTVSystem) -> void:
	if is_instance_valid(system):
		system.set_watching(false)
		if system.directory_changed.is_connected(_refresh_directory):
			system.directory_changed.disconnect(_refresh_directory)
	system = value
	if is_instance_valid(system):
		system.directory_changed.connect(_refresh_directory)
	_refresh_directory()
	_sync_watching()


func _refresh_directory() -> void:
	if not is_instance_valid(directory):
		return
	directory.clear()
	if not is_instance_valid(system) or system.cameras.is_empty():
		directory.add_item("Нет подключённых камер")
		directory.disabled = true
		properties.text = "MIC -- / VIDEO --"
		image.texture = null
		image.hide()
		connection.text = "НЕТ КАМЕР"
		connection.show()
		for button: Button in buttons.values():
			button.disabled = true
		return
	directory.disabled = false
	for camera: CCTVCamera in system.cameras:
		directory.add_item("%s / %s" % [camera.location_label, camera.display_name])
	image.texture = system.viewport.get_texture()
	_select(0)


func _select(index: int) -> void:
	if not is_instance_valid(system) or system.cameras.is_empty():
		return
	release_controls()
	system.select_camera(index)
	var camera := system.selected
	properties.text = "%s    /    %s" % ["VIDEO B/W" if camera.monochrome else "VIDEO COLOR", "MIC +" if camera.has_microphone else "MIC -"]
	properties.tooltip_text = "Микрофон: только свойство прототипа. Звук пока не подключён."
	_material.set_shader_parameter("monochrome", camera.monochrome)
	# Never present the previous camera's last frame under the new camera label.
	image.hide()
	connection.show()
	connection.text = "ПОДКЛЮЧЕНИЕ..."


func set_input_enabled(value: bool) -> void:
	if input_enabled == value:
		return
	input_enabled = value
	if not value:
		cancel_controls()


func _start_command(pan: float, zoom_direction: float) -> void:
	if not input_enabled or not is_instance_valid(system) or not system.can_show_feed():
		return
	_pan = pan
	_zoom = zoom_direction
	system.selected.command(_pan, _zoom)


func release_controls() -> void:
	_pan = 0.0
	_zoom = 0.0
	if is_instance_valid(system) and is_instance_valid(system.selected):
		system.selected.command(0.0, 0.0)


func cancel_controls() -> void:
	release_controls()
	if is_instance_valid(system) and is_instance_valid(system.selected):
		system.selected.stop_immediately()
	if is_instance_valid(directory):
		directory.get_popup().hide()


func _popup_input(event: InputEvent) -> void:
	if event.is_action_pressed("back") and not event.is_echo():
		directory.get_popup().hide()
		leave_requested.emit()


func _input(event: InputEvent) -> void:
	# Includes release outside the original button/window.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		release_controls()


func _process(_delta: float) -> void:
	if not is_instance_valid(system) or not is_instance_valid(system.selected):
		return
	var connected := system.can_show_feed()
	image.visible = connected
	connection.visible = not connected
	for button: Button in buttons.values():
		button.disabled = not connected
	var camera := system.selected
	_material.set_shader_parameter("interference", 1.0 if camera.interference_left > 0.0 else 0.0)
	var limit := " / LIMIT" if absf(camera.pan_degrees) >= camera.pan_limit_degrees - 0.1 else ""
	telemetry.text = "PAN %+.0f°%s   /   ZOOM %.1fx" % [camera.pan_degrees, limit, camera.zoom]
	status.text = "CONNECTING..." if not connected else ("SIGNAL UNSTABLE / MOTOR" if camera.interference_left > 0.0 else "LOCAL CCTV / %s / %02d FPS" % [camera.camera_id, int(system.feed_fps)])


func _sync_watching() -> void:
	if is_instance_valid(system):
		system.set_watching(is_visible_in_tree())
		if is_instance_valid(image) and not system.can_show_feed():
			image.hide()
			connection.show()
			connection.text = "ПОДКЛЮЧЕНИЕ..." if not system.cameras.is_empty() else "НЕТ КАМЕР"


func _visibility_changed() -> void:
	if not is_visible_in_tree():
		cancel_controls()
	_sync_watching()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_controls()


func _exit_tree() -> void:
	if is_instance_valid(system):
		system.set_watching(false)
