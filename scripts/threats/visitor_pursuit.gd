class_name VisitorPursuit
extends RefCounted
## Lightweight waypoint pursuit shared by the police and neighbor visitors.

const SPEED: float = 3.2
const BODY_HEIGHT: float = 1.9
const BODY_RADIUS: float = 0.23
var _body_shape := CapsuleShape3D.new()


func _init() -> void:
	_body_shape.height = BODY_HEIGHT
	_body_shape.radius = BODY_RADIUS


func advance(game: Node3D, visual: Node3D, route: Array[Vector3], delta: float) -> void:
	if game.is_hidden():
		return
	var start := visual.global_position
	var destination: Vector3 = game.player.global_position
	destination.y = start.y
	var points: Array[Vector3] = [start]
	for waypoint: Vector3 in route:
		var point := waypoint
		point.y = start.y
		if point.distance_squared_to(points.back()) > 0.01 and not _contains_point(points, point):
			points.append(point)
	if destination.distance_squared_to(start) <= 0.0001:
		return
	points.append(destination)

	var path := _shortest_path(game, points)
	if path.size() < 2:
		return
	var remaining := SPEED * maxf(0.0, delta)
	for path_index: int in range(1, path.size()):
		var target: Vector3 = points[path[path_index]]
		var offset := target - visual.global_position
		var distance := offset.length()
		if distance <= 0.0001:
			continue
		var step := minf(remaining, distance)
		visual.look_at(Vector3(target.x, visual.global_position.y, target.z), Vector3.UP)
		visual.global_position += offset / distance * step
		remaining -= step
		if remaining <= 0.0001:
			break


func _shortest_path(game: Node3D, points: Array[Vector3]) -> Array[int]:
	var count := points.size()
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for index: int in count:
		distances.append(INF)
		previous.append(-1)
		visited.append(false)
	distances[0] = 0.0

	for _step: int in count:
		var current := -1
		for index: int in count:
			if not visited[index] and (current < 0 or distances[index] < distances[current]):
				current = index
		if current < 0 or is_inf(distances[current]):
			break
		if current == count - 1:
			break
		visited[current] = true
		for neighbor: int in count:
			if neighbor == current or visited[neighbor]:
				continue
			if not _clear_segment(game, points[current], points[neighbor]):
				continue
			var candidate := distances[current] + points[current].distance_to(points[neighbor])
			if candidate < distances[neighbor]:
				distances[neighbor] = candidate
				previous[neighbor] = current

	if is_inf(distances[count - 1]):
		return []
	var path: Array[int] = []
	var cursor := count - 1
	while cursor >= 0:
		path.push_front(cursor)
		if cursor == 0:
			break
		cursor = previous[cursor]
	if path.front() != 0:
		return []
	return path


func _clear_segment(game: Node3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body_shape
	query.transform.origin = from + Vector3.UP
	query.motion = to - from
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999


func _contains_point(points: Array[Vector3], point: Vector3) -> bool:
	for existing: Vector3 in points:
		if existing.distance_squared_to(point) <= 0.01:
			return true
	return false
