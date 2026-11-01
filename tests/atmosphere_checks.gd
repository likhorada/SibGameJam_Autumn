extends Node
var failures: int = 0
var game: Node3D
var director: AtmosphereDirector


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("ATMOSPHERE: " + message)


func profile(id: StringName, computer: bool = true, walking: bool = true, immediate: bool = false, fail: bool = false) -> AtmosphereProfile:
	var result := AtmosphereProfile.new()
	result.id = id
	result.at_computer = computer
	result.walking = walking
	var probe := Node.new()
	probe.set_script(load("res://tests/atmosphere_probe.gd"))
	probe.immediate = immediate
	probe.fail_start = fail
	result.scene = PackedScene.new()
	result.scene.pack(probe)
	probe.free()
	return result


func make_game(profiles: Array[AtmosphereProfile]) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	var settings := AtmosphereConfig.new()
	settings.events = profiles
	game.atmosphere_config = settings
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.shift.set_process(false)
	game.threats.set_process(false)
	director = game.atmosphere
	director.set_process(false)
	expect(game.dev_menu._atmosphere_list.item_count == director.event_ids().size(), "Dev selector exposes configured pool")


func discard() -> void:
	game.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	make_game([])
	game.mode = game.Mode.COMPUTER
	game.shift._finish_stage()
	expect(game.shift.stage == 1 and game.shift.state == ShiftDirector.State.ROUTE, "Empty pool skips transition without a pause")
	expect(game.mode == game.Mode.COMPUTER and not game.threats.has_blocker(&"atmosphere_pending"), "No ejection or stale blocker")
	expect(not game.shift.status.visible, "No test-scare HUD")
	expect(not director.history.is_empty(), "Empty transition recorded in dev diagnostics")
	await discard()

	make_game([profile(&"a"), profile(&"b"), profile(&"c"), profile(&"d")])
	director.clear_cooldown()
	director.advance(100)
	expect(not director.is_busy() and not director.armed, "No random event before alarm")
	director.start_run()
	expect(director.reserves[0] != &"" and director.reserves[0] != director.reserves[1], "Two distinct reservations")
	game.shift.state = ShiftDirector.State.ROUTE
	director.random_limit = 2
	director.clear_cooldown()
	director.advance(100)
	expect(director.is_busy() and director.random_count == 1, "Long frame starts at most one random event")
	expect(director.active_id not in director.reserves, "Random event never consumes reserved IDs")
	var active: AtmosphereEvent = director._active
	var used_id := director.active_id
	expect(not game.trigger_neighbor() and not game.trigger_power_outage(), "Threats and outages wait for atmosphere")
	game.mode = game.Mode.COMPUTER
	director.advance(0.5)
	expect(director._active == active, "Context switch does not cancel active event")
	game.shift.stage = 0
	game.shift._finish_stage()
	expect(game.shift.state == ShiftDirector.State.EVENT and director.reserves[0] == &"", "Existing random event fulfils transition and releases reserve")
	director.advance(2)
	expect(not director.is_busy() and active.cleanup_count == 1, "Completion cleans exactly once")
	active.finished.emit(&"late")
	expect(not director.is_busy(), "Late signal is ignored")
	game.shift._process(0)
	expect(game.shift.stage == 1 and game.mode == game.Mode.COMPUTER, "Next route starts with PC unchanged")
	expect(used_id not in director._candidates(false, true, false), "Started event is not randomly repeated")
	expect(not game.threats.has_blocker(&"atmosphere"), "Completion releases threat slot")
	expect(director.request_event(used_id, true), "Safe dev force bypasses one-shot restriction")
	active = director._active
	director.enabled = false
	expect(active.cleanup_count == 1 and not director.is_busy(), "Disable cancels and cleans event")
	expect(game.threats.enabled, "Atmosphere disable does not disable threats")
	director.enabled = true
	game.mode = game.Mode.HIDING
	expect(not director.request_event(used_id, true), "Dev force cannot bypass hiding")
	game.mode = game.Mode.FUSEBOX
	expect(not director.request_event(used_id, true), "Dev force cannot bypass repair")
	game.mode = game.Mode.ENTERING
	expect(not director.request_event(used_id, true), "Dev force cannot bypass camera transitions")
	game.mode = game.Mode.WALKING
	expect(game.trigger_neighbor(), "Threat can start once atmosphere releases slot")
	expect(not director.request_event(used_id, true), "Atmosphere cannot overlap active threat")
	game.threats.set_event_enabled(&"psych_neighbor", false)
	expect(director.request_event(used_id, true), "No extra grace period after threat")
	active = director._active
	director.seconds_left = 0.1
	director.advance(0.2)
	expect(not director.is_busy() and active.last_outcome == &"timeout", "Per-event watchdog releases slot")
	await discard()

	make_game([profile(&"walking", false, true), profile(&"pc", true, false)])
	director.start_run()
	director.reserves = [&"walking", &""]
	game.mode = game.Mode.COMPUTER
	game.shift._finish_stage()
	expect(director.active_id == &"pc", "Transition replaces unsuitable reserve for current context")
	director.complete_event()
	game.shift._process(0)
	director.reserves[1] = &"pc"
	game.shift._finish_stage()
	expect(director.active_id == &"pc", "Guaranteed transition may repeat exhausted suitable content")
	director.cancel()
	game.shift._process(0)
	expect(game.shift.stage == 2, "Cancelled event releases transition")
	await discard()

	make_game([profile(&"instant", true, true, true)])
	director.start_run()
	game.shift._finish_stage()
	expect(game.shift.stage == 1 and not director.is_busy(), "Synchronous completion is safe")
	expect(director.used.has(&"instant"), "Synchronous completion consumes one-shot")
	await discard()

	make_game([profile(&"broken", true, true, false, true)])
	director.start_run()
	game.shift._finish_stage()
	expect(game.shift.stage == 1 and not director.is_busy(), "Failed setup cannot lock transition")
	expect(not director.used.has(&"broken"), "Failed setup does not consume one-shot")
	expect(not game.threats.has_blocker(&"atmosphere"), "Failed setup releases blocker")
	await discard()

	make_game([profile(&"broken", true, true, false, true), profile(&"repeat")])
	director.start_run()
	director.reserves = [&"broken", &""]
	director.used[&"repeat"] = true
	game.shift._finish_stage()
	expect(director.active_id == &"repeat", "Failed fresh candidates fall back to valid used content")
	director.complete_event()
	game.shift._process(0)
	director.request_event(&"repeat", true)
	director._active.queue_free()
	await get_tree().process_frame
	director.advance(0)
	expect(not director.is_busy() and not game.threats.has_blocker(&"atmosphere"), "Missing handler cannot leak world reservation")
	director.request_event(&"repeat", true)
	var director_ref: WeakRef = weakref(director)
	var event_ref: WeakRef = weakref(director._active)
	await discard()
	expect(director_ref.get_ref() == null and event_ref.get_ref() == null, "Live teardown frees director and event")

	make_game([profile(&"final")])
	director.start_run()
	game.mode = game.Mode.HIDING
	game.shift._finish_stage()
	expect(game.shift.state == ShiftDirector.State.WAITING_EVENT, "Transition waits in hiding")
	game.mode = game.Mode.WALKING
	game.shift._process(0)
	expect(director.is_busy(), "Transition starts in stable context")
	director.cancel()
	game.shift._process(0)
	game.shift.stage = 2
	game.shift.state = ShiftDirector.State.REPORT
	director.random_limit = 2
	director.reserves = [&"", &""]
	director.used.clear()
	director.clear_cooldown()
	director.advance(100)
	expect(director.is_busy(), "Random events allowed while returning for report")
	active = director._active
	game.mode = game.Mode.COMPUTER
	game.shift._process(0)
	expect(game.terminal_ui.chat.session.quiz_started and not director.is_busy(), "Quiz cancels event immediately")
	expect(active.last_outcome == &"quiz_started", "Quiz invokes cleanup")
	expect(not director.request_event(&"final", true), "No dev event during quiz")
	await discard()

	make_game([profile(&"reserve_a"), profile(&"reserve_b")])
	director.start_run()
	game.mode = game.Mode.HIDING
	game.shift._finish_stage()
	director.enabled = false
	expect(not director.transition_pending and director.reserves[0] == &"", "Disabled pending transition releases unused reserve")
	game.shift._process(0)
	expect(game.shift.stage == 1 and not game.threats.has_blocker(&"atmosphere_pending"), "Disable cannot leave route blocked")
	await discard()

	make_game([profile(&"cleanup")])
	expect(director.used.is_empty() and not director.armed, "New run has fresh state")
	director.request_event(&"cleanup", true)
	active = director._active
	game._finish_report(false, 0)
	expect(active.cleanup_count == 1 and not director.enabled, "Run end cleans before freezing game")
	await discard()
	print("ATMOSPHERE SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(0 if failures == 0 else 1)
