extends "res://scripts/main.gd"
## Test export only. Production exports exclude tests/* and have no telemetry bridge.

func _ready() -> void:
	super._ready()
	player.position = Vector3(4.2, 0.02, -5.3)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.stop_motion(true)


func _process(_delta: float) -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.powerCommand || ''")
	if command is String and not command.is_empty():
		JavaScriptBridge.eval("window.powerCommand = ''")
		if command == "pc":
			enter_computer()
	var camera := get_viewport().get_camera_3d()
	var points: Array = []
	for handle: Node3D in power.board.handles:
		var point := camera.unproject_position(handle.global_position)
		points.append([point.x, point.y])
	var buttons: Dictionary = {}
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		var point := button.get_global_rect().get_center()
		buttons[button.text] = [point.x, point.y]
	var data := {
		"powered": power.powered, "cooldown": threats.wait_seconds_left,
		"mode": int(mode), "dev": dev_menu.is_open,
		"debug_hud": dev_menu._debug_hud_enabled,
		"unlimited": player.stamina.unlimited, "stamina": player.stamina.value,
		"progress": power.board.progress, "latched": power.board.latched,
		"held": power.board.held, "flashlight": power.flashlight.visible,
		"points": points, "buttons": buttons,
		"desktop": terminal_ui.visible, "controls": player.controls_enabled,
		"notes": terminal_ui.notepad.editor.text,
	}
	JavaScriptBridge.eval("window.powerTelemetry = " + JSON.stringify(data))
