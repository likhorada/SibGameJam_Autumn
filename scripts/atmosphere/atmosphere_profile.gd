class_name AtmosphereProfile
extends Resource
## Selection data only. Behaviour belongs to an AtmosphereEvent scene.

@export var id: StringName
@export var enabled: bool = true
@export_range(0.01, 100.0) var weight: float = 1.0
@export var random_trigger: bool = true
@export var transition_trigger: bool = true
@export var at_computer: bool = true
@export var walking: bool = true
@export var repeatable: bool = false
@export_range(0.1, 300.0) var timeout_seconds: float = 20.0
@export var scene: PackedScene
