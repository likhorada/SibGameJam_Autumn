class_name AtmosphereConfig
extends Resource

@export var events: Array[AtmosphereProfile] = []
@export_range(1.0, 300.0) var min_interval: float = 40.0
@export_range(1.0, 300.0) var max_interval: float = 70.0
@export_range(0, 20) var min_random_events: int = 1
@export_range(0, 20) var max_random_events: int = 2
