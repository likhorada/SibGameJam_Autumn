extends Node3D

enum Mode { WALKING, ENTERING, COMPUTER, LEAVING }

@export_range(0.02, 2.0) var transition_seconds: float = 0.7

var mode: Mode = Mode.WALKING
var transition: Tween
var pointer_was_captured: bool = false
var pointer_retry_after_msec: int = 0

@onready var player: ApartmentPlayer = $Player
@onready var terminal: Node3D = $Terminal
@onready var transition_camera: Camera3D = $TransitionCamera
@onready var terminal_ui: TerminalDesktop = $UI/TerminalUI
@onready var exit_button: Button = terminal_ui.exit_button
@onready var hud: Control = $UI/HUD
@onready var hint: Label = $UI/HUD/Hint
@onready var crosshair: Label = $UI/HUD/Crosshair


func _ready() -> void:
	exit_button.pressed.connect(leave_computer)
	terminal_ui.leave_requested.connect(_leave_from_ui_escape)
	# A click is required for browser pointer lock; desktop uses the same flow.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Browsers may consume Esc before Godot receives it. Detect native unlock too.
	if pointer_was_captured and not captured:
		_record_pointer_release()
	pointer_was_captured = captured
	hud.visible = mode == Mode.WALKING
	if mode != Mode.WALKING:
		return
	crosshair.visible = captured
	if not captured and Time.get_ticks_msec() < pointer_retry_after_msec:
		hint.text = "Браузер освободил мышь. Подожди секунду, затем нажми ЛКМ"
	elif not captured:
		hint.text = "Нажми ЛКМ, чтобы осмотреться"
	elif player.interaction_id == &"computer":
		hint.text = "E — сесть за компьютер"
	else:
		hint.text = ""


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("back") and not event.is_echo():
		if mode == Mode.COMPUTER:
			leave_computer(not OS.has_feature("web"))
		elif mode == Mode.WALKING:
			_release_pointer()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.WALKING:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_capture_pointer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.interaction_id == &"computer":
			enter_computer()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_pointer()
		if is_instance_valid(player):
			player.stop_motion()


func enter_computer() -> void:
	if mode != Mode.WALKING:
		return
	mode = Mode.ENTERING
	# Copy before disabling motion: preserve the exact rendered bob/roll/FOV.
	transition_camera.global_transform = player.camera.global_transform
	transition_camera.fov = player.camera.fov
	player.set_controls_enabled(false)
	player.interaction_id = &""
	hud.hide()
	transition_camera.make_current()
	transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(transition_camera, "global_transform", terminal.get_node("SeatView").global_transform, transition_seconds * 0.45)
	transition.parallel().tween_property(transition_camera, "fov", player.camera_motion.base_fov, transition_seconds * 0.45)
	transition.tween_property(transition_camera, "global_transform", terminal.get_node("MonitorView").global_transform, transition_seconds * 0.55)
	transition.tween_callback(_show_desktop)


func _show_desktop() -> void:
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
	player.set_controls_enabled(true)
	hud.show()


func _capture_pointer() -> void:
	if Time.get_ticks_msec() >= pointer_retry_after_msec:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_pointer() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or pointer_was_captured:
		_record_pointer_release()
	pointer_was_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(player):
		player.stop_motion()


func _record_pointer_release() -> void:
	if OS.has_feature("web"):
		# Chrome's security cooldown also applies to very rapid PC enter/exit cycles.
		pointer_retry_after_msec = Time.get_ticks_msec() + 2000


func _exit_tree() -> void:
	if is_instance_valid(transition):
		transition.kill()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
