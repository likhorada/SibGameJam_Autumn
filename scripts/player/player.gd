class_name ApartmentPlayer
extends CharacterBody3D

@export var walk_speed: float = 2.5
@export var sprint_speed: float = 4.3
@export var mouse_sensitivity: float = 0.0022
@export var interaction_distance: float = 2.2

var controls_enabled: bool = true
var interaction_id: StringName = &""

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.screen_relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.screen_relative.y * mouse_sensitivity,
			deg_to_rad(-80.0), deg_to_rad(80.0)
		)


func _physics_process(delta: float) -> void:
	interaction_id = &""
	if not controls_enabled:
		velocity = Vector3.ZERO
		return
	var direction := Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		direction = global_basis * Vector3(axis.x, 0.0, axis.y)
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		interaction_id = find_interaction()


func find_interaction() -> StringName:
	var start := camera.global_position
	var end := start - camera.global_basis.z * interaction_distance
	var query := PhysicsRayQueryParameters3D.create(start, end, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return &""
	return StringName(hit.collider.get_meta("interaction", &""))


func place_at(marker: Node3D) -> void:
	global_transform = marker.global_transform
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	interaction_id = &""
