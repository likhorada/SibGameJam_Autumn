extends SceneTree
## Isolated native pixel test: independent of apartment/threat scripts.
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("CRT SMOKE requires rendered pixels; run without --headless")
		quit(1)
		return
	var scene := Node.new()
	root.add_child(scene)
	var desktop := CanvasLayer.new()
	desktop.layer = 1
	scene.add_child(desktop)
	var background := ColorRect.new()
	background.color = Color(0.24, 0.29, 0.34)
	desktop.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay := CanvasLayer.new()
	overlay.layer = 2
	scene.add_child(overlay)
	var crt := ColorRect.new()
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/terminal_crt.gdshader")
	material.set_shader_parameter("strength", 0.55)
	crt.material = material
	overlay.add_child(crt)
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		crt.hide()
		var clean := await _image()
		crt.show()
		var filtered := await _image()
		var low := 1.0
		var high := 0.0
		for y: int in range(60, size.y - 60):
			var ratio := filtered.get_pixel(100, y).r / maxf(clean.get_pixel(100, y).r, 0.001)
			low = minf(low, ratio)
			high = maxf(high, ratio)
		print("CRT ", size, " brightness: ", low, "..", high)
		_expect(high - low > 0.10, "Scanlines visibly change pixels at %s" % size)
		await create_timer(0.8).timeout
		var moved := await _image()
		var changed := 0
		for y: int in range(30, size.y - 30):
			if absf(moved.get_pixel(100, y).r - filtered.get_pixel(100, y).r) > 0.004:
				changed += 1
		_expect(changed > 10, "Rolling band moves at %s" % size)
		material.set_shader_parameter("strength", 0.0)
		var disabled := await _image()
		_expect(disabled.get_pixel(100, 100).is_equal_approx(clean.get_pixel(100, 100)), "Zero strength preserves desktop")
		material.set_shader_parameter("strength", 0.55)
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-dir="):
				filtered.save_png(argument.trim_prefix("--capture-dir=").path_join("crt_%dx%d.png" % [size.x, size.y]))
	scene.queue_free()
	await process_frame
	print("CRT SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _image() -> Image:
	for index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CRT: " + message)
