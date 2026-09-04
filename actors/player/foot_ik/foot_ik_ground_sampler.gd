class_name FootIKGroundSampler
extends RefCounted
## Samples and smooths the world-space surface beneath each animated foot.
## Gait ownership, pelvis policy, and skeleton writes remain with collaborators.
const WORLD_COLLISION_MASK := 1
const LANDING_PLANNER := preload("res://actors/player/foot_ik/foot_ik_landing_planner.gd")
const RUNTIME_SETTINGS := preload("res://actors/player/foot_ik/foot_ik_runtime_settings.gd")
const CONTACT_SURFACE_COLLISION_MASK := 1 << 5
const GROUND_COLLISION_MASK := WORLD_COLLISION_MASK | CONTACT_SURFACE_COLLISION_MASK
const TARGET_NOISE_DEADBAND := 0.01
const PLANT_LOCK_WEIGHT := 0.95
const STANCE_ZONE_MIN_LATERAL := 0.06
const STANCE_ZONE_MAX_LATERAL := 0.56
const STANCE_ZONE_MAX_LONGITUDINAL := 0.40
const IDLE_STANCE_REHOME_LATERAL := 0.12
const LOWER_RISER_REHOME_STEP := 0.02
const LOWER_RISER_REHOME_STEPS := 24
const LANDING_UPPER_CONFIRM_FRAMES := 4
const LANDING_UPPER_CONTACT_DISTANCE := 0.06
const COMPRESSED_UPPER_SEARCH_SAMPLES := 36
const SPLIT_SAFE_SEARCH_STEP := 0.05
const SPLIT_SAFE_SEARCH_RINGS := 16
const LANDING_CONTACT_CLEARANCE_RADIUS := 0.02
const IDLE_FREEZE_MAX_TARGET_DRIFT := 0.08
const STAIR_TREAD_UP_DOT := 0.999
var smoothed_target: Dictionary = {} # side -> Vector3 (world)
var smoothed_normal: Dictionary = {} # side -> Vector3 (world)
var debug_raw_target: Dictionary = {} # side -> Vector3 (world)
var debug_effective_offset: Dictionary = {} # side -> float
var idle_lower_latched_target: Dictionary = {} # side -> Vector3 (world surface)
var landing_committed_target: Dictionary = {} # side -> Vector3 (world surface)
var idle_lower_acquiring: Dictionary = {} # side -> Vector3 (world surface)
var lower_riser_away: Dictionary = {} # side -> horizontal Vector3 (world)
var lower_riser_away_surface_y: Dictionary = {} # side -> lower surface height
var lower_riser_cleared_target: Dictionary = {} # side -> validated world surface
var landing_upper_confirmation_frames: Dictionary = {} # side -> int
var landing_upper_confirmed: Dictionary = {} # side -> Vector3 (world surface)
var compressed_upper_target: Dictionary = {} # side -> supported surface for straighter knee
var preferred_root_nudge := Vector3.ZERO # lets the capsule make room for a supported upper stance
var preferred_root_nudge_surface_y := -INF
var split_safe_root_target := Vector3(INF, INF, INF)
var split_safe_surface_y := -INF
var split_rejected_surface_y := -INF
var split_safe_held_upper_target: Dictionary = {} # side -> last proven upper support
var sample_previous_support: Dictionary = {} # side -> target before this frame's probe
var idle_stance_rehoming: Dictionary = {} # side -> corrected supported target
var airborne_safe_root_target: Vector3:
	get: return _landing_planner.safe_root_target
var airborne_committed_surface_y: float:
	get: return _landing_planner.committed_surface_y
var airborne_landing_decision: String:
	get: return _landing_planner.decision
var airborne_landing_probe_local: Dictionary = {} # stable grounded foot offsets for landing
var _owner
var _settings: FootIKRuntimeSettings
var _landing_planner
func _init(owner) -> void:
	_owner = owner
	_settings = RUNTIME_SETTINGS.new()
	_landing_planner = LANDING_PLANNER.new(self, owner, _settings)
func reset() -> void:
	smoothed_target.clear()
	smoothed_normal.clear()
	debug_raw_target.clear()
	debug_effective_offset.clear()
	idle_lower_latched_target.clear()
	landing_committed_target.clear()
	idle_lower_acquiring.clear()
	lower_riser_away.clear()
	lower_riser_away_surface_y.clear()
	lower_riser_cleared_target.clear()
	landing_upper_confirmation_frames.clear()
	landing_upper_confirmed.clear()
	compressed_upper_target.clear()
	preferred_root_nudge_surface_y = -INF
	split_safe_root_target = Vector3(INF, INF, INF)
	split_safe_surface_y = -INF
	split_rejected_surface_y = -INF
	split_safe_held_upper_target.clear()
	sample_previous_support.clear()
	idle_stance_rehoming.clear()
	_landing_planner.reset()
func landing_commitment_snapshot() -> Dictionary:
	if not airborne_safe_root_target.is_finite():
		return {}
	return {
		"root": airborne_safe_root_target,
		"surface_y": airborne_committed_surface_y,
		"decision": airborne_landing_decision,
	}
func restore_landing_commitment(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_landing_planner.safe_root_target = snapshot["root"]
	_landing_planner.committed_surface_y = snapshot["surface_y"]
	_landing_planner.decision = "landing_hold %s" % snapshot["decision"]
func reject_split_safe_root() -> void:
	split_rejected_surface_y = split_safe_surface_y
	split_safe_root_target = Vector3(INF, INF, INF)
	split_safe_surface_y = -INF
	split_safe_held_upper_target.clear()
	landing_upper_confirmed.clear()
	landing_upper_confirmation_frames.clear()
	for side: StringName in [&"left", &"right"]:
		idle_lower_latched_target.erase(side)
		idle_lower_acquiring.erase(side)
		_owner._gait_tracker.invalidate_idle_freeze(side)
		if debug_raw_target.has(side):
			smoothed_target[side] = debug_raw_target[side]
func feet_have_common_current_support() -> bool:
	for side: StringName in [&"left", &"right"]:
		if (not debug_raw_target.has(side)
				or not bool(_owner.debug_contact_hit.get(side, false))):
			return false
		var contact_distance := float(_owner.debug_contact_distance.get(side, -1.0))
		if contact_distance < 0.0 or contact_distance > _settings.max_split_ik_height:
			return false
	return absf((debug_raw_target[&"left"] as Vector3).y
			- (debug_raw_target[&"right"] as Vector3).y) \
			<= _settings.max_split_ik_height
func _clear_lower_riser_away(side: StringName) -> void:
	lower_riser_away.erase(side)
	lower_riser_away_surface_y.erase(side)
func is_compressed_target_settled(side: StringName) -> bool:
	return (compressed_upper_target.has(side) and smoothed_target.has(side)
			and (smoothed_target[side] as Vector3).distance_to(
					compressed_upper_target[side]) <= TARGET_NOISE_DEADBAND)
func straighten_compressed_upper_target(space: PhysicsDirectSpaceState3D,
		side: StringName, context: Dictionary) -> Vector3:
	var target: Vector3 = context["target"]
	var normal: Vector3 = context["normal"]
	var surface: Vector3 = context["surface"]
	var other_side: StringName = &"right" if side == &"left" else &"left"
	var other_surface: Vector3 = smoothed_target.get(other_side, surface)
	var animation_name: String = _owner.player_body.anim_player.current_animation.get_file()
	var lowest_hit: bool = context.get("lowest_hit", false)
	var lowest_surface: Vector3 = context.get("lowest_surface", surface)
	var character := _owner.player_body.get_parent() as Player
	var partial_upper_support := (lowest_hit and character != null
			and surface.y - lowest_surface.y > character.step_height)
	var recovering_split := split_safe_root_target.is_finite()
	if split_safe_held_upper_target.size() < 2:
		recovering_split = _request_overheight_split_safe_zone(
				space, surface, other_surface, animation_name)
	var enabled: bool = (_settings.upper_foot_reposition_enabled
			and animation_name.contains("idle")
			and not landing_committed_target.has(side)
			and surface.is_finite()
			and normal.dot(Vector3.UP) >= STAIR_TREAD_UP_DOT
			and (surface.y > other_surface.y + _owner.step_min_rise
					or partial_upper_support)
			and not recovering_split)
	if not enabled:
		compressed_upper_target.erase(side)
		return target
	var hip: Vector3 = context["hip"]
	var offset: float = context["offset"]
	var upper: float = context["upper"]
	var lower: float = context["lower"]
	var to_world: Transform3D = context["to_world"]
	var minimum_knee_angle := deg_to_rad(
			180.0 - _settings.preferred_upper_knee_flexion_degrees)
	var minimum_reach := sqrt(maxf(0.0, upper * upper + lower * lower
			- 2.0 * upper * lower * cos(minimum_knee_angle)))
	minimum_reach += 0.01 # small margin for the shared hip's later sub-frame movement
	var retained_knee_angle := deg_to_rad(
			180.0 - _settings.retained_upper_knee_flexion_degrees)
	var retained_minimum_reach := sqrt(maxf(0.0, upper * upper + lower * lower
			- 2.0 * upper * lower * cos(retained_knee_angle)))
	if partial_upper_support and not compressed_upper_target.has(side):
		var supported_target := _find_partial_upper_target(space, side, surface)
		if supported_target.is_finite():
			compressed_upper_target[side] = supported_target
	if compressed_upper_target.has(side):
		var cached_surface: Vector3 = compressed_upper_target[side]
		var cached_target := cached_surface + Vector3.UP * offset
		var cached_hit := raycast_ground(space, cached_surface + Vector3.UP * 0.2, 0.4)
		if (cached_hit["hit"] and is_target_inside_stance_zone(side, cached_surface)
				and absf((cached_hit["position"] as Vector3).y - cached_surface.y) <= 0.03
				and (not partial_upper_support or has_support_patch(
						space, cached_surface, _settings.upper_support_radius))
				and hip.distance_to(cached_target) >= retained_minimum_reach - 0.005
				and _owner._leg_solver._target_thigh_swing(
					side, hip, cached_target, upper, lower, to_world)
				<= deg_to_rad(_owner._leg_solver.max_hip_swing_degrees(side))):
			var current_surface: Vector3 = smoothed_target[side]
			var next_surface := current_surface.move_toward(cached_surface,
					_settings.upper_foot_acquire_speed * float(context["delta"]))
			smoothed_target[side] = next_surface
			return next_surface + Vector3.UP * offset
		compressed_upper_target.erase(side)
	if hip.distance_to(target) >= minimum_reach - 0.005:
		return target
	var horizontal := target - hip
	horizontal.y = 0.0
	var vertical_distance := absf(hip.y - target.y)
	var required_horizontal := sqrt(maxf(0.0,
			minimum_reach * minimum_reach - vertical_distance * vertical_distance))
	if horizontal.length_squared() <= 0.0001 or required_horizontal <= horizontal.length():
		return target
	var best_surface := Vector3.ZERO
	var best_distance := INF
	var blocked_distance := INF
	var blocked_nudge := Vector3.ZERO
	for sample_index in COMPRESSED_UPPER_SEARCH_SAMPLES:
		var angle := TAU * float(sample_index) / float(COMPRESSED_UPPER_SEARCH_SAMPLES)
		var candidate_target := hip + Vector3(cos(angle), 0.0, sin(angle)) * required_horizontal
		candidate_target.y = target.y
		if (_owner._leg_solver._target_thigh_swing(
				side, hip, candidate_target, upper, lower, to_world)
				> deg_to_rad(_owner._leg_solver.max_hip_swing_degrees(side))):
			continue
		var candidate_probe := candidate_target - Vector3.UP * offset + Vector3.UP * 0.2
		var candidate_hit := raycast_ground(space, candidate_probe, 0.4)
		if (not candidate_hit["hit"]
				or (candidate_hit["normal"] as Vector3).dot(Vector3.UP) < 0.999):
			continue
		var candidate_surface: Vector3 = candidate_hit["position"]
		if (absf(candidate_surface.y - (context["surface"] as Vector3).y) > 0.03
				or not is_target_inside_stance_zone(side, candidate_surface)):
			continue
		var distance := candidate_target.distance_to(target)
		var support_nudge := _support_patch_inward(
				space, candidate_surface, _settings.upper_support_radius)
		if not support_nudge.is_zero_approx():
			if distance < blocked_distance:
				blocked_distance = distance
				blocked_nudge = support_nudge
			continue
		if distance < best_distance:
			best_distance = distance
			best_surface = candidate_surface
	if not is_finite(best_distance):
		if not blocked_nudge.is_zero_approx():
			preferred_root_nudge += blocked_nudge.normalized()
		return target
	compressed_upper_target[side] = best_surface
	smoothed_normal[side] = Vector3.UP
	return target
func _find_partial_upper_target(space: PhysicsDirectSpaceState3D,
		side: StringName, surface: Vector3) -> Vector3:
	var candidate := surface
	for _step in 12:
		var inward := _support_patch_inward(
				space, candidate, _settings.upper_support_radius)
		if inward.is_zero_approx():
			return candidate if is_target_inside_stance_zone(side, candidate) \
					else Vector3(INF, INF, INF)
		candidate += inward.normalized() * 0.02
		var hit := raycast_ground(space, candidate + Vector3.UP * 0.2, 0.4)
		if (not hit["hit"] or absf((hit["position"] as Vector3).y - surface.y) > 0.03):
			continue
		candidate = hit["position"]
	return Vector3(INF, INF, INF)
func sample(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		side: StringName, foot_pose: Transform3D, foot_pos: Vector3,
		to_world: Transform3D, delta: float, likely_idle: bool = false,
		frozen: bool = false) -> Dictionary:
	if side == &"left":
		preferred_root_nudge = Vector3.ZERO
		preferred_root_nudge_surface_y = -INF
	var previous_support: Vector3 = smoothed_target.get(side, foot_pos)
	if delta > 0.0:
		idle_stance_rehoming.erase(side)
	sample_previous_support[side] = previous_support
	var hit := raycast_ground(space, foot_pos)
	if not hit["hit"] and likely_idle and _owner.step_prediction_enabled:
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
	var character := _owner.player_body.get_parent() as Player
	var idle_animation: bool = _owner.player_body.anim_player.current_animation \
			.get_file().contains("idle")
	if character != null and _landing_planner.reject_grounded_mismatch(
			character.global_position, _settings.max_split_ik_height, idle_animation, 0.05):
		landing_committed_target.clear()
	var committed_hit := _committed_landing_hit(space, side, character)
	if not committed_hit.is_empty():
		hit = committed_hit
		raw_target = committed_hit["position"]
		raw_normal = committed_hit["normal"]
		landing_committed_target[side] = raw_target
	debug_raw_target[side] = raw_target
	var safe_zone_pending := (character != null and split_safe_root_target.is_finite()
			and Vector2(character.global_position.x - split_safe_root_target.x,
					character.global_position.z - split_safe_root_target.z).length() > 0.05)
	if (safe_zone_pending and previous_support.y
			> split_safe_surface_y + _settings.max_split_ik_height
			and _has_surface_at_height(
					space, previous_support, previous_support.y, previous_support.y + 0.2)):
		raw_target = previous_support
		raw_normal = Vector3.UP
		smoothed_target[side] = previous_support
		smoothed_normal[side] = Vector3.UP
	if (frozen and smoothed_target.has(side)
			and (smoothed_target[side] as Vector3).distance_to(raw_target)
			> IDLE_FREEZE_MAX_TARGET_DRIFT
			and (hit["hit"] or not _owner._velocity_suppressed)):
		_owner._gait_tracker.invalidate_idle_freeze(side)
		frozen = false
	if likely_idle:
		if character != null and hit["hit"]:
			airborne_landing_probe_local[side] = character.global_basis.inverse() \
					* (raw_target - character.global_position)
	if not smoothed_target.has(side):
		smoothed_target[side] = raw_target
		smoothed_normal[side] = raw_normal
	elif hit["hit"] and raw_normal.dot(Vector3.UP) < 0.999:
		var current: Vector3 = smoothed_target[side]
		current -= raw_normal * (current - raw_target).dot(raw_normal)
		smoothed_target[side] = current
	var body_turning: bool = _owner._gait_tracker.is_body_turning(side)
	var landing_committed := landing_committed_target.has(side)
	if landing_committed:
		smoothed_target[side] = landing_committed_target[side]
		smoothed_normal[side] = Vector3.UP
	var idle_lower_latched := (false if landing_committed else
			_latch_idle_lower_support(
					space, side, body_turning, raw_target, raw_normal, delta, frozen))
	var landing_upper_owned := landing_upper_confirmed.has(side)
	if landing_upper_owned:
		var upper_surface: Vector3 = landing_upper_confirmed[side]
		raw_target = upper_surface
		raw_normal = Vector3.UP
		smoothed_target[side] = upper_surface
		smoothed_normal[side] = Vector3.UP
	var idle_lower_acquiring_now := idle_lower_acquiring.has(side)
	if idle_lower_acquiring_now:
		_owner._gait_tracker.invalidate_idle_freeze(side)
	var target_lock_allowed: bool = _owner._gait_tracker.target_lock_allows_latch(side)
	if hit["hit"] and likely_idle and raw_normal.dot(Vector3.UP) < 0.999:
		smoothed_normal[side] = raw_normal
		if body_turning:
			# A gradual turn supplies smoothing; a stale ramp target becomes unreachable.
			smoothed_target[side] = raw_target
	var likely_planted: bool = ((
			float(_owner._smoothed_ground_weight.get(side, 0.0)) >= PLANT_LOCK_WEIGHT
			or _owner._gait_tracker.is_locomotion_stance_active(side))
			and _owner._landing_grace_time <= 0.0
			and _owner.player_body.anim_player.current_animation.get_file() != "unarmed_jump_land"
			and target_lock_allowed)
	var idle_rehome_planted := float(
			_owner._smoothed_ground_weight.get(side, 0.0)) >= PLANT_LOCK_WEIGHT
	if (_settings.idle_stance_rehome_enabled and idle_rehome_planted
			and not landing_committed and not idle_lower_latched
			and not idle_lower_acquiring_now and not landing_upper_owned
			and not _owner._gait_tracker.is_body_translating()
			and idle_animation and _rehome_idle_stance_target(
					space, side, foot_pos, raw_target, raw_normal, delta)):
		idle_stance_rehoming[side] = smoothed_target[side]
		_owner._gait_tracker.invalidate_idle_freeze(side)
		frozen = false
	if _owner._landing_grace_time > 0.0 and not landing_upper_owned:
		smoothed_target[side] = raw_target
		smoothed_normal[side] = raw_normal
	elif not frozen and not idle_lower_latched and not idle_lower_acquiring.has(
			side) and not likely_planted and raw_target.distance_to(
			smoothed_target[side] as Vector3) > TARGET_NOISE_DEADBAND:
		var amount := clampf(delta * _owner.smooth_rate, 0.0, 1.0)
		var current_target := smoothed_target[side] as Vector3
		# A planted foot turning on a tread must not follow the animated probe
		# onto the next tread; translation is required for a height change.
		var follow_target := raw_target
		smoothed_target[side] = (move_target_smoothed(current_target, follow_target, delta)
				if not body_turning else current_target.move_toward(
				follow_target, _owner.target_max_speed * delta))
		smoothed_normal[side] = (smoothed_normal[side] as Vector3).lerp(
				raw_normal, amount).normalized()
	if (not hit["hit"] and not frozen and not idle_lower_latched and not landing_upper_owned
			and not idle_lower_acquiring.has(side)):
		var release_contact: Dictionary = contact_from_previous_support(
				space, side, previous_support, foot_pos)
		if release_contact["hit"]:
			return release_contact
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
			surface_hit = hit
			animated_lowest_point = foot_pos
		if not surface_hit["hit"]:
			surface_hit = raycast_ground(
					space, animated_lowest_point, _owner.idle_settle_search_down)
	if not surface_hit["hit"] and landing_upper_owned:
		surface_hit = {
			"hit": true,
			"position": landing_upper_confirmed[side],
			"normal": Vector3.UP,
		}
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
		"idle_lower_latched": idle_lower_latched,
		"idle_lower_acquiring": idle_lower_acquiring_now,
		"idle_stance_rehoming": idle_stance_rehoming.has(side),
	}
func _committed_landing_hit(space: PhysicsDirectSpaceState3D, side: StringName,
		character: Player) -> Dictionary:
	if (not _owner._grounded or character == null
			or not is_finite(airborne_committed_surface_y)
			or not airborne_landing_probe_local.has(side)
			or Vector2(character.velocity.x, character.velocity.z).length() > 0.05):
		landing_committed_target.erase(side)
		return {}
	var animation_name: String = _owner.player_body.anim_player.current_animation.get_file()
	if not (animation_name.contains("jump_land") or animation_name.contains("idle")):
		landing_committed_target.erase(side)
		return {}
	var point: Vector3 = character.global_position + character.global_basis \
			* (airborne_landing_probe_local[side] as Vector3)
	point.y = airborne_committed_surface_y
	var hit := raycast_ground(space, point + Vector3.UP * 0.25, 0.5)
	if (not hit["hit"] or absf((hit["position"] as Vector3).y
			- airborne_committed_surface_y) > 0.03):
		return {}
	return hit
func _latch_idle_lower_support(space: PhysicsDirectSpaceState3D, side: StringName,
		_body_turning: bool, raw_target: Vector3, raw_normal: Vector3, delta: float,
		frozen: bool = false) -> bool:
	var character := _owner.player_body.get_parent() as CharacterBody3D
	var animation_name: String = _owner.player_body.anim_player.current_animation.get_file()
	var support_animation: bool = (
			animation_name.contains("idle") or animation_name.contains("jump_land"))
	# Keep validated support through rotation; the stance-zone check retires it.
	var safe_zone_pending := (character != null and landing_upper_confirmed.has(side)
			and split_safe_root_target.is_finite()
			and Vector2(character.global_position.x - split_safe_root_target.x,
					character.global_position.z - split_safe_root_target.z).length() > 0.05)
	var should_release: bool = (not _settings.idle_lower_support_enabled
			or character == null or not _owner._grounded
			or (not support_animation and not safe_zone_pending)
			or (character != null
			and Vector2(character.velocity.x, character.velocity.z).length() > 0.05
			and not safe_zone_pending))
	if should_release:
		idle_lower_latched_target.erase(side)
		idle_lower_acquiring.erase(side)
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		landing_upper_confirmed.erase(side)
		return false
	if landing_upper_confirmed.has(side):
		idle_lower_latched_target.erase(side)
		idle_lower_acquiring.erase(side)
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		if animation_name.contains("jump_land") or not frozen:
			return false
		landing_upper_confirmed.erase(side)
	if not smoothed_target.has(side):
		return false
	# Deep split searches start only from a flat lower tread in the stance zone.
	var has_lower_state := (idle_lower_latched_target.has(side)
			or idle_lower_acquiring.has(side))
	var raw_drop := character.global_position.y - raw_target.y
	if (not has_lower_state
			and (raw_normal.dot(Vector3.UP) < STAIR_TREAD_UP_DOT
			or raw_drop <= _owner.step_min_rise
			or raw_drop > _owner.step_down_max_crouch + _owner.step_min_rise
			or not is_target_inside_stance_zone(side, raw_target))):
		return false
	var transition := _update_idle_lower_transition(
			side, raw_target, raw_normal, delta, character)
	if transition["handled"]:
		return transition["latched"]
	return _validate_idle_lower_support(
			space, side, transition["previous"], transition["had_latch"], delta, character)

func _update_idle_lower_transition(side: StringName, raw_target: Vector3,
		raw_normal: Vector3, delta: float, character: CharacterBody3D) -> Dictionary:
	if idle_lower_acquiring.has(side):
		var acquire_target: Vector3 = idle_lower_acquiring[side]
		var acquire_drop := character.global_position.y - acquire_target.y
		if (not is_target_inside_stance_zone(side, acquire_target)
				or acquire_drop > _owner.step_down_max_crouch + _owner.step_min_rise):
			idle_lower_acquiring.erase(side)
			_clear_lower_riser_away(side)
			lower_riser_cleared_target.erase(side)
		else:
			var current: Vector3 = smoothed_target[side]
			current = current.move_toward(acquire_target, _settings.lower_foot_acquire_speed * delta)
			smoothed_target[side] = current
			smoothed_normal[side] = raw_normal
			if current.distance_to(acquire_target) > TARGET_NOISE_DEADBAND:
				return {"handled": true, "latched": false}
			idle_lower_acquiring.erase(side)
			var acquired_drop := character.global_position.y - acquire_target.y
			var acquired: bool = (acquired_drop > _owner.step_min_rise
					and acquired_drop <= _owner.step_down_max_crouch + _owner.step_min_rise)
			if acquired:
				idle_lower_latched_target[side] = acquire_target
			return {"handled": true, "latched": acquired}
	var had_latch := idle_lower_latched_target.has(side)
	var previous: Vector3 = idle_lower_latched_target.get(side, smoothed_target[side])
	if not is_target_inside_stance_zone(side, previous):
		# Physical support outside the stance rectangle remains invalid.
		idle_lower_latched_target.erase(side)
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		if not is_target_inside_stance_zone(side, raw_target):
			return {"handled": true, "latched": false}
		if raw_normal.dot(Vector3.UP) < STAIR_TREAD_UP_DOT:
			smoothed_target[side] = raw_target
			smoothed_normal[side] = raw_normal
			return {"handled": true, "latched": false}
		# Rehome the complete target continuously. Copying the new X/Z first
		# teleported a planted foot across a tread during stationary rotation.
		smoothed_target[side] = previous.move_toward(
				raw_target, _settings.lower_foot_acquire_speed * delta)
		smoothed_normal[side] = raw_normal
		idle_lower_acquiring[side] = raw_target
		return {"handled": true, "latched": false}
	return {"handled": false, "latched": false,
			"previous": previous, "had_latch": had_latch}
func _validate_idle_lower_support(space: PhysicsDirectSpaceState3D, side: StringName,
		previous: Vector3, had_latch: bool, delta: float,
		character: CharacterBody3D) -> bool:
	var probe_up := 0.2
	var support := raycast_ground(
			space, Vector3(previous.x, character.global_position.y + probe_up, previous.z),
			probe_up + _owner.step_down_max_crouch + _owner.step_min_rise)
	if not support["hit"] or (support["normal"] as Vector3).dot(Vector3.UP) < 0.999:
		idle_lower_latched_target.erase(side)
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		return false
	var surface: Vector3 = support["position"]
	var drop := character.global_position.y - surface.y
	if drop <= _owner.step_min_rise or drop > _owner.step_down_max_crouch + _owner.step_min_rise:
		idle_lower_latched_target.erase(side)
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		return false
	var animation_name: String = _owner.player_body.anim_player.current_animation.get_file()
	var cleared_surface := (_rehome_lower_surface_from_riser(
			space, side, surface, character) if animation_name.contains("idle") else surface)
	if cleared_surface.distance_to(surface) > TARGET_NOISE_DEADBAND:
		# Move a lower plant away when its shin would still cross the riser.
		surface = cleared_surface
		idle_lower_latched_target.erase(side)
		smoothed_target[side] = previous.move_toward(
				surface, _settings.lower_foot_acquire_speed * delta)
		smoothed_normal[side] = support["normal"]
		idle_lower_acquiring[side] = surface
		return false
	# Fresh idle support descends at a bounded rate before it may latch.
	if not had_latch and absf(previous.y - surface.y) > TARGET_NOISE_DEADBAND:
		smoothed_target[side] = previous.move_toward(
				surface, _settings.lower_foot_acquire_speed * delta)
		smoothed_normal[side] = support["normal"]
		idle_lower_acquiring[side] = surface
		return false
	# Retain the lower surface when idle animation sways across the upper edge.
	smoothed_target[side] = surface
	smoothed_normal[side] = support["normal"]
	idle_lower_latched_target[side] = surface
	return true
func _rehome_lower_surface_from_riser(space: PhysicsDirectSpaceState3D,
		side: StringName, surface: Vector3, character: CharacterBody3D) -> Vector3:
	if not _settings.lower_riser_rehome_enabled:
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		return surface
	if (lower_riser_cleared_target.has(side)
			and (lower_riser_cleared_target[side] as Vector3).distance_to(surface)
			<= TARGET_NOISE_DEADBAND):
		return surface
	if _has_lower_riser_clearance(space, surface):
		_clear_lower_riser_away(side)
		lower_riser_cleared_target[side] = surface
		return surface
	var away := Vector3.ZERO
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var neighbor_xz := surface + direction * _settings.lower_riser_clearance_radius
		var neighbor := raycast_ground(space,
				Vector3(neighbor_xz.x, character.global_position.y, neighbor_xz.z),
				_owner.idle_settle_search_down)
		if (neighbor["hit"] and (neighbor["normal"] as Vector3).dot(Vector3.UP)
				>= STAIR_TREAD_UP_DOT
				and (neighbor["position"] as Vector3).y > surface.y + _owner.step_min_rise):
			away -= direction
	if away.length_squared() <= 0.0001:
		_clear_lower_riser_away(side)
		lower_riser_cleared_target.erase(side)
		return surface
	away = away.normalized()
	lower_riser_away[side] = away
	lower_riser_away_surface_y[side] = surface.y
	# Cardinal probes combine at corners; search their escape direction nearest-first.
	for step in range(1, LOWER_RISER_REHOME_STEPS + 1):
		var candidate_xz := surface + away * LOWER_RISER_REHOME_STEP * float(step)
		var candidate_hit := raycast_ground(space,
				Vector3(candidate_xz.x, character.global_position.y, candidate_xz.z),
				_owner.idle_settle_search_down)
		if (not candidate_hit["hit"]
				or (candidate_hit["normal"] as Vector3).dot(Vector3.UP)
				< STAIR_TREAD_UP_DOT):
			continue
		var candidate: Vector3 = candidate_hit["position"]
		if (absf(candidate.y - surface.y) > 0.03
				or not is_target_inside_stance_zone(side, candidate)
				or not _has_lower_riser_clearance(space, candidate)):
			continue
		lower_riser_cleared_target[side] = candidate
		return candidate
	lower_riser_cleared_target.erase(side)
	return surface
func _has_lower_riser_clearance(
		space: PhysicsDirectSpaceState3D, surface: Vector3) -> bool:
	for sample_index in 16:
		var angle := TAU * float(sample_index) / 16.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) \
				* _settings.lower_riser_clearance_radius
		var hit := raycast_ground(space, surface + offset + Vector3.UP * 0.2, 0.4)
		if (not hit["hit"] or (hit["normal"] as Vector3).dot(Vector3.UP)
				< STAIR_TREAD_UP_DOT
				or absf((hit["position"] as Vector3).y - surface.y) > 0.03):
			return false
	return true
func _rehome_idle_stance_target(space: PhysicsDirectSpaceState3D,
		side: StringName, foot_pos: Vector3, raw_target: Vector3,
		raw_normal: Vector3, delta: float) -> bool:
	var current: Vector3 = smoothed_target.get(side, Vector3(INF, INF, INF))
	if delta <= 0.0 or not current.is_finite() or is_target_inside_stance_zone(side, current):
		return false
	var character := _owner.player_body.get_parent() as Node3D
	if character == null:
		return false
	var forward := -character.global_basis.z
	var outward := -character.global_basis.x if side == &"left" else character.global_basis.x
	forward.y = 0.0
	outward.y = 0.0
	if forward.length_squared() <= 0.0001 or outward.length_squared() <= 0.0001:
		return false
	forward = forward.normalized()
	outward = outward.normalized()
	var from_root := current - character.global_position
	var lateral := clampf(from_root.dot(outward), IDLE_STANCE_REHOME_LATERAL,
			STANCE_ZONE_MAX_LATERAL - 0.04)
	var longitudinal := clampf(from_root.dot(forward),
			-STANCE_ZONE_MAX_LONGITUDINAL + 0.04, STANCE_ZONE_MAX_LONGITUDINAL - 0.04)
	var destination := character.global_position + outward * lateral + forward * longitudinal
	destination.y = current.y
	var probe_y := maxf(foot_pos.y, current.y) + 0.2
	var same_height_supported := (_has_surface_at_height(space, current, current.y, probe_y)
			and _has_surface_at_height(space, destination, current.y, probe_y))
	var next := raw_target
	if same_height_supported:
		next = current.move_toward(destination, _settings.idle_stance_rehome_speed * delta)
	elif not (is_target_inside_stance_zone(side, raw_target)
			and raw_normal.dot(Vector3.UP) >= STAIR_TREAD_UP_DOT
			and absf(raw_target.y - current.y) <= _settings.max_split_ik_height):
		# Retire a stale tread instead of fighting the final stance limiter.
		return false
	var next_hit := raycast_ground(space, Vector3(next.x, probe_y, next.z), probe_y - current.y + 0.2)
	if (not next_hit["hit"] or (next_hit["normal"] as Vector3).dot(Vector3.UP) < STAIR_TREAD_UP_DOT
			or absf((next_hit["position"] as Vector3).y - current.y) > 0.03):
		return false
	smoothed_target[side] = next_hit["position"]
	smoothed_normal[side] = next_hit["normal"]
	return true
func is_target_inside_stance_zone(side: StringName, target: Vector3) -> bool:
	var character := _owner.player_body.get_parent() as Node3D
	if character == null:
		return false
	var forward := -character.global_transform.basis.z
	var outward := (-character.global_transform.basis.x
			if side == &"left" else character.global_transform.basis.x)
	forward.y = 0.0
	outward.y = 0.0
	if forward.length_squared() <= 0.0001 or outward.length_squared() <= 0.0001:
		return false
	var from_root := target - character.global_position
	var lateral := from_root.dot(outward.normalized())
	var longitudinal := from_root.dot(forward.normalized())
	return (lateral >= STANCE_ZONE_MIN_LATERAL
			and lateral <= STANCE_ZONE_MAX_LATERAL
			and absf(longitudinal) <= STANCE_ZONE_MAX_LONGITUDINAL)
func validate_and_latch_landing_lower_support(side: StringName, contact: Dictionary,
		hip_position: Vector3, leg_reach: float) -> bool:
	var character := _owner.player_body.get_parent() as Node3D
	var previous_lower: Vector3 = idle_lower_latched_target.get(side, Vector3.ZERO)
	var raw_surface: Vector3 = contact.get("raw_target", Vector3.ZERO)
	# Capsule support at raw height proves the tread despite a raised landing sole.
	var root_on_raw_surface: bool = (character != null and
			absf(character.global_position.y - raw_surface.y) <= _owner.step_min_rise)
	var confirms_upper: bool = (idle_lower_latched_target.has(side)
			and contact["hit"] and contact.get("animated_contact_hit", false)
			and (float(contact.get("animated_contact_distance", INF))
			<= LANDING_UPPER_CONTACT_DISTANCE or root_on_raw_surface)
			and (contact.get("raw_normal", Vector3.UP) as Vector3).dot(Vector3.UP)
			>= STAIR_TREAD_UP_DOT
			and raw_surface.y > previous_lower.y + _owner.step_min_rise)
	if confirms_upper:
		var upper_frames := int(landing_upper_confirmation_frames.get(side, 0)) + 1
		landing_upper_confirmation_frames[side] = upper_frames
		if upper_frames >= LANDING_UPPER_CONFIRM_FRAMES:
			idle_lower_latched_target.erase(side)
			idle_lower_acquiring.erase(side)
			_clear_lower_riser_away(side)
			lower_riser_cleared_target.erase(side)
			landing_upper_confirmation_frames.erase(side)
			landing_upper_confirmed[side] = raw_surface
	else:
		landing_upper_confirmation_frames.erase(side)
	var reachable: bool = (not landing_upper_confirmed.has(side)
			and contact.has("ground_target") and contact["hit"] and _owner._grounded
			and _owner.player_body.anim_player.current_animation.get_file().contains("jump_land")
			and character.global_position.y - Vector3(contact["ground_target"]).y
			> _owner.step_min_rise
			and hip_position.distance_to(contact["ground_target"])
			<= leg_reach + _owner.step_down_max_crouch
			and is_target_inside_stance_zone(side, contact["ground_target"]))
	if reachable:
		# Carry proven support through jump_land -> idle.
		idle_lower_latched_target[side] = contact["raw_target"]
		landing_upper_confirmation_frames.erase(side)
	return reachable
func contact_from_previous_support(space: PhysicsDirectSpaceState3D, side: StringName,
		previous_surface: Vector3, animated_foot: Vector3) -> Dictionary:
	# Retain prior physical support while a newly walking foot fades its IK weight.
	if (not _owner._grounded
			or float(_owner._smoothed_ground_weight.get(side, 0.0)) <= 0.0):
		return {"hit": false}
	var probe := Vector3(previous_surface.x,
			maxf(animated_foot.y, previous_surface.y) + 0.2, previous_surface.z)
	var support := raycast_ground(space, probe, _owner.idle_settle_search_down + 0.5)
	if (not support["hit"]
			or absf((support["position"] as Vector3).y - previous_surface.y) > 0.05):
		return {"hit": false}
	var surface: Vector3 = support["position"]
	var normal: Vector3 = support["normal"]
	var offset: float = maxf(
			_owner.ankle_offset, _owner._sole_depth_below_foot.get(side, 0.0))
	smoothed_target[side] = surface
	smoothed_normal[side] = normal
	return {
		"hit": true,
		"raw_target": surface,
		"raw_normal": normal,
		"effective_offset": offset,
		"ground_target": surface + normal * offset,
		"raw_ground_target": surface + normal * offset,
		"animated_lowest_point": animated_foot,
		"animated_contact_distance": maxf(0.0, animated_foot.y - surface.y),
		"animated_contact_hit": true,
		"animated_contact_position": surface,
		"animated_contact_normal": normal,
		"previous_support_release": true,
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
	# Match the harness by comparing the sole with the extrapolated toe tip.
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
func _support_patch_inward(space: PhysicsDirectSpaceState3D,
		surface: Vector3, radius: float) -> Vector3:
	var inward := Vector3.ZERO
	for offset: Vector3 in [Vector3(radius, 0.0, 0.0), Vector3(-radius, 0.0, 0.0),
			Vector3(0.0, 0.0, radius), Vector3(0.0, 0.0, -radius)]:
		var hit := raycast_ground(space, surface + offset + Vector3.UP * 0.2, 0.4)
		if (not hit["hit"] or (hit["normal"] as Vector3).dot(Vector3.UP) < STAIR_TREAD_UP_DOT
				or absf((hit["position"] as Vector3).y - surface.y) > 0.03):
			inward -= offset.normalized()
	return inward
func prepare_overheight_split_safe_zone(space: PhysicsDirectSpaceState3D,
		per_leg: Dictionary) -> bool:
	if (not _settings.grounded_split_recovery_enabled
			and (split_safe_root_target.is_finite() or not split_safe_held_upper_target.is_empty())):
		reject_split_safe_root()
	if (not _settings.grounded_split_recovery_enabled
			or not per_leg.has(&"left") or not per_leg.has(&"right")):
		return false
	var left_surface: Vector3 = per_leg[&"left"].get("raw_target", Vector3.ZERO)
	var right_surface: Vector3 = per_leg[&"right"].get("raw_target", Vector3.ZERO)
	var upper_surface := left_surface if left_surface.y >= right_surface.y else right_surface
	var lower_surface := right_surface if left_surface.y >= right_surface.y else left_surface
	var animation_name: String = _owner.player_body.anim_player.current_animation.get_file()
	var character := _owner.player_body.get_parent() as Player
	if (idle_lower_latched_target.has(&"left")
			and idle_lower_latched_target.has(&"right")
			and absf((idle_lower_latched_target[&"left"] as Vector3).y
					- (idle_lower_latched_target[&"right"] as Vector3).y) <= 0.03
			and Vector2(character.velocity.x, character.velocity.z).length() <= 0.05):
		preferred_root_nudge = Vector3.ZERO
		preferred_root_nudge_surface_y = -INF
		split_safe_root_target = Vector3(INF, INF, INF)
		split_safe_surface_y = -INF
		split_safe_held_upper_target.clear()
		return false
	var recovering := _request_overheight_split_safe_zone(
			space, upper_surface, lower_surface, animation_name)
	if not recovering:
		split_safe_held_upper_target.clear()
		return false
	var root_to_safe := split_safe_root_target - character.global_position
	root_to_safe.y = 0.0
	if (split_safe_surface_y < upper_surface.y - 0.03
			and (root_to_safe.length() > 0.05
					or character.global_position.y > split_safe_surface_y + 0.15)):
		split_safe_held_upper_target.clear()
		return false
	if split_safe_held_upper_target.is_empty():
		var root_motion := split_safe_root_target - character.global_position
		for side: StringName in [&"left", &"right"]:
			var previous: Vector3 = sample_previous_support.get(side, Vector3(INF, INF, INF))
			var current: Vector3 = smoothed_target.get(side, Vector3(INF, INF, INF))
			if previous.is_finite() and absf(previous.y - split_safe_surface_y) <= 0.03:
				split_safe_held_upper_target[side] = previous
			elif current.is_finite() and absf(current.y - split_safe_surface_y) <= 0.03:
				split_safe_held_upper_target[side] = current
			else:
				var shifted: Vector3 = per_leg[side].get("raw_target", current) + root_motion
				shifted.y = split_safe_surface_y
				if _has_surface_at_height(
						space, shifted, split_safe_surface_y, upper_surface.y + 0.2):
					split_safe_held_upper_target[side] = shifted
	if split_safe_held_upper_target.size() < 2:
		return false
	for side: StringName in [&"left", &"right"]:
		var held_surface: Vector3 = split_safe_held_upper_target[side]
		var leg: Dictionary = per_leg[side]
		var offset: float = leg.get("effective_offset", _owner.ankle_offset)
		var held_target := held_surface + Vector3.UP * offset
		smoothed_target[side] = held_surface
		smoothed_normal[side] = Vector3.UP
		idle_lower_latched_target.erase(side)
		idle_lower_acquiring.erase(side)
		leg["target"] = held_target
		leg["ground_target"] = held_target
		leg["raw_ground_target"] = held_target
		leg["raw_target"] = held_surface
		leg["raw_normal"] = Vector3.UP
		leg["step_down"] = false
		leg["preserve_idle_pose"] = false
		leg["ground_weight"] = 1.0
		leg["chain_weight"] = 1.0
		_owner._solved_target_smoothed[side] = held_target
		_owner.debug_step_down[side] = false
	return true
func _request_overheight_split_safe_zone(space: PhysicsDirectSpaceState3D,
		upper_surface: Vector3, lower_surface: Vector3, animation_name: String,
		left := Vector3(INF, INF, INF), right := Vector3(INF, INF, INF)) -> bool:
	var character := _owner.player_body.get_parent() as Player
	var landing_recovery := not landing_upper_confirmed.is_empty()
	var continuing_recovery := (character != null and split_safe_root_target.is_finite()
			and split_safe_held_upper_target.size() == 2
			and (animation_name.contains("idle") or landing_recovery))
	if continuing_recovery:
		var remaining := split_safe_root_target - character.global_position
		remaining.y = 0.0
		if remaining.length() > 0.03:
			preferred_root_nudge += split_safe_root_target - character.global_position
			preferred_root_nudge_surface_y = split_safe_surface_y
			return true
	if (character == null
			or (not animation_name.contains("idle") and not landing_recovery)
			or upper_surface.y - lower_surface.y <= _settings.max_split_ik_height):
		split_safe_root_target = Vector3(INF, INF, INF)
		split_safe_surface_y = -INF
		split_rejected_surface_y = -INF
		split_safe_held_upper_target.clear()
		return false
	var root := character.global_position
	if not split_safe_root_target.is_finite() or root.distance_to(split_safe_root_target) <= 0.03:
		var safe := _find_nearest_split_safe_root(
				space, root, upper_surface.y, lower_surface.y,
				upper_surface.y + 0.2, left, right)
		split_safe_root_target = safe["root"]
		split_safe_surface_y = safe["surface_y"]
	if not split_safe_root_target.is_finite():
		return false
	preferred_root_nudge += split_safe_root_target - root
	preferred_root_nudge_surface_y = split_safe_surface_y
	return true
func _find_split_safe_root(space: PhysicsDirectSpaceState3D,
		root: Vector3, surface_y: float, probe_y: float,
		left := Vector3(INF, INF, INF), right := Vector3(INF, INF, INF)) -> Vector3:
	if not left.is_finite() or not right.is_finite():
		if not debug_raw_target.has(&"left") or not debug_raw_target.has(&"right"):
			return Vector3(INF, INF, INF)
		left = debug_raw_target[&"left"]
		right = debug_raw_target[&"right"]
	for ring in range(1, SPLIT_SAFE_SEARCH_RINGS + 1):
		var radius := float(ring) * SPLIT_SAFE_SEARCH_STEP
		var samples := ring * 8
		for sample_index in samples:
			var angle := TAU * float(sample_index) / float(samples)
			var motion := Vector3(cos(angle), 0.0, sin(angle)) * radius
			if (_has_surface_at_height(space, root + motion, surface_y, probe_y)
					and _has_surface_at_height(space, left + motion, surface_y, probe_y)
					and _has_surface_at_height(space, right + motion, surface_y, probe_y)):
				return root + motion
	return Vector3(INF, INF, INF)
func _find_nearest_split_safe_root(space: PhysicsDirectSpaceState3D, root: Vector3,
		upper_y: float, lower_y: float, probe_y: float,
		left: Vector3, right: Vector3) -> Dictionary:
	var upper := _find_split_safe_root(space, root, upper_y, probe_y, left, right)
	var lower := _find_split_safe_root(space, root, lower_y, probe_y, left, right)
	if is_equal_approx(split_rejected_surface_y, upper_y):
		upper = Vector3(INF, INF, INF)
	if is_equal_approx(split_rejected_surface_y, lower_y):
		lower = Vector3(INF, INF, INF)
	if not upper.is_finite():
		return {"root": lower, "surface_y": lower_y}
	if not lower.is_finite() or root.distance_to(upper) <= root.distance_to(lower):
		return {"root": upper, "surface_y": upper_y}
	return {"root": lower, "surface_y": lower_y}
func predict_airborne_safe_root(space: PhysicsDirectSpaceState3D,
		max_landing_drop: float) -> Vector3:
	return _landing_planner.predict(space, max_landing_drop)
func _has_surface_at_height(space: PhysicsDirectSpaceState3D,
		position: Vector3, surface_y: float, probe_y: float) -> bool:
	var probe := Vector3(position.x, probe_y, position.z)
	var hit := raycast_ground(space, probe, probe_y - surface_y + 0.2)
	return (hit["hit"] and (hit["normal"] as Vector3).dot(Vector3.UP) >= STAIR_TREAD_UP_DOT
			and absf((hit["position"] as Vector3).y - surface_y) <= 0.03)
