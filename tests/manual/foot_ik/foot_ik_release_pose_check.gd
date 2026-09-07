extends Node
## Releasing legs must follow the coordinated pelvis before and after identity.


class Gait extends RefCounted:
	func is_body_translating() -> bool:
		return false


class Owner extends RefCounted:
	var _ground_sampler: Dictionary = {"_settings": FootIKRuntimeSettings.new()}
	var player_body: Dictionary = {"anim_player": {
		"current_animation": &"moves/unarmed_idle", "current_animation_position": 0.5}}
	var _gait_tracker := Gait.new()
	var _velocity_suppressed := false
	var _prev_leg_bone_poses: Dictionary = {}
	var _leg_fresh_pose_cache: Dictionary = {}
	var _bone_indices: Dictionary = {}
	var _smoothed_shared_drop := 0.0
	var _pelvis_lateral_shift := Vector3(0.03, 0.0, 0.04)
	var _smoothed_normal: Dictionary = {&"left": Vector3.UP}


func _ready() -> void:
	var owner_state := Owner.new()
	var skeleton := Skeleton3D.new()
	add_child(skeleton)
	skeleton.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(2.0, 3.0, 4.0))
	var indices: Dictionary = {}
	var poses: Dictionary = {}
	var names: Array[StringName] = [&"pelvis", &"hip", &"knee", &"foot", &"toe", &"leaf"]
	for index in names.size():
		skeleton.add_bone(names[index])
		if index > 0:
			skeleton.set_bone_parent(index, index - 1)
		skeleton.set_bone_pose_position(index, Vector3(0.0, -0.2, 0.0))
		indices[names[index]] = index
		poses[names[index]] = skeleton.get_bone_global_pose(index)
	owner_state._bone_indices[&"left"] = indices
	owner_state._leg_fresh_pose_cache[&"left"] = poses
	var solver := preload("res://actors/player/foot_ik/foot_ik_leg_solver.gd").new(owner_state)
	var failures: Array[String] = []
	for scenario in ["no_history", "last_correction", "zero_delta", "decaying", "refresh"]:
		solver.reset_runtime_state()
		if scenario == "last_correction":
			solver._previous_corrections["left:hip"] = Quaternion(Vector3.UP, 0.00005)
		if scenario in ["decaying", "refresh"]:
			solver._previous_corrections["left:hip"] = Quaternion(Vector3.UP, 0.1)
		# Recreate animation evaluation followed by the shared-pelvis output pass.
		for index in names.size():
			skeleton.set_bone_global_pose(index, poses[names[index]])
		var pelvis: Transform3D = poses[&"pelvis"]
		var local_shift := skeleton.global_basis.inverse() * owner_state._pelvis_lateral_shift
		pelvis.origin += local_shift
		skeleton.set_bone_global_pose(0, pelvis)
		var delta := 0.0 if scenario in ["zero_delta", "refresh"] else 0.016
		solver.release_to_animation(skeleton, &"left", delta)
		for joint: StringName in [&"hip", &"knee", &"foot", &"toe", &"leaf"]:
			var actual := skeleton.get_bone_global_pose(indices[joint])
			var expected: Transform3D = poses[joint]
			expected.origin += local_shift
			if not actual.origin.is_equal_approx(expected.origin):
				failures.append("%s:%s shifted %.6fm" % [
						scenario, joint, actual.origin.distance_to(expected.origin)])
		if scenario not in ["decaying", "refresh"] and not solver._previous_corrections.is_empty():
			failures.append("%s retained correction history" % scenario)
	print("FOOT_IK_RELEASE_POSE_CHECK %s failures=%s" % [
			"PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)
