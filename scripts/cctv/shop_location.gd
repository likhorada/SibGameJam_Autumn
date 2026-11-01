extends ObservationLocation

@export var drink_paths: Array[NodePath] = [^"Drinks/Tea", ^"Drinks/Coffee", ^"Drinks/Wine", ^"Drinks/Soda"]
var drink: int = 0


func _ready() -> void:
	super._ready()
	for path: NodePath in drink_paths:
		var item := get_node_or_null(path)
		if item != null:
			item.get_node("Name").text = tr(item.get_node("Name").text).replace(" ", "\n")


func set_drink(value: int) -> void:
	drink = value


func event(id: String) -> void:
	if id == "take" and drink >= 0 and drink < drink_paths.size():
		bottle = get_node_or_null(drink_paths[drink]) as Node3D
		if bottle != null:
			bottle.reparent(target)
			bottle.position = Vector3(0.5, 0.7, 0.25)
	elif id == "checkout" and is_instance_valid(bottle):
		bottle.reparent(self)
		bottle.position = Vector3(0.5, 1.3, 2.3)
