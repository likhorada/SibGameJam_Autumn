class_name PoliceRaid
extends ThreatEvent
## Warning protects distant players; close contact is dangerous during approach too.

enum Visit { DORMANT, WARNING, SEARCHING, DEPARTING, CHASING }
const VISUAL := preload("res://scenes/threats/police_officer.tscn")
const AMBUSH_SOUND := preload("res://assets/audio/police_aimbush.wav")
@export var settings: PoliceRaidConfig = preload("res://data/threats/police_raid.tres")
var visit: Visit = Visit.DORMANT
var game: Node3D
var visual: Node3D
var knock_audio: AudioStreamPlayer3D
var voice_audio: AudioStreamPlayer3D
var footsteps_audio: AudioStreamPlayer3D
var arrival_audio: AudioStreamPlayer3D
var ambush_audio: AudioStreamPlayer3D
var awareness := ThreatAwareness.new()
var pressure := VisitorPressure.new()
var pursuit := VisitorPursuit.new()
var _approach: Vector3
var _entry_pending: bool = false
var _elapsed: float = 0.0
var _knock_left: float = 0.0
var _voice_left: float = 0.0
var _voice_pending: bool = false
var _route: Array[Vector3] = []
var _departure: Array[Vector3] = []
var _pursuit_route: Array[Vector3] = []


func bind(value: Node3D) -> void:
	game = value
	for marker: Node3D in game.get_node("Apartment/PoliceRoute").get_children():
		_route.append(marker.global_position)
	_pursuit_route.append(game.room_door.get_node("Approach").global_position)
	_pursuit_route.append_array(_route)
	_departure.assign(_route)
	_departure.reverse()
	_departure.append(game.room_door.get_node("Approach").global_position)


func _ready() -> void:
	visual = VISUAL.instantiate()
	add_child(visual)
	knock_audio = _audio(settings.knock_sound, settings.warning_volume_db)
	voice_audio = _audio(settings.warning_voice if settings.warning_voice != null else settings.knock_sound, settings.warning_volume_db)
	footsteps_audio = _audio(settings.footsteps, settings.footsteps_volume_db)
	arrival_audio = _audio(settings.arrival_sound, settings.warning_volume_db)
	ambush_audio = _audio(AMBUSH_SOUND, settings.warning_volume_db - 4.0)
	awareness.confirm_seconds = settings.detection_seconds
	awareness.recovery_seconds = settings.suspicion_recovery_seconds
	awareness.sight_range = settings.sight_range
	awareness.half_angle = settings.sight_half_angle
	awareness.close_distance = settings.close_distance
	awareness.close_confirm_seconds = settings.close_capture_seconds


func _audio(stream: AudioStream, volume: float) -> AudioStreamPlayer3D:
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.volume_db = volume
	audio.bus = &"SFX"
	audio.unit_size = 7.0
	audio.max_distance = 22.0
	visual.add_child(audio)
	audio.position.y = 1.0
	return audio


func can_start() -> bool:
	return is_instance_valid(game) and game.power.powered and not game.run_ended


func can_schedule() -> bool:
	if not can_start():
		return false
	var spawn: Vector3 = game.room_door.get_node("Approach").global_position
	var offset: Vector3 = spawn - game.player.global_position
	return Vector2(offset.x, offset.z).length() >= maxf(1.5, settings.close_distance + 0.5)


func warning_started() -> void:
	visit = Visit.WARNING
	_elapsed = 0.0
	awareness.reset()
	pressure.reset()
	_approach = game.room_door.get_node("Approach").global_position
	visual.global_position = _approach
	visual.look_at(_route[0], Vector3.UP)
	visual.show()
	game.prepare_for_threat()
	if arrival_audio.stream != null:
		arrival_audio.play()
	footsteps_audio.play()
	ambush_audio.play()
	knock_audio.play()
	_knock_left = maxf(1.0, settings.knock_interval)
	_voice_left = maxf(0.0, settings.voice_delay)
	_voice_pending = true


func active_started() -> void:
	if visit == Visit.CHASING:
		return
	visit = Visit.SEARCHING
	_elapsed = 0.0
	_voice_pending = false
	knock_audio.stop()
	voice_audio.stop()
	_entry_pending = not game.room_door.force_open(game)
	visual.show()
	visual.global_position = _route[0]
	footsteps_audio.pitch_scale = 1.0
	footsteps_audio.play()
	pressure.reset(_route, settings.search_seconds, settings.pressure_seconds)


func advance(delta: float) -> void:
	if visit == Visit.DORMANT or not game.capture_reason.is_empty():
		return
	if awareness.advance_close(game, visual, delta):
		game.begin_threat_capture("POLICE_DEATH", visual)
		return
	if awareness.close_now:
		# Face the player and stop briefly; do not keep walking through them.
		footsteps_audio.stop()
		return
	if visit != Visit.CHASING and game.room_door.is_open:
		awareness.advance(game, visual, delta)
		if awareness.visible_now:
			_begin_chase()
	if visit == Visit.CHASING:
		pursuit.advance(game, visual, _pursuit_route, delta)
		if not footsteps_audio.playing:
			footsteps_audio.play()
		return
	_elapsed += delta
	if visit == Visit.WARNING:
		var approach_progress := clampf(_elapsed / 3.0, 0.0, 1.0)
		visual.global_position = _approach.lerp(_route[0], approach_progress)
		if approach_progress >= 1.0:
			footsteps_audio.stop()
		if _voice_pending:
			_voice_left -= delta
			if _voice_left <= 0.0:
				voice_audio.play()
				_voice_pending = false
		_knock_left -= delta
		if _knock_left <= 0.0:
			knock_audio.play()
			_knock_left = maxf(1.0, settings.knock_interval)
			_voice_left = maxf(0.0, settings.voice_delay)
			_voice_pending = true
	elif visit in [Visit.SEARCHING, Visit.DEPARTING]:
		if _entry_pending:
			_entry_pending = not game.room_door.force_open(game)
			_elapsed = 0.0
			return
		if awareness.suspicion > 0.0:
			_elapsed = maxf(0.0, _elapsed - delta)
			footsteps_audio.stop()
			return
		if visit == Visit.SEARCHING:
			pressure.advance(game, visual, delta)
			_elapsed = pressure.movement_elapsed
			if pressure.holding:
				footsteps_audio.stop()
			elif not footsteps_audio.playing:
				footsteps_audio.play()
			if pressure.finished:
				visit = Visit.DEPARTING
				_elapsed = 0.0
				voice_audio.stream = settings.departure_sound if settings.departure_sound != null else settings.knock_sound
				voice_audio.play()
				footsteps_audio.pitch_scale = 1.15
		else:
			if not footsteps_audio.playing:
				footsteps_audio.play()
			_move(_departure, _elapsed / maxf(0.5, settings.departure_seconds))
			if _elapsed >= settings.departure_seconds:
				resolved.emit(&"survived")


func _begin_chase() -> void:
	game.threats.play_detected()
	visit = Visit.CHASING
	_entry_pending = false
	_elapsed = 0.0
	knock_audio.stop()
	voice_audio.stop()
	footsteps_audio.pitch_scale = 1.2
	if not footsteps_audio.playing:
		footsteps_audio.play()


func _move(points: Array[Vector3], progress: float) -> void:
	var cursor := clampf(progress, 0.0, 1.0) * (points.size() - 1)
	var index := mini(int(cursor), points.size() - 2)
	var position := points[index].lerp(points[index + 1], cursor - index)
	if visual.global_position.distance_squared_to(position) > 0.0001:
		visual.look_at(position, Vector3.UP)
	visual.global_position = position


func resolved_started(outcome: StringName) -> void:
	ended(outcome)


func ended(_outcome: StringName) -> void:
	visit = Visit.DORMANT
	_voice_pending = false
	_elapsed = 0.0
	_entry_pending = false
	footsteps_audio.pitch_scale = 1.0
	awareness.reset()
	pressure.reset()
	game.room_door.held_by_police = false
	if is_instance_valid(visual):
		visual.hide()
	if is_instance_valid(knock_audio):
		knock_audio.stop()
	if is_instance_valid(voice_audio):
		voice_audio.stop()
		voice_audio.stream = settings.warning_voice if settings.warning_voice != null else settings.knock_sound
	if is_instance_valid(footsteps_audio):
		footsteps_audio.stop()
	if is_instance_valid(arrival_audio):
		arrival_audio.stop()
	if is_instance_valid(ambush_audio):
		ambush_audio.stop()
