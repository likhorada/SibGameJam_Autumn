extends SceneTree


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/outage_checks.gd").new())
