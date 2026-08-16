extends RefCounted
## Minimal "residual correction" alternative to the full stair predictor/gait
## tracker pipeline (see docs/foot_ik_industry_review.md). Modeled on real
## shipped/working systems (Unity's Final IK, source read directly; a real
## Godot 4.6 addon, github.com/blugart-dev/kickback, source read directly):
## raycast each foot, blend correction weight from foot height above the
## CHARACTER ROOT (not velocity, not absolute world height - see
## residual_swing_threshold's doc comment), and use ONE simple pelvis sink
## (the worst-case leg overreach, one symmetric lerp rate) instead of
## reach-limit trig, asymmetric rates, or predictive swing lift. Deliberately
## has no idle-freeze, no predicted next tread, no support-leg transfer -
## this mode exists to test whether that machinery is actually needed.

var _owner
var _smoothed_pelvis_offset := 0.0
var _smoothed_weight: Dictionary = {} # side -> float
var _pelvis_base_pose := Transform3D()
var _pelvis_base_pose_frame := -1


func _init(owner) -> void:
	_owner = owner


func process(skel: Skeleton3D, space: PhysicsDirectSpaceState3D, delta: float) -> void:
	var to_world := skel.global_transform
	var current_frame := Engine.get_physics_frames()
	if _owner._leg_fresh_pose_cache_frame != current_frame:
		_owner._leg_fresh_pose_cache.clear()
		_owner._leg_fresh_pose_cache_frame = current_frame
	var root_y := (_owner.player_body.get_parent() as Node3D).global_position.y
	var per_leg: Dictionary = {}
	var worst_overreach := 0.0
	for side: StringName in _owner._bone_indices:
		var leg := _sample_leg(skel, to_world, space, side, root_y, delta)
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


func _sample_leg(skel: Skeleton3D, to_world: Transform3D, space: PhysicsDirectSpaceState3D,
		side: StringName, root_y: float, delta: float) -> Dictionary:
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
	var foot_pos: Vector3 = to_world * (fresh["foot"] as Transform3D).origin
	# Root-relative height, not absolute or velocity-based - see
	# residual_swing_threshold's doc comment on player_foot_ik_modifier.gd.
	var far: float = foot_pos.y - root_y
	var raw_weight := 0.0
	if far < _owner.residual_swing_threshold:
		raw_weight = clampf(1.0 - (far - _owner.residual_plant_threshold)
				/ (_owner.residual_swing_threshold - _owner.residual_plant_threshold), 0.0, 1.0)
	var hit: Dictionary = _owner._ground_sampler.raycast_ground(space, foot_pos)
	# Shared debug/introspection fields LEGACY writes every frame - this mode
	# must too, or external tooling (the live JSONL trace, the debug panel)
	# reads stale LEGACY leftovers and misdiagnoses this mode entirely (found
	# live: "contact_hit false" the whole session was last-mode leftover, not
	# what this corrector actually saw).
	_owner.debug_contact_hit[side] = hit["hit"]
	_owner.debug_raw_weight[side] = raw_weight
	_owner.debug_step_down[side] = false
	if not hit["hit"] and raw_weight > 0.0:
		# The short probe can miss a real tread the foot is standing on (e.g.
		# idle sway/turning drift). Only retry deep when this leg already
		# reads as planted, not mid-swing - a genuinely swinging foot missing
		# the short probe should stay uncorrected, not snap to a distant floor.
		hit = _owner._ground_sampler.raycast_ground(space, foot_pos, _owner.idle_settle_search_down)
		_owner.debug_contact_hit[side] = hit["hit"]
	var raw_target := foot_pos
	var normal := Vector3.UP
	var max_reach: float = upper_length + lower_length - 0.001
	if hit["hit"]:
		normal = hit["normal"]
		raw_target = (hit["position"] as Vector3) + normal * float(_owner.ankle_offset)
	# Only a GENUINELY unreachable target (a real void, several meters down)
	# should give up and fall back to raw animation - a hard cutoff at the
	# exact reach boundary is fragile against ordinary noise (this rig's own
	# authored idle stance already sits close to full extension, so a tiny
	# per-frame wobble tripped this every frame and got permanently stuck at
	# weight 0 - the same "don't gate on a noisy boundary value" mistake
	# already documented elsewhere in this project). The leg solver already
	# clamps and copes fine with ordinary minor overreach on its own.
	var unreachable_margin := max_reach + 0.08
	if not hit["hit"] or hip_pos.distance_to(raw_target) > unreachable_margin:
		raw_target = foot_pos
		raw_weight = 0.0
	var weight: float = move_toward(
			float(_smoothed_weight.get(side, raw_weight)), raw_weight,
			_owner.residual_foot_blend_speed * delta)
	_smoothed_weight[side] = weight
	var target := foot_pos.lerp(raw_target, weight)
	# solve() reads _smoothed_normal directly; the other two are read-only for
	# external tooling (trace/debug panel), not consumed by this mode itself.
	_owner._smoothed_normal[side] = normal
	_owner._smoothed_target[side] = raw_target
	_owner._smoothed_ground_weight[side] = weight
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
	# SkeletonModifier3D runs this twice per physics tick (once real, once a
	# phantom delta=0 - see AGENTS.md). Reading the skeleton's CURRENT pelvis
	# pose every call sinks it twice per tick, compounding forever - cache the
	# true pre-sink baseline once per physics frame instead, same fix already
	# used for this exact bug in player_foot_ik_modifier.gd.
	var current_frame := Engine.get_physics_frames()
	if _pelvis_base_pose_frame != current_frame:
		_pelvis_base_pose = skel.get_bone_global_pose(pelvis_idx)
		_pelvis_base_pose_frame = current_frame
	if _smoothed_pelvis_offset <= 0.0:
		return
	var pelvis_world := to_world * _pelvis_base_pose
	pelvis_world.origin -= Vector3.UP * _smoothed_pelvis_offset
	skel.set_bone_global_pose(pelvis_idx, to_world.affine_inverse() * pelvis_world)
