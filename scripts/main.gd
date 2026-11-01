extends Node3D

signal hiding_changed(hidden: bool)
const DEFEAT_SCENES := {
	"POLICE_DEATH": preload("res://scenes/threats/police_defeat.tscn"),
	"NEIGHBOR_DEATH": preload("res://scenes/threats/neighbor_defeat.tscn"),
	"ENTITY_DEATH": preload("res://scenes/threats/entity_defeat.tscn"),
}
enum Mode { WALKING, ENTERING, COMPUTER, LEAVING, FUSEBOX_ENTERING, FUSEBOX, FUSEBOX_LEAVING, HIDING, CAPTURED }

@export_range(0.02, 2.0) var transition_seconds: float = 0.7
@export var observation_shift_enabled: bool = true
@export var atmosphere_config: AtmosphereConfig = preload("res://data/atmosphere/default.tres")

var mode: Mode = Mode.WALKING
var transition: Tween
var pointer_was_captured: bool = false
var pointer_retry_after_msec: int = 0
var fusebox_hint: Label
var _focus_active: bool = true
var run_ended: bool = false
var failure_reason: String = ""
var capture_reason: String = ""
var capture_cutscene: DefeatCutscene
@onready var visual_effects: VisualEffects = $VisualEffects

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
@onready var threats: ThreatManager = $ThreatManager
var ambient: AmbientDirector
var shift: ShiftDirector
var atmosphere: AtmosphereDirector
var neighbor: PsychNeighbor
var police: PoliceRaid
var outage: PowerOutage
var hiding_spot: HidingSpot
var _hide_entry_pose: Transform3D
var _hidden_look := Vector2.ZERO
var _hide_blocked_left: float = 0.0
@onready var room_door: RoomDoor = $Apartment/RoomDoor
@onready var hiding_spots: Dictionary = {
	&"hide_wardrobe": $Apartment/HidingSpots/Wardrobe,
	&"hide_bed": $Apartment/HidingSpots/Bed,
}


func _ready() -> void:
	terminal_ui.report_finished.connect(_finish_report)
	hud.bind_player(player)
	hud.game = self
	terminal_ui.cctv.bind_system(cctv_system)
	exit_button.pressed.connect(leave_computer)
	terminal_ui.leave_requested.connect(_leave_from_ui_escape)
	# A click is required for browser pointer lock; desktop uses the same flow.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	power.bind(self)
	power.power_changed.connect(_on_power_changed)
	power.outage_guard = threats.can_start_power_outage
	neighbor = PsychNeighbor.new()
	neighbor.bind(self)
	threats.register_event(&"psych_neighbor", neighbor)
	police = PoliceRaid.new()
	police.bind(self)
	threats.register_event(&"police_raid", police)
	outage = PowerOutage.new()
	outage.bind(self)
	threats.register_event(&"power_outage", outage)
	power.outage_request = threats.request_event.bind(&"power_outage", true)
	power.danger_audio_active = func() -> bool:
		return is_instance_valid(outage) and outage.has_active_encounter()
	ambient = AmbientDirector.new()
	add_child(ambient)
	ambient.bind(self)
	atmosphere = AtmosphereDirector.new()
	atmosphere.config = atmosphere_config
	add_child(atmosphere)
	atmosphere.bind(self)
	dev_menu.bind(self)
	dev_menu.opened.connect(_on_dev_opened)
	dev_menu.closed.connect(_on_dev_closed)
	fusebox_hint = Label.new()
	fusebox_hint.text = "FUSEBOX_HELP"
	fusebox_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fusebox_hint.add_theme_font_override("font", preload("res://assets/fonts/static/Handjet-SemiBold.ttf"))
	fusebox_hint.add_theme_font_size_override("font_size", 20)
	fusebox_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	fusebox_hint.add_theme_constant_override("shadow_offset_x", 2)
	fusebox_hint.add_theme_constant_override("shadow_offset_y", 2)
	fusebox_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(fusebox_hint)
	fusebox_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fusebox_hint.offset_top = -50
	fusebox_hint.hide()
	if observation_shift_enabled:
		shift = ShiftDirector.new()
		add_child(shift)
		shift.bind(self)
	visual_effects.bind(self)


func _physics_process(_delta: float) -> void:
	_hide_blocked_left = maxf(0.0, _hide_blocked_left - _delta)
	threats.random_allowed = is_instance_valid(shift) and shift.state == ShiftDirector.State.ROUTE
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Browsers may consume Esc before Godot receives it. Detect native unlock too.
	if pointer_was_captured and not captured:
		_record_pointer_release()
	pointer_was_captured = captured
	hud.visible = mode in [Mode.WALKING, Mode.HIDING] and not dev_menu.is_open
	fusebox_hint.visible = mode == Mode.FUSEBOX and not dev_menu.is_open
	if dev_menu.is_open:
		return
	if mode == Mode.HIDING:
		crosshair.hide()
		if not captured:
			hint.text = tr("Браузер освободил мышь. Подожди секунду, затем нажми ЛКМ") if Time.get_ticks_msec() < pointer_retry_after_msec else tr("Нажми ЛКМ, чтобы осмотреться")
		else:
			hint.text = tr("HIDE_EXIT_BLOCKED" if _hide_blocked_left > 0.0 else "HIDE_EXIT")
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
	elif player.interaction_id == &"room_door":
		hint.text = tr("DOOR_HELD" if room_door.held_by_police else "DOOR_BLOCKED" if room_door.blocked_seconds_left > 0.0 else "DOOR_CLOSE" if room_door.is_open else "DOOR_OPEN")
	elif hiding_spots.has(player.interaction_id):
		hint.text = tr(hiding_spots[player.interaction_id].prompt_key)
	else:
		hint.text = "" if power.powered else tr("FLASHLIGHT_HINT")


func _input(event: InputEvent) -> void:
	if mode == Mode.CAPTURED:
		if event.is_action_pressed("back"):
			_release_pointer()
		get_viewport().set_input_as_handled()
		return
	if dev_menu.is_open:
		return
	if mode == Mode.FUSEBOX or mode == Mode.FUSEBOX_ENTERING:
		# The flashlight also stays one keypress away while repairing.
		if event.is_action_pressed("flashlight") and not event.is_echo():
			power.toggle_flashlight()
			get_viewport().set_input_as_handled()
			return
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
		elif mode in [Mode.WALKING, Mode.HIDING]:
			_release_pointer()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.HIDING and not dev_menu.is_open:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_capture_pointer()
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event is InputEventMouseMotion:
				_hidden_look.x = clampf(_hidden_look.x - event.screen_relative.x * player.mouse_sensitivity, -deg_to_rad(hiding_spot.max_yaw_degrees), deg_to_rad(hiding_spot.max_yaw_degrees))
				_hidden_look.y = clampf(_hidden_look.y - event.screen_relative.y * player.mouse_sensitivity, -deg_to_rad(hiding_spot.max_pitch_degrees), deg_to_rad(hiding_spot.max_pitch_degrees))
				_update_hiding_view()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("interact") and not event.is_echo():
				leave_hiding()
				get_viewport().set_input_as_handled()
		return
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
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.interaction_id == &"room_door":
			room_door.toggle()
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and hiding_spots.has(player.interaction_id):
			enter_hiding(hiding_spots[player.interaction_id])
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("flashlight") and not event.is_echo() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		power.toggle_flashlight()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_active = false
		# The window may never receive keyup for held keys (hand browser blur);
		# drop stale action presses so the player cannot walk "by itself".
		_drop_stale_key_state()
		if is_instance_valid(power):
			power.board.cancel_hold()
			power.set_interacting(false)
		_release_pointer()
		if is_instance_valid(player):
			player.stop_motion()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_active = true
		# Clear again: keyups lost just before the blur can lag behind focus.
		_drop_stale_key_state()
		if is_instance_valid(power) and mode == Mode.FUSEBOX and not dev_menu.is_open:
			power.set_interacting(true)


func is_hidden() -> bool:
	return mode == Mode.HIDING and is_instance_valid(hiding_spot) and not run_ended


func enter_hiding(spot: HidingSpot) -> bool:
	if mode != Mode.WALKING or dev_menu.is_open or run_ended or not is_instance_valid(spot):
		return false
	_hide_entry_pose = player.global_transform
	hiding_spot = spot
	_hidden_look = Vector2.ZERO
	_hide_blocked_left = 0.0
	player.set_controls_enabled(false)
	player.interaction_id = &""
	_drop_stale_key_state(false)
	power.board.cancel_hold()
	hud.clear_smear()
	mode = Mode.HIDING
	_update_hiding_view()
	transition_camera.fov = spot.view_fov
	transition_camera.make_current()
	hiding_changed.emit(true)
	return true


func _update_hiding_view() -> void:
	if is_instance_valid(hiding_spot):
		var look := Basis(Vector3.UP, _hidden_look.x) * Basis(Vector3.RIGHT, _hidden_look.y)
		transition_camera.global_transform = hiding_spot.view.global_transform * Transform3D(look, Vector3.ZERO)


func leave_hiding(capture_pointer: bool = true) -> bool:
	if mode != Mode.HIDING or run_ended:
		return false
	var pose: Variant = hiding_spot.find_safe_exit(player, _hide_entry_pose, self)
	if pose == null:
		_hide_blocked_left = 2.0
		return false
	player.global_transform = pose
	player.head.rotation = Vector3.ZERO
	player.stop_motion(true)
	hiding_spot = null
	_resume_walking(false)
	if capture_pointer:
		_capture_pointer()
	# Exposure starts only after body, camera and controls agree.
	hiding_changed.emit(false)
	return true


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


func _resume_walking(flush_buffered_input: bool = true) -> void:
	mode = Mode.WALKING
	player.camera.make_current()
	# WASD typed in the terminal/fusebox UI stays "pressed" in the Input singleton
	# (typing reaches Input before the GUI consumes it) and would re-enable auto-walk.
	_drop_stale_key_state(flush_buffered_input)
	player.set_controls_enabled(not dev_menu.is_open)
	hud.show()


func _drop_stale_key_state(flush_buffered_input: bool = true) -> void:
	# Godot 4.6 has no GDScript binding for Input.release_pressed_events();
	# replaying buffered events plus explicit action releases covers our controls.
	# E enters/exits hiding synchronously: release action states there without
	# draining the input queue reentrantly from an input callback.
	if flush_buffered_input:
		Input.flush_buffered_events()
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint", &"interact"]:
		Input.action_release(action)


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
	threats.set_blocked(&"blackout", not powered)
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
		_drop_stale_key_state()
		player.set_controls_enabled(true)
	elif mode == Mode.COMPUTER and power.powered:
		terminal_ui.show()
		terminal_ui.resume_desktop()
	elif mode == Mode.FUSEBOX:
		power.board.set_active(true, transition_camera)
		power.set_interacting(_focus_active)
	elif mode == Mode.HIDING:
		_drop_stale_key_state()
		player.set_controls_enabled(false)
		_update_hiding_view()


func disable_threats() -> void:
	threats.disable_threats()
	power.restore_power()


func trigger_neighbor() -> bool:
	return threats.request_event(&"psych_neighbor", true)


func trigger_police() -> bool:
	return threats.request_event(&"police_raid", true)


func trigger_power_outage() -> bool:
	return threats.request_event(&"power_outage", true)


func fail_from_threat(reason: String) -> void:
	_finish_report(false, 0, reason)


func _finish_report(won: bool, score: int, reason: String = "") -> void:
	if run_ended:
		return
	run_ended = true
	atmosphere.enabled = false
	if is_instance_valid(capture_cutscene):
		capture_cutscene.queue_free()
	failure_reason = reason
	threats.disable_threats()
	if is_instance_valid(shift):
		shift.state = ShiftDirector.State.ENDED
	terminal_ui.suspend_desktop()
	cctv_system.set_watching(false)
	if ambient != null:
		ambient.stop_all()
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
	# Same artist font as EXIT for a consistent result screen.
	var report_font := preload("res://assets/fonts/static/Handjet-SemiBold.ttf")
	var report_theme := Theme.new()
	report_theme.default_font = report_font
	report_theme.default_font_size = 20
	column.theme = report_theme
	center.add_child(column)
	var title := Label.new()
	title.text = tr("THREAT_GAME_OVER" if not reason.is_empty() else "CHAT_WIN" if won else "CHAT_LOSE")
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	var detail := Label.new()
	detail.text = tr(reason) if not reason.is_empty() else tr("CHAT_RESULT") % [score, ChatSession.CONTENT.QUESTIONS.size()]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 300
	column.add_child(detail)
	var reply := Label.new()
	reply.text = tr("CHAT_SUCCESS" if won else "CHAT_FAILURE")
	reply.visible = reason.is_empty()
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


func threat_target_points() -> Array[Vector3]:
	if is_hidden() or run_ended or not capture_reason.is_empty():
		return []
	return [player.global_position + Vector3.UP * 1.55, player.global_position + Vector3.UP * 0.95]


func enemy_blocks_exit(position: Vector3) -> bool:
	var enemies: Array[Node3D] = []
	if is_instance_valid(police) and police.visit != PoliceRaid.Visit.DORMANT:
		enemies.append(police.visual)
	if is_instance_valid(neighbor) and neighbor.visit != PsychNeighbor.Visit.DORMANT:
		enemies.append(neighbor.visual)
	if is_instance_valid(outage) and outage.has_active_encounter():
		enemies.append(outage.entity)
	for enemy: Node3D in enemies:
		if Vector2(enemy.global_position.x - position.x, enemy.global_position.z - position.z).length() < 0.85:
			return true
	return false


func place_player_safely(position: Vector3) -> bool:
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var pose := player.global_transform
	pose.origin = position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.transform = pose * capsule.transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query).is_empty():
		return false
	player.global_transform = pose
	player.stop_motion(true)
	return true


func prepare_for_threat() -> bool:
	# No script can grant browser pointer lock without a real user gesture.
	var forced := mode in [Mode.ENTERING, Mode.COMPUTER, Mode.LEAVING, Mode.FUSEBOX_ENTERING, Mode.FUSEBOX, Mode.FUSEBOX_LEAVING]
	if not forced:
		return false
	_kill_transition()
	terminal_ui.suspend_desktop()
	terminal_ui.hide()
	power.board.set_active(false)
	power.set_interacting(false)
	if mode in [Mode.ENTERING, Mode.COMPUTER, Mode.LEAVING]:
		var exit_position: Vector3 = terminal.get_node("ExitPoint").global_position
		for offset: Vector3 in [Vector3.ZERO, Vector3(0.7, 0, 0), Vector3(0, 0, -0.7)]:
			if place_player_safely(exit_position + offset):
				break
	_resume_walking()
	player.stop_motion(true)
	if not OS.has_feature("web"):
		_capture_pointer()
	return true


func begin_threat_capture(reason: String, enemy: Node3D) -> bool:
	if run_ended or not capture_reason.is_empty() or is_hidden() or not DEFEAT_SCENES.has(reason) or not is_instance_valid(enemy):
		return false
	if dev_menu.is_open:
		dev_menu.close_menu()
	capture_reason = reason
	atmosphere.enabled = false
	threats.capture_in_progress = true
	if is_instance_valid(shift):
		shift.set_process(false)
	_kill_transition()
	terminal_ui.suspend_desktop()
	terminal_ui.hide()
	power.board.set_active(false)
	power.set_interacting(false)
	transition_camera.global_transform = get_viewport().get_camera_3d().global_transform
	transition_camera.fov = player.camera_motion.base_fov
	transition_camera.make_current()
	player.set_controls_enabled(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_drop_stale_key_state(false)
	mode = Mode.CAPTURED
	# Keep the choreography in the room where the attack happened.
	var face := enemy.global_position + Vector3.UP * 1.6
	if transition_camera.global_position.distance_squared_to(face) > 0.001:
		transition_camera.look_at(face, Vector3.UP)
	terminal_ui.process_mode = Node.PROCESS_MODE_DISABLED
	cctv_system.set_watching(false)
	cctv_system.process_mode = Node.PROCESS_MODE_DISABLED
	$Apartment.process_mode = Node.PROCESS_MODE_DISABLED
	power.set_flashlight_enabled(false)
	power.process_mode = Node.PROCESS_MODE_DISABLED
	ambient.stop_all()
	ambient.process_mode = Node.PROCESS_MODE_DISABLED
	dev_menu.visible = false
	dev_menu.process_mode = Node.PROCESS_MODE_DISABLED
	for audio: AudioStreamPlayer3D in threats.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	hud.clear_smear()
	capture_cutscene = DEFEAT_SCENES[reason].instantiate()
	capture_cutscene.autoplay = false
	add_child(capture_cutscene)
	capture_cutscene.place_at_capture(transition_camera, enemy, player)
	capture_cutscene.finished.connect(_finish_report.bind(false, 0, reason))
	return true


func _process(delta: float) -> void:
	if capture_reason.is_empty() or run_ended:
		return
	if is_instance_valid(capture_cutscene):
		capture_cutscene.advance(delta)
