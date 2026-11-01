class_name ObservationLocation
extends Node3D
## Scene-authored observation location. Cameras anywhere below this root are discovered by CCTVSystem.

@export var target_path: NodePath = ^"Target"
@export var route_path: NodePath = ^"Route"

var target: Node3D
var working: bool = true
var bottle: Node3D


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	if target == null or get_node_or_null(route_path) == null:
		push_error("Observation location requires Target and Route nodes: %s" % scene_file_path)


func route() -> Array:
	var points: Array = []
	var route_root := get_node_or_null(route_path)
	if route_root == null:
		return points
	for child: Node in route_root.get_children():
		if child is ObservationWaypoint:
			points.append({"point": to_local(child.global_position), "seconds": child.seconds, "event": child.event_id})
	return points


func exit_point(index: int) -> Vector3:
	var exits := get_node_or_null(^"Exits")
	if exits == null or index < 0 or index >= exits.get_child_count():
		push_error("Missing street exit %d in %s" % [index, scene_file_path])
		return Vector3.ZERO
	return to_local((exits.get_child(index) as Node3D).global_position)


func event(_id: String) -> void:
	pass
