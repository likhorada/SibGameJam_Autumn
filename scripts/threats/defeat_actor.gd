class_name DefeatActor
extends Node3D
## Retextured GuyRig replacements need the same DEF bone names, not node paths.
@export var model_scene: PackedScene = preload("res://assets/models/GuyRig.glb")
@export var body_angles := Vector3.ZERO
@export var head_angles := Vector3.ZERO
@export var left_wrist := Vector3(0.24, 1.02, -0.08)
@export var right_wrist := Vector3(-0.24, 1.02, -0.08)
@export var arm_pole_height: float = -0.6
@export_range(0.0, 1.0) var kneel: float = 0.0
var skeleton: Skeleton3D
var model: Node3D
var _bones: Dictionary = {}
var _rests: Dictionary = {}


func _ready() -> void:
	model = model_scene.instantiate()
	add_child(model)
	for candidate: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		if candidate.find_bone("DEF-spine.006") >= 0:
			skeleton = candidate
			break
	for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		player.stop()
	if skeleton == null:
		push_error("Defeat actor needs GuyRig DEF bones")
		return
	for index: int in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		_bones[bone_name] = index
		_rests[bone_name] = skeleton.get_bone_global_rest(index)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		# Imported AABBs describe the T pose, not hands reaching towards the camera.
		mesh.extra_cull_margin = 3.0
	apply_pose()


func apply_pose() -> void:
	if skeleton == null:
		return
	var pivot := Vector3(0, 0.92, -0.05)
	# Choreography uses negative Z as forward; GuyRig's textured face is +Z.
	var bend := Basis.from_euler(Vector3(-body_angles.x, -body_angles.y, body_angles.z) * PI / 180.0)
	var body := Transform3D(bend, pivot - bend * pivot)
	for bone_name: String in ["DEF-pelvis.L", "DEF-pelvis.R", "DEF-breast.L", "DEF-breast.R", "DEF-shoulder.L", "DEF-shoulder.R"]:
		if _rests.has(bone_name):
			_override(bone_name, body * (_rests[bone_name] as Transform3D))
	for index: int in 7:
		var bone_name := "DEF-spine" if index == 0 else "DEF-spine.%03d" % index
		if not _rests.has(bone_name):
			continue
		var pose: Transform3D = body * _rests[bone_name]
		if index >= 5:
			var head_pivot: Vector3 = body * (_rests["DEF-spine.006"] as Transform3D).origin
			var twist := Basis.from_euler(Vector3(-head_angles.x, -head_angles.y, head_angles.z) * PI / 180.0)
			pose.origin = head_pivot + bend * twist * bend.inverse() * (pose.origin - head_pivot)
			pose.basis = bend * twist * bend.inverse() * pose.basis
		_override(bone_name, pose)
	_arm("L", Vector3(left_wrist.x, left_wrist.y, -left_wrist.z), body)
	_arm("R", Vector3(right_wrist.x, right_wrist.y, -right_wrist.z), body)
	if kneel > 0.0:
		for side: String in ["L", "R"]:
			var sign_x := 1.0 if side == "L" else -1.0
			var hip: Vector3 = (_rests["DEF-thigh." + side] as Transform3D).origin
			var knee: Vector3 = (_rests["DEF-shin." + side] as Transform3D).origin.lerp(Vector3(sign_x * 0.2, 0.65, 0.32), kneel)
			var ankle := Vector3(sign_x * 0.22, lerpf(0.09, 0.56, kneel), -0.35 * kneel)
			_segment("DEF-thigh." + side, "DEF-thigh." + side + ".001", hip, knee)
			_segment("DEF-shin." + side, "DEF-shin." + side + ".001", knee, ankle)
			var foot := "DEF-foot." + side
			if _rests.has(foot):
				var foot_pose := Transform3D((_rests[foot] as Transform3D).basis, ankle)
				_override(foot, foot_pose)
				_follow("DEF-toe." + side, foot_pose * (_rests[foot] as Transform3D).affine_inverse())
	skeleton.force_update_all_bone_transforms()


func _arm(side: String, wrist: Vector3, body: Transform3D) -> void:
	var upper := "DEF-upper_arm." + side
	var lower := "DEF-forearm." + side
	var hand := "DEF-hand." + side
	var shoulder: Vector3 = body * (_rests[upper] as Transform3D).origin
	var a: float = (_rests[upper] as Transform3D).origin.distance_to((_rests[lower] as Transform3D).origin)
	var b: float = (_rests[lower] as Transform3D).origin.distance_to((_rests[hand] as Transform3D).origin)
	var reach := wrist - shoulder
	var distance := clampf(reach.length(), absf(a - b) + 0.01, a + b - 0.001)
	var direction := reach.normalized()
	var target := shoulder + direction * distance
	var sign_x := 1.0 if side == "L" else -1.0
	var pole := Vector3(sign_x, arm_pole_height, -0.35)
	var perpendicular := (pole - direction * pole.dot(direction)).normalized()
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var elbow := shoulder + direction * along + perpendicular * sqrt(maxf(0, a * a - along * along))
	_segment(upper, upper + ".001", shoulder, elbow)
	_segment(lower, lower + ".001", elbow, target)
	var rest: Transform3D = _rests[hand]
	var forward := (target - elbow).normalized()
	var hand_pose := Transform3D(Basis(Quaternion(rest.basis.y.normalized(), forward)) * rest.basis, target)
	_override(hand, hand_pose)
	var hand_delta := hand_pose * rest.affine_inverse()
	# Thumb deform bones live in a separate Rigify branch; move them with the hand.
	for index: int in range(1, 4):
		_follow("DEF-thumb.%02d." % index + side, hand_delta)


func _follow(bone_name: String, delta: Transform3D) -> void:
	if _rests.has(bone_name):
		_override(bone_name, delta * (_rests[bone_name] as Transform3D))


func _segment(bone_name: String, middle_name: String, start: Vector3, end: Vector3) -> void:
	var rest: Transform3D = _rests[bone_name]
	var direction := (end - start).normalized()
	var basis := Basis(Quaternion(rest.basis.y.normalized(), direction)) * rest.basis
	_override(bone_name, Transform3D(basis, start))
	_override(middle_name, Transform3D(basis, start.lerp(end, 0.5)))


func _override(bone_name: String, pose: Transform3D) -> void:
	if _bones.has(bone_name):
		skeleton.set_bone_global_pose_override(_bones[bone_name], pose, 1.0, true)
