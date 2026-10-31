extends "res://scripts/main.gd"
## Dedicated Web fixture: production has neither this clock control nor JS bridge.
var last_command: String = ""


func _ready() -> void:
	if OS.has_feature("web"):
		TranslationServer.set_locale(str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'ru'")))
	super._ready()
	transition_seconds = 0.04
	threats.set_event_enabled(&"power_outage", false)
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
	timer.timeout.connect(_publish_police)


func _aim_spot(bed: bool) -> void:
	var position := Vector3(-0.55, 0.03, 4.5) if bed else Vector3(-1.85, 0.03, 1.35)
	var target := Vector3(-1.7, 0.48, 4.5) if bed else Vector3(-1.85, 1.3, 2.55)
	player.position = position
	var direction := target - (position + Vector3(0, 1.6, 0))
	player.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	player.head.rotation = Vector3(atan2(direction.y, Vector2(direction.x, direction.z).length()), 0, 0)
	player.stop_motion(true)


func _publish_police() -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.policeCommand || ''")
	JavaScriptBridge.eval("window.policeCommand = ''")
	if not str(command).is_empty():
		last_command = str(command)
	match str(command):
		"wardrobe": _aim_spot(false)
		"bed": _aim_spot(true)
		"trigger": trigger_police()
		"active": threats.advance(12.0)
		"search_done": threats.advance(police.settings.search_seconds)
		"gone":
			threats.advance(police.settings.departure_seconds)
			threats.advance(1.0)
	var buttons: Dictionary = {}
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		var point := button.get_global_rect().get_center()
		buttons[button.text] = [point.x, point.y]
	var data := {"mode": int(mode), "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"hidden": is_hidden(), "controls": player.controls_enabled, "interaction": player.interaction_id,
		"dev": dev_menu.is_open, "buttons": buttons, "command": last_command,
		"visit": int(police.visit), "state": int(threats.state), "open": room_door.is_open,
		"ended": run_ended, "reason": failure_reason, "steps": police.footsteps_audio.playing,
		"knock": police.knock_audio.playing, "look": [_hidden_look.x, _hidden_look.y],
		"body": [player.position.x, player.position.y, player.position.z],
		"camera": [transition_camera.position.x, transition_camera.position.y, transition_camera.position.z]}
	JavaScriptBridge.eval("window.policeTelemetry = " + JSON.stringify(data))
