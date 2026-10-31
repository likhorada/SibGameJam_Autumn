class_name ThreatProfile
extends Resource
## Timing and selection data only. Enemy-specific behaviour belongs in its event.

@export var id: StringName
@export var enabled: bool = true
@export_range(0.0, 100.0) var weight: float = 1.0
@export_range(0.0, 120.0) var warning_seconds: float = 5.0
## Zero disables the watchdog (a blackout must wait for a real repair).
@export_range(0.0, 600.0) var max_active_seconds: float = 30.0
@export_range(0.0, 30.0) var resolved_seconds: float = 1.0
