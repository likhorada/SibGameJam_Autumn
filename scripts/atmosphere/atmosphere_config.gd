class_name AtmosphereConfig
extends Resource

@export var events: Array[AtmosphereProfile] = []
@export_range(1.0, 300.0) var min_interval: float = 40.0
@export_range(1.0, 300.0) var max_interval: float = 70.0
