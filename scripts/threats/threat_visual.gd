class_name ThreatVisual
extends "res://scripts/threats/defeat_actor.gd"
## Presentation only: actual world displacement drives gait, never the enemy route.
enum Style { POLICE, NEIGHBOR, ENTITY }
@export var style: Style = Style.POLICE
var gait_phase: float = 0.0
var gait_weight: float = 0.0
var _last_position: Vector3
var _was_visible: bool = false
@onready var head: Node3D = $Head


func _ready() -> void:
	super._ready()
	# The route/sight API faces -Z, while the imported textured face points +Z.
	model.rotation.y = PI
	_last_position = global_position
	apply_pose()


func _process(delta: float) -> void:
	var current := is_visible_in_tree()
	var distance := Vector2(global_position.x - _last_position.x, global_position.z - _last_position.z).length()
	_last_position = global_position
	if not current or not _was_visible or distance > maxf(0.5, delta * 8.0):
		gait_phase = 0.0
		gait_weight = 0.0
	elif delta > 0.0:
		var moving := distance / delta > 0.03
		gait_weight = move_toward(gait_weight, 1.0 if moving else 0.0, delta * 10.0)
		gait_phase = fposmod(gait_phase + distance * TAU / 1.15, TAU)
	_was_visible = current
	if current:
		apply_pose()


func apply_pose() -> void:
	if skeleton == null:
		return
	var swing := sin(gait_phase) * gait_weight
	var nervous := style == Style.NEIGHBOR
	body_angles = Vector3(-5, 0, 2) if nervous else Vector3(-3, 0, 0) if style == Style.ENTITY else Vector3.ZERO
	# Preserve the Head marker contract used by VisitorPressure, but turn real bones.
	head_angles = Vector3(head.rotation.x, -head.rotation.y, -head.rotation.z) * 180.0 / PI
	left_wrist = Vector3(0.29, 0.84, -0.04 - swing * 0.13)
	right_wrist = Vector3(-0.29, 0.84, -0.04 + swing * 0.13)
	if style == Style.ENTITY:
		left_wrist.z -= 0.12
		right_wrist.z -= 0.12
	super.apply_pose()
	for side: String in ["L", "R"]:
		var phase := gait_phase if side == "L" else gait_phase + PI
		var stride := sin(phase)
		_pose_leg(side, stride * gait_weight * 0.34, maxf(0.0, -stride) * gait_weight * 0.5)
	model.position.y = absf(sin(gait_phase * 2.0)) * gait_weight * 0.012
	skeleton.force_update_all_bone_transforms()


func _pose_leg(side: String, swing: float, bend: float) -> void:
	var thigh := "DEF-thigh." + side
	var shin := "DEF-shin." + side
	if not _rests.has(thigh) or not _rests.has(shin):
		return
	var hip: Vector3 = (_rests[thigh] as Transform3D).origin
	var turn := Basis(Vector3.RIGHT, swing)
	var upper := Transform3D(turn, hip - turn * hip)
	_follow(thigh, upper)
	_follow(thigh + ".001", upper)
	var knee: Vector3 = upper * (_rests[shin] as Transform3D).origin
	var knee_turn := Basis(Vector3.RIGHT, bend)
	var lower := Transform3D(knee_turn, knee - knee_turn * knee) * upper
	_follow(shin, lower)
	_follow(shin + ".001", lower)
	_follow("DEF-foot." + side, lower)
	_follow("DEF-toe." + side, lower)
