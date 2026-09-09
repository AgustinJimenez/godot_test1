extends "res://tests/manual/foot_ik/foot_ik_ramp_matrix_check.gd"
## Replays the original settle/idle history. PASS means measurement agrees, NOT no clipping.

const EVALUATOR := preload("res://tools/foot_ik/foot_clearance_evaluator.gd")
const MESH_SAMPLES := preload("res://tests/manual/foot_ik/foot_ik_clearance_mesh_samples.gd")
const CACHED_SAMPLES := preload("res://tests/manual/foot_ik/foot_ik_clearance_cached_samples.gd")
var _capture := MESH_SAMPLES.new()
var _cached := CACHED_SAMPLES.new()
var _cached_player: Player
var _cached_usec := 0
var _build_usec := 0
var _point_error := 0.0
var _comparisons := 0
var _clipped_samples := 0
var _clear_samples := 0
var _mismatches := 0
var _max_depth_error := 0.0
var _worst_depth := 0.0
var _worst_region: StringName = &"none"
var _measurement_usec := 0
var _capture_usec := 0
var _max_points := 0
var _boundary_disagreements := 0


func _filter_requested_case() -> void:
	super._filter_requested_case()
	for argument in OS.get_cmdline_user_args():
		if argument.trim_prefix("--").begins_with("case="):
			return
	var selected: Array[Dictionary] = []
	for data: Dictionary in _cases:
		if data["position_name"] in [&"top_left", &"middle_center"]:
			selected.append(data)
	_cases = selected


func _sample_current_case() -> void:
	super._sample_current_case()
	var ramp := _cases[_case_index]["ramp"] as CSGBox3D
	var before := _ik._final_bone_poses.duplicate(true)
	var before_root := _player.global_transform
	var oracle := _case_check.sample_box_volume(
			_player, _ik, _foot_bones, ramp, RAMP_PENETRATION_TOLERANCE)
	var capture_start := Time.get_ticks_usec()
	var samples := _capture.capture(_player, _ik, _foot_bones)
	_capture_usec += Time.get_ticks_usec() - capture_start
	if _cached_player != _player:
		var build_start := Time.get_ticks_usec()
		if not _cached.rebuild(_player, _foot_bones):
			_mismatches += 1
		_cached_player = _player
		_build_usec += Time.get_ticks_usec() - build_start
	var cached_start := Time.get_ticks_usec()
	var cached := _cached.capture(_player, _ik, _foot_bones)
	_cached_usec += Time.get_ticks_usec() - cached_start
	var reference_points: PackedVector3Array = samples["points"]
	var cached_points: PackedVector3Array = cached["points"]
	var cache_matches: bool = (reference_points.size() == cached_points.size()
			and samples["regions"] == cached["regions"])
	if cache_matches:
		for index in reference_points.size():
			_point_error = maxf(_point_error, reference_points[index].distance_to(cached_points[index]))
		cache_matches = _point_error <= EVALUATOR.BOUNDARY_EPSILON_M
	_max_points = maxi(_max_points, (samples["points"] as PackedVector3Array).size())
	var start := Time.get_ticks_usec()
	var measured := EVALUATOR.evaluate_box(cached_points, ramp.global_transform,
			ramp.size, RAMP_PENETRATION_TOLERANCE)
	_measurement_usec += Time.get_ticks_usec() - start
	_comparisons += 1
	var mismatch: bool = (not cache_matches or not measured.available
			or not oracle.get("available", false)
			or before != _ik._final_bone_poses or before_root != _player.global_transform)
	if measured.available and oracle.get("available", false):
		var error := absf(measured.max_penetration_m - float(oracle["max_depth"]))
		_max_depth_error = maxf(_max_depth_error, error)
		mismatch = mismatch or error > EVALUATOR.BOUNDARY_EPSILON_M
		var count_difference := absi(measured.penetrating_points - int(oracle["vertices"]))
		if count_difference > 0:
			_boundary_disagreements += 1
		mismatch = mismatch or count_difference > measured.boundary_points
		mismatch = mismatch or not _points_agree(samples["points"], ramp, measured)
		# Do not let ambiguous boundary counts hide a missed material penetration.
		mismatch = mismatch or ((measured.max_penetration_m > 0.00001)
				!= (float(oracle["max_depth"]) > 0.00001))
		if int(oracle["vertices"]) > 0:
			_clipped_samples += 1
		else:
			_clear_samples += 1
		if measured.max_penetration_m > _worst_depth:
			_worst_depth = measured.max_penetration_m
			_worst_region = samples["regions"][measured.worst_point_index]
	if mismatch:
		_mismatches += 1
		if _mismatches <= 3:
			print("CLEARANCE_MISMATCH case=%d frame=%d reason=%s counts=%d/%d depths=%s/%s" % [
					_case_index, _case_frame, measured.reason, measured.penetrating_points,
					int(oracle.get("vertices", -1)), measured.max_penetration_m,
					oracle.get("max_depth", -1.0)])


func _points_agree(points: PackedVector3Array, ramp: CSGBox3D,
		measured: EVALUATOR.Result) -> bool:
	# Same finite-volume predicate as the existing oracle, independently evaluated
	# per vertex to ensure EVERY count disagreement is at a numerical boundary.
	var inverse := ramp.global_transform.affine_inverse()
	var half := ramp.size * 0.5
	for index in points.size():
		var local := inverse * points[index]
		var embedded := (absf(local.x) <= half.x and absf(local.z) <= half.z
				and local.y > -half.y and local.y < half.y - RAMP_PENETRATION_TOLERANCE)
		var expected := 0.0
		if embedded:
			expected = minf(half.y - local.y, minf(local.y + half.y,
					minf(half.x - absf(local.x), half.z - absf(local.z))))
		var actual: float = measured.point_depths_m[index]
		if absf(actual - expected) > EVALUATOR.BOUNDARY_EPSILON_M:
			return false
		if embedded != (actual > 0.0) and measured.point_boundary[index] == 0:
			return false
	return true


func _start_next_case() -> void:
	if _case_index + 1 < _cases.size():
		super._start_next_case()
		return
	var passed := (_comparisons > 0 and _clipped_samples > 0
			and _clear_samples > 0 and _mismatches == 0)
	print("FOOT_IK_CLEARANCE_REPLAY_CHECK %s comparisons=%d clipped=%d clear=%d " % [
			"PASS" if passed else "FAIL", _comparisons, _clipped_samples, _clear_samples]
			+ "mismatches=%d depth_error_m=%.8f worst_depth_m=%.6f region=%s evaluator_avg_us=%.1f" % [
					_mismatches, _max_depth_error, _worst_depth, _worst_region,
					float(_measurement_usec) / maxf(_comparisons, 1)]
			+ " boundary_count_disagreements=%d points=%d capture_avg_us=%.1f" % [
					_boundary_disagreements, _max_points,
					float(_capture_usec) / maxf(_comparisons, 1)]
			+ " cached_avg_us=%.1f build_us=%d point_error_m=%.8f" % [
					float(_cached_usec) / maxf(_comparisons, 1), _build_usec, _point_error])
	get_tree().quit(0 if passed else 1)
