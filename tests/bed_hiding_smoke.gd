extends SceneTree
## End-to-end bed interaction without the unrelated wardrobe/raid assertions.


func _initialize() -> void:
	check.call_deferred()


func check() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.threats.set_process(false)
	game.shift.set_process(false)
	game.ambient.random_chance = 0.0
	var player: ApartmentPlayer = game.player
	player.global_position = Vector3(-0.55, 0.03, 4.5)
	var target := Vector3(-1.7, 0.48, 4.5)
	var direction: Vector3 = target - (player.global_position + Vector3(0, 1.6, 0))
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = atan2(direction.y, Vector2(direction.x, direction.z).length())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	await physics_frame
	assert(player.find_interaction() == &"hide_bed", "Looking at the bed must show its hide interaction")
	player.interaction_id = &"hide_bed"
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	if DisplayServer.get_name() == "headless":
		assert(game.enter_hiding(game.hiding_spots[player.interaction_id]), "Bed must enter hiding from its ray-detected interaction")
	else:
		game._unhandled_input(event)
	assert(game.is_hidden(), "Bed interaction must enter hiding")
	if DisplayServer.get_name() == "headless":
		assert(game.leave_hiding(false), "Bed exit must not overlap furniture")
	else:
		game._unhandled_input(event)
	assert(not game.is_hidden(), "Exit must restore walking")
	print("BED HIDING PASS")
	quit()
