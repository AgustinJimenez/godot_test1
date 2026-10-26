extends RefCounted
## Bakes a ledge BVH clip into an Animation on the player's skeleton (rotation track per bone, hips position), so the
## climb system can play it like any other clip. The clip is turned to face where the skeleton faces and moved so the
## chosen frame has the wrists `wrist_height` above the skeleton's origin (the capsule's feet), the pelvis over it.

const BvhClip := preload("res://tests/manual/ledge_anim/bvh_clip.gd")
const BvhRetarget := preload("res://tests/manual/ledge_anim/bvh_retarget.gd")
const DIR := "D:/RE/game_locomotion/anims/bvh_trav_ledge/"


static func available() -> bool:
	return DirAccess.dir_exists_absolute(DIR)


## `anchor`: the frame (0 = first, 1 = last) that is lined up with the wrists at `wrist_height`.
## `track_prefix` is the animation-player-relative skeleton path ("Skeleton3D" in "Skeleton3D:Hips").
## `tilt_from` / `tilt_to` (radians): the swing of the body away from the wall, at the clip's start and after
## `tilt_span` (fraction of the clip).
static func bake(file: String, retarget: BvhRetarget, track_prefix: String, wrist_height: float,
		anchor: int, looping: bool, hands_in: float, tilt_from := 0.0, tilt_to := 0.0, tilt_span := 1.0) -> Animation:
	var clip: BvhClip = BvhClip.load_file(DIR + file + ".bvh")
	if clip == null:
		return null
	var skeleton := retarget.skeleton
	var anchor_time := 0.0 if anchor == 0 else float(clip.frames.size() - 1) * clip.frame_time
	retarget.scale = retarget.fit_scale(clip)
	retarget.yaw = retarget.facing_yaw(clip, anchor_time)
	var source: Array[Transform3D] = clip.pose(anchor_time, false)
	var wrists := (source[clip.names.find("l_wrist")].origin + source[clip.names.find("r_wrist")].origin) * 0.5
	# the wrists `hands_in` past the capsule toward the wall (PlayerClimb.HAND_BACK plus how far the capsule hangs out)
	var forward: Vector3 = retarget.yaw.inverse() * retarget.target_forward()
	var hands_at := wrists - forward * hands_in / retarget.scale
	retarget.origin = Vector3(hands_at.x, wrists.y - wrist_height / retarget.scale, hands_at.z)
	retarget.tilt = 0.0
	retarget.pivot = retarget.yaw * (wrists - retarget.origin)
	var anim := Animation.new()
	anim.length = float(clip.frames.size() - 1) * clip.frame_time
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var tracks := {}
	for bone in skeleton.get_bone_count():
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("%s:%s" % [track_prefix, skeleton.get_bone_name(bone)]))
		tracks[bone] = track
	var hips := skeleton.find_bone(String(retarget.role_map["Hips"]))
	var hips_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_track, NodePath("%s:%s" % [track_prefix, skeleton.get_bone_name(hips)]))
	for frame in clip.frames.size():
		var time := float(frame) * clip.frame_time
		retarget.tilt = lerpf(tilt_from, tilt_to, smoothstep(0.0, tilt_span, float(frame) / float(maxi(clip.frames.size() - 1, 1))))
		retarget.apply(clip, time, false)
		for bone in tracks:
			anim.rotation_track_insert_key(tracks[bone], time, skeleton.get_bone_pose_rotation(bone))
		anim.position_track_insert_key(hips_track, time, skeleton.get_bone_pose_position(hips))
	retarget.tilt = 0.0
	skeleton.reset_bone_poses()
	return anim
