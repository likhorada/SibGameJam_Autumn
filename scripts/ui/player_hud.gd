class_name PlayerHUD
extends Control
## Screen effect draws on the world-only layer, before HUD labels and PC windows.

@export_group("Stamina presentation")
@export_range(1.0, 4.0) var visual_curve_power: float = 2.0
@export_range(1.0, 30.0) var bar_response: float = 12.0
@export_range(1.0, 30.0) var bar_fade_response: float = 8.0
@export_group("Fatigue comfort")
## Zero disables the screen shader without affecting stamina, bob or mouse look.
@export_range(0.0, 1.0) var fatigue_strength: float = 1.0
@export_range(1.0, 20.0) var fatigue_response: float = 5.0
@export_range(1.0, 40.0) var smear_response: float = 20.0
@export_range(0.0, 0.1) var shutter_seconds: float = 0.035
## Logical pixels at the project's design resolution, scales with the window.
@export_range(0.0, 40.0) var max_smear_pixels: float = 18.0
@export_range(0.0, 0.5) var ghost_weight: float = 0.32
@export_range(1.0, 4.0) var ghost_distance: float = 2.6

var player: ApartmentPlayer
var displayed_ratio: float = 1.0
var bar_alpha: float = 0.0
var fatigue_blend: float = 0.0
var smear_uv := Vector2.ZERO
var _previous_basis := Basis.IDENTITY
var _previous_size := Vector2.ZERO
var _history_valid: bool = false
var anxiety_amount: float = 0.0
var world_effects_active: bool = true
var _previous_camera: Camera3D
var game: Node3D
var threat_hint: Label

@onready var bar: Control = $StaminaBar
@onready var fill: ColorRect = $StaminaBar/Fill
@onready var fatigue: ColorRect = $Fatigue
@onready var _material: ShaderMaterial = fatigue.material


func _ready() -> void:
	var hud_theme := Theme.new()
	# Same artist font as the menu; the PC desktop keeps its own theme.
	hud_theme.default_font = preload("res://assets/fonts/static/Handjet-SemiBold.ttf")
	theme = hud_theme
	fatigue.material = fatigue.material.duplicate()
	_material = fatigue.material
	bar.modulate.a = 0.0
	fatigue.hide()
	threat_hint = Label.new()
	threat_hint.name = "ThreatHint"
	threat_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	threat_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_hint.add_theme_font_size_override("font_size", 24)
	threat_hint.add_theme_color_override("font_color", Color("efcf9d"))
	threat_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	threat_hint.add_theme_constant_override("shadow_offset_x", 2)
	threat_hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(threat_hint)
	threat_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	threat_hint.offset_top = -57
	threat_hint.offset_bottom = -30
	threat_hint.hide()


func bind_player(value: ApartmentPlayer) -> void:
	player = value
	clear_smear()


func visual_ratio(real_ratio: float) -> float:
	return 1.0 - pow(1.0 - clampf(real_ratio, 0.0, 1.0), visual_curve_power)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(game):
		var key := warning_key()
		threat_hint.text = tr(key)
		threat_hint.visible = not key.is_empty()
	var weight := 1.0 - exp(-bar_response * delta)
	displayed_ratio = lerpf(displayed_ratio, visual_ratio(player.stamina.value), weight)
	fill.size.x = bar.size.x * displayed_ratio
	var showing := is_visible_in_tree() and player.stamina.value < 0.9999
	bar_alpha = lerpf(bar_alpha, 1.0 if showing else 0.0, 1.0 - exp(-bar_fade_response * delta))
	bar.modulate.a = bar_alpha
	var stamina_active := is_visible_in_tree() and player.controls_enabled and player.camera.current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var view := get_viewport().get_camera_3d()
	if view == null:
		clear_smear()
		return
	if view != _previous_camera:
		_history_valid = false
		_previous_camera = view
	var active := world_effects_active and (stamina_active or anxiety_amount > 0.001)
	update_smear(delta, player.stamina.fatigue_amount() if stamina_active else 0.0, view.global_basis, active)


func update_smear(delta: float, fatigue_amount: float, view_basis: Basis, active: bool) -> void:
	var view_size := get_viewport().get_visible_rect().size
	if not active or (fatigue_strength <= 0.0 and anxiety_amount <= 0.0) or shutter_seconds <= 0.0 or max_smear_pixels <= 0.0:
		clear_smear()
		return
	var target_fatigue := maxf(fatigue_amount * fatigue_strength, anxiety_amount)
	fatigue_blend = lerpf(fatigue_blend, target_fatigue, 1.0 - exp(-fatigue_response * delta))
	# Recovery already supplies a gradual envelope. Do not let smoothing extend
	# the effect past the agreed 45% clear threshold.
	fatigue_blend = minf(fatigue_blend, target_fatigue)
	var target := Vector2.ZERO
	if _history_valid and view_size == _previous_size:
		# Measure the final rendered camera, including immediate large mouse flicks.
		var angles := (_previous_basis.inverse() * view_basis).get_euler()
		var view := get_viewport().get_camera_3d()
		var vertical_scale := 2.0 * tan(deg_to_rad(view.fov if view != null else player.camera.fov) * 0.5)
		var aspect := view_size.x / maxf(view_size.y, 1.0)
		target = Vector2(angles.y / (vertical_scale * aspect), -angles.x / vertical_scale)
		target *= shutter_seconds / maxf(delta, 0.0001)
		target = (target * view_size).limit_length(max_smear_pixels) / view_size
	_previous_basis = view_basis
	_previous_size = view_size
	_history_valid = true
	smear_uv = smear_uv.lerp(target, 1.0 - exp(-smear_response * delta))
	var anxiety_smear := Vector2(4.0, 1.2) / Vector2(1280, 720) * anxiety_amount
	var combined_smear := smear_uv * (1.0 + anxiety_amount * 0.8) + anxiety_smear
	_material.set_shader_parameter("smear_uv", combined_smear)
	_material.set_shader_parameter("intensity", fatigue_blend)
	_material.set_shader_parameter("ghost_weight", ghost_weight)
	_material.set_shader_parameter("ghost_distance", ghost_distance)
	# Fatigue alone is motion-only; anxiety leaves a small persistent double image.
	fatigue.visible = fatigue_blend > 0.001 and (combined_smear * view_size).length() > 0.05


func clear_smear() -> void:
	_history_valid = false
	fatigue_blend = 0.0
	smear_uv = Vector2.ZERO
	if is_instance_valid(fatigue):
		fatigue.hide()
		_material.set_shader_parameter("smear_uv", Vector2.ZERO)
		_material.set_shader_parameter("intensity", 0.0)


func warning_key() -> String:
	if game.run_ended or not game.capture_reason.is_empty():
		return ""
	if is_instance_valid(game.police) and game.police.visit != PoliceRaid.Visit.DORMANT and not game.is_hidden():
		return "THREAT_HIDE"
	if is_instance_valid(game.outage) and game.outage.entity.phase in [CorridorEntity.Phase.WARNING, CorridorEntity.Phase.ACTIVE] and not game.outage.entity.is_chasing and not game.is_hidden():
		return "THREAT_FREEZE"
	return ""
