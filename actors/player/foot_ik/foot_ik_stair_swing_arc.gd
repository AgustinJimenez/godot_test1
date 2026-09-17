extends RefCounted
## Optional 030 prototype. Owns a supported destination separately from the airborne waypoint.
## Planning also runs for missing contacts; an airborne swing is not a planted foot.

const FLAT_DOT := 0.999
const SCAN_STEP := 0.12
const SCAN_COUNT := 20
const SWING_SECONDS := 0.32
const PLANT_RISE_LIMIT := 0.05 # m/frame max target step-up while planted (030 step transaction)

var _owner
var _states: Dictionary = {}
var _bases: Dictionary = {}
var _last_frame := -1
var _last_side: StringName = &""
var _previous_root := Vector3(INF, INF, INF)
var _root_velocity := Vector3.ZERO
var _decisions: Dictionary = {}
var _animated_y: Dictionary = {}
var _plant_y: Dictionary = {}


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	_states.clear()
	_bases.clear()
	_last_frame = -1
	_last_side = &""
	_previous_root = Vector3(INF, INF, INF)
	_root_velocity = Vector3.ZERO
	_decisions.clear()
	_animated_y.clear()
	_plant_y.clear()


func get_state(side: StringName) -> Dictionary:
	return _states.get(side, {}).duplicate()


func get_decision(side: StringName) -> String:
	return _decisions.get(side, "disabled")


func prepare(space: PhysicsDirectSpaceState3D, per_leg: Dictionary, delta: float) -> void:
	if not FootIKDebug.settings.stair_swing_arc or not _owner.step_prediction_enabled:
		reset()
		return
	var animation: String = _owner.player_body.anim_player.current_animation.get_file()
	if not (animation.contains("walk") or animation.contains("sprint")):
		reset()
		return
	var advance := delta > 0.0 and _last_frame != Engine.get_physics_frames()
	_last_frame = Engine.get_physics_frames()
	var root: Vector3 = _owner.player_body.get_parent().global_position
	if advance:
		if _previous_root.is_finite(): _root_velocity = (root - _previous_root) / delta
		_previous_root = root
	var skel: Skeleton3D = _owner.get_skeleton()
	for side: StringName in per_leg:
		_decisions[side] = "active"
		var leg: Dictionary = per_leg[side]
		# Step transaction (030): a planted/support target that steps up a full tread in one frame
		# yanks the foot through the riser, which is what makes the 025 retry fire and spike the
		# joints (028). Ease its rise instead.
		var target_now: Vector3 = leg.get("target", leg["hip_pos"]) as Vector3
		var previous_y: float = float(_plant_y.get(side, target_now.y))
		if target_now.y - previous_y > PLANT_RISE_LIMIT:
			target_now.y = previous_y + PLANT_RISE_LIMIT
			leg["target"] = target_now
			if leg.has("ground_target"):
				leg["ground_target"] = target_now
		_plant_y[side] = (leg["target"] as Vector3).y
		var fresh: Dictionary = _owner._leg_fresh_pose_cache[side]
		var animated_y: float = (fresh["foot"] as Transform3D).origin.y
		var rising := 0.0
		if advance:
			rising = (animated_y - float(_animated_y.get(side, animated_y))) / delta
			_animated_y[side] = animated_y
		var foot: Vector3 = skel.global_transform * (fresh["foot"] as Transform3D).origin
		var normal: Vector3 = leg.get("raw_normal", Vector3.UP)
		var contact := bool(leg.get("hit", false)) and normal.dot(Vector3.UP) >= FLAT_DOT
		if not _bases.has(side) and contact:
			_bases[side] = leg["raw_target"]
		if _owner._stair_predictor.get_support_side() == side:
			_decisions[side] = "support"
			_states.erase(side)
			if contact: _bases[side] = leg["raw_target"]
			continue
		if not _states.has(side):
			if not _states.is_empty() or side == _last_side:
				_decisions[side] = "await_other_leg"
				continue
			var weight: float = _owner._smoothed_ground_weight.get(side, 0.0)
			if weight >= 0.8 or not _bases.has(side) or rising < 0.1:
				_decisions[side] = "not_swinging_or_no_base"
				if contact: _bases[side] = leg["raw_target"]
				continue
			var landing := _find_landing(space, foot, _bases[side], leg)
			if landing.is_empty():
				_decisions[side] = "no_destination base=%s hip=%s velocity=%s reach=%.3f" % [
						_bases[side], leg["hip_pos"], _root_velocity,
						float(leg["upper"]) + float(leg["lower"])]
				continue
			var start := foot
			var foot_idx: int = _owner._bone_indices[side]["foot"]
			if _owner._final_bone_poses.has(foot_idx):
				start = skel.global_transform * _owner.get_final_bone_global_pose(foot_idx).origin
			_states[side] = {"start": start, "surface": landing["position"],
					"elapsed": 0.0, "progress": 0.0, "weight": 0.0}
			_last_side = side
		var state: Dictionary = _states[side]
		if advance:
			state["elapsed"] += delta * maxf(_owner.player_body.locomotion_playback_scale, 0.001)
		var progress := clampf(float(state["elapsed"]) / SWING_SECONDS, 0.0, 1.0)
		var surface: Vector3 = state["surface"]
		var support: Dictionary = _owner._ground_sampler.raycast_ground(space, surface)
		if (not support["hit"] or (support["position"] as Vector3).distance_to(surface) > 0.03):
			_states.erase(side)
			continue
		var offset: float = maxf(_owner.ankle_offset, _owner._sole_depth_below_foot.get(side, 0.0))
		var landing := surface + Vector3.UP * offset
		var eased := smoothstep(0.0, 1.0, progress)
		var target: Vector3 = (state["start"] as Vector3).lerp(landing, eased)
		target.y += sin(PI * progress) * float(_owner.step_clearance_margin)
		var reach: float = float(leg["upper"]) + float(leg["lower"])
		if (leg["hip_pos"] as Vector3).distance_to(target) > reach + _owner.step_down_max_crouch:
			_states.erase(side)
			continue
		state["progress"] = progress
		state["weight"] = smoothstep(0.0, 0.25, progress)
		state["target"] = target
		leg.merge({"air_swing": true, "target": target, "ground_target": landing,
				"raw_ground_target": landing, "raw_target": surface, "raw_normal": Vector3.UP,
				"effective_offset": offset, "ground_weight": 0.0, "chain_weight": state["weight"],
				"preserve_idle_pose": false, "animated_contact_hit": false,
				"animated_contact_distance": INF, "swing_destination": surface}, true)
		# No invented support: only the destination is validated, never the in-air waypoint.
		leg["hit"] = false
		if progress >= 1.0:
			leg["hit"] = true
			leg["animated_contact_hit"] = true
			leg["animated_contact_distance"] = 0.0
			leg["animated_contact_position"] = surface
			leg["animated_contact_normal"] = Vector3.UP
			leg["ground_weight"] = 1.0
			_bases[side] = surface


func _find_landing(space: PhysicsDirectSpaceState3D,
		foot: Vector3, base: Vector3, leg: Dictionary) -> Dictionary:
	var direction: Vector3 = _owner._stair_predictor._travel_direction
	if direction.length_squared() < 0.001:
		return {}
	var future_hip: Vector3 = leg["hip_pos"] + _root_velocity * SWING_SECONDS
	var reach: float = float(leg["upper"]) + float(leg["lower"])
	var best: Dictionary = {}
	var best_score := INF
	for i in range(1, SCAN_COUNT + 1):
		var probe := foot + direction * (SCAN_STEP * i)
		probe.y = future_hip.y
		var hit: Dictionary = _owner._ground_sampler.raycast_ground(space, probe, reach + 0.5)
		if not hit["hit"]:
			continue
		var normal: Vector3 = hit["normal"]
		var surface: Vector3 = hit["position"]
		if normal.dot(Vector3.UP) < FLAT_DOT or surface.y <= base.y + _owner.step_min_rise:
			continue
		if surface.y > maxf(base.y, foot.y - float(_owner.ankle_offset)) + reach * 0.85:
			continue
		var inset: Dictionary = _owner._ground_sampler.raycast_ground(
				space, surface + direction * 0.12)
		if not inset["hit"] or absf((inset["position"] as Vector3).y - surface.y) >= 0.01:
			continue
		var landing: Vector3 = inset["position"] + Vector3.UP * float(_owner.ankle_offset)
		var score := future_hip.distance_to(landing)
		if score <= reach + 0.05 and score < best_score:
			best = inset
			best_score = score
	return best
