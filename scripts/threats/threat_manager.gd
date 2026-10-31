class_name ThreatManager
extends Node
## Run-local scheduler. Only registered, available adapters can be selected.

signal state_changed(state: State, event_id: StringName)
signal event_finished(event_id: StringName, outcome: StringName)

enum State { IDLE, WARNING, ACTIVE, RESOLVED }

@export var config: ThreatConfig = preload("res://data/threats/default.tres")
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			_finish_event(&"disabled")

var state: State = State.IDLE
var active_id: StringName = &""
var random_allowed: bool = false
var run_seconds: float = 0.0
var eligible_seconds: float = 0.0
var safe_seconds_left: float = 0.0
var wait_seconds_left: float = 0.0
var phase_seconds_left: float = 0.0
var _events: Dictionary = {}
var _event_enabled: Dictionary = {}
var _blockers: Dictionary = {}
var _active_event: ThreatEvent
var _outcome: StringName = &""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_schedule()


func _process(delta: float) -> void:
	advance(delta)


func register_event(id: StringName, event: ThreatEvent) -> bool:
	if config.profile_for(id) == null or _events.has(id) or not is_instance_valid(event):
		return false
	if event.get_parent() != null:
		return false
	_events[id] = event
	add_child(event)
	event.resolved.connect(_on_event_resolved.bind(event))
	return true


func is_registered(id: StringName) -> bool:
	return _events.has(id) and is_instance_valid(_events[id])


func is_busy() -> bool:
	# Keep the slot throughout Resolved, including departure/cleanup sounds.
	return state != State.IDLE


func set_blocked(reason: StringName, value: bool) -> void:
	if value:
		_blockers[reason] = true
	else:
		_blockers.erase(reason)


func has_blocker(reason: StringName) -> bool:
	return _blockers.has(reason)


func can_start_external_event() -> bool:
	return enabled and not is_busy() and _blockers.is_empty()


func can_start_power_outage() -> bool:
	# A future power_outage adapter must be able to cut power inside its own slot.
	# This permission does NOT allow a second threat to claim that slot.
	return enabled and (active_id == &"power_outage" or can_start_external_event())


func set_event_enabled(id: StringName, value: bool) -> void:
	# Do not mutate the shared .tres resource or another run's settings.
	_event_enabled[id] = value
	if not value and active_id == id:
		_finish_event(&"disabled")


func is_event_enabled(id: StringName) -> bool:
	var profile := config.profile_for(id)
	return profile != null and bool(_event_enabled.get(id, profile.enabled))


func request_event(id: StringName, forced: bool = false) -> bool:
	# Forced tests bypass timing/selection, never exclusivity or world blockers.
	if not can_start_external_event() or not _available(id):
		return false
	if not forced and (not random_allowed or run_seconds < config.opening_safe_seconds or safe_seconds_left > 0.0 or wait_seconds_left > 0.0):
		return false
	active_id = id
	_active_event = _events[id]
	_outcome = &""
	state = State.WARNING
	phase_seconds_left = maxf(0.0, config.profile_for(id).warning_seconds)
	state_changed.emit(state, active_id)
	if state == State.WARNING and active_id == id:
		_active_event.warning_started()
	return true


func advance(delta: float) -> void:
	if not enabled or delta < 0.0:
		return
	run_seconds += delta
	if is_busy():
		_advance_event(delta)
		return
	# Safety elapses in world time. Selection time only elapses while eligible.
	var eligible_delta := minf(delta, maxf(0.0, run_seconds - config.opening_safe_seconds))
	eligible_delta = minf(eligible_delta, maxf(0.0, delta - safe_seconds_left))
	safe_seconds_left = maxf(0.0, safe_seconds_left - delta)
	if not random_allowed or not _blockers.is_empty():
		return
	eligible_seconds += eligible_delta
	wait_seconds_left = maxf(0.0, wait_seconds_left - eligible_delta)
	if wait_seconds_left > 0.0 or eligible_delta <= 0.0:
		return
	var candidates: Array[StringName] = []
	var total_weight: float = 0.0
	for id: StringName in _events:
		if _available(id):
			candidates.append(id)
			total_weight += config.profile_for(id).weight
	# No catch-up burst after a long frame, repair, tab switch or dev session.
	if total_weight > 0.0 and _rng.randf() < config.event_chance:
		var roll := _rng.randf() * total_weight
		for id: StringName in candidates:
			roll -= config.profile_for(id).weight
			if roll <= 0.0:
				if request_event(id):
					return
	_schedule()


func _available(id: StringName) -> bool:
	var profile := config.profile_for(id)
	return profile != null and bool(_event_enabled.get(id, profile.enabled)) and profile.weight > 0.0 and is_registered(id) and _events[id].can_start()


func _advance_event(delta: float) -> void:
	if not is_instance_valid(_active_event):
		_finish_event(&"unavailable")
		return
	var current := _active_event
	var previous_state := state
	var id := active_id
	current.advance(delta)
	if current != _active_event or state != previous_state:
		return
	phase_seconds_left = maxf(0.0, phase_seconds_left - delta)
	if phase_seconds_left > 0.0:
		return
	match state:
		State.WARNING:
			state = State.ACTIVE
			phase_seconds_left = maxf(0.0, config.profile_for(id).max_active_seconds)
			state_changed.emit(state, active_id)
			if state == State.ACTIVE and current == _active_event:
				current.active_started()
		State.ACTIVE:
			if config.profile_for(id).max_active_seconds > 0.0:
				_resolve(&"timeout")
		State.RESOLVED:
			_finish_event(_outcome)


func _on_event_resolved(outcome: StringName, event: ThreatEvent) -> void:
	# Ignore late signals from an adapter that no longer owns the slot.
	if event == _active_event and state in [State.WARNING, State.ACTIVE]:
		_resolve(outcome)


func _resolve(outcome: StringName) -> void:
	_outcome = outcome
	state = State.RESOLVED
	phase_seconds_left = maxf(0.0, config.profile_for(active_id).resolved_seconds)
	var current := _active_event
	state_changed.emit(state, active_id)
	if state == State.RESOLVED and current == _active_event:
		current.resolved_started(outcome)


func _finish_event(outcome: StringName) -> void:
	if not is_busy():
		return
	var id := active_id
	var current := _active_event
	_active_event = null
	active_id = &""
	state = State.IDLE
	phase_seconds_left = 0.0
	safe_seconds_left = maxf(0.0, config.safe_seconds)
	_schedule()
	if is_instance_valid(current):
		current.ended(outcome)
	state_changed.emit(state, active_id)
	event_finished.emit(id, outcome)


func disable_threats() -> void:
	enabled = false
	_finish_event(&"disabled")


func reset_run() -> void:
	disable_threats()
	_blockers.clear()
	_event_enabled.clear()
	random_allowed = false
	run_seconds = 0.0
	eligible_seconds = 0.0
	safe_seconds_left = 0.0
	phase_seconds_left = 0.0
	enabled = true
	_schedule()


func _schedule() -> void:
	var progress := clampf(eligible_seconds / maxf(1.0, config.ramp_seconds), 0.0, 1.0)
	var scale := lerpf(1.0, clampf(config.final_interval_scale, 0.1, 1.0), progress)
	var minimum := maxf(0.1, config.min_interval)
	wait_seconds_left = _rng.randf_range(minimum, maxf(minimum, config.max_interval)) * scale


func _exit_tree() -> void:
	disable_threats()
