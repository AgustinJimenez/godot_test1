class_name FootIKGroundSampler
extends RefCounted
## Samples and smooths the world-space surface beneath each animated foot.
## Gait ownership, pelvis policy, and skeleton writes remain with their
## dedicated collaborators; this helper only reports contact geometry.

# Ordinary world collision plus authored contact-only surfaces. A character
# capsule can travel on a simplified ramp while the feet still sample the
# visible stair treads instead of that locomotion proxy.
const WORLD_COLLISION_MASK := 1
const CONTACT_SURFACE_COLLISION_MASK := 1 << 5
const GROUND_COLLISION_MASK := WORLD_COLLISION_MASK | CONTACT_SURFACE_COLLISION_MASK
const TARGET_NOISE_DEADBAND := 0.01
const PLANT_LOCK_WEIGHT := 0.95
## A genuine stair tread is horizontal (matches the modifier's flat_contact
## and the stair predictor's STAIR_TREAD_UP_DOT). A sloped ramp fails this, so
## the pure-rotation climb guard below never fires on a ramp.
const STAIR_TREAD_UP_DOT := 0.999

var smoothed_target: Dictionary = {} # side -> Vector3 (world)
var smoothed_normal: Dictionary = {} # side -> Vector3 (world)
var debug_raw_target: Dictionary = {} # side -> Vector3 (world)
var debug_effective_offset: Dictionary = {} # side -> float

var _owner


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	smoothed_target.clear()
	smoothed_normal.clear()
	debug_raw_target.clear()
	debug_effective_offset.clear()


func sample(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		side: StringName, foot_pose: Transform3D, foot_pos: Vector3,
		to_world: Transform3D, delta: float, likely_idle: bool = false,
		frozen: bool = false) -> Dictionary:
	var hit := raycast_ground(space, foot_pos)
	if not hit["hit"] and likely_idle and _owner.step_prediction_enabled:
		# A steep ramp can pass above a downhill-facing animated foot. Lift the
		# idle recovery probe by the allowed pelvis range as well as searching
		# deeper; the ordinary short probe still protects moving swing timing.
		var recovery_origin: Vector3 = foot_pos + Vector3.UP * float(
				_owner.step_down_max_crouch)
		hit = raycast_ground(space, recovery_origin,
				_owner.idle_settle_search_down + _owner.step_down_max_crouch)
	var raw_target: Vector3 = hit["position"] if hit["hit"] else foot_pos
	var raw_normal: Vector3 = hit["normal"] if hit["hit"] else Vector3.UP
	if _owner.step_prediction_enabled:
		var toe_probe := animated_lowest_surface_point_world(skel, side, foot_pose, foot_pos, to_world)
		var toe_hit := raycast_ground(space, toe_probe)
		if toe_hit["hit"] and (toe_hit["position"] as Vector3).y > raw_target.y + _owner.step_min_rise:
			raw_target = toe_hit["position"]
			raw_normal = toe_hit["normal"]
	debug_raw_target[side] = raw_target
	if not smoothed_target.has(side):
		smoothed_target[side] = raw_target
		smoothed_normal[side] = raw_normal
	elif hit["hit"] and raw_normal.dot(Vector3.UP) < 0.999:
		# A void-dangle temporarily stores the animated foot as the target. On
		# contact recovery, lerping that off-surface point toward a ramp moves
		# the requested plant through empty space or through the slope. Project
		# it back onto the current slope plane before any tangent smoothing.
		var current: Vector3 = smoothed_target[side]
		current -= raw_normal * (current - raw_target).dot(raw_normal)
		smoothed_target[side] = current
	var target_lock_allowed: bool = _owner._gait_tracker.target_lock_allows_latch(side)
	var body_turning: bool = _owner._gait_tracker.is_body_turning(side)
	if hit["hit"] and likely_idle and raw_normal.dot(Vector3.UP) < 0.999:
		smoothed_normal[side] = raw_normal
		if body_turning:
			# A gradual turn supplies the visual smoothing; an old world target
			# trails around a steep ramp until the leg cannot reach it.
			smoothed_target[side] = raw_target
	var likely_planted: bool = ((
			float(_owner._smoothed_ground_weight.get(side, 0.0)) >= PLANT_LOCK_WEIGHT
			or _owner._gait_tracker.is_locomotion_stance_active(side))
			and _owner._landing_grace_time <= 0.0
			and _owner.player_body.anim_player.current_animation.get_file() != "unarmed_jump_land"
			and target_lock_allowed)
	if _owner._landing_grace_time > 0.0:
		# Weight already eases touchdown; target lag can trigger a reach/pelvis sink.
		smoothed_target[side] = raw_target
		smoothed_normal[side] = raw_normal
	elif not frozen and not likely_planted and raw_target.distance_to(
			smoothed_target[side] as Vector3) > TARGET_NOISE_DEADBAND:
		var amount := clampf(delta * _owner.smooth_rate, 0.0, 1.0)
		var current_target := smoothed_target[side] as Vector3
		# A planted foot rotating in place must never climb: the re-probe ray
		# fires from the animated foot, which swings over the stair edge while
		# the body turns, so it reads the NEXT tread up and drags the foot
		# through the stair (confirmed live: idle turn near the step edge
		# jumped the smoothed target a full 0.2m up and pulled the foot into
		# the tread). Climbing requires real body translation - a pure turn
		# only moves sideways/down. Flat-floor turning is unaffected (there
		# the re-probe returns the same height), and a sloped ramp fails the
		# flat-tread check so it still tracks normally. The weight gate keeps
		# the guard from firing during an initial settle, where a foot's
		# target is still legitimately chasing the surface it will land on
		# (weight ramps up only once contact is established); only a foot
		# already planted may be held against a stair climb.
		var follow_target := raw_target
		smoothed_target[side] = (move_target_smoothed(current_target, follow_target, delta)
				if not body_turning else current_target.move_toward(
				follow_target, _owner.target_max_speed * delta))
		smoothed_normal[side] = (smoothed_normal[side] as Vector3).lerp(
				raw_normal, amount).normalized()
	if not hit["hit"] and not frozen:
		return {"hit": false}
	var desired_down := -(smoothed_normal[side] as Vector3)
	var foot_basis: Basis = _owner._compute_new_foot_basis_world(
			skel, side, desired_down, foot_pose)
	var toe_offset: Vector3 = foot_basis * (
			_owner._toe_rest_offset.get(side, Vector3.ZERO) as Vector3)
	var tip_offset := toe_offset
	if not toe_offset.is_zero_approx():
		tip_offset += toe_offset.normalized() * _owner.toe_tip_margin
	var effective_offset := maxf(_owner.ankle_offset, maxf(
			tip_offset.dot(desired_down),
			_owner._sole_depth_below_foot.get(side, 0.0)))
	debug_effective_offset[side] = effective_offset
	var animated_lowest_point := foot_pos
	var surface_hit := {"hit": false}
	if _owner.step_prediction_enabled:
		animated_lowest_point = animated_lowest_surface_point_world(
				skel, side, foot_pose, foot_pos, to_world)
		surface_hit = raycast_ground(space, animated_lowest_point)
		if likely_idle and raw_normal.dot(Vector3.UP) < 0.999 and not surface_hit["hit"]:
			# A downhill-facing idle sole can begin below a steep ramp plane;
			# reuse the valid ankle probe so the leg settles instead of releasing.
			surface_hit = hit
			animated_lowest_point = foot_pos
		if not surface_hit["hit"]:
			# A stationary foot may use the deep fallback without confusing
			# ordinary mid-swing timing.
			surface_hit = raycast_ground(
					space, animated_lowest_point, _owner.idle_settle_search_down)
	var contact_hit := bool(surface_hit["hit"])
	var contact_position: Vector3 = surface_hit["position"] if contact_hit else foot_pos
	return {
		"hit": true, "raw_target": raw_target, "raw_normal": raw_normal,
		"effective_offset": effective_offset,
		"ground_target": (smoothed_target[side] as Vector3)
				+ (smoothed_normal[side] as Vector3) * effective_offset,
		"raw_ground_target": raw_target + raw_normal * effective_offset,
		"animated_lowest_point": animated_lowest_point,
		"animated_contact_distance": maxf(
				0.0, animated_lowest_point.y - contact_position.y) if contact_hit else INF,
		"animated_contact_hit": contact_hit,
		"animated_contact_position": contact_position,
		"animated_contact_normal": surface_hit["normal"] if contact_hit else Vector3.UP,
	}


func move_target_smoothed(current: Vector3, raw_target: Vector3, delta: float) -> Vector3:
	var amount := clampf(delta * _owner.smooth_rate, 0.0, 1.0)
	var lerped := current.lerp(raw_target, amount)
	var max_dist: float = _owner.target_max_speed * delta
	if max_dist <= 0.0:
		return lerped
	var move := lerped - current
	if move.length() > max_dist:
		lerped = current + move.normalized() * max_dist
	return lerped


func animated_lowest_surface_point_world(
		skel: Skeleton3D, side: StringName, animated_foot_pose: Transform3D,
		foot_position: Vector3, to_world: Transform3D) -> Vector3:
	# Match the harness's rendered-contact estimate by comparing the sole
	# below the ankle with the extrapolated toe tip.
	var sole_down_world := (
			to_world.basis * animated_foot_pose.basis
			* (_owner._sole_down_local[side] as Vector3)
	).normalized()
	var sole_point: Vector3 = foot_position + sole_down_world * _owner.ankle_offset
	var toe_idx: int = (_owner._bone_indices[side] as Dictionary).get("toe", -1)
	if toe_idx < 0:
		return sole_point
	var toe_position: Vector3 = to_world * skel.get_bone_global_pose(toe_idx).origin
	var foot_to_toe := toe_position - foot_position
	var toe_tip := toe_position
	if not foot_to_toe.is_zero_approx():
		toe_tip += foot_to_toe.normalized() * _owner.toe_tip_margin
	return toe_tip if toe_tip.y < sole_point.y else sole_point


func raycast_ground(space: PhysicsDirectSpaceState3D, foot_pos: Vector3,
		down: float = -1.0) -> Dictionary:
	var from: Vector3 = foot_pos + Vector3.UP * float(_owner.ray_up)
	var to: Vector3 = foot_pos + Vector3.DOWN * (
			down if down > 0.0 else _owner.ray_down)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GROUND_COLLISION_MASK
	query.collide_with_areas = false
	if (is_instance_valid(_owner.player_body)
			and _owner.player_body.get_parent() is CollisionObject3D):
		query.exclude = [
			(_owner.player_body.get_parent() as CollisionObject3D).get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {"hit": false, "position": foot_pos, "normal": Vector3.UP}
	return {"hit": true, "position": result["position"], "normal": result["normal"]}


func has_support_patch(space: PhysicsDirectSpaceState3D, surface: Vector3, radius: float) -> bool:
	for offset: Vector3 in [Vector3(radius, 0.0, 0.0), Vector3(-radius, 0.0, 0.0),
			Vector3(0.0, 0.0, radius), Vector3(0.0, 0.0, -radius)]:
		var hit := raycast_ground(space, surface + offset + Vector3.UP * 0.2, 0.4)
		if (not hit["hit"] or (hit["normal"] as Vector3).dot(Vector3.UP) < STAIR_TREAD_UP_DOT
				or absf((hit["position"] as Vector3).y - surface.y) > 0.03):
			return false
	return true
