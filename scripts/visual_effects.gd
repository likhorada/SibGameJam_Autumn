class_name VisualEffects
extends Node
## One low-resolution apartment render, one existing active CCTV render.
## Gameplay cameras stay in place: physics, interaction and transitions are unchanged.

@export var render_height: int = 144
@export_range(0.0, 1.0) var crt_strength: float = 0.55
@export_range(0.0, 1.0) var anxiety_strength: float = 0.85
@export_range(1.0, 20.0) var danger_radius: float = 7.0
@export_range(0.0, 5.0) var full_danger_radius: float = 1.5
@export_range(0.1, 5.0) var recovery_seconds: float = 2.5

var game: Node3D
var viewport: SubViewport
var camera: Camera3D
var image: TextureRect
var crt: ColorRect
var anxiety: float = 0.0
var _scare: float = 0.0
var _root: Viewport
var _was_disabled: bool
var _world_layer: CanvasLayer
var _smear_layer: CanvasLayer
var _crt_layer: CanvasLayer


func bind(value: Node3D) -> void:
	game = value
	_root = game.get_viewport()
	_was_disabled = _root.disable_3d
	viewport = SubViewport.new()
	viewport.name = "ApartmentViewport"
	viewport.world_3d = game.get_world_3d()
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	_world_layer = CanvasLayer.new()
	_world_layer.layer = -10
	add_child(_world_layer)
	image = TextureRect.new()
	image.name = "PixelWorld"
	image.texture = viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_layer.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The original shader remains a single pass, below all text even in hiding.
	_smear_layer = CanvasLayer.new()
	_smear_layer.layer = 0
	add_child(_smear_layer)
	game.hud.fatigue.reparent(_smear_layer, false)
	game.hud.fatigue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crt_layer = CanvasLayer.new()
	_crt_layer.layer = 2
	add_child(_crt_layer)
	crt = ColorRect.new()
	crt.name = "TerminalCRT"
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/terminal_crt.gdshader")
	crt.material = material
	_crt_layer.add_child(crt)
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.disable_3d = true
	RenderingServer.frame_pre_draw.connect(_sync_camera)
	_sync_camera()


func _process(delta: float) -> void:
	if not is_instance_valid(game):
		return
	# The main viewport's 3D pass is disabled; keep the proxy camera updated from
	# process rather than relying only on its pre-draw callback (not emitted by
	# every Compatibility/Web backend when that pass is disabled).
	_sync_camera()
	_scare = maxf(0.0, _scare - delta / recovery_seconds)
	var target := maxf(_proximity(), _scare) * anxiety_strength
	if game.run_ended:
		target = 0.0
		_scare = 0.0
	if target > anxiety:
		anxiety = move_toward(anxiety, target, delta * 4.0)
	else:
		anxiety = move_toward(anxiety, target, delta / recovery_seconds)
	var presenting: bool = not game.dev_menu.is_open and not game.run_ended
	game.hud.anxiety_amount = anxiety if presenting else 0.0
	game.hud.world_effects_active = presenting and game.mode != game.Mode.COMPUTER
	game.terminal_ui.cctv.set_anxiety(anxiety if presenting else 0.0)
	crt.visible = presenting and game.mode == game.Mode.COMPUTER and game.terminal_ui.visible and crt_strength > 0.0
	crt.material.set_shader_parameter("strength", crt_strength)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if game.mode == game.Mode.COMPUTER else SubViewport.UPDATE_ALWAYS


func trigger_scare(strength: float = 1.0) -> void:
	_scare = maxf(_scare, clampf(strength, 0.0, 1.0))


func _proximity() -> float:
	var positions: Array[Vector3] = []
	if is_instance_valid(game.neighbor) and game.neighbor.visit != PsychNeighbor.Visit.DORMANT:
		positions.append(game.neighbor.visual.global_position)
	if is_instance_valid(game.police) and game.police.visit != PoliceRaid.Visit.DORMANT:
		positions.append(game.police.visual.global_position)
	if is_instance_valid(game.outage) and game.outage.has_active_encounter():
		positions.append(game.outage.entity.global_position)
	var amount := 0.0
	for position: Vector3 in positions:
		if not ThreatAwareness.clear_line(game, game.player.global_position + Vector3.UP * 1.5, position + Vector3.UP * 1.2):
			continue
		var distance: float = game.player.global_position.distance_to(position)
		amount = maxf(amount, 0.45 * (1.0 - smoothstep(full_danger_radius, maxf(full_danger_radius + 0.01, danger_radius), distance)))
	return amount


func _sync_camera() -> void:
	if not is_instance_valid(game):
		return
	var size := _root.get_visible_rect().size
	var target_size := Vector2i(maxi(16, roundi(render_height * size.x / maxf(size.y, 1.0))), maxi(16, render_height))
	if viewport.size != target_size:
		viewport.size = target_size
	var source := _root.get_camera_3d()
	if source == null:
		return
	camera.global_transform = source.global_transform
	camera.projection = source.projection
	camera.keep_aspect = source.keep_aspect
	camera.fov = source.fov
	camera.size = source.size
	camera.frustum_offset = source.frustum_offset
	camera.h_offset = source.h_offset
	camera.v_offset = source.v_offset
	camera.near = source.near
	camera.far = source.far
	camera.cull_mask = source.cull_mask
	camera.environment = source.environment
	camera.attributes = source.attributes


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_camera):
		RenderingServer.frame_pre_draw.disconnect(_sync_camera)
	if is_instance_valid(_root):
		_root.disable_3d = _was_disabled
