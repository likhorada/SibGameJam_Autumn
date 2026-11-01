class_name CCTVSystem
extends Node
## One isolated 3D world, one small render target, only the selected lens renders.
## Location scripts/animations continue processing even when rendering is disabled.

signal directory_changed

@export var locations: Array[PackedScene] = []
@export var feed_size := Vector2i(480, 270)
@export_range(5.0, 30.0) var feed_fps: float = 18.0
@export_range(0.0, 2.0) var connection_seconds: float = 0.4

var cameras: Array[CCTVCamera] = []
var selected: CCTVCamera
var viewport: SubViewport
var connection_left: float = 0.0
var watching: bool = false
var _frame_time: float = 0.0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "FeedViewport"
	viewport.size = feed_size.max(Vector2i(16, 16))
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	var world := Node3D.new()
	world.name = "Locations"
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("252d32")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("9ca8b0")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	for index: int in locations.size():
		if locations[index] == null:
			push_warning("CCTV: empty location slot %d" % index)
			continue
		var location := locations[index].instantiate()
		if location is not Node3D:
			push_warning("CCTV: location must have a Node3D root")
			location.free()
			continue
		world.add_child(location)
		location.position += Vector3(index * 100.0, 0, 0)
		_collect_cameras(location)
	_sort_cameras()
	directory_changed.emit()


func _sort_cameras() -> void:
	cameras.sort_custom(func(a: CCTVCamera, b: CCTVCamera) -> bool:
		if a.location_label != b.location_label:
			return a.location_label < b.location_label
		if a.list_order != b.list_order:
			return a.list_order < b.list_order
		return String(a.camera_id) < String(b.camera_id))


func _collect_cameras(node: Node) -> void:
	if node is CCTVCamera:
		if node.camera_id.is_empty():
			# A dropped-in camera works immediately; explicit IDs stay stable across renames.
			node.camera_id = StringName(str(node.get_path()))
		var duplicate := false
		for camera: CCTVCamera in cameras:
			duplicate = duplicate or camera.camera_id == node.camera_id
		if duplicate:
			push_warning("CCTV: skipped duplicate Camera ID at %s" % node.get_path())
		else:
			cameras.append(node)
	for child: Node in node.get_children():
		_collect_cameras(child)


func replace_location(location: Node3D) -> void:
	# Keep the one viewport and environment; unload all previous scene cameras.
	if is_instance_valid(selected):
		selected.stop_immediately()
	selected = null
	cameras.clear()
	var world := viewport.get_node("Locations")
	for child: Node in world.get_children():
		if not child is WorldEnvironment:
			world.remove_child(child)
			child.queue_free()
	world.add_child(location)
	_collect_cameras(location)
	_sort_cameras()
	directory_changed.emit()
	if not cameras.is_empty() and selected == null:
		select_camera(0)


func select_camera(index: int) -> void:
	if index < 0 or index >= cameras.size():
		return
	if is_instance_valid(selected):
		selected.stop_immediately()
		selected.lens.clear_current(false)
	selected = cameras[index]
	selected.reset_view()
	selected.lens.make_current()
	connection_left = connection_seconds
	_frame_time = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func set_watching(value: bool) -> void:
	if watching == value:
		return
	watching = value
	if not watching:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(selected):
			selected.stop_immediately()
	elif not cameras.is_empty():
		select_camera(maxi(cameras.find(selected), 0))


func _process(delta: float) -> void:
	if not watching or not is_instance_valid(selected):
		return
	connection_left = maxf(0.0, connection_left - delta)
	selected.advance_motor(delta)
	_frame_time += delta
	if connection_left <= 0.0 and selected.interference_left <= 0.0 and _frame_time >= 1.0 / feed_fps:
		_frame_time = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func can_show_feed() -> bool:
	return watching and is_instance_valid(selected) and connection_left <= 0.0
