class_name RunRandom
extends RefCounted
## A fresh seed per run, independent named streams for gameplay and presentation.


static func fresh_seed() -> int:
	# Keep cross-scene state on the main loop, whose lifetime is explicit.
	# A static variable retains this GDScript resource at engine shutdown.
	var loop := Engine.get_main_loop()
	var last_seed: int = loop.get_meta(&"_last_run_seed", -1)
	var source := RandomNumberGenerator.new()
	source.randomize()
	var value := source.randi()
	while value == last_seed:
		value = source.randi()
	loop.set_meta(&"_last_run_seed", value)
	return value


static func stream_seed(run_seed: int, stream: StringName) -> int:
	return ("%d:%s" % [run_seed, stream]).hash()


static func generator(run_seed: int, stream: StringName) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = stream_seed(run_seed, stream)
	return result
