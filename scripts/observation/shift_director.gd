class_name ShiftDirector
extends Node
## A run-local timeline independent of camera rendering and desktop visibility.
enum State { INTRO, DEADLINE, ROUTE, SCARE, REPORT, ENDED }
const DATA := preload("res://data/observation/shift.gd")
const LOCATION := preload("res://scripts/cctv/observation_location.gd")
var state: State = State.INTRO
var stage: int = 0
var seconds_left: float = 60.0
var code: String
var drink: int
var branch: int = -1
var game: Node3D
var location: Node3D
var route: Array = []
var step: int = 0
var step_time: float = 0.0
var start_point: Vector3
var status: Label
var hack_status: Label
var hack_button: Button
var outages_allowed: bool
var rng := RandomNumberGenerator.new()


func bind(value: Node3D) -> void:
	game = value
	rng.randomize()
	code = "%04d" % rng.randi_range(1000, 9999)
	drink = rng.randi_range(0, DATA.DRINKS.size() - 1)
	outages_allowed = game.power.random_outages_enabled
	game.power.random_outages_enabled = false
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
	game.power.random_outages_enabled = outages_allowed
	_begin_route(DATA.OFFICE)
	_update_status()


func _load_stage() -> void:
	location = LOCATION.new()
	location.stage = stage
	location.code = code
	location.drink = drink
	game.cctv_system.replace_location(location)


func _begin_route(points: Array) -> void:
	route = points.duplicate(true)
	location.working = false
	for i: int in route.size():
		var marker := Marker3D.new()
		marker.name = "RoutePoint%d" % i
		location.add_child(marker)
		marker.position = route[i].point
	step = 0
	step_time = 0
	start_point = location.target.position
	state = State.ROUTE


func _process(delta: float) -> void:
	advance(delta)
	_update_status()
	if state == State.REPORT and game.mode == game.Mode.COMPUTER and game.power.powered and not game.dev_menu.is_open:
		var session: ChatSession = game.terminal_ui.chat.session
		if not session.quiz_started:
			session.questions = report_questions()
			session.start_quiz()
			game.terminal_ui.launch_app(&"chat")


func advance(delta: float) -> void:
	if state == State.DEADLINE or state == State.SCARE:
		seconds_left = maxf(0, seconds_left - delta)
		if seconds_left <= 0:
			if state == State.DEADLINE:
				state = State.ENDED
				game._finish_report(false, 0)
			else:
				stage += 1
				_load_stage()
				_begin_route(DATA.SHOP if stage == 1 else DATA.STREET_ENTRY)
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
					route.append({"point": DATA.EXITS[branch], "seconds": 28.0})
					route.append({"point": DATA.EXITS[branch] + Vector3(0, 0, -5), "seconds": 16.0})
				else:
					location.event(event)
				step += 1
				step_time = 0
				start_point = location.target.position
				if step == route.size():
					_finish_stage()


func _finish_stage() -> void:
	if stage == 2:
		state = State.REPORT
		return
	state = State.SCARE
	seconds_left = 5.0
	# A real scare will call complete_scare(); this explicit test event lasts five seconds.
	if game.dev_menu.is_open:
		game.dev_menu.close_menu()
	game.power.board.set_active(false)
	game.power.set_interacting(false)
	game._kill_transition()
	game.terminal_ui.suspend_desktop()
	game.terminal_ui.hide()
	if game.mode in [game.Mode.ENTERING, game.Mode.COMPUTER, game.Mode.LEAVING]:
		game.player.place_at(game.terminal.get_node("ExitPoint"))
	game._resume_walking()
	game._release_pointer()


func complete_scare() -> void:
	if state == State.SCARE:
		advance(seconds_left)


func _update_status() -> void:
	if not is_instance_valid(status):
		return
	var text := ""
	match state:
		State.INTRO: text = tr("OBS_WAIT_INTRO")
		State.DEADLINE: text = tr("OBS_DEADLINE") % ceili(seconds_left)
		State.ROUTE: text = tr("OBS_RUNNING")
		State.SCARE: text = tr("OBS_SCARE") % ceili(seconds_left)
		State.REPORT: text = tr("OBS_RETURN")
	status.text = text
	status.visible = state in [State.DEADLINE, State.SCARE, State.REPORT]
	if state == State.REPORT and game.mode == game.Mode.COMPUTER:
		status.hide()
	hack_status.text = text
	hack_button.disabled = state != State.DEADLINE or not game.power.powered


func report_questions() -> Array:
	var codes := [code, "%04d" % (1000 + (int(code) - 1000 + 127) % 9000), "%04d" % (1000 + (int(code) - 1000 + 513) % 9000)]
	codes.shuffle()
	return [
		{"id": "code", "prompt": "OBS_Q_CODE", "answers": codes, "correct": code},
		{"id": "drink", "prompt": "OBS_Q_DRINK", "answers": DATA.DRINKS, "correct": DATA.DRINKS[drink]},
		{"id": "path", "prompt": "OBS_Q_PATH", "answers": DATA.PATHS, "correct": DATA.PATHS[maxi(branch, 0)]},
	]
