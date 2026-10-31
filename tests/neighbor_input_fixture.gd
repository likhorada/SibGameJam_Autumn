extends "res://scripts/main.gd"
## Test-only bridge for real Chrome clicks, pointer capture and physical E input.
var last_command: String = ""


func _ready() -> void:
	TranslationServer.set_locale("ru")
	super._ready()
	transition_seconds = 0.04
	power.random_outages_enabled = false
	threats.set_process(false)
	shift.set_process(false)
	_look_door()
	var bridge := Node.new()
	bridge.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bridge)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	bridge.add_child(timer)
	timer.timeout.connect(_publish_neighbor)


func _look_door() -> void:
	player.position = Vector3(1.5, 0.02, 1.1)
	player.rotation = Vector3(0, -PI * 0.5, 0)
	player.head.rotation = Vector3.ZERO
	player.stop_motion(true)


func _publish_neighbor() -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.neighborCommand || ''")
	JavaScriptBridge.eval("window.neighborCommand = ''")
	if not str(command).is_empty():
		last_command = str(command)
	match str(command):
		"look_door": _look_door()
		"look_leaf":
			player.position = Vector3(2.3, 0.02, 0.6)
			player.rotation = Vector3(0, PI, 0)
			player.head.rotation = Vector3.ZERO
			player.stop_motion(true)
		"active": threats.advance(5.0)
		"trigger": trigger_neighbor()
		"die": threats.advance(3.0)
		"leave":
			threats.advance(neighbor.settings.rattle_seconds)
			threats.advance(neighbor.settings.departure_seconds)
			threats.advance(1.0)
		"computer": enter_computer()
	var buttons: Dictionary = {}
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		var point := button.get_global_rect().get_center()
		buttons[button.text] = [point.x, point.y]
	var file: Vector2 = terminal_ui.desktop_icons[&"night_note"].get_global_rect().get_center()
	var data := {"open": room_door.is_open, "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"interaction": player.interaction_id, "dev": dev_menu.is_open, "buttons": buttons,
		"state": int(threats.state), "visit": int(neighbor.visit), "ended": run_ended,
		"reason": failure_reason, "steps": neighbor.footsteps_audio.playing,
		"handle": neighbor.handle_audio.playing, "mode": int(mode),
		"active": String(terminal_ui.active_app), "file": [file.x, file.y], "command": last_command}
	JavaScriptBridge.eval("window.neighborTelemetry = " + JSON.stringify(data))
