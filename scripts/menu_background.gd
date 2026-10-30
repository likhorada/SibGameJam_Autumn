extends TextureRect
## Artist contract: ordinary Node3D scene with an active Camera3D and its own lighting.
@export var backgrounds: Array[PackedScene] = []
@export var feed_size := Vector2i(640, 360)
@export_range(5, 30) var feed_fps: float = 18.0
@export var monochrome: bool = true
var viewport: SubViewport
var selected_index: int = -1
var elapsed: float = 0.0
var _frame_time: float = 0.0

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = feed_size.max(Vector2i(16, 16))
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var available: Array[int] = []
	for index: int in backgrounds.size():
		if backgrounds[index] != null:
			available.append(index)
	if available.is_empty():
		return
	selected_index = available.pick_random()
	var scene := backgrounds[selected_index].instantiate()
	viewport.add_child(scene)
	texture = viewport.get_texture()
	var effect := ShaderMaterial.new()
	effect.shader = preload("res://assets/shaders/cctv_feed.gdshader")
	effect.set_shader_parameter("monochrome", monochrome)
	material = effect

func _process(delta: float) -> void:
	elapsed += delta
	_frame_time += delta
	if _frame_time >= 1.0 / feed_fps:
		_frame_time = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if material:
		material.set_shader_parameter("interference", 0.22 if fmod(elapsed, 11.0) > 10.8 else 0.015)
