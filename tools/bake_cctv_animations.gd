extends SceneTree
## Run after the Blender bake. No Blender or external file access is needed by the game.

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/animations"))
	var library := AnimationLibrary.new()
	var directory := OS.get_environment("LOCALAPPDATA").path_join("Temp/opencode/cctv-animation-bake")
	for clip: String in ["idle", "walk", "work", "stand", "carry_idle", "carry_walk", "reach"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(directory.path_join(clip + ".glb"), state) == OK)
		var model := document.generate_scene(state)
		var players := model.find_children("*", "AnimationPlayer")
		assert(players.size() == 1)
		var player: AnimationPlayer = players[0]
		var animation: Animation = player.get_animation(player.get_animation_list()[0]).duplicate()
		# Blender frame 1 is timestamp 1/30; remove that dead frame from loops/transitions.
		for track: int in animation.get_track_count():
			var keys: Array = []
			for key: int in animation.track_get_key_count(track):
				keys.append([maxf(0.0, animation.track_get_key_time(track, key) - 1.0 / 30.0), animation.track_get_key_value(track, key)])
			for key: int in range(animation.track_get_key_count(track) - 1, -1, -1):
				animation.track_remove_key(track, key)
			for key: Array in keys:
				animation.track_insert_key(track, key[0], key[1])
		animation.length -= 1.0 / 30.0
		var skeleton: Skeleton3D = model.get_node("rig/Skeleton3D")
		var required: Dictionary = {}
		for bone: int in skeleton.get_bone_count():
			if not skeleton.get_bone_name(bone).begins_with("DEF-"):
				continue
			var ancestor := bone
			while ancestor >= 0:
				required[skeleton.get_bone_name(ancestor)] = true
				ancestor = skeleton.get_bone_parent(ancestor)
		for index: int in range(animation.get_track_count() - 1, -1, -1):
			var path := String(animation.track_get_path(index))
			# Rigify deform chains inherit ORG/control ancestors. Keep their baked motion too;
			# stripping them disconnects shoulders and hips even though no IK runs in Godot.
			if not path.contains("Skeleton3D:") or not required.has(path.get_slice(":", 1)):
				animation.remove_track(index)
		for bone: int in skeleton.get_bone_count():
			if not required.has(skeleton.get_bone_name(bone)):
				continue
			var path := NodePath("rig/Skeleton3D:" + skeleton.get_bone_name(bone))
			for type: int in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				if animation.find_track(path, type) >= 0:
					continue
				var track := animation.add_track(type)
				animation.track_set_path(track, path)
				match type:
					Animation.TYPE_POSITION_3D: animation.position_track_insert_key(track, 0.0, skeleton.get_bone_rest(bone).origin)
					Animation.TYPE_ROTATION_3D: animation.rotation_track_insert_key(track, 0.0, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
					Animation.TYPE_SCALE_3D: animation.scale_track_insert_key(track, 0.0, skeleton.get_bone_rest(bone).basis.get_scale())
		animation.loop_mode = Animation.LOOP_NONE if clip in ["stand", "reach"] else Animation.LOOP_LINEAR
		assert(library.add_animation(clip, animation) == OK)
		print("CCTV CLIP ", clip, " tracks=", animation.get_track_count(), " length=", animation.length)
		model.free()
	assert(ResourceSaver.save(library, "res://assets/animations/cctv_humanoid.res") == OK)
	quit()
