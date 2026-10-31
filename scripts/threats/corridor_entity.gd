class_name CorridorEntity
extends Node3D
## Driven only by PowerOutage's clock. No collision, pursuit or navigation.
enum Phase { DORMANT, WAITING, WARNING, ACTIVE }
const VISUAL := preload("res://scenes/threats/corridor_entity.tscn")
var settings: CorridorEntityConfig
var game: Node3D
var phase: Phase = Phase.DORMANT
var visual: Node3D
var warning_audio: AudioStreamPlayer3D
var footsteps_audio: AudioStreamPlayer3D
var departure_audio: AudioStreamPlayer3D
var error_seconds: float = 0.0
var repeat_left: float = 0.0
var duration: float = 0.0
var elapsed: float = 0.0
var _from: Vector3
var _to: Vector3
var _last_player_position: Vector3
var _zone: Area3D
var _routes: Node3D
var _rng := RandomNumberGenerator.new()


func bind(value: Node3D) -> void:
	game = value
	_zone = game.get_node("Apartment/CorridorEncounters/Zone")
	_routes = game.get_node("Apartment/CorridorEncounters/Routes")


func _ready() -> void:
	_rng.randomize()
	visual = VISUAL.instantiate()
	add_child(visual)
	warning_audio = _audio(settings.warning_sound)
	warning_audio.pitch_scale = settings.warning_pitch
	footsteps_audio = _audio(settings.footsteps)
	departure_audio = _audio(settings.departure_sound)


func _audio(stream: AudioStream) -> AudioStreamPlayer3D:
	var audio := AudioStreamPlayer3D.new()
	audio.bus = &"SFX"
	audio.stream = stream
	audio.unit_size = 6.0
	audio.max_distance = 18.0
	audio.volume_db = settings.volume_db
	visual.add_child(audio)
	audio.position.y = 1.2
	return audio


func start() -> void:
	stop()
	phase = Phase.WAITING
	repeat_left = 0.0
	_last_player_position = game.player.global_position


func in_corridor() -> bool:
	var shape: BoxShape3D = _zone.get_node("Shape").shape
	return AABB(-shape.size * 0.5, shape.size).has_point(_zone.to_local(game.player.global_position))


func advance(delta: float) -> void:
	if phase == Phase.DORMANT:
		return
	if game.power.powered or game.run_ended:
		stop()
		return
	var position: Vector3 = game.player.global_position
	var displacement := position - _last_player_position
	displacement.y = 0.0
	_last_player_position = position
	if phase == Phase.WAITING:
		repeat_left = maxf(0.0, repeat_left - delta)
		if repeat_left <= 0.0 and in_corridor() and game.mode in [game.Mode.WALKING, game.Mode.FUSEBOX, game.Mode.FUSEBOX_ENTERING, game.Mode.FUSEBOX_LEAVING] and not game.dev_menu.is_open:
			_try_encounter()
		return
	if phase == Phase.WARNING:
		elapsed += delta
		if elapsed >= settings.warning_seconds:
			phase = Phase.ACTIVE
			elapsed = 0.0
			duration = _rng.randf_range(maxf(0.5, settings.min_encounter_seconds), maxf(settings.min_encounter_seconds, settings.max_encounter_seconds))
			warning_audio.stop()
			footsteps_audio.play()
		return
	var consumed := minf(delta, maxf(0.0, duration - elapsed))
	elapsed += consumed
	visual.global_position = _from.lerp(_to, clampf(elapsed / duration, 0.0, 1.0))
	if not footsteps_audio.playing:
		footsteps_audio.play()
	var distance := Vector2(position.x - visual.global_position.x, position.z - visual.global_position.z).length()
	var moving: bool = game.mode == game.Mode.WALKING and displacement.length() / maxf(delta, 0.001) > settings.movement_threshold
	if in_corridor() and distance <= settings.near_radius and (moving or beam_hits()):
		error_seconds += consumed
		if error_seconds + 0.000001 >= settings.error_budget_seconds:
			game.fail_from_threat("ENTITY_DEATH")
			return
	if elapsed >= duration:
		visual.hide()
		footsteps_audio.stop()
		departure_audio.play()
		phase = Phase.WAITING
		repeat_left = _rng.randf_range(maxf(1.0, settings.min_repeat_seconds), maxf(settings.min_repeat_seconds, settings.max_repeat_seconds))


func _try_encounter() -> bool:
	var candidates: Array[Vector3] = []
	var destinations: Array[Vector3] = []
	for route: Node3D in _routes.get_children():
		var a: Vector3 = route.get_node("A").global_position
		var b: Vector3 = route.get_node("B").global_position
		for reversed: bool in [false, true]:
			var origin := b if reversed else a
			var target := a if reversed else b
			var distance := origin.distance_to(game.player.global_position)
			if distance >= settings.min_spawn_distance and distance <= settings.max_spawn_distance and _clear_spawn(origin):
				candidates.append(origin)
				destinations.append(target)
	if candidates.is_empty():
		return false
	var index := _rng.randi_range(0, candidates.size() - 1)
	_from = candidates[index]
	_to = destinations[index]
	visual.global_position = _from
	visual.look_at(_to, Vector3.UP)
	visual.show()
	phase = Phase.WARNING
	elapsed = 0.0
	error_seconds = 0.0
	departure_audio.stop()
	warning_audio.play()
	return true


func _clear_spawn(origin: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 2.2, 0.55)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = origin + Vector3(0, 1.2, 0)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(query).is_empty()


func beam_hits() -> bool:
	if not game.power.flashlight_on:
		return false
	game.power.update_flashlight()
	for light: SpotLight3D in [game.power.flashlight, game.power.flashlight_spill]:
		for height: float in [1.2, 0.35]:
			var target := visual.global_position + Vector3.UP * height
			var ray := target - light.global_position
			if ray.length() > light.spot_range or ray.length_squared() < 0.0001:
				continue
			if (-light.global_basis.z).dot(ray.normalized()) < cos(deg_to_rad(light.spot_angle)):
				continue
			var query := PhysicsRayQueryParameters3D.create(light.global_position, target, 1, [game.player.get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				return true
	return false


func stop() -> void:
	phase = Phase.DORMANT
	error_seconds = 0.0
	repeat_left = 0.0
	if is_instance_valid(visual):
		visual.hide()
	for audio: AudioStreamPlayer3D in [warning_audio, footsteps_audio, departure_audio]:
		if is_instance_valid(audio):
			audio.stop()
