extends "res://scripts/main.gd"
## Test-only browser telemetry/clock. Never included in production exports.
var _command_id: int = 0
var _prepared: bool = false
var _outcome: StringName = &""


func _ready() -> void:
	if OS.has_feature("web"):
		TranslationServer.set_locale(str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'en'")))
	super._ready()
	transition_seconds = 0.04
	dev_menu.hold_seconds = 0.1
	shift.set_process(false)
	threats.set_process(false)
	atmosphere.set_process(false)
	atmosphere.event_finished.connect(func(id: StringName, outcome: StringName):
		if id == &"firewall_breach":
			_outcome = outcome)
	enter_computer.call_deferred()
	var bridge := Timer.new()
	bridge.wait_time = 0.05
	bridge.autostart = true
	add_child(bridge)
	bridge.timeout.connect(_publish)


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	if not _prepared and mode == Mode.COMPUTER:
		_prepared = true
		terminal_ui.launch_app(&"calculator")
		terminal_ui.calculator.press("7")
		terminal_ui.calculator.press("3")
		terminal_ui.launch_app(&"cctv")
		terminal_ui.launch_app(&"notepad")
		terminal_ui.notepad.editor.text = "Firewall evidence stays"
		terminal_ui.chat.session.history.append({"sender": "you", "text": "firewall history marker"})
	var raw = JavaScriptBridge.eval("JSON.stringify(window.firewallCommand || null)")
	var command = JSON.parse_string(str(raw))
	if command is Dictionary:
		JavaScriptBridge.eval("window.firewallCommand = null")
		_command_id = int(command.id)
		match str(command.name):
			"reveal_trigger":
				for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
					if button.text == "TriggerFirewallBreach":
						dev_menu._scroll.ensure_control_visible(button)
			"advance": atmosphere.advance(float(command.get("seconds", 0.0)))
			"due":
				var current := atmosphere._active as FirewallBreach
				if current != null:
					current.round_state.attack_wait = 0.1
			"return": enter_computer()
			"start": atmosphere.request_event(&"firewall_breach", true)
			"cancel": atmosphere.cancel()
			"minimize_calc": terminal_ui.windows[&"calculator"].minimize()
			"quiz":
				shift.state = ShiftDirector.State.REPORT
				shift._process(0)
	var event := atmosphere._active as FirewallBreach
	var ports: Array = []
	var block_point := Vector2.ZERO
	var panel_rect := Rect2()
	if event != null:
		for index: int in 9:
			var point := event.view.port_buttons[index].get_global_rect().get_center()
			ports.append({"index": index, "open": event.round_state.ports[index], "point": [point.x, point.y]})
		block_point = event.view.block_button.get_global_rect().get_center()
		panel_rect = event.view.get_global_rect()
	var trigger := Vector2.ZERO
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		if button.text == "TriggerFirewallBreach":
			trigger = button.get_global_rect().get_center()
	var opened: Dictionary = {}
	for id: StringName in terminal_ui.windows:
		opened[id] = terminal_ui.windows[id].opened
	var area := terminal_ui.get_global_rect()
	var start_point := terminal_ui.start_button.get_global_rect().get_center()
	var note_icon: Vector2 = terminal_ui.desktop_icons[&"notepad"].get_global_rect().get_center()
	var data := {"command": _command_id, "mode": int(mode), "dev": dev_menu.is_open,
		"trigger": [trigger.x, trigger.y], "active": event != null, "ports": ports,
		"block": [block_point.x, block_point.y], "block_enabled": event != null and not event.view.block_button.disabled,
		"elapsed": event.round_state.elapsed if event != null else 0.0,
		"round_state": int(event.round_state.state) if event != null else -1,
		"modal": terminal_ui.has_modal(), "visible": event.overlay.is_visible_in_tree() if event != null else false,
		"panel": [panel_rect.position.x, panel_rect.position.y, panel_rect.size.x, panel_rect.size.y],
		"area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"notes": terminal_ui.notepad.editor.text, "calc": terminal_ui.calculator.model.entry,
		"history": terminal_ui.chat.session.history.any(func(item: Dictionary) -> bool: return item.text == "firewall history marker"),
		"opened": opened, "outcome": String(_outcome), "app": String(terminal_ui.active_app),
		"start": [start_point.x, start_point.y], "menu": terminal_ui.start_menu.visible,
		"note_icon": [note_icon.x, note_icon.y], "quiz": terminal_ui.chat.session.quiz_started}
	JavaScriptBridge.eval("window.firewallTelemetry = " + JSON.stringify(data))
