extends "res://scripts/main.gd"
## Test-only deterministic poses/telemetry for real browser GUI and rendered detection.
var _command_id: int = 0
var _prepared: bool = false
var _last_request: bool = false
var _last_figure_reason: StringName = &""
var _tracked_figure_id: int = 0


func _ready() -> void:
	if OS.has_feature("web"):
		TranslationServer.set_locale(str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'en'")))
	super._ready()
	transition_seconds = 0.04
	dev_menu.hold_seconds = 0.1
	shift.set_process(false)
	threats.set_process(false)
	atmosphere.set_process(false)
	enter_computer.call_deferred()
	var bridge := Timer.new()
	bridge.wait_time = 0.05
	bridge.autostart = true
	add_child(bridge)
	bridge.timeout.connect(_publish)


func _aim(which: String) -> void:
	mode = Mode.WALKING
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.make_current()
	var point: Vector3 = get_node("Apartment/BathroomApparitionPoint").global_position
	player.camera.global_position = Vector3(0, 1.6, 2.8) if which == "wall" else Vector3(0, 1.6, 0)
	player.camera.look_at(Vector3(0, 1.6, -10) if which == "away" else point + Vector3.UP * 1.3)
	if which == "peripheral":
		player.camera.global_basis = Basis(Vector3.UP, deg_to_rad(50)) * player.camera.global_basis
	visual_effects._process(0)


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	if not _prepared and mode == Mode.COMPUTER:
		_prepared = true
		terminal_ui.launch_app(&"notepad")
		terminal_ui.notepad.editor.text = "Resident evidence"
	var raw = JavaScriptBridge.eval("JSON.stringify(window.residentsCommand || null)")
	var command = JSON.parse_string(str(raw))
	if command is Dictionary:
		JavaScriptBridge.eval("window.residentsCommand = null")
		_command_id = int(command.id)
		match str(command.name):
			"reveal":
				for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
					if button.text == str(command.get("button", "")):
						dev_menu._scroll.ensure_control_visible(button)
			"question": _last_request = atmosphere.request_event(&"question_popup", true)
			"figure": _last_request = atmosphere.request_event(&"bathroom_apparition", true)
			"room_camera": _last_request = atmosphere.request_event(&"room_camera_feed", true)
			"expire_room_camera":
				atmosphere.residents.room_camera_seconds_left = 0.01
				atmosphere.residents._process(0.02)
			"firewall": _last_request = atmosphere.request_event(&"firewall_breach", true)
			"cancel": atmosphere.cancel()
			"return": enter_computer()
			"wall", "away", "peripheral": _aim(str(command.name))
			"threat": _last_request = trigger_neighbor()
			"disable_threats": disable_threats()
			"quiz":
				shift.state = ShiftDirector.State.REPORT
				shift._process(0)
	var resident: AtmosphereResidents = atmosphere.residents
	if is_instance_valid(resident.figure) and resident.figure.get_instance_id() != _tracked_figure_id:
		_tracked_figure_id = resident.figure.get_instance_id()
		resident.figure.dismissed.connect(func(reason: StringName): _last_figure_reason = reason)
	var question := resident.question
	var rect := question.get_global_rect() if is_instance_valid(question) else Rect2()
	var close_point := question.close_button.get_global_rect().get_center() if is_instance_valid(question) else Vector2.ZERO
	var buttons: Dictionary = {}
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text in ["TriggerQuestionPopup", "TriggerBathroomApparition", "TriggerRoomCamera", "TriggerFirewallBreach"]:
			var at := button.get_global_rect().get_center()
			buttons[button.text] = [at.x, at.y]
	var point: Vector3 = get_node("Apartment/BathroomApparitionPoint").global_position + Vector3.UP * 1.3
	var projected := get_viewport().get_camera_3d().unproject_position(point)
	var area := terminal_ui.workspace.get_global_rect()
	var room_camera := resident.room_camera
	var camera_rect := room_camera.get_global_rect() if is_instance_valid(room_camera) else Rect2()
	var camera_close := room_camera.close_button.get_global_rect().get_center() if is_instance_valid(room_camera) else Vector2.ZERO
	var camera_source := resident.room_camera_source
	var camera_pose := [camera_source.global_position.x, camera_source.global_position.y, camera_source.global_position.z, camera_source.global_rotation.x, camera_source.global_rotation.y, camera_source.global_rotation.z] if is_instance_valid(camera_source) else []
	var camera_has_bw_shader: bool = is_instance_valid(room_camera) and room_camera.feed.material is ShaderMaterial and room_camera.feed.material.shader.code.contains("luminance")
	var camera_has_audio: bool = is_instance_valid(room_camera) and (not room_camera.find_children("*", "AudioStreamPlayer", true, false).is_empty() or not room_camera.find_children("*", "AudioStreamPlayer3D", true, false).is_empty())
	var data := {"command": _command_id, "mode": int(mode), "dev": dev_menu.is_open,
		"buttons": buttons, "request": _last_request,
		"question": is_instance_valid(question), "key": String(question.question_key) if is_instance_valid(question) else "",
		"text": question.body.text if is_instance_valid(question) else "",
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"close": [close_point.x, close_point.y], "deck": resident.remaining_questions.size(),
		"figure": is_instance_valid(resident.figure), "figure_reason": String(_last_figure_reason),
		"audio": is_instance_valid(resident.figure) and is_instance_valid(resident.figure.audio),
		"projected": [projected.x, projected.y], "busy": atmosphere.is_busy(),
		"notes": terminal_ui.notepad.editor.text, "app": String(terminal_ui.active_app),
		"modal": terminal_ui.has_modal(), "area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"room_camera": is_instance_valid(room_camera),
		"room_camera_rect": [camera_rect.position.x, camera_rect.position.y, camera_rect.size.x, camera_rect.size.y],
		"room_camera_close": [camera_close.x, camera_close.y],
		"room_camera_seconds": resident.room_camera_seconds_left,
		"room_camera_pose": camera_pose,
		"room_camera_title": room_camera.title_label.text if is_instance_valid(room_camera) else "",
		"room_camera_bw": camera_has_bw_shader,
		"room_camera_audio": camera_has_audio,
		"room_camera_override": is_instance_valid(visual_effects._room_camera_source),
		"room_camera_rendering": visual_effects.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"room_camera_order": resident.question_overlay.get_children().find(room_camera) if is_instance_valid(room_camera) else -1,
		"quiz": terminal_ui.chat.session.quiz_started}
	JavaScriptBridge.eval("window.residentsTelemetry = " + JSON.stringify(data))
