class_name BathroomApparition
extends Node3D
## A decoration, not an enemy. No collision, AI, capture, proximity pulse or damage.
signal dismissed(reason: StringName)
const SEEN_HOLD_SECONDS: float = 0.5
const SAMPLES: Array[Vector3] = [
	Vector3(0, 1.65, 0), Vector3(0, 1.3, 0),
	Vector3(-0.22, 1.4, 0), Vector3(0.22, 1.4, 0),
	Vector3(-0.27, 0.95, 0), Vector3(0.27, 0.95, 0),
	Vector3(0, 0.8, 0), Vector3(-0.12, 0.3, 0), Vector3(0.12, 0.3, 0),
]
var game: Node3D
var settings: BathroomApparitionConfig
var visual: Node3D
var audio: AudioStreamPlayer3D
var visible_in_physics: bool = false
var _ended: bool = false
var _visible_points: Array[Vector3] = []
var _sample_origin := Vector3.ZERO
var seen_seconds_left: float = -1.0


func _ready() -> void:
	visual = settings.visual_scene.instantiate()
	add_child(visual)
	visual.show()
	# Reuse only the pose/model. Freeze presentation animation on this instance.
	visual.set_process(false)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.018, 0.022, 0.02)
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = dark
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for collision: CollisionObject3D in visual.find_children("*", "CollisionObject3D", true, false):
		collision.collision_layer = 0
		collision.collision_mask = 0
	if settings.loop_sound != null:
		audio = AudioStreamPlayer3D.new()
		audio.stream = settings.loop_sound
		audio.bus = &"SFX"
		audio.volume_db = settings.volume_db
		audio.max_db = settings.volume_db
		audio.unit_size = 2.5
		audio.max_distance = 18.0
		add_child(audio)
		audio.position.y = 1.2
		audio.finished.connect(_repeat_sound)
		audio.play()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


static func world_view_visible(game_node: Node3D) -> bool:
	return not game_node.run_ended and game_node.capture_reason.is_empty() and game_node.mode != game_node.Mode.COMPUTER and not game_node.dev_menu.is_open and game_node._focus_active


static func placement_visible(game_node: Node3D, pose: Transform3D) -> bool:
	# Call only from physics. The logical apartment camera drives the rendered proxy.
	var camera := game_node.get_viewport().get_camera_3d()
	if camera == null:
		return false
	for sample: Vector3 in SAMPLES:
		var target := pose * sample
		if camera.is_position_in_frustum(target) and ThreatAwareness.clear_line(game_node, camera.global_position, target):
			return true
	return false


static func in_frustum(camera: Camera3D, pose: Transform3D) -> bool:
	for sample: Vector3 in SAMPLES:
		if camera.is_position_in_frustum(pose * sample):
			return true
	return false


func _physics_process(delta: float) -> void:
	visible_in_physics = false
	_visible_points.clear()
	if _ended:
		return
	if seen_seconds_left >= 0.0:
		seen_seconds_left = maxf(0.0, seen_seconds_left - maxf(0.0, delta))
		if seen_seconds_left <= 0.0:
			dismiss(&"seen")
		return
	if not world_view_visible(game):
		return
	var camera := game.get_viewport().get_camera_3d()
	if camera == null:
		return
	_sample_origin = camera.global_position
	for sample: Vector3 in SAMPLES:
		var target := global_transform * sample
		if camera.is_position_in_frustum(target) and ThreatAwareness.clear_line(game, _sample_origin, target):
			_visible_points.append(target)
	visible_in_physics = not _visible_points.is_empty()


func _on_frame_post_draw() -> void:
	# Never remove before the first real apartment frame that actually presented it.
	if _ended or seen_seconds_left >= 0.0:
		return
	if visible_in_physics and world_view_visible(game) and visual.is_visible_in_tree() and game.visual_effects.viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		var camera := game.get_viewport().get_camera_3d()
		# Mouse smoothing/tweens may change the camera after the physics sample.
		if camera == null or camera.global_position.distance_squared_to(_sample_origin) > 0.01:
			return
		for target: Vector3 in _visible_points:
			if camera.is_position_in_frustum(target):
				seen_seconds_left = SEEN_HOLD_SECONDS
				return


func _repeat_sound() -> void:
	if not _ended and is_instance_valid(audio):
		audio.play()


func dismiss(reason: StringName) -> void:
	if _ended:
		return
	_ended = true
	visible_in_physics = false
	hide()
	if is_instance_valid(audio):
		audio.stop()
	dismissed.emit(reason)
	queue_free()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	if is_instance_valid(audio):
		audio.stop()
