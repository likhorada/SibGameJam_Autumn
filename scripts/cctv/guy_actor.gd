@tool
extends Node3D
## Shared baked skeletal animation; no Blender/IK dependency at runtime.

const CLIPS := preload("res://assets/animations/cctv_humanoid.res")
const MODELS := [preload("res://assets/models/GuyRig.glb"), preload("res://assets/models/DecoyGreen.glb"),
	preload("res://assets/models/DecoyRed.glb"), preload("res://assets/models/DecoyYellow.glb")]

@export_enum("Target", "Decoy Green", "Decoy Red", "Decoy Yellow") var appearance: int = 0
@export_enum("idle", "work") var initial_activity: String = "idle"
@export var phase_offset: float = 0.0

var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var activity: String = "idle"
var carrying: Node3D
var grip: BoneAttachment3D
var _previous_position := Vector3.ZERO
var _busy: float = 0.0
var _pending_item: Node3D
var _handoff: float = -1.0
var _release_parent: Node3D
var _release_point := Vector3.ZERO
var _heading: float = 0.0
var _grip_offset := Vector3.ZERO


func _ready() -> void:
	model = MODELS[appearance].instantiate()
	model.name = "Model"
	add_child(model, false, Node.INTERNAL_MODE_BACK)
	player = model.get_node("AnimationPlayer")
	skeleton = model.get_node("rig/Skeleton3D")
	player.add_animation_library(&"cctv", CLIPS)
	grip = BoneAttachment3D.new()
	grip.name = "DrinkGrip"
	grip.bone_name = "DEF-hand.R"
	skeleton.add_child(grip)
	_previous_position = global_position
	_heading = global_rotation.y
	_play(initial_activity, 0.0)
	player.seek(phase_offset, true)
	if Engine.is_editor_hint():
		player.pause()
		set_process(false)


func start_departure() -> void:
	_busy = CLIPS.get_animation(&"stand").length
	_play("stand", 0.12)


func pick_up(item: Node3D, grip_offset: Vector3 = Vector3.ZERO) -> void:
	_face(item.global_position)
	_grip_offset = grip_offset
	_pending_item = item
	_release_parent = null
	_start_reach()


func put_down(destination: Node3D, point: Vector3) -> void:
	_face(destination.to_global(point))
	_release_parent = destination
	_release_point = point
	_start_reach()


func hold_item(item: Node3D, grip_offset: Vector3 = Vector3.ZERO) -> void:
	carrying = item
	_grip_offset = grip_offset
	carrying.owner = null
	# During a location switch the old scene has already left the tree. No global
	# transform needs preserving: the wrist pose below supplies the new position.
	carrying.reparent(grip, false)
	# Follow position without inheriting the animated wrist rotation.
	carrying.top_level = true
	_update_carried_item()
	if _busy == 0.0:
		_play("carry_idle", 0.0)


func _start_reach() -> void:
	_busy = CLIPS.get_animation(&"reach").length
	_handoff = 0.45
	_play("reach", 0.12)


func _process(delta: float) -> void:
	var direction := global_position - _previous_position
	_previous_position = global_position
	advance_motion(delta, direction)


func advance_motion(delta: float, displacement: Vector3) -> void:
	displacement.y = 0.0
	var speed := displacement.length() / maxf(delta, 0.001)
	if speed > 0.025:
		_heading = atan2(displacement.x, displacement.z)
	global_rotation.y = lerp_angle(global_rotation.y, _heading, 1.0 - exp(-8.0 * delta))
	if _handoff >= 0.0:
		_handoff -= delta
		if _handoff < 0.0:
			if is_instance_valid(_pending_item):
				hold_item(_pending_item, _grip_offset)
				_pending_item = null
			elif is_instance_valid(carrying) and is_instance_valid(_release_parent):
				carrying.reparent(_release_parent)
				carrying.top_level = false
				carrying.position = _release_point
				carrying.rotation = Vector3.ZERO
				carrying = null
	_busy = maxf(0.0, _busy - delta)
	if _busy == 0.0 and not (initial_activity == "work" and activity == "work"):
		var clip := "walk" if speed > 0.025 else "idle"
		if is_instance_valid(carrying):
			clip = "carry_" + clip
		_play(clip)
		player.speed_scale = clampf(speed / 1.12, 0.18, 2.2) if speed > 0.025 else 1.0
	if is_instance_valid(carrying):
		_update_carried_item()


func _update_carried_item() -> void:
	carrying.global_basis = Basis.IDENTITY
	var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("DEF-hand.R"))
	carrying.global_position = skeleton.global_transform * wrist.origin + _grip_offset


func _play(clip: String, blend: float = 0.18) -> void:
	if activity == clip and player.is_playing():
		return
	activity = clip
	player.speed_scale = 1.0
	player.play(StringName("cctv/" + clip), blend)
	if clip.ends_with("walk"):
		player.seek(fmod(phase_offset, CLIPS.get_animation(StringName(clip)).length), true)


func _face(point: Vector3) -> void:
	var direction := point - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.0001:
		_heading = atan2(direction.x, direction.z)


func face_direction(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() > 0.0001:
		_heading = atan2(direction.x, direction.z)
