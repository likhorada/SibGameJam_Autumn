extends ObservationLocation


func set_code(value: String) -> void:
	$Screen/Code.text = value


func start_route() -> void:
	super.start_route()
	$Target/Guy.start_departure()
	# Roll the chair back before the hips straighten, instead of standing through its seat.
	var chair: Node3D = $Cubicle.get_node("Office-Chair")
	create_tween().tween_property(chair, "global_position", chair.global_position + Vector3(0, 0, 0.45), 0.45)
