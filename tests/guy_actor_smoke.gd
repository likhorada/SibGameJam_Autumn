extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for scene: String in ["office", "street", "shop", "yard"]:
		var location: Node3D = load("res://scenes/cctv/locations/%s.tscn" % scene).instantiate()
		root.add_child(location)
		location.set_process(false)
		var actors := location.find_children("Guy", "Node3D")
		_expect(actors.size() == (7 if scene == "street" else 1), scene + " supplies every actor")
		var variants: Dictionary = {}
		for actor: Node3D in actors:
			actor.set_process(false)
			actor.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			variants[actor.appearance] = true
			var expected: String = ["GuyRig", "DecoyGreen", "DecoyRed", "DecoyYellow"][actor.appearance]
			_expect(actor.model.scene_file_path.ends_with(expected + ".glb"), "Actor uses its actual model, not a tinted substitute")
			for clip: String in ["idle", "walk", "work", "stand", "reach", "carry_walk"]:
				_expect(actor.player.has_animation("cctv/" + clip), "Shared clip available: " + clip)
			actor._play("idle", 0.0)
			actor.player.advance(0.1)
			var head_standing := _bone(actor, "DEF-spine.006")
			actor._play("work", 0.0)
			actor.player.advance(0.1)
			var head_seated := _bone(actor, "DEF-spine.006")
			_expect(head_standing.y - head_seated.y > 0.35, "Work pose actually lowers the seated body")
			_expect(_bone(actor, "DEF-hand.R").y < head_seated.y, "Hands stay below the head, not in T-pose")
			actor.start_departure()
			actor.advance_motion(0.7, Vector3.ZERO)
			actor.player.advance(0.7)
			_expect(actor.activity == "stand", "Departure starts with a non-looping stand transition")
			actor.advance_motion(0.8, Vector3.ZERO)
			actor.player.advance(0.8)
			actor.advance_motion(0.1, Vector3(0.1, 0, 0))
			actor.player.advance(0.2)
			_expect(actor.activity == "walk", "Standing transitions into locomotion")
			var foot := _bone(actor, "DEF-foot.L")
			var travel := 0.0
			for sample: int in 4:
				actor.player.advance(0.2)
				travel = maxf(travel, foot.distance_to(_bone(actor, "DEF-foot.L")))
			_expect(travel > 0.15, "Walk actually moves the feet across a full cycle")
			actor.advance_motion(0.2, Vector3.ZERO)
			_expect(actor.activity == "idle", "Stopping returns to idle")
		if scene == "street":
			_expect(variants.size() == 4, "Street contains target plus all three decoy models")
		if scene == "office":
			location.start_route()
			_expect(not location.working and location.get_node("Target/Guy").activity == "stand", "Alarm route triggers getting up")
			_expect(location.route()[0].point.is_equal_approx(location.target.position), "First office segment keeps the actor at the chair")
		if scene == "shop":
			var actor: Node3D = location.get_node("Target/Guy")
			location.event("take")
			actor.advance_motion(0.5, Vector3.ZERO)
			actor.player.advance(0.5)
			_expect(location.bottle.get_parent() == actor.grip, "Purchase attaches to the real hand bone")
			actor.advance_motion(0.6, Vector3.ZERO)
			actor.advance_motion(0.1, Vector3(0, 0, 0.1))
			_expect(actor.activity == "carry_walk", "Carrying uses a separate walk cycle")
			location.event("checkout")
			actor.advance_motion(0.5, Vector3.ZERO)
			_expect(location.bottle.get_parent() == location and actor.carrying == null, "Checkout releases the drink onto the counter")
		location.queue_free()
		await process_frame
	print("GUY ACTOR SMOKE: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _bone(actor: Node3D, name: String) -> Vector3:
	return actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone(name)).origin


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
