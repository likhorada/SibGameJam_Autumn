extends AtmosphereEvent


func start(game: Node3D) -> bool:
	if not game.atmosphere.residents.place_figure():
		return false
	finished.emit(&"spawned")
	return true
