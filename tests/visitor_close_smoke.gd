extends SceneTree


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/visitor_close_checks.gd").new())
