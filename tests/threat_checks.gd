extends Node
## Probe adapters exist only in tests, never in the production scene/export.

class ProbeEvent extends ThreatEvent:
	var available: bool = true
	var warnings: int = 0
	var activations: int = 0
	var resolutions: Array[StringName] = []
	var endings: Array[StringName] = []
	var resolve_on_activation: bool = false

	func can_start() -> bool:
		return available

	func warning_started() -> void:
		warnings += 1

	func active_started() -> void:
		activations += 1
		if resolve_on_activation:
			resolved.emit(&"survived")

	func resolved_started(outcome: StringName) -> void:
		resolutions.append(outcome)

	func ended(outcome: StringName) -> void:
		endings.append(outcome)

var failures: int = 0
var root: Window:
	get:
		return get_tree().root


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("THREATS: " + message)


func _run() -> void:
	var manager := ThreatManager.new()
	manager.config = load("res://data/threats/default.tres").duplicate(true)
	root.add_child(manager)
	manager.set_process(false)
	manager._rng.seed = 42
	manager.config.min_interval = 25.0
	manager.config.max_interval = 25.0
	manager.reset_run()
	var neighbor := ProbeEvent.new()
	var police := ProbeEvent.new()
	var outage := ProbeEvent.new()
	expect(manager.register_event(&"psych_neighbor", neighbor), "Neighbor probe registers")
	expect(manager.register_event(&"police_raid", police), "Police probe registers")
	expect(manager.register_event(&"power_outage", outage), "Outage probe registers")
	var duplicate := ProbeEvent.new()
	expect(not manager.register_event(&"psych_neighbor", duplicate), "Duplicate adapter is rejected")
	expect(not manager.register_event(&"unknown", duplicate), "Unknown profile is rejected")
	duplicate.free()
	manager.advance(100.0)
	expect(not manager.is_busy() and manager.wait_seconds_left == 25.0, "Briefing time cannot consume random interval")
	manager.reset_run()
	manager.random_allowed = true
	manager.advance(44.0)
	expect(not manager.is_busy() and manager.wait_seconds_left == 25.0, "Opening grace precedes selection timer")
	manager.advance(1.0)
	manager.advance(24.0)
	expect(not manager.is_busy(), "No random attack before complete eligible interval")
	manager.advance(1.0)
	expect(manager.state == ThreatManager.State.WARNING, "One weighted event starts after eligible interval")
	expect(neighbor.warnings + police.warnings + outage.warnings == 1, "Exactly one event selected")
	expect(not manager.request_event(&"police_raid", true), "Forced command cannot overlap a warning")
	expect(not manager.can_start_external_event(), "Existing power cannot overlap a threat")
	manager.enabled = false
	expect(not manager.is_busy() and not manager.enabled, "Inspector master toggle clears active reservation")
	manager.advance(1000.0)
	expect(not manager.request_event(&"psych_neighbor", true), "Disable blocks both random and forced events")
	expect(neighbor.endings.size() + police.endings.size() + outage.endings.size() == 1, "Disable cleans adapter once")
	manager.reset_run()
	expect(manager.run_seconds == 0.0 and manager.eligible_seconds == 0.0 and manager.active_id.is_empty(), "Reset clears clocks and active ID")
	expect(manager.request_event(&"psych_neighbor", true), "Forced test bypasses grace and briefing")
	manager.advance(5.0)
	expect(manager.state == ThreatManager.State.ACTIVE and neighbor.activations == 1, "Warning advances to active")
	neighbor.resolved.emit(&"survived")
	expect(manager.state == ThreatManager.State.RESOLVED and manager.is_busy(), "Departure retains exclusive slot")
	expect(not manager.request_event(&"police_raid", true), "Resolved blocks a second event too")
	manager.advance(1.0)
	expect(manager.state == ThreatManager.State.IDLE and manager.safe_seconds_left == 20.0, "Resolution returns to idle with safe interval")
	neighbor.resolved.emit(&"late")
	expect(manager.state == ThreatManager.State.IDLE, "Late adapter signals cannot resurrect an event")
	manager.random_allowed = true
	manager.advance(19.0)
	expect(manager.wait_seconds_left == 25.0, "Safety cannot consume random selection interval")
	manager.run_seconds = 100.0
	manager.advance(1.0)
	manager.advance(24.0)
	expect(not manager.is_busy(), "Full selection interval follows safety")
	manager.set_blocked(&"scripted_scare", true)
	manager.advance(60.0)
	expect(not manager.is_busy() and not manager.request_event(&"police_raid", true), "Scare blocks random and forced starts")
	manager.set_blocked(&"scripted_scare", false)
	manager.set_blocked(&"blackout", true)
	expect(not manager.request_event(&"psych_neighbor", true), "Existing blackout reserves the world")
	manager.set_blocked(&"blackout", false)
	manager.reset_run()
	manager.request_event(&"police_raid", true)
	manager.advance(12.0)
	manager.advance(20.0)
	expect(manager.state == ThreatManager.State.RESOLVED and police.resolutions.back() == &"timeout", "Watchdog prevents a finite event from softlocking")
	manager.advance(1.0)
	expect(police.endings.back() == &"timeout", "Watchdog eventually cleans adapter")
	manager.request_event(&"power_outage", true)
	manager.advance(2.0)
	manager.advance(1000.0)
	expect(manager.state == ThreatManager.State.ACTIVE, "Zero watchdog permits waiting for real power repair")
	manager.set_event_enabled(&"power_outage", false)
	expect(not manager.is_busy() and outage.endings.back() == &"disabled", "Per-event disable cleans current event")
	expect(not manager.request_event(&"power_outage", true), "Per-event disable blocks forced commands")
	expect(load("res://data/threats/default.tres").profile_for(&"power_outage").enabled, "Runtime toggles never modify shared defaults")
	manager.reset_run()
	police.resolve_on_activation = true
	manager.request_event(&"police_raid", true)
	manager.advance(12.0)
	expect(manager.state == ThreatManager.State.RESOLVED, "Synchronous resolution from active callback is safe")
	manager.advance(1.0)
	manager.reset_run()
	manager.config.opening_safe_seconds = 0.0
	manager.config.event_chance = 0.0
	manager.random_allowed = true
	manager.advance(1000.0)
	expect(not manager.is_busy(), "Zero probability prevents random events even after long frames")
	manager.config.event_chance = 1.0
	manager.set_event_enabled(&"psych_neighbor", false)
	manager.set_event_enabled(&"police_raid", false)
	outage.available = false
	manager.advance(1000.0)
	expect(not manager.is_busy(), "Unavailable and disabled adapters cannot be selected")
	manager.reset_run()
	manager.eligible_seconds = manager.config.ramp_seconds
	manager._schedule()
	expect(is_equal_approx(manager.wait_seconds_left, 25.0 * 0.65), "Difficulty scales only selection interval")
	expect(manager.config.profile_for(&"police_raid").warning_seconds == 12.0, "Difficulty leaves response windows unchanged")
	manager.queue_free()
	await get_tree().process_frame
	await _integration()
	print("THREAT SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)


func _integration() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	get_tree().current_scene = game
	game.transition_seconds = 0.02
	var manager: ThreatManager = game.threats
	manager.set_process(false)
	expect(manager._events.size() == 2 and manager._events[&"psych_neighbor"] is PsychNeighbor and manager._events[&"police_raid"] is PoliceRaid, "Production registers two real threats")
	var neighbor: PsychNeighbor = game.neighbor
	manager.request_event(&"psych_neighbor", true)
	game.power.trigger_outage()
	expect(game.power.powered, "Real outage is rejected while event owns the slot")
	game.shift._finish_stage()
	expect(game.shift.state == ShiftDirector.State.WAITING_SCARE, "Real story scare queues behind active event")
	neighbor.resolved.emit(&"survived")
	manager.advance(1.0)
	game.shift._process(0.0)
	expect(game.shift.state == ShiftDirector.State.SCARE, "Queued scare starts after event cleanup")
	expect(not manager.request_event(&"psych_neighbor", true), "Story scare owns reservation")
	game.power.trigger_outage()
	expect(game.power.powered, "Power cannot interrupt the scripted scare")
	game.shift.complete_scare()
	expect(not manager.has_blocker(&"scripted_scare"), "Scare completion releases reservation")
	game.power.random_outages_enabled = false
	game.power.trigger_outage()
	expect(not game.power.powered and manager.has_blocker(&"blackout"), "Real blackout holds blocker until repair")
	expect(not manager.request_event(&"psych_neighbor", true), "Probe cannot start during real blackout")
	game.disable_threats()
	expect(game.power.powered and not manager.has_blocker(&"blackout") and not manager.enabled, "DisableThreats safely restores real power and clears blocker")
	manager.reset_run()
	var outage := ProbeEvent.new()
	manager.register_event(&"power_outage", outage)
	manager.request_event(&"power_outage", true)
	game.power.trigger_outage()
	expect(not game.power.powered and manager.active_id == &"power_outage", "Power adapter can cut real power inside its own reservation")
	expect(not manager.request_event(&"psych_neighbor", true), "Power adapter permission cannot admit a second threat")
	game.disable_threats()
	expect(game.power.powered and outage.endings == [&"disabled"], "Disabling a reserved blackout cleans adapter and restores real power")
	game.queue_free()
	await get_tree().process_frame
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	get_tree().current_scene = game
	manager = game.threats
	manager.set_process(false)
	expect(manager.enabled and manager.active_id.is_empty() and manager.run_seconds < 1.0 and manager._events.size() == 2, "New scene resets flags and active event, and registers fresh threats")
	neighbor = game.neighbor
	manager.request_event(&"psych_neighbor", true)
	game.shift.stage = 2
	game.shift._finish_stage()
	game.mode = game.Mode.COMPUTER
	game.shift._process(0.0)
	expect(not game.terminal_ui.chat.session.quiz_started, "Final report waits for outstanding threat")
	expect(not manager.random_allowed and not game.power.random_outages_enabled, "Report disables new random threats including legacy outages")
	neighbor.resolved.emit(&"survived")
	manager.advance(1.0)
	game.shift._process(0.0)
	expect(game.terminal_ui.chat.session.quiz_started, "Report opens after active event resolves")
	manager.request_event(&"psych_neighbor", true)
	game._finish_report(false, 0)
	expect(not manager.enabled and not manager.is_busy() and neighbor.visit == PsychNeighbor.Visit.DORMANT, "Result stops threat scheduling and cleans active slot")
	game.queue_free()
	await get_tree().process_frame
