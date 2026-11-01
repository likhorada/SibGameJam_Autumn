extends ObservationLocation

var elapsed: float = 0.0


func _ready() -> void:
	super._ready()
	for exit: Node in $Exits.get_children():
		var sign: Label3D = get_node("%sSign" % exit.name)
		sign.text = tr(sign.text)


func _process(delta: float) -> void:
	elapsed += delta
	for i: int in $Pedestrians.get_child_count():
		var actor: Node3D = $Pedestrians.get_child(i)
		actor.position = exit_point(i / 2) + Vector3(sin(elapsed * 0.25 + i) * 2, 0, cos(elapsed * 0.2 + i) * 2)
