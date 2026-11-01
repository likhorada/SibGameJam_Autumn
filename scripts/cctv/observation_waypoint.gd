@tool
class_name ObservationWaypoint
extends Marker3D
## Place under a location's Route node in chronological order.

@export_range(0.01, 300.0, 0.01) var seconds: float = 5.0
@export var event_id: String = ""
