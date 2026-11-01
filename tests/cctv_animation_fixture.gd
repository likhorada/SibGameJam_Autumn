extends "res://scripts/main.gd"
## Isolated browser acceptance fixture; excluded from production exports.

var command_id: int = 0


func _ready() -> void:
	atmosphere_config = AtmosphereConfig.new()
	super._ready()
	shift.set_process(false)
	threats.set_process(false)
	power.set_process(false)
	transition_seconds = 0.02
	enter_computer.call_deferred()
	await get_tree().create_timer(0.3).timeout
	terminal_ui.launch_app(&"cctv")
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_publish)


func _publish() -> void:
	if not OS.has_feature("web"):
		return
	var command = JavaScriptBridge.eval("JSON.stringify(window.animationCommand || {})")
	var request: Dictionary = JSON.parse_string(str(command))
	if int(request.get("id", 0)) > command_id:
		command_id = int(request.id)
		match str(request.get("name", "")):
			"alarm":
				shift.state = ShiftDirector.State.DEADLINE
				shift.start_alarm()
			"advance": shift.advance(float(request.get("seconds", 0)))
			"camera":
				terminal_ui.cctv.directory.select(int(request.get("index", 0)))
				terminal_ui.cctv._select(int(request.get("index", 0)))
			"live": shift.set_process(bool(request.get("enabled", false)))
			"pickup": shift.location.event("take")
			"checkout": shift.location.event("checkout")
	var actor: Node3D = shift.location.get_node("Target/Guy")
	var skeleton: Skeleton3D = actor.skeleton
	var foot := skeleton.get_bone_global_pose(skeleton.find_bone("DEF-foot.L")).origin
	var head := skeleton.get_bone_global_pose(skeleton.find_bone("DEF-spine.006")).origin
	var variants: Array = []
	var pedestrians := shift.location.get_node_or_null("Pedestrians")
	if pedestrians:
		for pedestrian: Node in pedestrians.get_children():
			variants.append(pedestrian.get_node("Guy").model.scene_file_path)
	var data := {"command": command_id, "stage": shift.stage, "activity": actor.activity,
		"foot": [foot.x, foot.y, foot.z], "head_y": head.y, "holding": is_instance_valid(actor.carrying),
		"variants": variants, "position": [actor.global_position.x, actor.global_position.y, actor.global_position.z]}
	JavaScriptBridge.eval("window.animationTelemetry = " + JSON.stringify(data))
