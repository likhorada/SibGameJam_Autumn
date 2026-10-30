extends Node3D

enum Mode { WALKING, ENTERING, COMPUTER, LEAVING, FUSEBOX_ENTERING, FUSEBOX, FUSEBOX_LEAVING }

@export_range(0.02, 2.0) var transition_seconds: float = 0.7

var mode: Mode = Mode.WALKING
var transition: Tween
var pointer_was_captured: bool = false
var pointer_retry_after_msec: int = 0
var fusebox_hint: Label
var _focus_active: bool = true

@onready var player: ApartmentPlayer = $Player
@onready var terminal: Node3D = $Terminal
@onready var transition_camera: Camera3D = $TransitionCamera
@onready var terminal_ui: TerminalDesktop = $UI/TerminalUI
@onready var exit_button: Button = terminal_ui.exit_button
@onready var hud: PlayerHUD = $UI/HUD
@onready var hint: Label = $UI/HUD/Hint
@onready var crosshair: Label = $UI/HUD/Crosshair
@onready var cctv_system: CCTVSystem = $CCTVSystem
@onready var power: ApartmentPower = $PowerSystem
@onready var dev_menu = $DevMenu


func _ready() -> void:
	terminal_ui.report_finished.connect(_finish_report)
	hud.bind_player(player)
	terminal_ui.cctv.bind_system(cctv_system)
	exit_button.pressed.connect(leave_computer)
	terminal_ui.leave_requested.connect(_leave_from_ui_escape)
	# A click is required for browser pointer lock; desktop uses the same flow.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	power.bind(self)
	power.power_changed.connect(_on_power_changed)
	dev_menu.bind(self)
	dev_menu.opened.connect(_on_dev_opened)
	dev_menu.closed.connect(_on_dev_closed)
	fusebox_hint = Label.new()
	fusebox_hint.text = "FUSEBOX_HELP"
	fusebox_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fusebox_hint.add_theme_font_size_override("font_size", 18)
	fusebox_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	fusebox_hint.add_theme_constant_override("shadow_offset_x", 2)
	fusebox_hint.add_theme_constant_override("shadow_offset_y", 2)
	fusebox_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(fusebox_hint)
	fusebox_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fusebox_hint.offset_top = -50
	fusebox_hint.hide()


func _physics_process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Browsers may consume Esc before Godot receives it. Detect native unlock too.
	if pointer_was_captured and not captured:
		_record_pointer_release()
	pointer_was_captured = captured
	hud.visible = mode == Mode.WALKING and not dev_menu.is_open
	fusebox_hint.visible = mode == Mode.FUSEBOX and not dev_menu.is_open
	if dev_menu.is_open:
		return
	if mode != Mode.WALKING:
		return
	crosshair.visible = captured
	if not captured and Time.get_ticks_msec() < pointer_retry_after_msec:
		hint.text = tr("Браузер освободил мышь. Подожди секунду, затем нажми ЛКМ")
	elif not captured:
		hint.text = tr("Нажми ЛКМ, чтобы осмотреться")
	elif player.interaction_id == &"computer":
		hint.text = tr("E — сесть за компьютер") if power.powered else tr("NO_POWER")
	elif player.interaction_id == &"fusebox":
		hint.text = tr("POWER_OK") if power.powered else tr("USE_FUSEBOX")
	else:
		hint.text = ""


func _input(event: InputEvent) -> void:
	if dev_menu.is_open:
		return
	if mode == Mode.FUSEBOX or mode == Mode.FUSEBOX_ENTERING:
		var moving := false
		for action: String in ["move_forward", "move_backward", "move_left", "move_right"]:
			moving = moving or event.is_action_pressed(action)
		if event.is_action_pressed("back") or moving:
			leave_fusebox(not OS.has_feature("web") or moving)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("back") and not event.is_echo():
		if mode == Mode.COMPUTER:
			leave_computer(not OS.has_feature("web"))
		elif mode == Mode.WALKING:
			_release_pointer()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.WALKING or dev_menu.is_open:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_capture_pointer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.interaction_id == &"computer":
			enter_computer()
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.interaction_id == &"fusebox" and not power.powered:
			enter_fusebox()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_active = false
		if is_instance_valid(power):
			power.board.cancel_hold()
			power.set_interacting(false)
		_release_pointer()
		if is_instance_valid(player):
			player.stop_motion()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_active = true
		if is_instance_valid(power) and mode == Mode.FUSEBOX and not dev_menu.is_open:
			power.set_interacting(true)


func enter_computer() -> void:
	if mode != Mode.WALKING or not power.powered or dev_menu.is_open:
		return
	mode = Mode.ENTERING
	# Copy before disabling motion: preserve the exact rendered bob/roll/FOV.
	transition_camera.global_transform = player.camera.global_transform
	transition_camera.fov = player.camera.fov
	player.set_controls_enabled(false)
	hud.clear_smear()
	player.interaction_id = &""
	hud.hide()
	transition_camera.make_current()
	transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(transition_camera, "global_transform", terminal.get_node("SeatView").global_transform, transition_seconds * 0.45)
	transition.parallel().tween_property(transition_camera, "fov", player.camera_motion.base_fov, transition_seconds * 0.45)
	transition.tween_property(transition_camera, "global_transform", terminal.get_node("MonitorView").global_transform, transition_seconds * 0.55)
	transition.tween_callback(_show_desktop)


func _show_desktop() -> void:
	if not power.powered:
		_eject_from_computer()
		return
	mode = Mode.COMPUTER
	terminal_ui.show()
	_release_pointer()
	terminal_ui.resume_desktop()


func leave_computer(capture_pointer: bool = true) -> void:
	if mode != Mode.COMPUTER:
		return
	mode = Mode.LEAVING
	terminal_ui.suspend_desktop()
	terminal_ui.hide()
	# Capture synchronously from the user's button/key gesture, not a tween callback.
	if capture_pointer:
		_capture_pointer()
	player.place_at(terminal.get_node("ExitPoint"))
	transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(transition_camera, "global_transform", terminal.get_node("SeatView").global_transform, transition_seconds * 0.45)
	transition.tween_property(transition_camera, "global_transform", player.camera.global_transform, transition_seconds * 0.55)
	transition.tween_callback(_resume_walking)


func _leave_from_ui_escape() -> void:
	# Browser Esc can veto pointer lock in the very same key gesture.
	leave_computer(not OS.has_feature("web"))


func _resume_walking() -> void:
	mode = Mode.WALKING
	player.camera.make_current()
	player.set_controls_enabled(not dev_menu.is_open)
	hud.show()


func _capture_pointer() -> void:
	if not dev_menu.is_open and Time.get_ticks_msec() >= pointer_retry_after_msec:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_pointer() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or pointer_was_captured:
		_record_pointer_release()
	pointer_was_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(player):
		player.stop_motion()
	if is_instance_valid(hud):
		hud.clear_smear()


func _record_pointer_release() -> void:
	if OS.has_feature("web"):
		# Chrome's security cooldown also applies to very rapid PC enter/exit cycles.
		pointer_retry_after_msec = Time.get_ticks_msec() + 2000


func _exit_tree() -> void:
	if is_instance_valid(transition):
		transition.kill()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _kill_transition() -> void:
	if is_instance_valid(transition):
		transition.kill()


func _eject_from_computer() -> void:
	_kill_transition()
	terminal_ui.suspend_desktop()
	terminal_ui.hide()
	player.place_at(terminal.get_node("ExitPoint"))
	_release_pointer()
	_resume_walking()


func _on_power_changed(powered: bool) -> void:
	if not powered and mode in [Mode.ENTERING, Mode.COMPUTER, Mode.LEAVING]:
		_eject_from_computer()
	elif powered and mode in [Mode.FUSEBOX_ENTERING, Mode.FUSEBOX]:
		leave_fusebox(false)


func enter_fusebox() -> void:
	if mode != Mode.WALKING or power.powered or dev_menu.is_open:
		return
	mode = Mode.FUSEBOX_ENTERING
	transition_camera.global_transform = player.camera.global_transform
	transition_camera.fov = player.camera.fov
	player.set_controls_enabled(false)
	hud.clear_smear()
	hud.hide()
	_release_pointer()
	transition_camera.make_current()
	_kill_transition()
	transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(transition_camera, "global_transform", power.board.get_node("CloseView").global_transform, transition_seconds)
	transition.parallel().tween_property(transition_camera, "fov", 55.0, transition_seconds)
	transition.tween_callback(_finish_fusebox_enter)


func _finish_fusebox_enter() -> void:
	mode = Mode.FUSEBOX
	power.board.set_active(not dev_menu.is_open, transition_camera)
	power.set_interacting(not dev_menu.is_open and _focus_active)


func leave_fusebox(capture_pointer: bool = true) -> void:
	if mode not in [Mode.FUSEBOX_ENTERING, Mode.FUSEBOX]:
		return
	_kill_transition()
	power.board.set_active(false)
	power.set_interacting(false)
	mode = Mode.FUSEBOX_LEAVING
	if capture_pointer:
		_capture_pointer()
	transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(transition_camera, "global_transform", player.camera.global_transform, minf(transition_seconds, 0.25))
	transition.parallel().tween_property(transition_camera, "fov", player.camera.fov, minf(transition_seconds, 0.25))
	transition.tween_callback(_resume_walking)


func _on_dev_opened() -> void:
	player.set_controls_enabled(false)
	_release_pointer()
	power.board.set_active(false)
	power.set_interacting(false)
	if mode == Mode.COMPUTER:
		terminal_ui.suspend_desktop()
		terminal_ui.hide()


func _on_dev_closed() -> void:
	if mode == Mode.WALKING:
		player.set_controls_enabled(true)
	elif mode == Mode.COMPUTER and power.powered:
		terminal_ui.show()
		terminal_ui.resume_desktop()
	elif mode == Mode.FUSEBOX:
		power.board.set_active(true, transition_camera)
		power.set_interacting(_focus_active)


func _finish_report(won: bool, score: int) -> void:
	terminal_ui.suspend_desktop()
	cctv_system.set_watching(false)
	_release_pointer()
	_kill_transition()
	# Freeze this run, but keep only the result overlay processing input.
	process_mode = Node.PROCESS_MODE_DISABLED
	var result := CanvasLayer.new()
	result.layer = 50
	result.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(result)
	var backdrop := ColorRect.new()
	backdrop.color = Color("080d0b")
	result.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	backdrop.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	var title := Label.new()
	title.text = tr("CHAT_WIN" if won else "CHAT_LOSE")
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var detail := Label.new()
	detail.text = tr("CHAT_RESULT") % [score, ChatSession.CONTENT.QUESTIONS.size()]
	column.add_child(detail)
	var reply := Label.new()
	reply.text = tr("CHAT_SUCCESS" if won else "CHAT_FAILURE")
	reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply.custom_minimum_size.x = 300
	column.add_child(reply)
	for item: Array in [["CHAT_RESTART", "res://scenes/main.tscn"], ["CHAT_MENU", "res://scenes/menu/menu.tscn"]]:
		var button := Button.new()
		button.text = tr(item[0])
		button.pressed.connect(func(): get_tree().change_scene_to_file(item[1]))
		column.add_child(button)
		if item[0] == "CHAT_RESTART":
			button.grab_focus()
