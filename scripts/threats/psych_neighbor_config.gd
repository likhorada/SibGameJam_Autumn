class_name PsychNeighborConfig
extends Resource

@export_range(0.2, 15.0) var attack_delay: float = 3.0
@export_range(0.5, 20.0) var rattle_seconds: float = 4.0
@export_range(0.5, 15.0) var departure_seconds: float = 3.0
@export var footsteps: AudioStream = preload("res://assets/audio/steps.wav")
@export var handle_sound: AudioStream
@export_range(-30.0, 6.0) var footsteps_volume_db: float = -4.0
@export_range(-30.0, 6.0) var handle_volume_db: float = -2.0
