class_name PlayerFootIKModifier
extends SkeletonModifier3D
## Plants each foot on the actual ground/step surface beneath it instead of
## wherever the flat-ground-authored locomotion clips leave it - raycasts
## straight down from each foot's animated position, then bends hip/knee to
## reach that point (closed-form two-bone IK) and tilts the foot to match
## the surface normal. Mirrors player_hand_grip_modifier.gd/
## player_look_pose_modifier.gd: a plain SkeletonModifier3D subclass reading
## and writing bone poses inside _process_modification(), added as a
## skeleton child by PlayerBody. Raycasting needs physics-fresh collision
## state, so PlayerBody switches the skeleton's modifier callback mode to
## MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS (a skeleton-wide setting, shared
## with the other modifiers on the same skeleton) when attaching this one.

## Logs the rest-pose-derived sole axis for each leg once at startup - cheap
## and worth keeping permanently, so a future catalog character whose rig
## has a genuinely different bone-axis convention shows up as a readable log
## line instead of a silent wrong-looking foot.
const LOG_SOLE_AXIS := true

## How far above/below the animated foot position to search for ground.
## The default `ray_down` comfortably covers the tallest single stair riser
## exercised by foot_ik_preview.tscn (0.35m) plus margin for a foot that's
## mid-stride and briefly higher than the tread it's about to land on.
## @export (not const) so a live debug panel can tune these against real
## gameplay instead of guessing values against the static preview scene alone.
@export var ray_up: float = 0.5
@export var ray_down: float = 0.6
## Matches the level geometry collision layer used throughout the project
## (see e.g. player.tscn's own CharacterBody3D collision_mask).
const GROUND_COLLISION_MASK := 1
## Approximate sole thickness/ankle clearance so the ankle doesn't sink
## exactly to the raycast hit point. The foot/toe are no longer forced flat
## (see _compute_new_foot_basis_world's doc comment) - they now preserve
## this idle clip's natural toe-down stance, so the effective ground offset
## actually used per-leg is whichever is larger of this value and the
## predicted toe-tip drop (see _process_modification_with_delta and
## toe_tip_margin below); this is just the floor under that, the minimum
## clearance for a leg whose toe doesn't droop below the ankle at all.
@export var ankle_offset: float = 0.0475
## How far past the toe bone's own origin the visible mesh tip actually
## extends, along the foot-to-toe direction - bone origins sit at joints,
## not at fingertip/toetip mesh extremes, so predicting ground clearance
## from the toe bone's position alone still let the visual mesh clip through
## the floor by a few cm. Matches the debug overlay's own TOE_TIP_EXTRA_LENGTH
## (tests/manual/foot_ik/foot_ik_debug_overlay.gd), which independently
## approximates the same thing for its toe-tip marker.
@export var toe_tip_margin: float = 0.035
## Exponential-smoothing rate for the raycast-derived target/normal, so the
## foot doesn't pop when a hit jumps between two different tread heights
## frame to frame (e.g. right at a step edge).
@export var smooth_rate: float = 14.0
## How fast the *animated*, uncorrected foot is currently rising/falling
## (meters/second) counts as "mid-swing" - the correction blends from full
## strength at 0 speed down to none at this speed, instead of applying
## unconditionally every frame regardless of gait phase. Without this, the
## raycast finds essentially the same ground point under the foot on every
## frame of a walk cycle (most obviously on flat ground, where it finds the
## literal same height every frame), and the leg gets bent to plant there
## even while the animation is trying to lift the foot through the air for
## a step - measured killing a natural ~0.27m walk-cycle foot-height swing
## down to a completely flat, unmoving foot.
##
## Deliberately velocity-based, not height-based: an earlier version blended
## on how far the animated foot sits above its ground target, which broke
## static standing on the taller of two adjacent stair treads (a large but
## perfectly legitimate *static* correction, wrongly read as "mid-swing"
## just because the required correction was large) - a foot that isn't
## currently moving vertically is either standing still or momentarily
## planted between steps, and either way should get full correction
## regardless of how tall that correction needs to be. A foot actively
## swinging through the air, by contrast, has real vertical speed - that's
## the actual distinguishing signal, not distance-to-target.
@export var swing_speed_threshold: float = 0.35
## How much more harshly RISING vertical velocity counts against
## swing_speed_threshold than the same-magnitude FALLING velocity does - see
## the rising-velocity scaling comment in _process_modification_with_delta()
## for why this is a continuous scale-up rather than an outright sign cutoff
## at 0 (a hard cutoff there caused a real, visible twitch on completely
## static idle poses, from ordinary floating-point/animation noise).
@export var rising_penalty: float = 4.0
## Minimum time (seconds) for ground_weight to rise from 0 to 1 - caps how
## fast the correction can snap back ON, without limiting how fast it can
## snap OFF. A walk cycle's vertical velocity crosses exactly zero for a
## single frame at the very top of the swing arc (same as a thrown ball's
## velocity at its apex) - read literally, that one frame looks identical to
## "foot has stopped, must be planted," briefly pulling the foot back down
## toward the ground mid-air before the very next frame's real (non-zero)
## velocity releases it again. Measured as a real, visible dip - not just a
## theoretical edge case - comparing a walking dummy with IK against the raw
## animation frame by frame (e.g. 0.282 vs the animation's own 0.353 at the
## exact peak of one stride). Falling (real swing starting) stays instant,
## since only the rise is capped.
@export var ground_weight_rise_time: float = 0.12

const LEGS := {
	&"left": {"hip": &"LeftUpLeg", "knee": &"LeftLeg", "foot": &"LeftFoot", "toe": &"LeftToeBase"},
	&"right": {
		"hip": &"RightUpLeg", "knee": &"RightLeg", "foot": &"RightFoot", "toe": &"RightToeBase"},
}

var player_body: PlayerBody

var _bone_indices: Dictionary = {} # side -> {hip, knee, foot, toe, leaf: int}
var _leg_lengths: Dictionary = {} # side -> {upper, lower: float}
var _sole_down_local: Dictionary = {} # side -> Vector3, one of the 6 principal axes
## Toe's rest-pose position/orientation relative to the foot, in the foot's
## own rest-pose local space - see _solve_leg's toe section for why this
## (not the toe's *animated* pose) is what the toe gets rigidly rebuilt
## from each frame.
var _toe_rest_offset: Dictionary = {} # side -> Vector3
var _toe_rest_relative_basis: Dictionary = {} # side -> Basis
## Orthonormal local-space frame per foot bone (columns: right, sole-down,
## toe-forward) - see _solve_leg's foot-orientation section for why this
## replaces a plain single-vector "align sole-down to the ground normal"
## quaternion: that approach leaves the twist around the down axis to fall
## out of an implicit, unstable perpendicular-axis choice, which can spin
## the whole foot ~90+ degrees when the animated sole direction ends up
## close to opposite the target. Building the corrected basis from two
## explicit reference vectors (down and toe-forward) instead keeps the twist
## always well-defined.
var _foot_frame_local: Dictionary = {} # side -> Basis
## Same idea, one level further down: many rigs give the last real toe bone
## a "leaf" child (here ball_leaf_l/r) purely to define its length/end
## point for animation tools - found by walking the skeleton, not a BONE_MAP
## role name, since these aren't part of the canonical retargeting set.
## Left untouched, it silently kept its stale animated rotation right at
## the toe tip - the exact spot most likely to carry mesh weight - while
## every bone we *did* correct measured perfectly flat, which is what made
## this one so easy to miss.
var _leaf_rest_offset: Dictionary = {} # side -> Vector3 (relative to toe)
var _leaf_rest_relative_basis: Dictionary = {} # side -> Basis (relative to toe)
var _smoothed_target: Dictionary = {} # side -> Vector3 (world)
var _smoothed_normal: Dictionary = {} # side -> Vector3 (world)
## Previous frame's *animated* (pre-IK) foot bone position, used to measure
## its vertical speed - see swing_speed_threshold's own doc comment.
var _prev_animated_foot_pos: Dictionary = {} # side -> Vector3 (world)
## Rate-limited (fast fall, slow rise) version of the raw velocity-derived
## ground_weight - see ground_weight_rise_time's own doc comment.
var _smoothed_ground_weight: Dictionary = {} # side -> float


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for side: StringName in LEGS:
		var roles: Dictionary = LEGS[side]
		var hip_name := player_body.resolve_bone_name(roles["hip"])
		var knee_name := player_body.resolve_bone_name(roles["knee"])
		var foot_name := player_body.resolve_bone_name(roles["foot"])
		var hip_idx := skel.find_bone(hip_name)
		var knee_idx := skel.find_bone(knee_name)
		var foot_idx := skel.find_bone(foot_name)
		if hip_idx < 0 or knee_idx < 0 or foot_idx < 0:
			continue
		# Toe/ball is optional - some rigs don't have one, and the leg still
		# works fine without it (see _solve_leg's toe_idx >= 0 guard), just
		# with no correction for whatever curl the animation baked into it.
		var toe_idx := skel.find_bone(player_body.resolve_bone_name(roles["toe"]))
		# The leaf (if any) is found by walking the skeleton, not a role
		# name - take the first child, which is all this rig has; a rig
		# with several would need real per-child handling, not assumed here.
		var leaf_idx := -1
		if toe_idx >= 0:
			var toe_children := skel.get_bone_children(toe_idx)
			if not toe_children.is_empty():
				leaf_idx = toe_children[0]
		_bone_indices[side] = {
			"hip": hip_idx, "knee": knee_idx, "foot": foot_idx, "toe": toe_idx, "leaf": leaf_idx}
		var hip_rest: Vector3 = skel.get_bone_global_rest(hip_idx).origin
		var knee_rest: Vector3 = skel.get_bone_global_rest(knee_idx).origin
		var foot_rest := skel.get_bone_global_rest(foot_idx)
		_leg_lengths[side] = {
			"upper": hip_rest.distance_to(knee_rest),
			"lower": knee_rest.distance_to(foot_rest.origin),
		}
		_sole_down_local[side] = _derive_sole_down_local(skel, foot_idx, side)
		if toe_idx >= 0:
			var toe_rest := skel.get_bone_global_rest(toe_idx)
			var foot_rest_basis_inv := foot_rest.basis.inverse()
			_toe_rest_offset[side] = foot_rest_basis_inv * (toe_rest.origin - foot_rest.origin)
			_toe_rest_relative_basis[side] = foot_rest_basis_inv * toe_rest.basis
			if leaf_idx >= 0:
				# Relative to the *foot's* rest transform, not the toe's -
				# chaining through the toe's own rest pose measured leaf.y
				# sitting ~3.5cm above the (correctly flattened) toe, i.e.
				# the toe's own bind pose isn't perfectly flat either (same
				# kind of bias _derive_sole_down_local found on the foot,
				# just never explicitly corrected for the toe). Anchoring
				# straight to the foot reuses the one reference already
				# confirmed flat instead of compounding a second bone's own
				# rest-pose bias on top.
				var leaf_rest := skel.get_bone_global_rest(leaf_idx)
				_leaf_rest_offset[side] = foot_rest_basis_inv * (leaf_rest.origin - foot_rest.origin)
				_leaf_rest_relative_basis[side] = foot_rest_basis_inv * leaf_rest.basis
		var sole_down_local: Vector3 = _sole_down_local[side]
		var local_forward := _derive_forward_local(
				sole_down_local, _toe_rest_offset.get(side, Vector3.ZERO))
		var local_right := sole_down_local.cross(local_forward).normalized()
		_foot_frame_local[side] = Basis(local_right, sole_down_local, local_forward)


## The rig's rest/bind pose is the one reference guaranteed to show the
## character standing flat-footed on level ground (no animation-specific
## ankle relaxation to bias the reading), so it's a more reliable source for
## "which direction is the sole normal" than sampling any one animated frame.
## Returns the EXACT rest-pose local-space direction of world down - not
## snapped to the nearest cardinal axis (±X/±Y/±Z). An earlier version did
## snap to the nearest axis, on the assumption the rig's local axes are
## meant to align with world down/forward/right and any mismatch was just
## animation noise; measured against this rig's actual rest pose, the
## nearest axis was still ~26.6 degrees off. Since _toe_rest_offset and
## _leaf_rest_offset (see _ready() below) are expressed in this SAME local
## frame and get carried through the corrected foot basis every frame (see
## _solve_leg), that 26.6-degree quantization error was reproduced exactly
## on the toe and leaf too - a visible kink that had nothing to do with the
## actual rig geometry and everything to do with rounding to the nearest
## axis. Using the exact direction keeps the whole chain's original
## geometric relationships intact instead of introducing avoidable error.
func _derive_sole_down_local(skel: Skeleton3D, foot_idx: int, side: StringName) -> Vector3:
	var rest_basis := skel.get_bone_global_rest(foot_idx).basis
	var exact_local_down := (rest_basis.inverse() * Vector3.DOWN).normalized()
	if LOG_SOLE_AXIS:
		var candidates := [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]
		var nearest_axis := Vector3.DOWN
		var best_dot := -INF
		for local_axis: Vector3 in candidates:
			for axis_sign: float in [1.0, -1.0]:
				var axis := local_axis * axis_sign
				var dot := axis.dot(exact_local_down)
				if dot > best_dot:
					best_dot = dot
					nearest_axis = axis
		print("[FootIK] ", side, " derived sole_down_local=", exact_local_down,
				" (nearest cardinal axis=", nearest_axis, ", dot=", best_dot, ")")
	return exact_local_down


## Picks a local "forward" reference orthogonal to sole_down_local, used to
## keep the foot's twist/roll well-defined when it's rebuilt in world space
## (see _solve_leg) instead of leaving it to an unstable single-vector
## rotation. The rest-pose offset toward the toe bone is the natural choice
## when one exists; falling back to whichever cardinal axis isn't already
## the sole-down axis still works for a toe-less rig, since RIGHT/UP/FORWARD
## are mutually orthogonal by construction.
func _derive_forward_local(sole_down_local: Vector3, toe_offset_local: Vector3) -> Vector3:
	var raw := toe_offset_local
	if raw.is_zero_approx():
		raw = Vector3.FORWARD if absf(sole_down_local.dot(Vector3.FORWARD)) < 0.5 else Vector3.RIGHT
	var forward := raw - sole_down_local * raw.dot(sole_down_local)
	if forward.length_squared() < 0.0001:
		var fallback := Vector3.RIGHT if absf(sole_down_local.dot(Vector3.RIGHT)) < 0.5 else Vector3.UP
		forward = fallback - sole_down_local * fallback.dot(sole_down_local)
	return forward.normalized()


## Built from two explicit reference vectors (ground-down, toe-forward)
## rather than a single shortest-arc quaternion aligning just sole_down_local
## to -smoothed_normal - that approach leaves the twist around the down axis
## to fall out of an implicit, unstable perpendicular-axis choice, which can
## spin the whole foot 90+ degrees whenever the animated sole direction ends
## up close to opposite the target (e.g. a mid-stride pose). Rebuilding the
## basis from two vectors keeps the twist always well-defined. Depends only
## on orientation (the animated foot pose and desired_down), not on the
## target position, so it's safe to call ahead of the actual IK position
## solve too - see _process_modification_with_delta's toe-drop prediction.
func _compute_new_foot_basis_world(
		skel: Skeleton3D, side: StringName, desired_down: Vector3) -> Basis:
	var foot_idx: int = _bone_indices[side]["foot"]
	var to_world := skel.global_transform
	var foot_pose := skel.get_bone_global_pose(foot_idx)
	var animated_foot_basis_world := to_world.basis * foot_pose.basis
	var local_frame: Basis = _foot_frame_local[side]
	var animated_forward := animated_foot_basis_world * local_frame.z
	var world_forward := animated_forward - desired_down * animated_forward.dot(desired_down)
	if world_forward.length_squared() < 0.0001:
		var animated_right := animated_foot_basis_world * local_frame.x
		world_forward = animated_right - desired_down * animated_right.dot(desired_down)
	world_forward = world_forward.normalized()
	var world_right := desired_down.cross(world_forward).normalized()
	var target_basis := Basis(world_right, desired_down, world_forward)
	return target_basis * local_frame.inverse()


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	# First pass: update each leg's smoothed ground target, and work out how
	# far past its own max reach that target is. A standing idle pose can
	# already have the leg close to fully extended, so asking the foot to
	# reach all the way to the true ground plane can exceed the leg's
	# physical length on its own - the standard fix (see e.g. two-bone IK
	# foot-planting writeups) is to lower the hip/pelvis just enough to
	# bring the target back into reach, not to leave the foot short.
	var to_world := skel.global_transform
	var per_leg: Dictionary = {} # side -> {hip_pos, target, normal, upper, lower, overreach}
	var shared_drop := 0.0
	for side: StringName in _bone_indices:
		var indices: Dictionary = _bone_indices[side]
		var lengths: Dictionary = _leg_lengths[side]
		var hip_idx: int = indices["hip"]
		var foot_idx: int = indices["foot"]
		var upper_length: float = lengths["upper"]
		var lower_length: float = lengths["lower"]
		var hip_pos: Vector3 = to_world * skel.get_bone_global_pose(hip_idx).origin
		var foot_pos: Vector3 = to_world * skel.get_bone_global_pose(foot_idx).origin

		var hit := _raycast_ground(space, foot_pos)
		var raw_target: Vector3 = hit["position"] if hit["hit"] else foot_pos
		var raw_normal: Vector3 = hit["normal"] if hit["hit"] else Vector3.UP
		if not _smoothed_target.has(side):
			_smoothed_target[side] = raw_target
			_smoothed_normal[side] = raw_normal
		var smooth_amount := clampf(delta * smooth_rate, 0.0, 1.0)
		var target_prev: Vector3 = _smoothed_target[side]
		var normal_prev: Vector3 = _smoothed_normal[side]
		_smoothed_target[side] = target_prev.lerp(raw_target, smooth_amount)
		_smoothed_normal[side] = normal_prev.lerp(raw_normal, smooth_amount).normalized()

		per_leg[side] = {"hip_pos": hip_pos, "hit": hit["hit"], "upper": upper_length,
				"lower": lower_length}
		if not hit["hit"]:
			continue

		# ankle_offset alone only guarantees the ANKLE clears the ground - the
		# corrected foot orientation (see _compute_new_foot_basis_world) can
		# still have the toe sitting further below the ankle than that, since
		# it now preserves this rig's natural toe-down idle stance instead of
		# forcing foot+toe flat (see that function's own doc comment for why
		# forcing flat was reverted). Predicting that drop here - purely
		# from orientation, before the position solve - and folding it into
		# the offset keeps the toe from clipping through the floor without
		# needing a second full IK solve.
		var desired_down := -(_smoothed_normal[side] as Vector3)
		var new_foot_basis_world := _compute_new_foot_basis_world(skel, side, desired_down)
		var toe_rest_offset: Vector3 = _toe_rest_offset.get(side, Vector3.ZERO)
		var toe_offset_world := new_foot_basis_world * toe_rest_offset
		# Extending past the toe bone itself, along the same foot->toe
		# direction, to predict clearance for the visual mesh tip rather than
		# just the bone origin - see toe_tip_margin's own doc comment.
		var tip_offset_world := toe_offset_world
		if not toe_offset_world.is_zero_approx():
			tip_offset_world += toe_offset_world.normalized() * toe_tip_margin
		var toe_drop := tip_offset_world.dot(desired_down)
		var effective_offset := maxf(ankle_offset, toe_drop)

		var ground_target: Vector3 = (_smoothed_target[side] as Vector3) + \
				(_smoothed_normal[side] as Vector3) * effective_offset

		# See swing_speed_threshold's own doc comment for why this is
		# velocity-based, not a height/clearance comparison. First frame has
		# no previous sample yet - assume stationary (grounded) rather than
		# guessing a spurious large initial velocity from a zero vector.
		# Godot calls this modifier twice per physics tick - once with
		# delta=0 (some internal reset/pre-pass), once with the real fixed
		# delta - discovered by direct instrumentation after this produced a
		# permanently-flat (0 velocity, ground_weight stuck at 1) result
		# despite the animation visibly progressing frame to frame. Updating
		# the reference sample on the delta=0 call made the very next
		# (real-delta) call compare against a same-tick duplicate, i.e.
		# zero measured movement, every single tick - only update the
		# reference on calls with real delta so consecutive real samples are
		# actually one physics tick apart.
		# SIGNED velocity (positive = rising, toward -smoothed_normal being
		# down) - not just its magnitude. A parabolic swing arc decelerates
		# for several consecutive frames approaching its peak, not just one
		# instant, so gating on |velocity| alone (however it's smoothed)
		# still lets a real multi-frame low-speed *ascending* stretch read
		# as "grounded" and visibly pull the foot down before it's actually
		# started descending - measured directly: several frames of
		# increasing divergence from the raw animation right before the top
		# of a stride, snapping back only once the foot was already well
		# past the peak.
		#
		# Rising velocity is scaled up by rising_penalty before comparing to
		# swing_speed_threshold, rather than an outright sign cutoff at
		# exactly 0 - a hard cutoff there means ANY positive velocity, down
		# to floating-point noise or an idle clip's own subtle breathing
		# sway, zeroes the correction completely for that one frame, and the
		# foot visibly snaps back to the raw animated pose (a real, sudden
		# twitch on an otherwise-static idle stair pose - a much worse
		# regression than the swing-apex dip this was meant to fix, since it
		# hit every character, moving or not). Scaling instead of cutting
		# off keeps tiny rising noise well under threshold (so idle stays
		# fully corrected, no twitch) while still suppressing genuine
		# swing-phase rising motion (far larger in magnitude) well before it
		# reaches the low-speed approach to the peak.
		var vertical_velocity := 0.0
		if delta > 0.0:
			if _prev_animated_foot_pos.has(side):
				var prev_pos: Vector3 = _prev_animated_foot_pos[side]
				vertical_velocity = (foot_pos - prev_pos).dot(_smoothed_normal[side] as Vector3) \
						/ delta
			_prev_animated_foot_pos[side] = foot_pos
		var effective_speed := absf(vertical_velocity)
		if vertical_velocity > 0.0:
			effective_speed *= rising_penalty
		var raw_ground_weight := clampf(1.0 - effective_speed / swing_speed_threshold, 0.0, 1.0)

		# Only rate-limit the RISE - see ground_weight_rise_time's own doc
		# comment for the single-frame swing-apex false positive this fixes.
		# Falling (a real swing starting) must stay instant, or the foot
		# would keep getting pulled toward the ground for a moment after
		# it's actually started lifting.
		var prev_weight: float = _smoothed_ground_weight.get(side, raw_ground_weight)
		var ground_weight := raw_ground_weight
		if raw_ground_weight > prev_weight and ground_weight_rise_time > 0.0:
			var max_rise: float = delta / ground_weight_rise_time
			ground_weight = minf(raw_ground_weight, prev_weight + max_rise)
		_smoothed_ground_weight[side] = ground_weight

		var target := foot_pos.lerp(ground_target, ground_weight)

		per_leg[side]["target"] = target
		per_leg[side]["ground_weight"] = ground_weight
		var max_reach := upper_length + lower_length - 0.001
		var horizontal_dist_sq := Vector2(hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
		var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
		var needed_drop: float = (hip_pos.y - target.y) - max_vertical_diff
		shared_drop = maxf(shared_drop, needed_drop)

	for side: StringName in _bone_indices:
		var leg: Dictionary = per_leg[side]
		if not leg["hit"]:
			continue
		_solve_leg(skel, side, leg["hip_pos"] - Vector3.UP * shared_drop, leg["target"],
				leg["upper"], leg["lower"], leg["ground_weight"])


func _solve_leg(
		skel: Skeleton3D, side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float) -> void:
	var indices: Dictionary = _bone_indices[side]
	var hip_idx: int = indices["hip"]
	var knee_idx: int = indices["knee"]
	var foot_idx: int = indices["foot"]

	var to_world := skel.global_transform
	var to_local := to_world.affine_inverse()

	var hip_pose := skel.get_bone_global_pose(hip_idx)
	var knee_pose := skel.get_bone_global_pose(knee_idx)
	var foot_pose := skel.get_bone_global_pose(foot_idx)

	var knee_pos: Vector3 = to_world * knee_pose.origin
	var foot_pos: Vector3 = to_world * foot_pose.origin
	var smoothed_normal: Vector3 = _smoothed_normal[side]

	# Two-bone IK (law of cosines), using the *animated* hip-to-knee
	# direction as the bend-plane reference so the correction preserves
	# whichever way the current animation already bends the knee (forward
	# during a walk cycle, etc.) instead of needing a separate pole target.
	# This reference deliberately uses the hip's own *animated* position
	# (before any reach-driven drop below), not the lowered `hip_pos` used
	# for placement - dropping the hip translates the whole leg but must
	# not itself change which way the knee is considered to bend.
	var animated_hip_pos: Vector3 = to_world * hip_pose.origin
	var to_target := target - hip_pos
	var eps := 0.001
	var min_reach: float = absf(upper_length - lower_length) + eps
	var max_reach: float = upper_length + lower_length - eps
	var dist := clampf(to_target.length(), min_reach, max_reach)
	if to_target.is_zero_approx():
		return
	var target_dir := to_target.normalized()

	var animated_hip_to_knee := knee_pos - animated_hip_pos
	var bend_axis := target_dir.cross(animated_hip_to_knee)
	if bend_axis.length_squared() < 0.0001:
		# Leg already points almost exactly at the target - no well-defined
		# bend plane, and no correction is needed anyway.
		bend_axis = target_dir.cross(Vector3.UP)
		if bend_axis.length_squared() < 0.0001:
			bend_axis = target_dir.cross(Vector3.FORWARD)
	bend_axis = bend_axis.normalized()

	var cos_hip_angle := clampf(
			(upper_length * upper_length + dist * dist - lower_length * lower_length)
					/ (2.0 * upper_length * dist),
			-1.0, 1.0)
	var hip_angle := acos(cos_hip_angle)

	var new_hip_to_knee_dir := target_dir.rotated(bend_axis, hip_angle)
	var new_knee_pos := hip_pos + new_hip_to_knee_dir * upper_length
	var new_foot_pos := hip_pos + target_dir * dist
	var new_knee_to_foot_dir := (new_foot_pos - new_knee_pos).normalized()

	var current_hip_to_knee_dir := animated_hip_to_knee.normalized()
	var current_knee_to_foot_dir := (foot_pos - knee_pos).normalized()

	var hip_delta := Quaternion(current_hip_to_knee_dir, new_hip_to_knee_dir)
	var knee_delta := Quaternion(current_knee_to_foot_dir, new_knee_to_foot_dir)

	var new_hip_basis_world := Basis(hip_delta) * (to_world.basis * hip_pose.basis)
	var new_knee_basis_world := Basis(knee_delta) * (to_world.basis * knee_pose.basis)

	var desired_down := -smoothed_normal
	var animated_foot_basis_world := to_world.basis * foot_pose.basis
	var ground_foot_basis_world := _compute_new_foot_basis_world(skel, side, desired_down)
	# Slerped by the same ground_weight as the position target above, so the
	# foot keeps its natural (unlevelled) swing-phase orientation while
	# airborne and only tilts flat to match the ground as it actually
	# approaches landing, instead of being forced flat on every frame
	# regardless of gait phase.
	var new_foot_basis_world := Basis(animated_foot_basis_world.get_rotation_quaternion().slerp(
			ground_foot_basis_world.get_rotation_quaternion(), ground_weight))

	skel.set_bone_global_pose(hip_idx,
			Transform3D(to_local.basis * new_hip_basis_world, to_local * hip_pos))
	skel.set_bone_global_pose(knee_idx,
			Transform3D(to_local.basis * new_knee_basis_world, to_local * new_knee_pos))
	skel.set_bone_global_pose(foot_idx,
			Transform3D(to_local.basis * new_foot_basis_world, to_local * new_foot_pos))

	# The toe/ball bone is a separate child bone with its own animated pose -
	# left alone, it keeps pointing wherever the untouched animation put it
	# while the foot rotates flat underneath it, reading as the toe tip
	# lifting off the ground even though the ankle looks perfectly planted.
	# Carrying the toe's *animated* offset/orientation along by the foot's
	# rotation was tried first and wasn't enough - measured ~9cm of toe-to-
	# ground gap even with the ankle exactly on target, because the idle
	# clip itself has the toes curled/raised relative to the foot (weight-
	# on-the-ball posing), and rigidly preserving that relative curl just
	# carries the lift along for the ride. Rebuilding the toe from its
	# *rest-pose* offset/orientation relative to the foot instead (cached in
	# _ready(), see _toe_rest_offset/_toe_rest_relative_basis) assumes the
	# bind pose is the one reference that actually has the whole foot flat
	# on the ground - same reasoning _derive_sole_down_local() already uses
	# for the foot itself - so the toe ends up coplanar with the corrected
	# foot instead of preserving an animated curl that was lifting it.
	var toe_idx: int = indices["toe"]
	if toe_idx >= 0:
		var rest_offset: Vector3 = _toe_rest_offset[side]
		var rest_relative_basis: Basis = _toe_rest_relative_basis[side]
		var new_toe_pos := new_foot_pos + new_foot_basis_world * rest_offset
		var new_toe_basis_world := new_foot_basis_world * rest_relative_basis
		skel.set_bone_global_pose(toe_idx,
				Transform3D(to_local.basis * new_toe_basis_world, to_local * new_toe_pos))

		# Same rigid rest-pose rebuild, one more level down - see the
		# _leaf_rest_offset/_leaf_rest_relative_basis doc comment for why
		# this bone (found by walking the skeleton, e.g. ball_leaf_l/r) was
		# the actual missing piece: it's right at the toe tip, the most
		# likely spot to carry mesh weight, and was silently keeping its
		# stale animated rotation while every bone measured above it
		# checked out perfectly flat. Anchored to the *foot's* new pose,
		# not the toe's - see the offset's own doc comment for why.
		var leaf_idx: int = indices["leaf"]
		if leaf_idx >= 0:
			var leaf_rest_offset: Vector3 = _leaf_rest_offset[side]
			var leaf_rest_relative_basis: Basis = _leaf_rest_relative_basis[side]
			var new_leaf_pos := new_foot_pos + new_foot_basis_world * leaf_rest_offset
			var new_leaf_basis_world := new_foot_basis_world * leaf_rest_relative_basis
			skel.set_bone_global_pose(leaf_idx,
					Transform3D(to_local.basis * new_leaf_basis_world, to_local * new_leaf_pos))


func _raycast_ground(space: PhysicsDirectSpaceState3D, foot_pos: Vector3) -> Dictionary:
	var from := foot_pos + Vector3.UP * ray_up
	var to := foot_pos + Vector3.DOWN * ray_down
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GROUND_COLLISION_MASK
	query.collide_with_areas = false
	if is_instance_valid(player_body) and player_body.get_parent() is CollisionObject3D:
		query.exclude = [(player_body.get_parent() as CollisionObject3D).get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {"hit": false, "position": foot_pos, "normal": Vector3.UP}
	return {"hit": true, "position": result["position"], "normal": result["normal"]}
