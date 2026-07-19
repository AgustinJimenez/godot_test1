class_name HumanoidRetargeter
extends RefCounted

## Generic version of PlayerBody's UAL retarget engine (see player_body.gd's
## _retarget_clip and docs/task_history/ual_animation_retargeting.md for the
## full debugging history behind this exact math) - extracted as a
## standalone utility instead of shared code, deliberately, so nothing here
## can ever regress the already-hardened, gameplay-critical player rig.
## Duplicated on purpose; do not merge back into player_body.gd.
##
## Used to retarget Human Basic Motions FREE's "B-"-prefixed Blender-rigify
## skeleton onto the mixamorig7_-prefixed Ch08/10/15_nonPBR characters,
## which share the standard Mixamo skeleton SHAPE (same hierarchy depth and
## joint layout as MotusMan/Unreal Mannequin) but not the naming convention.
##
## Callers describe both skeletons via a BoneMapConfig instead of hardcoded
## bone name constants (contrast player_body.gd's BONE_MAP/SWING_BONES/
## HAND_BONES module-level consts), since this utility has no fixed source
## or target rig of its own.

const RETARGET_SAMPLE_HZ := 30.0


## - bone_map: source bone name -> target bone name, covering every bone
##   that should carry rotation (mirrors player_body.gd's BONE_MAP).
## - hips_source / hips_target: carries the root position track.
## - head_source / head_target, shoulder_l_source / shoulder_l_target,
##   shoulder_r_source / shoulder_r_target: only used to compute each rig's
##   own rest "facing" direction, for the arm IK's direction_map.
## - arm_chains: Array of Dictionary, one per arm, each with keys
##   source_hand, target_shoulder, target_arm, target_forearm, target_hand -
##   mirrors _match_arm_skeleton_positions' hardcoded Left/Right loop.
class BoneMapConfig:
	var bone_map: Dictionary = {}
	var hips_source: StringName
	var hips_target: StringName
	var head_source: StringName
	var head_target: StringName
	var shoulder_l_source: StringName
	var shoulder_l_target: StringName
	var shoulder_r_source: StringName
	var shoulder_r_target: StringName
	var arm_chains: Array[Dictionary] = []


## Mirrors player_body.gd's _retarget_clip (use_humanoid_retarget path
## only - the legacy delta/swing comparison modes that method also supports
## are debug-only scaffolding from the original UAL investigation and have
## no reason to exist twice).
static func retarget_clip(src_skeleton: Skeleton3D, src_animation: Animation,
		target_skeleton: Skeleton3D, config: BoneMapConfig,
		force_loop: bool = false) -> Animation:
	var bone_tracks: Dictionary = {}
	for t in src_animation.get_track_count():
		var path := src_animation.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var bone_name := StringName(path.get_subname(0))
		if not bone_tracks.has(bone_name):
			bone_tracks[bone_name] = {}
		var track_type := src_animation.track_get_type(t)
		if track_type == Animation.TYPE_ROTATION_3D:
			bone_tracks[bone_name]["rot"] = t
		elif track_type == Animation.TYPE_POSITION_3D:
			bone_tracks[bone_name]["pos"] = t

	var anim := Animation.new()
	anim.length = src_animation.length
	anim.loop_mode = Animation.LOOP_LINEAR if force_loop else src_animation.loop_mode

	var out_rot_track: Dictionary = {}
	for src_name: StringName in config.bone_map:
		var target_name: StringName = config.bone_map[src_name]
		if (not bone_tracks.has(src_name) or target_skeleton.find_bone(target_name) < 0
				or src_skeleton.find_bone(src_name) < 0):
			continue
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(String(target_skeleton.name) + ":" + String(target_name)))
		out_rot_track[target_name] = track
	var out_pos_track := -1
	if bone_tracks.has(config.hips_source):
		out_pos_track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(out_pos_track,
				NodePath(String(target_skeleton.name) + ":" + String(config.hips_target)))

	var source_hips := src_skeleton.find_bone(config.hips_source)
	var target_hips := target_skeleton.find_bone(config.hips_target)
	var position_scale := 1.0
	if source_hips >= 0 and target_hips >= 0:
		var source_height := src_skeleton.get_bone_global_rest(source_hips).origin.length()
		var target_height := target_skeleton.get_bone_global_rest(target_hips).origin.length()
		if source_height > 0.0001:
			position_scale = target_height / source_height
	var source_facing := _skeleton_rest_facing(src_skeleton, config.hips_source,
			config.head_source, config.shoulder_l_source, config.shoulder_r_source)
	var target_facing := _skeleton_rest_facing(target_skeleton, config.hips_target,
			config.head_target, config.shoulder_l_target, config.shoulder_r_target)
	var source_to_target_facing := Basis(Vector3.UP,
			source_facing.signed_angle_to(target_facing, Vector3.UP))
	var arm_position_scale := (
			_skeleton_height(target_skeleton, config.hips_target, config.head_target)
			/ maxf(_skeleton_height(src_skeleton, config.hips_source, config.head_source), 0.0001))
	var sample_count := int(ceil(src_animation.length * RETARGET_SAMPLE_HZ)) + 1
	for i in sample_count:
		var time: float = minf(i / RETARGET_SAMPLE_HZ, src_animation.length)

		for src_name: StringName in config.bone_map:
			var src_idx := src_skeleton.find_bone(src_name)
			if src_idx < 0 or not bone_tracks.has(src_name):
				continue
			var tracks: Dictionary = bone_tracks[src_name]
			var local_rot := src_skeleton.get_bone_rest(src_idx).basis.get_rotation_quaternion()
			if tracks.has("rot"):
				local_rot = src_animation.rotation_track_interpolate(tracks["rot"], time)
			src_skeleton.set_bone_pose_rotation(src_idx, local_rot)
			if tracks.has("pos"):
				src_skeleton.set_bone_pose_position(
						src_idx, src_animation.position_track_interpolate(tracks["pos"], time))

		var target_global: Dictionary = {}
		for src_name: StringName in config.bone_map:
			var target_name: StringName = config.bone_map[src_name]
			var target_idx := target_skeleton.find_bone(target_name)
			var src_idx := src_skeleton.find_bone(src_name)
			if target_idx < 0 or src_idx < 0 or not bone_tracks.has(src_name):
				continue
			var local := _humanoid_retarget_local_pose(
					src_skeleton, src_idx, target_skeleton, target_idx, position_scale)
			local.basis = Basis(local.basis.get_rotation_quaternion())
			var parent_idx := target_skeleton.get_bone_parent(target_idx)
			var parent_global := Transform3D()
			if parent_idx >= 0:
				parent_global = target_global.get(
						parent_idx, target_skeleton.get_bone_global_rest(parent_idx))
			target_global[target_idx] = parent_global * local
			target_skeleton.set_bone_pose_rotation(target_idx, local.basis.get_rotation_quaternion())
			target_skeleton.set_bone_pose_position(target_idx, local.origin)
			if out_rot_track.has(target_name):
				anim.track_insert_key(out_rot_track[target_name], time, local.basis.get_rotation_quaternion())
			if target_name == config.hips_target and out_pos_track >= 0:
				anim.track_insert_key(out_pos_track, time, local.origin)
		_match_arm_skeleton_positions(anim, src_skeleton, target_skeleton, target_global,
				out_rot_track, source_to_target_facing, arm_position_scale, config)
	return anim


static func _humanoid_retarget_local_pose(src_skel: Skeleton3D, src_idx: int,
		target_skel: Skeleton3D, target_idx: int, position_scale: float) -> Transform3D:
	var src_parent_rest := Transform3D()
	var src_parent := src_skel.get_bone_parent(src_idx)
	if src_parent >= 0:
		src_parent_rest = src_skel.get_bone_global_rest(src_parent)
	var target_parent_rest := Transform3D()
	var target_parent := target_skel.get_bone_parent(target_idx)
	if target_parent >= 0:
		target_parent_rest = target_skel.get_bone_global_rest(target_parent)
	var src_rest := src_skel.get_bone_rest(src_idx)
	var target_rest := target_skel.get_bone_rest(target_idx)
	var src_pose := src_skel.get_bone_pose(src_idx)
	var pre_basis := target_parent_rest.basis.inverse() * src_parent_rest.basis
	var post_basis := (src_rest.basis.inverse() * src_parent_rest.basis.inverse()
			* target_parent_rest.basis * target_rest.basis)
	var origin := (pre_basis * ((src_pose.origin - src_rest.origin) * position_scale)
			+ target_rest.origin)
	return Transform3D(pre_basis * src_pose.basis * post_basis, origin)


static func _match_arm_skeleton_positions(anim: Animation, src_skel: Skeleton3D,
		target_skel: Skeleton3D, target_global: Dictionary, out_rot_track: Dictionary,
		direction_map: Basis, position_scale: float, config: BoneMapConfig) -> void:
	var source_hips := _manual_global_pose(src_skel, src_skel.find_bone(config.hips_source)).origin
	var target_hips := _manual_global_pose(
			target_skel, target_skel.find_bone(config.hips_target)).origin
	for chain: Dictionary in config.arm_chains:
		var source_hand := src_skel.find_bone(StringName(chain["source_hand"]))
		var shoulder_idx := target_skel.find_bone(StringName(chain["target_shoulder"]))
		var arm_idx := target_skel.find_bone(StringName(chain["target_arm"]))
		var forearm_idx := target_skel.find_bone(StringName(chain["target_forearm"]))
		var hand_idx := target_skel.find_bone(StringName(chain["target_hand"]))
		if (source_hand < 0
				or shoulder_idx < 0 or arm_idx < 0 or forearm_idx < 0 or hand_idx < 0
				or not target_global.has(shoulder_idx) or not target_global.has(arm_idx)
				or not target_global.has(forearm_idx) or not target_global.has(hand_idx)):
			continue
		var joints: Array[Vector3] = [
			_manual_global_pose(target_skel, shoulder_idx).origin,
			_manual_global_pose(target_skel, arm_idx).origin,
			_manual_global_pose(target_skel, forearm_idx).origin,
			_manual_global_pose(target_skel, hand_idx).origin,
		]
		var lengths: Array[float] = [
			joints[0].distance_to(joints[1]),
			joints[1].distance_to(joints[2]),
			joints[2].distance_to(joints[3]),
		]
		var desired_wrist := target_hips + direction_map * (
				(_manual_global_pose(src_skel, source_hand).origin - source_hips) * position_scale)
		_solve_fabrik(joints, lengths, desired_wrist)
		var chain_indices := [shoulder_idx, arm_idx, forearm_idx]
		for joint in chain_indices.size():
			_aim_bone_at_direction(anim, target_skel, target_global, out_rot_track,
					chain_indices[joint], (joints[joint + 1] - joints[joint]).normalized())


static func _solve_fabrik(joints: Array[Vector3], lengths: Array[float], target: Vector3) -> void:
	var root := joints[0]
	var total_length := lengths[0] + lengths[1] + lengths[2]
	if root.distance_to(target) >= total_length:
		var direction := (target - root).normalized()
		for i in lengths.size():
			joints[i + 1] = joints[i] + direction * lengths[i]
		return
	for iteration in 12:
		joints[3] = target
		for i in range(2, -1, -1):
			joints[i] = joints[i + 1] + (joints[i] - joints[i + 1]).normalized() * lengths[i]
		joints[0] = root
		for i in lengths.size():
			joints[i + 1] = joints[i] + (joints[i + 1] - joints[i]).normalized() * lengths[i]
		if joints[3].distance_to(target) < 0.00001:
			break


static func _aim_bone_at_direction(anim: Animation, target_skel: Skeleton3D,
		target_global: Dictionary, out_rot_track: Dictionary, bone_idx: int,
		desired_direction: Vector3) -> void:
	var children := target_skel.get_bone_children(bone_idx)
	if children.is_empty():
		return
	var child_idx: int = children[0]
	var parent_idx := target_skel.get_bone_parent(bone_idx)
	var parent_global := _manual_global_pose(target_skel, parent_idx)
	var bone_global := _manual_global_pose(target_skel, bone_idx)
	var child_global := _manual_global_pose(target_skel, child_idx)
	var current_direction := (child_global.origin - bone_global.origin).normalized()
	var desired_global_basis := _swing_between(
			current_direction, desired_direction) * bone_global.basis
	var local_rotation := (parent_global.basis.inverse()
			* desired_global_basis).get_rotation_quaternion()
	target_skel.set_bone_pose_rotation(bone_idx, local_rotation)
	target_global[bone_idx] = _manual_global_pose(target_skel, bone_idx)
	var bone_name := target_skel.get_bone_name(bone_idx)
	if out_rot_track.has(bone_name):
		var track: int = out_rot_track[bone_name]
		anim.track_set_key_value(track, anim.track_get_key_count(track) - 1, local_rotation)


static func _skeleton_height(
		skel: Skeleton3D, hips_name: StringName, head_name: StringName) -> float:
	var hips := skel.get_bone_global_rest(skel.find_bone(hips_name)).origin
	var head := skel.get_bone_global_rest(skel.find_bone(head_name)).origin
	return hips.distance_to(head)


static func _skeleton_rest_facing(skel: Skeleton3D, hips_name: StringName, head_name: StringName,
		left_shoulder_name: StringName, right_shoulder_name: StringName) -> Vector3:
	var hips := skel.get_bone_global_rest(skel.find_bone(hips_name)).origin
	var head := skel.get_bone_global_rest(skel.find_bone(head_name)).origin
	var left := skel.get_bone_global_rest(skel.find_bone(left_shoulder_name)).origin
	var right := skel.get_bone_global_rest(skel.find_bone(right_shoulder_name)).origin
	var across := (right - left).normalized()
	var up := (head - hips).normalized()
	var facing := across.cross(up)
	facing.y = 0.0
	return facing.normalized()


## Same manual-parent-walk technique as player_body.gd's _manual_global_pose -
## Skeleton3D.get_bone_global_pose()'s cache only refreshes on the engine's
## own per-frame update, which never runs while baking offline in a static
## call like this.
static func _manual_global_pose(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := skel.get_bone_pose(idx)
	var parent := skel.get_bone_parent(idx)
	while parent >= 0:
		t = skel.get_bone_pose(parent) * t
		parent = skel.get_bone_parent(parent)
	return t


static func _swing_between(from: Vector3, to: Vector3) -> Basis:
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
