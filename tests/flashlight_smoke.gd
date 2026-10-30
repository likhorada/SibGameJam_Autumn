extends SceneTree
## Needs a real renderer: checks that spill brightens nearby off-axis surfaces only.
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.power.random_outages_enabled = false
	game.power.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process(false)
	game.player.position = Vector3(100, 0, 100)
	game.power.trigger_outage()
	game.power._process(0.0)
	var camera: Camera3D = game.player.camera
	var points: Array[Vector2] = []
	for offset: Vector3 in [Vector3(-0.9, -0.3, -1.25), Vector3(0.9, -0.3, -1.25), Vector3(1.9, 0.4, -4.0)]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.5, 0.1)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.7, 0.7, 0.7)
		box.material = material
		mesh.mesh = box
		game.add_child(mesh)
		mesh.global_position = camera.global_position + offset
		points.append(camera.unproject_position(mesh.global_position))
	game.power.flashlight_spill.hide()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var narrow := root.get_texture().get_image()
	game.power.flashlight_spill.show()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var broad := root.get_texture().get_image()
	for index: int in points.size():
		var point := Vector2i(points[index])
		var before := narrow.get_pixelv(point)
		var after := broad.get_pixelv(point)
		var difference := after.r + after.g + after.b - before.r - before.g - before.b
		print("FLASHLIGHT surface %d: brightness change %.4f" % [index, difference])
		expect(difference > 0.03 if index < 2 else absf(difference) < 0.01, "Near spill illuminates sides but not distant surface")
	game.player.position = Vector3(0, 0.02, 0.7)
	game.power._process(0.0)
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/flashlight_spill.png")
	game.power.restore_power()
	expect(not game.power.flashlight.visible and not game.power.flashlight_spill.visible, "Both cones shut down on restoration")
	game.queue_free()
	await process_frame
	print("FLASHLIGHT SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
