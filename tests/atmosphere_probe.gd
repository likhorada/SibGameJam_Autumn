extends AtmosphereEvent
## Test-only handler. No production profiles reference this script.
@export var fail_start: bool = false
@export var immediate: bool = false
var elapsed: float = 0.0
var cleanup_count: int = 0
var last_outcome: StringName


func start(_game: Node3D) -> bool:
	if immediate:
		finished.emit(&"completed")
	return not fail_start


func advance(delta: float) -> void:
	elapsed += delta
	if elapsed >= 2.0:
		finished.emit(&"completed")


func ended(outcome: StringName) -> void:
	cleanup_count += 1
	last_outcome = outcome
