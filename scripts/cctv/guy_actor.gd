@tool
extends Node3D
## Keep the GLB's authored pose instead of displaying its T-pose rest skeleton.

@export var shirt_color := Color(0.74, 0.53, 0.25)
var _previous_position := Vector3.ZERO


func _ready() -> void:
	var player: AnimationPlayer = $Model/AnimationPlayer
	player.play(&"Action")
	player.advance(0.0)
	player.pause()
	for part: String in ["Torso", "ArmUp", "ArmDown"]:
		var mesh: MeshInstance3D = get_node("Model/rig/Skeleton3D/" + part)
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
			material.albedo_color = shirt_color
			mesh.set_surface_override_material(surface, material)
	_previous_position = global_position
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	var direction := global_position - _previous_position
	direction.y = 0.0
	if direction.length_squared() > 0.000001:
		look_at(global_position + direction.normalized(), Vector3.UP, true)
	_previous_position = global_position
