class_name TerminalDesktop
extends Control
## In-game controls only: no native OS windows, files or external services.

signal leave_requested
signal report_finished(won: bool, score: int)

const WINDOW_SCENE := preload("res://scenes/ui/desktop/desktop_window.tscn")
const NOTEPAD_SCENE := preload("res://scenes/ui/desktop/notepad.tscn")
const CALCULATOR_SCENE := preload("res://scenes/ui/desktop/calculator.tscn")
const CCTV_SCENE := preload("res://scenes/ui/desktop/cctv_app.tscn")
const CHAT_SCENE := preload("res://scenes/ui/desktop/chat.tscn")
const INPUT_AUDIO := preload("res://scripts/ui/desktop/desktop_input_audio.gd")
const NIGHT_NOTE := preload("res://scripts/ui/desktop/night_note_app.gd")
const ICONS := {
	&"hack": preload("res://assets/ui/chat.svg"),
	&"chat": preload("res://assets/ui/chat.svg"),
	&"notepad": preload("res://assets/ui/notepad.svg"),
	&"calculator": preload("res://assets/ui/calculator.svg"),
	&"cctv": preload("res://assets/ui/cctv.svg"),
	&"night_note": preload("res://assets/ui/notepad.svg"),
}
const TITLES := {&"notepad": "Блокнот", &"calculator": "Калькулятор", &"cctv": "CCTV", &"chat": "RELAY", &"hack": "ALARM.sh", &"night_note": "night.txt"}
const TASKBAR_HEIGHT := 44.0

var windows: Dictionary = {}
var task_buttons: Dictionary = {}
var desktop_icons: Dictionary = {}
var active_app: StringName = &""
var notepad: NotepadApp
var calculator: CalculatorApp
var cctv: CCTVApp
var chat: ChatApp
var night_note: NightNoteApp
var input_audio: Node
var _first_login: bool = true
var exit_button: Button
var start_button: Button
var start_menu: PanelContainer
var clock: Label
var _boot_msec: int = 0
var _clock_minute: int = -1
var _windows_layer: Control
var _task_list: HBoxContainer
var transient_overlay: Control

@onready var workspace: Control = $Workspace


func _ready() -> void:
	_boot_msec = Time.get_ticks_msec()
	_build_icons()
	_windows_layer = Control.new()
	_windows_layer.name = "Windows"
	_windows_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workspace.add_child(_windows_layer)
	_windows_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_taskbar()
	_build_start_menu()
	_create_app(&"notepad", Vector2(150, 100), Vector2(550, 380), Vector2(320, 230))
	_create_app(&"calculator", Vector2(540, 130), Vector2(330, 420), Vector2(280, 380))
	notepad = NOTEPAD_SCENE.instantiate()
	windows[&"notepad"].content.add_child(notepad)
	notepad.leave_requested.connect(leave_requested.emit)
	calculator = CALCULATOR_SCENE.instantiate()
	windows[&"calculator"].content.add_child(calculator)
	_create_app(&"cctv", Vector2(350, 35), Vector2(760, 540), Vector2(390, 295))
	cctv = CCTV_SCENE.instantiate()
	windows[&"cctv"].content.add_child(cctv)
	cctv.leave_requested.connect(leave_requested.emit)
	_create_app(&"chat", Vector2(180, 40), Vector2(680, 560), Vector2(330, 340))
	chat = CHAT_SCENE.instantiate()
	windows[&"chat"].content.add_child(chat)
	chat.finished.connect(func(won: bool, score: int): report_finished.emit(won, score))
	_create_app(&"hack", Vector2(240, 140), Vector2(480, 220), Vector2(330, 180))
	_create_app(&"night_note", Vector2(300, 70), Vector2(560, 490), Vector2(300, 230))
	night_note = NIGHT_NOTE.new()
	windows[&"night_note"].content.add_child(night_note)
	input_audio = INPUT_AUDIO.new()
	add_child(input_audio)
	resized.connect(_fit_workspace)
	visibility_changed.connect(_on_visibility_changed)
	_fit_workspace.call_deferred()
	_update_task_buttons()


func _build_icons() -> void:
	var index := 0
	for app: StringName in TITLES:
		var icon := Button.new()
		icon.name = String(app).capitalize() + "Icon"
		icon.theme_type_variation = &"DesktopIcon"
		icon.toggle_mode = true
		icon.position = Vector2(20, 24 + index * 116)
		icon.size = Vector2(110, 100)
		icon.tooltip_text = TITLES[app]
		icon.pressed.connect(_select_icon.bind(app))
		icon.gui_input.connect(_icon_input.bind(app))
		workspace.add_child(icon)
		desktop_icons[app] = icon
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(column)
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_top = 8
		var image := TextureRect.new()
		image.texture = ICONS[app]
		image.custom_minimum_size = Vector2(48, 48)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(image)
		var label := Label.new()
		label.text = TITLES[app]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("e4e8ed"))
		label.add_theme_color_override("font_shadow_color", Color("202933"))
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
		index += 1


func _build_taskbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "Taskbar"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -TASKBAR_HEIGHT
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = tr("Пуск")
	start_button.toggle_mode = true
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.custom_minimum_size.x = 96
	start_button.pressed.connect(_toggle_start)
	row.add_child(start_button)
	_task_list = HBoxContainer.new()
	_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_task_list)
	for app: StringName in TITLES:
		var button := Button.new()
		button.text = TITLES[app]
		button.icon = ICONS[app]
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 20)
		button.custom_minimum_size.x = 110
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_task_pressed.bind(app))
		_task_list.add_child(button)
		task_buttons[app] = button
	clock = Label.new()
	clock.custom_minimum_size.x = 72
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.tooltip_text = tr("Внутриигровое время сеанса")
	row.add_child(clock)


func _build_start_menu() -> void:
	start_menu = PanelContainer.new()
	start_menu.name = "StartMenu"
	start_menu.size = Vector2(250, 210)
	add_child(start_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	start_menu.add_child(column)
	var heading := Label.new()
	heading.text = tr("ЛОКАЛЬНЫЙ СЕАНС")
	heading.add_theme_font_size_override("font_size", 13)
	column.add_child(heading)
	for app: StringName in TITLES:
		var button := Button.new()
		button.text = TITLES[app]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = ICONS[app]
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = 40
		button.pressed.connect(launch_app.bind(app))
		column.add_child(button)
	column.add_child(HSeparator.new())
	exit_button = Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = tr("Встать [Esc]")
	exit_button.focus_mode = Control.FOCUS_NONE
	exit_button.custom_minimum_size.y = 38
	exit_button.pressed.connect(_close_start)
	column.add_child(exit_button)
	start_menu.hide()


func _create_app(app: StringName, at: Vector2, initial_size: Vector2, minimum: Vector2) -> void:
	var window: DesktopAppWindow = WINDOW_SCENE.instantiate()
	window.name = String(app).capitalize() + "Window"
	window.window_title = TITLES[app]
	window.minimum_window_size = minimum
	window.position = at
	window.size = initial_size
	_windows_layer.add_child(window)
	windows[app] = window
	window.state_changed.connect(_window_changed.bind(app))
	window.focus_requested.connect(activate_window.bind(app))


func _process(_delta: float) -> void:
	var minute := int((Time.get_ticks_msec() - _boot_msec) / 60000)
	if minute != _clock_minute:
		_clock_minute = minute
		var total := (9 * 60 + minute) % (24 * 60)
		clock.text = "%02d:%02d" % [int(total / 60), total % 60]


func launch_app(app: StringName) -> void:
	if not windows.has(app):
		return
	_close_start()
	_deselect_icons()
	windows[app].open_window()
	activate_window(app)
	_focus_content(app)


func activate_window(app: StringName) -> void:
	var window: DesktopAppWindow = windows[app]
	if not window.opened or window.minimized:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not window.is_ancestor_of(focus):
		focus.release_focus()
	active_app = app
	_windows_layer.move_child(window, -1)
	for id: StringName in windows:
		windows[id].set_active(id == active_app)
	_update_task_buttons()
	_sync_cctv_controls()
	_focus_content(app)


func _focus_content(app: StringName) -> void:
	if app == &"notepad" and is_visible_in_tree():
		notepad.focus_editor()
	elif app == &"chat" and is_visible_in_tree():
		chat.focus_composer()


func _task_pressed(app: StringName) -> void:
	_close_start()
	var window: DesktopAppWindow = windows[app]
	if app == active_app and window.visible:
		window.minimize()
	else:
		launch_app(app)


func _window_changed(app: StringName) -> void:
	var window: DesktopAppWindow = windows[app]
	if active_app == app and (not window.opened or window.minimized):
		_clear_active()
		for index: int in range(_windows_layer.get_child_count() - 1, -1, -1):
			var candidate := _windows_layer.get_child(index)
			if candidate is DesktopAppWindow and candidate.opened and not candidate.minimized:
				for id: StringName in windows:
					if windows[id] == candidate:
						activate_window(id)
						_focus_content(id)
				break
	_update_task_buttons()
	_sync_cctv_controls()


func _update_task_buttons() -> void:
	for app: StringName in task_buttons:
		var window: DesktopAppWindow = windows[app]
		var button: Button = task_buttons[app]
		button.visible = window.opened
		button.set_pressed_no_signal(active_app == app and not window.minimized)


func _clear_active() -> void:
	active_app = &""
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	for app: StringName in windows:
		windows[app].set_active(false)
	_update_task_buttons()
	_sync_cctv_controls()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = event.position
		if start_menu.visible and start_menu.get_global_rect().has_point(point):
			return
		# A fictional popup must not also activate/refocus an app underneath it.
		if is_instance_valid(transient_overlay) and transient_overlay.is_visible_in_tree():
			for popup: Control in transient_overlay.get_children():
				if popup.visible and popup.get_global_rect().has_point(point):
					return
		if not start_button.get_global_rect().has_point(point):
			_close_start()
		for index: int in range(_windows_layer.get_child_count() - 1, -1, -1):
			var window: DesktopAppWindow = _windows_layer.get_child(index)
			if window.visible and window.get_global_rect().has_point(point):
				for app: StringName in windows:
					if windows[app] == window:
						activate_window(app)
				return
		if workspace.get_global_rect().has_point(point):
			_clear_active()
			_deselect_icons()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or start_menu.visible or active_app != &"calculator":
		return
	if event is InputEventKey and calculator.handle_key(event):
		get_viewport().set_input_as_handled()


func _select_icon(app: StringName) -> void:
	for id: StringName in desktop_icons:
		desktop_icons[id].set_pressed_no_signal(id == app)


func _deselect_icons() -> void:
	for icon: Button in desktop_icons.values():
		icon.set_pressed_no_signal(false)


func _icon_input(event: InputEvent, app: StringName) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		launch_app(app)
		desktop_icons[app].accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		launch_app(app)
		desktop_icons[app].accept_event()


func _toggle_start() -> void:
	if not start_button.button_pressed:
		_close_start()
		return
	start_menu.show()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	start_menu.move_to_front()
	_fit_workspace()
	_sync_cctv_controls()


func _close_start() -> void:
	var was_open := start_menu.visible
	start_menu.hide()
	start_button.set_pressed_no_signal(false)
	if was_open and not active_app.is_empty():
		_focus_content(active_app)
	_sync_cctv_controls()


func _fit_workspace() -> void:
	var available := Vector2(size.x, maxf(size.y - TASKBAR_HEIGHT, 1.0))
	var rows := maxi(1, int((available.y - 24.0) / 116.0))
	var icon_index := 0
	for app: StringName in desktop_icons:
		var icon: Button = desktop_icons[app]
		if app == &"night_note":
			# Keep the file visible beside the initial RELAY window, not underneath it.
			icon.position = Vector2(maxf(20.0, available.x - 130.0), 24)
			continue
		icon.position = Vector2(20 + int(icon_index / rows) * 120, 24 + (icon_index % rows) * 116)
		icon_index += 1
	for window: DesktopAppWindow in windows.values():
		window.fit_to_area(available)
	start_menu.position = Vector2(6, maxf(size.y - TASKBAR_HEIGHT - start_menu.size.y - 3, 0))


func resume_desktop() -> void:
	_fit_workspace()
	input_audio.enabled = true
	if _first_login:
		_first_login = false
		launch_app(&"chat")
		chat.begin()
	_sync_cctv_controls()
	if not active_app.is_empty():
		_focus_content(active_app)


func suspend_desktop() -> void:
	if is_instance_valid(input_audio):
		input_audio.stop()
	if is_instance_valid(chat):
		chat.set_input_enabled(false)
	_close_start()
	cctv.cancel_controls()
	notepad.editor.get_menu().hide()
	for window: DesktopAppWindow in windows.values():
		window.cancel_gesture()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and is_instance_valid(start_menu):
		suspend_desktop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(start_menu):
		_close_start()


func _sync_cctv_controls() -> void:
	if is_instance_valid(chat):
		chat.set_input_enabled(active_app == &"chat" and not start_menu.visible and is_visible_in_tree())
	if is_instance_valid(cctv):
		cctv.set_input_enabled(active_app == &"cctv" and not start_menu.visible and is_visible_in_tree())
