extends "res://tests/stamina_fixture.gd"
## Test-only browser commands; never included in production exports.

func _ready() -> void:
	super._ready()
	observation_shift_enabled = false
	threats.random_allowed = false


func _process(delta: float) -> void:
	super._process(delta)
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.effectsCommand || ''")
	if command is String and not command.is_empty():
		JavaScriptBridge.eval("window.effectsCommand = ''")
		match command:
			"crt_off": visual_effects.crt_strength = 0.0
			"crt_on": visual_effects.crt_strength = 0.55
			"scare": visual_effects.trigger_scare()
			"pc": enter_computer()
			"cctv": terminal_ui.launch_app(&"cctv")
			"leave": leave_computer(false)
	var data := {
		"anxiety": visual_effects.anxiety,
		"crt": visual_effects.crt.visible,
		"smear": hud.fatigue.visible,
		"width": visual_effects.viewport.size.x,
		"height": visual_effects.viewport.size.y,
		"camera_error": visual_effects.camera.global_position.distance_to(get_viewport().get_camera_3d().global_position),
		"world_rendering": visual_effects.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"cctv_anxiety": terminal_ui.cctv._material.get_shader_parameter("anxiety"),
		"mode": int(mode),
	}
	JavaScriptBridge.eval("window.effectsTelemetry = " + JSON.stringify(data))
