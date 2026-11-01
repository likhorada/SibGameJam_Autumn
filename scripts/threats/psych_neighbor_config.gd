class_name PsychNeighborConfig
extends Resource

@export_range(0.2, 15.0) var attack_delay: float = 3.0
@export_range(0.5, 20.0) var rattle_seconds: float = 4.0
@export_range(0.5, 15.0) var departure_seconds: float = 3.0
@export_range(1.0, 30.0) var search_seconds: float = 8.0
@export_range(0.0, 8.0) var pressure_seconds: float = 4.0
@export_range(0.1, 5.0) var detection_seconds: float = 1.0
@export_range(0.1, 8.0) var suspicion_recovery_seconds: float = 2.0
@export_range(1.0, 20.0) var sight_range: float = 9.0
@export_range(15.0, 90.0) var sight_half_angle: float = 65.0
@export_range(0.2, 2.0) var close_distance: float = 1.0
@export_range(0.05, 1.0) var close_capture_seconds: float = 0.25
@export var footsteps: AudioStream = preload("res://assets/audio/steps.wav")
@export var handle_sounds: Array[AudioStream] = [
	preload("res://assets/audio/scratchin1.wav"),
	preload("res://assets/audio/scratchin2.wav"),
]
@export_range(-30.0, 6.0) var footsteps_volume_db: float = -4.0
@export_range(-30.0, 6.0) var handle_volume_db: float = -2.0
