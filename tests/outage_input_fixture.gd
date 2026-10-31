extends "res://scripts/main.gd"
## Dedicated Web fixture: production has neither this clock control nor JS bridge.
var last_command: String = ""


func _ready() -> void:
	if OS.has_feature("web"):
		TranslationServer.set_locale(str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'ru'")))
	super._ready()
	transition_seconds = 0.04
	threats.set_event_enabled(&"psych_neighbor", false)
	threats.set_event_enabled(&"police_raid", false)
	threats.set_process(false)
	shift.set_process(false)
	enter_computer.call_deferred()
	var bridge := Node.new()
	bridge.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bridge)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	bridge.add_child(timer)
	timer.timeout.connect(_publish_outage)


func _publish_outage() -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.outageCommand || ''")
	JavaScriptBridge.eval("window.outageCommand = ''")
	if not str(command).is_empty():
		last_command = str(command)
	var entity := outage.entity
	match str(command):
		"corridor":
			player.global_position = Vector3(4.1, 0.03, -2.0)
			player.rotation = Vector3.ZERO
			player.head.rotation = Vector3.ZERO
			player.stop_motion(true)
		"encounter":
			entity.repeat_left = 0.0
			threats.advance(0.05)
		"active":
			threats.advance(entity.settings.warning_seconds + 0.05)
			threats.advance(0.1)
		"die":
			# Walking in the dark near the figure spends the shared error budget.
			var spawn: Vector3 = entity.visual.global_position
			player.global_position = Vector3(4.1, 0.03, spawn.z - 1.2)
			entity._last_player_position = player.global_position
			player.global_position = Vector3(4.1, 0.03, spawn.z - 0.6)
			entity.error_seconds = entity.settings.error_budget_seconds - 0.01
			player.global_position = Vector3(4.1, 0.03, spawn.z - 0.4)
			threats.advance(0.02)
		"toggle":
			power.toggle_flashlight()
	var buttons: Dictionary = {}
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		var point := button.get_global_rect().get_center()
		buttons[button.text] = [point.x, point.y]
	var data := {
		"mode": int(mode), "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"powered": power.powered, "light": power.flashlight_on,
		"warn": entity.warning_audio.playing, "steps": entity.footsteps_audio.playing,
		"phase": int(entity.phase), "visible": entity.visual.visible,
		"in_corridor": entity.in_corridor(), "repeat": entity.repeat_left,
		"error": entity.error_seconds, "state": int(threats.state),
		"dev": dev_menu.is_open, "ended": run_ended, "reason": failure_reason,
		"buttons": buttons, "command": last_command,
	}
	JavaScriptBridge.eval("window.outageTelemetry = " + JSON.stringify(data))
