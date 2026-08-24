class_name PlayerDirectionalLocomotionLibrary
extends RefCounted
## Builds directional clips absent from UAL's forward-only gameplay set.

const ACTION_PACK_REFERENCE_PATH := "res://assets/models/action_adventure_pack/idle.fbx"
const ACTION_PACK_ANIMATION := &"mixamo_com"
const ACTION_PACK_CROUCH_CLIPS := {
	&"unarmed_crouch_left": "res://assets/models/action_adventure_pack/crouched sneaking left.fbx",
	&"unarmed_crouch_right": "res://assets/models/action_adventure_pack/crouched sneaking right.fbx",
}
const ACTION_PACK_STAND_CLIPS := {
	&"unarmed_walk_left": "res://assets/models/imported_animations/left_strafe_walking.fbx",
	&"unarmed_walk_right": "res://assets/models/imported_animations/right_strafe_walking.fbx",
}


static func walk_animation(movement_input: Vector2) -> StringName:
	if movement_input.is_zero_approx():
		return &"unarmed_walk"
	var norm := movement_input.normalized()
	var abs_x := absf(norm.x)
	var abs_y := absf(norm.y)
	if abs_x < 0.25:
		return &"unarmed_walk"
	if abs_y < 0.25:
		return &"unarmed_walk_left" if norm.x < 0.0 else &"unarmed_walk_right"
	if norm.y < 0.0:
		return &"unarmed_walk_fwd_left" if norm.x < 0.0 else &"unarmed_walk_fwd_right"
	return &"unarmed_walk_left" if norm.x < 0.0 else &"unarmed_walk_right"


static func crouch_animation(movement_input: Vector2) -> StringName:
	if movement_input.is_zero_approx():
		return &"unarmed_crouch_walk"
	var norm := movement_input.normalized()
	if absf(norm.x) > absf(norm.y) * 1.5:
		return &"unarmed_crouch_left" if norm.x < 0.0 else &"unarmed_crouch_right"
	return &"unarmed_crouch_walk"


## MotusMan and arbitrary catalog characters do not share the Action Pack's
## rest axes, so these clips must use the model-space humanoid retargeter.
static func add_directional_crouch_clips(lib: AnimationLibrary, target_skeleton: Skeleton3D,
		target_humanoid_map: Dictionary) -> void:
	var reference_root := (load(ACTION_PACK_REFERENCE_PATH) as PackedScene).instantiate()
	var source_skeleton := reference_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var config := UniversalAnimationPools.mixamo_to_target_map_config(
			"mixamorig_", target_humanoid_map)
	var forward_crouch := lib.get_animation(&"unarmed_crouch_walk")
	var forward_walk := lib.get_animation(&"unarmed_walk")

	for gameplay_name: StringName in ACTION_PACK_CROUCH_CLIPS:
		_retarget_action_clip(lib, gameplay_name, ACTION_PACK_CROUCH_CLIPS[gameplay_name],
				source_skeleton, target_skeleton, config, forward_crouch, true,
				target_humanoid_map, true)
	for gameplay_name: StringName in ACTION_PACK_STAND_CLIPS:
		_retarget_action_clip(lib, gameplay_name, ACTION_PACK_STAND_CLIPS[gameplay_name],
				source_skeleton, target_skeleton, config, forward_walk, false,
				target_humanoid_map, true)
	if lib.has_animation(&"unarmed_walk") and lib.has_animation(&"unarmed_walk_left"):
		var fwd := lib.get_animation(&"unarmed_walk")
		var left := lib.get_animation(&"unarmed_walk_left")
		var right := lib.get_animation(&"unarmed_walk_right")
		lib.add_animation(&"unarmed_walk_fwd_left", _blend_animations(fwd, left, 0.38))
		lib.add_animation(&"unarmed_walk_fwd_right", _blend_animations(fwd, right, 0.38))
	reference_root.free()


static func _blend_animations(anim_a: Animation, anim_b: Animation, weight_b: float) -> Animation:
	var blended := Animation.new()
	var duration: float = lerpf(anim_a.length, anim_b.length, weight_b)
	blended.length = duration
	blended.loop_mode = Animation.LOOP_LINEAR
	var fps := 30.0
	var frame_count := int(round(duration * fps))

	var tracks_a := {}
	for t in anim_a.get_track_count():
		tracks_a[anim_a.track_get_path(t)] = t
	var tracks_b := {}
	for t in anim_b.get_track_count():
		tracks_b[anim_b.track_get_path(t)] = t

	for path: NodePath in tracks_a:
		var ta: int = tracks_a[path]
		var type := anim_a.track_get_type(ta)
		var tb: int = tracks_b.get(path, -1)
		var new_track := blended.add_track(type)
		blended.track_set_path(new_track, path)

		for f in range(frame_count + 1):
			var norm_time := float(f) / float(frame_count)
			var time_a := norm_time * anim_a.length
			var time_b := norm_time * anim_b.length
			var t_out := norm_time * duration
			if type == Animation.TYPE_ROTATION_3D:
				var qa := _sample_rotation_track(anim_a, ta, time_a)
				var qb := _sample_rotation_track(anim_b, tb, time_b) if tb >= 0 else qa
				var q_blend := qa.slerp(qb, weight_b).normalized()
				blended.track_insert_key(new_track, t_out, q_blend)
			elif type == Animation.TYPE_POSITION_3D:
				var pa := _sample_position_track(anim_a, ta, time_a)
				var pb := _sample_position_track(anim_b, tb, time_b) if tb >= 0 else pa
				var p_blend := pa.lerp(pb, weight_b)
				blended.track_insert_key(new_track, t_out, p_blend)
	return blended


static func _sample_rotation_track(anim: Animation, track: int, time: float) -> Quaternion:
	var keys := anim.track_get_key_count(track)
	if keys == 0:
		return Quaternion.IDENTITY
	if keys == 1:
		return anim.track_get_key_value(track, 0)
	for i in range(keys - 1):
		var t0 := anim.track_get_key_time(track, i)
		var t1 := anim.track_get_key_time(track, i + 1)
		if time >= t0 and time <= t1:
			var factor := (time - t0) / (t1 - t0) if t1 > t0 else 0.0
			var q0: Quaternion = anim.track_get_key_value(track, i)
			var q1: Quaternion = anim.track_get_key_value(track, i + 1)
			return q0.slerp(q1, factor).normalized()
	return anim.track_get_key_value(track, keys - 1)


static func _sample_position_track(anim: Animation, track: int, time: float) -> Vector3:
	var keys := anim.track_get_key_count(track)
	if keys == 0:
		return Vector3.ZERO
	if keys == 1:
		return anim.track_get_key_value(track, 0)
	for i in range(keys - 1):
		var t0 := anim.track_get_key_time(track, i)
		var t1 := anim.track_get_key_time(track, i + 1)
		if time >= t0 and time <= t1:
			var factor := (time - t0) / (t1 - t0) if t1 > t0 else 0.0
			var p0: Vector3 = anim.track_get_key_value(track, i)
			var p1: Vector3 = anim.track_get_key_value(track, i + 1)
			return p0.lerp(p1, factor)
	return anim.track_get_key_value(track, keys - 1)


static func _retarget_action_clip(lib: AnimationLibrary, gameplay_name: StringName,
		source_path: String, source_skeleton: Skeleton3D, target_skeleton: Skeleton3D,
		default_config: HumanoidRetargeter.BoneMapConfig, forward_reference: Animation,
		align_facing: bool, target_humanoid_map: Dictionary, is_looping: bool = true) -> void:
	var clip_root := (load(source_path) as PackedScene).instantiate()
	var clip_player := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip_skel := clip_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if clip_skel == null:
		clip_skel = source_skeleton
	var prefix = HumanoidRetargeter.detect_bone_prefix(clip_skel)
	var config := default_config
	if prefix != null and prefix != "mixamorig_":
		config = UniversalAnimationPools.mixamo_to_target_map_config(
				prefix, target_humanoid_map)
	if clip_player != null and not clip_player.get_animation_list().is_empty():
		var anim_name: StringName = (ACTION_PACK_ANIMATION
				if clip_player.has_animation(ACTION_PACK_ANIMATION)
				else clip_player.get_animation_list()[0])
		var source := clip_player.get_animation(anim_name)
		var animation := HumanoidRetargeter.retarget_clip(
				clip_skel, source, target_skeleton, config, is_looping, false)
		animation.loop_mode = Animation.LOOP_LINEAR if is_looping else Animation.LOOP_NONE
		HumanoidRetargeter.make_clip_in_place(animation)
		if align_facing:
			HumanoidRetargeter.align_clip_facing(
					animation, forward_reference, target_skeleton)
		lib.add_animation(gameplay_name, animation)
	clip_root.free()
