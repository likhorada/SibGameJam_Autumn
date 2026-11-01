class_name PsychNeighbor
extends ThreatEvent
## Door race followed by a visible search. An unseen hiding player is safe.

enum Visit { DORMANT, APPROACHING, RATTLING, ENTERING, DEPARTING, RETREATING, SEARCHING, CHASING }
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
var _rng := RandomNumberGenerator.new()
var awareness := ThreatAwareness.new()
var pressure := VisitorPressure.new()
var pursuit := VisitorPursuit.new()
var _search_route: Array[Vector3] = []
var _depart_route: Array[Vector3] = []
var _pursuit_route: Array[Vector3] = []
var _inside: bool = false


func bind(value: Node3D) -> void:
	game = value
	door = game.get_node("Apartment/RoomDoor")
	door.changed.connect(_on_door_changed)
	_search_route.append(door.get_node("Threshold").global_position)
	for marker: Node3D in game.get_node("Apartment/PoliceRoute").get_children():
		if marker.name != "Entry":
			_search_route.append(marker.global_position)
	_pursuit_route.append(door.get_node("Approach").global_position)
	_pursuit_route.append_array(_search_route)


func _ready() -> void:
	_rng = RunRandom.generator(game.run_seed, &"neighbor_audio")
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
	awareness.confirm_seconds = settings.detection_seconds
	awareness.recovery_seconds = settings.suspicion_recovery_seconds
	awareness.sight_range = settings.sight_range
	awareness.half_angle = settings.sight_half_angle
	awareness.close_distance = settings.close_distance
	awareness.close_confirm_seconds = settings.close_capture_seconds


func can_start() -> bool:
	return is_instance_valid(game) and is_instance_valid(door) and game.power.powered and not game.run_ended


func can_schedule() -> bool:
	if not can_start():
		return false
	var offset: Vector3 = door.get_node("Approach").global_position - game.player.global_position
	return Vector2(offset.x, offset.z).length() >= maxf(1.5, settings.close_distance + 0.5)


func warning_started() -> void:
	visit = Visit.APPROACHING
	_elapsed = 0.0
	entry_seconds = 0.0
	_inside = false
	awareness.reset()
	pressure.reset()
	visual.global_position = door.get_node("Approach").global_position
	visual.show()
	_face(door.get_node("Waiting").global_position)
	footsteps_audio.play()


func active_started() -> void:
	if visit == Visit.CHASING:
		return
	visual.global_position = door.get_node("Waiting").global_position
	footsteps_audio.stop()
	_begin_rattle()
	if door.is_open:
		_begin_entry()


func advance(delta: float) -> void:
	if visit == Visit.DORMANT or not game.capture_reason.is_empty():
		return
	if awareness.advance_close(game, visual, delta):
		game.begin_threat_capture("NEIGHBOR_DEATH", visual)
		return
	if awareness.close_now:
		footsteps_audio.stop()
		handle_audio.stop()
		return
	if visit != Visit.CHASING and door.is_open:
		awareness.advance(game, visual, delta)
		if awareness.visible_now:
			_begin_chase()
	if visit == Visit.CHASING:
		handle_audio.stop()
		pursuit.advance(game, visual, _pursuit_route, delta)
		if not footsteps_audio.playing:
			footsteps_audio.play()
		return
	if visit in [Visit.SEARCHING, Visit.DEPARTING] and _inside:
		if awareness.suspicion > 0.0:
			footsteps_audio.stop()
			return
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
				_begin_departure()
		Visit.ENTERING:
			entry_seconds += delta
			var progress := clampf(entry_seconds / maxf(0.2, settings.attack_delay), 0.0, 1.0)
			visual.global_position = _entry_from.lerp(door.get_node("Threshold").global_position, progress)
			_steps()
			if progress >= 1.0:
				_inside = true
				visit = Visit.SEARCHING
				_elapsed = 0.0
				pressure.reset(_search_route, settings.search_seconds, settings.pressure_seconds, true)
		Visit.RETREATING:
			visual.global_position = _entry_from.lerp(door.get_node("Waiting").global_position, clampf(_elapsed / 0.6, 0.0, 1.0))
			if _elapsed >= 0.6:
				_begin_rattle()
		Visit.SEARCHING:
			pressure.advance(game, visual, delta)
			_elapsed = pressure.movement_elapsed
			if pressure.holding:
				footsteps_audio.stop()
			else:
				_steps()
			if pressure.finished:
				_begin_departure()
		Visit.DEPARTING:
			_move_route(_depart_route, _elapsed / maxf(0.5, settings.departure_seconds))
			_steps()
			if _elapsed >= settings.departure_seconds:
				resolved.emit(&"survived")


func _on_door_changed(open: bool) -> void:
	if visit not in [Visit.RATTLING, Visit.ENTERING, Visit.DEPARTING, Visit.RETREATING] or _inside:
		return
	if open and visit != Visit.ENTERING:
		_begin_entry()
	elif visit == Visit.ENTERING:
		# The door won the race; he remains dangerous until he actually leaves.
		visit = Visit.RETREATING
		_entry_from = visual.global_position
		_elapsed = 0.0
		_face(door.get_node("Waiting").global_position)


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
	if is_instance_valid(game.visual_effects):
		game.visual_effects.trigger_scare()
	visit = Visit.ENTERING
	entry_seconds = 0.0
	_elapsed = 0.0
	_entry_from = visual.global_position
	_face(door.get_node("Threshold").global_position)
	footsteps_audio.play()
	handle_audio.stop()


func _begin_chase() -> void:
	game.threats.play_detected()
	visit = Visit.CHASING
	entry_seconds = 0.0
	_elapsed = 0.0
	_inside = true
	footsteps_audio.pitch_scale = 1.2
	footsteps_audio.play()
	handle_audio.stop()


func _begin_departure() -> void:
	visit = Visit.DEPARTING
	_elapsed = 0.0
	_depart_route.clear()
	_depart_route.append(visual.global_position)
	if _inside:
		for index: int in range(_search_route.size() - 2, -1, -1):
			_depart_route.append(_search_route[index])
	_depart_route.append(door.get_node("Waiting").global_position)
	_depart_route.append(door.get_node("Approach").global_position)
	handle_audio.stop()
	_steps()


func _move_route(points: Array[Vector3], progress: float) -> void:
	var cursor := clampf(progress, 0.0, 1.0) * (points.size() - 1)
	var index := mini(int(cursor), points.size() - 2)
	var destination := points[index].lerp(points[index + 1], cursor - index)
	# A closed entrance holds an indoor visitor instead of letting him phase out.
	if _inside and not door.is_open and destination.x >= door.global_position.x:
		if not door.set_open(true):
			_elapsed = maxf(0.0, _elapsed - 0.1)
			return
	_face(destination)
	visual.global_position = destination


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
	footsteps_audio.pitch_scale = 1.0
	awareness.reset()
	pressure.reset()
	_inside = false
	if is_instance_valid(visual):
		visual.hide()
	if is_instance_valid(footsteps_audio):
		footsteps_audio.stop()
	if is_instance_valid(handle_audio):
		handle_audio.stop()
