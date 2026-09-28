class_name FootIKV2Modifier
extends SkeletonModifier3D
## v2 foot IK - flat ground first. For each leg: sample the ground under the animated foot, then
## solve the hip -> knee -> ankle chain analytically so the ankle sits on it.
##
## Deliberately small. v1 (actors/player/foot_ik/) grew to 20 modules and ~6.8k lines because every
## new symptom got its own layer; v2 adds one behaviour at a time, each with its own check, and the
## acceptance scene lives beside it. No stairs, no swing prediction, no validation/retry layers yet.

## Role names are the character's humanoid roles, resolved through PlayerBody (same as v1) so this
## works on any catalog character.
const LEGS := {
	&"left": {"hip": &"LeftUpLeg", "knee": &"LeftLeg", "foot": &"LeftFoot",
		"toe": &"LeftToeBase"},
	&"right": {"hip": &"RightUpLeg", "knee": &"RightLeg", "foot": &"RightFoot",
		"toe": &"RightToeBase"},
}

@export var enabled := true
## Physics layers the ground is on: 1 = world, 6 = the project's authored contact surfaces
## (1 << 5), matching v1's GROUND_COLLISION_MASK. Looking only at layer 1 misses authored
## stairs/ramps entirely.
@export_flags_3d_physics var ground_mask := 1 | (1 << 5)
## Fallback floor limit when the character is not a CharacterBody3D. A hit steeper than this is not
## a floor (a wall or a riser) and is left to the animation, like v1's require_walkable check.
@export var fallback_floor_max_angle_deg := 46.0
## A sampled surface this far BELOW the foot is not the foot's floor (the ground under a ledge, the
## floor past a ramp edge): re-probe inward toward the body before believing it. One stair riser is
## ~0.35, so this sits just above that.
@export var max_surface_drop := 0.45
@export var ray_up := 0.5
@export var ray_down := 1.2
## How far the ankle sits above the sampled ground when the foot is planted. Negative means
## "derive it from the rig's own rest pose", which is the only value that is right for every
## character (this rig's ankle rest is 0.111 m above the floor).
@export var ankle_height := -1.0
## 0 = keep the authored pose, 1 = fully plant on the sampled ground.
@export_range(0.0, 1.0) var weight := 1.0
## When a planted foot's target is past the leg's reach (the downhill foot of a body standing across
## a slope), lower the pelvis by the shortfall - up to this much - so the leg can reach the ground
## instead of the foot being left floating at the flat-ground height. 0 disables it.
@export var max_pelvis_drop := 0.40
## While the character is moving faster than `still_speed` (m/s) the drop is capped much lower: a
## deep squat is right for standing on a steep slope but looks wrong mid-stride (measured: the body
## sank 0.2-0.4 m during ramp strafes).
@export var moving_pelvis_drop := 0.06
@export var still_speed := 0.5
## Jumping (airborne or in a jump clip) counts as moving for the pelvis drop and stance shift.
@export var jump_counts_as_moving := true
## The drop grows at this rate (m/s) and is released at the next one, so the body neither pops down
## when the character stops nor pops back up the moment a foot stops needing it.
@export var pelvis_attack_speed := 1.5
@export var pelvis_release_speed := 0.6
## At rest, a planted foot whose floor is out of reach may be brought this far toward the body
## (horizontally) before the pelvis is asked to sink further: the downhill foot on a steep slope.
## 0 disables it. The pelvis is only lowered for what the stance shift cannot cover, past
## SOFT_PELVIS_DROP.
@export var max_stance_shift := 0.30
## At rest, a planted foot whose floor is still out of reach reaches as far as the leg allows
## instead of being released to hang at the animation's flat-ground height.
@export var reach_when_still := true
## The same while walking: a planted foot briefly out of reach (a stride onto lower ground) reaches
## as far as it can instead of popping to the animation's height for a frame or two.
@export var reach_when_moving := true
const SOFT_PELVIS_DROP := 0.10
const STANCE_SHIFT_STEP := 0.05
const STANCE_RELEASE_SPEED := 0.6
## How far ahead of the toe bone the shoe's tip is (matches the lab's orange/green tip sphere).
const TOE_TIP_FORWARD := 0.035
## A clearance "penetration" bigger than this is a riser, not a slope: retreat instead of lifting.
const RISER_PENETRATION := 0.04
const RISER_RETREAT_STEP := 0.012
## Retreats are tried first; a foot still in the riser after this many is lifted onto the tread
## (a tall step the foot genuinely has to climb), as before.
const RISER_MAX_RETREATS := 4
const CLEAR_ATTEMPTS := 8
## Vertical speed (m/s) above which the character counts as airborne / jumping.
const JUMP_SPEED_EPSILON := 0.5
const PELVIS_REACH_MARGIN := 0.012
## The heel is the rearmost point within this height of the shoe's lowest vertex.
const HEEL_SOLE_BAND := 0.04
## Only a foot the ANIMATION plants (its ankle within this of the character's own floor level) can
## ask for a pelvis drop; a swinging foot is high off that level and must not pull the body down.
const PELVIS_PLANTED_TOLERANCE := 0.05
## A foot lifted more than this above the sampled ground is treated as mid-swing and left to the
## animation. A foot at or below that height is corrected - including onto a surface above it
## (stepping up a ramp), which the animation alone would clip straight through.
@export var max_lift := 0.25

var player_body: PlayerBody
## side -> the target this leg was last corrected toward, and why it was skipped. Exposed so the
## trace logs the REAL decision instead of re-deriving it (a restated condition is where that kind
## of bug hides - see v1's notes).
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
var debug_pelvis_drop := 0.0
var debug_solve: Dictionary = {}
## side -> {hip_to_target, reach}: the reach decision every frame, released or not, so a persistent
## `out_of_reach` can be read off the trace (debug_solve is only written when a solve runs).
var debug_reach_check: Dictionary = {}
## side -> "released" (left to the animation), "at_target" (reached its sampled surface) or
## "stretched" (aimed at it but the leg could not get there). Lets a harness grade only feet that
## are actually meant to be down, without re-deriving that decision itself.
var debug_state: Dictionary = {}
## side -> {"before_deg", "after_deg", "applied"}: how far the sole was from the sampled surface
## normal before the align pass and after it, in the skeleton's own space.
var debug_align: Dictionary = {}

## side -> {"hip", "knee", "foot", "upper", "lower", "rest_pole"}
var _legs: Dictionary = {}
## Base animation poses, captured once per frame before anything is modified. The modifier can be
## evaluated more than once per tick (including delta == 0 refresh passes), so re-deriving from the
## live skeleton on a later pass would read our own output back as if it were the animation.
var _frame := -1
var _base: Dictionary = {}
var _hips_bone := -1
var _hips_base := Transform3D.IDENTITY
var _pelvis_drop := 0.0
var _stance_shift: Dictionary = {}
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
		# Knee bend plane at rest, so a leg whose bend direction is ambiguous still folds forward.
		var sole_depth := _measure_sole_depth(skel, foot,
				skel.find_bone(player_body.resolve_bone_name(roles["toe"])))
		print("[FootIKv2] %s sole_depth=%.4f bone_rest_y=%.4f" % [
				side, sole_depth, foot_rest.y])
		if ankle_height < 0.0:
			# The ankle must sit this high above the ground for the SOLE to touch it. The foot
			# bone's own rest height is not that value (0.111 vs a real sole depth of ~0.096), so
			# it is measured from the skinned foot mesh in the rest pose, which stands on the floor.
			ankle_height = sole_depth
		var rest_direction := (foot_rest - hip_rest).normalized()
		var rest_pole := knee_rest - hip_rest
		rest_pole -= rest_direction * rest_pole.dot(rest_direction)
		_legs[side] = {
			"hip": hip, "knee": knee, "foot": foot,
			"toe": skel.find_bone(player_body.resolve_bone_name(roles["toe"])),
			# The toe bone sits only this far above the sole (the rest pose stands on the floor).
			# It is NOT ankle_height: using that put the toe's "sole point" ~8 cm underground on
			# flat ground, so the clearance pass lifted every foot by the difference.
			"toe_depth": maxf(0.0, skel.get_bone_global_rest(skel.find_bone(
					player_body.resolve_bone_name(roles["toe"]))).origin.y),
			"upper": hip_rest.distance_to(knee_rest),
			"lower": knee_rest.distance_to(foot_rest),
			"rest_pole": rest_pole.normalized(),
			# The sole's downward direction in the foot bone's own space: the rest pose stands on
			# the floor, so world-down at rest IS the sole direction for this rig.
			"sole_local": (skel.get_bone_global_rest(foot).basis.inverse() * Vector3.DOWN).normalized(),
			# The visible heel (rearmost sole-level mesh point) in the foot bone's own space.
			"heel_local": _measure_heel_local(skel, foot,
					skel.find_bone(player_body.resolve_bone_name(roles["toe"]))),
		}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _legs.is_empty():
		return
	if enabled:
		debug_last_frame = Engine.get_physics_frames()
		debug_passes += 1
		_take_snapshot(skel)
		if _pelvis_drop > 0.0005 and _hips_bone >= 0:
			skel.set_bone_global_pose(_hips_bone, _hips_base)
		for side: StringName in _legs:
			_place_foot(skel, side, _legs[side])
	_publish_final_poses(skel)


## The published result: world transforms of the bones a harness or trace cares about, captured at
## the END of this pass (v2 is the last modifier, so this is what gets rendered) and stamped with
## the physics frame. Reading Skeleton3D bones from anywhere else - a node's _process(), or the
## skeleton_updated signal - returned stale or unmodified poses (12 cm+ off for the foot, hips
## "0.6 m too low"). Refreshed whether or not v2 is enabled so an A/B run reads the same way.
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


## Work out how far the pelvis must sink for every planted foot to reach its ground, then shift the
## cached animation poses (pelvis and the leg bones that ride on it) by that amount so the solve
## below sees the lowered body. The pelvis pose itself is re-applied on every pass.
func _update_pelvis_drop(skel: Skeleton3D) -> void:
	var host := player_body.get_parent() as CharacterBody3D if player_body != null else null
	var moving := (host != null
			and Vector2(host.velocity.x, host.velocity.z).length() > still_speed)
	# A jump is motion too: airborne, rising/falling, or in a jump clip (crouch, take-off, landing).
	# The deep standing-still squat must never fire there - it pushed the pelvis 0.2-0.4 m down and
	# back up frame to frame during jumps on a steep ramp.
	if jump_counts_as_moving:
		if host != null and (not host.is_on_floor() or absf(host.velocity.y) > JUMP_SPEED_EPSILON):
			moving = true
		if (player_body != null and player_body.anim_player != null
				and String(player_body.anim_player.current_animation).contains("jump")):
			moving = true
	_is_moving = moving
	var delta := get_physics_process_delta_time()
	var needed := _plan_stance(skel, moving, delta)
	if moving:
		needed = minf(needed, moving_pelvis_drop)
	if needed > _pelvis_drop:
		_pelvis_drop = minf(needed, _pelvis_drop + pelvis_attack_speed * delta)
	else:
		_pelvis_drop = maxf(needed, _pelvis_drop - pelvis_release_speed * delta)
	debug_pelvis_drop = _pelvis_drop
	if _hips_bone < 0:
		return
	_hips_base = skel.get_bone_global_pose(_hips_bone)
	if _pelvis_drop <= 0.0005:
		return
	var shift := -(skel.global_transform.basis.inverse() * Vector3.UP).normalized() * _pelvis_drop
	_hips_base.origin += shift
	for side: StringName in _legs:
		for key: String in ["hip", "knee", "foot"]:
			var pose := (_base[side] as Dictionary)[key] as Transform3D
			pose.origin += shift
			(_base[side] as Dictionary)[key] = pose


## Decide, once per frame, how each planted foot and the pelvis cope with a floor the flat-ground
## animation cannot reach. Two tools, cheapest first: at rest a foot may be brought IN toward the
## body (`_stance_shift`, the way a person narrows their stance on a steep slope, which also raises
## the ground under it), and the pelvis then drops by whatever shortfall is left. Returns that drop.
func _plan_stance(skel: Skeleton3D, moving: bool, delta: float) -> float:
	var to_world := skel.global_transform
	var worst := 0.0
	for side: StringName in _legs:
		var chosen := 0.0
		var drop := _foot_drop(to_world, side, 0.0)
		var tried: Array = [[0.0, drop]]
		debug_stance_plan[side] = tried
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
		var held := maxf(chosen, float(_stance_shift.get(side, 0.0)) - STANCE_RELEASE_SPEED * delta)
		_stance_shift[side] = held
		debug_stance_shift[side] = held
		worst = maxf(worst, drop)
	return minf(worst, max_pelvis_drop)


## The vertical drop THIS foot needs so its target is within the leg's reach, when its ankle is
## brought `shift` metres toward the hip (horizontally). 0 for a foot that is mid-swing, has no
## floor, stands on something too steep to be a floor, or already reaches.
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
	# _place_foot samples from an ankle that is ALREADY lowered by the held pelvis drop, and the
	# floor's plausibility (`max_surface_drop`) depends on that height. Sampling from the higher,
	# unlowered ankle flipped a floor 0.41 m down to "implausible" (limit 0.45) on the frame it was
	# planned, so the plan chased the stair tread the edge probe found instead and asked for no drop.
	sample.y -= _pelvis_drop
	var hit := _ground_hit(sample, hip_world)
	if hit.is_empty() or not _is_walkable(hit["normal"] as Vector3):
		return 0.0
	var target := (hit["position"] as Vector3) + (hit["normal"] as Vector3) * ankle_height
	# _place_foot re-samples the floor under the foot's LANDED position (_resample_and_correct) and
	# re-aims there. On a steep slope the ankle sits ~ankle_height off the surface, so that second
	# floor is several cm lower and further: plan for the target the foot will really end up chasing.
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


## A foot is mid-swing only when it is high above the sampled ground AND lifted above the
## character's own floor level. The second test matters on a steep slope: a foot the animation
## plants (ankle at the character's floor level) can sit well over `max_lift` above the DOWNHILL
## ground - it is planted, just out of the slope's plane, and must be reached to, not released.
func _is_swinging(animated_ankle: Vector3, ground_y: float, floor_y: float) -> bool:
	return (animated_ankle.y - ground_y > max_lift
			and animated_ankle.y - floor_y > ankle_height + PELVIS_PLANTED_TOLERANCE)


func _place_foot(skel: Skeleton3D, side: StringName, leg: Dictionary) -> void:
	var base: Dictionary = _base[side]
	# get_bone_global_pose() is relative to the SKELETON, not the world, so the ground query has to
	# go through the skeleton's own transform or it samples the wrong place as soon as the character
	# is off the origin. Positions are converted back before the solve, which works in skeleton space.
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
	debug_ground[side] = ground
	var collider := hit.get("collider") as Node
	debug_surface[side] = String(collider.name) if collider != null else ""
	if not _is_walkable(normal):
		debug_skip_reason[side] = "not_walkable"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	var target := ground + normal * ankle_height
	# A foot well above the sampled ground is mid-swing; dragging it down to the floor would read
	# as an invisible floor. A foot at or below the expected height is corrected, even when the
	# sampled surface is ABOVE it (stepping onto a ramp) - that is the case the animation clips.
	if _is_swinging(animated_ankle, ground.y, to_world.origin.y):
		debug_skip_reason[side] = "mid_swing"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	# A target the leg cannot reach is not this foot's floor (a tread edge, the floor far below a
	# raised stance): stretching toward it locks the knee straight and floats the shoe. Leave the
	# animation alone instead - it already knows where the foot is.
	var blended := to_world.affine_inverse() * animated_ankle.lerp(target, weight)
	var hip_local: Vector3 = (base["hip"] as Transform3D).origin
	var reach := float(leg["upper"]) + float(leg["lower"]) - 0.001
	debug_reach_check[side] = {"hip_to_target": hip_local.distance_to(blended), "reach": reach}
	var clamped := false
	if hip_local.distance_to(blended) > reach:
		if (_is_moving and not reach_when_moving) or not reach_when_still:
			debug_skip_reason[side] = "out_of_reach"
			debug_target.erase(side)
			debug_state[side] = "released"
			return
		# Standing still on a foot the animation plants, with the real floor beyond the leg's
		# reach even after the pelvis has dropped as far as it may (a foot off the side of a stair
		# over the floor below): reach as far as the leg goes toward that floor rather than hand the
		# foot back to the animation to hang in the air. The solver clamps the distance.
		clamped = true
	debug_target[side] = target
	debug_skip_reason[side] = "reach_clamped" if clamped else ""
	debug_animated_ankle[side] = animated_ankle
	debug_ground[side] = ground
	_solve(skel, leg, base, blended, side)
	_align_foot(skel, leg, normal, side)
	# The surface was sampled under the ANIMATED foot, but the foot lands somewhere else - and on a
	# ramp the height changes with position, so that target can be wrong by the slope's rise over the
	# shift. Re-sample under the foot that actually resulted and correct once (v1: "resample the
	# collider under the new deepest point after every adjustment").
	_resample_and_correct(skel, leg, base, hip_world, side)
	debug_toe_lift[side] = 0.0
	_clear_toe(skel, leg, base, to_world, hip_world, side)
	var landed: Vector3 = skel.get_bone_global_pose(int(leg["foot"])).origin
	# How far the foot ended from the target it was FINALLY chasing (after the resample, the riser
	# retreat and the toe/heel lift), not the first blended one: those corrections moved the target
	# on purpose, and grading against the stale one read every corrected foot as a miss.
	var final_target: Vector3 = to_world.affine_inverse() * (debug_target[side] as Vector3)
	var miss := landed.distance_to(final_target)
	debug_solve[side]["residual"] = miss
	debug_solve[side]["clamped"] = clamped
	debug_state[side] = "at_target" if miss <= 0.02 else "stretched"
	debug_ground_normal[side] = normal


## Lay the sole on the sampled surface: rotate the foot so its sole points into the ground along
## the surface normal. Without it a ramp keeps the shoe level while the ground tilts under it, so
## the toe or heel cuts into the slope.
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
	var blended := Quaternion.IDENTITY.slerp(Quaternion(sole, want), weight)
	if blended.get_angle() >= 0.0001:
		pose.basis = Basis(blended) * pose.basis
		skel.set_bone_global_pose(foot, pose)
		record["applied"] = true
	record["after_deg"] = rad_to_deg(
			(pose.basis * sole_local).normalized().angle_to(want))
	debug_align[side] = record


## Sample the surface this foot should stand on, looking DOWN FROM THE BODY - not from just above
## the animated foot. On a ramp that foot can sit below the slope, and a ray starting at its own
## height never reaches the ramp above it: it hits the floor instead, and the foot is aimed at the
## wrong surface (measured: both feet targeting y=0.086 while the body stood at y=0.95 on a ramp).
## A surface steeper than the character can stand on is a wall or a riser, not this foot's floor.
## v1 gates on require_walkable for the same reason; without it a foot can be aimed at a vertical
## face and driven through it.
## Toe clearance (v1's 025 class): a flat-aligned foot can still leave the shoe's TOE under the
## surface. Raise the ankle target by the toe's penetration and re-place, resampling the surface
## under the toe's new position each pass - one correction can move the offender onto a different
## surface, so reusing the first hit is not enough.
func _clear_toe(skel: Skeleton3D, leg: Dictionary, base: Dictionary, to_world: Transform3D,
		hip_world: Vector3, side: StringName) -> void:
	var retreats := 0
	for attempt in CLEAR_ATTEMPTS:
		var foot_pose := skel.get_bone_global_pose(int(leg["foot"]))
		var sole := (foot_pose.basis * (leg["sole_local"] as Vector3)).normalized()
		var toe_world: Vector3 = (to_world * skel.get_bone_global_pose(int(leg["toe"]))).origin
		var toe_point := toe_world + sole * float(leg["toe_depth"])
		# The shoe has three contact points that can go under a slope: the toe bone's sole point, the
		# shoe's tip a little further forward, and the heel at the back. Grade all three - the toe
		# bone alone missed the tip on a downhill slope and the heel on an uphill one.
		var forward := (toe_world - (to_world * foot_pose).origin).normalized()
		var points: Array[Vector3] = [toe_point, toe_point + forward * TOE_TIP_FORWARD,
				(to_world * foot_pose) * (leg["heel_local"] as Vector3)]
		var penetration := 0.0
		for point: Vector3 in points:
			var hit := _ray(point, hip_world)
			if not hit.is_empty():
				penetration = maxf(penetration, (hit["position"] as Vector3).y - point.y)
		if penetration <= 0.002:
			return
		var target: Vector3 = debug_target.get(side, toe_point) as Vector3
		if penetration > RISER_PENETRATION and retreats < RISER_MAX_RETREATS:
			retreats += 1
			# A point that is "under" a tread more than a few cm higher is not sunk into a slope: it is
			# poking into a RISER (the ray from above finds the next tread's top). Lifting the whole
			# foot onto that tread left the heel floating a full step above its own; slide the foot
			# back off the riser instead and try again.
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
	var moved := (again["position"] as Vector3).y - (debug_ground.get(side, landed_world) as Vector3).y
	if absf(moved) < 0.005:
		return
	debug_ground[side] = again["position"]
	debug_ground_normal[side] = normal
	var target := (again["position"] as Vector3) + normal * ankle_height
	debug_target[side] = target
	var blended := to_world.affine_inverse() * (landed_world.lerp(target, weight))
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
	# Near an edge (a ramp/step the foot is partly past) the straight-down ray finds the ground far
	# BELOW instead of the surface under the stance. v1 recovers by probing inward toward the body;
	# take the first inward probe that lands on a plausible surface.
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


## Analytic two-bone solve: aim the upper bone at the knee position and the lower bone at the ankle
## target. The maths lives in FootIKV2Solver so it can be tested without a scene; this only turns
## the result into bone poses.
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


## How far the lowest foot-mesh vertex sits below the foot bone, in the rest pose. Falls back to the
## bone's own rest height when the mesh cannot be read, so the modifier still runs.
func _measure_sole_depth(skel: Skeleton3D, foot: int, toe: int) -> float:
	var foot_rest := skel.get_bone_global_rest(foot)
	var lowest := INF
	for point: Vector3 in _foot_mesh_points(skel, foot, toe):
		lowest = minf(lowest, point.y)
	if not is_finite(lowest):
		return foot_rest.origin.y
	return foot_rest.origin.y - lowest


## The rearmost sole-level point of the foot mesh, in the FOOT BONE's own rest space, so it rides
## the bone at any pose: the visible heel. "Sole level" is the lowest 4 cm of the shoe; rearmost is
## along the foot's own forward axis (foot bone toward toe bone, flattened to the ground).
## Returns the bone-local origin when the mesh cannot be read.
func _measure_heel_local(skel: Skeleton3D, foot: int, toe: int) -> Vector3:
	var points := _foot_mesh_points(skel, foot, toe)
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


## Rest-pose (skeleton space) positions of every foot-mesh vertex that is mostly weighted to the
## foot or toe bone. Empty when the mesh cannot be read.
func _foot_mesh_points(skel: Skeleton3D, foot: int, toe: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	if player_body == null or not is_instance_valid(player_body.character):
		return points
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
				var summed := Vector3.ZERO
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
					summed += (skel.get_bone_global_rest(bone)
							* skin.get_bind_pose(bind) * vertices[vertex]) * weight
					total += weight
				if total > 0.5:
					points.append(summed / total)
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
