class_name FootIKV2Modifier
extends SkeletonModifier3D
## v2 foot IK: per leg, sample the ground under the animated foot, solve hip -> knee -> ankle.
## Deliberately small: one behaviour at a time, each with its own check (v1 grew to 20 modules).

## Role names are the character's humanoid roles, resolved through PlayerBody for any character.
const LEGS := {
	&"left": {"hip": &"LeftUpLeg", "knee": &"LeftLeg", "foot": &"LeftFoot",
		"toe": &"LeftToeBase"},
	&"right": {"hip": &"RightUpLeg", "knee": &"RightLeg", "foot": &"RightFoot",
		"toe": &"RightToeBase"},
}

@export var enabled := true
## Physics layers the ground is on: 1 = world, 6 = authored surfaces (layer 1 alone misses stairs).
@export_flags_3d_physics var ground_mask := 1 | (1 << 5)
## Fallback floor limit when not a CharacterBody3D; steeper is a wall/riser, left to the animation.
@export var fallback_floor_max_angle_deg := 46.0
## A surface this far BELOW the foot is not its floor (a ledge/ramp edge): re-probe inward first.
@export var max_surface_drop := 0.45
@export var ray_up := 0.5
@export var ray_down := 1.2
## How far the ankle sits above ground when planted. Negative derives it from the rig's rest pose.
@export var ankle_height := -1.0
## 0 = keep the authored pose, 1 = fully plant on the sampled ground.
@export_range(0.0, 1.0) var weight := 1.0
## When a foot's target is past the leg's reach, lower the pelvis by the shortfall, up to this.
@export var max_pelvis_drop := 0.40
## Faster than `still_speed`, the drop is capped much lower (a deep squat looks wrong mid-stride).
@export var moving_pelvis_drop := 0.06
@export var still_speed := 0.5
## Jumping (airborne or in a jump clip) counts as moving for the pelvis drop and stance shift.
@export var jump_counts_as_moving := true
## Let the body follow the capsule's height smoothly instead of popping a whole tread per step.
@export var body_smooth := true
@export var body_follow_rate := 8.0
@export var body_max_lag := 0.18
## Slide a planted foot along its length until its whole sole is on one surface, up to this far.
@export var support_snap := true
@export var support_search := 0.16
const SUPPORT_STEP := 0.02
const SUPPORT_TOLERANCE := 0.03
const SUPPORT_MIN_PLANT := 0.9
const SINK_MIN := 0.04 # a flat sole this far below the aimed-at height re-aims the resting foot
const BODY_LAG_SNAP := 0.4
## The drop grows at this rate (m/s) and is released at the next one (no pop down or back up).
@export var pelvis_attack_speed := 1.5
## How fast the pelvis drop may GROW (m/s) while moving or jumping (release stays normal).
@export var moving_pelvis_rate := 0.25
@export var pelvis_release_speed := 0.6
## At rest, a foot whose floor is out of reach may be brought this far toward the body first.
@export var max_stance_shift := 0.30
## At rest, a foot still out of reach reaches as far as the leg allows instead of releasing.
@export var reach_when_still := true
## The same while walking: a foot briefly out of reach reaches as far as it can instead of popping.
@export var reach_when_moving := true
## Fade the correction out smoothly as a foot lifts, instead of snapping it the frame it swings.
@export var plant_fade := true
## Planted at least this much may still clamp toward an out-of-reach surface; below it, releases.
@export_range(0.0, 1.0, 0.05) var reach_clamp_plant_min := 0.85
## Filter the sampled floor height so a foot at a tread edge does not chase the ray flip-flopping.
@export var ground_filter := true
const SOFT_PELVIS_DROP := 0.10
const STANCE_SHIFT_STEP := 0.05
const STANCE_RELEASE_SPEED := 0.6
## How far ahead of the toe bone the shoe's tip is (matches the lab's orange/green tip sphere).
const TOE_TIP_FORWARD := 0.035
## A clearance "penetration" bigger than this is a riser, not a slope: retreat instead of lifting.
const RISER_PENETRATION := 0.04
const SOLE_GAP_TOLERANCE := 0.001 # leave this much float once the true lowest sole vertex clears
const SOLE_SINK_ATTEMPTS := 2 # lowering can shift which vertex is lowest; re-scan once more
const RISER_RETREAT_STEP := 0.012
## Retreats are tried first; a foot still in the riser after this many is lifted onto the tread.
const RISER_MAX_RETREATS := 4
const CLEAR_ATTEMPTS := 8
## Vertical speed (m/s) above which the character counts as airborne / jumping.
const JUMP_SPEED_EPSILON := 0.5
## A foot the animation has lifted less than PLANT_FADE_START above the character's floor level is
## fully planted; by PLANT_FADE_END it is fully swinging. Smoothly blended in between.
const PLANT_FADE_START := 0.03
const PLANT_FADE_END := 0.14
## The plant weight moves at most this fast (per second): 1 -> 0 takes 1/PLANT_RATE s.
const PLANT_RATE := 8.0
## A swinging foot is released to the animation once its weight has faded below this.
const PLANT_RELEASE_BELOW := 0.02
## The floor height a foot chases changes at most this fast (m/s): a 0.35 m riser takes ~7 frames.
const GROUND_RATE := 3.0
## A different floor level must be the answer this many frames in a row (within GROUND_SAME_LEVEL)
## before the foot follows it.
const GROUND_HOLD_FRAMES := 3
const GROUND_SAME_LEVEL := 0.04
## Changes up to this per frame (a slope is ~0.04 at 45 deg / 3.2 m/s) are followed exactly; a
## bigger step is rate-limited; one past GROUND_SNAP (a landing, a respawn) is taken at once.
const GROUND_FOLLOW := 0.06
const GROUND_SNAP := 0.45
const PELVIS_REACH_MARGIN := 0.012
## The heel is the rearmost point within this height of the shoe's lowest vertex.
const HEEL_SOLE_BAND := 0.04
## Only a foot the ANIMATION plants (ankle within this of the character's floor level) can ask
## for a pelvis drop.
const PELVIS_PLANTED_TOLERANCE := 0.05
## A foot lifted more than this above the sampled ground is mid-swing and left to the animation;
## one at or below it is corrected, even onto a surface above it (stepping up a ramp).
@export var max_lift := 0.25

var player_body: PlayerBody
## side -> the target this leg was last corrected toward, and why it was skipped, so the trace
## logs the REAL decision instead of re-deriving it.
var debug_target: Dictionary = {}
var debug_skip_reason: Dictionary = {}
var debug_ground_normal: Dictionary = {}
## side -> the animated ankle, the sampled ground, and the reach check, so a trace can tell a
## skipped swing foot from a target the leg simply could not reach.
var debug_animated_ankle: Dictionary = {}
var debug_ground: Dictionary = {}
## side -> name of the collider the ground ray hit (which surface owns the contact).
var debug_surface: Dictionary = {}
## Physics frame of the last real pass and the pass count: a frozen modifier shows a stale frame.
var debug_last_frame := -1
var debug_passes := 0
## bone index -> world Transform3D as published at the end of the last pass, and its physics frame.
var final_pose: Dictionary = {}
var final_frame := -1
## The pelvis drop applied this frame (m), for the trace.
var _stretch_hold := 0.0 # extra pelvis drop a resting, unreachable foot asked for
var debug_pelvis_drop := 0.0
var debug_solve: Dictionary = {}
## side -> {hip_to_target, reach}: the reach decision every frame, released or not (trace).
var debug_reach_check: Dictionary = {}
## side -> "released", "at_target", or "stretched" (out of reach): grades only feet meant down.
var debug_state: Dictionary = {}
## side -> {"before_deg", "after_deg", "applied"}: how far the sole was from the sampled surface
## normal before the align pass and after it, in the skeleton's own space.
var debug_align: Dictionary = {}

## side -> {"hip", "knee", "foot", "upper", "lower", "rest_pole"}
var _legs: Dictionary = {}
var _sole_cache: Dictionary = {} # side -> _cache_sole_vertices() result
## Base animation poses, captured once per frame before anything is modified (the modifier can run
## more than once per tick; re-deriving later would read our own output back as the animation).
var _frame := -1
var _base: Dictionary = {}
var _hips_bone := -1
var _hips_base := Transform3D.IDENTITY
var _pelvis_drop := 0.0
## side -> how far the foot was slid along its length to sit on one surface this frame (trace).
var debug_support_shift: Dictionary = {}
var _smoothed_y := NAN
var _body_lag := 0.0
## How far the visible body trails below the capsule this frame (m), for the trace.
var debug_body_lag := 0.0
var _stance_shift: Dictionary = {}
var _ground_pending: Dictionary = {}
var _ground_raw: Dictionary = {}
var _ground_frame: Dictionary = {}
var _ground_state: Dictionary = {}
var _plant_weight: Dictionary = {}
var _plant_state: Dictionary = {}
var _plant_frame: Dictionary = {}
var _support_last: Dictionary = {} # side -> last flatten slide (kept while valid)
var _spread_level := 0.0 # sole surface height from the last `_support_spread`
## side -> how planted the animation has this foot, 1 down .. 0 swinging (trace).
var debug_plant_weight: Dictionary = {}
var _is_moving := false
## side -> metres the foot is currently brought in toward the body (trace).
var debug_stance_shift: Dictionary = {}
## side -> [[shift, drop needed], ...] tried by the last stance plan (trace).
var debug_stance_plan: Dictionary = {}
## side -> how far the toe/tip/heel clearance pass lifted the ankle target this frame (trace).
var debug_toe_lift: Dictionary = {}


func _ready() -> void:
	if player_body == null:
		player_body = get_skeleton().get_parent() as PlayerBody if get_skeleton() != null else null
	_build_legs()


func _build_legs() -> void:
	_legs.clear()
	var skel := get_skeleton()
	if skel == null or player_body == null:
		return
	_hips_bone = skel.find_bone(player_body.resolve_bone_name(&"Hips"))
	for side: StringName in LEGS:
		var roles: Dictionary = LEGS[side]
		var hip := skel.find_bone(player_body.resolve_bone_name(roles["hip"]))
		var knee := skel.find_bone(player_body.resolve_bone_name(roles["knee"]))
		var foot := skel.find_bone(player_body.resolve_bone_name(roles["foot"]))
		if hip < 0 or knee < 0 or foot < 0:
			continue
		var hip_rest := skel.get_bone_global_rest(hip).origin
		var knee_rest := skel.get_bone_global_rest(knee).origin
		var foot_rest := skel.get_bone_global_rest(foot).origin
		var toe_bone := skel.find_bone(player_body.resolve_bone_name(roles["toe"]))
		_sole_cache[side] = _cache_sole_vertices(skel, foot, toe_bone)
		# Knee bend plane at rest, so a leg whose bend direction is ambiguous still folds forward.
		var sole_depth := _measure_sole_depth(skel, side, foot)
		print("[FootIKv2] %s sole_depth=%.4f bone_rest_y=%.4f" % [
				side, sole_depth, foot_rest.y])
		if ankle_height < 0.0:
			# How high the ankle sits for the SOLE to touch: not the bone's own rest height (0.111
			# vs a real sole depth of ~0.096), so it is measured from the skinned mesh at rest.
			ankle_height = sole_depth
		var rest_direction := (foot_rest - hip_rest).normalized()
		var rest_pole := knee_rest - hip_rest
		rest_pole -= rest_direction * rest_pole.dot(rest_direction)
		_legs[side] = {
			"hip": hip, "knee": knee, "foot": foot,
			"toe": toe_bone,
			# The toe bone sits only this far above the sole; NOT ankle_height (that put its "sole
			# point" ~8 cm underground and the clearance pass lifted every foot).
			"toe_depth": maxf(0.0, skel.get_bone_global_rest(toe_bone).origin.y),
			"upper": hip_rest.distance_to(knee_rest),
			"lower": knee_rest.distance_to(foot_rest),
			"rest_pole": rest_pole.normalized(),
			# The sole's downward direction in the foot bone's own space: the rest pose stands on
			# the floor, so world-down at rest IS the sole direction for this rig.
			"sole_local": (skel.get_bone_global_rest(foot).basis.inverse() * Vector3.DOWN).normalized(),
			# The visible heel (rearmost sole-level mesh point) in the foot bone's own space.
			"heel_local": _measure_heel_local(skel, side, foot, toe_bone),
		}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _legs.is_empty():
		return
	var t0 := FootIKV2Debug.begin()
	if enabled:
		debug_last_frame = Engine.get_physics_frames()
		debug_passes += 1
		_take_snapshot(skel)
		if _pelvis_drop + _body_lag > 0.0005 and _hips_bone >= 0:
			skel.set_bone_global_pose(_hips_bone, _hips_base)
		for side: StringName in _legs:
			_place_foot(skel, side, _legs[side])
	_publish_final_poses(skel)
	FootIKV2Debug.end(&"total", t0)
	FootIKV2Debug.frame_tick()


## The published result: world transforms captured at the END of this pass (reading bones from
## _process() or skeleton_updated returned stale poses). Refreshed even when v2 is disabled.
func _publish_final_poses(skel: Skeleton3D) -> void:
	final_frame = Engine.get_physics_frames()
	var to_world := skel.global_transform
	for side: StringName in _legs:
		for role: String in ["hip", "knee", "foot", "toe"]:
			var bone := int((_legs[side] as Dictionary)[role])
			if bone >= 0:
				final_pose[bone] = to_world * skel.get_bone_global_pose(bone)
	for role: StringName in [&"Hips", &"Spine", &"Spine1", &"Spine2"]:
		var bone := skel.find_bone(player_body.resolve_bone_name(role))
		if bone >= 0:
			final_pose[bone] = to_world * skel.get_bone_global_pose(bone)


func _take_snapshot(skel: Skeleton3D) -> void:
	var current := Engine.get_physics_frames()
	if current == _frame:
		return
	_frame = current
	_base.clear()
	for side: StringName in _legs:
		var leg: Dictionary = _legs[side]
		_base[side] = {
			"hip": skel.get_bone_global_pose(int(leg["hip"])),
			"knee": skel.get_bone_global_pose(int(leg["knee"])),
			"foot": skel.get_bone_global_pose(int(leg["foot"])),
		}
	_update_pelvis_drop(skel)


## How far the pelvis must sink for every planted foot to reach its ground; shifts the cached
## animation poses (pelvis and the legs riding on it) so the solve below sees the lowered body.
func _update_pelvis_drop(skel: Skeleton3D) -> void:
	var host := player_body.get_parent() as CharacterBody3D if player_body != null else null
	var moving := (host != null
			and Vector2(host.velocity.x, host.velocity.z).length() > still_speed)
	# A jump is motion too (airborne or in a jump clip): the deep standing squat must never fire
	# there - it pushed the pelvis 0.2-0.4 m down and back up frame to frame.
	var jumpish := false
	if jump_counts_as_moving:
		if host != null and (not host.is_on_floor() or absf(host.velocity.y) > JUMP_SPEED_EPSILON):
			moving = true
			jumpish = true
		if (player_body != null and player_body.anim_player != null
				and String(player_body.anim_player.current_animation).contains("jump")):
			moving = true
			jumpish = true
	_is_moving = moving
	var delta := get_physics_process_delta_time()
	_update_body_lag(host, jumpish, delta)
	var needed := _plan_stance(skel, moving, delta)
	# The body is already `_body_lag` below the capsule, which is that much of the drop done.
	needed = maxf(needed - _body_lag, 0.0)
	# A resting foot the leg still could not reach (the plan samples under the ANIMATED ankle, the
	# foot then slides onto a lower tread) asks for that much more drop, held until the next move.
	_stretch_hold = 0.0 if moving else _stretch_hold
	for side: StringName in _legs:
		if not moving and debug_state.get(side, "") == "stretched":
			_stretch_hold = maxf(_stretch_hold, _pelvis_drop + float(
					(debug_solve.get(side, {}) as Dictionary).get("residual", 0.0)))
	needed = minf(maxf(needed, _stretch_hold), max_pelvis_drop)
	if moving:
		needed = minf(needed, moving_pelvis_drop)
	# Moving, the drop is a slow low-pass (a fast attack bobbed the body once per stair step); at
	# rest it stays fast. Only the ATTACK is slowed - a slow release left a 0.23 m squat in a jump.
	var attack := moving_pelvis_rate if moving else pelvis_attack_speed
	var release := pelvis_release_speed
	if needed > _pelvis_drop:
		_pelvis_drop = minf(needed, _pelvis_drop + attack * delta)
	else:
		_pelvis_drop = maxf(needed, _pelvis_drop - release * delta)
	debug_pelvis_drop = _pelvis_drop
	if _hips_bone < 0:
		return
	_hips_base = skel.get_bone_global_pose(_hips_bone)
	var total_drop := _pelvis_drop + _body_lag
	if total_drop <= 0.0005:
		return
	var shift := -(skel.global_transform.basis.inverse() * Vector3.UP).normalized() * total_drop
	_hips_base.origin += shift
	for side: StringName in _legs:
		for key: String in ["hip", "knee", "foot"]:
			var pose := (_base[side] as Dictionary)[key] as Transform3D
			pose.origin += shift
			(_base[side] as Dictionary)[key] = pose


## How far the VISIBLE body trails below the capsule (which pops a whole tread in 2-3 frames): a
## first-order lag, never above it, capped, snapping when airborne or jumping.
func _update_body_lag(host: CharacterBody3D, jumpish: bool, delta: float) -> void:
	if not body_smooth or host == null:
		_body_lag = 0.0
		_smoothed_y = NAN
		debug_body_lag = 0.0
		return
	var root_y := host.global_position.y
	if is_nan(_smoothed_y) or jumpish or absf(root_y - _smoothed_y) > BODY_LAG_SNAP:
		_smoothed_y = root_y
	else:
		_smoothed_y += (root_y - _smoothed_y) * (1.0 - exp(-body_follow_rate * delta))
		_smoothed_y = clampf(_smoothed_y, root_y - body_max_lag, root_y)
	_body_lag = root_y - _smoothed_y
	debug_body_lag = _body_lag


## How each foot and the pelvis cope with a floor the flat-ground animation cannot reach: at rest
## a foot may be brought IN first (`_stance_shift`), the pelvis drops by whatever is left.
func _plan_stance(skel: Skeleton3D, moving: bool, delta: float) -> float:
	var to_world := skel.global_transform
	var worst := 0.0
	for side: StringName in _legs:
		var chosen := 0.0
		var drop := _foot_drop(to_world, side, 0.0)
		var tried: Array = [[0.0, drop]]
		debug_stance_plan[side] = tried
		var current := float(_stance_shift.get(side, 0.0))
		var keep := INF
		if not moving and drop > SOFT_PELVIS_DROP and current > 0.0:
			# A shift that still gets the foot within reach is kept: the search below flips between 5 cm
			# candidates as the idle animation nudges the foot, and each flip snapped the planted foot.
			keep = _foot_drop(to_world, side, current)
			if keep <= SOFT_PELVIS_DROP:
				chosen = current
				drop = keep
		if not moving and drop > SOFT_PELVIS_DROP and max_stance_shift > 0.0:
			var best_drop := drop
			var shift := STANCE_SHIFT_STEP
			while shift <= max_stance_shift + 0.0001:
				var candidate := _foot_drop(to_world, side, shift)
				tried.append([shift, candidate])
				if candidate < best_drop:
					best_drop = candidate
					chosen = shift
				if candidate <= SOFT_PELVIS_DROP:
					break
				shift += STANCE_SHIFT_STEP
			drop = best_drop
		var held := maxf(chosen, current - STANCE_RELEASE_SPEED * delta)
		_stance_shift[side] = held
		debug_stance_shift[side] = held
		worst = maxf(worst, drop)
	return minf(worst, max_pelvis_drop)


## The vertical drop THIS foot needs to be within the leg's reach, ankle brought `shift` m toward
## the hip. 0 for a foot mid-swing, with no floor, too steep to stand on, or already reaching.
func _foot_drop(to_world: Transform3D, side: StringName, shift: float) -> float:
	if max_pelvis_drop <= 0.0:
		return 0.0
	var leg: Dictionary = _legs[side]
	var base: Dictionary = _base[side]
	var animated_ankle: Vector3 = (to_world * (base["foot"] as Transform3D)).origin
	# the character's own floor level (the skeleton sits on the capsule)
	if animated_ankle.y - to_world.origin.y > ankle_height + PELVIS_PLANTED_TOLERANCE:
		return 0.0
	var hip_world: Vector3 = (to_world * (base["hip"] as Transform3D)).origin
	var sample := animated_ankle + _inward(animated_ankle, hip_world) * shift
	# Sample from the ankle ALREADY lowered by the held drop, as _place_foot does: plausibility
	# (`max_surface_drop`) depends on that height and the un-lowered sample flipped it.
	sample.y -= _pelvis_drop + _body_lag
	var hit := _ground_hit(sample, hip_world)
	if hit.is_empty() or not _is_walkable(hit["normal"] as Vector3):
		return 0.0
	var target := (hit["position"] as Vector3) + (hit["normal"] as Vector3) * ankle_height
	# _place_foot re-aims at the floor under the LANDED foot (a few cm lower on a steep slope): plan
	# for the target the foot will really end up chasing.
	var again := _ground_hit(target, hip_world)
	if not again.is_empty() and _is_walkable(again["normal"] as Vector3):
		var moved := (again["position"] as Vector3).y - (hit["position"] as Vector3).y
		if absf(moved) >= 0.005:
			target = (again["position"] as Vector3) + (again["normal"] as Vector3) * ankle_height
	var to_hip := hip_world - animated_ankle.lerp(target, weight)
	# Aim for just inside the reach: landing exactly on it made the reach check in _place_foot flip
	# to `out_of_reach` on rounding, dropping the pelvis but still releasing the foot.
	var reach := float(leg["upper"]) + float(leg["lower"]) - PELVIS_REACH_MARGIN
	var excess := to_hip.length_squared() - reach * reach
	if excess <= 0.0:
		return 0.0
	# Smallest straight-down move of the hip that brings the target within reach.
	var discriminant := to_hip.y * to_hip.y - excess
	return to_hip.y if discriminant < 0.0 else to_hip.y - sqrt(discriminant)


## Horizontal unit vector from the ankle toward the hip: the direction a foot is brought in.
static func _inward(ankle: Vector3, hip: Vector3) -> Vector3:
	var flat := Vector3(hip.x - ankle.x, 0.0, hip.z - ankle.z)
	return flat.normalized() if flat.length_squared() > 0.000001 else Vector3.ZERO


## Floor height under the animated foot, filtered: at a tread's edge the ray flips treads every
## frame (0.15-0.21 m jumps). HIGHER taken at once; LOWER only after it persists, then rate-limited.
func _filtered_ground_height(side: StringName, raw: float) -> float:
	if not ground_filter:
		return raw
	var frame_now := Engine.get_physics_frames()
	if int(_ground_frame.get(side, -1)) == frame_now:
		return float(_ground_state.get(side, raw))
	_ground_frame[side] = frame_now
	_ground_raw[side] = raw
	if not _ground_state.has(side):
		_ground_state[side] = raw
		return raw
	var state: float = _ground_state[side]
	var gap := absf(raw - state)
	if gap <= GROUND_FOLLOW or gap > GROUND_SNAP or raw > state:
		# a slope, a landing/teleport, or a HIGHER tread (believing that one late clips the toe);
		# ignoring a flicker DOWN only holds the foot a few frames higher.
		_ground_state[side] = raw
		_ground_pending.erase(side)
		return raw
	# A different tread level: only believe it once it has been the answer for GROUND_HOLD_FRAMES
	# frames in a row, so a foot straddling an edge (0.20, 0.00, 0.20, ...) keeps the level it had.
	var pending: Dictionary = _ground_pending.get(side, {})
	if not pending.is_empty() and absf(raw - float(pending["level"])) <= GROUND_SAME_LEVEL:
		pending["count"] = int(pending["count"]) + 1
	else:
		pending = {"level": raw, "count": 1}
	_ground_pending[side] = pending
	if int(pending["count"]) >= GROUND_HOLD_FRAMES:
		_ground_state[side] = move_toward(state, raw, GROUND_RATE / 60.0)
	return float(_ground_state[side])


## The re-sample under the LANDED foot: the filtered first sample plus the slope-sized rise or
## fall between the two sample points - a tread flip contributes nothing.
func _filtered_resample(side: StringName, again_y: float) -> float:
	if not ground_filter or not _ground_state.has(side):
		return again_y
	var difference := again_y - float(_ground_raw.get(side, again_y))
	if absf(difference) > GROUND_FOLLOW:
		difference = 0.0
	return float(_ground_state[side]) + difference


## Mid-swing only when high above the sampled ground AND above the character's own floor level - a
## planted foot can sit well over `max_lift` above DOWNHILL ground and must still be reached to.
func _is_swinging(animated_ankle: Vector3, ground_y: float, floor_y: float) -> bool:
	return (animated_ankle.y - ground_y > max_lift
			and animated_ankle.y - floor_y > ankle_height + PELVIS_PLANTED_TOLERANCE)


func _place_foot(skel: Skeleton3D, side: StringName, leg: Dictionary) -> void:
	var base: Dictionary = _base[side]
	# Bone poses are skeleton-relative: ground queries go through the skeleton's own transform.
	var to_world := skel.global_transform
	var animated_ankle: Vector3 = (to_world * (base["foot"] as Transform3D)).origin
	var hip_world: Vector3 = (to_world * (base["hip"] as Transform3D)).origin
	debug_animated_ankle[side] = animated_ankle
	# A foot brought in toward the body at rest (see _plan_stance) is aimed at the floor under its
	# NEW position, so a steep slope's higher ground is what the leg reaches for.
	var shift := float(_stance_shift.get(side, 0.0))
	var sample := animated_ankle + _inward(animated_ankle, hip_world) * shift
	var hit := _ground_hit(sample, hip_world)
	if hit.is_empty():
		debug_skip_reason[side] = "no_ground"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	var ground: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	ground.y = _filtered_ground_height(side, ground.y)
	debug_ground[side] = ground
	var collider := hit.get("collider") as Node
	debug_surface[side] = String(collider.name) if collider != null else ""
	if not _is_walkable(normal):
		debug_skip_reason[side] = "not_walkable"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	var target := ground + normal * ankle_height
	# A foot well above the sampled ground is mid-swing. One at or below is corrected, even onto a
	# surface ABOVE it (stepping onto a ramp) - that is the case the animation clips.
	var swinging := _is_swinging(animated_ankle, ground.y, to_world.origin.y)
	# How firmly this foot is planted, from how far the ANIMATION has lifted it above the character's
	# floor level: 1 planted, fading to 0 as it swings (a hard switch snapped a pinned foot 30 cm).
	var lift := animated_ankle.y - to_world.origin.y - ankle_height
	var wanted := 1.0 - smoothstep(PLANT_FADE_START, PLANT_FADE_END, lift) if plant_fade else 1.0
	if swinging:
		wanted = 0.0
	# The animation can lift a foot ~10 cm in a frame at toe-off, faster than the fade above, so the
	# weight itself is rate-limited too: a planted foot cannot drop from full IK to none in one go.
	var plant: float = _plant_state.get(side, wanted)
	var frame_now := Engine.get_physics_frames()
	if plant_fade and int(_plant_frame.get(side, -1)) != frame_now:
		plant = move_toward(plant, wanted, PLANT_RATE / 60.0)
		_plant_state[side] = plant
		_plant_frame[side] = frame_now
	_plant_weight[side] = plant
	debug_plant_weight[side] = plant
	# A swinging foot is handed back only once its correction has faded out: an immediate release
	# snapped a foot pinned on a lower tread 20-30 cm to the animation in one frame.
	if swinging and (not plant_fade or plant <= PLANT_RELEASE_BELOW):
		debug_skip_reason[side] = "mid_swing"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	var blended := to_world.affine_inverse() * animated_ankle.lerp(target, weight * plant)
	var hip_local: Vector3 = (base["hip"] as Transform3D).origin
	var reach := float(leg["upper"]) + float(leg["lower"]) - 0.001
	debug_reach_check[side] = {"hip_to_target": hip_local.distance_to(blended), "reach": reach}
	var clamped := false
	if hip_local.distance_to(blended) > reach:
			# A TRAILING foot (plant faded below full) that cannot reach should STEP, not stretch:
			# clamping instead drives the knee straight and skates the shoe.
		var trailing := plant < reach_clamp_plant_min
		if trailing or (_is_moving and not reach_when_moving) or not reach_when_still:
			debug_skip_reason[side] = "out_of_reach"
			debug_target.erase(side)
			debug_state[side] = "released"
			return
		# Standing on a planted foot whose floor is beyond the leg's reach even after the maximum
		# pelvis drop: reach as far as the leg goes rather than hang in the air (solver clamps).
		clamped = true
	debug_target[side] = target
	debug_skip_reason[side] = "reach_clamped" if clamped else ""
	debug_animated_ankle[side] = animated_ankle
	debug_ground[side] = ground
	_solve(skel, leg, base, blended, side)
	_align_foot(skel, leg, normal, side)
	# The surface was sampled under the ANIMATED foot but the foot lands elsewhere (on a ramp the
	# height changes with position): re-sample under the foot that resulted and correct once.
	_resample_and_correct(skel, leg, base, hip_world, side)
	_flatten_support(skel, leg, base, to_world, hip_world, side)
	debug_toe_lift[side] = 0.0
	_clear_toe(skel, leg, base, to_world, hip_world, side)
	var landed: Vector3 = skel.get_bone_global_pose(int(leg["foot"])).origin
	# How far the foot ended from the FINAL target (after the resample, retreat, lift), not the
	# first blended one - grading against the stale target read every corrected foot as a miss.
	var final_target: Vector3 = to_world.affine_inverse() * (debug_target[side] as Vector3)
	var miss := landed.distance_to(final_target)
	debug_solve[side]["residual"] = miss
	debug_solve[side]["clamped"] = clamped
	debug_state[side] = "at_target" if miss <= 0.02 else "stretched"
	debug_ground_normal[side] = normal


## Lay the sole on the sampled surface (rotate so it points along the surface normal); without it
## a ramp keeps the shoe level while the ground tilts, cutting the toe or heel into the slope.
func _align_foot(skel: Skeleton3D, leg: Dictionary, normal: Vector3,
		side: StringName) -> void:
	var foot := int(leg["foot"])
	var pose := skel.get_bone_global_pose(foot)
	var sole_local := leg["sole_local"] as Vector3
	var sole := (pose.basis * sole_local).normalized()
	# The normal is a world direction and the pose is skeleton-relative; compare in skeleton space.
	var local_normal := (skel.global_transform.basis.orthonormalized().inverse() * normal).normalized()
	var want := -local_normal
	var record := {"before_deg": rad_to_deg(sole.angle_to(want)), "after_deg": -1.0, "applied": false,
			"reason": ""}
	if normal.dot(Vector3.UP) < 0.5:
		record["reason"] = "too_steep"
		debug_align[side] = record
		return
	if sole.dot(want) < -0.999:
		record["reason"] = "opposite"
		debug_align[side] = record
		return
	var blended := Quaternion.IDENTITY.slerp(Quaternion(sole, want),
			weight * float(_plant_weight.get(side, 1.0)))
	if blended.get_angle() >= 0.0001:
		pose.basis = Basis(blended) * pose.basis
		skel.set_bone_global_pose(foot, pose)
		record["applied"] = true
	record["after_deg"] = rad_to_deg(
			(pose.basis * sole_local).normalized().angle_to(want))
	debug_align[side] = record


## Toe clearance: a flat-aligned foot can still leave the TOE under the surface. Raise by the
## penetration and re-place, resampling each pass (one fix can move it onto a different surface).
func _clear_toe(skel: Skeleton3D, leg: Dictionary, base: Dictionary, to_world: Transform3D,
		hip_world: Vector3, side: StringName) -> void:
	var retreats := 0
	for attempt in CLEAR_ATTEMPTS:
		var foot_pose := skel.get_bone_global_pose(int(leg["foot"]))
		var sole := (foot_pose.basis * (leg["sole_local"] as Vector3)).normalized()
		var toe_world: Vector3 = (to_world * skel.get_bone_global_pose(int(leg["toe"]))).origin
		var toe_point := toe_world + sole * float(leg["toe_depth"])
		# Three contact points can go under a slope: toe sole point, tip further forward, heel - the
		# toe alone missed the tip downhill and the heel uphill.
		var forward := (toe_world - (to_world * foot_pose).origin).normalized()
		var points: Array[Vector3] = [toe_point, toe_point + forward * TOE_TIP_FORWARD,
				(to_world * foot_pose) * (leg["heel_local"] as Vector3)]
		var penetration := 0.0
		var min_gap := INF # smallest FLOATING distance across the three points (>=0 = touching)
		for point: Vector3 in points:
			var hit := _ray(point, hip_world)
			if not hit.is_empty():
				var delta: float = (hit["position"] as Vector3).y - point.y
				penetration = maxf(penetration, delta)
				min_gap = minf(min_gap, -delta)
		if penetration <= 0.002:
			# The three checked (rigid, rest-offset) points are clear, but the real GPU-skinned
			# sole can still sit a few mm above the floor between them. At rest only.
			if not _is_moving:
				_sink_to_true_sole(skel, side, leg, base, to_world, hip_world)
			return
		var target: Vector3 = debug_target.get(side, toe_point) as Vector3
		if penetration > RISER_PENETRATION and retreats < RISER_MAX_RETREATS:
			retreats += 1
			# A point "under" a tread more than a few cm higher is poking into a RISER, not a slope;
			# lifting onto that tread left the heel floating a step up - retreat instead.
			var flat := Vector3(forward.x, 0.0, forward.z)
			if flat.length_squared() > 0.000001:
				target -= flat.normalized() * RISER_RETREAT_STEP
				debug_target[side] = target
				_solve(skel, leg, base, to_world.affine_inverse() * target, side)
				_align_foot(skel, leg, debug_ground_normal.get(side, Vector3.UP), side)
				continue
		target.y += penetration
		debug_toe_lift[side] = float(debug_toe_lift.get(side, 0.0)) + penetration
		debug_target[side] = target
		_solve(skel, leg, base, to_world.affine_inverse() * target, side)
		_align_foot(skel, leg, debug_ground_normal.get(side, Vector3.UP), side)


## Land the WHOLE sole on one flat surface (stairs often straddle a riser). Three sole points are
## sampled; if not one plane, the foot slides along its length, smallest shift first. Planted only.
func _flatten_support(skel: Skeleton3D, leg: Dictionary, base: Dictionary, to_world: Transform3D,
		hip_world: Vector3, side: StringName) -> void:
	debug_support_shift[side] = 0.0
	if not support_snap or float(_plant_weight.get(side, 1.0)) < SUPPORT_MIN_PLANT:
		return
	var foot_world := to_world * skel.get_bone_global_pose(int(leg["foot"]))
	var toe_world := (to_world * skel.get_bone_global_pose(int(leg["toe"]))).origin
	var forward := Vector3(toe_world.x - foot_world.origin.x, 0.0, toe_world.z - foot_world.origin.z)
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var heel: Vector3 = foot_world * (leg["heel_local"] as Vector3)
	var tip := toe_world + forward * TOE_TIP_FORWARD
	var points: Array[Vector3] = [heel, (heel + tip) * 0.5, tip]
	var normal: Vector3 = debug_ground_normal.get(side, Vector3.UP)
	# height change per metre along the foot, so a ramp's own slope is not read as a step
	var slope := -(normal.x * forward.x + normal.z * forward.z) / maxf(normal.y, 0.2)
	var shift := _wanted_support_shift(points, foot_world.origin, forward, slope, hip_world,
			float(_support_last.get(side, 0.0)), (debug_ground.get(side, Vector3.ZERO) as Vector3).y)
	_support_last[side] = shift
	if shift != 0.0:
		var target: Vector3 = debug_target.get(side, foot_world.origin) as Vector3
		target += forward * shift
		debug_target[side] = target
		debug_support_shift[side] = shift
		_solve(skel, leg, base, to_world.affine_inverse() * target, side)
		_align_foot(skel, leg, normal, side)
		_resample_and_correct(skel, leg, base, hip_world, side)
		for index in points.size():
			points[index] += forward * shift
	if not _is_moving:
		_sink_to_sole_level(skel, leg, base, to_world, points, side)


## At rest, a sole flat on ONE surface well below the aimed-at height is a foot hanging over a lower
## tread (the ground filter ignores such a resample; three agreeing sole points are not a flip).
func _sink_to_sole_level(skel: Skeleton3D, leg: Dictionary, base: Dictionary,
		to_world: Transform3D, points: Array[Vector3], side: StringName) -> void:
	var ground: Vector3 = debug_ground.get(side, Vector3.ZERO)
	var normal: Vector3 = debug_ground_normal.get(side, Vector3.UP)
	var hip_world := (to_world * (base["hip"] as Transform3D)).origin
	var lowest := INF
	var highest := -INF
	for point: Vector3 in points:
		var hit := _ray(point, hip_world)
		if hit.is_empty():
			return
		lowest = minf(lowest, (hit["position"] as Vector3).y)
		highest = maxf(highest, (hit["position"] as Vector3).y)
	if highest - lowest > SUPPORT_TOLERANCE or normal.y < 0.95 or ground.y - highest < SINK_MIN:
		return
	ground.y = highest
	debug_ground[side] = ground
	_ground_state[side] = highest
	# straight down from where the foot IS (not the animated spot the ground was first sampled at)
	var landed: Vector3 = (to_world * skel.get_bone_global_pose(int(leg["foot"]))).origin
	var target := Vector3(landed.x, highest + ankle_height, landed.z)
	debug_target[side] = target
	_solve(skel, leg, base, to_world.affine_inverse() * landed.lerp(
			target, weight * float(_plant_weight.get(side, 1.0))), side)
	_align_foot(skel, leg, normal, side)


## The smallest slide (0 when flat) that puts the whole sole on one surface; kept while it still
## works (re-searching flipped 2 cm candidates); prefers the surface AIMED at (`aim_y`).
func _wanted_support_shift(points: Array[Vector3], ankle: Vector3, forward: Vector3, slope: float,
		hip_world: Vector3, previous: float, aim_y: float) -> float:
	if previous != 0.0 and _support_spread(points, ankle, forward, slope, previous,
			hip_world) <= SUPPORT_TOLERANCE and absf(_spread_level - aim_y) <= SINK_MIN:
		return previous
	if _support_spread(points, ankle, forward, slope, 0.0, hip_world) <= SUPPORT_TOLERANCE:
		return 0.0
	var fallback := 0.0
	for step in range(1, int(support_search / SUPPORT_STEP) + 1):
		for direction: float in [1.0, -1.0]:
			var shift: float = direction * float(step) * SUPPORT_STEP
			if _support_spread(points, ankle, forward, slope, shift, hip_world) > SUPPORT_TOLERANCE:
				continue
			if absf(_spread_level - aim_y) <= SINK_MIN:
				return shift
			fallback = fallback if fallback != 0.0 else shift
	return fallback


## How far the surface under the sole's points departs from one plane when slid `shift` m along
## its length: spread of each point's height minus what the slope alone gives. No ground = a step.
func _support_spread(points: Array[Vector3], ankle: Vector3, forward: Vector3, slope: float,
		shift: float, hip_world: Vector3) -> float:
	var lowest := INF
	var highest := -INF
	for point: Vector3 in points:
		var moved := point + forward * shift
		var hit := _ray(moved, hip_world)
		if hit.is_empty():
			return INF
		var along := (moved - ankle).dot(forward)
		var deviation := (hit["position"] as Vector3).y - slope * along
		lowest = minf(lowest, deviation)
		highest = maxf(highest, deviation)
	_spread_level = highest
	return highest - lowest


## One correction pass from the surface under the RESULTING foot position (see the caller).
func _resample_and_correct(skel: Skeleton3D, leg: Dictionary, base: Dictionary,
		hip_world: Vector3, side: StringName) -> void:
	var to_world := skel.global_transform
	var landed_world: Vector3 = (to_world * skel.get_bone_global_pose(int(leg["foot"]))).origin
	var again := _ground_hit(landed_world, hip_world)
	if again.is_empty():
		return
	var normal: Vector3 = again["normal"]
	if not _is_walkable(normal):
		return
	# The same filter as the first sample: the re-sample under the landed foot flipped between treads
	# too, and re-aiming at each flip undid the filtering (the foot still jumped 0.15-0.2 m).
	var again_position: Vector3 = again["position"]
	again_position.y = _filtered_resample(side, again_position.y)
	var moved := again_position.y - (debug_ground.get(side, landed_world) as Vector3).y
	if absf(moved) < 0.005:
		return
	debug_ground[side] = again_position
	debug_ground_normal[side] = normal
	var target := again_position + normal * ankle_height
	debug_target[side] = target
	var blended := to_world.affine_inverse() * (
			landed_world.lerp(target, weight * float(_plant_weight.get(side, 1.0))))
	_solve(skel, leg, base, blended, side)
	_align_foot(skel, leg, normal, side)


func _is_walkable(normal: Vector3) -> bool:
	var limit := fallback_floor_max_angle_deg
	var body := player_body.get_parent() as CharacterBody3D if player_body != null else null
	if body != null:
		limit = rad_to_deg(body.floor_max_angle)
	return normal.dot(Vector3.UP) >= cos(deg_to_rad(limit))


func _ground_hit(ankle: Vector3, hip: Vector3) -> Dictionary:
	var hit := _ray(ankle, hip)
	if _plausible(hit, ankle):
		return hit
	# Near an edge the straight-down ray finds the ground far BELOW instead of the stance surface;
	# take the first inward probe (toward the body) that lands on a plausible one.
	var root := hip
	if player_body != null and player_body.get_parent() is Node3D:
		root = (player_body.get_parent() as Node3D).global_position
	var inward := Vector3(root.x - ankle.x, 0.0, root.z - ankle.z)
	if inward.length_squared() < 0.0001:
		return hit
	inward = inward.normalized()
	for step: float in [0.04, 0.08, 0.12, 0.18, 0.26]:
		var candidate := _ray(ankle + inward * step, hip)
		if _plausible(candidate, ankle):
			return candidate
	return hit


func _ray(point: Vector3, hip: Vector3) -> Dictionary:
	var space := get_skeleton().get_world_3d().direct_space_state
	if space == null:
		return {}
	var top := Vector3(point.x, maxf(hip.y, point.y + ray_up), point.z)
	var query := PhysicsRayQueryParameters3D.create(
			top, point - Vector3.UP * ray_down, ground_mask)
	var body := player_body.get_parent() as CollisionObject3D
	if body != null:
		query.exclude = [body.get_rid()]
	return space.intersect_ray(query)


func _plausible(hit: Dictionary, anchor: Vector3) -> bool:
	if hit.is_empty():
		return false
	return anchor.y - (hit["position"] as Vector3).y <= max_surface_drop


## Analytic two-bone solve: aim the upper bone at the knee and the lower at the ankle target. The
## maths lives in FootIKV2Solver (testable without a scene); this only applies bone poses.
func _solve(skel: Skeleton3D, leg: Dictionary, base: Dictionary, target: Vector3,
		side: StringName) -> void:
	var hip_pos: Vector3 = (base["hip"] as Transform3D).origin
	debug_solve[side] = {
		"reach": float(leg["upper"]) + float(leg["lower"]) - 0.001,
		"needed": hip_pos.distance_to(target),
		"target_local": target,
	}
	var solved := FootIKV2Solver.solve(
			hip_pos, (base["knee"] as Transform3D).origin, target,
			float(leg["upper"]), float(leg["lower"]), leg["rest_pole"] as Vector3)
	_aim(skel, int(leg["hip"]), int(leg["knee"]), solved["knee"] as Vector3)
	_aim(skel, int(leg["knee"]), int(leg["foot"]), solved["ankle"] as Vector3)
	# What the solver asked for vs where the chain actually put the foot: a mismatch here is the
	# aim step, not the maths.
	debug_solve[side]["solved_ankle"] = solved["ankle"] as Vector3
	debug_solve[side]["knee_target"] = solved["knee"] as Vector3
	debug_solve[side]["landed"] = skel.get_bone_global_pose(int(leg["foot"])).origin
	debug_solve[side]["landed_knee"] = skel.get_bone_global_pose(int(leg["knee"])).origin


## How far the lowest foot-mesh vertex sits below the foot bone at rest (falls back to the bone's
## own rest height if the mesh cannot be read).
func _measure_sole_depth(skel: Skeleton3D, side: StringName, foot: int) -> float:
	var foot_rest := skel.get_bone_global_rest(foot)
	var lowest := INF
	for point: Vector3 in _eval_sole_points(skel, side, false):
		lowest = minf(lowest, point.y)
	if not is_finite(lowest):
		return foot_rest.origin.y
	return foot_rest.origin.y - lowest


## The rearmost sole-level point of the foot mesh, in the FOOT BONE's rest space (rides the bone
## at any pose). "Sole level" is the lowest 4 cm; rearmost along the foot's forward axis.
func _measure_heel_local(skel: Skeleton3D, side: StringName, foot: int, toe: int) -> Vector3:
	var points := _eval_sole_points(skel, side, false)
	var foot_rest := skel.get_bone_global_rest(foot)
	if points.is_empty() or toe < 0:
		return Vector3.ZERO
	var forward := skel.get_bone_global_rest(toe).origin - foot_rest.origin
	forward.y = 0.0
	forward = forward.normalized()
	var lowest := INF
	for point: Vector3 in points:
		lowest = minf(lowest, point.y)
	var heel := foot_rest.origin
	var rearmost := INF
	for point: Vector3 in points:
		if point.y > lowest + HEEL_SOLE_BAND:
			continue
		var along := point.dot(forward)
		if along < rearmost:
			rearmost = along
			heel = point
	heel.y = lowest # the contact point straight below the back of the heel, on the sole
	return foot_rest.affine_inverse() * heel


## At rest, lower until the true lowest point of the skinned sole (`live` mesh walk) is
## `SOLE_GAP_TOLERANCE` off the floor - the rigid rest-offset clear/heel points miss a GPU blend.
func _sink_to_true_sole(skel: Skeleton3D, side: StringName, leg: Dictionary, base: Dictionary,
		to_world: Transform3D, hip_world: Vector3) -> void:
	var t0 := FootIKV2Debug.begin()
	_sink_to_true_sole_impl(skel, side, leg, base, to_world, hip_world)
	FootIKV2Debug.end(&"sink", t0)


func _sink_to_true_sole_impl(skel: Skeleton3D, side: StringName, leg: Dictionary, base: Dictionary,
		to_world: Transform3D, hip_world: Vector3) -> void:
	for attempt in SOLE_SINK_ATTEMPTS:
		var lowest := INF
		var lowest_point := Vector3.ZERO
		for point: Vector3 in _eval_sole_points(skel, side, true):
			var world := to_world * point
			if world.y < lowest:
				lowest = world.y
				lowest_point = world
		if not is_finite(lowest):
			return
		var hit := _ray(lowest_point, hip_world)
		if hit.is_empty():
			return
		var gap: float = lowest - (hit["position"] as Vector3).y
		if gap <= SOLE_GAP_TOLERANCE:
			return
		var target: Vector3 = debug_target.get(side, lowest_point) as Vector3
		target.y -= gap - SOLE_GAP_TOLERANCE
		debug_target[side] = target
		_solve(skel, leg, base, to_world.affine_inverse() * target, side)
		_align_foot(skel, leg, debug_ground_normal.get(side, Vector3.UP), side)


## Per-bone contributions of every foot-mesh vertex on the foot/toe bone, cached ONCE per leg (the
## walk below cost ~8ms/call). Replayed cheaply at rest or the current pose by `_eval_sole_points`.
func _cache_sole_vertices(skel: Skeleton3D, foot: int, toe: int) -> Array:
	var cached: Array = []
	if player_body == null or not is_instance_valid(player_body.character):
		return cached
	for node: Node in player_body.character.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part == null or part.mesh == null or part.get_skin_reference() == null:
			continue
		var skin := part.get_skin_reference().get_skin()
		if skin == null:
			continue
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
			var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var influences := bones.size() / vertices.size()
			for vertex in vertices.size():
				var contribs: Array = []
				var total := 0.0
				for influence in influences:
					var slot := vertex * influences + influence
					var bind := bones[slot]
					var weight := weights[slot]
					if weight <= 0.0 or bind < 0 or bind >= skin.get_bind_count():
						continue
					var bone := skin.get_bind_bone(bind)
					if bone < 0:
						bone = skel.find_bone(skin.get_bind_name(bind))
					if bone < 0 or (bone != foot and bone != toe):
						continue
					contribs.append([bone, weight, skin.get_bind_pose(bind) * vertices[vertex]])
					total += weight
				if total > 0.5:
					cached.append({"total": total, "contribs": contribs})
	return cached


## Replay `_cache_sole_vertices`' contributions at rest, or (`live`) the CURRENT bone pose.
func _eval_sole_points(skel: Skeleton3D, side: StringName, live: bool) -> PackedVector3Array:
	var points := PackedVector3Array()
	for entry: Dictionary in _sole_cache.get(side, []) as Array:
		var summed := Vector3.ZERO
		for contrib: Array in entry["contribs"] as Array:
			var bone_pose := skel.get_bone_global_pose(contrib[0]) if live \
					else skel.get_bone_global_rest(contrib[0])
			summed += (bone_pose * (contrib[2] as Vector3)) * float(contrib[1])
		points.append(summed / float(entry["total"]))
	return points


## Rotate `bone` about its own origin so the segment to `child` points at `target`.
func _aim(skel: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var child_pos: Vector3 = skel.get_bone_global_pose(child).origin
	var from := child_pos - pose.origin
	var to := target - pose.origin
	if from.length_squared() < 0.0000001 or to.length_squared() < 0.0000001:
		return
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skel.set_bone_global_pose(bone, pose)
