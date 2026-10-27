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


## The way each clip faces, read three ways (legs, shoulders, wrists): angle (deg) from the skeleton's own forward.
static func facing(player: Player) -> void:
	const BvhClip := preload("res://tests/manual/ledge_anim/bvh_clip.gd")
	const BvhRetarget := preload("res://tests/manual/ledge_anim/bvh_retarget.gd")
	var retarget := BvhRetarget.new(player.skeleton, player.body._target_humanoid_map)
	var target := retarget.target_forward()
	for file in ["ledge-facing-idle", "ledge-hang-idle-base", "ledge-land-waist-contact_to_ledge-grab-idle", "ledge-grab-idle_to_ledge-facing-idle-full"]:
		var clip: BvhClip = BvhClip.load_file("D:/RE/game_locomotion/anims/bvh_trav_ledge/" + file + ".bvh")
		for time in [0.0, float(clip.frames.size() - 1) * clip.frame_time]:
			var source: Array[Transform3D] = clip.pose(time, false)
			var line := "FACING %s t=%.2f" % [file, time]
			for pair in [["legs", "l_upper_leg", "r_upper_leg"], ["shoulders", "l_shoulder", "r_shoulder"], ["wrists", "l_wrist", "r_wrist"], ["feet", "l_ankle", "r_ankle"]]:
				var side: Vector3 = source[clip.names.find(pair[2])].origin - source[clip.names.find(pair[1])].origin
				var forward := Vector3.UP.cross(side)
				forward.y = 0.0
				line += " %s %.0f" % [pair[0], rad_to_deg(forward.signed_angle_to(target, Vector3.UP))]
			print(line)


## The skeleton's rest pose, same columns as `dump`, to read the clips' axes against.
static func rest(player: Player) -> void:
	var skeleton: Skeleton3D = player.skeleton
	skeleton.reset_bone_poses()
	var map: Dictionary = player.body._target_humanoid_map
	var line := "REST"
	for role: String in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "RightUpLeg", "LeftArm", "RightArm", "LeftHand", "RightHand"]:
		var bone := skeleton.find_bone(String(map[role]))
		var global := skeleton.get_bone_global_pose(bone)
		line += " | %s p(%+.2f %.2f %+.2f) y(%.2f %.2f %.2f) z(%.2f %.2f %.2f)" % [role, global.origin.x, global.origin.y, global.origin.z,
				global.basis.y.x, global.basis.y.y, global.basis.y.z, global.basis.z.x, global.basis.z.y, global.basis.z.z]
	print(line)


## Is the clip's left on the left? The sign of (right leg - left leg) x (toe direction) on Y: the skeleton's rest gives +1.
static func handedness(player: Player) -> void:
	const BvhClip := preload("res://tests/manual/ledge_anim/bvh_clip.gd")
	var skeleton: Skeleton3D = player.skeleton
	var map: Dictionary = player.body._target_humanoid_map
	skeleton.reset_bone_poses()
	var at := func(role: String) -> Vector3: return skeleton.get_bone_global_pose(skeleton.find_bone(String(map[role]))).origin
	var side: Vector3 = at.call("RightUpLeg") - at.call("LeftUpLeg")
	var toes: Vector3 = at.call("LeftToeBase") - at.call("LeftFoot"); toes.y = 0.0
	print("HAND skeleton rest side x toes y = %+.2f (side %s toes %s)" % [side.cross(toes).y, side, toes])
	for file in ["ledge-facing-idle", "ledge-hang-idle-base"]:
		var clip: BvhClip = BvhClip.load_file("D:/RE/game_locomotion/anims/bvh_trav_ledge/" + file + ".bvh")
		var source: Array[Transform3D] = clip.pose(0.0, false)
		var s: Vector3 = source[clip.names.find("r_upper_leg")].origin - source[clip.names.find("l_upper_leg")].origin
		var t: Vector3 = source[clip.names.find("l_toe")].origin - source[clip.names.find("l_ankle")].origin
		t.y = 0.0; print("HAND %s side x toes y = %+.2f (side %s toes %s)" % [file, s.cross(t).y, s, t])
