class_name PlayerStamina
extends Node
## Normalized gameplay state. Presentation must never change this value.

@export_range(0.2, 15.0) var sprint_seconds: float = 3.0
@export_range(0.0, 5.0) var recovery_delay: float = 0.5
@export_range(0.2, 30.0) var rest_recovery_seconds: float = 4.0
@export_range(0.2, 30.0) var walking_recovery_seconds: float = 6.0
@export_range(0.05, 1.0) var restart_ratio: float = 0.35
@export_range(0.01, 0.9) var warning_ratio: float = 0.2
@export_range(0.01, 1.0) var clear_fatigue_ratio: float = 0.45
@export_range(0.0, 0.5) var warning_strength: float = 0.22

var value: float = 1.0
var exhausted: bool = false
var fatigue_latched: bool = false
var delay_left: float = 0.0
var unlimited: bool = false


func can_sprint() -> bool:
	return not exhausted and value > 0.0


func advance(delta: float, sprinting: bool, moving: bool) -> void:
	if unlimited:
		reset()
		return
	if sprinting and can_sprint():
		value = maxf(0.0, value - delta / sprint_seconds)
		delay_left = recovery_delay
		if value <= 0.000001:
			value = 0.0
			exhausted = true
			fatigue_latched = true
	else:
		# Only the part of this tick AFTER the delay regenerates stamina.
		var recovery_delta := maxf(0.0, delta - delay_left)
		delay_left = maxf(0.0, delay_left - delta)
		var duration := walking_recovery_seconds if moving else rest_recovery_seconds
		value = minf(1.0, value + recovery_delta / duration)
		if value >= restart_ratio:
			exhausted = false
		if value >= clear_fatigue_ratio:
			fatigue_latched = false


func fatigue_amount() -> float:
	var warning := clampf(1.0 - value / warning_ratio, 0.0, 1.0) * warning_strength
	if fatigue_latched:
		return maxf(warning, clampf(1.0 - value / clear_fatigue_ratio, 0.0, 1.0))
	return warning


func reset() -> void:
	value = 1.0
	exhausted = false
	fatigue_latched = false
	delay_left = 0.0


func set_unlimited(enabled: bool) -> void:
	unlimited = enabled
	reset()
