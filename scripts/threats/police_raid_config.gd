class_name PoliceRaidConfig
extends Resource

@export_range(0.5, 30.0) var search_seconds: float = 6.0
@export_range(0.5, 15.0) var departure_seconds: float = 3.0
@export_range(1.0, 12.0) var knock_interval: float = 4.0
@export_range(0.0, 3.0) var voice_delay: float = 0.9
@export var knock_sound: AudioStream = preload("res://assets/audio/heavy_knock.wav")
@export var warning_voice: AudioStream
@export var departure_sound: AudioStream
@export var footsteps: AudioStream = preload("res://assets/audio/steps.wav")
@export_range(-30.0, 6.0) var warning_volume_db: float = -1.0
@export_range(-30.0, 6.0) var footsteps_volume_db: float = -4.0
