extends "res://tests/chat_fixture.gd"
## Test-only commands accelerate the timeline, never included in production.

func _ready() -> void:
	super._ready()
	shift.set_process(false)
	threats.set_event_enabled(&"power_outage", false)


func _publish() -> void:
	super._publish()
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("window.shiftCommand || ''")
	JavaScriptBridge.eval("window.shiftCommand = ''")
	match str(command):
		"hack": terminal_ui.launch_app(&"hack")
		"next": shift.advance(300)
		"event": shift.complete_event()
		"return": enter_computer()
		"cctv": terminal_ui.launch_app(&"cctv")
	shift._process(0)
	var point := shift.hack_button.get_global_rect().get_center()
	var data := {"state": int(shift.state), "stage": shift.stage, "hack": [point.x, point.y],
		"cameras": cctv_system.cameras.size(), "correct": -1}
	var session: ChatSession = terminal_ui.chat.session
	if session.quiz_started and not session.ended:
		var question: Dictionary = session.questions[session.question_index]
		data.correct = question.answers.find(question.correct)
	JavaScriptBridge.eval("window.shiftTelemetry = " + JSON.stringify(data))
