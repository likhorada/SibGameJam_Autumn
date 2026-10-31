class_name PoliceRaid
extends ThreatEvent
## Scripted room check. Hiding state is authoritative; no pursuit or navigation AI.

enum Visit { DORMANT, WARNING, SEARCHING, DEPARTING }
const VISUAL := preload("res://scenes/threats/police_officer.tscn")
@export var settings: PoliceRaidConfig = preload("res://data/threats/police_raid.tres")
var visit: Visit = Visit.DORMANT
var game: Node3D
var visual: Node3D
var knock_audio: AudioStreamPlayer3D
var voice_audio: AudioStreamPlayer3D
var footsteps_audio: AudioStreamPlayer3D
var _elapsed: float = 0.0
var _knock_left: float = 0.0
var _voice_left: float = 0.0
var _voice_pending: bool = false
var _route: Array[Vector3] = []
var _departure: Array[Vector3] = []


func bind(value: Node3D) -> void:
	game = value
	game.hiding_changed.connect(_on_hiding_changed)
	for marker: Node3D in game.get_node("Apartment/PoliceRoute").get_children():
		_route.append(marker.global_position)
	_departure.assign(_route)
	_departure.reverse()
	_departure.append(game.room_door.get_node("Approach").global_position)


func _ready() -> void:
	visual = VISUAL.instantiate()
	add_child(visual)
	knock_audio = _audio(settings.knock_sound, settings.warning_volume_db)
	voice_audio = _audio(settings.warning_voice if settings.warning_voice != null else PoliceAudio.radio(), settings.warning_volume_db)
	footsteps_audio = _audio(settings.footsteps, settings.footsteps_volume_db)


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


func warning_started() -> void:
	visit = Visit.WARNING
	_elapsed = 0.0
	visual.global_position = _route[0]
	visual.hide()
	knock_audio.play()
	_knock_left = maxf(1.0, settings.knock_interval)
	_voice_left = maxf(0.0, settings.voice_delay)
	_voice_pending = true


func active_started() -> void:
	visit = Visit.SEARCHING
	_elapsed = 0.0
	_voice_pending = false
	knock_audio.stop()
	voice_audio.stop()
	game.room_door.set_open(true)
	if not game.is_hidden():
		game.fail_from_threat("POLICE_DEATH")
		return
	visual.show()
	visual.global_position = _route[0]
	footsteps_audio.pitch_scale = 1.0
	footsteps_audio.play()


func advance(delta: float) -> void:
	_elapsed += delta
	if visit == Visit.WARNING:
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
		if not game.is_hidden():
			game.fail_from_threat("POLICE_DEATH")
			return
		if not footsteps_audio.playing:
			footsteps_audio.play()
		if visit == Visit.SEARCHING:
			_move(_route, _elapsed / maxf(0.5, settings.search_seconds))
			if _elapsed >= settings.search_seconds:
				visit = Visit.DEPARTING
				_elapsed = 0.0
				voice_audio.stream = settings.departure_sound if settings.departure_sound != null else PoliceAudio.radio()
				voice_audio.play()
				footsteps_audio.pitch_scale = 1.15
		else:
			_move(_departure, _elapsed / maxf(0.5, settings.departure_seconds))
			if _elapsed >= settings.departure_seconds:
				resolved.emit(&"survived")


func _move(points: Array[Vector3], progress: float) -> void:
	var cursor := clampf(progress, 0.0, 1.0) * (points.size() - 1)
	var index := mini(int(cursor), points.size() - 2)
	var position := points[index].lerp(points[index + 1], cursor - index)
	if visual.global_position.distance_squared_to(position) > 0.0001:
		visual.look_at(position, Vector3.UP)
	visual.global_position = position


func _on_hiding_changed(hidden: bool) -> void:
	if not hidden and visit in [Visit.SEARCHING, Visit.DEPARTING]:
		game.fail_from_threat("POLICE_DEATH")


func resolved_started(outcome: StringName) -> void:
	ended(outcome)


func ended(_outcome: StringName) -> void:
	visit = Visit.DORMANT
	_voice_pending = false
	_elapsed = 0.0
	if is_instance_valid(visual):
		visual.hide()
	if is_instance_valid(knock_audio):
		knock_audio.stop()
	if is_instance_valid(voice_audio):
		voice_audio.stop()
		voice_audio.stream = settings.warning_voice if settings.warning_voice != null else PoliceAudio.radio()
	if is_instance_valid(footsteps_audio):
		footsteps_audio.stop()
