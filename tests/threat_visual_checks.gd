extends Node3D
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("THREAT VISUAL: " + message)


func _run() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1.25, -4.0)
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.07, 0.055)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.7, 0.62)
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	add_child(light)
	var visuals: Array[ThreatVisual] = []
	for file: String in ["police_officer", "psych_neighbor", "corridor_entity"]:
		var visual: ThreatVisual = load("res://scenes/threats/" + file + ".tscn").instantiate()
		add_child(visual)
		visual.set_process(false)
		visual.position.x = (visuals.size() - 1) * 1.25
		visuals.append(visual)
		expect(not visual.visible, "Starts hidden: " + file)
		expect(visual.model.scene_file_path == "res://assets/models/GuyRig.glb", "Actual replaceable GuyRig: " + file)
		expect(visual.skeleton != null and visual.skeleton.find_bone("DEF-foot.L") >= 0, "Leg rig bound")
		expect(visual.model.basis.z.dot(Vector3.FORWARD) > 0.99, "Textured face matches route -Z")
		visual.show()
		visual._process(0.1)
		var rest: Transform3D = visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("DEF-foot.L"))
		for index: int in 3:
			visual.position.z -= 0.1
			visual._process(0.1)
		expect(visual.gait_weight > 0.9, "Actual movement enables walking")
		var walking: Transform3D = visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("DEF-foot.L"))
		expect(not rest.is_equal_approx(walking), "Feet really animate, not just the root")
		var stopped_at := visual.global_transform
		for index: int in 10:
			visual._process(0.1)
		expect(is_zero_approx(visual.gait_weight) and stopped_at.is_equal_approx(visual.global_transform), "Idle stops gait without moving gameplay root")
		var head_index := visual.skeleton.find_bone("DEF-spine.006")
		var old_head := visual.skeleton.get_bone_global_pose(head_index)
		var head_rest := visual.head.rotation
		visual.head.rotation.y += 0.4
		visual._process(0.1)
		expect(not old_head.is_equal_approx(visual.skeleton.get_bone_global_pose(head_index)), "Pressure marker turns actual head bones")
		visual.head.rotation = head_rest
		visual.position.z += 15.0
		visual._process(0.1)
		expect(is_zero_approx(visual.gait_weight), "Spawn teleport does not trigger sprint animation")
		visual.hide()
		visual._process(0.1)
		visual.position.z = 0.0
		visual.show()
		visual._process(0.1)
		expect(is_zero_approx(visual.gait_weight) and is_zero_approx(visual.gait_phase), "A new visit resets presentation")
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/threat_visuals.png")
	for visual: ThreatVisual in visuals:
		for index: int in 3:
			visual.position.z -= 0.1
			visual._process(0.1)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("LOCALAPPDATA") + "/Temp/opencode/threat_visuals_walking.png")
	for visual: ThreatVisual in visuals:
		visual.queue_free()
	await get_tree().process_frame
	print("THREAT VISUALS: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.threatTestResult = " + JSON.stringify({"failures": failures}))
	else:
		get_tree().quit(0 if failures == 0 else 1)
