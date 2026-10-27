extends RefCounted
## Prints the chest bones' facing (global up and forward axes) every twelfth of each baked GALS climb clip.

const ROLES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]
const STEPS := 12


static func dump(player: Player) -> void:
	var library := player.body.anim_player.get_animation_library(&"moves")
	var skeleton: Skeleton3D = player.skeleton
	var map: Dictionary = player.body._target_humanoid_map
	for name in library.get_animation_list():
		if not String(name).contains("climb"):
			continue
		var anim := library.get_animation(name)
		print("CHEST clip ", name, " length ", anim.length)
		for i in STEPS + 1:
			var t := anim.length * float(i) / float(STEPS)
			skeleton.reset_bone_poses()
			for track in anim.get_track_count():
				var bone := skeleton.find_bone(String(anim.track_get_path(track)).get_slice(":", 1))
				if bone < 0:
					continue
				if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(track, t))
				elif anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
					skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(track, t))
			var line := "CHEST t=%.2f" % t
			for role: String in ROLES:
				var basis := skeleton.get_bone_global_pose(skeleton.find_bone(String(map[role]))).basis
				line += " | %s y(%.2f %.2f %.2f) z(%.2f %.2f %.2f)" % [role, basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z]
			print(line)
	skeleton.reset_bone_poses()
