class_name ThreatAwareness
extends RefCounted
## Body-based sight, shared by visitors. Camera motion never changes exposure.
var suspicion: float = 0.0
var confirm_seconds: float = 1.0
var recovery_seconds: float = 2.0
var sight_range: float = 9.0
var half_angle: float = 65.0
var visible_now: bool = false
var close_distance: float = 1.0
var close_confirm_seconds: float = 0.25
var close_recovery_seconds: float = 0.25
var close_suspicion: float = 0.0
var close_now: bool = false


func reset() -> void:
	suspicion = 0.0
	visible_now = false
	close_suspicion = 0.0
	close_now = false


func advance_close(game: Node3D, observer: Node3D, delta: float) -> bool:
	# Warning protects distant players, not someone touching/circling the visitor.
	# No viewing cone here: the same short response applies from every direction.
	close_now = false
	var targets: Array[Vector3] = game.threat_target_points()
	if targets.is_empty():
		close_suspicion = 0.0
		return false
	var origin := observer.global_position + Vector3.UP * 1.65
	for target: Vector3 in targets:
		var offset := target - origin
		if Vector2(offset.x, offset.z).length() > close_distance or absf(offset.y) > 1.2:
			continue
		if clear_line(game, origin, target):
			close_now = true
			break
	var sample := clampf(delta, 0.0, 0.1)
	if close_now:
		close_suspicion = minf(1.0, close_suspicion + sample / maxf(0.05, close_confirm_seconds))
		_face_player(game, observer)
	else:
		close_suspicion = maxf(0.0, close_suspicion - maxf(0.0, delta) / maxf(0.05, close_recovery_seconds))
	return close_suspicion >= 0.99999


func _face_player(game: Node3D, observer: Node3D) -> void:
	var target: Vector3 = game.player.global_position
	target.y = observer.global_position.y
	if observer.global_position.distance_squared_to(target) > 0.001:
		observer.look_at(target, Vector3.UP)


func advance(game: Node3D, observer: Node3D, delta: float) -> bool:
	visible_now = false
	var origin := observer.global_position + Vector3.UP * 1.65
	for target: Vector3 in game.threat_target_points():
		var offset := target - origin
		if offset.length() > sight_range or offset.length_squared() < 0.0001:
			continue
		var horizontal_offset := Vector3(offset.x, 0, offset.z)
		var horizontal := horizontal_offset.normalized()
		# A player overlapping the visitor cannot hide inside its visual mesh.
		if horizontal_offset.length() > 0.45 and (-observer.global_basis.z).dot(horizontal) < cos(deg_to_rad(half_angle)):
			continue
		if clear_line(game, origin, target):
			visible_now = true
			break
	# A stalled render frame must not turn a single sight sample into a capture.
	var sample := minf(delta, 0.1)
	if visible_now:
		suspicion = minf(1.0, suspicion + sample / maxf(0.1, confirm_seconds))
		_face_player(game, observer)
	else:
		suspicion = maxf(0.0, suspicion - sample / maxf(0.1, recovery_seconds))
	var head := observer.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = -0.22 * suspicion
	return suspicion >= 0.99999


static func clear_line(game: Node3D, origin: Vector3, target: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(origin, target, 1, [game.player.get_rid()])
	return game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
