class_name RunRandom
extends RefCounted
## A fresh seed per run, independent named streams for gameplay and presentation.
static var _last_seed: int = -1


static func fresh_seed() -> int:
	var source := RandomNumberGenerator.new()
	source.randomize()
	var value := source.randi()
	while value == _last_seed:
		value = source.randi()
	_last_seed = value
	return value


static func stream_seed(run_seed: int, stream: StringName) -> int:
	return ("%d:%s" % [run_seed, stream]).hash()


static func generator(run_seed: int, stream: StringName) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = stream_seed(run_seed, stream)
	return result
