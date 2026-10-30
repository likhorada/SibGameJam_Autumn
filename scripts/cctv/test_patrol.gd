extends Node3D
## Deliberately simple independent test action, not a clue/day timeline.

@export var travel := Vector3(4, 0, 0)
@export var period: float = 12.0
var elapsed: float = 0.0
var _origin := Vector3.ZERO


func _ready() -> void:
	_origin = position


func _process(delta: float) -> void:
	elapsed += delta
	position = _origin + travel * (0.5 - 0.5 * cos(elapsed * TAU / period))
