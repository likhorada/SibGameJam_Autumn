class_name HidingSpot
extends Node3D
## A camera pose plus collision-checked standing exits, not a crouch controller.

@export var prompt_key: String = "HIDE_WARDROBE"
@export_range(0.0, 40.0) var max_yaw_degrees: float = 18.0
@export_range(0.0, 20.0) var max_pitch_degrees: float = 6.0
@export_range(35.0, 80.0) var view_fov: float = 60.0

@onready var view: Marker3D = $View


func find_safe_exit(player: ApartmentPlayer, entry_pose: Transform3D) -> Variant:
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var candidates: Array[Transform3D] = []
	for marker: Node3D in $Exits.get_children():
		candidates.append(marker.global_transform)
	candidates.append(entry_pose)
	for pose: Transform3D in candidates:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule.shape
		query.transform = pose * capsule.transform
		query.collision_mask = player.collision_mask
		query.exclude = [player.get_rid()]
		if player.get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			return pose
	return null
