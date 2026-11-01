extends SceneTree


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/threat_visual_checks.gd").new())
