class_name PlayerTempWalk
extends RefCounted
## TEMPORARY experiment: plays another forward walk as `unarmed_walk` to compare how they look.
## CHOICE picks the clip (0 = ALS normal walk, 1 = UAL1 Walk_Formal, 2 = UAL2 Walk_Carry, 3 = UAL2
## Zombie walk, 4 = Mixamo walking); -1 or ENABLED = false keeps UAL1's `Walk`. Every clip is
## retargeted at startup onto whatever character the player wears, like the UAL clips. Delete this
## file and its call in PlayerStairClips.add_to to remove the experiment.

const ENABLED := true
const CHOICE := 4 # the user's pick (Mixamo walking at PLAYBACK_SCALE)
const ALS_PATH := "res://assets/models/als_mannequin_standalone/full_set/ALS_N_Walk_F.fbx"
const UAL1_PATH := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const UAL2_PATH := "res://assets/models/universal_animation_library_2/UAL2_Standard.glb"
const MIXAMO_PATH := "res://assets/models/action_adventure_pack/walking.fbx"
const HBM_MODEL := "res://assets/models/human_basic_motions/HumanM_Model.fbx"
const HBM_WALK := "res://assets/models/human_basic_motions/HumanM@Walk01_Forward.fbx"
const PLAYBACK_SCALE := 0.575 # the Mixamo walk plays at this fraction of the matching speed
## Also play ALS diagonal and backward walks (needs the forward experiment, in a normal run).
const DIRECTIONAL := false # off until the user confirms the ALS diagonals/backward/sideways look
## Pure sideways: 0 = the old strafe clips, 1 = ALS LF blended with LB (RF with RB), 2 = the ALS
## diagonal turned SIDE_YAW_DEG at the hips, so its diagonal steps become sideways steps.
const SIDEWAYS := 2
const SIDE_YAW_DEG := 45.0
const ALS_DIR := "res://assets/models/als_mannequin_standalone/full_set/"
const DIRECTIONAL_CLIPS := {
	&"unarmed_walk_fwd_left": "ALS_N_Walk_LF", &"unarmed_walk_fwd_right": "ALS_N_Walk_RF",
	&"unarmed_walk_back": "ALS_N_Walk_B", &"unarmed_walk_back_left": "ALS_N_Walk_LB",
	&"unarmed_walk_back_right": "ALS_N_Walk_RB",
}
## [source file, clip name in it ("" = the file's only clip)]
## Walking speed (m/s at 1x playback) of the experiment clip when it has to override the walk speed
## reference (0 = use the game's): its feet must cover the ground it is played at.
static var clip_speed := 0.0
static var _lengths: Dictionary = {} # directional clip name -> loop length (s)
static var _forward_length := 1.3333 # loop length of the forward experiment clip (s)
const CHOICES: Array = [
	[ALS_PATH, ""],
	[UAL1_PATH, &"Walk_Formal"],
	[UAL2_PATH, &"Walk_Carry"],
	[UAL2_PATH, &"Zombie_Walk_Fwd"],
	[MIXAMO_PATH, ""],
	[HBM_WALK, ""],
]


## A headless check can ask for the experiment walks (the comparison scene's --temp-walk).
static var use_in_headless := false


static func _skip_headless() -> bool:
	return DisplayServer.get_name() == "headless" and not use_in_headless


static func apply(library: AnimationLibrary, body: PlayerBody) -> void:
	if (not ENABLED or CHOICE < 0 or CHOICE >= CHOICES.size() or _skip_headless()
			or not library.has_animation(&"unarmed_walk")): # headless checks keep the real walk
		return
	var path: String = CHOICES[CHOICE][0]
	var clip_name: StringName = CHOICES[CHOICE][1]
	var clip: Animation = _als(body) if path == ALS_PATH else _hbm(body) if path == HBM_WALK \
			else _mixamo(library, body) \
			if path == MIXAMO_PATH else body._retarget_clip(
			path, clip_name, body._held_pose, true)
	if clip == null:
		push_warning("PlayerTempWalk: clip %s not found in %s" % [clip_name, path])
		return
	library.remove_animation(&"unarmed_walk")
	_forward_length = clip.length
	library.add_animation(&"unarmed_walk", clip)
	if DIRECTIONAL:
		_add_directional(library, body)


## The ALS file has one clip; its bone names differ from the map's (`head`, not `Head`): with it
## unfound the rest facing came out 180 degrees wrong and the arm IK crossed the arms.
static func _als(body: PlayerBody, path := ALS_PATH) -> Animation:
	var source := (load(path) as PackedScene).instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var clip: Animation = null
	for lib_name in source_player.get_animation_library_list():
		for candidate in source_player.get_animation_library(lib_name).get_animation_list():
			if clip == null and candidate != &"RESET":
				clip = source_player.get_animation_library(lib_name).get_animation(candidate)
	var result: Animation = null
	if clip != null:
		var config: HumanoidRetargeter.BoneMapConfig = body._retarget_config
		var old_head := config.head_source
		if source_skeleton.find_bone(old_head) < 0 and source_skeleton.find_bone(&"head") >= 0:
			config.head_source = &"head"
		result = HumanoidRetargeter.retarget_clip(
				source_skeleton, clip, body.skeleton, config, true, true)
		config.head_source = old_head
	source.free()
	return result


## The Action Pack's Mixamo walk, retargeted the way the Action Pack strafe clips are (in place, no
## arm IK): the shared helper adds it to the library under a throwaway name, taken back out.
static func _mixamo(library: AnimationLibrary, body: PlayerBody) -> Animation:
	var config := UniversalAnimationPools.mixamo_to_target_map_config(
			"mixamorig_", body._target_humanoid_map)
	PlayerDirectionalLocomotionLibrary._retarget_action_clip(library, &"temp_mixamo_walk",
			MIXAMO_PATH, body.skeleton, body.skeleton, config, library.get_animation(&"unarmed_walk"),
			false, body._target_humanoid_map, true)
	if not library.has_animation(&"temp_mixamo_walk"):
		return null
	var clip := library.get_animation(&"temp_mixamo_walk")
	clip_speed = _in_place(clip, body)
	library.remove_animation(&"temp_mixamo_walk")
	return clip


## `make_clip_in_place` assumes the hips' local Y is up, but this rig has Z up and Y forward,
## so the Mixamo walk kept its forward travel: the body walked ahead then snapped back at the loop.
## Removes the accumulated travel along the two horizontal axes and returns the speed it covered
## (m/s at 1x), which is the clip's own walking speed.
static func _in_place(clip: Animation, body: PlayerBody) -> float:
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var bone := body.skeleton.find_bone(StringName(clip.track_get_path(track).get_subname(0)))
		var parent := body.skeleton.get_bone_parent(bone)
		var parent_basis := body.skeleton.get_bone_global_rest(parent).basis if parent >= 0 \
				else Basis.IDENTITY
		var vertical := 0
		var best := 0.0
		for axis in 3:
			var up := absf((parent_basis * _unit(axis)).y)
			if up > best:
				best = up
				vertical = axis
		var count := clip.track_get_key_count(track)
		var first := clip.track_get_key_value(track, 0) as Vector3
		var last := clip.track_get_key_value(track, count - 1) as Vector3
		var travel := last - first
		travel[vertical] = 0.0
		for key in count:
			var progress := clip.track_get_key_time(track, key) / clip.length
			var value := clip.track_get_key_value(track, key) as Vector3
			clip.track_set_key_value(track, key, value - travel * progress)
		return travel.length() / clip.length
	return 0.0


static func _unit(axis: int) -> Vector3:
	return Vector3(1.0 if axis == 0 else 0.0, 1.0 if axis == 1 else 0.0, 1.0 if axis == 2 else 0.0)




## The Human Basic Motions walk ("B-" bones): the project's own HBM bone map, arm IK on, like its
## library builder (UniversalAnimationPools), then the same in-place fix as the Mixamo walk.
static func _hbm(body: PlayerBody) -> Animation:
	var source_root := (load(HBM_MODEL) as PackedScene).instantiate()
	var source_skeleton := source_root.get_node(^"Skeleton3D") as Skeleton3D
	var clip_root := (load(HBM_WALK) as PackedScene).instantiate()
	var clip_player := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source: Animation = null
	for lib_name in clip_player.get_animation_library_list():
		var library := clip_player.get_animation_library(lib_name)
		if library.has_animation(&"HumanM_Walk01_Forward"):
			source = library.get_animation(&"HumanM_Walk01_Forward")
	var result: Animation = null
	if source != null:
		var config := UniversalAnimationPools._hbm_to_target_map_config(body._target_humanoid_map)
		result = HumanoidRetargeter.retarget_clip(
				source_skeleton, source, body.skeleton, config, true)
		_in_place(result, body)
		# in place already: pick the speed that gives the UAL walk's step rate (1.6 m/s for 1.33 s)
		clip_speed = 1.6 * (1.3333 / result.length) * PLAYBACK_SCALE
	clip_root.free()
	source_root.free()
	return result


## ALS diagonal and backward walks, retargeted like the forward one, added as new clips.
static func _add_directional(library: AnimationLibrary, body: PlayerBody) -> void:
	for clip_name: StringName in DIRECTIONAL_CLIPS:
		var clip := _als(body, ALS_DIR + String(DIRECTIONAL_CLIPS[clip_name]) + ".fbx")
		if clip == null:
			continue
		if library.has_animation(clip_name):
			library.remove_animation(clip_name)
		library.add_animation(clip_name, clip)
		_lengths[clip_name] = clip.length
	if SIDEWAYS == 1:
		for pair in [[&"unarmed_walk_side_left", &"unarmed_walk_fwd_left", &"unarmed_walk_back_left"],
				[&"unarmed_walk_side_right", &"unarmed_walk_fwd_right", &"unarmed_walk_back_right"]]:
			var side := PlayerDirectionalLocomotionLibrary._blend_animations(
					library.get_animation(pair[1]), library.get_animation(pair[2]), 0.5)
			library.add_animation(pair[0], side)
			_lengths[pair[0]] = side.length
	if SIDEWAYS == 2:
		for pair in [[&"unarmed_walk_side_left", &"unarmed_walk_fwd_left", 1.0],
				[&"unarmed_walk_side_right", &"unarmed_walk_fwd_right", -1.0]]:
			var side := _yawed(
					library.get_animation(pair[1]), deg_to_rad(SIDE_YAW_DEG) * pair[2], body)
			library.add_animation(pair[0], side)
			_lengths[pair[0]] = side.length


## Experiment: A / D alone turn the whole body 90 degrees toward the move side (the head keeps the
## camera aim, like W+A / W+D at 45) and play the forward walk instead of the strafe clips.
const SIDE_BODY_TURN := false
## S+A / S+D turn the body 45 degrees and play the reverse walk (confirmed look).
const BACK_BODY_TURN := true
## A / D alone (body not turned, only while SIDE_BODY_TURN is off): 0 = the old Action Pack strafe
## clips, 1 = ALS CLF_Walk_L/R (CROUCH walks), 2 = walk_strafe_left/right (deformed limbs),
## 3 = ALS N_Walk_LF / RF with the hips turned SIDE_YAW_DEG (diagonal steps become sideways).
const SIDE_SET := 3
const ALS_TURNED_CLIPS := {
	&"unarmed_walk_left": ["ALS_N_Walk_LF", 1.0], &"unarmed_walk_right": ["ALS_N_Walk_RF", -1.0],
}
const ALS_SIDE_CLIPS := {
	&"unarmed_walk_left": "ALS_CLF_Walk_L", &"unarmed_walk_right": "ALS_CLF_Walk_R",
}
const STRAFE2_CLIPS := {
	&"unarmed_walk_left": "res://assets/models/imported_animations/walk_strafe_left.fbx",
	&"unarmed_walk_right": "res://assets/models/imported_animations/walk_strafe_right.dae",
}


## Called after the Action Pack strafe clips are built (they would overwrite these). Headless
## checks keep the old strafes, like the forward walk.
static func apply_side(library: AnimationLibrary, body: PlayerBody) -> void:
	if (ENABLED and SIDE_SET > 0 and not SIDE_BODY_TURN and _forward_length > 0.0
			and not _skip_headless()):
		_add_side_clips(library, body)


## Replaces the strafe clips with SIDE_SET's sideways walks, retargeted like the forward one. They
## play at the forward walk's step rate (`ref_speed`), so the legs stay in step with W.
static func _add_side_clips(library: AnimationLibrary, body: PlayerBody) -> void:
	var sources: Dictionary = ALS_SIDE_CLIPS if SIDE_SET == 1 else STRAFE2_CLIPS
	if SIDE_SET == 3:
		sources = ALS_TURNED_CLIPS
	for clip_name: StringName in sources:
		var clip: Animation = null
		if SIDE_SET == 3:
			clip = _als(body, ALS_DIR + String(sources[clip_name][0]) + ".fbx")
			if clip != null:
				clip = _yawed(clip, deg_to_rad(SIDE_YAW_DEG) * float(sources[clip_name][1]), body)
		elif SIDE_SET == 1:
			clip = _als(body, ALS_DIR + String(sources[clip_name]) + ".fbx")
		else:
			clip = _strafe2(library, body, sources[clip_name])
		if clip == null:
			push_warning("PlayerTempWalk: side clip %s did not load" % clip_name)
			continue
		if library.has_animation(clip_name):
			library.remove_animation(clip_name)
		library.add_animation(clip_name, clip)
		_lengths[clip_name] = clip.length


## A Mixamo-rig sideways clip, retargeted by the Action Pack helper under a throwaway name, then
## made in place on the right axis (a no-op for a clip that already stays put).
static func _strafe2(library: AnimationLibrary, body: PlayerBody, path: String) -> Animation:
	var config := UniversalAnimationPools.mixamo_to_target_map_config(
			"mixamorig_", body._target_humanoid_map)
	PlayerDirectionalLocomotionLibrary._retarget_action_clip(library, &"temp_side_clip", path,
			body.skeleton, body.skeleton, config, library.get_animation(&"unarmed_walk"), false,
			body._target_humanoid_map, true)
	if not library.has_animation(&"temp_side_clip"):
		return null
	var clip := library.get_animation(&"temp_side_clip")
	_in_place(clip, body)
	library.remove_animation(&"temp_side_clip")
	return clip


## True when the body should turn: forward (W, W+A, W+D), or with the experiment on A / D alone and
## the back diagonals (S+A, S+D). Plain S keeps the old behaviour.
static func turns_body(input_dir: Vector2) -> bool:
	return input_dir.y < -0.2 or side_is_forward_walk(input_dir) or back_diagonal(input_dir)


## S+A / S+D with the experiment on: the body faces away from the move direction (45 degrees) and
## the walk plays in reverse, the same way W+A turns the body 45 degrees.
static func back_diagonal(input_dir: Vector2) -> bool:
	return BACK_BODY_TURN and input_dir.y > 0.2 and absf(input_dir.x) > 0.2


## The body yaw offset for a travel angle: toward the travel direction, or for the back diagonals
## the opposite way round (travel angle 135 degrees left gives 45 degrees right).
static func body_turn(input_dir: Vector2, travel_angle: float) -> float:
	return travel_angle - signf(travel_angle) * PI if input_dir.y > 0.2 else travel_angle


## A / D alone (not backward) while the side-turn experiment is on.
static func side_is_forward_walk(input_dir: Vector2) -> bool:
	return SIDE_BODY_TURN and absf(input_dir.x) > 0.2 and input_dir.y <= 0.2


## The clip for a movement input while the directional experiment is on, else &"" (the game's own
## choice). Forward is the forward walk, a wide angle off forward is a diagonal, sideways keeps the
## strafe clips, backward is the ALS backward walk.
static func directional(input: Vector2) -> StringName:
	if not ENABLED or not DIRECTIONAL or _lengths.is_empty() or input.is_zero_approx():
		return &""
	var norm := input.normalized()
	if norm.y < -0.2:
		if absf(norm.x) < 0.38:
			return &""
		return &"unarmed_walk_fwd_left" if norm.x < 0.0 else &"unarmed_walk_fwd_right"
	if norm.y > 0.2:
		if absf(norm.x) < 0.38:
			return &"unarmed_walk_back"
		return &"unarmed_walk_back_left" if norm.x < 0.0 else &"unarmed_walk_back_right"
	if SIDEWAYS > 0 and absf(norm.x) > 0.2: # A or D alone
		return &"unarmed_walk_side_left" if norm.x < 0.0 else &"unarmed_walk_side_right"
	return &""


## The ground speed (m/s at 1x) a walk clip is played against. The forward experiment clip has its
## own; a directional clip gets the forward clip's step rate (same steps per second at the same
## ground speed), so the walks stay in step when the direction changes.
static func ref_speed(target: StringName, is_strafe: bool) -> float:
	var fallback := PlayerBody.STRAFE_REF_SPEED if is_strafe else PlayerBody.WALK_REF_SPEED
	var forward := clip_speed / PLAYBACK_SCALE if ENABLED and clip_speed > 0.1 else 0.0
	if target == &"unarmed_walk" and forward > 0.0:
		return forward
	if _lengths.has(target) and forward > 0.0:
		return forward * _forward_length / float(_lengths[target])
	return fallback


## A copy of `clip` with the hips turned `yaw` radians about the world's up axis (+ = left): the
## legs and torso below turn with it, so a diagonal walk's steps become sideways steps.
static func _yawed(clip: Animation, yaw: float, body: PlayerBody) -> Animation:
	var turned := clip.duplicate() as Animation
	var hips_path := NodePath(
			"%s:%s" % [body.skeleton.name, body._retarget_config.hips_target])
	# a bone's rotation is relative to its parent, and this rig's hips hang under a rotated `root`
	var hips := body.skeleton.find_bone(StringName(body._retarget_config.hips_target))
	var parent := body.skeleton.get_bone_parent(hips)
	var parent_basis := body.skeleton.get_bone_global_rest(parent).basis if parent >= 0 \
			else Basis.IDENTITY
	var up := (parent_basis.inverse() * (
			body.skeleton.global_transform.basis.inverse() * Vector3.UP)).normalized()
	var turn := Quaternion(up, yaw)
	for track in turned.get_track_count():
		if turned.track_get_type(track) != Animation.TYPE_ROTATION_3D \
				or turned.track_get_path(track) != hips_path:
			continue
		for key in turned.track_get_key_count(track):
			var rotation := turned.track_get_key_value(track, key) as Quaternion
			turned.track_set_key_value(track, key, turn * rotation)
	return turned
