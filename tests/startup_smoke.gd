extends SceneTree
## Exercise the configured main scene, then drain audio before engine shutdown.
## --quit-after tears down AudioServer too soon for an autoplaying WAV loop.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("STARTUP: " + message)


func _run() -> void:
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("STARTUP: Cannot load the configured main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame: int in 10:
		await process_frame
	var music := scene.get_node_or_null("MenuMusic") as AudioStreamPlayer
	expect(music != null, "Configured main scene has menu music")
	if music != null:
		expect(music.playing, "Menu music autoplays at startup")
		expect(music.stream.resource_path == "res://assets/audio/main_menu.wav", "Menu uses the authored music")
		music.stop()
	# Keep the stopped player and stream alive until the mixing thread releases
	# its playback, then release the scene before shutting down the server.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	await create_timer(0.2).timeout
	var scene_ref: WeakRef = weakref(scene)
	scene.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	expect(scene_ref.get_ref() == null, "Startup scene is freed before shutdown")
	print("STARTUP SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
