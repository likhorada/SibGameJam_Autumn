extends ObservationLocation
## The authored shop is shared by the shift, CCTV sandbox and menu background.
## Only ShiftDirector advances the route; simply instancing the shop never starts a run.

const DATA := preload("res://data/observation/shift.gd")
@export var drink_paths: Array[NodePath] = [^"Drinks/Wine", ^"Drinks/Gin", ^"Drinks/Vodka"]
@export var checkout_path: NodePath = ^"CheckoutItem"
var drink: int = 0


func _ready() -> void:
	super._ready()
	for index: int in drink_paths.size():
		var item: Node3D = get_node(drink_paths[index])
		item.set_meta(&"evidence_id", DATA.DRINKS[index])
	set_drink(drink)


func set_drink(value: int) -> void:
	assert(value >= 0 and value < drink_paths.size(), "Unknown shop drink")
	drink = value
	var item: Node3D = get_node(drink_paths[drink])
	# Right wrist is 0.21 m to the actor's right when facing the shelf (-Z).
	# These are actual scene waypoints, not a second hidden route in the presentation.
	for name: String in ["Approach", "Browse", "Shelf", "Pickup"]:
		get_node("Route/" + name).position.x = item.position.x - 0.21


func event(id: String) -> void:
	if id == "take":
		bottle = get_node(drink_paths[drink]) as Node3D
		$Target/Guy.pick_up(bottle, Vector3(0, -0.24, 0))
		$Target/Guy.face_direction(-global_basis.z)
	elif id == "checkout" and is_instance_valid(bottle):
		$Target/Guy.put_down(self, get_node(checkout_path).position)
		$Target/Guy.face_direction(-global_basis.z)
