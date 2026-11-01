extends "res://scripts/main.gd"
## Dedicated browser fixture only. No JavaScript or accelerated clock in production.
var _command_id: int = 0


func _ready() -> void:
	if OS.has_feature("web"):
		TranslationServer.set_locale(str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'en'")))
	super._ready()
	transition_seconds = 0.04
	dev_menu.hold_seconds = 0.1
	shift.set_process(false)
	threats.set_process(false)
	atmosphere.set_process(false)
	enter_computer.call_deferred()
	var bridge := Timer.new()
	bridge.wait_time = 0.05
	bridge.autostart = true
	add_child(bridge)
	bridge.timeout.connect(_publish)


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval("JSON.stringify(window.idiotCommand || null)")
	var command = JSON.parse_string(str(raw))
	if command is Dictionary:
		JavaScriptBridge.eval("window.idiotCommand = null")
		_command_id = int(command.id)
		match str(command.name):
			"cctv": terminal_ui.launch_app(&"cctv")
			"reveal_trigger":
				for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
					if button.text == "TriggerYouAreAnIdiot":
						dev_menu._scroll.ensure_control_visible(button)
			"advance": atmosphere.advance(float(command.get("seconds", 0.0)))
			"return": enter_computer()
			"start": atmosphere.request_event(&"you_are_an_idiot", true)
			"quiz":
				shift.state = ShiftDirector.State.REPORT
				shift._process(0)
	var event := atmosphere._active as YouAreAnIdiot
	var windows: Array = []
	if event != null:
		for popup: IdiotPopup in event.popups:
			var cross := popup.close_button.get_global_rect().get_center()
			var rect := popup.get_global_rect()
			windows.append({"close": [cross.x, cross.y], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	var trigger_position := Vector2.ZERO
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "TriggerYouAreAnIdiot":
			trigger_position = button.get_global_rect().get_center()
	var start_point := terminal_ui.start_button.get_global_rect().get_center()
	var workspace := terminal_ui.workspace.get_global_rect()
	var data := {"command": _command_id, "mode": int(mode), "dev": dev_menu.is_open,
		"trigger": [trigger_position.x, trigger_position.y], "windows": windows,
		"active": event != null, "chaotic": event.chaotic if event != null else false,
		"closing": event.closing_mode if event != null else false,
		"elapsed": event.elapsed if event != null else 0.0,
		"audio": event.audio.playing if event != null else false,
		"volume": event.audio.volume_db if event != null else -80.0,
		"visible": event.overlay.is_visible_in_tree() if event != null else false,
		"start": [start_point.x, start_point.y], "menu": terminal_ui.start_menu.visible,
		"workspace": [workspace.position.x, workspace.position.y, workspace.size.x, workspace.size.y],
		"quiz": terminal_ui.chat.session.quiz_started}
	JavaScriptBridge.eval("window.idiotTelemetry = " + JSON.stringify(data))
