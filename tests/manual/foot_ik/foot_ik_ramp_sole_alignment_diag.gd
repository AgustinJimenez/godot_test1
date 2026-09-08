extends "res://tests/manual/foot_ik/foot_ik_ramp_matrix_check.gd"
## Diagnostic only: no bone writes, no pose changes, no pass/fail contract.
## Isolates the six genuinely deep 15-degree uphill clips (top_* x uphill/uphill_cross,
## 22-88mm, ~500 ball/foot vertices) and reports whether the rendered sole actually
## conforms to the ramp plane, or stays under-rotated so the front of the foot buries.
## Every other reported ramp "failure" is a <=1um tolerance graze; see 012.

const DEEP_POSITIONS: Array[String] = ["top_left", "top_center", "top_right"]
const DEEP_FACINGS: Array[String] = ["uphill", "uphill_cross", "cross_left"]


func _filter_requested_case() -> void:
	super._filter_requested_case()
	var selected: Array[Dictionary] = []
	for data: Dictionary in _cases:
		if (float(data["angle"]) in [15.0, 30.0]
				and String(data["position_name"]) in DEEP_POSITIONS
				and String(data["yaw_name"]) in DEEP_FACINGS):
			selected.append(data)
	_cases = selected


func _sample_current_case() -> void:
	super._sample_current_case()
	var case: Dictionary = _cases[_case_index]
	var ramp := case["ramp"] as CSGBox3D
	var surface_normal: Vector3 = ramp.global_transform.basis.y.normalized()
	var inverse := ramp.global_transform.affine_inverse()
	var half_thickness: float = ramp.size.y * 0.5
	var to_world: Transform3D = _player.skeleton.global_transform
	var report := "[SOLE] %s/%s frame=%d" % [
			case["position_name"], case["yaw_name"], _case_frame]
	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = _ik._bone_indices[side]
		var foot_pose: Transform3D = _ik._final_bone_poses.get(indices["foot"], Transform3D())
		var sole_down: Vector3 = _ik._sole_down_local.get(side, Vector3.DOWN)
		var sole_normal: Vector3 = -((to_world.basis * foot_pose.basis) * sole_down).normalized()
		var ik_normal: Vector3 = _ik._smoothed_normal.get(side, Vector3.UP)
		var heights := PackedStringArray()
		for joint: StringName in [&"hip", &"knee", &"foot", &"toe", &"leaf"]:
			var index: int = indices[joint]
			if index < 0:
				continue
			var pose: Transform3D = _ik._final_bone_poses.get(index, Transform3D())
			heights.append("%s=%+.3f" % [joint, (inverse * (to_world * pose.origin)).y - half_thickness])
		report += " | %s sole_vs_surface=%5.1fdeg sampled_normal_err=%5.1fdeg" % [
				side, rad_to_deg(sole_normal.angle_to(surface_normal)),
				rad_to_deg(ik_normal.angle_to(surface_normal))]
		report += " normal=(%+.2f,%+.2f,%+.2f) dot_up=%+.3f" % [
				ik_normal.x, ik_normal.y, ik_normal.z, ik_normal.dot(Vector3.UP)]
		# Is this foot even over the slab, or hanging past its end into empty space?
		var foot_local := inverse * (to_world * foot_pose.origin)
		report += " footprint_z=%+.3f/%.3f x=%+.3f/%.3f over_slab=%s" % [
				foot_local.z, ramp.size.z * 0.5, foot_local.x, ramp.size.x * 0.5,
				absf(foot_local.z) <= ramp.size.z * 0.5 and absf(foot_local.x) <= ramp.size.x * 0.5]
		report += " weight=%.2f hit=%s dist=%+.3f %s" % [
				float(_ik.debug_raw_weight.get(side, -1.0)),
				bool(_ik.debug_contact_hit.get(side, false)),
				float(_ik.debug_contact_distance.get(side, -1.0)),
				" ".join(heights)]
	print(report)


func _start_next_case() -> void:
	if _case_index + 1 < _cases.size():
		super._start_next_case()
		return
	print("FOOT_IK_RAMP_SOLE_ALIGNMENT_DIAG DONE cases=%d" % _cases.size())
	get_tree().quit(0)
