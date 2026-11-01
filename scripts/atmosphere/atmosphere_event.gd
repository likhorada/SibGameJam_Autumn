class_name AtmosphereEvent
extends Node
## A fresh instance is created for each start. Never require the player to notice it.
signal finished(outcome: StringName)


func start(_game: Node3D) -> bool:
	# Return false if setup cannot succeed. Cleanup is called even on failed setup.
	return false


func advance(_delta: float) -> void:
	pass


func ended(_outcome: StringName) -> void:
	# Implement idempotent cleanup: stop audio, restore changes, remove spawned nodes.
	pass
