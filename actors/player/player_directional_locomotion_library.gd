class_name PlayerDirectionalLocomotionLibrary
extends RefCounted
## Builds directional clips absent from UAL's forward-only gameplay set.

const ACTION_PACK_REFERENCE_PATH := "res://assets/models/action_adventure_pack/idle.fbx"
const ACTION_PACK_ANIMATION := &"mixamo_com"
const ACTION_PACK_CROUCH_CLIPS := {
	&"unarmed_crouch_left": "res://assets/models/action_adventure_pack/crouched sneaking left.fbx",
	&"unarmed_crouch_right": "res://assets/models/action_adventure_pack/crouched sneaking right.fbx",
}


static func crouch_animation(movement_input: Vector2) -> StringName:
	if movement_input.x < -0.5:
		return &"unarmed_crouch_left"
	if movement_input.x > 0.5:
		return &"unarmed_crouch_right"
	return &"unarmed_crouch_walk"


## MotusMan and arbitrary catalog characters do not share the Action Pack's
## rest axes, so these clips must use the model-space humanoid retargeter.
static func add_directional_crouch_clips(lib: AnimationLibrary, target_skeleton: Skeleton3D,
		target_humanoid_map: Dictionary) -> void:
	var reference_root := (load(ACTION_PACK_REFERENCE_PATH) as PackedScene).instantiate()
	var source_skeleton := reference_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var config := UniversalAnimationPools.mixamo_to_target_map_config(
			"mixamorig_", target_humanoid_map)
	var forward_reference := lib.get_animation(&"unarmed_crouch_walk")
	for gameplay_name: StringName in ACTION_PACK_CROUCH_CLIPS:
		var clip_root := (load(ACTION_PACK_CROUCH_CLIPS[gameplay_name]) as PackedScene).instantiate()
		var clip_player := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if clip_player != null and clip_player.has_animation(ACTION_PACK_ANIMATION):
			var source := clip_player.get_animation(ACTION_PACK_ANIMATION)
			var animation := HumanoidRetargeter.retarget_clip(
					source_skeleton, source, target_skeleton, config, true, false)
			HumanoidRetargeter.make_clip_in_place(animation)
			HumanoidRetargeter.align_clip_facing(
					animation, forward_reference, target_skeleton)
			lib.add_animation(gameplay_name, animation)
		clip_root.free()
	reference_root.free()
