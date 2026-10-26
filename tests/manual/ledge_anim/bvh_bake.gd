extends RefCounted
## Bakes a ledge BVH clip into an Animation on the player's skeleton (rotation track per bone, hips position), so the
## climb system can play it like any other clip. The clip is turned to face where the skeleton faces and moved so the
## chosen frame has the wrists `wrist_height` above the skeleton's origin (the capsule's feet), the pelvis over it.

const BvhClip := preload("res://tests/manual/ledge_anim/bvh_clip.gd")
const BvhRetarget := preload("res://tests/manual/ledge_anim/bvh_retarget.gd")
## A standing pose in the clips' own set: the roll of the clips is read against it.
const CALIBRATION := "ledge-facing-idle"
const DIR := "D:/RE/game_locomotion/anims/bvh_trav_ledge/"


static func available() -> bool:
	return DirAccess.dir_exists_absolute(DIR)


## `anchor`: the frame (0 = first, 1 = last) that is lined up with the wrists at `wrist_height`.
## `track_prefix` is the animation-player-relative skeleton path ("Skeleton3D" in "Skeleton3D:Hips").
## `settle_to`: a clip (baked the same way) whose first pose this one eases into at its end (a clip anchored on its
## last frame) or out of at its start (anchored on its first), so a hand-over
## between the two does not swing the legs through the wall.
## `tilt_from` / `tilt_to` (radians): the swing of the body away from the wall, at the clip's start and after
## `tilt_span` (fraction of the clip).
static func bake(file: String, retarget: BvhRetarget, track_prefix: String, wrist_height: float, wall_height: float,
		anchor: int, looping: bool, hands_in: float, tilt_from := 0.0, tilt_to := 0.0, tilt_span := 1.0, settle_to: Animation = null) -> Animation:
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
	retarget.wall_top = wall_height - 0.05 # the hold is at the top of the wall; the body below it keeps off the wall
	retarget.pivot = retarget.yaw * (wrists - retarget.origin)
	var reference: BvhClip = BvhClip.load_file(DIR + CALIBRATION + ".bvh")
	retarget.scale = retarget.fit_scale(reference)
	retarget.calibrate(reference, 0.0)
	retarget.scale = retarget.fit_scale(clip)
	retarget.carry_twist = true
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
		var settle := 0.0
		var fraction := float(frame) / float(maxi(clip.frames.size() - 1, 1))
		if settle_to != null:
			settle = smoothstep(0.65, 1.0, fraction) if anchor == 1 else 1.0 - smoothstep(0.0, 0.15, fraction)
		for bone in tracks:
			var rotation := skeleton.get_bone_pose_rotation(bone)
			if settle > 0.0:
				rotation = rotation.slerp(settle_to.rotation_track_interpolate(tracks[bone], 0.0), settle)
			anim.rotation_track_insert_key(tracks[bone], time, rotation)
		anim.position_track_insert_key(hips_track, time, skeleton.get_bone_pose_position(hips))
	retarget.tilt = 0.0
	retarget.carry_twist = false
	retarget.wall_top = INF
	skeleton.reset_bone_poses()
	return anim
