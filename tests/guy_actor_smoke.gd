extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for scene: String in ["office", "observation_shop", "street", "shop", "yard"]:
		var location: Node3D = load("res://scenes/cctv/locations/%s.tscn" % scene).instantiate()
		root.add_child(location)
		var actors := location.find_children("Guy", "Node3D")
		_expect(actors.size() == (7 if scene == "street" else 1), scene + " uses GuyRig for every actor")
		for actor: Node3D in actors:
			var player: AnimationPlayer = actor.get_node("Model/AnimationPlayer")
			_expect(player.has_animation(&"Action") and not player.is_playing(), "Imported pose is applied once and paused")
			var skeleton: Skeleton3D = actor.get_node("Model/rig/Skeleton3D")
			var bone := skeleton.find_bone("DEF-upper_arm.L")
			_expect(bone >= 0 and not skeleton.get_bone_pose_rotation(bone).is_equal_approx(Quaternion.IDENTITY), "Authored pose replaces rest pose")
			var torso: MeshInstance3D = skeleton.get_node("Torso")
			_expect(torso.get_surface_override_material(0).albedo_color == actor.shirt_color, "Shirt color preserves target/decoy distinction")
		location.queue_free()
		await process_frame
	print("GUY ACTOR SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
