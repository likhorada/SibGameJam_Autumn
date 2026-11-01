class_name CorridorEntityConfig
extends Resource

@export var enabled: bool = true
@export_range(0.1, 10.0) var warning_seconds: float = 2.0
@export_range(0.5, 15.0) var min_encounter_seconds: float = 3.0
@export_range(0.5, 15.0) var max_encounter_seconds: float = 5.0
@export_range(0.1, 5.0) var error_budget_seconds: float = 1.0
@export_range(0.1, 8.0) var error_recovery_seconds: float = 2.0
@export_range(1.0, 20.0) var chase_seconds: float = 6.0
@export_range(0.0, 5.0) var forced_exit_warning_bonus: float = 2.0
@export_range(0.2, 4.0) var retreat_seconds: float = 1.5
## Optional designer-provided WAV, intentionally empty until assigned.
@export var chase_sound: AudioStream
@export_range(1.0, 60.0) var min_repeat_seconds: float = 15.0
@export_range(1.0, 60.0) var max_repeat_seconds: float = 25.0
@export_range(0.5, 8.0) var near_radius: float = 3.5
@export_range(0.5, 8.0) var pursuit_speed: float = 3.2
@export_range(1.0, 6.0) var min_spawn_distance: float = 2.0
@export_range(1.0, 15.0) var max_spawn_distance: float = 13.0
@export_range(0.01, 0.5) var movement_threshold: float = 0.08
@export var warning_sound: AudioStream = preload("res://assets/audio/creep_coming_pitched.wav")
@export var departure_sound: AudioStream = preload("res://assets/audio/creep_goaway_pitched.wav")
@export var footsteps: AudioStream = preload("res://assets/audio/steps.wav")
@export_range(0.5, 2.0) var warning_pitch: float = 1.35
@export_range(-30.0, 6.0) var volume_db: float = -3.0
