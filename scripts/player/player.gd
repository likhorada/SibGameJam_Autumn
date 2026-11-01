class_name ApartmentPlayer
extends CharacterBody3D

const PLAYER_FOOTSTEPS := preload("res://assets/audio/player_steps.wav")

@export var walk_speed: float = 2.5
@export var sprint_speed: float = 4.3
@export_range(1.0, 60.0) var acceleration: float = 18.0
@export_range(1.0, 60.0) var braking: float = 22.0
@export_range(0.1, 1.0) var walk_footstep_interval: float = 0.34
@export_range(0.1, 1.0) var sprint_footstep_interval: float = 0.20
@export var mouse_sensitivity: float = 0.0022
@export var interaction_distance: float = 2.2
## Exponential response in 1/seconds; zero gives instant mouse look.
@export_range(0.0, 40.0) var look_response: float = 18.0
@export_range(0.0, 15.0) var max_look_lag_degrees: float = 6.0

var controls_enabled: bool = true
var interaction_id: StringName = &""
var is_sprinting: bool = false
var _pending_look := Vector2.ZERO
var _motion_velocity := Vector3.ZERO
var _motion_acceleration := Vector3.ZERO
var exhaustion_audio: AudioStreamPlayer
var footsteps_audio: AudioStreamPlayer3D
var _footstep_left: float = 0.0

@onready var head: Node3D = $Head
@onready var camera_motion: PlayerCameraMotion = $Head/CameraMotion
@onready var camera: Camera3D = $Head/CameraMotion/Camera3D
@onready var stamina: PlayerStamina = $Stamina


func _ready() -> void:
	mouse_sensitivity = get_node("/root/Preferences").sensitivity
	exhaustion_audio = AudioStreamPlayer.new()
	exhaustion_audio.name = "ExhaustionAudio"
	exhaustion_audio.bus = &"SFX"
	exhaustion_audio.stream = preload("res://assets/audio/exausted.wav")
	exhaustion_audio.volume_db = -6.0
	add_child(exhaustion_audio)
	stamina.became_exhausted.connect(_play_exhaustion_sound)
	footsteps_audio = AudioStreamPlayer3D.new()
	footsteps_audio.name = "FootstepsAudio"
	footsteps_audio.bus = &"SFX"
	footsteps_audio.stream = PLAYER_FOOTSTEPS
	footsteps_audio.volume_db = -6.0
	footsteps_audio.unit_size = 3.0
	footsteps_audio.max_distance = 12.0
	add_child(footsteps_audio)
	footsteps_audio.position.y = 0.08


func _play_exhaustion_sound() -> void:
	if is_instance_valid(exhaustion_audio):
		exhaustion_audio.play()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_pending_look += event.screen_relative * mouse_sensitivity
		# Preserve total input while bounding the lag of a fast mouse flick.
		var limit := deg_to_rad(max_look_lag_degrees)
		var retained := _pending_look.clamp(Vector2(-limit, -limit), Vector2(limit, limit))
		_apply_look(_pending_look - retained)
		_pending_look = retained


func _process(delta: float) -> void:
	if not controls_enabled:
		return
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var applied_look := Vector2.ZERO
	if active:
		var weight := 1.0 if look_response <= 0.0 else 1.0 - exp(-look_response * delta)
		applied_look = _pending_look * weight
		_pending_look -= applied_look
		_apply_look(applied_look)
	else:
		_pending_look = Vector2.ZERO
	var local_velocity := global_basis.inverse() * _motion_velocity
	var local_acceleration := global_basis.inverse() * _motion_acceleration
	camera_motion.update_feedback(
		delta, local_velocity, local_acceleration, applied_look / maxf(delta, 0.0001),
		is_on_floor(), is_sprinting, active, walk_speed, sprint_speed
	)


func _apply_look(amount: Vector2) -> void:
	rotate_y(-amount.x)
	head.rotation.x = clampf(head.rotation.x - amount.y, deg_to_rad(-80.0), deg_to_rad(80.0))


func _physics_process(delta: float) -> void:
	interaction_id = &""
	if not controls_enabled:
		stop_motion()
		stamina.advance(delta, false, false)
		return
	var direction := Vector3.ZERO
	var axis := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		axis = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		direction = global_basis * Vector3(axis.x, 0.0, axis.y)
	# Forward and forward-diagonal only. Sideways/backward movement stays walking.
	var requested_sprint := axis.y < -0.01 and Input.is_action_pressed("sprint") and stamina.can_sprint() and is_on_floor()
	var speed := sprint_speed if requested_sprint else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := direction * speed
	var rate := acceleration if target.length_squared() > horizontal.length_squared() else braking
	horizontal = horizontal.move_toward(target, rate * delta)
	# Focus loss/Esc must stop immediately, not continue the normal braking glide.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		horizontal = Vector3.ZERO
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	var actual_velocity := get_real_velocity()
	actual_velocity.y = 0.0
	var moving := actual_velocity.length() > 0.08
	is_sprinting = requested_sprint and moving and is_on_floor()
	stamina.advance(delta, is_sprinting, moving)
	if not stamina.can_sprint():
		is_sprinting = false
	_update_footsteps(delta, actual_velocity.length())
	_motion_acceleration = ((actual_velocity - _motion_velocity) / maxf(delta, 0.0001)).limit_length(30.0)
	_motion_velocity = actual_velocity
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		interaction_id = find_interaction()


func _update_footsteps(delta: float, speed: float) -> void:
	if not is_on_floor() or speed <= 0.08:
		_footstep_left = 0.0
		return
	_footstep_left -= delta
	if _footstep_left > 0.0:
		return
	footsteps_audio.play()
	var sprint_ratio := clampf(speed / sprint_speed, 0.0, 1.0)
	_footstep_left = lerpf(walk_footstep_interval, sprint_footstep_interval, sprint_ratio)


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
	stop_motion(true)
	interaction_id = &""


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		stop_motion(true)


func stop_motion(reset_camera: bool = false) -> void:
	is_sprinting = false
	_footstep_left = 0.0
	if is_instance_valid(footsteps_audio):
		footsteps_audio.stop()
	velocity = Vector3.ZERO
	_motion_velocity = Vector3.ZERO
	_motion_acceleration = Vector3.ZERO
	_pending_look = Vector2.ZERO
	if reset_camera:
		camera_motion.reset_motion()
