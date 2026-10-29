extends Node3D
## Source for tools/bake_apartment.gd, not a runtime script.
## Disposable greybox geometry. Replace props with artist-owned scenes later.
## Coordinates and openings are intentionally explicit for collision review.

const WALL_HEIGHT := 2.8

var plaster: StandardMaterial3D
var floor_material: StandardMaterial3D
var dark_wood: StandardMaterial3D
var porcelain: StandardMaterial3D
var metal: StandardMaterial3D


func _ready() -> void:
	plaster = _material(Color(0.34, 0.35, 0.28))
	floor_material = _material(Color(0.22, 0.19, 0.15))
	dark_wood = _material(Color(0.19, 0.12, 0.075))
	porcelain = _material(Color(0.55, 0.56, 0.47))
	metal = _material(Color(0.19, 0.23, 0.21))
	_build_rooms()
	_build_props()
	_light("RoomLight", Vector3(0, 2.55, 0), Color(1.0, 0.78, 0.48), 1.1, 5.5)
	_light("BedroomLight", Vector3(0, 2.5, 5), Color(0.82, 0.68, 0.49), 0.6, 3.5)
	_light("BathroomLight", Vector3(-4.5, 2.5, -1), Color(0.65, 0.82, 0.73), 0.8, 3.5)
	_light("CorridorLight", Vector3(4.2, 2.5, 1.5), Color(0.65, 0.72, 0.48), 0.55, 5.0)
	_light("FuseboxLight", Vector3(4.2, 2.3, -6), Color(0.68, 0.76, 0.57), 0.4, 3.0)


func _build_rooms() -> void:
	# Main room: x -3..3, z -3..3. Bedroom behind the seated player.
	_room_slabs("Main", Vector3(0, 0, 0), Vector2(6, 6))
	_wall("North", Vector3(0, 1.4, -3), Vector3(6.2, WALL_HEIGHT, 0.2))
	_wall("SouthLeft", Vector3(-1.2, 1.4, 3), Vector3(3.6, WALL_HEIGHT, 0.2))
	_wall("SouthRight", Vector3(2.4, 1.4, 3), Vector3(1.2, WALL_HEIGHT, 0.2))
	_lintel("BedroomLintel", Vector3(1.2, 2.5, 3), Vector3(1.2, 0.6, 0.2))
	# West opening to the private bathroom: z -1.1..0.1.
	_wall("WestNorth", Vector3(-3, 1.4, -2.05), Vector3(0.2, WALL_HEIGHT, 1.9))
	_wall("WestSouth", Vector3(-3, 1.4, 1.55), Vector3(0.2, WALL_HEIGHT, 2.9))
	_lintel("BathroomLintel", Vector3(-3, 2.5, -0.5), Vector3(0.2, 0.6, 1.2))
	# East opening to the communal corridor: z 0.4..1.8.
	_wall("EastNorth", Vector3(3, 1.4, -1.3), Vector3(0.2, WALL_HEIGHT, 3.4))
	_wall("EastSouth", Vector3(3, 1.4, 2.4), Vector3(0.2, WALL_HEIGHT, 1.2))
	_lintel("CorridorLintel", Vector3(3, 2.5, 1.1), Vector3(0.2, 0.6, 1.4))

	_room_slabs("Bedroom", Vector3(0, 0, 4.8), Vector2(6, 3.6))
	_wall("BedroomBack", Vector3(0, 1.4, 6.6), Vector3(6.2, WALL_HEIGHT, 0.2))
	_wall("BedroomWest", Vector3(-3, 1.4, 4.8), Vector3(0.2, WALL_HEIGHT, 3.6))
	_wall("BedroomEast", Vector3(3, 1.4, 4.8), Vector3(0.2, WALL_HEIGHT, 3.6))

	_room_slabs("Bathroom", Vector3(-4.5, 0, -1.1), Vector2(3, 3.8))
	_wall("BathroomWest", Vector3(-6, 1.4, -1.1), Vector3(0.2, WALL_HEIGHT, 4))
	_wall("BathroomNorth", Vector3(-4.5, 1.4, -3), Vector3(3, WALL_HEIGHT, 0.2))
	_wall("BathroomSouth", Vector3(-4.5, 1.4, 0.8), Vector3(3, WALL_HEIGHT, 0.2))

	_room_slabs("Corridor", Vector3(4.2, 0, 0), Vector2(2.4, 14))
	_wall("CorridorEast", Vector3(5.4, 1.4, 0), Vector3(0.2, WALL_HEIGHT, 14.2))
	_wall("CorridorNorth", Vector3(4.2, 1.4, -7), Vector3(2.4, WALL_HEIGHT, 0.2))
	_wall("CorridorSouth", Vector3(4.2, 1.4, 7), Vector3(2.4, WALL_HEIGHT, 0.2))
	_wall("CorridorWestNorth", Vector3(3, 1.4, -5), Vector3(0.2, WALL_HEIGHT, 4))
	_wall("CorridorWestSouth", Vector3(3, 1.4, 6.8), Vector3(0.2, WALL_HEIGHT, 0.4))


func _build_props() -> void:
	_box("Wardrobe", Vector3(-1.85, 1.05, 2.55), Vector3(1.5, 2.1, 0.65), dark_wood)
	_box("WardrobeSeam", Vector3(-1.85, 1.05, 2.215), Vector3(0.025, 2, 0.015), metal, false)
	_box("BedFrame", Vector3(-1.7, 0.28, 5.1), Vector3(1.4, 0.55, 2.1), dark_wood)
	_box("Mattress", Vector3(-1.7, 0.61, 5.1), Vector3(1.35, 0.18, 2), porcelain)
	_box("Pillow", Vector3(-1.7, 0.75, 5.75), Vector3(0.8, 0.14, 0.4), porcelain, false)
	# Tub has a recessed inner surface, rather than a solid white box.
	_box("TubBase", Vector3(-5.25, 0.17, -1.35), Vector3(0.95, 0.34, 2.1), porcelain)
	_box("TubOuterRim", Vector3(-5.73, 0.43, -1.35), Vector3(0.12, 0.32, 2.1), porcelain)
	_box("TubInnerRim", Vector3(-4.77, 0.43, -1.35), Vector3(0.12, 0.32, 2.1), porcelain)
	_box("TubHeadRim", Vector3(-5.25, 0.43, -2.35), Vector3(0.95, 0.32, 0.12), porcelain)
	_box("TubFootRim", Vector3(-5.25, 0.43, -0.35), Vector3(0.95, 0.32, 0.12), porcelain)
	_box("ToiletBase", Vector3(-3.75, 0.2, -2.1), Vector3(0.35, 0.4, 0.45), porcelain)
	_box("ToiletSeat", Vector3(-3.75, 0.45, -2.1), Vector3(0.5, 0.12, 0.65), porcelain)
	_box("ToiletTank", Vector3(-3.75, 0.65, -2.5), Vector3(0.5, 0.7, 0.22), porcelain)
	# Decorative communal doors stay solid; no door mechanic in this slice.
	for z: float in [-4.0, 4.5]:
		_box("NeighbourDoor", Vector3(5.28, 1.05, z), Vector3(0.06, 2.1, 0.95), dark_wood, false)
	_box("Fusebox", Vector3(4.2, 1.45, -6.82), Vector3(0.65, 0.85, 0.22), metal)
	_box("FuseboxStripe", Vector3(4.2, 1.55, -6.695), Vector3(0.45, 0.12, 0.02), _material(Color(0.6, 0.48, 0.12)), false)
	_sign("FuseboxLabel", "ЩИТОК\n(пока без механики)", Vector3(4.2, 2.15, -6.65))
	_sign("BathroomLabel", "САНУЗЕЛ", Vector3(-2.88, 2.35, -0.5), PI / 2.0)
	_sign("BedroomLabel", "СПАЛЬНЯ", Vector3(1.2, 2.35, 2.88), PI)


func _room_slabs(label: String, center: Vector3, size: Vector2) -> void:
	_box(label + "Floor", center + Vector3(0, -0.1, 0), Vector3(size.x, 0.2, size.y), floor_material)
	_box(label + "Ceiling", center + Vector3(0, 2.9, 0), Vector3(size.x, 0.2, size.y), plaster)


func _wall(label: String, center: Vector3, size: Vector3) -> void:
	_box(label, center, size, plaster)


func _lintel(label: String, center: Vector3, size: Vector3) -> void:
	_box(label, center, size, dark_wood)


func _box(label: String, center: Vector3, size: Vector3, material: Material, solid: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.name = label
	visual.position = center
	add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		visual.add_child(body)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _light(label: String, center: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = label
	light.position = center
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
	_box(label + "Fixture", center + Vector3(0, 0.1, 0), Vector3(0.35, 0.07, 0.35), porcelain, false)


func _sign(label: String, text: String, center: Vector3, yaw: float = 0.0) -> void:
	var sign_label := Label3D.new()
	sign_label.name = label
	sign_label.text = text
	sign_label.position = center
	sign_label.rotation.y = yaw
	sign_label.font_size = 28
	sign_label.pixel_size = 0.008
	sign_label.modulate = Color(0.8, 0.8, 0.65)
	add_child(sign_label)
