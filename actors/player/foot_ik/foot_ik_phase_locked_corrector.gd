extends RefCounted
## "Sample once per footfall" alternative to RESIDUAL_STAIR's continuous
## per-frame reclassification (see docs/foot_ik_industry_review.md's Perlin
## patent research: real touchdown-only sampling, not every-frame raycast +
## threshold). Reuses foot_ik_gait_tracker.gd's already-tuned `landed` event
## (velocity + falling-streak hysteresis, proven in LEGACY) as the touchdown
## trigger instead of inventing a new phase/velocity classifier - no
## confirmed walk-cycle symmetry to build a phase table on anyway. On landed,
## the raycast already sampled this same frame is LOCKED and held fixed for
## a timed stance window, then eased out to raw animation - never
## re-raycast or re-classified while locked, which is what structurally
## avoids the boundary-flicker bugs RESIDUAL_STAIR hit tonight (a target
## recomputed every frame can flicker across a threshold; a target set once
## and held cannot). Pelvis: RESIDUAL_STAIR's own validated approach
## (worst-case overreach, one smoothed rate, no reach-limit trig).

var _owner
var _smoothed_pelvis_offset := 0.0
var _pelvis_base_pose := Transform3D()
var _pelvis_base_pose_frame := -1
var _locked_target: Dictionary = {} # side -> Vector3
var _locked_normal: Dictionary = {} # side -> Vector3
var _stance_time_left: Dictionary = {} # side -> float
var _weight: Dictionary = {} # side -> float


func _init(owner) -> void:
	_owner = owner


func process(skel: Skeleton3D, space: PhysicsDirectSpaceState3D, delta: float) -> void:
	var to_world := skel.global_transform
	var current_frame := Engine.get_physics_frames()
	if _owner._leg_fresh_pose_cache_frame != current_frame:
		_owner._leg_fresh_pose_cache.clear()
		_owner._leg_fresh_pose_cache_frame = current_frame
	var per_leg: Dictionary = {}
	var worst_overreach := 0.0
	for side: StringName in _owner._bone_indices:
		var leg := _sample_leg(skel, to_world, space, side, delta)
		per_leg[side] = leg
		worst_overreach = maxf(worst_overreach, leg["needed_drop"] as float)
	worst_overreach = maxf(0.0, worst_overreach)
	_smoothed_pelvis_offset = move_toward(
			_smoothed_pelvis_offset, worst_overreach, _owner.residual_pelvis_lerp_speed * delta)
	_sink_pelvis(skel, to_world)
	for side: StringName in per_leg:
		var leg: Dictionary = per_leg[side]
		var weight: float = leg["weight"]
		_owner._leg_solver.solve(skel, side,
				(leg["hip_pos"] as Vector3) - Vector3.UP * _smoothed_pelvis_offset,
				leg["target"], leg["upper"], leg["lower"], weight, weight, delta)
	for i in skel.get_bone_count():
		_owner._final_bone_poses[i] = skel.get_bone_global_pose(i)


func _sample_leg(skel: Skeleton3D, to_world: Transform3D,
		space: PhysicsDirectSpaceState3D, side: StringName, delta: float) -> Dictionary:
	var indices: Dictionary = _owner._bone_indices[side]
	var lengths: Dictionary = _owner._leg_lengths[side]
	var hip_idx: int = indices["hip"]
	var foot_idx: int = indices["foot"]
	var upper_length: float = lengths["upper"]
	var lower_length: float = lengths["lower"]
	if not _owner._leg_fresh_pose_cache.has(side):
		_owner._leg_fresh_pose_cache[side] = {
			"hip": skel.get_bone_global_pose(hip_idx),
			"knee": skel.get_bone_global_pose(indices["knee"]),
			"foot": skel.get_bone_global_pose(foot_idx),
			"toe": (skel.get_bone_global_pose(indices["toe"])
					if int(indices["toe"]) >= 0 else Transform3D()),
			"leaf": (skel.get_bone_global_pose(indices["leaf"])
					if int(indices["leaf"]) >= 0 else Transform3D()),
		}
	var fresh: Dictionary = _owner._leg_fresh_pose_cache[side]
	var hip_pos: Vector3 = to_world * (fresh["hip"] as Transform3D).origin
	var animated_foot_pos: Vector3 = (fresh["foot"] as Transform3D).origin # skeleton-local
	var foot_pos: Vector3 = to_world * animated_foot_pos
	var hit: Dictionary = _owner._ground_sampler.raycast_ground(space, foot_pos)
	_owner.debug_contact_hit[side] = hit["hit"]
	_owner.debug_step_down[side] = false
	var ground_target := foot_pos
	var normal := Vector3.UP
	var contact_distance := INF
	var max_reach: float = upper_length + lower_length - 0.001
	if hit["hit"]:
		normal = hit["normal"]
		ground_target = (hit["position"] as Vector3) + normal * float(_owner.ankle_offset)
		contact_distance = absf(foot_pos.y - (hit["position"] as Vector3).y)
	var gait: Dictionary = _owner._gait_tracker.update(side, animated_foot_pos, foot_pos,
			ground_target, hit["hit"], contact_distance, to_world, delta)
	var landed: bool = gait["landed"]
	if landed and hit["hit"] and hip_pos.distance_to(ground_target) <= max_reach + 0.08:
		# Same "don't gate a target right at the exact reach boundary" fix as
		# RESIDUAL_STAIR - a small margin, since the leg solver already
		# copes fine with ordinary minor overreach on its own.
		_locked_target[side] = ground_target
		_locked_normal[side] = normal
		_stance_time_left[side] = _owner.phase_locked_stance_time
		_weight[side] = 1.0
	elif float(_stance_time_left.get(side, 0.0)) > 0.0:
		_stance_time_left[side] = maxf(0.0, float(_stance_time_left[side]) - delta)
	else:
		var release_rate: float = 1.0 / maxf(_owner.phase_locked_release_time, 0.001)
		_weight[side] = move_toward(float(_weight.get(side, 0.0)), 0.0, release_rate * delta)
	var weight: float = float(_weight.get(side, 0.0))
	var target: Vector3 = _locked_target.get(side, foot_pos) if weight > 0.0 else foot_pos
	_owner._smoothed_normal[side] = _locked_normal.get(side, Vector3.UP)
	_owner._smoothed_target[side] = target
	_owner._smoothed_ground_weight[side] = weight
	_owner.debug_raw_weight[side] = weight
	var horizontal := Vector2(hip_pos.x - target.x, hip_pos.z - target.z).length()
	var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal * horizontal))
	var needed_drop: float = (hip_pos.y - target.y) - max_vertical_diff
	return {"hip_pos": hip_pos, "target": target, "upper": upper_length,
			"lower": lower_length, "needed_drop": needed_drop, "weight": weight}


func _sink_pelvis(skel: Skeleton3D, to_world: Transform3D) -> void:
	if _owner._bone_indices.is_empty():
		return
	var first_leg: Dictionary = _owner._bone_indices.values()[0]
	var pelvis_idx := skel.get_bone_parent(int(first_leg["hip"]))
	if pelvis_idx < 0:
		return
	var current_frame := Engine.get_physics_frames()
	if _pelvis_base_pose_frame != current_frame:
		_pelvis_base_pose = skel.get_bone_global_pose(pelvis_idx)
		_pelvis_base_pose_frame = current_frame
	if _smoothed_pelvis_offset <= 0.0:
		return
	var pelvis_world := to_world * _pelvis_base_pose
	pelvis_world.origin -= Vector3.UP * _smoothed_pelvis_offset
	skel.set_bone_global_pose(pelvis_idx, to_world.affine_inverse() * pelvis_world)
