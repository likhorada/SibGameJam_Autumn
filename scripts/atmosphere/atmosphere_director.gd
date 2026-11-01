class_name AtmosphereDirector
extends Node
## Non-lethal, run-local events. No presentation or player movement lives here.
signal event_started(id: StringName)
signal event_finished(id: StringName, outcome: StringName)

@export var config: AtmosphereConfig = preload("res://data/atmosphere/default.tres")
var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			cancel(&"disabled")
var game: Node3D
var armed: bool = false
var active_id: StringName = &""
var seconds_left: float = 0.0
var wait_seconds_left: float = 0.0
var random_count: int = 0
var random_limit: int = 0
var used: Dictionary = {}
var reserves: Array[StringName] = [&"", &""]
var transition_pending: bool = false
var transition_index: int = -1
var history: PackedStringArray = []
var _profiles: Dictionary = {}
var _active: AtmosphereEvent
var _finishing: bool = false
var _starting: bool = false
var _early_outcome: StringName = &""
var _rng := RandomNumberGenerator.new()


func bind(value: Node3D) -> void:
	game = value
	_rng.randomize()
	for profile: AtmosphereProfile in config.events:
		if profile == null or profile.id == &"" or _profiles.has(profile.id) or profile.scene == null or not is_finite(profile.timeout_seconds) or profile.timeout_seconds <= 0.0:
			note("Invalid/duplicate atmosphere profile skipped")
			continue
		_profiles[profile.id] = profile
	_schedule()


func start_run() -> void:
	if armed:
		return
	armed = true
	random_limit = _rng.randi_range(config.min_random_events, maxi(config.min_random_events, config.max_random_events))
	for index: int in 2:
		reserves[index] = _pick(_candidates(true, false, false))
	note("Armed; reserves: %s" % str(reserves))


func note(message: String) -> void:
	history.append(message)
	while history.size() > 12:
		history.remove_at(0)


func is_busy() -> bool:
	return active_id != &"" or _finishing


func context() -> StringName:
	if game.mode == game.Mode.COMPUTER:
		return &"computer"
	if game.mode == game.Mode.WALKING:
		return &"walking"
	return &"unstable"


func blocked_reason(ignore_menu: bool = false) -> String:
	if not enabled:
		return "disabled"
	if game.run_ended or not game.capture_reason.is_empty() or game.terminal_ui.chat.session.quiz_started:
		return "run ended / quiz"
	if game.dev_menu.is_open and not ignore_menu:
		return "dev menu"
	if game.threats.is_busy() or game.threats.capture_in_progress:
		return "active threat"
	if not game.power.powered:
		return "blackout"
	if context() == &"unstable":
		return "hiding / interaction / camera transition"
	# Respect other systems' reservations, but not our own pending transition.
	var ignored: Array[StringName] = [&"atmosphere", &"atmosphere_pending"]
	var reason: StringName = game.threats.blocking_reason_except(ignored)
	if reason != &"":
		return "world blocker: " + String(reason)
	return ""


func request_transition(index: int) -> void:
	if transition_pending or index < 0 or index >= reserves.size():
		return
	transition_pending = true
	transition_index = index
	game.threats.set_blocked(&"atmosphere_pending", true)
	if is_busy():
		# An already running random event fulfils this transition.
		reserves[index] = &""
		note("Transition %d uses active %s; reserve released" % [index, active_id])
	try_transition()


func try_transition() -> void:
	if not transition_pending or is_busy():
		return
	if not enabled:
		_end_transition("Atmosphere disabled; transition skipped")
		return
	if not blocked_reason().is_empty():
		return
	var candidates := _candidates(true, true, false, transition_index)
	var selected: StringName = reserves[transition_index]
	if selected not in candidates:
		selected = _pick(candidates)
	reserves[transition_index] = &""
	# Try each candidate once if its setup fails; never stall the route on bad content.
	var attempted: Array[StringName] = []
	while true:
		if selected == &"":
			candidates = _candidates(true, true, true, transition_index).filter(func(id: StringName) -> bool: return id not in attempted)
			selected = _pick(candidates)
			if selected == &"":
				break
			if used.has(selected):
				note("Transition fallback repeat: " + String(selected))
		attempted.append(selected)
		if request_event(selected, false, true):
			return
		candidates.erase(selected)
		selected = _pick(candidates.filter(func(id: StringName) -> bool: return id not in attempted))
	_end_transition("Transition %d skipped: no suitable event" % transition_index)


func request_event(id: StringName, forced: bool = false, for_transition: bool = false) -> bool:
	if is_busy() or not blocked_reason(forced).is_empty() or not _profiles.has(id):
		return false
	if transition_pending and not for_transition:
		return false
	var profile: AtmosphereProfile = _profiles[id]
	if not _matches(profile, true) or (not forced and not for_transition and (used.has(id) or id in reserves)):
		return false
	if for_transition and not profile.transition_trigger:
		return false
	if not forced and not for_transition:
		if not armed or not profile.random_trigger or wait_seconds_left > 0.0 or random_count >= random_limit:
			return false
		if not is_instance_valid(game.shift) or game.shift.state not in [ShiftDirector.State.ROUTE, ShiftDirector.State.REPORT]:
			return false
	var instance := profile.scene.instantiate()
	if not instance is AtmosphereEvent:
		instance.free()
		note("Invalid handler: " + String(id))
		return false
	_active = instance
	active_id = id
	seconds_left = profile.timeout_seconds
	game.threats.set_blocked(&"atmosphere", true)
	instance.finished.connect(_on_finished.bind(instance))
	_starting = true
	_early_outcome = &""
	add_child(instance)
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		_starting = false
		_finish(&"setup_failed")
		return false
	var accepted: bool = instance.start(game)
	_starting = false
	if not accepted:
		_finish(&"setup_failed")
		return false
	used[id] = true
	note("Started: " + String(id))
	var immediate_outcome := _early_outcome
	event_started.emit(id)
	if _active == instance and immediate_outcome != &"":
		_finish(immediate_outcome)
	return true


func _on_finished(outcome: StringName, source: AtmosphereEvent) -> void:
	if source != _active:
		return
	if _starting:
		_early_outcome = outcome if outcome != &"" else &"completed"
	else:
		_finish(outcome)


func _finish(outcome: StringName) -> void:
	if active_id == &"" or _finishing:
		return
	_finishing = true
	var current := _active
	var id := active_id
	_active = null
	active_id = &""
	seconds_left = 0.0
	if is_instance_valid(current):
		current.ended(outcome)
		if is_instance_valid(current):
			current.queue_free()
	game.threats.set_blocked(&"atmosphere", false)
	_finishing = false
	note("Finished: %s / %s" % [id, outcome])
	_schedule()
	if transition_pending and outcome != &"setup_failed":
		_end_transition("Transition %d completed" % transition_index)
	event_finished.emit(id, outcome)


func complete_event() -> void:
	_finish(&"dev_completed")


func cancel(outcome: StringName = &"cancelled") -> void:
	_finish(outcome)
	if transition_pending:
		_end_transition("Transition cancelled: " + String(outcome))


func _end_transition(message: String) -> void:
	note(message)
	if transition_index >= 0:
		reserves[transition_index] = &""
	transition_pending = false
	transition_index = -1
	game.threats.set_blocked(&"atmosphere_pending", false)


func _matches(profile: AtmosphereProfile, check_context: bool) -> bool:
	return profile.enabled and is_finite(profile.weight) and profile.weight > 0.0 and (not check_context or (profile.at_computer if context() == &"computer" else profile.walking))


func _candidates(for_transition: bool, check_context: bool, allow_used: bool, reserve_slot: int = -1) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _profiles:
		var profile: AtmosphereProfile = _profiles[id]
		if not _matches(profile, check_context) or (not allow_used and used.has(id)):
			continue
		if not (profile.transition_trigger if for_transition else profile.random_trigger):
			continue
		var reserved_elsewhere := false
		for index: int in reserves.size():
			if index != reserve_slot and reserves[index] == id:
				reserved_elsewhere = true
		if reserved_elsewhere:
			continue
		result.append(id)
	return result


func _pick(candidates: Array) -> StringName:
	var total: float = 0.0
	for id: StringName in candidates:
		total += _profiles[id].weight
	var roll := _rng.randf() * total
	for id: StringName in candidates:
		roll -= _profiles[id].weight
		if roll <= 0.0:
			return id
	return &""


func clear_cooldown() -> void:
	wait_seconds_left = 0.0


func _schedule() -> void:
	wait_seconds_left = _rng.randf_range(maxf(1.0, config.min_interval), maxf(config.min_interval, config.max_interval))


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if delta < 0.0 or not is_instance_valid(game):
		return
	if game.run_ended or not game.capture_reason.is_empty() or game.terminal_ui.chat.session.quiz_started:
		cancel(&"run ended / quiz")
		return
	if is_busy():
		if not is_instance_valid(_active) or _active.is_queued_for_deletion():
			_finish(&"unavailable")
			return
		var current := _active
		current.advance(delta)
		if current == _active:
			seconds_left = maxf(0.0, seconds_left - delta)
			if seconds_left <= 0.0:
				_finish(&"timeout")
		return
	if transition_pending:
		try_transition()
		return
	if not armed or not blocked_reason().is_empty() or random_count >= random_limit or not is_instance_valid(game.shift):
		return
	if game.shift.state not in [ShiftDirector.State.ROUTE, ShiftDirector.State.REPORT]:
		return
	wait_seconds_left = maxf(0.0, wait_seconds_left - delta)
	if wait_seconds_left > 0.0:
		return
	var id := _pick(_candidates(false, true, false))
	if id != &"" and request_event(id):
		random_count += 1
	_schedule()


func debug_status() -> String:
	return "Atmosphere: %s / %s (%.1fs), context: %s\nRandom: %d/%d; wait %.1fs; status: %s\nPool: %s; used: %s\nReserves: %s; transition: %s\n%s" % [
		"ON" if enabled else "OFF", active_id, seconds_left, context(), random_count, random_limit,
		wait_seconds_left, scheduling_reason(), str(_profiles.keys()), str(used.keys()), str(reserves),
		str(transition_index), "\n".join(history)]


func scheduling_reason() -> String:
	var reason := blocked_reason()
	if not reason.is_empty():
		return reason
	if is_busy():
		return "event active"
	if transition_pending:
		return "transition pending"
	if not armed:
		return "waiting for ALARM.sh"
	if not is_instance_valid(game.shift) or game.shift.state not in [ShiftDirector.State.ROUTE, ShiftDirector.State.REPORT]:
		return "outside observation / return"
	if random_count >= random_limit:
		return "random limit reached"
	if _candidates(false, true, false).is_empty():
		return "no unused, unreserved candidates for context"
	return "cooldown" if wait_seconds_left > 0.0 else "ready"


func event_ids() -> Array:
	return _profiles.keys()


func _exit_tree() -> void:
	cancel(&"teardown")
