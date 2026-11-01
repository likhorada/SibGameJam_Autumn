class_name AmbientDirector
extends Node
## Pure audio direction: base hum, proximity hum, random apartment one-shots.
## Owns no gameplay logic; follows mode and power state reported by other systems.

const NOISE := preload("res://assets/audio/ambient_noise.wav")
const NEAR_NOISE := preload("res://assets/audio/ambient_noise2.wav")
const SUSPENSE := preload("res://assets/audio/creep_suspence.wav")
const EVENT_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/scratchin1.wav"),
	preload("res://assets/audio/scratchin2.wav"),
	preload("res://assets/audio/knock1.wav"),
	preload("res://assets/audio/knock2.wav"),
	preload("res://assets/audio/knock3.wav"),
]
## Volume treated as silence by the fade logic below.
const MUTE_DB: float = -60.0

@export_group("Base hum")
@export var noise_volume_db: float = -12.0
@export_group("Approach hum")
@export var near_volume_db: float = -6.0
@export_range(0.5, 12.0) var near_full_radius: float = 3.0
@export_range(1.0, 20.0) var near_mute_radius: float = 7.0
@export_range(0.05, 2.0) var fade_seconds: float = 0.35
@export_group("Random one-shots")
@export_range(0.0, 1.0) var random_chance: float = 0.075
@export_range(0.2, 120.0) var random_min_interval: float = 10.0
@export_range(0.2, 180.0) var random_max_interval: float = 20.0
@export var random_volume_db: float = -10.0
@export_group("Threat suspense")
@export var suspense_volume_db: float = -12.0

var game: Node3D
var powered: bool = true
var noise_audio: AudioStreamPlayer
var near_audio: AudioStreamPlayer
var event_audio: AudioStreamPlayer
var suspense_audio: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _event_left: float = 0.0


func bind(value: Node3D) -> void:
	game = value
	_rng.randomize()
	powered = game.power.powered
	game.power.power_changed.connect(_on_power_changed)
	game.threats.state_changed.connect(func(state: ThreatManager.State, _id: StringName):
		if state != ThreatManager.State.IDLE and is_instance_valid(event_audio):
			event_audio.stop())
	noise_audio = _make_player(NOISE)
	near_audio = _make_player(NEAR_NOISE)
	event_audio = AudioStreamPlayer.new()
	event_audio.bus = &"SFX"
	event_audio.volume_db = random_volume_db
	add_child(event_audio)
	suspense_audio = _make_player(SUSPENSE)
	suspense_audio.bus = &"Ambience"
	suspense_audio.volume_db = MUTE_DB
	_schedule_event()
	# Both loops start silent and are faded in by _process where appropriate.
	noise_audio.play()
	near_audio.play()


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = MUTE_DB
	add_child(player)
	return player


func _on_power_changed(value: bool) -> void:
	powered = value
	_schedule_event()


func _exit_tree() -> void:
	# Stop voices explicitly so abrupt teardown does not leak playing streams.
	stop_all()


func _schedule_event() -> void:
	_event_left = _rng.randf_range(random_min_interval, random_max_interval)


func _process(delta: float) -> void:
	if game == null:
		return
	var noise_target := noise_volume_db if powered else MUTE_DB
	if game.threats.is_busy():
		noise_target -= 10.0
	_fade(noise_audio, noise_target, delta, noise_volume_db)
	var near_target := _near_target_db()
	if game.threats.is_busy():
		near_target -= 10.0
	_fade(near_audio, near_target, delta, near_volume_db)
	var detection_in_progress: bool = is_instance_valid(game.threats.detected_audio) and game.threats.detected_audio.playing
	_fade(
		suspense_audio,
		suspense_volume_db if _is_hunting() and not detection_in_progress else MUTE_DB,
		delta,
		suspense_volume_db,
	)
	_tick_events(delta)


func _is_hunting() -> bool:
	if game.run_ended or not game.capture_reason.is_empty():
		return false
	if is_instance_valid(game.neighbor) and game.neighbor.visit == PsychNeighbor.Visit.CHASING:
		return true
	if is_instance_valid(game.police) and game.police.visit == PoliceRaid.Visit.CHASING:
		return true
	return (
		is_instance_valid(game.outage)
		and is_instance_valid(game.outage.entity)
		and game.outage.entity.phase == CorridorEntity.Phase.ACTIVE
		and game.outage.entity.is_chasing
	)


func _near_target_db() -> float:
	if not powered:
		return MUTE_DB
	var point: Node3D = game.terminal.get_node_or_null("MonitorView") as Node3D
	if point == null:
		point = game.terminal
	var distance: float = game.player.global_position.distance_to(point.global_position)
	var span: float = maxf(near_mute_radius - near_full_radius, 0.1)
	var strength: float = clampf(1.0 - (distance - near_full_radius) / span, 0.0, 1.0)
	return lerpf(MUTE_DB, near_volume_db, strength)


func _fade(player: AudioStreamPlayer, target_db: float, delta: float, top_db: float) -> void:
	if player == null:
		return
	# move_toward in dB keeps the fade linear and independent of current distance.
	var rate: float = maxf(top_db - MUTE_DB, 1.0) / maxf(fade_seconds, 0.05)
	player.volume_db = move_toward(player.volume_db, target_db, rate * delta)
	if target_db > MUTE_DB + 1.0 and not player.playing:
		player.play()
	elif target_db <= MUTE_DB + 1.0 and player.volume_db <= MUTE_DB + 1.0 and player.playing:
		player.stop()


func _tick_events(delta: float) -> void:
	if not powered or game == null or game.dev_menu.is_open:
		return
	if game.threats.is_busy():
		return
	if game.mode != game.Mode.WALKING:
		return
	_event_left -= delta
	if _event_left > 0.0:
		return
	_schedule_event()
	if _rng.randf() < random_chance and not event_audio.playing:
		event_audio.stream = EVENT_STREAMS[_rng.randi_range(0, EVENT_STREAMS.size() - 1)]
		event_audio.play()


func stop_all() -> void:
	powered = false
	for player: AudioStreamPlayer in [noise_audio, near_audio, event_audio, suspense_audio]:
		if player != null:
			player.stop()
