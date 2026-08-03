class_name PlayerFootIKModifier
extends SkeletonModifier3D
## TEMPORARY / EXPERIMENTAL: the implementation has been separated into
## contact, gait, stair-prediction, and bone-solve phases, but its current
## stair-walking result is not accepted. Keep it available for the manual
## harness and follow-up tuning; passing numeric checks only means it avoids
## the known hierarchy-stretch and airborne-IK regressions.
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

signal foot_landed(side: StringName, ground_position: Vector3)

## Logs the rest-pose-derived sole axis for each leg once at startup - cheap
## and worth keeping permanently, so a future catalog character whose rig
## has a genuinely different bone-axis convention shows up as a readable log
## line instead of a silent wrong-looking foot.
const LOG_SOLE_AXIS := true
const LEG_SOLVER := preload("res://actors/player/foot_ik/foot_ik_leg_solver.gd")
const GAIT_TRACKER := preload("res://actors/player/foot_ik/foot_ik_gait_tracker.gd")
const STAIR_PREDICTOR := preload("res://actors/player/foot_ik/foot_ik_stair_predictor.gd")
const NATIVE_BACKEND := preload("res://actors/player/foot_ik/foot_ik_native_backend.gd")

enum SolverBackend { CUSTOM, NATIVE_TWO_BONE }

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
const GROUND_CONTACT_DISTANCE := 0.03
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
## How many consecutive frames the animated foot must be clearly falling
## (faster than velocity_noise_floor, downward) before it's trusted as a
## real landing approach - see the falling-streak comment in
## _process_modification_with_delta() for the swing-apex artifact this
## fixes: a parabolic arc's low-speed stretch near its peak includes a
## couple of technically-falling frames right after the top, fast enough to
## slip past rising_penalty's rising-only gate and briefly nudge
## ground_weight up before the leg's real (much faster, sustained) descent
## begins. A real footfall falls for many frames in a row, not two, so
## requiring a short streak filters the peak blip out without meaningfully
## delaying genuine landings.
@export var min_falling_streak: int = 3
## Velocity magnitude (m/s) below which vertical motion is ignored entirely
## - treated as exactly stationary regardless of sign, before rising_penalty
## even applies. rising_penalty alone reduces sensitivity to idle noise but
## doesn't remove it: noise around this size, scaled by rising_penalty, can
## still be a meaningful fraction of swing_speed_threshold and cause a
## smaller but still visible partial dip. Genuine swing motion is far
## faster than ordinary idle sway/animation jitter, so a small dead zone
## below it costs nothing during a real step.
@export var velocity_noise_floor: float = 0.03
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
## exact peak of one stride).
@export var ground_weight_rise_time: float = 0.12
## Same idea as ground_weight_rise_time, but for the opposite direction -
## much shorter, not zero. An earlier version let the fall happen in a
## single frame (uncapped), reasoning that a genuine swing needs to release
## the correction immediately rather than holding the foot down for a
## moment after it's actually started lifting. That's still true for a real
## swing start, but the SAME instant-fall path also fires when recovering
## from the small residual rise near a swing peak (see
## ground_weight_rise_time above) - and snapping from "leg bent extra to
## plant" back to "matches the animation" in exactly one physics frame is a
## visible pop/cut regardless of which case caused it, confirmed by logging
## the knee's own bend angle frame by frame (75.0 -> 89.4 degrees, a single-
## frame jump, immediately after the capped-rise dip). A short but nonzero
## fall time smooths that snap-back into a couple of frames instead of one,
## while staying fast enough that a genuine swing start still reads as
## essentially immediate.
@export var ground_weight_fall_time: float = 0.05
## Optional stair predictor lifts a swinging foot over the next higher tread.
## Enabled for normal PlayerBody instances; the manual harness tunes its values.
@export var step_prediction_enabled: bool = true
@export var step_prediction_distance: float = 0.6
@export var step_min_rise: float = 0.05
@export var step_clearance_margin: float = 0.11
@export var step_lift_rate: float = 36.0
@export var flat_idle_noop_distance: float = 0.01 # Preserve authored idle inside 1 cm.
@export_range(0.0, 170.0, 1.0) var max_knee_flexion_degrees: float = 150.0
@export var solver_backend := SolverBackend.CUSTOM
const LEGS := {
	&"left": {"hip": &"LeftUpLeg", "knee": &"LeftLeg", "foot": &"LeftFoot", "toe": &"LeftToeBase"},
	&"right": {
		"hip": &"RightUpLeg", "knee": &"RightLeg", "foot": &"RightFoot", "toe": &"RightToeBase"},
}
var player_body: PlayerBody
var _leg_solver: RefCounted
var _gait_tracker: RefCounted
var _stair_predictor: RefCounted
var _native_backend: RefCounted

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
## Last toe-leaf transforms are tracked too; stale weighted leaf poses kinked
## the visible toe even when every corrected parent measured flat.
var _leaf_rest_offset: Dictionary = {} # side -> Vector3 (relative to toe)
var _leaf_rest_relative_basis: Dictionary = {} # side -> Basis (relative to toe)
var _smoothed_target: Dictionary = {} # side -> Vector3 (world)
var _smoothed_normal: Dictionary = {} # side -> Vector3 (world)
## Previous frame's animated foot position in skeleton space. Measuring
## relative to the skeleton excludes player/root stair-hover translation;
## otherwise both feet falsely become "swinging" whenever the visible body
## eases upward, releasing and re-engaging IK once per tread.
var _prev_animated_foot_pos: Dictionary = {} # side -> Vector3 (skeleton)
## Rate-limited (fast fall, slow rise) version of the raw velocity-derived
## ground_weight - see ground_weight_rise_time's own doc comment.
var _smoothed_ground_weight: Dictionary = {} # side -> float
## Consecutive frames the animated foot has been clearly falling - see
## min_falling_streak's own doc comment.
var _falling_streak: Dictionary = {} # side -> int
var _landing_fell: Dictionary = {} # side -> bool
var _smoothed_step_lift: Dictionary:
	get:
		return _stair_predictor.get_step_lifts() if _stair_predictor != null else {}
var predicted_step_targets: Dictionary:
	get:
		return _stair_predictor.get_predicted_targets() if _stair_predictor != null else {}
var debug_vertical_velocity: Dictionary = {} # side -> pre-IK animation velocity
var _forced_support_side: StringName:
	get:
		return _stair_predictor.get_support_side() if _stair_predictor != null else &""
# Retained pole prevents an ambiguous straight leg choosing the reverse bend.
var _knee_pole_local: Dictionary = {} # side -> Vector3
func reset_runtime_state() -> void:
	_smoothed_target.clear()
	_smoothed_normal.clear()
	_prev_animated_foot_pos.clear()
	_smoothed_ground_weight.clear()
	_falling_streak.clear()
	_landing_fell.clear()
	debug_vertical_velocity.clear()
	if _stair_predictor != null:
		_stair_predictor.reset()

func set_character_grounded(value: bool) -> void:
	if active == value:
		return
	reset_runtime_state()
	active = value
	if _native_backend != null:
		_native_backend.set_enabled(value and solver_backend == SolverBackend.NATIVE_TWO_BONE)


func set_solver_backend(value: SolverBackend) -> void:
	if solver_backend == value:
		return
	reset_runtime_state()
	solver_backend = value
	if _native_backend != null:
		_native_backend.set_enabled(active and solver_backend == SolverBackend.NATIVE_TWO_BONE)


func set_debug_enabled(value: bool) -> void:
	active = value
	reset_runtime_state()
	if _native_backend != null:
		_native_backend.set_enabled(value and solver_backend == SolverBackend.NATIVE_TWO_BONE)


func _ready() -> void:
	_leg_solver = LEG_SOLVER.new(self)
	_gait_tracker = GAIT_TRACKER.new(self)
	_stair_predictor = STAIR_PREDICTOR.new(self)
	_native_backend = NATIVE_BACKEND.new(self)
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
		var rest_leg_direction := (foot_rest.origin - hip_rest).normalized()
		var rest_pole := knee_rest - hip_rest
		rest_pole -= rest_leg_direction * rest_pole.dot(rest_leg_direction)
		if rest_pole.length_squared() < 0.0001:
			rest_pole = Vector3.FORWARD - rest_leg_direction * rest_leg_direction.z
		_knee_pole_local[side] = rest_pole.normalized()
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
	_native_backend.setup(skel, _bone_indices)
	_native_backend.set_enabled(active and solver_backend == SolverBackend.NATIVE_TWO_BONE)


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
	_stair_predictor.update_travel_direction(delta)

	# Find the shared pelvis drop needed to keep both ground targets reachable.
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
		var animated_foot_pose := skel.get_bone_global_pose(foot_idx)
		var animated_foot_pos := animated_foot_pose.origin
		var foot_pos: Vector3 = to_world * animated_foot_pos

		var contact := _sample_ground_contact(
				skel, space, side, animated_foot_pose, foot_pos, to_world, delta)
		per_leg[side] = {"hip_pos": hip_pos, "hit": contact["hit"], "upper": upper_length,
				"lower": lower_length, "vertical_velocity": 0.0}
		if not contact["hit"]:
			continue
		var raw_target: Vector3 = contact["raw_target"]
		var raw_normal: Vector3 = contact["raw_normal"]
		var effective_offset: float = contact["effective_offset"]
		var ground_target: Vector3 = contact["ground_target"]
		var raw_ground_target: Vector3 = contact["raw_ground_target"]
		var animated_lowest_point: Vector3 = contact["animated_lowest_point"]
		var animated_contact_distance: float = contact["animated_contact_distance"]
		var animated_contact_hit: bool = contact["animated_contact_hit"]
		var animated_contact_position: Vector3 = contact["animated_contact_position"]
		var animated_contact_normal: Vector3 = contact["animated_contact_normal"]

		var gait: Dictionary = _gait_tracker.update(side, animated_foot_pos, foot_pos,
				ground_target, animated_contact_hit, animated_contact_distance, to_world, delta)
		var vertical_velocity: float = gait["vertical_velocity"]
		var ground_weight: float = gait["ground_weight"]
		var landed: bool = gait["landed"]

		# Preserve authored level-ground idle; real gaps/slopes still run IK.
		var preserve_idle_pose: bool = (
				ground_weight >= 0.999
				and absf(vertical_velocity) <= velocity_noise_floor
				and raw_normal.dot(Vector3.UP) >= 0.999
				and not _stair_predictor.has_latched_target()
				and foot_pos.distance_to(ground_target) <= flat_idle_noop_distance)
		var target := foot_pos if preserve_idle_pose else foot_pos.lerp(ground_target, ground_weight)
		if step_prediction_enabled:
			target += Vector3.UP * _stair_predictor.update_swing_lift(
					space, side, foot_pos, animated_foot_pose.basis, raw_target,
					animated_lowest_point, ground_weight, landed, delta)

		per_leg[side]["target"] = target
		per_leg[side]["ground_target"] = ground_target
		per_leg[side]["raw_ground_target"] = raw_ground_target
		per_leg[side]["raw_target"] = raw_target
		per_leg[side]["raw_normal"] = raw_normal
		per_leg[side]["animated_foot_pos"] = foot_pos
		per_leg[side]["animated_contact_distance"] = animated_contact_distance
		per_leg[side]["animated_contact_hit"] = animated_contact_hit
		per_leg[side]["animated_contact_position"] = animated_contact_position
		per_leg[side]["animated_contact_normal"] = animated_contact_normal
		per_leg[side]["effective_offset"] = effective_offset
		per_leg[side]["vertical_velocity"] = vertical_velocity
		per_leg[side]["ground_weight"] = ground_weight
		per_leg[side]["preserve_idle_pose"] = preserve_idle_pose
		if preserve_idle_pose:
			continue
		var max_reach := upper_length + lower_length - 0.001
		var horizontal_dist_sq := Vector2(hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
		var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
		var needed_drop: float = (hip_pos.y - target.y) - max_vertical_diff
		shared_drop = maxf(shared_drop, needed_drop)

	_apply_support_pelvis_and_legs(skel, to_world, per_leg, shared_drop)


func _sample_ground_contact(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		side: StringName, foot_pose: Transform3D, foot_pos: Vector3,
		to_world: Transform3D, delta: float) -> Dictionary:
	var hit := _raycast_ground(space, foot_pos)
	var raw_target: Vector3 = hit["position"] if hit["hit"] else foot_pos
	var raw_normal: Vector3 = hit["normal"] if hit["hit"] else Vector3.UP
	if not _smoothed_target.has(side):
		_smoothed_target[side] = raw_target
		_smoothed_normal[side] = raw_normal
	var amount := clampf(delta * smooth_rate, 0.0, 1.0)
	_smoothed_target[side] = (_smoothed_target[side] as Vector3).lerp(raw_target, amount)
	_smoothed_normal[side] = (_smoothed_normal[side] as Vector3).lerp(
			raw_normal, amount).normalized()
	if not hit["hit"]:
		return {"hit": false}
	var desired_down := -(_smoothed_normal[side] as Vector3)
	var foot_basis := _compute_new_foot_basis_world(skel, side, desired_down)
	var toe_offset: Vector3 = foot_basis * (_toe_rest_offset.get(side, Vector3.ZERO) as Vector3)
	var tip_offset := toe_offset
	if not toe_offset.is_zero_approx():
		tip_offset += toe_offset.normalized() * toe_tip_margin
	var effective_offset := maxf(ankle_offset, tip_offset.dot(desired_down))
	var animated_lowest_point := foot_pos
	var surface_hit := {"hit": false}
	if step_prediction_enabled:
		animated_lowest_point = _animated_lowest_surface_point_world(
				skel, side, foot_pose, foot_pos, to_world)
		surface_hit = _raycast_ground(space, animated_lowest_point)
	var contact_hit := bool(surface_hit["hit"])
	var contact_position: Vector3 = surface_hit["position"] if contact_hit else foot_pos
	return {
		"hit": true, "raw_target": raw_target, "raw_normal": raw_normal,
		"effective_offset": effective_offset,
		"ground_target": (_smoothed_target[side] as Vector3)
				+ (_smoothed_normal[side] as Vector3) * effective_offset,
		"raw_ground_target": raw_target + raw_normal * effective_offset,
		"animated_lowest_point": animated_lowest_point,
		"animated_contact_distance": maxf(0.0, animated_lowest_point.y - contact_position.y)
				if contact_hit else INF,
		"animated_contact_hit": contact_hit,
		"animated_contact_position": contact_position,
		"animated_contact_normal": surface_hit["normal"] if contact_hit else Vector3.UP,
	}


func _apply_support_pelvis_and_legs(skel: Skeleton3D, to_world: Transform3D,
		per_leg: Dictionary, shared_drop: float) -> void:
	if step_prediction_enabled and _stair_predictor.is_active():
		shared_drop = _stair_predictor.ensure_support(per_leg, shared_drop)
	# Pelvis and thigh roots move together so skinning across the seam cannot tear.
	if shared_drop > 0.0 and not _bone_indices.is_empty():
		var first_leg: Dictionary = _bone_indices.values()[0]
		var pelvis_idx := skel.get_bone_parent(first_leg["hip"])
		if pelvis_idx >= 0:
			var pelvis_world := to_world * skel.get_bone_global_pose(pelvis_idx)
			pelvis_world.origin -= Vector3.UP * shared_drop
			skel.set_bone_global_pose(pelvis_idx, to_world.affine_inverse() * pelvis_world)
	if solver_backend == SolverBackend.NATIVE_TWO_BONE:
		_native_backend.update_targets(skel, per_leg)
		return
	for side: StringName in _bone_indices:
		var leg: Dictionary = per_leg[side]
		if not leg["hit"] or leg.get("preserve_idle_pose", false):
			continue
		_leg_solver.solve(skel, side, leg["hip_pos"] - Vector3.UP * shared_drop, leg["target"],
				leg["upper"], leg["lower"], leg["ground_weight"])

func _animated_lowest_surface_point_world(
		skel: Skeleton3D, side: StringName, animated_foot_pose: Transform3D,
		foot_position: Vector3, to_world: Transform3D) -> Vector3:
	# Match the manual harness's rendered-contact estimate: compare the sole
	# point below the ankle with the extrapolated toe tip and use whichever
	# is lower. Measuring only the ankle is why support previously transferred
	# while the visible foot was still tens of centimeters from the tread.
	var sole_down_world := (
			to_world.basis * animated_foot_pose.basis * (_sole_down_local[side] as Vector3)
	).normalized()
	var sole_point := foot_position + sole_down_world * ankle_offset
	var toe_idx: int = (_bone_indices[side] as Dictionary).get("toe", -1)
	if toe_idx < 0:
		return sole_point
	var toe_position: Vector3 = to_world * skel.get_bone_global_pose(toe_idx).origin
	var foot_to_toe := toe_position - foot_position
	var toe_tip := toe_position
	if not foot_to_toe.is_zero_approx():
		toe_tip += foot_to_toe.normalized() * toe_tip_margin
	return toe_tip if toe_tip.y < sole_point.y else sole_point


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
