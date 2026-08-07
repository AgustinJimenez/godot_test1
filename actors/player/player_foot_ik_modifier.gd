class_name PlayerFootIKModifier
extends SkeletonModifier3D
## TEMPORARY / EXPERIMENTAL: separated into contact, gait, stair-prediction,
## and bone-solve phases, but its current stair-walking result is not
## accepted. Kept for the manual harness and follow-up tuning; passing
## numeric checks only avoids the known hierarchy-stretch/airborne-IK regressions.
## Plants each foot on the actual ground/step surface beneath it instead of
## wherever the flat-ground-authored locomotion clips leave it - raycasts
## straight down from each foot's animated position, then bends hip/knee to
## reach that point (closed-form two-bone IK) and tilts the foot to match
## the surface normal. Mirrors player_hand_grip_modifier.gd/player_look_pose_modifier.gd:
## a plain SkeletonModifier3D subclass reading/writing poses in
## _process_modification(), added as a skeleton child by PlayerBody, which
## switches the skeleton's modifier callback mode for physics-fresh raycasts.

signal foot_landed(side: StringName, ground_position: Vector3)

## Logs the rest-pose-derived sole axis for each leg at startup - a future
## catalog character with a different bone-axis convention then shows up as
## a readable log line instead of a silent wrong-looking foot.
const LOG_SOLE_AXIS := true
## Logs the measured planted sole depth for each leg at rig setup (see
## _measure_leg_sole_depth) - a rig whose bind geometry hangs unusually low
## under the ball/toe then shows up as a readable line, not a silent sink.
const LOG_SOLE_DEPTH := true
const LEG_SOLVER := preload("res://actors/player/foot_ik/foot_ik_leg_solver.gd")
const GAIT_TRACKER := preload("res://actors/player/foot_ik/foot_ik_gait_tracker.gd")
const STAIR_PREDICTOR := preload("res://actors/player/foot_ik/foot_ik_stair_predictor.gd")
const NATIVE_BACKEND := preload("res://actors/player/foot_ik/foot_ik_native_backend.gd")

enum SolverBackend { CUSTOM, NATIVE_TWO_BONE }

## Search range above/below the animated foot for ground. ray_down covers
## the tallest riser in foot_ik_preview.tscn (0.35m) plus stride margin.
## @export (not const) so the debug panel can tune against real gameplay.
@export var ray_up: float = 0.5
@export var ray_down: float = 0.6
## Idle-only fallback depth when ray_down finds nothing: ray_down stays short
## so a mid-swing foot doesn't "see" a distant floor and distort gait timing,
## but a stationary foot has no such concern - see _sample_ground_contact.
@export var idle_settle_search_down: float = 4.0
## Matches the level geometry collision layer used throughout the project.
const GROUND_COLLISION_MASK := 1
const GROUND_CONTACT_DISTANCE := 0.03
const TARGET_NOISE_DEADBAND := 0.01 # sub-this raycast noise is rejected, not lerped toward
## Approximate sole thickness/ankle clearance so the ankle doesn't sink
## exactly to the raycast hit point. The foot/toe are no longer forced flat
## (see _compute_new_foot_basis_world) - they preserve the idle clip's
## natural toe-down stance, so the effective ground offset per-leg is
## whichever is larger of this and the predicted toe-tip drop (see
## _process_modification_with_delta/toe_tip_margin) - this is just the floor
## under that, the minimum clearance for a leg whose toe doesn't droop at all.
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
## foot doesn't pop when a hit jumps between tread heights frame to frame.
@export var smooth_rate: float = 14.0
## How fast the *animated*, uncorrected foot is currently rising/falling
## (meters/second) counts as "mid-swing" - the correction blends from full
## strength at 0 speed down to none at this speed, instead of applying
## unconditionally every frame regardless of gait phase. Without this, the
## raycast finds essentially the same ground point under the foot on every
## frame of a walk cycle, and the leg gets bent to plant there even while
## the animation is trying to lift the foot through the air for a step -
## measured killing a natural ~0.27m walk-cycle foot-height swing down to a
## completely flat, unmoving foot.
##
## Deliberately velocity-based, not height-based: an earlier version blended
## on how far the animated foot sits above its ground target, which broke
## static standing on the taller of two adjacent stair treads (a large but
## legitimate *static* correction, wrongly read as "mid-swing" just because
## the required correction was large) - a foot that isn't currently moving
## vertically is either standing still or momentarily planted between steps,
## and either way should get full correction regardless of how tall that
## correction needs to be. A foot actively swinging through the air, by
## contrast, has real vertical speed - that's the distinguishing signal.
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
## the correction immediately. That's true for a real swing start, but the
## SAME instant-fall path also fires when recovering from the small residual
## rise near a swing peak (see ground_weight_rise_time above) - snapping
## from "leg bent extra to plant" back to "matches the animation" in exactly
## one physics frame is a visible pop regardless of which case caused it
## (confirmed by logging the knee's bend angle: 75.0 -> 89.4 degrees in one
## frame, right after the capped-rise dip). A short but nonzero fall time
## smooths that snap-back into a couple of frames instead of one, while
## staying fast enough that a genuine swing start still reads as immediate.
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
@export_range(10.0, 170.0, 1.0) var max_hip_swing_degrees: float = 100.0 # cone from straight down
## When true, overrides the gait tracker's contact-lost check and forces both
## feet to plant on the ground. Used by the foot IK harness during inspection
## idle poses where the animated foot height doesn't match the step geometry.
var force_plant_mode: bool = false
## Idle step-down: a stationary stance foot whose sole rests more than
## GROUND_CONTACT_DISTANCE above a lower surface (e.g. straddling a stair
## riser) never stays floating. Requires motionless for
## STEP_DOWN_STATIC_STREAK consecutive real-delta frames. If reachable within
## step_down_pelvis_drop of shared-pelvis sink, plants directly. Beyond that,
## rather than stretch the leg or move the whole capsule (an earlier
## whole-body walk-down approach marched the character down a whole
## staircase from one idle foot, unprompted), _retract_to_reachable() pulls
## the target horizontally back toward the hip until it finds a point
## genuinely within reach - like a person shortening their stride near a
## drop-off. If nothing is found, the foot floats at its animated pose.
## Never engages while airborne or with force_plant_mode on.
@export_range(0.0, 1.0, 0.01) var idle_step_down_speed: float = 0.06
@export_range(0.0, 0.75, 0.005) var step_down_pelvis_drop: float = 0.35
## Hard ceiling on shared pelvis sink for a foot _retract_to_reachable()
## couldn't rescue (the drop is genuinely deeper than the leg can reach from
## the body's current height, e.g. standing on a step above a much lower
## floor) - deliberately looser than step_down_pelvis_drop's "still looks
## like ordinary standing" budget, this is "as deep a crouch as a person
## could still plausibly be doing," past which sinking further would just
## look broken rather than merely deep. The leg still cannot fully reach in
## this case; capping shared_drop here (rather than leaving it uncapped)
## means the leg solver's own reach envelope naturally leaves the foot
## hanging just short of the true target instead of pulling the whole pose
## into an unbounded, unrealistic squat.
@export_range(0.0, 1.0, 0.005) var step_down_max_crouch: float = 0.6
const STEP_DOWN_STATIC_STREAK := 4
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
## Max extent of this leg's planted bind geometry below the foot bone's
## origin (meters), measured once at rig setup - see _measure_leg_sole_depth.
## Fed into effective_offset so a planted sole clears the ground even when
## the ball/toe geometry hangs below the bone origins.
var _sole_depth_below_foot: Dictionary = {} # side -> float
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
## out of an implicit, unstable perpendicular-axis choice, which can spin the
## whole foot ~90+ degrees when the animated sole direction ends up close to
## opposite the target. Building the corrected basis from two explicit
## reference vectors (down and toe-forward) keeps the twist well-defined.
var _foot_frame_local: Dictionary = {} # side -> Basis
## Last toe-leaf transforms tracked too; stale weighted leaf poses kinked the
## visible toe even when every corrected parent measured flat.
var _leaf_rest_offset: Dictionary = {} # side -> Vector3 (relative to toe)
var _leaf_rest_relative_basis: Dictionary = {} # side -> Basis (relative to toe)
var _smoothed_target: Dictionary = {} # side -> Vector3 (world)
var _smoothed_normal: Dictionary = {} # side -> Vector3 (world)
## Previous frame's animated foot position in skeleton space. Measuring
## relative to the skeleton excludes player/root stair-hover translation;
## otherwise both feet falsely become "swinging" whenever the visible body
## eases upward, releasing and re-engaging IK once per tread.
var _prev_animated_foot_pos: Dictionary = {} # side -> Vector3 (skeleton)
## Held bone poses reused by the leg solver in place of a fresh (possibly
## seam-jumped) skeleton read on a loop-reset frame - see solve()'s doc.
var _prev_leg_bone_poses: Dictionary = {} # side -> Dictionary
var _prev_pelvis_pose: Transform3D
var _has_prev_pelvis_pose: bool = false
## Rate-limited (fast fall, slow rise) version of the raw velocity-derived
## ground_weight - see ground_weight_rise_time's own doc comment.
var _smoothed_ground_weight: Dictionary = {} # side -> float
var _falling_streak: Dictionary = {} # side -> int, see min_falling_streak's doc comment
var _rising_streak: Dictionary = {} # side -> int, see _raw_weight()'s doc comment
## Watchdog for foot_ik_gait_tracker.gd's _smooth_weight - see its own doc
## comment for why this exists.
var _weight_stuck_time: Dictionary = {} # side -> float (seconds)
var _landing_fell: Dictionary = {} # side -> bool
var _step_down_static_streak: Dictionary = {} # side -> int
## Counts down after set_character_grounded()'s airborne->grounded
## transition - see _sample_ground_contact's own deadlock comment.
var _landing_grace_time := 0.0
var _prev_animation_position := -1.0 # see update_animation_discontinuity()'s doc comment
var _animation_discontinuous := false # ditto - pose-hold/contact_lost window
var _animation_discontinuity_hold := 0 # ditto
var _velocity_suppressed := false # ditto - wider, velocity-only window
var _velocity_suppress_hold := 0 # ditto
const LANDING_GRACE_DURATION := 0.35
var _idle_frozen: Dictionary = {} # side -> bool, see gait_tracker's update_idle_freeze() doc
var _idle_freeze_streak: Dictionary = {} # side -> int
var _idle_unfreeze_streak: Dictionary = {} # side -> int, ditto
var _smoothed_step_lift: Dictionary:
	get:
		return _stair_predictor.get_step_lifts() if _stair_predictor != null else {}
var predicted_step_targets: Dictionary:
	get:
		return _stair_predictor.get_predicted_targets() if _stair_predictor != null else {}
var debug_vertical_velocity: Dictionary = {} # side -> pre-IK animation velocity
## Surface-to-surface measurement used by the gait tracker: vertical distance
## from the animated sole/toe lowest point to the secondary ground ray hit.
## INF when no secondary contact exists; exposes the controlled character's
## own value so harness readouts don't borrow the 0.35m walker's rays.
var debug_contact_distance: Dictionary = {} # side -> float
var debug_contact_hit: Dictionary = {} # side -> bool
var debug_step_down: Dictionary = {} # side -> bool
var debug_raw_weight: Dictionary = {} # side -> float, pre-smoothing gait_tracker output
var debug_contact_lost: Dictionary = {} # side -> bool, forces raw_weight to 0 when true
## A stationary foot whose lower surface needed more pelvis sink than
## step_down_pelvis_drop allows was retracted toward the hip to a reachable
## point instead - see _retract_to_reachable's doc comment. Diagnostic only.
var debug_retracted: Dictionary = {} # side -> bool
## Final post-IK skeleton-space global poses (bone index -> Transform3D),
## captured at the end of each modification pass. External harnesses sample
## these instead of get_bone_global_pose() at their own (idle) time, where the
## skeleton may still hold the pre-IK animated pose from the last animation
## update and would otherwise skin a mesh that was never actually rendered.
var _final_bone_poses: Dictionary = {} # int bone index -> Transform3D (skeleton space)
var _forced_support_side: StringName:
	get:
		return _stair_predictor.get_support_side() if _stair_predictor != null else &""
# Retained pole prevents an ambiguous straight leg choosing the reverse bend.
var _knee_pole_local: Dictionary = {} # side -> Vector3
func reset_runtime_state() -> void:
	_smoothed_target.clear()
	_smoothed_normal.clear()
	_prev_animated_foot_pos.clear()
	_prev_leg_bone_poses.clear()
	_has_prev_pelvis_pose = false
	_smoothed_ground_weight.clear()
	_falling_streak.clear()
	_rising_streak.clear()
	_weight_stuck_time.clear()
	_landing_fell.clear()
	_step_down_static_streak.clear()
	_idle_frozen.clear()
	_idle_freeze_streak.clear()
	_idle_unfreeze_streak.clear()
	_landing_grace_time = 0.0
	_prev_animation_position = -1.0
	_animation_discontinuity_hold = 0
	_velocity_suppress_hold = 0
	debug_vertical_velocity.clear()
	debug_contact_distance.clear()
	debug_contact_hit.clear()
	debug_step_down.clear()
	debug_raw_weight.clear()
	debug_contact_lost.clear()
	debug_retracted.clear()
	if _stair_predictor != null:
		_stair_predictor.reset()

## Grounded state (re-asserted every tick) and the debug checkbox both wrote
## `active` directly, clobbering an unchecked box back to true. Track apart.
var _grounded: bool = true
var _debug_force_disabled: bool = false


func set_character_grounded(value: bool) -> void:
	_grounded = value
	var desired := value and not _debug_force_disabled
	if active == desired:
		return
	reset_runtime_state()
	active = desired
	_landing_grace_time = LANDING_GRACE_DURATION if desired else 0.0
	if _native_backend != null:
		_native_backend.set_enabled(desired and solver_backend == SolverBackend.NATIVE_TWO_BONE)


func set_solver_backend(value: SolverBackend) -> void:
	if solver_backend == value:
		return
	reset_runtime_state()
	solver_backend = value
	if _native_backend != null:
		_native_backend.set_enabled(active and solver_backend == SolverBackend.NATIVE_TWO_BONE)


func set_debug_enabled(value: bool) -> void:
	_debug_force_disabled = not value
	var desired := _grounded and not _debug_force_disabled
	active = desired
	reset_runtime_state()
	if _native_backend != null:
		_native_backend.set_enabled(desired and solver_backend == SolverBackend.NATIVE_TWO_BONE)


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
	for side: StringName in _bone_indices:
		_sole_depth_below_foot[side] = _measure_leg_sole_depth(skel, side)
		if LOG_SOLE_DEPTH:
			print("[FootIK] ", side, " measured planted sole depth below foot origin=",
					_sole_depth_below_foot[side])


## The rig's rest/bind pose is the one reference guaranteed to show the
## character standing flat-footed on level ground (no animation-specific
## ankle relaxation to bias the reading), so it's a more reliable source for
## "which direction is the sole normal" than sampling any one animated frame.
## Returns the EXACT rest-pose local-space direction of world down - not
## snapped to the nearest cardinal axis (±X/±Y/±Z). An earlier version did
## snap to the nearest axis, assuming the rig's local axes align with world
## down/forward/right and any mismatch was just animation noise; measured
## against this rig's actual rest pose, the nearest axis was still ~26.6
## degrees off. Since _toe_rest_offset/_leaf_rest_offset (_ready() below) are
## expressed in this SAME local frame and get carried through the corrected
## foot basis every frame (see _solve_leg), that quantization error was
## reproduced exactly on the toe and leaf too - a visible kink with nothing
## to do with the rig geometry, only rounding. The exact direction keeps the
## whole chain's original geometric relationships intact.
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
## foot_pose is passed in, not re-read, so a caller can hand in a held pose.
func _compute_new_foot_basis_world(
		skel: Skeleton3D, side: StringName, desired_down: Vector3,
		foot_pose: Transform3D) -> Basis:
	var to_world := skel.global_transform
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


## Measures how far this leg's own planted bind geometry extends below the
## foot bone's origin, once at rig setup. Bone origins sit at joints, not the
## lowest skinned sole point - ball/toe bind geometry can hang several cm
## below the toe bone origin (measured ~9mm into the tread before this
## existed), so origins + a toe-tip margin alone still look sunk into the floor.
## Data-driven (no per-asset constants): CPU-skins every skinned vertex that
## influences this leg's foot/toe/leaf bones through their flat planted pose -
## foot on the level-ground corrected basis at ZERO, toe/leaf at their
## full-weight rest offsets, exactly what the solver produces at full
## ground_weight - reports the deepest point below the foot origin, matching
## foot_ik_leg_solver.gd's own output 1:1 with the rendered planted sole.
func _measure_leg_sole_depth(skel: Skeleton3D, side: StringName) -> float:
	var indices: Dictionary = _bone_indices[side]
	var chain := {int(indices["foot"]): true}
	if indices["toe"] >= 0:
		chain[int(indices["toe"])] = true
	if indices["leaf"] >= 0:
		chain[int(indices["leaf"])] = true
	var foot_bone_pose := skel.get_bone_global_pose(int(indices["foot"]))
	var planted_basis := _compute_new_foot_basis_world(skel, side, Vector3.DOWN, foot_bone_pose)
	var chain_poses := {int(indices["foot"]): Transform3D(planted_basis, Vector3.ZERO)}
	if indices["toe"] >= 0:
		chain_poses[int(indices["toe"])] = Transform3D(
				planted_basis * (_toe_rest_relative_basis[side] as Basis),
				planted_basis * (_toe_rest_offset[side] as Vector3))
	if indices["leaf"] >= 0:
		chain_poses[int(indices["leaf"])] = Transform3D(
				planted_basis * (_leaf_rest_relative_basis[side] as Basis),
				planted_basis * (_leaf_rest_offset[side] as Vector3))
	var max_depth := 0.0
	if player_body == null or not is_instance_valid(player_body.character):
		return max_depth
	var meshes := player_body.character.find_children("*", "MeshInstance3D", true, false)
	for mesh_node: Node in meshes:
		var mesh_part := mesh_node as MeshInstance3D
		if mesh_part == null or mesh_part.mesh == null:
			continue
		var skin_reference := mesh_part.get_skin_reference()
		if skin_reference == null:
			continue
		var skin := skin_reference.get_skin()
		if skin == null:
			continue
		var is_chain_bind: Array[bool] = []
		is_chain_bind.resize(skin.get_bind_count())
		var planted_bind_transforms: Array[Transform3D] = []
		planted_bind_transforms.resize(skin.get_bind_count())
		for bind_index in skin.get_bind_count():
			var bone_index := skin.get_bind_bone(bind_index)
			if bone_index < 0:
				bone_index = skel.find_bone(skin.get_bind_name(bind_index))
			var in_chain: bool = bone_index >= 0 and chain.has(bone_index)
			is_chain_bind[bind_index] = in_chain
			if in_chain:
				# Same composition as the runtime skin (bone pose then the
				# skin's per-bone bind pose), with the chain bone taking its
				# flat planted pose - omitting the bind pose here made the
				# measured sole depth ~1.5cm shallow vs the rendered mesh.
				planted_bind_transforms[bind_index] = (
						chain_poses[bone_index] * skin.get_bind_pose(bind_index))
			elif bone_index >= 0:
				# Non-chain influences (e.g. the shin pulling on ankle-top
				# vertices) keep their rest pose; the deepest sole vertices
				# are foot-chain-dominant, so this only biases the top edge.
				planted_bind_transforms[bind_index] = (
						skel.get_bone_global_pose(bone_index) * skin.get_bind_pose(bind_index))
			else:
				planted_bind_transforms[bind_index] = Transform3D.IDENTITY
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := (
					arrays[Mesh.ARRAY_BONES] as PackedInt32Array
					if arrays[Mesh.ARRAY_BONES] is PackedInt32Array else PackedInt32Array())
			var weights := (
					arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
					if arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array else PackedFloat32Array())
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var influences := bones.size() / vertices.size()
			for vertex_index in vertices.size():
				var touches_chain := false
				for influence in influences:
					var bind_index: int = bones[vertex_index * influences + influence]
					if (bind_index >= 0 and bind_index < is_chain_bind.size()
							and is_chain_bind[bind_index]):
						touches_chain = true
						break
				if not touches_chain:
					continue
				var planted := Vector3.ZERO
				var total_weight := 0.0
				for influence in influences:
					var array_index := vertex_index * influences + influence
					var weight: float = weights[array_index]
					var bind_index: int = bones[array_index]
					if (weight <= 0.0 or bind_index < 0
							or bind_index >= planted_bind_transforms.size()):
						continue
					planted += (planted_bind_transforms[bind_index] * vertices[vertex_index]) * weight
					total_weight += weight
				if total_weight > 0.0:
					max_depth = maxf(max_depth, -(planted / total_weight).y)
	return max_depth


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	_stair_predictor.update_travel_direction(delta)
	if delta > 0.0:
		_landing_grace_time = maxf(0.0, _landing_grace_time - delta)
	_gait_tracker.update_animation_discontinuity(delta)

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
		var hip_pose := skel.get_bone_global_pose(hip_idx)
		var animated_foot_pose := skel.get_bone_global_pose(foot_idx)
		# solve() holds its own internal reads across a loop-reset frame, but
		# this hip_pos/foot_pos, read earlier and passed straight into solve()
		# as the final hip placement, was still popping unheld.
		if _animation_discontinuous and _prev_leg_bone_poses.has(side):
			var held: Dictionary = _prev_leg_bone_poses[side]
			hip_pose = held["hip"]
			animated_foot_pose = held["foot"]
		var hip_pos: Vector3 = to_world * hip_pose.origin
		var animated_foot_pos := animated_foot_pose.origin
		var foot_pos: Vector3 = to_world * animated_foot_pos

		# Read before _sample_ground_contact() (which only reads, never writes,
		# _prev_animated_foot_pos - the gait tracker owns that update, later)
		# so the primary-ray fallback below can tell a genuinely stationary
		# foot apart from one mid-swing without waiting a frame.
		var anim_speed := _animated_vertical_speed(
				side, animated_foot_pos, to_world, delta)
		var likely_idle := absf(anim_speed) <= idle_step_down_speed \
				or _landing_grace_time > 0.0 # see _landing_grace_time's doc comment
		var frozen: bool = _gait_tracker.update_idle_freeze(side, anim_speed, delta)
		var contact := _sample_ground_contact(skel, space, side, animated_foot_pose,
				foot_pos, to_world, delta, likely_idle, frozen)
		per_leg[side] = {"hip_pos": hip_pos, "hit": contact["hit"], "upper": upper_length,
				"lower": lower_length, "vertical_velocity": 0.0}
		if not contact["hit"]:
			debug_contact_hit[side] = false
			debug_contact_distance[side] = -1.0
			debug_step_down[side] = false
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

		var classification := _step_down_classification(
				side, hip_pos, ground_target, animated_contact_hit,
				animated_contact_distance, anim_speed, upper_length, lower_length)
		var step_down: bool = classification["plant"]
		if classification["settle"]:
			# Frozen: keep the settled target fixed - this search otherwise
			# reruns and direct-overwrites the target with no smoothing.
			if not frozen:
				var retracted := _retract_to_reachable(space, hip_pos, ground_target,
						upper_length, lower_length)
				debug_retracted[side] = retracted["found"]
				if retracted["found"]:
					ground_target = retracted["target"]
					_smoothed_target[side] = retracted["surface"]
					_smoothed_normal[side] = retracted["normal"]
			# Either way, reach as far as a deep-but-human crouch allows (see
			# step_down_max_crouch below) rather than snap back to animated.
			step_down = true
		else:
			debug_retracted[side] = false
		debug_step_down[side] = step_down
		var gait_flags := {"step_down": step_down, "frozen": frozen,
				"skip_velocity_gate": _landing_grace_time > 0.0}
		var gait: Dictionary = _gait_tracker.update(side, animated_foot_pos, foot_pos, ground_target,
				animated_contact_hit, animated_contact_distance, to_world, delta, gait_flags)
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
					animated_lowest_point, ground_weight, landed, delta, step_down)

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
		debug_contact_hit[side] = animated_contact_hit
		debug_contact_distance[side] = (
				animated_contact_distance if animated_contact_hit else -1.0)
		if preserve_idle_pose:
			continue
		var max_reach := upper_length + lower_length - 0.001
		var horizontal_dist_sq := Vector2(hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
		var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
		var needed_drop: float = (hip_pos.y - target.y) - max_vertical_diff
		shared_drop = maxf(shared_drop, needed_drop)
	shared_drop = minf(shared_drop, step_down_max_crouch)

	_apply_support_pelvis_and_legs(skel, to_world, per_leg, shared_drop)
	for i in skel.get_bone_count():
		_final_bone_poses[i] = skel.get_bone_global_pose(i)


## Mirrors foot_ik_gait_tracker._measure_velocity so the step-down static test
## uses the exact same per-frame foot speed the weight logic sees. Reads the
## previous frame's skeleton-space foot position, which the gait tracker has
## already stored, and measures relative to the skeleton so root stair-hover
## translation cannot masquerade as foot motion.
func _animated_vertical_speed(side: StringName, animated_foot_pos: Vector3,
		to_world: Transform3D, delta: float) -> float:
	var velocity := 0.0
	# Same loop-reset jump _measure_velocity() guards against - missed here it
	# spiked anim_speed, hard-resetting the static streak (a full-body pop).
	# Uses the wider _velocity_suppressed window (see update_animation_discontinuity).
	if delta > 0.0 and not _velocity_suppressed and _prev_animated_foot_pos.has(side):
		var previous: Vector3 = _prev_animated_foot_pos[side]
		var world_delta := to_world.basis * (animated_foot_pos - previous)
		velocity = world_delta.dot(_smoothed_normal[side] as Vector3) / (
				delta * maxf(player_body.locomotion_playback_scale, 0.001))
	# Only gait_tracker's own successful update() writes this reference
	# normally (see _prev_animated_foot_pos's doc comment) - deliberately
	# frozen during a genuine swing, which is the correct signal there. But
	# within landing grace we already distrust anim_speed entirely (see
	# _landing_grace_time), so refresh here too or this leg can exit grace
	# still stale and fall right back into the deadlock grace fixed.
	if _landing_grace_time > 0.0:
		_prev_animated_foot_pos[side] = animated_foot_pos
	return velocity


## Classifies this stationary foot's relationship to a lower surface it
## hovers over (stair-riser straddle). Requires a sustained streak of static
## frames so a swing's single near-zero-velocity apex frame can never fake
## "stationary", and the sole to be meaningfully above the lower surface
## (more than GROUND_CONTACT_DISTANCE, else ordinary planting handles it).
## Within step_down_pelvis_drop of shared-pelvis sink it plants via the
## ordinary skeleton-only sink ("plant"). Beyond that, the standing leg
## can't reach it with a sink alone - reported as "settle" so the caller
## retracts the target toward the hip instead (see _retract_to_reachable).
## contact_hit/contact_distance may come from _sample_ground_contact's much
## longer idle-only fallback probe, so a "settle" target here can be
## arbitrarily far below - fine, retraction searches independently of that.
func _step_down_classification(side: StringName, hip_pos: Vector3, ground_target: Vector3,
		contact_hit: bool, contact_distance: float, anim_speed: float,
		upper_length: float, lower_length: float) -> Dictionary:
	if not step_prediction_enabled or force_plant_mode:
		_step_down_static_streak[side] = 0
		return {"plant": false, "settle": false}
	# Decay by 1 (not a hard reset to 0) only for marginal noise just above
	# idle_step_down_speed - ordinary idle jitter can tick anim_speed slightly
	# over that line for one frame without the foot being any less stationary,
	# and a hard reset there made step_down flicker true/false continuously,
	# flickering the contact_lost bypass along with it and keeping
	# ground_weight pinned at 0 before it could finish ramping up. A genuine
	# swing start still needs an immediate, full reset or the foot starts
	# planting toward the old target before it's lifted, sinking into the
	# tread it's swinging over - confirmed via the body penetration check,
	# which caught exactly that regression from decaying unconditionally.
	var streak: int = _step_down_static_streak.get(side, 0)
	if absf(anim_speed) <= idle_step_down_speed:
		streak += 1
	elif absf(anim_speed) <= idle_step_down_speed * 2.0:
		streak = maxi(0, streak - 1)
	else:
		streak = 0
	_step_down_static_streak[side] = streak
	# Also bypass during landing grace (else a contact_lost frame pops weight).
	if (int(_step_down_static_streak.get(side, 0)) < STEP_DOWN_STATIC_STREAK
			and _landing_grace_time <= 0.0):
		return {"plant": false, "settle": false}
	if not contact_hit or not is_finite(contact_distance):
		return {"plant": false, "settle": false}
	if contact_distance <= GROUND_CONTACT_DISTANCE:
		return {"plant": false, "settle": false}
	var max_reach := upper_length + lower_length - 0.001
	var horizontal_dist_sq := Vector2(
			hip_pos.x - ground_target.x, hip_pos.z - ground_target.z).length_squared()
	var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
	var needed_sink := (hip_pos.y - ground_target.y) - max_vertical_diff
	if needed_sink <= step_down_pelvis_drop:
		return {"plant": true, "settle": false}
	return {"plant": false, "settle": true}


const RETRACT_STEPS := 8

## When a stationary foot's own ground target needs more pelvis sink than
## step_down_pelvis_drop allows, don't leave it floating at that distant
## point, and don't move the whole capsule toward it either - an earlier
## whole-body walk-down approach proved too eager in practice (it kept
## marching the character down an entire staircase from a single idle foot,
## unprompted, once one drop triggered it). Instead pull the target
## horizontally back toward the hip, re-probing the ground at each step,
## until a point within ordinary reach is found - like a person shortening
## their stride near a drop-off. Directly under the hip is reachable for any
## physically plausible standing rig, so this usually finds something well
## before running out of steps. A probe that finds nothing reachable at any
## step is a genuine ledge/void; the caller leaves that foot floating.
func _retract_to_reachable(space: PhysicsDirectSpaceState3D, hip_pos: Vector3,
		ground_target: Vector3, upper_length: float, lower_length: float) -> Dictionary:
	var max_reach := upper_length + lower_length - 0.001
	var from_xz := Vector2(ground_target.x, ground_target.z)
	var to_xz := Vector2(hip_pos.x, hip_pos.z)
	for i in RETRACT_STEPS + 1:
		var xz := from_xz.lerp(to_xz, float(i) / RETRACT_STEPS)
		var hit := _raycast_ground(
				space, Vector3(xz.x, hip_pos.y, xz.y), idle_settle_search_down)
		if not hit["hit"]:
			continue
		var normal: Vector3 = hit["normal"]
		var surface: Vector3 = hit["position"]
		var target := surface + normal * ankle_offset
		var horizontal_dist_sq := Vector2(
				hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
		var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
		var needed_sink: float = (hip_pos.y - target.y) - max_vertical_diff
		if needed_sink <= step_down_pelvis_drop:
			return {"found": true, "target": target, "surface": surface, "normal": normal}
	return {"found": false}


func _sample_ground_contact(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		side: StringName, foot_pose: Transform3D, foot_pos: Vector3, to_world: Transform3D,
		delta: float, likely_idle: bool = false, frozen: bool = false) -> Dictionary:
	var hit := _raycast_ground(space, foot_pos)
	if not hit["hit"] and likely_idle and step_prediction_enabled:
		# Nothing within the ordinary ray_down at the raw ankle position
		# either - not just the toe-tip-predicted point below. The short
		# range exists to protect mid-swing gait timing (see
		# idle_settle_search_down's doc comment); a stationary foot has no
		# such concern, so try once more here before falling back to the
		# animated pose - otherwise a foot resting further than ray_down
		# above real ground floats even though _sample_ground_contact's own
		# secondary-probe fallback below would have caught a shallower miss.
		hit = _raycast_ground(space, foot_pos, idle_settle_search_down)
	var raw_target: Vector3 = hit["position"] if hit["hit"] else foot_pos
	var raw_normal: Vector3 = hit["normal"] if hit["hit"] else Vector3.UP
	if not _smoothed_target.has(side):
		_smoothed_target[side] = raw_target
		_smoothed_normal[side] = raw_normal
	# Frozen: keep target fixed. Else reject sub-deadband noise outright.
	if not frozen and raw_target.distance_to(
			_smoothed_target[side] as Vector3) > TARGET_NOISE_DEADBAND:
		var amount := clampf(delta * smooth_rate, 0.0, 1.0)
		_smoothed_target[side] = (_smoothed_target[side] as Vector3).lerp(raw_target, amount)
		_smoothed_normal[side] = (_smoothed_normal[side] as Vector3).lerp(
				raw_normal, amount).normalized()
	if not hit["hit"] and not frozen:
		return {"hit": false}
	var desired_down := -(_smoothed_normal[side] as Vector3)
	var foot_basis := _compute_new_foot_basis_world(skel, side, desired_down, foot_pose)
	var toe_offset: Vector3 = foot_basis * (_toe_rest_offset.get(side, Vector3.ZERO) as Vector3)
	var tip_offset := toe_offset
	if not toe_offset.is_zero_approx():
		tip_offset += toe_offset.normalized() * toe_tip_margin
	var effective_offset := maxf(ankle_offset, maxf(
			tip_offset.dot(desired_down), _sole_depth_below_foot.get(side, 0.0)))
	var animated_lowest_point := foot_pos
	var surface_hit := {"hit": false}
	if step_prediction_enabled:
		animated_lowest_point = _animated_lowest_surface_point_world(
				skel, side, foot_pose, foot_pos, to_world)
		surface_hit = _raycast_ground(space, animated_lowest_point)
		if not surface_hit["hit"]:
			# The ordinary probe stays short so a mid-swing foot never "sees" a
			# distant floor and distorts gait timing - but that means a foot
			# hanging further than ray_down over open air reports no contact at
			# all. A stationary foot has no swing-timing concern, so try once
			# more at idle_settle_search_down before accepting there is truly
			# nothing to stand on; _step_down_classification treats a hit found
			# only here the same as any other settle target.
			surface_hit = _raycast_ground(space, animated_lowest_point, idle_settle_search_down)
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
			# A steep ramp needs pelvis sink every frame (reachability), so
			# this read is just as exposed to the loop-reset seam as the legs.
			var fresh_pelvis := skel.get_bone_global_pose(pelvis_idx)
			var pelvis_pose := fresh_pelvis
			if _animation_discontinuous and _has_prev_pelvis_pose:
				pelvis_pose = _prev_pelvis_pose
			_prev_pelvis_pose = fresh_pelvis
			_has_prev_pelvis_pose = true
			var pelvis_world := to_world * pelvis_pose
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


func _raycast_ground(
		space: PhysicsDirectSpaceState3D, foot_pos: Vector3, down: float = -1.0) -> Dictionary:
	var from := foot_pos + Vector3.UP * ray_up
	var to := foot_pos + Vector3.DOWN * (down if down > 0.0 else ray_down)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GROUND_COLLISION_MASK
	query.collide_with_areas = false
	if is_instance_valid(player_body) and player_body.get_parent() is CollisionObject3D:
		query.exclude = [(player_body.get_parent() as CollisionObject3D).get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {"hit": false, "position": foot_pos, "normal": Vector3.UP}
	return {"hit": true, "position": result["position"], "normal": result["normal"]}
