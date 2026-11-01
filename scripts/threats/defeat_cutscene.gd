class_name DefeatCutscene
extends Node3D
## Seekable choreography anchored to the actual capture; standalone preview retained.
signal finished
signal cue_reached(cue: StringName)
enum Kind { POLICE, NEIGHBOR, ENTITY }
@export var kind: Kind = Kind.POLICE
@export_range(5.0, 7.0) var duration_seconds: float = 6.4
@export var autoplay: bool = true
@export var model_scene: PackedScene = preload("res://assets/models/GuyRig.glb")
## Assign existing/designer WAVs by cue name. Empty by default: no generated sound.
@export var cue_sounds: Dictionary[StringName, AudioStream] = {}
var elapsed: float = 0.0
var completed: bool = false
var staged: bool = false
var _timeline: AnimationPlayer
var _cues: Dictionary = {}
var _emitted: Dictionary = {}
var _fade: ColorRect
var _audio: AudioStreamPlayer
var jumpscare_audio: AudioStreamPlayer
var on_location: bool = false
var _capture_eye: Vector3
var _capture_floor: Vector3
var _excluded: Array[RID] = []
var _source: Node3D
@onready var view: Camera3D = $View
@onready var actor: DefeatActor = $Actor


func _enter_tree() -> void:
	get_node("Actor").model_scene = model_scene


func _ready() -> void:
	_timeline = AnimationPlayer.new()
	_timeline.name = "Choreography"
	add_child(_timeline)
	var library := AnimationLibrary.new()
	var motion := Animation.new()
	motion.length = duration_seconds
	_timeline.root_node = NodePath("..")
	match kind:
		Kind.POLICE: _police(motion)
		Kind.NEIGHBOR: _neighbor(motion)
		Kind.ENTITY: _entity(motion)
	library.add_animation(&"defeat", motion)
	_timeline.add_animation_library(&"", library)
	_timeline.play(&"defeat")
	_timeline.pause()
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"SFX"
	add_child(_audio)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seek(0.0)
	jumpscare_audio = AudioStreamPlayer.new()
	jumpscare_audio.name = "JumpscareAudio"
	jumpscare_audio.bus = &"SFX"
	jumpscare_audio.volume_db = -6.0
	jumpscare_audio.stream = preload("res://assets/audio/jumpscare.wav")
	add_child(jumpscare_audio)
	jumpscare_audio.play()


func place_at_capture(camera: Camera3D, enemy: Node3D, player: CharacterBody3D) -> void:
	on_location = true
	_source = enemy
	_capture_eye = camera.global_position
	_capture_floor = Vector3(_capture_eye.x, player.global_position.y, _capture_eye.z)
	_excluded = [player.get_rid()]
	var forward := enemy.global_position - _capture_floor
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -camera.global_basis.z
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	global_basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	# Authored camera starts at z=1.15; map that point to the capture eye.
	global_position = _capture_floor - global_basis * Vector3(0, 0, 1.15)
	for node_name: String in ["Floor", "BackWall", "Door", "Ceiling"]:
		get_node(node_name).hide()
	view.environment = null
	view.far = camera.far
	# Small local fill keeps the attack readable even during a power outage.
	$KeyLight.light_energy = 0.55
	$KeyLight.omni_range = 2.5
	$FillLight.hide()
	seek(elapsed)


func _process(delta: float) -> void:
	if autoplay:
		advance(delta)


func advance(delta: float) -> void:
	if completed or delta < 0:
		return
	seek(minf(duration_seconds, elapsed + delta))
	for cue: StringName in _cues:
		if elapsed >= float(_cues[cue]) and not _emitted.has(cue):
			_emitted[cue] = true
			cue_reached.emit(cue)
			var stream: AudioStream = cue_sounds.get(cue)
			if stream != null:
				_audio.stream = stream
				_audio.play()
	if elapsed >= duration_seconds:
		completed = true
		if autoplay:
			# F6 preview holds the last pose; the game instead shows its result UI.
			_fade.hide()
		finished.emit()


func seek(seconds: float) -> void:
	elapsed = clampf(seconds, 0.0, duration_seconds)
	_timeline.seek(elapsed, true)
	if on_location:
		_constrain_to_room()
		actor.visible = elapsed >= 0.4
		$KeyLight.visible = elapsed >= 0.4
		if is_instance_valid(_source):
			_source.visible = elapsed < 0.4
	actor.apply_pose()
	# First show the real attacker. Switch cameras only while fully black.
	if elapsed >= 0.4:
		staged = true
		view.make_current()
	var alpha := 0.0
	if elapsed < 0.4:
		alpha = clampf((elapsed - 0.12) / 0.25, 0, 1)
	elif elapsed < 0.7:
		alpha = 1.0 - clampf((elapsed - 0.45) / 0.25, 0, 1)
	if elapsed > duration_seconds - 0.4:
		alpha = maxf(alpha, (elapsed - duration_seconds + 0.4) / 0.4)
	# Brief dark impact accents, never flashing white or persistent shaking.
	if kind == Kind.NEIGHBOR:
		for impact: float in [1.7, 2.65, 3.65]:
			alpha = maxf(alpha, maxf(0, 1.0 - absf(elapsed - impact) / 0.065) * 0.7)
	_fade.color.a = alpha


func _constrain_to_room() -> void:
	var initial_height := 1.67 if kind == Kind.ENTITY else 1.58
	view.position.y += _capture_eye.y - _capture_floor.y - initial_height
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.08
	view.global_position = _safe_motion(_capture_eye, view.global_position, camera_shape)
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.24
	body_shape.height = 1.7
	var body_center := Vector3.UP * 0.92
	var target := Vector3(actor.global_position.x, _capture_floor.y, actor.global_position.z)
	var safe := _safe_motion(_capture_floor + body_center, target + body_center, body_shape)
	actor.global_position = Vector3(safe.x, actor.global_position.y, safe.z)


func _safe_motion(from: Vector3, target: Vector3, shape: Shape3D) -> Vector3:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = from
	query.motion = target - from
	query.collision_mask = 1
	query.exclude = _excluded
	var space := get_world_3d().direct_space_state
	# If the initial pose already touches furniture, hold rather than cross it.
	if not space.intersect_shape(query).is_empty():
		return from
	var fraction := space.cast_motion(query)[0]
	return from.lerp(target, maxf(0.0, fraction - 0.01)) if fraction < 1.0 else target


func _track(animation: Animation, path: String, times: Array, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for index: int in times.size():
		animation.track_insert_key(track, times[index], values[index])


func _police(animation: Animation) -> void:
	_cues = {&"grab": 0.8, &"fall": 1.25, &"floor_impact": 1.8, &"pin": 2.6, &"hold": 4.0}
	_track(animation, "Actor:position", [0, 0.7, 0.84, 1.15, 1.5, 2.3, 2.6, 4.0, 6.4],
		[Vector3(0, 0, -0.5), Vector3(0, 0, -0.5), Vector3(0.06, 0, 0.25), Vector3(0.06, 0, 0.25), Vector3(0, -0.2, 0.4), Vector3(0, -0.5, 0.38), Vector3(0, -0.55, 0.38), Vector3(0, -0.55, 0.38), Vector3(0, -0.55, 0.38)])
	_track(animation, "Actor:body_angles", [0, 0.7, 0.84, 1.2, 2.3, 2.6, 4.0, 4.08, 4.2, 6.4],
		[Vector3.ZERO, Vector3.ZERO, Vector3(-12, 0, -4), Vector3(-12, 0, -4), Vector3(-36, 0, 0), Vector3(-42, 0, 0), Vector3(-42, 0, 0), Vector3(-45, 2, -2), Vector3(-42, 0, 0), Vector3(-42, 0, 0)])
	_track(animation, "Actor:kneel", [0, 1.4, 2.3, 6.4], [0.0, 0.0, 1.0, 1.0])
	_track(animation, "Actor:arm_pole_height", [0, 2.2, 2.6, 6.4], [-0.6, -0.6, 0.8, 0.8])
	_track(animation, "Actor:left_wrist", [0, 0.7, 0.84, 1.2, 2.5, 2.65, 6.4],
		[Vector3(0.24, 1.02, -0.08), Vector3(0.24, 1.02, -0.08), Vector3(0.17, 1.5, -0.43), Vector3(0.17, 1.5, -0.43), Vector3(0.24, 1.2, -0.6), Vector3(0.24, 1.0, -0.62), Vector3(0.24, 1.0, -0.62)])
	_track(animation, "Actor:right_wrist", [0, 0.72, 0.87, 1.2, 2.5, 2.65, 6.4],
		[Vector3(-0.24, 1.02, -0.08), Vector3(-0.24, 1.02, -0.08), Vector3(-0.17, 1.48, -0.43), Vector3(-0.17, 1.48, -0.43), Vector3(-0.24, 1.2, -0.6), Vector3(-0.24, 1.0, -0.62), Vector3(-0.24, 1.0, -0.62)])
	_track(animation, "Actor:head_angles", [0, 0.8, 1.0, 2.5, 2.6, 4.0, 4.08, 4.25, 6.4],
		[Vector3.ZERO, Vector3.ZERO, Vector3(-8, -8, 3), Vector3(-8, -8, 3), Vector3(-16, 0, 0), Vector3(-16, 0, 0), Vector3(-19, 5, -4), Vector3(-16, 0, 0), Vector3(-16, 0, 0)])
	_track(animation, "View:position", [0, 1.15, 1.24, 1.48, 1.79, 1.82, 1.96, 2.6, 6.4],
		[Vector3(0, 1.58, 1.15), Vector3(0, 1.58, 1.15), Vector3(0.06, 1.62, 1.17), Vector3(-0.05, 0.8, 1.35), Vector3(0, 0.24, 1.4), Vector3(0.025, 0.16, 1.4), Vector3(0, 0.2, 1.4), Vector3(0, 0.2, 1.2), Vector3(0, 0.2, 1.2)])
	_track(animation, "View:rotation_degrees", [0, 1.15, 1.24, 1.48, 1.79, 1.82, 1.96, 2.6, 6.4],
		[Vector3.ZERO, Vector3.ZERO, Vector3(6, -3, -7), Vector3(43, 0, 9), Vector3(68, 0, -5), Vector3(72, 0, 5), Vector3(66, 0, 2), Vector3(58, 0, 0), Vector3(58, 0, 0)])
	_track(animation, "View:fov", [0, 1.2, 1.8, 2.6, 6.4], [68.0, 68.0, 76.0, 68.0, 68.0])


func _neighbor(animation: Animation) -> void:
	_cues = {&"approach": 0.65, &"windup": 1.3, &"hit_1": 1.7, &"hit_2": 2.65, &"hit_3": 3.65, &"loom": 4.4}
	_track(animation, "Actor:position", [0, 0.8, 1.05, 1.3, 1.65, 1.72, 2.6, 2.68, 3.6, 3.7, 4.4, 6.2],
		[Vector3(0, 0, -0.9), Vector3(0, 0, -0.9), Vector3(0.12, 0, 0.1), Vector3(0.12, 0, 0.1), Vector3(0.12, 0, 0.1), Vector3(-0.06, 0, 0.45), Vector3(-0.06, 0, 0.45), Vector3(0.08, 0, 0.5), Vector3(0.08, 0, 0.5), Vector3(-0.08, 0, 0.5), Vector3(0, -0.25, 0.6), Vector3(0, -0.25, 0.6)])
	_track(animation, "Actor:body_angles", [0, 1.25, 1.45, 1.68, 1.74, 2.3, 2.61, 2.7, 3.3, 3.61, 3.7, 4.4, 6.2],
		[Vector3(-5, 0, 4), Vector3(-5, 0, 4), Vector3(5, -24, -8), Vector3(5, -24, -8), Vector3(-15, 18, 5), Vector3(0, 24, 8), Vector3(0, 24, 8), Vector3(-20, -18, -7), Vector3(8, -20, -4), Vector3(8, -20, -4), Vector3(-24, 10, 4), Vector3(-35, 0, 0), Vector3(-35, 0, 0)])
	_track(animation, "Actor:left_wrist", [0, 1.3, 1.45, 1.65, 1.72, 1.9, 3.25, 3.4, 3.62, 3.69, 4.4, 6.2],
		[Vector3(0.25, 1.05, -0.1), Vector3(0.25, 1.05, -0.1), Vector3(0.35, 1.72, 0.1), Vector3(0.35, 1.72, 0.1), Vector3(0.04, 1.6, -0.48), Vector3(0.25, 1.3, -0.15), Vector3(0.25, 1.3, -0.15), Vector3(0.25, 1.8, 0.12), Vector3(0.25, 1.8, 0.12), Vector3(0.0, 1.5, -0.49), Vector3(0.2, 1.05, -0.35), Vector3(0.2, 1.05, -0.35)])
	_track(animation, "Actor:right_wrist", [0, 2.15, 2.35, 2.6, 2.68, 2.9, 4.4, 6.2],
		[Vector3(-0.25, 1.1, -0.1), Vector3(-0.25, 1.1, -0.1), Vector3(-0.32, 1.75, 0.12), Vector3(-0.32, 1.75, 0.12), Vector3(0.03, 1.58, -0.48), Vector3(-0.23, 1.35, -0.1), Vector3(-0.2, 1.05, -0.35), Vector3(-0.2, 1.05, -0.35)])
	_track(animation, "Actor:head_angles", [0, 1.1, 1.2, 2.0, 2.1, 3.1, 3.2, 4.4, 6.2],
		[Vector3(0, 0, 13), Vector3(0, 0, 13), Vector3(-9, 10, -8), Vector3(-9, 10, -8), Vector3(-12, -12, 9), Vector3(-12, -12, 9), Vector3(-4, 14, -13), Vector3(-15, 0, 5), Vector3(-15, 0, 5)])
	_track(animation, "View:position", [0, 1.65, 1.72, 1.9, 2.6, 2.68, 2.9, 3.6, 3.7, 4.4, 6.2],
		[Vector3(0, 1.58, 1.15), Vector3(0, 1.58, 1.15), Vector3(-0.1, 1.5, 1.24), Vector3(0, 1.48, 1.2), Vector3(0, 1.48, 1.2), Vector3(0.1, 1.33, 1.3), Vector3(0, 1.38, 1.25), Vector3(0, 1.38, 1.25), Vector3(-0.08, 0.9, 1.4), Vector3(0, 0.65, 1.4), Vector3(0, 0.65, 1.4)])
	_track(animation, "View:rotation_degrees", [0, 1.65, 1.72, 1.95, 2.6, 2.68, 2.95, 3.6, 3.7, 4.4, 6.2],
		[Vector3.ZERO, Vector3.ZERO, Vector3(-8, -9, 12), Vector3(0, -2, 3), Vector3(0, -2, 3), Vector3(-11, 10, -12), Vector3(4, 0, -3), Vector3(4, 0, -3), Vector3(17, -4, 13), Vector3(52, 0, 6), Vector3(52, 0, 6)])
	_track(animation, "View:fov", [0, 1.65, 1.72, 2.0, 4.4, 6.2], [68.0, 68.0, 76.0, 68.0, 64.0, 64.0])


func _entity(animation: Animation) -> void:
	_cues = {&"freeze": 0.65, &"lurch_1": 1.45, &"lurch_2": 2.25, &"face": 2.85, &"twitch": 4.6}
	_track(animation, "Actor:position", [0, 1.4, 1.48, 2.2, 2.27, 2.8, 2.87, 4.55, 4.62, 4.8, 6.4],
		[Vector3(0, 0, -1.2), Vector3(0, 0, -1.2), Vector3(0.13, 0, -0.2), Vector3(0.13, 0, -0.2), Vector3(-0.08, 0, 0.4), Vector3(-0.08, 0, 0.4), Vector3(0, 0, 0.86), Vector3(0, 0, 0.86), Vector3(0.025, 0.01, 0.88), Vector3(0, 0, 0.86), Vector3(0, 0, 0.86)])
	_track(animation, "Actor:body_angles", [0, 1.4, 1.48, 2.2, 2.27, 2.8, 2.87, 6.4],
		[Vector3(-4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 8, -8), Vector3(0, 8, -8), Vector3(0, -5, 5), Vector3(0, -5, 5), Vector3.ZERO, Vector3.ZERO])
	_track(animation, "Actor:head_angles", [0, 1.4, 1.48, 2.2, 2.27, 2.8, 2.87, 3.7, 3.74, 4.55, 4.62, 4.8, 6.4],
		[Vector3(0, 0, 18), Vector3(0, 0, 18), Vector3(-6, 14, -20), Vector3(-6, 14, -20), Vector3(7, -10, 14), Vector3(7, -10, 14), Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1, -3, -4), Vector3(1, -3, -4), Vector3(-3, 3, 5), Vector3(0, 0, 0), Vector3(0, 0, 0)])
	_track(animation, "Actor:left_wrist", [0, 1.45, 2.25, 2.85, 6.4],
		[Vector3(0.3, 0.98, -0.12), Vector3(0.3, 0.98, -0.12), Vector3(0.36, 1.6, -0.23), Vector3(0.33, 1.56, -0.35), Vector3(0.33, 1.56, -0.35)])
	_track(animation, "Actor:right_wrist", [0, 1.45, 2.25, 2.85, 6.4],
		[Vector3(-0.3, 0.98, -0.12), Vector3(-0.3, 0.98, -0.12), Vector3(-0.36, 1.6, -0.23), Vector3(-0.33, 1.56, -0.35), Vector3(-0.33, 1.56, -0.35)])
	_track(animation, "View:position", [0, 2.8, 2.87, 3.0, 4.55, 4.62, 4.8, 6.4],
		[Vector3(0, 1.67, 1.15), Vector3(0, 1.67, 1.15), Vector3(0.025, 1.68, 1.18), Vector3(0, 1.67, 1.15), Vector3(0, 1.67, 1.15), Vector3(-0.012, 1.675, 1.16), Vector3(0, 1.67, 1.15), Vector3(0, 1.67, 1.15)])
	_track(animation, "View:rotation_degrees", [0, 2.8, 2.87, 3.0, 6.4], [Vector3.ZERO, Vector3.ZERO, Vector3(1, -2, 3), Vector3.ZERO, Vector3.ZERO])
	_track(animation, "View:fov", [0, 2.8, 2.87, 3.1, 6.4], [64.0, 64.0, 72.0, 64.0, 64.0])
