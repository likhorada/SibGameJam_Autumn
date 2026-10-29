extends SceneTree
## Explicit opt-in only! Overwrites apartment.tscn, including hand-edited geometry.
## godot --headless --path . --script res://tools/bake_apartment.gd


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var apartment: Node3D = load("res://scenes/apartment/apartment.tscn").instantiate()
	# Preserve the environment; rebuild the layout from its source.
	for child: Node in apartment.get_children():
		if child is not WorldEnvironment:
			apartment.remove_child(child)
			child.free()
	apartment.set_script(load("res://tools/apartment_layout.gd"))
	root.add_child(apartment)
	apartment.set_script(null)
	_assign_owner(apartment, apartment)
	var packed := PackedScene.new()
	var error := packed.pack(apartment)
	if error == OK:
		error = ResourceSaver.save(packed, "res://scenes/apartment/apartment.tscn")
	print("Apartment bake: ", error_string(error))
	apartment.free()
	quit(0 if error == OK else 1)


func _assign_owner(node: Node, scene_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_root
		_assign_owner(child, scene_root)
