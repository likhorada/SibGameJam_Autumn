class_name PsychNeighbor
extends ThreatEvent
## Scripted visit only: no navigation, pursuit or player-position damage checks.

enum Visit { DORMANT, APPROACHING, RATTLING, ENTERING, DEPARTING }
const VISUAL := preload("res://scenes/threats/psych_neighbor.tscn")

@export var settings: PsychNeighborConfig = preload("res://data/threats/psych_neighbor.tres")
var visit: Visit = Visit.DORMANT
var game: Node3D
var door: RoomDoor
var visual: Node3D
var footsteps_audio: AudioStreamPlayer3D
var handle_audio: AudioStreamPlayer3D
var entry_seconds: float = 0.0
var _elapsed: float = 0.0
var _handle_left: float = 0.0
var _entry_from: Vector3
var _departure_from: Vector3
var _rng := RandomNumberGenerator.new()


func bind(value: Node3D) -> void:
	game = value
	door = game.get_node("Apartment/RoomDoor")
	door.changed.connect(_on_door_changed)


func _ready() -> void:
	_rng.randomize()
	visual = VISUAL.instantiate()
	add_child(visual)
	footsteps_audio = AudioStreamPlayer3D.new()
	footsteps_audio.bus = &"SFX"
	footsteps_audio.unit_size = 6.0
	footsteps_audio.max_distance = 20.0
	footsteps_audio.volume_db = settings.footsteps_volume_db
	footsteps_audio.stream = settings.footsteps
	visual.add_child(footsteps_audio)
	footsteps_audio.position.y = 1.0
	handle_audio = AudioStreamPlayer3D.new()
	handle_audio.bus = &"SFX"
	handle_audio.unit_size = 6.0
	handle_audio.max_distance = 20.0
	handle_audio.volume_db = settings.handle_volume_db
	visual.add_child(handle_audio)
	handle_audio.position.y = 1.1


func can_start() -> bool:
	return is_instance_valid(game) and is_instance_valid(door) and game.power.powered and not game.run_ended


func warning_started() -> void:
	visit = Visit.APPROACHING
	_elapsed = 0.0
	entry_seconds = 0.0
	visual.global_position = door.get_node("Approach").global_position
	visual.show()
	_face(door.get_node("Waiting").global_position)
	footsteps_audio.play()


func active_started() -> void:
	visual.global_position = door.get_node("Waiting").global_position
	footsteps_audio.stop()
	_begin_rattle()
	if door.is_open:
		_begin_entry()


func advance(delta: float) -> void:
	_elapsed += delta
	match visit:
		Visit.APPROACHING:
			var duration: float = game.threats.config.profile_for(&"psych_neighbor").warning_seconds
			visual.global_position = door.get_node("Approach").global_position.lerp(door.get_node("Waiting").global_position, clampf(_elapsed / maxf(duration, 0.01), 0.0, 1.0))
			_steps()
		Visit.RATTLING:
			_handle_left -= delta
			if _handle_left <= 0.0:
				_play_handle_sound()
				_handle_left = 1.1
			if _elapsed >= settings.rattle_seconds:
				visit = Visit.DEPARTING
				_elapsed = 0.0
				_departure_from = visual.global_position
				handle_audio.stop()
				_face(door.get_node("Approach").global_position)
				footsteps_audio.play()
		Visit.ENTERING:
			entry_seconds += delta
			var progress := clampf(entry_seconds / maxf(0.2, settings.attack_delay), 0.0, 1.0)
			visual.global_position = _entry_from.lerp(door.get_node("Threshold").global_position, progress)
			_steps()
			if progress >= 1.0:
				game.fail_from_threat("NEIGHBOR_DEATH")
		Visit.DEPARTING:
			visual.global_position = _departure_from.lerp(door.get_node("Approach").global_position, clampf(_elapsed / maxf(0.5, settings.departure_seconds), 0.0, 1.0))
			_steps()
			if _elapsed >= settings.departure_seconds:
				resolved.emit(&"survived")


func _on_door_changed(open: bool) -> void:
	if visit not in [Visit.RATTLING, Visit.ENTERING, Visit.DEPARTING]:
		return
	if open:
		_begin_entry()
	elif visit == Visit.ENTERING:
		# The door won the race; he remains dangerous until he actually leaves.
		visual.global_position = door.get_node("Waiting").global_position
		_begin_rattle()


func _begin_rattle() -> void:
	visit = Visit.RATTLING
	_elapsed = 0.0
	entry_seconds = 0.0
	_handle_left = 1.1
	footsteps_audio.stop()
	_face(door.global_position)
	_play_handle_sound()


func _play_handle_sound() -> void:
	var available: Array[AudioStream] = []
	for stream: AudioStream in settings.handle_sounds:
		if stream != null:
			available.append(stream)
	if available.is_empty():
		return
	handle_audio.stream = available[_rng.randi_range(0, available.size() - 1)]
	handle_audio.play()


func _begin_entry() -> void:
	visit = Visit.ENTERING
	entry_seconds = 0.0
	_elapsed = 0.0
	_entry_from = visual.global_position
	_face(door.get_node("Threshold").global_position)
	footsteps_audio.play()


func _steps() -> void:
	if not footsteps_audio.playing:
		footsteps_audio.play()


func _face(target: Vector3) -> void:
	if visual.global_position.distance_squared_to(target) > 0.001:
		visual.look_at(target, Vector3.UP)


func resolved_started(_outcome: StringName) -> void:
	ended(_outcome)


func ended(_outcome: StringName) -> void:
	visit = Visit.DORMANT
	entry_seconds = 0.0
	if is_instance_valid(visual):
		visual.hide()
	if is_instance_valid(footsteps_audio):
		footsteps_audio.stop()
	if is_instance_valid(handle_audio):
		handle_audio.stop()
