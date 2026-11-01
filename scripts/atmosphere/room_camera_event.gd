extends AtmosphereEvent


func start(game: Node3D) -> bool:
	if not game.atmosphere.residents.show_room_camera():
		return false
	finished.emit(&"spawned")
	return true
