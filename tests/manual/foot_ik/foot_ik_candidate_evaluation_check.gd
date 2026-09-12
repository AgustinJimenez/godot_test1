extends Node3D
## No live skeleton/history/debug mutations during evaluation, including release branches.
## Optional FOOT_IK_REFERENCE_SOLVER points at a pre-extraction script for local A/B evidence;
## normal acceptance runs require no historical script or external fixture.

const SOLVER := preload("res://actors/player/foot_ik/foot_ik_leg_solver.gd")
const JOINTS: Array[StringName] = [&"hip", &"knee", &"foot", &"toe", &"leaf"]


class Body extends Node3D:
	var anim_player: Dictionary = {
		"current_animation": &"moves/unarmed_idle", "current_animation_position": 0.5}


class Motion extends RefCounted:
	var active := false
	func is_body_translating() -> bool:
		return active
	func is_active() -> bool:
		return active


class Owner extends Node3D:
	var player_body := Body.new()
	var _ground_sampler := FootIKGroundSampler.new(self)
	var _gait_tracker := Motion.new()
	var _stair_predictor := Motion.new()
	var _velocity_suppressed := false
	var _animation_discontinuous := false
	var _prev_leg_bone_poses: Dictionary = {}
	var _leg_fresh_pose_cache: Dictionary = {}
	var _bone_indices: Dictionary = {}
	var _smoothed_shared_drop := 0.0
	var _pelvis_lateral_shift := Vector3.ZERO
	var _smoothed_normal: Dictionary = {}
	var _smoothed_target: Dictionary = {}
	var _knee_pole_local: Dictionary = {}
	var _toe_rest_offset: Dictionary = {}
	var _toe_rest_relative_basis: Dictionary = {}
	var _leaf_rest_offset: Dictionary = {}
	var _leaf_rest_relative_basis: Dictionary = {}
	var _landing_grace_time := 0.0
	var max_hip_swing_degrees := 100.0
	var max_knee_flexion_degrees := 150.0

	func _ready() -> void:
		add_child(player_body)

	func _compute_new_foot_basis_world(skel: Skeleton3D, _side: StringName,
			desired_down: Vector3, pose: Transform3D) -> Basis:
		return Basis(Quaternion(Vector3.DOWN, desired_down)) * skel.global_basis * pose.basis


var _owner_state: Owner
var _skeleton: Skeleton3D
var _reference_skeleton: Skeleton3D
var _solver: RefCounted
var _reference: RefCounted
var _frame := 0
var _samples := 0
var _failures: Array[String] = []


func _ready() -> void:
	_owner_state = Owner.new()
	add_child(_owner_state)
	_skeleton = _make_skeleton()
	_reference_skeleton = _make_skeleton()
	_solver = SOLVER.new(_owner_state)
	var reference_path := OS.get_environment("FOOT_IK_REFERENCE_SOLVER")
	var reference_script: Script = SOLVER if reference_path.is_empty() else load(reference_path)
	_reference = reference_script.new(_owner_state)


func _make_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	add_child(skeleton)
	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = {}
		for joint in JOINTS:
			var index := skeleton.get_bone_count()
			skeleton.add_bone("%s_%s" % [side, joint])
			if joint != &"hip":
				skeleton.set_bone_parent(index, index - 1)
			indices[joint] = index
		_owner_state._bone_indices[side] = indices
	return skeleton


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame > 120:
		_check_reset_invalidation()
		print("FOOT_IK_CANDIDATE_EVALUATION_CHECK %s samples=%d failures=%s" % [
				"PASS" if _failures.is_empty() else "FAIL", _samples, _failures])
		# The sampler/planner own each other in the runtime; break that fixture cycle on exit.
		_owner_state._ground_sampler._landing_planner = null
		get_tree().quit(0 if _failures.is_empty() else 1)
		return
	_prepare_frame()
	for side: StringName in [&"left", &"right"]:
		var poses: Dictionary = _owner_state._leg_fresh_pose_cache[side]
		var hip := _skeleton.global_transform * (poses[&"hip"] as Transform3D).origin
		var knee := _skeleton.global_transform * (poses[&"knee"] as Transform3D).origin
		var foot := _skeleton.global_transform * (poses[&"foot"] as Transform3D).origin
		var target := foot + Vector3(sin(_frame * 0.19) * 0.4,
				0.15 + cos(_frame * 0.13) * 0.15, cos(_frame * 0.23) * 0.3)
		var weight := float(_frame % 5) / 4.0
		if _frame % 11 == 0:
			target = foot # Exact animation pass-through / release.
			weight = 0.0
		elif _frame % 13 == 0:
			target = hip # Degenerate target release.
		var dt: float = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0][_frame % 3]
		for delta: float in [dt, 0.0, dt]:
			_check_candidate(side, hip, target, hip.distance_to(knee),
					knee.distance_to(foot), weight, delta)


func _prepare_frame() -> void:
	var clips := [&"moves/unarmed_idle", &"moves/walk", &"moves/unarmed_crouch",
			&"moves/jump_land"]
	_owner_state.player_body.anim_player.current_animation = clips[(_frame / 10) as int % 4]
	_owner_state.player_body.anim_player.current_animation_position = (
			0.0 if _frame % 9 == 0 else 0.5)
	_owner_state._animation_discontinuous = _frame % 9 == 0
	_owner_state._velocity_suppressed = _frame % 9 == 0
	_owner_state._landing_grace_time = 0.1 if _frame % 7 == 0 else 0.0
	_owner_state._smoothed_shared_drop = 0.1 if _frame % 3 == 0 else 0.0
	_owner_state._stair_predictor.active = _frame % 2 == 0
	_owner_state._pelvis_lateral_shift = Vector3(0.03, 0.0, 0.04)
	var world := Transform3D(Basis(Vector3.UP, _frame * 0.05), Vector3(2.0, 1.0, -3.0))
	_owner_state.transform = world
	_skeleton.transform = world
	_reference_skeleton.transform = world
	for side: StringName in [&"left", &"right"]:
		var x := 0.15 if side == &"left" else -0.15
		var points := [Vector3(x, 1.0, 0.0), Vector3(x, 0.52, -0.12),
				Vector3(x, 0.04, 0.0), Vector3(x, 0.04, -0.08), Vector3(x, 0.04, -0.18)]
		var poses: Dictionary = {}
		for joint_index in JOINTS.size():
			var joint := JOINTS[joint_index]
			var pose := Transform3D(Basis(Vector3.RIGHT, sin(_frame * 0.1) * 0.1),
					points[joint_index])
			poses[joint] = pose
			var index: int = _owner_state._bone_indices[side][joint]
			_skeleton.set_bone_global_pose(index, pose)
			_reference_skeleton.set_bone_global_pose(index, pose)
		if not _owner_state._leg_fresh_pose_cache.is_empty():
			_owner_state._prev_leg_bone_poses[side] = (
					_owner_state._leg_fresh_pose_cache.get(side, poses))
		_owner_state._leg_fresh_pose_cache[side] = poses
		_owner_state._knee_pole_local[side] = Vector3.FORWARD
		_owner_state._smoothed_normal[side] = (
				Vector3(0.0, 1.0, 0.4).normalized() if _frame % 4 == 0 else Vector3.UP)
		_owner_state._smoothed_target[side] = world * points[2]
		_owner_state._toe_rest_offset[side] = Vector3(0.0, 0.0, -0.08)
		_owner_state._leaf_rest_offset[side] = Vector3(0.0, 0.0, -0.18)
		_owner_state._toe_rest_relative_basis[side] = Basis.IDENTITY
		_owner_state._leaf_rest_relative_basis[side] = Basis.IDENTITY
		var sampler := _owner_state._ground_sampler
		sampler.idle_lower_acquiring.clear()
		if _frame % 6 == 0:
			sampler.idle_lower_acquiring[side] = true
		sampler.lower_riser_away[side] = Vector3.BACK
		sampler.lower_riser_away_surface_y[side] = (world * points[2]).y


func _check_candidate(side: StringName, hip: Vector3, target: Vector3,
		upper: float, lower: float, weight: float, delta: float) -> void:
	_samples += 1
	var before := FootIKLegSolveState.capture(_solver)
	var bones := _bone_poses(_skeleton)
	var input: FootIKLegSolveInput = _solver.capture_input(_skeleton, side)
	var options := {&"instant": _frame % 17 == 0, &"target_plan_validated": _frame % 2 == 0,
			&"stationary_slope": _frame % 4 == 0}
	var first: FootIKLegPoseResult = _solver.evaluate_candidate(
			input, hip, target, upper, lower, weight, weight, delta, options)
	# Reject another candidate; it must not influence a repeat of the first.
	_solver.evaluate_candidate(input, hip, hip + Vector3.LEFT,
			upper, lower, 1.0, 1.0, delta, options)
	_expect(_bone_poses(_skeleton) == bones, "evaluation changed bones")
	# Also change a live setting, pose cache, normal and skeleton after capture.
	var settings := _owner_state._ground_sampler._settings
	var old_alignment := settings.minimum_knee_pole_alignment
	var old_normal: Vector3 = _owner_state._smoothed_normal[side]
	var old_poses: Dictionary = _owner_state._leg_fresh_pose_cache[side].duplicate(true)
	settings.minimum_knee_pole_alignment = 0.99
	_owner_state._smoothed_normal[side] = Vector3.RIGHT
	_owner_state._leg_fresh_pose_cache[side][&"hip"] = Transform3D.IDENTITY
	_skeleton.set_bone_global_pose(0, Transform3D.IDENTITY)
	var repeat: FootIKLegPoseResult = _solver.evaluate_candidate(
			input, hip, target, upper, lower, weight, weight, delta, options)
	settings.minimum_knee_pole_alignment = old_alignment
	_owner_state._smoothed_normal[side] = old_normal
	_owner_state._leg_fresh_pose_cache[side] = old_poses
	for index in bones.size():
		_skeleton.set_bone_global_pose(index, bones[index])
	# Rebuilding locals from global transforms can round off; rejection must preserve the
	# exact freshly restored skeleton, not undo that harmless restore-time rounding.
	bones = _bone_poses(_skeleton)
	_expect(_same_result(first, repeat), "fixed snapshot evaluation changed")
	_expect(_same_state(before, _solver), "evaluation changed live history/diagnostics")
	_expect(_same_state(before, input.history), "evaluation mutated input history")
	_expect(not _solver.commit_candidate(_reference_skeleton, first),
			"candidate committed to a different skeleton")
	# A frame-stale result must also be rejected without side effects.
	var original_frame := repeat.physics_frame
	repeat.physics_frame -= 1
	_expect(not _solver.commit_candidate(_skeleton, repeat), "stale candidate committed")
	repeat.physics_frame = original_frame
	_expect(_bone_poses(_skeleton) == bones, "rejection changed bones")
	_expect(_same_state(before, _solver), "rejection changed history")
	_expect(_solver.commit_candidate(_skeleton, first), "fresh candidate rejected")
	var accepted_bones := _bone_poses(_skeleton)
	var accepted_state := FootIKLegSolveState.capture(_solver)
	_expect(not _solver.commit_candidate(_skeleton, first), "candidate committed twice")
	_expect(not _solver.commit_candidate(_skeleton, repeat), "superseded candidate committed")
	_expect(_bone_poses(_skeleton) == accepted_bones, "duplicate commit changed bones")
	_expect(_same_state(accepted_state, _solver), "duplicate commit changed history")
	_reference.solve(_reference_skeleton, side, hip, target, upper, lower,
			weight, weight, delta, options)
	for index in accepted_bones.size():
		_expect(accepted_bones[index].is_equal_approx(
				_reference_skeleton.get_bone_global_pose(index)), "pose differs from reference")
	_expect(_same_state(accepted_state, _reference), "history/debug differs from reference")


func _check_reset_invalidation() -> void:
	var input: FootIKLegSolveInput = _solver.capture_input(_skeleton, &"left")
	var result: FootIKLegPoseResult = _solver.evaluate_candidate(
			input, Vector3.UP, Vector3.ZERO, 0.5, 0.5, 1.0, 1.0, 0.016)
	_solver.reset_runtime_state()
	var state := FootIKLegSolveState.capture(_solver)
	var bones := _bone_poses(_skeleton)
	_expect(not _solver.commit_candidate(_skeleton, result), "pre-reset candidate committed")
	_expect(_same_state(state, _solver), "pre-reset candidate restored history")
	_expect(_bone_poses(_skeleton) == bones, "pre-reset candidate changed bones")


func _bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(index))
	return poses


func _same_state(first: Object, second: Object) -> bool:
	for field in FootIKLegSolveState.FIELDS:
		if first.get(field) != second.get(field):
			return false
	return true


func _same_result(first: FootIKLegPoseResult, second: FootIKLegPoseResult) -> bool:
	if first.has_pose != second.has_pose or not _same_state(first.next_state, second.next_state):
		return false
	for joint in JOINTS:
		for suffix in ["idx", "pos", "basis"]:
			if first.get("%s_%s" % [joint, suffix]) != second.get("%s_%s" % [joint, suffix]):
				return false
	return first.has_toe == second.has_toe and first.has_leaf == second.has_leaf


func _expect(passed: bool, reason: String) -> void:
	if not passed and _failures.size() < 20:
		_failures.append("frame=%d sample=%d %s" % [_frame, _samples, reason])
