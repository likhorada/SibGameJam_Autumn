class_name BathroomApparitionConfig
extends Resource

@export var visual_scene: PackedScene = preload("res://scenes/threats/corridor_entity.tscn")
## Intentionally empty until the artist supplies the sound. Never synthesize a fallback.
@export var loop_sound: AudioStream
@export_range(-40.0, 0.0) var volume_db: float = -14.0
