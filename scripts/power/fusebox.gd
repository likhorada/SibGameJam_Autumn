class_name ApartmentFusebox
extends Node3D
## Four physical handles; input is ray-tested every frame, not just at mouse-down.
signal repaired

@export_range(0.1, 10.0) var raise_seconds: float = 3.5
@export_range(0.1, 5.0) var fall_seconds: float = 1.2
@export_group("Optional mechanical audio")
@export var raise_sound: AudioStream
@export var fall_sound: AudioStream
@export var latch_sound: AudioStream

var progress: Array[float] = [1.0, 1.0, 1.0, 1.0]
var latched: Array[bool] = [true, true, true, true]
var active: bool = false
var held: int = -1
var powered: bool = true
var view_camera: Camera3D
@onready var handles: Array[Node] = $Handles.get_children()
@onready var motion_audio: AudioStreamPlayer3D = $MotionAudio
@onready var click_audio: AudioStreamPlayer3D = $ClickAudio


func _ready() -> void:
	_update_handles()


func reset_for_outage() -> void:
	cancel_hold()
	powered = false
	progress.assign([0.0, 0.0, 0.0, 0.0])
	latched.assign([false, false, false, false])
	_update_handles()


func mark_powered() -> void:
	cancel_hold()
	powered = true
	progress.assign([1.0, 1.0, 1.0, 1.0])
	latched.assign([true, true, true, true])
	_update_handles()


func set_active(value: bool, camera: Camera3D = null) -> void:
	active = value
	view_camera = camera if value else null
	cancel_hold()


func cancel_hold() -> void:
	if held >= 0 and not latched[held]:
		_play(click_audio, fall_sound)
	held = -1
	if is_instance_valid(motion_audio):
		motion_audio.stop()


func hovered_lever() -> int:
	if not active or not is_instance_valid(view_camera):
		return -1
	var mouse := get_viewport().get_mouse_position()
	var start := view_camera.project_ray_origin(mouse)
	var end := start + view_camera.project_ray_normal(mouse) * 3.0
	var query := PhysicsRayQueryParameters3D.create(start, end, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	if not is_ancestor_of(hit.collider):
		return -1
	return int(hit.collider.get_meta("lever_index", -1))


func begin_hold(index: int) -> void:
	if not active or powered or index < 0 or index >= 4 or latched[index]:
		return
	cancel_hold()
	held = index
	_play(motion_audio, raise_sound)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			begin_hold(hovered_lever())
		else:
			cancel_hold()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if held >= 0 and (not active or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or hovered_lever() != held):
		cancel_hold()
	if held >= 0 and raise_sound != null and not motion_audio.playing:
		_play(motion_audio, raise_sound)
	advance(delta)


func advance(delta: float) -> void:
	if powered:
		return
	for index: int in 4:
		if latched[index]:
			continue
		if active and index == held:
			progress[index] = minf(1.0, progress[index] + delta / maxf(raise_seconds, 0.01))
			if progress[index] >= 1.0 - 0.000001:
				progress[index] = 1.0
				latched[index] = true
				held = -1
				motion_audio.stop()
				_play(click_audio, latch_sound)
		else:
			progress[index] = maxf(0.0, progress[index] - delta / maxf(fall_seconds, 0.01))
	_update_handles()
	if latched.all(func(value: bool) -> bool: return value):
		powered = true
		repaired.emit()


func _update_handles() -> void:
	for index: int in handles.size():
		handles[index].position.y = lerpf(-0.19, 0.17, progress[index])
		var label := handles[index].get_node("State") as Label3D
		label.text = "ON" if latched[index] else "OFF"
		label.modulate = Color("b6c99d") if latched[index] else Color("ac7966")


func _play(player: AudioStreamPlayer3D, stream: AudioStream) -> void:
	if is_instance_valid(player) and stream != null:
		player.stream = stream
		player.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_hold()
