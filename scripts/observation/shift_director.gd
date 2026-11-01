class_name ShiftDirector
extends Node
## A run-local timeline independent of camera rendering and desktop visibility.
enum State { INTRO, DEADLINE, ROUTE, EVENT, REPORT, ENDED, WAITING_EVENT }
const DATA := preload("res://data/observation/shift.gd")
@export var stages: Array[PackedScene] = []
var state: State = State.INTRO
var stage: int = 0
var seconds_left: float = 60.0
var code: String
var drink: int
var branch: int = -1
var game: Node3D
var location: ObservationLocation
var route: Array = []
var step: int = 0
var step_time: float = 0.0
var start_point: Vector3
var status: Label
var hack_status: Label
var hack_button: Button
var rng := RandomNumberGenerator.new()


func bind(value: Node3D) -> void:
	game = value
	rng = RunRandom.generator(game.run_seed, &"observation")
	code = "%04d" % rng.randi_range(1000, 9999)
	drink = rng.randi_range(0, DATA.DRINKS.size() - 1)
	game.terminal_ui.chat.session.intro_completed.connect(_begin_deadline)
	game.terminal_ui.chat.session.live_report = true
	status = Label.new()
	status.add_theme_font_override("font", preload("res://assets/fonts/static/Handjet-SemiBold.ttf"))
	status.add_theme_font_size_override("font_size", 24)
	status.position = Vector2(20, 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.get_node("UI").add_child(status)
	var column := VBoxContainer.new()
	game.terminal_ui.windows[&"hack"].content.add_child(column)
	hack_status = Label.new()
	hack_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hack_status)
	hack_button = Button.new()
	hack_button.text = "OBS_HACK_START"
	hack_button.pressed.connect(start_alarm)
	column.add_child(hack_button)
	_load_stage()
	_update_status()


func _begin_deadline() -> void:
	if state == State.INTRO:
		state = State.DEADLINE
		seconds_left = 60.0


func start_alarm() -> void:
	if state != State.DEADLINE or not game.power.powered or game.mode != game.Mode.COMPUTER:
		return
	_begin_route(location.route())
	game.atmosphere.start_run()
	_update_status()


func _load_stage() -> void:
	location = stages[stage].instantiate() as ObservationLocation
	if location == null:
		push_error("Shift stage %d must use ObservationLocation" % stage)
		return
	game.cctv_system.replace_location(location)
	if location.has_method("set_code"):
		location.set_code(code)
	if location.has_method("set_drink"):
		location.set_drink(drink)


func _begin_route(points: Array) -> void:
	route = points.duplicate(true)
	location.working = false
	if route.is_empty():
		push_error("Observation route is empty: %s" % location.scene_file_path)
		return
	step = 0
	step_time = 0
	start_point = location.target.position
	state = State.ROUTE


func _process(delta: float) -> void:
	if state in [State.WAITING_EVENT, State.EVENT]:
		_poll_transition()
	advance(delta)
	_update_status()
	if state == State.REPORT and game.mode == game.Mode.COMPUTER and game.power.powered and not game.dev_menu.is_open and not game.threats.is_busy():
		var session: ChatSession = game.terminal_ui.chat.session
		if not session.quiz_started:
			game.atmosphere.cancel(&"quiz_started")
			session.questions = report_questions()
			session.start_quiz()
			game.terminal_ui.launch_app(&"chat")


func advance(delta: float) -> void:
	if state == State.DEADLINE:
		seconds_left = maxf(0, seconds_left - delta)
		if seconds_left <= 0:
			state = State.ENDED
			game._finish_report(false, 0)
	elif state == State.ROUTE:
		var remaining := delta
		while remaining > 0 and state == State.ROUTE:
			var item: Dictionary = route[step]
			var consumed := minf(remaining, float(item.seconds) - step_time)
			step_time += consumed
			remaining -= consumed
			location.target.position = start_point.lerp(item.point, clampf(step_time / float(item.seconds), 0, 1))
			if step_time >= float(item.seconds):
				var event: String = item.get("event", "")
				if event == "branch":
					branch = rng.randi_range(0, 2)
					var exit := location.exit_point(branch)
					route.append({"point": exit, "seconds": 28.0})
					route.append({"point": exit + Vector3(0, 0, -5), "seconds": 16.0})
				else:
					location.event(event)
				step += 1
				step_time = 0
				start_point = location.target.position
				if step == route.size():
					_finish_stage()
					# Never spend a long frame's leftover delta on the next location.
					return


func _finish_stage() -> void:
	if stage == stages.size() - 1:
		state = State.REPORT
		game.threats.random_allowed = false
		return
	game.threats.random_allowed = false
	state = State.WAITING_EVENT
	game.atmosphere.request_transition(stage)
	_poll_transition()


func _poll_transition() -> void:
	game.atmosphere.try_transition()
	if game.atmosphere.transition_pending:
		state = State.EVENT if game.atmosphere.is_busy() else State.WAITING_EVENT
		return
	stage += 1
	_load_stage()
	_begin_route(location.route())


func complete_event() -> void:
	game.atmosphere.complete_event()
	if state in [State.WAITING_EVENT, State.EVENT]:
		_poll_transition()


func _update_status() -> void:
	if not is_instance_valid(status):
		return
	var text := ""
	match state:
		State.INTRO: text = tr("OBS_WAIT_INTRO")
		State.DEADLINE: text = tr("OBS_DEADLINE") % ceili(seconds_left)
		State.ROUTE: text = tr("OBS_RUNNING")
		State.REPORT: text = tr("OBS_RETURN")
	status.text = text
	status.visible = state in [State.DEADLINE, State.REPORT]
	if state == State.REPORT and game.mode == game.Mode.COMPUTER:
		status.hide()
	hack_status.text = text
	hack_button.disabled = state != State.DEADLINE or not game.power.powered


func report_questions() -> Array:
	var codes := [code, "%04d" % (1000 + (int(code) - 1000 + 127) % 9000), "%04d" % (1000 + (int(code) - 1000 + 513) % 9000)]
	for index: int in range(codes.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value: String = codes[index]
		codes[index] = codes[other]
		codes[other] = value
	return [
		{"id": "code", "prompt": "OBS_Q_CODE", "answers": codes, "correct": code},
		{"id": "drink", "prompt": "OBS_Q_DRINK", "answers": DATA.DRINKS, "correct": DATA.DRINKS[drink]},
		{"id": "path", "prompt": "OBS_Q_PATH", "answers": DATA.PATHS, "correct": DATA.PATHS[maxi(branch, 0)]},
	]
