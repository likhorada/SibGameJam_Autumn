extends SceneTree
## Isolated geometry regression: does not load the observation shift or main scene.


func _initialize() -> void:
	check.call_deferred()


func check() -> void:
	var apartment: Node3D = load("res://scenes/apartment/apartment.tscn").instantiate()
	root.add_child(apartment)
	var player: ApartmentPlayer = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.global_position = Vector3(-0.55, 0.03, 4.5)
	await physics_frame
	await physics_frame
	var target := Vector3(-1.7, 0.48, 4.5)
	var start := player.camera.global_position
	var end := start + (target - start).normalized() * player.interaction_distance
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 1, [player.get_rid()]))
	assert(not hit.is_empty() and hit.collider.get_meta("interaction", &"") == &"hide_bed", "Bed must be reachable with the interaction ray")
	var spot: HidingSpot = apartment.get_node("HidingSpots/Bed")
	assert(spot.view.global_position.y < hit.position.y, "Hiding camera must be below the mattress collision")
	assert(spot.find_safe_exit(player, player.global_transform) != null, "At least one bed exit must fit the standing capsule")
	var routes: Node3D = apartment.get_node("CorridorEncounters/Routes")
	assert(routes.get_child_count() == 1, "No route may start by the fusebox")
	var origin: Vector3 = routes.get_child(0).get_node("A").global_position
	var destination: Vector3 = routes.get_child(0).get_node("B").global_position
	assert(origin.z > 5.0 and destination.z < origin.z and is_zero_approx(origin.y), "Monster route must start on the far-end floor")
	var floor_hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.2, origin - Vector3.UP * 0.3))
	assert(not floor_hit.is_empty() and absf(floor_hit.position.y) < 0.05, "Corridor floor must support the spawn")
	var capsule := CapsuleShape3D.new()
	capsule.radius = CorridorEntity.COLLISION_RADIUS
	capsule.height = CorridorEntity.COLLISION_HEIGHT
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = capsule
	sweep.transform.origin = origin + Vector3.UP * (CorridorEntity.COLLISION_HEIGHT * 0.5 + 0.03)
	sweep.motion = destination - origin
	sweep.collision_mask = 1
	sweep.exclude = [player.get_rid()]
	assert(player.get_world_3d().direct_space_state.cast_motion(sweep)[0] >= 0.999, "Far-end route must be clear for the monster capsule")
	print("APARTMENT GEOMETRY PASS")
	quit()
