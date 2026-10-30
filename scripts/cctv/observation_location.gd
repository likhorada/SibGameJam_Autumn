extends Node3D
## Low-poly prototype built from markers; only the active location is instantiated.
const CAMERA := preload("res://scenes/cctv/cctv_camera.tscn")
const DATA := preload("res://data/observation/shift.gd")
var stage: int = 0
var code: String
var drink: int = 0
var target: Node3D
var bottle: Node3D
var shelf_bottles: Array[Node3D] = []
var pedestrians: Array[Node3D] = []
var elapsed: float = 0.0
var working: bool = true
var arms: Array[Node3D] = []


func _ready() -> void:
	box(self, Vector3(0, -0.2, 0), Vector3(36, 0.3, 38), Color("424644"))
	target = person(Vector3(0, 0, 2), Color("bd8740"))
	if stage == 0:
		target.position = Vector3(-0.65, -0.35, 1.2)
		box(self, Vector3(-0.65, 0.4, 1.3), Vector3(0.8, 0.12, 0.8), Color("303b40"))
		for x: float in [-0.35, 0.35]:
			arms.append(box(target, Vector3(x, 0.9, -0.35), Vector3(0.16, 0.15, 0.7), Color("bd8740")))
		box(self, Vector3(0, 0.7, 0), Vector3(3, 0.15, 1.5), Color("65594a"))
		box(self, Vector3(0, 1.35, -0.25), Vector3(1.7, 0.95, 0.12), Color("101c1a"))
		label(code, Vector3(0, 1.4, -0.16), 64, 0.007)
		label("OFFICE / EXIT", Vector3(4, 2, -6), 48)
		box(self, Vector3(-4, 1.5, -4), Vector3(0.2, 3, 8), Color("61665b"))
		camera("DESK", Vector3(1.6, 2.5, 3.5), Vector3(0, 1.4, 0), 48)
		camera("EXIT", Vector3(8, 5, 4), Vector3(2, 0.8, -2))
	elif stage == 1:
		target.position = Vector3(-4, 0, 6)
		box(self, Vector3(-4, 0.6, 0), Vector3(2.5, 1.2, 2), Color("65594a"))
		for i: int in 4:
			var pumpkin := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.3
			mesh.height = 0.5
			pumpkin.mesh = mesh
			pumpkin.material_override = material(Color("d97528"))
			add_child(pumpkin)
			pumpkin.position = Vector3(-4.8 + i * 0.5, 1.4, 0)
		box(self, Vector3(3, 0.7, -1), Vector3(4, 0.2, 1), Color("77715b"))
		for i: int in 4:
			shelf_bottles.append(make_bottle(self, Vector3(1.8 + i * 0.8, 0.8, -1), i))
		box(self, Vector3(0, 0.65, 2), Vector3(3, 1.3, 1), Color("536564"))
		label("CHECKOUT", Vector3(0, 2.5, 2))
		camera("VEGETABLES", Vector3(-8, 5, 7), Vector3(-3, 0.8, 0))
		camera("SHELF", Vector3(4, 3, 4), Vector3(3, 1, -0.5), 48)
		camera("CHECKOUT", Vector3(0, 3, 7), Vector3(0, 1.1, 2.7), 48)
	else:
		target.position = Vector3(0, 0, 6)
		for i: int in 3:
			var end: Vector3 = DATA.EXITS[i]
			box(self, end * 0.6 + Vector3(0, -0.01, 0), Vector3(5, 0.1, 14), Color("62635c"))
			if i == 0:
				for x: float in [-2.8, 2.8]:
					box(self, end + Vector3(x, 1, 0), Vector3(0.3, 2, 7), Color("60514b"))
			else:
				for x: float in [-2.5, 2.5]:
					box(self, end + Vector3(x, 1, -1), Vector3(0.25, 2, 0.25), Color("534632"))
					box(self, end + Vector3(x, 2.2, -1), Vector3(1.5, 1.5, 1.5), Color("42563a"))
				if i == 2:
					box(self, end + Vector3(1.7, 0.5, 1), Vector3(1.5, 0.15, 0.6), Color("7d6248"))
			label(tr(DATA.PATHS[i]), end + Vector3(0, 2.4, -1), 32)
			# Short range and narrow view keep the actual junction outside every feed.
			camera(DATA.PATHS[i], end + Vector3(0, 4, 4), end + Vector3(0, 0.8, 0), 48)
			var cam: CCTVCamera = get_child(get_child_count() - 1)
			cam.lens.far = 9.0
			cam.pan_limit_degrees = 8
			for j: int in 2:
				pedestrians.append(person(end + Vector3(j * 2 - 1, 0, 1), Color("53687a") if j == 0 else Color("78677c")))


func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = at
	return node


func person(at: Vector3, color: Color) -> Node3D:
	var actor := Node3D.new()
	add_child(actor)
	actor.position = at
	box(actor, Vector3(0, 1, 0), Vector3(0.6, 0.8, 0.4), color)
	box(actor, Vector3(0, 1.6, 0), Vector3(0.35, 0.4, 0.35), Color("b69e85"))
	for side: float in [-0.18, 0.18]:
		box(actor, Vector3(side, 0.3, 0), Vector3(0.2, 0.6, 0.25), Color("222c33"))
	return actor


func make_bottle(parent: Node3D, at: Vector3, index: int) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.position = at
	var colors := [Color("d0b05b"), Color("65402c"), Color("921e35"), Color("4daf43")]
	box(node, Vector3(0, 0.23, 0), Vector3(0.28, 0.46, 0.28), colors[index])
	box(node, Vector3(0, 0.52, 0), Vector3(0.12, 0.15, 0.12), colors[index])
	var text := Label3D.new()
	text.text = tr(DATA.DRINKS[index]).replace(" ", "\n")
	text.font_size = 32
	text.pixel_size = 0.004
	text.position = Vector3(0, 0.25, 0.16)
	node.add_child(text)
	return node


func label(text: String, at: Vector3, size: int = 40, pixels: float = 0.01) -> void:
	var node := Label3D.new()
	node.text = text
	node.font_size = size
	node.pixel_size = pixels
	add_child(node)
	node.position = at


func camera(title: String, at: Vector3, aim: Vector3, fov: float = 65) -> void:
	var node: CCTVCamera = CAMERA.instantiate()
	node.camera_id = StringName("stage%d_%s" % [stage, title])
	node.display_name = title
	node.location_label = ["OBS_OFFICE", "OBS_SHOP", "OBS_STREET"][stage]
	node.base_fov = fov
	add_child(node)
	node.position = at
	node.look_at(aim)


func event(id: String) -> void:
	if id == "take":
		bottle = shelf_bottles[drink]
		bottle.reparent(target)
		bottle.position = Vector3(0.5, 0.7, 0.25)
	elif id == "checkout" and is_instance_valid(bottle):
		bottle.reparent(self)
		bottle.position = Vector3(0.5, 1.3, 2.3)


func _process(delta: float) -> void:
	elapsed += delta
	if stage == 0 and working:
		for i: int in arms.size():
			arms[i].position.y = 0.9 + sin(elapsed * 5 + i) * 0.025
	for i: int in pedestrians.size():
		var end: Vector3 = DATA.EXITS[i / 2]
		pedestrians[i].position = end + Vector3(sin(elapsed * 0.25 + i) * 2, 0, cos(elapsed * 0.2 + i) * 2)
