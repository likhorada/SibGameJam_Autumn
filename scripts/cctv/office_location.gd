extends ObservationLocation

var elapsed: float = 0.0


func set_code(value: String) -> void:
	$Screen/Code.text = value


func _process(delta: float) -> void:
	elapsed += delta
	if working:
		$Target/LeftArm.position.y = 0.9 + sin(elapsed * 5) * 0.025
		$Target/RightArm.position.y = 0.9 + sin(elapsed * 5 + 1) * 0.025
