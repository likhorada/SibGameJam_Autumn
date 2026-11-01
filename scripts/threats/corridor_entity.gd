class_name CorridorEntity
extends CharacterBody3D
## Driven by PowerOutage's encounter clock; pursuit uses the physics collision body.
enum Phase { DORMANT, WAITING, WARNING, ACTIVE, RETREATING }
const VISUAL := preload("res://scenes/threats/corridor_entity.tscn")
const SPILL_HIT_RANGE: float = 2.2
const SPILL_HIT_ANGLE: float = 70.0
const COLLISION_RADIUS: float = 0.2
const COLLISION_HEIGHT: float = 2.1
var settings: CorridorEntityConfig
var game: Node3D
var phase: Phase = Phase.DORMANT
var is_chasing: bool = false
var visual: Node3D
var warning_audio: AudioStreamPlayer3D
var footsteps_audio: AudioStreamPlayer3D
var departure_audio: AudioStreamPlayer3D
var chase_audio: AudioStreamPlayer3D
var error_seconds: float = 0.0
var repeat_left: float = 0.0
var duration: float = 0.0
var elapsed: float = 0.0
var _from: Vector3
var _to: Vector3
var _last_player_position: Vector3
var _collision_shape: CollisionShape3D
var _zone: Area3D
var _routes: Node3D
var _rng := RandomNumberGenerator.new()
var warning_duration: float = 2.0
var chase_elapsed: float = 0.0
var _retreat_elapsed: float = 0.0


func bind(value: Node3D) -> void:
	game = value
	_zone = game.get_node("Apartment/CorridorEncounters/Zone")
	_routes = game.get_node("Apartment/CorridorEncounters/Routes")


func _ready() -> void:
	_rng.randomize()
	collision_layer = 0
	collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.radius = COLLISION_RADIUS
	capsule.height = COLLISION_HEIGHT
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "PursuitCollision"
	_collision_shape.position.y = COLLISION_HEIGHT * 0.5
	_collision_shape.shape = capsule
	add_child(_collision_shape)
	visual = VISUAL.instantiate()
	add_child(visual)
	warning_audio = _audio(settings.warning_sound)
	warning_audio.pitch_scale = settings.warning_pitch
	footsteps_audio = _audio(settings.footsteps)
	departure_audio = _audio(settings.departure_sound)
	chase_audio = _audio(settings.chase_sound)


func _physics_process(delta: float) -> void:
	if game.run_ended or not game.capture_reason.is_empty():
		return
	if phase == Phase.ACTIVE:
		if is_chasing:
			_pursue_player(delta)
		else:
			var destination := _from.lerp(_to, clampf(elapsed / maxf(duration, 0.1), 0.0, 1.0))
			var motion := destination - global_position
			# Walking routes also respect walls and the player; no position warps.
			move_and_collide(motion.limit_length(2.5 * delta))
	elif phase == Phase.RETREATING:
		var direction: Vector3 = global_position - game.player.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			visual.look_at(global_position + direction, Vector3.UP)
			move_and_collide(direction.normalized() * 1.5 * delta)


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
	if not game.capture_reason.is_empty():
		return
	if phase == Phase.RETREATING:
		_retreat_elapsed += delta
		visual.scale = Vector3.ONE * (1.0 - clampf(_retreat_elapsed / maxf(0.2, settings.retreat_seconds), 0.0, 1.0))
		if _retreat_elapsed >= settings.retreat_seconds:
			_finish_departure()
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
		if elapsed >= warning_duration:
			phase = Phase.ACTIVE
			elapsed = 0.0
			duration = _rng.randf_range(maxf(0.5, settings.min_encounter_seconds), maxf(settings.min_encounter_seconds, settings.max_encounter_seconds))
			warning_audio.stop()
			footsteps_audio.play()
		return
	if is_chasing:
		chase_elapsed += delta
		if chase_elapsed >= settings.chase_seconds:
			_begin_departure()
		return
	var consumed := minf(delta, maxf(0.0, duration - elapsed))
	elapsed += consumed
	if not footsteps_audio.playing:
		footsteps_audio.play()
	var distance := Vector2(position.x - visual.global_position.x, position.z - visual.global_position.z).length()
	var moving: bool = game.mode == game.Mode.WALKING and displacement.length() / maxf(delta, 0.001) > settings.movement_threshold
	var exposed: bool = not game.is_hidden() and distance <= settings.near_radius and ThreatAwareness.clear_line(game, global_position + Vector3.UP * 1.2, position + Vector3.UP * 1.0)
	if exposed and (moving or beam_hits()):
		error_seconds = minf(settings.error_budget_seconds, error_seconds + minf(consumed, 0.1))
		if error_seconds + 0.000001 >= settings.error_budget_seconds:
			error_seconds = settings.error_budget_seconds
			is_chasing = true
			chase_elapsed = 0.0
			velocity = Vector3.ZERO
			footsteps_audio.pitch_scale = 1.3
			if chase_audio.stream != null:
				chase_audio.play()
	else:
		error_seconds = maxf(0.0, error_seconds - consumed * settings.error_budget_seconds / maxf(0.1, settings.error_recovery_seconds))
	if error_seconds > 0.0:
		var target := Vector3(position.x, global_position.y, position.z)
		if target.distance_squared_to(global_position) > 0.001:
			visual.look_at(target, Vector3.UP)
		visual.rotation.z = 0.15 * error_seconds / settings.error_budget_seconds
	else:
		visual.rotation.z = 0.0
	if elapsed >= duration and not is_chasing:
		_begin_departure()


func _pursue_player(delta: float) -> void:
	if game.is_hidden():
		_begin_departure()
		return
	var player_position: Vector3 = game.player.global_position
	var to_player := player_position - global_position
	to_player.y = 0.0
	if _touching_player():
		game.begin_threat_capture("ENTITY_DEATH", visual)
		return
	if to_player.length_squared() < 0.0001:
		return
	visual.look_at(Vector3(player_position.x, global_position.y, player_position.z), Vector3.UP)
	velocity = to_player.normalized() * settings.pursuit_speed
	var collision := move_and_collide(velocity * delta)
	velocity = Vector3.ZERO
	if collision != null and collision.get_collider() == game.player:
		game.begin_threat_capture("ENTITY_DEATH", visual)
		return
	if _touching_player():
		game.begin_threat_capture("ENTITY_DEATH", visual)


func _touching_player() -> bool:
	if game.is_hidden() or not game.capture_reason.is_empty():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_shape.shape
	query.transform = _collision_shape.global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query):
		if hit.get("collider") == game.player:
			return true
	return false


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
			if distance >= settings.min_spawn_distance and distance <= settings.max_spawn_distance and _clear_spawn(origin) and _clear_route(origin, target) and ThreatAwareness.clear_line(game, origin + Vector3.UP * 1.2, game.player.global_position + Vector3.UP * 1.2):
				candidates.append(origin)
				destinations.append(target)
	if candidates.is_empty():
		return false
	var index := _rng.randi_range(0, candidates.size() - 1)
	_from = candidates[index]
	_to = destinations[index]
	global_position = _from
	visual.scale = Vector3.ONE
	visual.rotation.z = 0.0
	visual.look_at(_to, Vector3.UP)
	visual.show()
	phase = Phase.WARNING
	elapsed = 0.0
	error_seconds = 0.0
	is_chasing = false
	chase_elapsed = 0.0
	warning_duration = settings.warning_seconds
	if game.prepare_for_threat():
		warning_duration += settings.forced_exit_warning_bonus
	_last_player_position = game.player.global_position
	footsteps_audio.pitch_scale = 1.0
	departure_audio.stop()
	warning_audio.play()
	if is_instance_valid(game.visual_effects):
		game.visual_effects.trigger_scare()
	return true


func _clear_route(origin: Vector3, target: Vector3) -> bool:
	# Check the complete capsule sweep against architecture, not just the spawn.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_shape.shape
	query.transform.origin = origin + Vector3.UP * COLLISION_HEIGHT * 0.5
	query.motion = target - origin
	query.collision_mask = 1
	query.exclude = [get_rid(), game.player.get_rid()]
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return fractions[0] >= 0.999


func _begin_departure() -> void:
	phase = Phase.RETREATING
	is_chasing = false
	velocity = Vector3.ZERO
	_retreat_elapsed = 0.0
	footsteps_audio.pitch_scale = 0.85
	chase_audio.stop()
	departure_audio.play()


func _finish_departure() -> void:
	visual.hide()
	visual.scale = Vector3.ONE
	visual.rotation.z = 0.0
	footsteps_audio.stop()
	phase = Phase.WAITING
	repeat_left = _rng.randf_range(maxf(1.0, settings.min_repeat_seconds), maxf(settings.min_repeat_seconds, settings.max_repeat_seconds))


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
	if _light_hits(game.power.flashlight, game.power.flashlight.spot_range, game.power.flashlight.spot_angle):
		return true
	return _light_hits(game.power.flashlight_spill, SPILL_HIT_RANGE, SPILL_HIT_ANGLE)


func _light_hits(light: SpotLight3D, max_range: float, angle: float) -> bool:
	for height: float in [1.2, 0.35]:
		var target := visual.global_position + Vector3.UP * height
		var ray := target - light.global_position
		if ray.length() > max_range or ray.length_squared() < 0.0001:
			continue
		if (-light.global_basis.z).dot(ray.normalized()) < cos(deg_to_rad(angle)):
			continue
		var query := PhysicsRayQueryParameters3D.create(light.global_position, target, 1, [game.player.get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false


func stop() -> void:
	phase = Phase.DORMANT
	error_seconds = 0.0
	repeat_left = 0.0
	is_chasing = false
	chase_elapsed = 0.0
	velocity = Vector3.ZERO
	if is_instance_valid(visual):
		visual.hide()
		visual.scale = Vector3.ONE
		visual.rotation.z = 0.0
	for audio: AudioStreamPlayer3D in [warning_audio, footsteps_audio, departure_audio, chase_audio]:
		if is_instance_valid(audio):
			audio.stop()
