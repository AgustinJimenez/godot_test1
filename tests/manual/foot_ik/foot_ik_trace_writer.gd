class_name FootIkTraceWriter
extends RefCounted
## Maintains a recent JSONL window without rewriting the whole file each frame.

const COMPACT_INTERVAL := 300
const BODY_CHAIN_ROLES: Array[StringName] = [
	&"Hips", &"Spine", &"Spine1", &"Spine2", &"Neck", &"Head",
	&"LeftShoulder", &"LeftArm", &"LeftForeArm", &"LeftHand",
	&"RightShoulder", &"RightArm", &"RightForeArm", &"RightHand",
]

var _path: String
var _maximum_lines: int
var _lines: Array[String] = []
var _capture_count := 0


func _init(path: String, maximum_lines: int) -> void:
	_path = path
	_maximum_lines = maximum_lines


func capture(line: String) -> void:
	_lines.append(line)
	if _lines.size() > _maximum_lines:
		_lines.pop_front()
	_capture_count += 1
	var compact := _lines.size() == _maximum_lines and _capture_count % COMPACT_INTERVAL == 0
	var mode := FileAccess.WRITE if _capture_count == 1 or compact else FileAccess.READ_WRITE
	var file := FileAccess.open(_path, mode)
	if file == null:
		return
	if mode == FileAccess.READ_WRITE:
		file.seek_end()
		file.store_line(line)
	else:
		for recent_line: String in _lines:
			file.store_line(recent_line)
	file.close()


static func capture_joint_transforms(probes: Dictionary) -> Dictionary:
	var result := {}
	for joint: String in probes:
		var probe: Node3D = probes[joint]
		if probe == null:
			continue
		var xform := probe.global_transform
		result[joint] = {
			"position": xform.origin, "scale": xform.basis.get_scale(),
			"rotation_deg": xform.basis.get_euler() * (180.0 / PI),
			"rotation_quaternion": xform.basis.orthonormalized().get_rotation_quaternion(),
		}
	return result


static func measure_bone_lengths(joints: Dictionary, references: Dictionary) -> Dictionary:
	var upper_reference := float(references.get("upper", 0.0))
	var lower_reference := float(references.get("lower", 0.0))
	var upper := 0.0
	var lower := 0.0
	if joints.has("hip") and joints.has("knee") and joints.has("foot"):
		var hip := joints["hip"] as Dictionary
		var knee := joints["knee"] as Dictionary
		var foot := joints["foot"] as Dictionary
		upper = (hip["position"] as Vector3).distance_to(knee["position"] as Vector3)
		lower = (knee["position"] as Vector3).distance_to(foot["position"] as Vector3)
	return {
		"upper": upper, "upper_reference": upper_reference,
		"upper_ratio": upper / upper_reference if upper_reference > 0.0 else 0.0,
		"lower": lower, "lower_reference": lower_reference,
		"lower_ratio": lower / lower_reference if lower_reference > 0.0 else 0.0,
	}


## Captures the connected center/arm chains around the already detailed leg
## trace. PlayerLookPoseModifier caches this same complete chain so no sample
## mixes a final modified child with a Skeleton3D-restored parent. Root-relative
## poses separate skeletal motion from travel; parent ratios expose stretch.
static func capture_body_chain(player_body: PlayerBody) -> Dictionary:
	var skeleton := player_body.skeleton
	if skeleton == null:
		return {}
	var result := {}
	var body_inverse := player_body.global_transform.affine_inverse()
	for role: StringName in BODY_CHAIN_ROLES:
		var bone_idx := skeleton.find_bone(player_body.resolve_bone_name(role))
		if bone_idx < 0:
			continue
		var visual_pose := player_body.get_visual_bone_global_pose(bone_idx)
		var world_pose := player_body.global_transform * visual_pose
		var relative_basis := (body_inverse.basis * world_pose.basis).orthonormalized()
		var parent_idx := skeleton.get_bone_parent(bone_idx)
		var parent_length := 0.0
		var parent_rest_length := 0.0
		var parent_name := StringName()
		if parent_idx >= 0:
			parent_name = skeleton.get_bone_name(parent_idx)
			var parent_pose := player_body.get_visual_bone_global_pose(parent_idx)
			parent_length = visual_pose.origin.distance_to(parent_pose.origin)
			parent_rest_length = skeleton.get_bone_global_rest(bone_idx).origin.distance_to(
					skeleton.get_bone_global_rest(parent_idx).origin)
		result[String(role)] = {
			"position": world_pose.origin,
			"root_relative_position": body_inverse * world_pose.origin,
			"scale": world_pose.basis.get_scale(),
			"rotation_deg": world_pose.basis.get_euler() * (180.0 / PI),
			"rotation_quaternion": world_pose.basis.orthonormalized().get_rotation_quaternion(),
			"root_relative_rotation_deg": relative_basis.get_euler() * (180.0 / PI),
			"root_relative_rotation_quaternion": relative_basis.get_rotation_quaternion(),
			"parent_bone": parent_name,
			"parent_length": parent_length,
			"parent_rest_length": parent_rest_length,
			"parent_length_ratio": (
					parent_length / parent_rest_length if parent_rest_length > 0.0 else 0.0),
		}
	return result


static func build_foot_trace(ik: Node, side: String,
		actual_pos: Vector3, target: Vector3, normal: Vector3, sole_depth: float,
		sole_dir: Vector3, toe_pos_y: float, hip_pos: Vector3,
		solved_foot_angle: float, solved_foot_pos: Vector3, diff_rot: float,
		joints: Dictionary, leg_angles: Dictionary) -> Dictionary:
	var sole: Vector3 = actual_pos + sole_dir * sole_depth
	var contact_hit := bool(ik.debug_contact_hit.get(side, false))
	var owner := _target_owner(ik, side)
	var action := _solver_action(ik, side, contact_hit, owner)
	var plan: FootIKTargetPlan = ik._target_coordinator.get_plan(StringName(side))
	return {
		"gap": actual_pos.y - target.y - sole_depth,
		"sole_clearance": sole.y - target.y,
		"pitch_deg": rad_to_deg(sole.normalized().angle_to(Vector3.DOWN)),
		"solved_foot_angle_deg": solved_foot_angle,
		"solved_foot_pos": solved_foot_pos,
		"solve_target": ik._leg_solver.debug_solve_target.get(side, target),
		"diff_rot_deg": diff_rot,
		"diff_pos_m": actual_pos.distance_to(solved_foot_pos),
		"ground_weight": float(ik._smoothed_ground_weight.get(side, 0.0)),
		"raw_weight": float(ik.debug_raw_weight.get(side, 0.0)),
		"weight_stuck_time": float(ik._weight_stuck_time.get(side, 0.0)),
		"vertical_velocity": float(ik.debug_vertical_velocity.get(side, 0.0)),
		"contact_hit": contact_hit,
		"contact_dist": float(ik.debug_contact_distance.get(side, -1.0)),
		"contact_lost": bool(ik.debug_contact_lost.get(side, false)),
		"frozen": bool(ik._idle_frozen.get(side, false)),
		"locomotion_stance": ik._gait_tracker.is_locomotion_stance_active(side),
		"locomotion_locked": ik._gait_tracker.is_locomotion_target_locked(side),
		"freeze_streak": int(ik._idle_freeze_streak.get(side, 0)),
		"step_down": bool(ik.debug_step_down.get(side, false)),
		"toe_tip_y": toe_pos_y,
		"foot_pos": actual_pos,
		"smoothed_target": target,
		"raw_target": ik._ground_sampler.debug_raw_target.get(side, target),
		"hip_pos": hip_pos,
		"bone_lengths": measure_bone_lengths(joints, ik._leg_lengths.get(side, {})),
		"floor_angle_deg": rad_to_deg(normal.angle_to(Vector3.UP)),
		"leg_angles_deg": leg_angles,
		"target_owner": owner,
		"target_generation": plan.generation if plan != null else -1,
		"target_plan_valid": plan.valid if plan != null else false,
		"target_plan_reason": plan.reason if plan != null else "legacy_unplanned",
		"solver_action": action,
		"decision": "%s foot: support=%s target_y=%.3f owner=%s action=%s" % [
				side, "hit" if contact_hit else "miss", target.y, owner, action],
		"signed_knee_flexion_deg": float(
				ik._leg_solver.debug_signed_knee_flexion.get(side, 0.0)),
		"negative_knee_clamped": bool(
				ik._leg_solver.debug_negative_knee_clamped.get(side, false)),
		"knee_direction_constrained": bool(
				ik._leg_solver.debug_knee_direction_constrained.get(side, false)),
		"knee_pole_alignment": float(
				ik._leg_solver.debug_knee_pole_alignment.get(side, 1.0)),
		"joints": joints,
	}


static func _target_owner(ik: Node, side: String) -> String:
	var plan: FootIKTargetPlan = ik._target_coordinator.get_plan(StringName(side))
	if plan != null:
		return plan.owner_name()
	if ik._ground_sampler.landing_committed_target.has(side):
		return "landing_commitment"
	if ik._ground_sampler.idle_lower_acquiring.has(side):
		return "idle_lower_acquiring"
	if ik._ground_sampler.idle_lower_latched_target.has(side):
		return "idle_lower_latched"
	if ik._ground_sampler.idle_stance_rehoming.has(side):
		return "idle_stance_rehome"
	if ik._idle_frozen.get(side, false):
		return "idle_freeze"
	if ik._forced_support_side == StringName(side):
		return "stair_support"
	if ik.predicted_step_targets.has(StringName(side)):
		return "stair_swing_prediction"
	if ik._gait_tracker.is_locomotion_target_locked(side):
		return "locomotion_lock"
	if ik._gait_tracker.is_locomotion_stance_active(side):
		return "locomotion_stance"
	return "live_contact"


static func build_stair_ik_state(ik: Node) -> Dictionary:
	return {
		"step_prediction_enabled": ik.step_prediction_enabled,
		"support_side": String(ik._forced_support_side),
		"root_vertical_speed": (
				ik._stair_predictor.get_root_vertical_speed()
				if ik._stair_predictor != null else 0.0),
		"step_lifts": ik._smoothed_step_lift,
		"predicted_targets": ik.predicted_step_targets,
		"landing_commitment_sides": ik._ground_sampler.landing_committed_target.keys(),
		"idle_lower_acquiring_sides": ik._ground_sampler.idle_lower_acquiring.keys(),
	}


static func _solver_action(ik: Node, side: String, contact_hit: bool, owner: String) -> String:
	if not ik.active:
		return "animation_only"
	var plan: FootIKTargetPlan = ik._target_coordinator.get_plan(StringName(side))
	if plan != null and plan.reason == "replace_invalid_with_raw_support":
		return "select_supported_stance_target"
	if plan != null and not plan.valid:
		return "reject_invalid_target"
	if bool(ik._leg_solver.debug_negative_knee_clamped.get(side, false)):
		return "clamp_negative_knee"
	if bool(ik._leg_solver.debug_knee_direction_constrained.get(side, false)):
		return "constrain_knee_direction"
	if not contact_hit and float(ik._smoothed_ground_weight.get(side, 0.0)) <= 0.001:
		return "release_unsupported"
	if owner == "idle_lower_acquiring":
		return "move_to_lower_support"
	if owner == "idle_stance_rehome":
		return "move_to_stance_zone"
	if owner == "landing_commitment":
		return "hold_committed_landing_support"
	if bool(ik._leg_solver.debug_stance_limited.get(side, false)):
		return "limit_stance_crossing"
	return "solve_to_support"


static func build_decision_summary(feet: Dictionary) -> String:
	return "%s; %s" % [feet["left"]["decision"], feet["right"]["decision"]]


static func build_safe_zone_decision(ik: PlayerFootIKModifier, player: Player) -> String:
	var sampler := ik._ground_sampler
	var action := "none"
	var surface_y: float = sampler.split_safe_surface_y
	var root_distance := -1.0
	if sampler.airborne_safe_root_target.is_finite():
		surface_y = sampler.airborne_committed_surface_y
		var delta: Vector3 = sampler.airborne_safe_root_target - player.global_position
		delta.y = 0.0
		root_distance = delta.length()
		action = "%s_%s" % ["landing" if player.is_on_floor() else "airborne",
				sampler.airborne_landing_decision]
	elif sampler.airborne_landing_decision.begins_with("reject_grounded_height"):
		action = sampler.airborne_landing_decision
	elif sampler.split_safe_root_target.is_finite():
		var delta: Vector3 = sampler.split_safe_root_target - player.global_position
		delta.y = 0.0
		root_distance = delta.length()
		action = "descend_to_lower" if surface_y < player.global_position.y - player.safe_margin \
				else "move_to_upper"
	elif sampler.feet_have_common_current_support():
		action = "keep_common_support"
	var left_distance := float(ik.debug_contact_distance.get(&"left", -1.0))
	var right_distance := float(ik.debug_contact_distance.get(&"right", -1.0))
	return ("safe_zone action=%s surface_y=%.3f root_distance=%.3f "
			+ "contact_distance=%.3f/%.3f") % [
			action, surface_y, root_distance, left_distance, right_distance]
