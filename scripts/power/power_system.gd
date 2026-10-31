class_name ApartmentPower
extends Node

signal power_changed(powered: bool)

@export_group("Emergency flashlight")
@export_range(0.0, 4.0) var flashlight_energy: float = 0.9
@export_range(0.5, 10.0) var flashlight_range: float = 3.5
@export_range(5.0, 70.0) var flashlight_angle: float = 35.0
## Short, broad spill lights nearby floor/objects instead of only a distant spot.
@export_range(0.0, 2.0) var flashlight_spill_energy: float = 0.48
@export_range(0.5, 4.0) var flashlight_spill_range: float = 3.0
@export_range(35.0, 85.0) var flashlight_spill_angle: float = 82.0
@export_range(0.0, 0.2) var blackout_ambient_energy: float = 0.012
@export_group("Behind ambience")
@export var behind_sounds: Array[AudioStream] = []
@export_range(0.0, 1.0) var behind_chance: float = 0.5
@export_range(0.2, 60.0) var behind_min_interval: float = 5.0
@export_range(0.2, 60.0) var behind_max_interval: float = 13.0
@export_range(0.5, 5.0) var behind_distance: float = 1.8

var powered: bool = true
var flashlight_on: bool = false
var flashlight: SpotLight3D
var flashlight_spill: SpotLight3D
var board: ApartmentFusebox
var game: Node3D
var _behind_left: float = 0.0
var _interacting: bool = false
var _lights: Array[Light3D] = []
var _light_visibility: Array[bool] = []
var _environment: Environment
var _normal_ambient: float
var _normal_background: Color
var _screen: MeshInstance3D
var _screen_material: Material
var _black_screen: StandardMaterial3D
var _behind_audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
## Optional reservation guard supplied by the run's ThreatManager.
var outage_guard: Callable
var outage_request: Callable
var danger_audio_active: Callable


func bind(value: Node3D) -> void:
	game = value
	_rng.randomize()
	board = game.get_node("Apartment/Fusebox/Breakers")
	board.repaired.connect(restore_power)
	for index: int in board.handles.size():
		board.handles[index].get_node("PickBody").set_meta("lever_index", index)
	for light: Node in game.get_node("Apartment").find_children("*", "Light3D", true, false):
		_lights.append(light)
		_light_visibility.append(light.visible)
	var world := game.get_node("Apartment/WorldEnvironment") as WorldEnvironment
	_environment = world.environment.duplicate()
	world.environment = _environment
	_normal_ambient = _environment.ambient_light_energy
	_normal_background = _environment.background_color
	_screen = game.get_node("Terminal/Monitor/Screen")
	_screen_material = _screen.material_override
	_black_screen = StandardMaterial3D.new()
	_black_screen.albedo_color = Color.BLACK
	_black_screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flashlight = SpotLight3D.new()
	flashlight.name = "EmergencyFlashlight"
	flashlight.light_color = Color("d4d9b5")
	flashlight.shadow_enabled = true
	flashlight.spot_attenuation = 0.8
	flashlight.visible = false
	game.add_child(flashlight)
	flashlight_spill = SpotLight3D.new()
	flashlight_spill.name = "EmergencyFlashlightSpill"
	flashlight_spill.light_color = flashlight.light_color
	flashlight_spill.shadow_enabled = true
	flashlight_spill.spot_attenuation = 0.6
	flashlight_spill.visible = false
	game.add_child(flashlight_spill)
	_behind_audio = AudioStreamPlayer3D.new()
	_behind_audio.bus = &"Ambience"
	_behind_audio.volume_db = -16.0
	_behind_audio.max_distance = 7.0
	game.add_child(_behind_audio)
	_schedule_behind()


func _process(delta: float) -> void:
	if not is_instance_valid(game):
		return
	if not powered:
		update_flashlight()
	var danger := danger_audio_active.is_valid() and bool(danger_audio_active.call())
	if danger:
		_behind_audio.stop()
	if _interacting and not danger:
		_behind_left -= delta
		if _behind_left <= 0.0:
			_schedule_behind()
			if not _behind_audio.playing and _rng.randf() < behind_chance:
				var available: Array[AudioStream] = []
				for stream: AudioStream in behind_sounds:
					if stream != null:
						available.append(stream)
				if not available.is_empty():
					var camera: Camera3D = get_viewport().get_camera_3d()
					_behind_audio.global_position = camera.global_position + camera.global_basis.z * behind_distance + camera.global_basis.x * _rng.randf_range(-0.6, 0.6)
					_behind_audio.stream = available[_rng.randi_range(0, available.size() - 1)]
					_behind_audio.play()


func trigger_outage() -> bool:
	# Every external/debug request goes through the single threat scheduler.
	return bool(outage_request.call()) if outage_request.is_valid() else false


func cut_power() -> bool:
	if not powered or not is_instance_valid(board):
		return false
	if outage_guard.is_valid() and not outage_guard.call():
		return false
	powered = false
	board.reset_for_outage()
	for light: Light3D in _lights:
		light.hide()
	_environment.ambient_light_energy = blackout_ambient_energy
	_environment.background_color = Color.BLACK
	_screen.material_override = _black_screen
	set_flashlight_enabled(true)
	power_changed.emit(false)
	return true


func restore_power() -> void:
	if powered:
		return
	powered = true
	board.mark_powered()
	for index: int in _lights.size():
		_lights[index].visible = _light_visibility[index]
	_environment.ambient_light_energy = _normal_ambient
	_environment.background_color = _normal_background
	_screen.material_override = _screen_material
	set_flashlight_enabled(false)
	set_interacting(false)
	power_changed.emit(true)


func set_flashlight_enabled(value: bool) -> void:
	flashlight_on = value and not powered
	flashlight.visible = flashlight_on
	flashlight_spill.visible = flashlight_on
	update_flashlight()


func toggle_flashlight() -> void:
	set_flashlight_enabled(not flashlight_on)


func update_flashlight() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		flashlight.global_transform = camera.global_transform
		flashlight_spill.global_transform = camera.global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0, -0.12, 0.05))
	flashlight.light_energy = flashlight_energy
	flashlight.spot_range = flashlight_range
	flashlight.spot_angle = flashlight_angle
	flashlight_spill.light_energy = flashlight_spill_energy
	flashlight_spill.spot_range = flashlight_spill_range
	flashlight_spill.spot_angle = flashlight_spill_angle


func set_interacting(value: bool) -> void:
	_interacting = value and not powered
	_schedule_behind()
	if not _interacting:
		_behind_audio.stop()


func _schedule_behind() -> void:
	_behind_left = _rng.randf_range(maxf(0.2, behind_min_interval), maxf(behind_min_interval, behind_max_interval))
