@tool
class_name CCTVCamera
extends Node3D
## Drop scenes/cctv/cctv_camera.tscn into any ordinary Node3D location.

@export_category("Directory")
@export var camera_id: StringName = &""
@export var display_name: String = "CAM"
@export var location_label: String = "LOCATION"
@export var list_order: int = 0
@export_category("Feed")
@export var monochrome: bool = false
@export var has_microphone: bool = false
@export_category("Mechanics")
@export_range(1.0, 80.0) var pan_limit_degrees: float = 32.0
@export_range(1.0, 45.0) var pan_speed_degrees: float = 14.0
@export_range(1.0, 120.0) var acceleration_degrees: float = 32.0
@export_range(0.0, 1.0) var command_delay: float = 0.22
@export_range(25.0, 100.0) var base_fov: float = 65.0
@export_range(1.1, 3.0) var max_zoom: float = 2.0
@export_range(0.1, 2.0) var zoom_speed: float = 0.45
@export_range(0.0, 0.5) var interference_seconds: float = 0.1

var pan_degrees: float = 0.0
var zoom: float = 1.0
var velocity: float = 0.0
var interference_left: float = 0.0
var _pan_command: float = 0.0
var _zoom_command: float = 0.0
var _delay_left: float = 0.0
var _pulse_time: float = 0.0

@onready var lens: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head


func _ready() -> void:
	if not Engine.is_editor_hint():
		reset_view()


func _get_configuration_warnings() -> PackedStringArray:
	if camera_id.is_empty():
		return ["Set a unique Camera ID before connecting this location to CCTVSystem."]
	return []


func reset_view() -> void:
	stop_immediately()
	pan_degrees = 0.0
	zoom = 1.0
	interference_left = 0.0
	_apply_pose()


func command(pan: float, zoom_direction: float) -> void:
	pan = clampf(pan, -1.0, 1.0)
	zoom_direction = clampf(zoom_direction, -1.0, 1.0)
	if pan == _pan_command and zoom_direction == _zoom_command:
		return
	_pan_command = pan
	_zoom_command = zoom_direction
	if pan != 0.0 or zoom_direction != 0.0:
		_delay_left = command_delay
		interference_left = interference_seconds
		_pulse_time = 0.0


func stop_immediately() -> void:
	_pan_command = 0.0
	_zoom_command = 0.0
	velocity = 0.0
	_delay_left = 0.0


func advance_motor(delta: float) -> void:
	interference_left = maxf(0.0, interference_left - delta)
	_delay_left = maxf(0.0, _delay_left - delta)
	var target := _pan_command * pan_speed_degrees if _delay_left <= 0.0 else 0.0
	velocity = move_toward(velocity, target, acceleration_degrees * delta)
	pan_degrees = clampf(pan_degrees + velocity * delta, -pan_limit_degrees, pan_limit_degrees)
	if absf(pan_degrees) >= pan_limit_degrees:
		velocity = 0.0
	if _delay_left <= 0.0:
		zoom = clampf(zoom + _zoom_command * zoom_speed * delta, 1.0, max_zoom)
	if absf(velocity) > 0.1 or _zoom_command != 0.0:
		_pulse_time += delta
		if _pulse_time >= 0.75:
			_pulse_time = 0.0
			interference_left = interference_seconds
	_apply_pose()


func _apply_pose() -> void:
	head.rotation.y = deg_to_rad(pan_degrees)
	# Focal-length ratio, rather than a linear FOV approximation.
	lens.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / zoom))
