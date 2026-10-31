class_name RoomDoor
extends Node3D
## Instant, matching visual/collision poses. Never close a leaf through the player.

signal changed(open: bool)

const DEFAULT_DOOR_SOUND: AudioStream = preload("res://assets/audio/door_click.wav")

@export var open_sound: AudioStream
@export var close_sound: AudioStream
var is_open: bool = false
var blocked_seconds_left: float = 0.0
var held_by_police: bool = false

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
	if not value and held_by_police:
		blocked_seconds_left = 1.0
		return false
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
	_apply_state(value)
	return true


func _apply_state(value: bool) -> void:
	is_open = value
	hinge.rotation.y = PI * 0.5 if value else 0.0
	blocked_seconds_left = 0.0
	audio.stream = (open_sound if value else close_sound)
	if audio.stream == null:
		audio.stream = DEFAULT_DOOR_SOUND
	audio.play()
	changed.emit(is_open)


func force_open(game: Node3D) -> bool:
	if is_open:
		held_by_police = true
		return true
	# Only move the player when the final leaf pose would intersect their body.
	var pose := global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), hinge.position) * leaf.transform
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = pose
	query.collision_mask = 1
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query):
		if hit.collider == game.player:
			var moved: bool = false
			for offset: Vector3 in [Vector3(-0.9, 0.03, 0), Vector3(1.2, 0.03, -0.4), Vector3(-1.4, 0.03, -0.5)]:
				var destination := global_position + offset
				if game.place_player_safely(destination):
					moved = true
					break
			if not moved:
				return false
	# The player's safe move and the door commit are one transaction. Re-querying
	# here can see the pre-move physics snapshot and incorrectly reject the move.
	_apply_state(true)
	held_by_police = true
	return true


func _exit_tree() -> void:
	if is_instance_valid(audio):
		audio.stop()
