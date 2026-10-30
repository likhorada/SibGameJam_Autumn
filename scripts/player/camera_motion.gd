class_name PlayerCameraMotion
extends Node3D
## Visual-only feedback below Head. Never rotates the capsule or the look pivot.

@export_group("Comfort")
## Zero disables bob, roll, acceleration response and sprint FOV, not mouse smoothing.
@export_range(0.0, 2.0) var effect_strength: float = 1.0
@export_range(1.0, 30.0) var response: float = 10.0

@export_group("Steps")
@export_range(0.5, 3.0) var stride_length: float = 1.7
@export_range(0.0, 0.08) var vertical_bob: float = 0.035
@export_range(0.0, 0.06) var lateral_bob: float = 0.022
@export_range(0.0, 2.0) var step_roll_degrees: float = 0.4
@export_range(1.0, 2.0) var sprint_bob_multiplier: float = 1.4

@export_group("Inertia")
@export_range(0.0, 5.0) var strafe_roll_degrees: float = 2.2
@export_range(0.0, 4.0) var turn_roll_degrees: float = 1.8
@export_range(0.0, 4.0) var acceleration_pitch_degrees: float = 1.6
@export_range(0.0, 3.0) var acceleration_roll_degrees: float = 0.5
@export_range(0.0, 8.0) var max_roll_degrees: float = 4.5

@export_group("Field of view")
@export_range(60.0, 100.0) var base_fov: float = 75.0
@export_range(60.0, 105.0) var sprint_fov: float = 80.0

var step_phase: float = 0.0
var _step_weight: float = 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	reset_motion()


func update_feedback(
	delta: float, local_velocity: Vector3, local_acceleration: Vector3,
	look_velocity: Vector2, grounded: bool, sprinting: bool, active: bool,
	walk_speed: float, sprint_speed: float
) -> void:
	var weight := 1.0 - exp(-response * delta)
	var speed := Vector2(local_velocity.x, local_velocity.z).length() if active else 0.0
	var moving := grounded and speed > 0.08
	var run_weight := 0.0
	if sprinting and moving:
		run_weight = clampf((speed - walk_speed) / maxf(sprint_speed - walk_speed, 0.01), 0.0, 1.0)
	var step_target := clampf(speed / maxf(walk_speed, 0.01), 0.0, 1.0) if moving else 0.0
	_step_weight = lerpf(_step_weight, step_target, weight)
	if moving:
		step_phase = fposmod(step_phase + speed * delta * TAU / stride_length, TAU)
	var amplitude := _step_weight * lerpf(1.0, sprint_bob_multiplier, run_weight)
	var target_position := Vector3(
		sin(step_phase) * lateral_bob, sin(step_phase * 2.0) * vertical_bob, 0.0
	) * amplitude * effect_strength
	var roll := sin(step_phase) * deg_to_rad(step_roll_degrees) * amplitude
	var pitch := 0.0
	if active:
		roll -= clampf(local_velocity.x / maxf(walk_speed, 0.01), -1.0, 1.0) * deg_to_rad(strafe_roll_degrees)
		roll -= clampf(look_velocity.x / 3.0, -1.0, 1.0) * deg_to_rad(turn_roll_degrees)
		roll -= clampf(local_acceleration.x / 18.0, -1.0, 1.0) * deg_to_rad(acceleration_roll_degrees)
		pitch = -clampf(local_acceleration.z / 18.0, -1.0, 1.0) * deg_to_rad(acceleration_pitch_degrees)
	roll = clampf(roll, -deg_to_rad(max_roll_degrees), deg_to_rad(max_roll_degrees))
	position = position.lerp(target_position, weight)
	rotation = rotation.lerp(Vector3(pitch, 0.0, roll) * effect_strength, weight)
	var target_fov := lerpf(base_fov, sprint_fov, run_weight * effect_strength)
	camera.fov = lerpf(camera.fov, target_fov, weight)


func reset_motion() -> void:
	step_phase = 0.0
	_step_weight = 0.0
	transform = Transform3D.IDENTITY
	camera.fov = base_fov
