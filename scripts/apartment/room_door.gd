class_name RoomDoor
extends Node3D
## Instant, matching visual/collision poses. Never close a leaf through the player.

signal changed(open: bool)

@export var open_sound: AudioStream
@export var close_sound: AudioStream
var is_open: bool = false
var blocked_seconds_left: float = 0.0

@onready var hinge: Node3D = $Hinge
@onready var leaf: StaticBody3D = $Hinge/Leaf
@onready var shape: CollisionShape3D = $Hinge/Leaf/CollisionShape3D
@onready var audio: AudioStreamPlayer3D = $DoorAudio


func _ready() -> void:
	hinge.rotation.y = 0.0


func _process(delta: float) -> void:
	blocked_seconds_left = maxf(0.0, blocked_seconds_left - delta)


func toggle() -> bool:
	return set_open(not is_open)


func set_open(value: bool) -> bool:
	if value == is_open:
		return true
	var angle := PI * 0.5 if value else 0.0
	var pose := global_transform * Transform3D(Basis(Vector3.UP, angle), hinge.position) * leaf.transform
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = pose
	query.collision_mask = 1
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query):
		if hit.collider is ApartmentPlayer:
			blocked_seconds_left = 1.0
			return false
	is_open = value
	hinge.rotation.y = angle
	blocked_seconds_left = 0.0
	audio.stream = (open_sound if value else close_sound)
	if audio.stream == null:
		audio.stream = DoorAudio.latch()
	audio.play()
	changed.emit(is_open)
	return true


func _exit_tree() -> void:
	if is_instance_valid(audio):
		audio.stop()
