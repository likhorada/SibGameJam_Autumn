class_name FirewallRound
extends RefCounted
## Fictional puzzle state only. Port numbers are labels, never network endpoints.
enum State { PLAYING, WON, LOST }

var state: State = State.PLAYING
var ports: Array[bool] = [] # true = open/red
var elapsed: float = 0.0
var duration: float = 15.0
var attack_wait: float = 0.0
var grace_left: float = 0.0
var settings: FirewallBreachConfig
var _rng := RandomNumberGenerator.new()


func begin(config: FirewallBreachConfig, seed_value: int = -1) -> void:
	settings = config
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	state = State.PLAYING
	elapsed = 0.0
	grace_left = 0.0
	# Even Inspector/runtime overrides cannot make the event exceed 20s including result.
	duration = clampf(settings.duration_seconds, 1.0, 19.0)
	ports.assign([false, false, false, false, false, false, false, false, false])
	var available: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
	for i: int in clampi(settings.initial_open_ports, 0, 9):
		var index: int = available.pop_at(_rng.randi_range(0, available.size() - 1))
		ports[index] = true
	_schedule_attack()


func open_count() -> int:
	return ports.count(true)


func seconds_left() -> float:
	return maxf(0.0, duration - elapsed)


func toggle_port(index: int) -> bool:
	if state != State.PLAYING or index < 0 or index >= ports.size():
		return false
	ports[index] = not ports[index]
	if open_count() == 0:
		grace_left = maxf(0.1, settings.block_grace_seconds)
		attack_wait = maxf(attack_wait, grace_left)
	return true


func block_connection() -> bool:
	if state != State.PLAYING or open_count() != 0 or seconds_left() <= 0.0:
		return false
	state = State.WON
	return true


func interval_range() -> Vector2:
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var minimum := maxf(0.15, lerpf(settings.early_interval_min, settings.late_interval_min, progress))
	var maximum := maxf(minimum, lerpf(settings.early_interval_max, settings.late_interval_max, progress))
	return Vector2(minimum, maximum)


func _schedule_attack() -> void:
	var interval := interval_range()
	attack_wait = _rng.randf_range(interval.x, interval.y)


func advance(delta: float) -> void:
	if state != State.PLAYING or delta < 0.0:
		return
	elapsed = minf(duration, elapsed + delta)
	if elapsed >= duration:
		state = State.LOST
		return
	grace_left = maxf(0.0, grace_left - delta)
	attack_wait = maxf(0.0, attack_wait - delta)
	if attack_wait > 0.0 or grace_left > 0.0:
		return
	var closed: Array[int] = []
	for i: int in ports.size():
		if not ports[i]:
			closed.append(i)
	if not closed.is_empty():
		ports[closed[_rng.randi_range(0, closed.size() - 1)]] = true
	# At most one reopening per frame: never punish a long frame with a catch-up burst.
	_schedule_attack()
