class_name PlayerBody
extends Node3D
## First-person body: the MotusMan mesh attached under the player so you see
## your own torso/legs and cast a shadow. The scene this script sits on is the
## aim-idle clip FBX; the other clips share the same skeleton, so their
## animations are merged into this AnimationPlayer at runtime (same trick as
## levels/animation_preview.gd).

const CLIP_DIR := "res://assets/models/pistol_starter/Animation/In-Place/"
const CLIPS := {
	&"relaxed_idle": "W1_Stand_Relaxed_Idle_IPC",
	&"aim_idle": "W1_Stand_Aim_Idle_IPC",
	&"walk": "W1_Walk_Aim_F_Loop_IPC",
	&"jog": "W1_Jog_Aim_F_Loop_IPC",
	&"crouch_idle": "W1_Crouch_Aim_Idle_IPC",
	&"crouch_walk": "W1_CrouchWalk_Aim_F_Loop_IPC",
}
## MotusMan FBXs bake broken absolute texture paths; reapply the diffuse.
const SKIN_TEXTURE := "res://assets/models/pistol_starter/MotusMan/sourceimages/MCG_diff.jpg"

## pistol_starter only ships an aim-pose walk - no unarmed walk clip exists
## for MotusMan there. This one comes from the CC0 "Universal Animation
## Library" pack instead (Unreal Mannequin-style rig, own bone names, own
## mesh - not used, just the animation), retargeted onto MotusMan at runtime
## (see _retarget_clip). Already in-place (no baked root motion).
const UAL_PATH := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const UAL_WALK_ANIM := &"Walk"
## Unreal Mannequin bone names, not Mixamo's - no shared prefix to strip, so
## this is an explicit map instead. Fingers are left out (not load-bearing
## for a walk cycle, MotusMan's finger names don't line up anyway).
const BONE_MAP: Dictionary = {
	&"pelvis": &"Hips",
	&"spine_01": &"Spine",
	&"spine_02": &"Spine1",
	&"spine_03": &"Spine2",
	&"neck_01": &"Neck",
	&"Head": &"Head",
	&"clavicle_r": &"RightShoulder",
	&"upperarm_r": &"RightArm",
	&"lowerarm_r": &"RightForeArm",
	&"hand_r": &"RightHand",
	&"clavicle_l": &"LeftShoulder",
	&"upperarm_l": &"LeftArm",
	&"lowerarm_l": &"LeftForeArm",
	&"hand_l": &"LeftHand",
	&"thigh_r": &"RightUpLeg",
	&"calf_r": &"RightLeg",
	&"foot_r": &"RightFoot",
	&"ball_r": &"RightToeBase",
	&"thigh_l": &"LeftUpLeg",
	&"calf_l": &"LeftLeg",
	&"foot_l": &"LeftFoot",
	&"ball_l": &"LeftToeBase",
}
## Arm bones retarget via position-based "swing" instead of the rotation
## delta every other bone uses (see _swing_retarget's doc comment) - full
## rotation transfer kept spreading the arms into a T-pose even with the
## delta computed in global space. Each entry names the child bone used to
## derive "which way is this bone currently pointing".
const SWING_BONES: Dictionary = {
	&"RightShoulder": &"RightArm",
	&"RightArm": &"RightForeArm",
	&"RightForeArm": &"RightHand",
	&"LeftShoulder": &"LeftArm",
	&"LeftArm": &"LeftForeArm",
	&"LeftForeArm": &"LeftHand",
}
## Hands: swing only reorients a bone by where ITS OWN child points, and
## hands have no further mapped child - held at relaxed_idle's wrist pose
## instead, same trick as the old held-bones approach. Not very noticeable
## at typical camera distance for a walk cycle.
const HELD_BONES: PackedStringArray = ["RightHand", "LeftHand"]

## Rough forward speeds (m/s) the clips were authored at, for foot matching.
const WALK_REF_SPEED := 1.6
const JOG_REF_SPEED := 3.0
const CROUCH_REF_SPEED := 1.1

## Camera pitch/yaw in radians, pushed by the player each physics tick.
var head_pitch := 0.0
var head_yaw := 0.0

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var mesh: MeshInstance3D = $Skeleton3D/MotusMan_v55


func _ready() -> void:
	# Higher priority = processed later: our head-bend pass in _process must
	# run AFTER the AnimationPlayer has written this frame's pose.
	process_priority = 100
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(SKIN_TEXTURE)
	material.roughness = 0.85
	mesh.material_override = material

	var lib := AnimationLibrary.new()
	for key: StringName in CLIPS:
		var clip_root: Node = (load(CLIP_DIR + CLIPS[key] + ".fbx") as PackedScene).instantiate()
		var clip_ap := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var anim := clip_ap.get_animation(CLIPS[key]).duplicate() as Animation
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, anim)
		clip_root.free()
	lib.add_animation(&"walk_relaxed",
			_retarget_clip(UAL_PATH, UAL_WALK_ANIM, lib.get_animation(&"relaxed_idle")))
	anim_player.add_animation_library(&"moves", lib)
	anim_player.play("moves/relaxed_idle")


## Copies a differently-rigged clip's tracks onto MotusMan's skeleton via
## BONE_MAP. Deltas are computed and reapplied in GLOBAL (skeleton-root)
## space, not each bone's parent-relative local space - see BONE_MAP's doc
## comment for why: a naive local-space "delta from own rest, reapplied to
## target's own rest" compounds the two rigs' differing bone-forward-axis
## conventions at every parent hop, and arms sit 6-7 hops deep (through the
## whole spine) versus 3-4 for legs, which is exactly why legs retargeted
## fine before while arms spread into a T-pose every time. Working in global
## space means each bone's delta is only ever relative to its OWN rest, with
## no compounding, regardless of chain depth.
##
## This requires resampling the source clip at fixed intervals (its own
## keyframe times aren't used directly) because a bone's global pose depends
## on its whole ANIMATED ancestor chain, not just its own track.
const RETARGET_SAMPLE_HZ := 30.0

func _retarget_clip(fbx_path: String, anim_name: StringName, held_pose: Animation) -> Animation:
	var clip_root: Node = (load(fbx_path) as PackedScene).instantiate()
	var clip_ap := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var src_skeleton := clip_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var src: Animation = null
	for lib_name in clip_ap.get_animation_library_list():
		var candidate_lib := clip_ap.get_animation_library(lib_name)
		if candidate_lib.has_animation(anim_name):
			src = candidate_lib.get_animation(anim_name)
			break

	# Which source track (if any) drives each source bone's rotation/position.
	var bone_tracks: Dictionary = {}
	for t in src.get_track_count():
		var path := src.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var bone_name := StringName(path.get_subname(0))
		if not bone_tracks.has(bone_name):
			bone_tracks[bone_name] = {}
		var track_type := src.track_get_type(t)
		if track_type == Animation.TYPE_ROTATION_3D:
			bone_tracks[bone_name]["rot"] = t
		elif track_type == Animation.TYPE_POSITION_3D:
			bone_tracks[bone_name]["pos"] = t

	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = Animation.LOOP_LINEAR

	var out_rot_track: Dictionary = {}
	for src_name in BONE_MAP:
		var target_name: StringName = BONE_MAP[src_name]
		if (target_name in HELD_BONES or not bone_tracks.has(src_name)
				or skeleton.find_bone(target_name) < 0 or src_skeleton.find_bone(src_name) < 0):
			continue
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("Skeleton3D:" + String(target_name)))
		out_rot_track[target_name] = track
	var out_pos_track := -1
	if not (&"Hips" in HELD_BONES) and bone_tracks.has(&"pelvis"):
		out_pos_track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(out_pos_track, NodePath("Skeleton3D:Hips"))

	var reverse_map: Dictionary = {}
	for src_name in BONE_MAP:
		reverse_map[BONE_MAP[src_name]] = src_name

	var sample_count := int(ceil(src.length * RETARGET_SAMPLE_HZ)) + 1
	for i in sample_count:
		var time: float = minf(i / RETARGET_SAMPLE_HZ, src.length)

		# Pass 1: fully pose the SOURCE skeleton for this sample first, every
		# mapped bone at once - SWING_BONES needs to look ahead at its own
		# child's animated position, which only exists once the whole source
		# pose for this instant has actually been applied.
		for src_name in BONE_MAP:
			var src_idx := src_skeleton.find_bone(src_name)
			if src_idx < 0 or not bone_tracks.has(src_name):
				continue
			var tracks: Dictionary = bone_tracks[src_name]
			var local_rot := src_skeleton.get_bone_rest(src_idx).basis.get_rotation_quaternion()
			if tracks.has("rot"):
				local_rot = src.rotation_track_interpolate(tracks["rot"], time)
			src_skeleton.set_bone_pose_rotation(src_idx, local_rot)
			if tracks.has("pos"):
				src_skeleton.set_bone_pose_position(src_idx, src.position_track_interpolate(tracks["pos"], time))

		# Pass 2: compute each target bone's retargeted GLOBAL pose, parent
		# first (BONE_MAP lists each chain root-to-leaf), then convert down
		# to target-local for storage.
		var target_global: Dictionary = {}
		for src_name in BONE_MAP:
			var target_name: StringName = BONE_MAP[src_name]
			var target_idx := skeleton.find_bone(target_name)
			var src_idx := src_skeleton.find_bone(src_name)
			if target_idx < 0 or src_idx < 0 or not bone_tracks.has(src_name):
				continue
			var target_rest := skeleton.get_bone_global_rest(target_idx)
			var target_basis: Basis
			var target_origin: Vector3 = target_rest.origin
			if SWING_BONES.has(target_name) and reverse_map.has(SWING_BONES[target_name]):
				target_basis = _swing_retarget(src_skeleton, src_idx, skeleton, target_idx,
						src_skeleton.find_bone(reverse_map[SWING_BONES[target_name]]),
						skeleton.find_bone(SWING_BONES[target_name]))
			else:
				var src_rest := src_skeleton.get_bone_global_rest(src_idx)
				var src_pose_global := src_skeleton.get_bone_global_pose(src_idx)
				var delta := src_rest.basis.inverse() * src_pose_global.basis
				target_basis = target_rest.basis * delta
				if target_name == &"Hips":
					var offset: Vector3 = src_pose_global.origin - src_rest.origin
					offset.x = 0.0
					offset.z = 0.0
					target_origin = target_rest.origin + offset
			var pose_global := Transform3D(target_basis, target_origin)
			target_global[target_idx] = pose_global
			if target_name in HELD_BONES:
				continue
			var parent_idx := skeleton.get_bone_parent(target_idx)
			var parent_global: Transform3D = target_global.get(
					parent_idx, skeleton.get_bone_global_rest(parent_idx)) if parent_idx >= 0 else Transform3D()
			var local := parent_global.affine_inverse() * pose_global
			if out_rot_track.has(target_name):
				anim.track_insert_key(out_rot_track[target_name], time, local.basis.get_rotation_quaternion())
			if target_name == &"Hips" and out_pos_track >= 0:
				anim.track_insert_key(out_pos_track, time, local.origin)
	clip_root.free()
	for held_bone in HELD_BONES:
		_bake_held_track(anim, held_bone, held_pose, src.length)
	return anim


## Retargets a bone by matching WHERE IT POINTS (its own to its child's
## global position, i.e. the direction of the bone itself in world space)
## rather than transferring its full rotation. Positions carry no "which
## local axis means forward" ambiguity at all, so this sidesteps the exact
## question full rotation transfer needs to get right - and gets wrong for
## the arms specifically, every attempt so far (spread into a T-pose).
## Trade-off: no roll/twist (e.g. forearm pronation) survives, only the
## swing - not very visible on this rig at typical camera distance for a
## walk cycle.
func _swing_retarget(src_skel: Skeleton3D, src_idx: int, target_skel: Skeleton3D, target_idx: int,
		src_child_idx: int, target_child_idx: int) -> Basis:
	var target_rest := target_skel.get_bone_global_rest(target_idx)
	if src_child_idx < 0 or target_child_idx < 0:
		return target_rest.basis
	var src_rest_dir := (src_skel.get_bone_global_rest(src_child_idx).origin
			- src_skel.get_bone_global_rest(src_idx).origin).normalized()
	var src_pose_dir := (src_skel.get_bone_global_pose(src_child_idx).origin
			- src_skel.get_bone_global_pose(src_idx).origin).normalized()
	var swing := _swing_between(src_rest_dir, src_pose_dir)
	return swing * target_rest.basis


## Shortest-arc rotation that takes `from` to `to` (both must be normalized).
func _swing_between(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	var len := axis.length()
	if len < 0.0001:
		if from.dot(to) > 0.0:
			return Basis.IDENTITY
		var perp := from.cross(Vector3.UP)
		if perp.length() < 0.0001:
			perp = from.cross(Vector3.RIGHT)
		return Basis(perp.normalized(), PI)
	return Basis(axis / len, from.angle_to(to))


## Adds a rotation track for held_bone holding a single fixed pose (its
## value from held_pose's first keyframe) for the whole clip duration.
func _bake_held_track(
		anim: Animation, held_bone: StringName, held_pose: Animation, length: float) -> void:
	for t in held_pose.get_track_count():
		var path := held_pose.track_get_path(t)
		if (path.get_subname_count() > 0 and StringName(path.get_subname(0)) == held_bone
				and held_pose.track_get_type(t) == Animation.TYPE_ROTATION_3D):
			var value = held_pose.track_get_key_value(t, 0)
			var new_track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(new_track, NodePath("Skeleton3D:" + String(held_bone)))
			anim.track_insert_key(new_track, 0.0, value)
			anim.track_insert_key(new_track, length, value)
			return


func _process(_delta: float) -> void:
	# Torso first: Neck sits on Spine2, so leaning the spine forward moves
	# where the neck/head bend starts from, same as a real body would.
	_bend_torso()
	_bend_head_bones()


## Looking straight down would bend the neck/head further than a real neck
## can, folding the chin/hood into the chest - clamp well short of the
## camera's own pitch_limit_deg so the mesh stops before it clips.
##
## The up limit is lower than you'd expect from anatomy alone: past ~72-75
## the linear-blend skin between Neck and Head stretches visibly (the
## classic "candy wrapper" artifact large joint rotations cause on this kind
## of rig) - 60 leaves real margin below where that starts.
const MAX_BEND_DOWN_DEG := 40.0
const MAX_BEND_UP_DEG := 60.0

## Same clamp the mesh bend uses. The player reads this to keep the eye
## position locked to the actual bone pose - if the neck stops bending, the
## eye must stop moving with it instead of sliding on past the frozen mesh.
func clamp_head_pitch(p: float) -> float:
	return clampf(p, -deg_to_rad(MAX_BEND_DOWN_DEG), deg_to_rad(MAX_BEND_UP_DEG))


## A small forward lean when looking down - just enough to read as leaning
## to look rather than a rigid periscope neck. Pitch only (yaw already turns
## the body itself via the head-yaw-limit/catch-up system), and only for
## looking down, not up. Same clamped pitch as the neck/head bend so it
## eases back out at the same rate.
const TORSO_BEND: Dictionary = {
	&"Spine": 0.04,
	&"Spine1": 0.05,
	&"Spine2": 0.06,
}

func _bend_torso() -> void:
	var clamped_pitch := clamp_head_pitch(head_pitch)
	if clamped_pitch >= 0.0:
		return
	for bone_name: StringName in TORSO_BEND:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var portion: float = TORSO_BEND[bone_name]
		var pose := skeleton.get_bone_global_pose(idx)
		pose.basis = Basis(Vector3.RIGHT, -clamped_pitch * portion) * pose.basis
		skeleton.set_bone_global_pose(idx, pose)


## Each axis is clamped on its own (MAX_BEND_*_DEG, head_yaw_limit_deg), but
## pitch and yaw near their limits *at the same time* compose into a larger
## rotation than either alone - large enough to hit the same skin-stretch
## artifact even though neither individual clamp was exceeded. Scale the
## (yaw, pitch) pair down together, as a single vector, so their combined
## magnitude never exceeds MAX_BEND_UP_DEG either - this only affects the
## visible bend, not the camera's actual look direction.
const MAX_COMBINED_BEND_DEG := MAX_BEND_UP_DEG

## Bend neck (35%) and head (65%) with the camera pitch/yaw so the skull
## rotates with the view instead of the camera diving through it. Runs
## after animation (process_priority), rotating the animated pose.
func _bend_head_bones() -> void:
	var split := {&"Neck": 0.35, &"Head": 0.65}
	var clamped_pitch := clamp_head_pitch(head_pitch)
	var yaw := head_yaw
	var combined := Vector2(yaw, clamped_pitch)
	var max_combined := deg_to_rad(MAX_COMBINED_BEND_DEG)
	if combined.length() > max_combined:
		combined = combined.normalized() * max_combined
		yaw = combined.x
		clamped_pitch = combined.y
	for bone_name: StringName in split:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var portion: float = split[bone_name]
		var pose := skeleton.get_bone_global_pose(idx)
		pose.basis = (Basis(Vector3.UP, yaw * portion)
				* Basis(Vector3.RIGHT, -clamped_pitch * portion) * pose.basis)
		skeleton.set_bone_global_pose(idx, pose)


## Called by the player every physics tick (calls down, signals up).
func update_motion(crouched: bool, armed: bool, ground_speed: float,
		sprinting: bool) -> void:
	var target: StringName
	var rate := 1.0
	if ground_speed > 0.6:
		if crouched:
			target = &"crouch_walk"
			rate = ground_speed / CROUCH_REF_SPEED
		elif sprinting:
			target = &"jog"
			rate = ground_speed / JOG_REF_SPEED
		else:
			target = &"walk" if armed else &"walk_relaxed"
			rate = ground_speed / WALK_REF_SPEED
	elif crouched:
		target = &"crouch_idle"
	else:
		target = &"aim_idle" if armed else &"relaxed_idle"
	var full := "moves/" + target
	if anim_player.current_animation != full:
		anim_player.play(full, 0.3)
	anim_player.speed_scale = clampf(rate, 0.8, 2.2)
