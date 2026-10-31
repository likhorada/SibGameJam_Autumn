class_name ThreatConfig
extends Resource
## Shared pacing. Each run keeps its mutable state in ThreatManager, not here.

@export_range(0.0, 600.0) var opening_safe_seconds: float = 45.0
@export_range(0.0, 120.0) var safe_seconds: float = 20.0
@export_range(0.1, 300.0) var min_interval: float = 25.0
@export_range(0.1, 300.0) var max_interval: float = 45.0
## One roll per eligible interval, never one roll per rendered frame.
@export_range(0.0, 1.0) var event_chance: float = 1.0
@export_range(1.0, 1200.0) var ramp_seconds: float = 180.0
@export_range(0.1, 1.0) var final_interval_scale: float = 0.65
@export var profiles: Array[ThreatProfile] = []


func profile_for(id: StringName) -> ThreatProfile:
	for profile: ThreatProfile in profiles:
		if profile != null and profile.id == id:
			return profile
	return null
