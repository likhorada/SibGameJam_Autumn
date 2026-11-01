class_name AtmosphereResidents
extends Node
## Run-local objects outlive their instant spawn event, never the run itself.
const DECK := preload("res://data/atmosphere/questions.gd")
const QUESTION := preload("res://scripts/atmosphere/question_popup.gd")
const FIGURE := preload("res://scripts/atmosphere/bathroom_apparition.gd")
const ROOM_CAMERA := preload("res://scripts/ui/desktop/room_camera_popup.gd")
const ROOM_CAMERA_SECONDS := 20.0
@export var bathroom_settings: BathroomApparitionConfig = preload("res://data/atmosphere/bathroom_settings.tres")
var game: Node3D
var director: AtmosphereDirector
var question: QuestionPopup
var figure: BathroomApparition
var room_camera: RoomCameraPopup
var room_camera_seconds_left: float = 0.0
var room_camera_source: Camera3D
var question_overlay: Control
var remaining_questions: Array[StringName] = []
var _rng := RandomNumberGenerator.new()
var _placement_checked: bool = false
var _placement_visible: bool = true
var _camera_pose := Transform3D.IDENTITY
var _camera_fov: float = 0.0
var _camera_view_size := Vector2.ZERO
var _placement_pose := Transform3D.IDENTITY


func bind(value: Node3D, owner_director: AtmosphereDirector) -> void:
	game = value
	director = owner_director
	_rng = RunRandom.generator(game.run_seed, &"residents")
	remaining_questions.assign(DECK.KEYS)
	question_overlay = Control.new()
	question_overlay.name = "ResidentQuestions"
	question_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.terminal_ui.workspace.add_child(question_overlay)
	question_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	question_overlay.resized.connect(_fit_question)
	question_overlay.resized.connect(_fit_room_camera)
	game.terminal_ui.resident_overlay = question_overlay
	room_camera_source = game.get_node_or_null("Apartment/RoomCamera") as Camera3D
	if is_instance_valid(room_camera_source):
		room_camera_source.current = false
		room_camera_source.look_at(game.get_node("Apartment/PoliceRoute/MainRoom").global_position + Vector3.UP * 0.9, Vector3.UP)
		room_camera_source.fov = 88.0
	director.set_event_condition(&"question_popup", can_show_question)
	director.set_event_condition(&"bathroom_apparition", can_place_figure)
	director.set_event_condition(&"room_camera_feed", can_show_room_camera)
	director.event_started.connect(_on_event_started)
	game.threats.state_changed.connect(_on_threat_state)


func can_show_question() -> bool:
	return not is_instance_valid(question) and not remaining_questions.is_empty() and not game.terminal_ui.has_modal()


func show_question() -> bool:
	if not can_show_question() or game.mode != game.Mode.COMPUTER:
		return false
	var key := remaining_questions[_rng.randi_range(0, remaining_questions.size() - 1)]
	question = QUESTION.new()
	question.question_key = key
	question_overlay.add_child(question)
	question.fit_to_area(question_overlay.size)
	question.position = ((question_overlay.size - question.size) * Vector2(0.5, 0.4)).max(Vector2.ZERO)
	question.dismissed.connect(clear_question.bind(&"closed"))
	remaining_questions.erase(key)
	director.note("Question shown: " + String(key))
	return true


func _fit_question() -> void:
	if is_instance_valid(question):
		question.fit_to_area(question_overlay.size)


func clear_question(reason: StringName) -> void:
	if not is_instance_valid(question):
		return
	var current := question
	question = null
	current.hide()
	current.cancel_gesture()
	current.queue_free()
	director.note("Question removed: " + String(reason))


func can_place_figure() -> bool:
	if is_instance_valid(figure) or bathroom_settings == null or bathroom_settings.visual_scene == null or game.get_node_or_null("Apartment/BathroomApparitionPoint") == null:
		return false
	if game.mode == game.Mode.COMPUTER:
		return true
	var camera := game.get_viewport().get_camera_3d()
	var point := game.get_node("Apartment/BathroomApparitionPoint") as Node3D
	if camera != null and not BathroomApparition.in_frustum(camera, point.global_transform):
		# Bob/movement may change after physics. A currently off-screen spot is safe
		# without querying physics from input/process or requiring the player to stop.
		return true
	return _placement_checked and camera != null and _camera_pose.is_equal_approx(camera.global_transform) and is_equal_approx(_camera_fov, camera.fov) and _camera_view_size == camera.get_viewport().get_visible_rect().size and _placement_pose.is_equal_approx(point.global_transform) and not _placement_visible


func place_figure() -> bool:
	if not can_place_figure():
		return false
	figure = FIGURE.new()
	figure.game = game
	figure.settings = bathroom_settings
	add_child(figure)
	figure.global_transform = game.get_node("Apartment/BathroomApparitionPoint").global_transform
	figure.dismissed.connect(_on_figure_dismissed)
	figure.seen.connect(director.confirm_seen.bind(&"bathroom_apparition"))
	director.note("Bathroom apparition placed; slot released")
	return true


func _on_figure_dismissed(reason: StringName) -> void:
	figure = null
	if reason == &"threat_started":
		director.release_unseen(&"bathroom_apparition")
	director.note("Bathroom apparition removed: " + String(reason))


func clear_figure(reason: StringName) -> void:
	if is_instance_valid(figure):
		figure.dismiss(reason)


func can_show_room_camera() -> bool:
	return not is_instance_valid(room_camera) and is_instance_valid(room_camera_source) and not game.terminal_ui.has_modal()


func show_room_camera() -> bool:
	if game.mode != game.Mode.COMPUTER or not can_show_room_camera():
		return false
	room_camera = ROOM_CAMERA.new()
	room_camera.feed_texture = game.visual_effects.viewport.get_texture()
	question_overlay.add_child(room_camera)
	room_camera.fit_to_area(question_overlay.size)
	room_camera.position = ((question_overlay.size - room_camera.size) * Vector2(0.5, 0.36)).max(Vector2.ZERO)
	room_camera.dismissed.connect(_on_room_camera_dismissed)
	room_camera_seconds_left = ROOM_CAMERA_SECONDS
	game.visual_effects.set_room_camera_source(room_camera_source)
	director.note("Room camera shown; 20-second timer started")
	return true


func _fit_room_camera() -> void:
	if is_instance_valid(room_camera):
		room_camera.fit_to_area(question_overlay.size)


func _on_room_camera_dismissed(reason: StringName) -> void:
	if not is_instance_valid(room_camera):
		return
	var current := room_camera
	room_camera = null
	room_camera_seconds_left = 0.0
	game.visual_effects.set_room_camera_source(null)
	current.queue_free()
	director.note("Room camera removed: " + String(reason))


func clear_room_camera(reason: StringName) -> void:
	if is_instance_valid(room_camera):
		room_camera.dismiss(reason)


func clear_all(reason: StringName) -> void:
	clear_question(reason)
	clear_figure(reason)
	clear_room_camera(reason)


func _on_event_started(id: StringName) -> void:
	if id == &"firewall_breach":
		clear_question(&"firewall_breach")


func _on_threat_state(state: ThreatManager.State, _id: StringName) -> void:
	if state == ThreatManager.State.WARNING:
		clear_figure(&"threat_started")


func _physics_process(_delta: float) -> void:
	var camera := game.get_viewport().get_camera_3d()
	var point := game.get_node_or_null("Apartment/BathroomApparitionPoint") as Node3D
	if camera == null or point == null:
		_placement_checked = false
		return
	_camera_pose = camera.global_transform
	_camera_fov = camera.fov
	_camera_view_size = camera.get_viewport().get_visible_rect().size
	_placement_pose = point.global_transform
	# Even while dev UI covers the world, forbid materializing into its camera view.
	_placement_visible = game.mode != game.Mode.COMPUTER and BathroomApparition.placement_visible(game, point.global_transform)
	_placement_checked = true


func _process(_delta: float) -> void:
	if game.run_ended or not game.capture_reason.is_empty() or game.terminal_ui.chat.session.quiz_started:
		clear_all(&"run ended / quiz")
	elif is_instance_valid(room_camera):
		room_camera_seconds_left = maxf(0.0, room_camera_seconds_left - _delta)
		if room_camera_seconds_left <= 0.0:
			clear_room_camera(&"timeout")


func debug_status() -> String:
	return "Residents: question %s; deck %d/12; bathroom %s; room camera %s (%.1fs)" % [str(question.question_key) if is_instance_valid(question) else "—", remaining_questions.size(), "present" if is_instance_valid(figure) else "—", "present" if is_instance_valid(room_camera) else "—", room_camera_seconds_left]


func _exit_tree() -> void:
	clear_all(&"teardown")
	if is_instance_valid(game) and is_instance_valid(game.terminal_ui) and game.terminal_ui.resident_overlay == question_overlay:
		game.terminal_ui.resident_overlay = null
	if is_instance_valid(question_overlay):
		question_overlay.queue_free()
