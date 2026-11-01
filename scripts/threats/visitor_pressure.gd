class_name VisitorPressure
extends RefCounted
## One optional listening stop per search; travel still uses the original time budget.
var used: bool = false
var holding: bool = false
var finished: bool = false
var movement_elapsed: float = 0.0
var hold_elapsed: float = 0.0
var hold_seconds: float = 4.0
var nervous: bool = false
var _attempted: bool = false
var _points: Array[Vector3] = []
var _duration: float = 6.0
var _distance: float = 0.0
var _length: float = 0.0
var _speed: float = 1.0
var _hold_distance: float = -1.0
var _hold_yaw: float = 0.0
var _arrival_yaw: float = 0.0
var _head: Node3D
var _head_rest := Vector3.ZERO


func reset(points: Array[Vector3] = [], seconds: float = 6.0, pause: float = 4.0, jittery: bool = false) -> void:
	_restore_head()
	_head = null
	_points.assign(points)
	_duration = maxf(0.1, seconds)
	hold_seconds = maxf(0.0, pause)
	nervous = jittery
	used = false
	holding = false
	finished = points.size() < 2
	movement_elapsed = 0.0
	hold_elapsed = 0.0
	_attempted = false
	_distance = 0.0
	_hold_distance = -1.0
	_length = _path_length(_points)
	_speed = _length / _duration


func advance(game: Node3D, visual: Node3D, delta: float) -> void:
	# Do not skip the optional stop when tests or a slow frame advance a large chunk.
	var remaining := maxf(0.0, delta)
	while remaining > 0.000001 and not finished:
		var step := minf(remaining, 0.05)
		_advance_step(game, visual, step)
		remaining -= step


func _advance_step(game: Node3D, visual: Node3D, delta: float) -> void:
	if finished or delta < 0.0:
		return
	# Begin the detour inside the apartment, after clearing the entrance leaf.
	# This also avoids querying the previous physics pose immediately after opening.
	var inside: bool = game.room_door.to_local(visual.global_position).x < -0.3
	if not _attempted and hold_seconds > 0.0 and game.is_hidden() and inside:
		_attempted = true
		_plan(game, visual)
	if not used:
		# Preserve the original waypoint timing until a hidden player adds a detour.
		movement_elapsed = minf(_duration, movement_elapsed + delta)
		var cursor := movement_elapsed / _duration * (_points.size() - 1)
		var segment := mini(int(cursor), _points.size() - 2)
		_distance = 0.0
		for index: int in range(segment):
			_distance += _points[index].distance_to(_points[index + 1])
		_distance += _points[segment].distance_to(_points[segment + 1]) * (cursor - segment)
		_place(visual)
		finished = movement_elapsed >= _duration - 0.000001
		return
	var remaining := delta
	while remaining > 0.000001 and not finished:
		if holding:
			var consumed := minf(remaining, maxf(0.0, hold_seconds - hold_elapsed))
			hold_elapsed += consumed
			remaining -= consumed
			_hold_pose(visual)
			if hold_elapsed >= hold_seconds - 0.000001:
				holding = false
				_hold_distance = -1.0
				_restore_head()
				if _distance >= _length - 0.00001:
					finished = true
			continue
		var endpoint := _hold_distance if _hold_distance >= 0.0 else _length
		var consumed := minf(remaining, maxf(0.0, endpoint - _distance) / maxf(0.001, _speed))
		_distance = minf(endpoint, _distance + consumed * _speed)
		movement_elapsed = minf(_duration, movement_elapsed + consumed)
		remaining -= consumed
		_place(visual)
		if _distance >= endpoint - 0.00001:
			if _hold_distance >= 0.0:
				holding = true
				_arrival_yaw = visual.rotation.y
				_head = visual.get_node_or_null("Head") as Node3D
				if _head != null:
					_head_rest = _head.rotation
				_hold_pose(visual)
			else:
				finished = true
		elif consumed <= 0.000001:
			break


func _plan(game: Node3D, visual: Node3D) -> void:
	var spot: HidingSpot = game.hiding_spot
	if spot.pressure_point == null or _points.size() < 4:
		return
	var time_left := _duration - movement_elapsed
	if time_left <= 0.1:
		return
	var segment := _segment_index()
	var checkpoint := spot.pressure_checkpoint
	var candidate: Array[Vector3] = [visual.global_position]
	var hold_index: int = -1
	if checkpoint <= segment:
		# Return through the bedroom doorway rather than cutting through its wall.
		if segment >= 2:
			_append(candidate, _points[2])
		_append(candidate, _points[1])
		hold_index = _append(candidate, spot.pressure_point.global_position)
		_append(candidate, _points[1])
		if segment >= 2:
			_append(candidate, _points[2])
	for index: int in range(segment + 1, _points.size()):
		_append(candidate, _points[index])
		if index == checkpoint:
			hold_index = _append(candidate, spot.pressure_point.global_position)
			_append(candidate, _points[index])
	if hold_index < 0:
		return
	var length := _path_length(candidate)
	# Late hiding must not make a visitor teleport or sprint unnaturally across rooms.
	if length / time_left > 2.8 or not _clear_path(game, candidate):
		return
	_points.assign(candidate)
	_length = length
	_distance = 0.0
	_speed = length / time_left
	_hold_distance = 0.0
	for index: int in range(hold_index):
		_hold_distance += _points[index].distance_to(_points[index + 1])
	_hold_yaw = spot.pressure_point.global_rotation.y
	used = true


func _place(visual: Node3D) -> void:
	var left := _distance
	for index: int in range(_points.size() - 1):
		var length := _points[index].distance_to(_points[index + 1])
		if left <= length + 0.00001 or index == _points.size() - 2:
			var position := _points[index].lerp(_points[index + 1], clampf(left / maxf(0.0001, length), 0, 1))
			if position.distance_squared_to(visual.global_position) > 0.000001:
				visual.look_at(position, Vector3.UP)
			visual.global_position = position
			return
		left -= length


func _hold_pose(visual: Node3D) -> void:
	visual.rotation.y = lerp_angle(_arrival_yaw, _hold_yaw, smoothstep(0, 0.45, hold_elapsed))
	if not is_instance_valid(_head):
		return
	var t := clampf(hold_elapsed / maxf(0.01, hold_seconds), 0, 1)
	var angle: float
	if nervous:
		angle = _sample(t, [0, 0.12, 0.26, 0.32, 0.65, 0.69, 0.86, 1], [0, -15, -15, 30, 30, -35, -35, 0])
	else:
		angle = _sample(t, [0, 0.2, 0.6, 0.68, 1], [0, 20, 20, -26, 0])
	_head.rotation = _head_rest + Vector3(0.025 * sin(t * TAU), deg_to_rad(angle), deg_to_rad(angle * (0.15 if nervous else 0.05)))


func _restore_head() -> void:
	if is_instance_valid(_head):
		_head.rotation = _head_rest


func _segment_index() -> int:
	var left := _distance
	for index: int in range(_points.size() - 1):
		var length := _points[index].distance_to(_points[index + 1])
		if left < length - 0.00001:
			return index
		left -= length
	return _points.size() - 2


static func _append(points: Array[Vector3], position: Vector3) -> int:
	if points.is_empty() or points.back().distance_squared_to(position) > 0.000001:
		points.append(position)
	return points.size() - 1


static func _path_length(points: Array[Vector3]) -> float:
	var length := 0.0
	for index: int in range(points.size() - 1):
		length += points[index].distance_to(points[index + 1])
	return length


static func _sample(t: float, times: Array, values: Array) -> float:
	for index: int in range(times.size() - 1):
		if t <= float(times[index + 1]):
			return lerpf(values[index], values[index + 1], smoothstep(times[index], times[index + 1], t))
	return values.back()


static func _clear_path(game: Node3D, points: Array[Vector3]) -> bool:
	var shape := CapsuleShape3D.new()
	shape.height = 1.9
	shape.radius = 0.23
	for index: int in range(points.size() - 1):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = points[index] + Vector3.UP
		query.motion = points[index + 1] - points[index]
		query.collision_mask = 1
		query.exclude = [game.player.get_rid()]
		var space := game.get_world_3d().direct_space_state
		if not space.intersect_shape(query).is_empty() or space.cast_motion(query)[0] < 0.999:
			return false
	return true
