extends "res://scripts/main.gd"
## Dedicated Web test only; excluded from production exports.

func _ready() -> void:
	if OS.has_feature("web"):
		var language = JavaScriptBridge.eval("new URL(location.href).searchParams.get('lang') || 'en'")
		TranslationServer.set_locale(str(language))
	super._ready()
	transition_seconds = 0.04
	power.random_outages_enabled = false
	enter_computer.call_deferred()
	# Continue telemetry after the result freezes the run.
	var bridge := Node.new()
	bridge.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bridge)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	bridge.add_child(timer)
	timer.timeout.connect(_publish)


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	var chat: ChatApp = terminal_ui.chat
	var options: Array = []
	for button: Button in chat.options.get_children():
		var point := button.get_global_rect().get_center()
		options.append([point.x, point.y])
	var buttons: Dictionary = {}
	for button: Button in dev_menu._overlay.find_children("*", "Button", true, false):
		var point := button.get_global_rect().get_center()
		buttons[button.text] = [point.x, point.y]
	var point := chat.composer.get_global_rect().get_center()
	var data := {"mode": int(mode), "dev": dev_menu.is_open, "options": options,
		"buttons": buttons, "selected": chat.session.selected, "typed": chat.session.typed,
		"length": tr(chat.session.selected).length(), "pending": chat.session.pending.size(),
		"intro": chat.session.intro_step, "quiz": chat.session.quiz_started,
		"question": chat.session.question_index, "ended": chat.session.ended,
		"score": chat.session.score, "frozen": process_mode == Node.PROCESS_MODE_DISABLED,
		"presses": terminal_ui.input_audio.presses_played, "audio": terminal_ui.input_audio.enabled,
		"draft_visible": chat.draft_header.visible, "send_visible": chat.send_reply.visible,
		"placeholder": chat.session.typed == 0 and chat.composer.text.contains(tr("CHAT_TYPE_HELP")),
		"composer": [point.x, point.y], "active": String(terminal_ui.active_app)}
	JavaScriptBridge.eval("window.chatTelemetry = " + JSON.stringify(data))
