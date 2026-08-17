class_name PlayerFootIKModifier
extends SkeletonModifier3D
## TEMPORARY / EXPERIMENTAL: split into contact, gait, stair-prediction, and
## bone-solve phases; stair-walking result still not accepted (see docs).
## Plants each foot on the actual ground/step surface beneath it instead of
## wherever the flat-ground-authored locomotion clips leave it - raycasts
## straight down from the animated foot, bends hip/knee to reach that point
## (closed-form two-bone IK), tilts the foot to match the surface normal.
## Mirrors player_hand_grip_modifier.gd / player_look_pose_modifier.gd.

signal foot_landed(side: StringName, ground_position: Vector3)
const LOG_SOLE_AXIS := true # rest-pose sole axis mismatch logs, not silently breaks
const LOG_SOLE_DEPTH := true # logs measured planted sole point count per leg at rig setup
const LEG_SOLVER := preload("res://actors/player/foot_ik/foot_ik_leg_solver.gd")
const GAIT_TRACKER := preload("res://actors/player/foot_ik/foot_ik_gait_tracker.gd")
const STAIR_PREDICTOR := preload("res://actors/player/foot_ik/foot_ik_stair_predictor.gd")
const NATIVE_BACKEND := preload("res://actors/player/foot_ik/foot_ik_native_backend.gd")
const GROUND_SAMPLER := preload("res://actors/player/foot_ik/foot_ik_ground_sampler.gd")
const RESIDUAL_CORRECTOR := preload("res://actors/player/foot_ik/foot_ik_residual_corrector.gd")
const PHASE_LOCKED_CORRECTOR := preload(
		"res://actors/player/foot_ik/foot_ik_phase_locked_corrector.gd")

enum SolverBackend { CUSTOM, NATIVE_TWO_BONE }
## LEGACY: full gait-tracker/stair-predictor pipeline (default, untouched).
## RESIDUAL_STAIR: raycast + always-on full-weight solve + one pelvis sink,
## no swing/stance tracking (see docs/foot_ik_industry_review.md).
## PHASE_LOCKED: samples ground once per footfall (gait tracker's `landed`
## event), holds the target fixed for a timed stance window.
enum LocomotionMode { LEGACY, RESIDUAL_STAIR, PHASE_LOCKED }

## Search range above/below the animated foot; ray_down covers the tallest riser plus stride margin.
@export var ray_up: float = 0.5
@export var ray_down: float = 0.6
@export var idle_settle_search_down: float = 4.0 # idle fallback depth when ray_down finds nothing
const GROUND_CONTACT_DISTANCE := 0.03
const DEEP_PLANT_PENETRATION := 0.05
## Approximate sole thickness/ankle clearance - the floor under
## effective_offset's other terms, for a leg whose toe doesn't droop at all.
@export var ankle_offset: float = 0.0475
## How far past the toe bone's own origin the visible mesh tip extends -
## bone origins sit at joints, not mesh extremes (matches the debug
## overlay's own TOE_TIP_EXTRA_LENGTH).
@export var toe_tip_margin: float = 0.035
## Exponential-smoothing rate for the raycast target/normal, so the foot
## doesn't pop between tread heights. Live-tunable via the debug panel.
@export var smooth_rate: float = 7.0
## Hard cap (m/s) on smooth_rate's per-frame target move - must stay above
## the player's fastest ground speed (roll_speed), or a lagging target grows
## an ever-larger hip-to-target gap each stride until the shared pelvis sink
## maxes out (confirmed live: the periodic walking hip snap).
@export var target_max_speed: float = 10.0
## How fast the *animated*, uncorrected foot's rising/falling (m/s) counts as
## "mid-swing" - blends from full strength at 0 speed to none here, instead of
## applying unconditionally (else the raycast plants toward the same ground
## point even while the animation lifts the foot). Velocity-based, not
## height-based: height alone broke static standing on a tall stair tread.
@export var swing_speed_threshold: float = 0.35
## How much more harshly RISING vertical velocity counts against
## swing_speed_threshold than same-magnitude FALLING velocity - a continuous
## scale-up, not a sign cutoff at 0 (that caused idle-noise twitch).
@export var rising_penalty: float = 4.0
## Consecutive clearly-falling frames needed before trusting a real landing
## approach - filters the low-speed blip near a swing apex without delay.
@export var min_falling_streak: int = 3
## Velocity magnitude (m/s) below which vertical motion is ignored entirely,
## treated as stationary before rising_penalty applies - rising_penalty alone
## doesn't fully remove idle noise sensitivity.
@export var velocity_noise_floor: float = 0.03
## Minimum time (seconds) for ground_weight to rise from 0 to 1 - caps how
## fast the correction can snap back ON, without limiting snap OFF speed. A
## walk cycle's vertical velocity crosses exactly zero for one frame at the
## swing arc's top, which reads as "foot stopped, must be planted," briefly
## pulling the foot down mid-air before the next frame's real velocity
## releases it (measured: 0.282 vs animation's own 0.353 at a stride's peak).
@export var ground_weight_rise_time: float = 0.24
## Same idea as ground_weight_rise_time, opposite direction. An earlier
## version let the fall happen in a single frame (a genuine swing start
## needs to release immediately), but the same instant-fall path also fired
## when recovering from the small residual rise near a swing peak, snapping
## "leg bent extra to plant" back to raw animation in one frame (confirmed:
## knee bend 75.0 -> 89.4 in one frame; a 0.05s release still removed a
## third of correction per frame, a 26.6-degree thigh jump at toe-off).
## Same longer ramp both ways on ordinary ground; gait tracker keeps the faster stair-hover timing.
@export var ground_weight_fall_time: float = 0.24
@export var step_prediction_enabled: bool = true
@export var step_prediction_distance: float = 0.6
@export var step_min_rise: float = 0.05
@export var step_clearance_margin: float = 0.11
@export var step_lift_rate: float = 4.0
## Seconds to blend foot/pelvis when stair support hands off to the other leg
## (see foot_ik_stair_predictor.gd) - was an instant snap, once-per-step pop.
@export var support_transfer_blend_time: float = 0.08
@export var step_down_transition_lift: float = 0.1 # step-down mid-transition lift, see below
@export var flat_idle_noop_distance: float = 0.01 # Preserve authored idle inside 1 cm.
@export_range(0.0, 170.0, 1.0) var max_knee_flexion_degrees: float = 150.0
@export_range(10.0, 170.0, 1.0) var max_hip_swing_degrees: float = 100.0 # cone from straight down
## When true, overrides the gait tracker's contact-lost check and forces both
## feet to plant on the ground. Used by the foot IK harness during inspection
## idle poses where the animated foot height doesn't match the step geometry.
var force_plant_mode: bool = false
## Idle step-down: a stationary stance foot whose sole rests more than
## GROUND_CONTACT_DISTANCE above a lower surface (e.g. straddling a stair
## riser) never stays floating - requires motionless for STEP_DOWN_STATIC_STREAK
## frames. If reachable within step_down_pelvis_drop, plants directly; beyond
## that, _retract_to_reachable() pulls the target toward the hip instead of
## stretching the leg or moving the whole capsule. Nothing found, foot floats.
@export_range(0.0, 1.0, 0.01) var idle_step_down_speed: float = 0.06
@export_range(0.0, 0.75, 0.005) var step_down_pelvis_drop: float = 0.35
## Hard ceiling on shared pelvis sink for a foot _retract_to_reachable()
## couldn't rescue (the drop is deeper than the leg can reach) - looser than
## step_down_pelvis_drop's "still looks like ordinary standing" budget, this
## is "as deep a crouch as a person could plausibly do." Capping here leaves
## the leg hanging just short of target instead of an unbounded squat.
@export_range(0.0, 1.0, 0.005) var step_down_max_crouch: float = 0.6
## Max speed (m/s) the shared pelvis may RISE back toward the animated pose
## after a reach-limit sink (the per-footfall stair shake's release edge).
## The sink itself still ENGAGES instantly - delaying it would stretch the
## leg (the documented shared_drop lerp regression) - but the +5-8cm
## single-frame upward pop at each foot re-plant becomes a smooth controlled
## rise instead. A pelvis that stays lower during release only bends the
## knees more; it can never stretch or penetrate. Capped at 1.5: at 60fps
## that rate moves the pelvis 0.025m/frame, exactly the pose-continuity jump
## limit. 0.0 disables release shaping (raw behaviour).
@export_range(0.0, 4.0, 0.1) var shared_drop_release_rate: float = 1.5
## Max speed (m/s) the shared pelvis may SINK during an idle settle. Walking
## engages stay instant (the hip is climbing, so a lagged sink stretches the
## planted leg - see _shape_shared_drop's doc comment). Stationary, the hip
## doesn't move, so a gradual engage only bends the knees more each frame -
## the "controlled crouch" an idle riser straddle was always meant to read as
## - fixing the foot sag an instant 12-26cm settle engage caused (foot 16cm
## below target, leg overextended past 0.887m reach). 0.0 disables shaping.
@export_range(0.0, 4.0, 0.1) var shared_drop_idle_engage_rate: float = 1.5
const STEP_DOWN_STATIC_STREAK := 4
@export var solver_backend := SolverBackend.CUSTOM
@export var locomotion_mode := LocomotionMode.LEGACY
@export var residual_pelvis_lerp_speed: float = 6.0 # RESIDUAL_STAIR: symmetric pelvis sink m/s
## RESIDUAL_STAIR: weight from foot height above the CHARACTER ROOT (kickback).
@export var residual_plant_threshold: float = 0.17
@export var residual_swing_threshold: float = 0.25
@export var residual_foot_blend_speed: float = 10.0
@export var phase_locked_stance_time: float = 0.35 # PHASE_LOCKED: locked-weight hold seconds
@export var phase_locked_release_time: float = 0.15 # PHASE_LOCKED: ease-out seconds after hold
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
var _ground_sampler: RefCounted
var _residual_corrector: RefCounted
var _phase_locked_corrector: RefCounted

var _bone_indices: Dictionary = {} # side -> {hip, knee, foot, toe, leaf: int}
var _leg_lengths: Dictionary = {} # side -> {upper, lower: float}
var _sole_down_local: Dictionary = {} # side -> Vector3, one of the 6 principal axes
## Max extent of this leg's planted bind geometry below the foot bone's
## origin (meters), measured once at rig setup - fed into effective_offset
## so a planted sole clears the ground even when the ball/toe geometry
## hangs below the bone origins. Orientation-invariant by construction:
## _compute_new_foot_basis_world() rotates the foot so its local down-axis
## always matches the ground normal, so this scalar never varies with tilt.
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
## out of an unstable perpendicular-axis choice, spinning the foot ~90+
## degrees when the animated sole ends up close to opposite the target.
var _foot_frame_local: Dictionary = {} # side -> Basis
## Last toe-leaf transforms tracked too; stale weighted leaf poses kinked the
## visible toe even when every corrected parent measured flat.
var _leaf_rest_offset: Dictionary = {} # side -> Vector3 (relative to toe)
var _leaf_rest_relative_basis: Dictionary = {} # side -> Basis (relative to toe)
## Compatibility views used by the focused gait/predictor/solver helpers and
## persistent diagnostics. FootIKGroundSampler owns the actual dictionaries.
var _smoothed_target: Dictionary:
	get:
		return _ground_sampler.smoothed_target if _ground_sampler != null else {}
var _smoothed_normal: Dictionary:
	get:
		return _ground_sampler.smoothed_normal if _ground_sampler != null else {}
## Previous frame's animated foot position in skeleton space. Measuring
## relative to the skeleton excludes player/root stair-hover translation;
## otherwise both feet falsely become "swinging" whenever the visible body
## eases upward, releasing and re-engaging IK once per tread.
var _prev_animated_foot_pos: Dictionary = {} # side -> Vector3 (skeleton)
## Held bone poses reused by the leg solver in place of a fresh (possibly
## seam-jumped) skeleton read on a loop-reset frame - see solve()'s doc.
var _prev_leg_bone_poses: Dictionary = {} # side -> Dictionary
## Guards _prev_leg_bone_poses against being overwritten more than once per
## real physics frame - see solve()'s own doc comment for why.
var _prev_leg_bone_poses_frame: Dictionary = {} # side -> int (Engine.get_physics_frames())
## Same-tick baseline cache for solve()'s own fresh_poses read - see
## foot_ik_leg_solver.gd's solve() doc comment.
var _leg_fresh_pose_cache: Dictionary = {} # side -> Dictionary
var _leg_fresh_pose_cache_frame: int = -1
var _prev_pelvis_pose: Transform3D
var _has_prev_pelvis_pose: bool = false
## Pre-sink pelvis pose baseline, cached once per real tick - see the
## twice-per-tick note where it's used.
var _pelvis_base_pose: Transform3D
var _pelvis_base_pose_frame: int = -1
## Rate-limited (fast fall, slow rise) version of the raw velocity-derived
## ground_weight - see ground_weight_rise_time's own doc comment.
var _smoothed_ground_weight: Dictionary = {} # side -> float
var _falling_streak: Dictionary = {} # side -> int, see min_falling_streak's doc comment
var _rising_streak: Dictionary = {} # side -> int, see _raw_weight()'s doc comment
var _weight_stuck_time: Dictionary = {} # side -> float, watchdog for gait_tracker's _smooth_weight
var _landing_fell: Dictionary = {} # side -> bool
var _step_down_static_streak: Dictionary = {} # side -> int
# Counts down after set_character_grounded()'s airborne->grounded transition.
var _landing_grace_time := 0.0
var _prev_animation_position := -1.0 # see update_animation_discontinuity()'s doc comment
var _animation_discontinuous := false # ditto - pose-hold/contact_lost window
var _animation_discontinuity_hold := 0 # ditto
var _velocity_suppressed := false # ditto - wider, velocity-only window
var _velocity_suppress_hold := 0 # ditto
const LANDING_GRACE_DURATION := 0.35
var _idle_frozen: Dictionary = {} # side -> bool, see gait_tracker's update_idle_freeze() doc
var _idle_freeze_streak: Dictionary = {} # side -> int, ditto
var _idle_unfreeze_streak: Dictionary = {} # side -> int, ditto
var _idle_freeze_yaw: Dictionary = {} # side -> float (rad), ditto
var _smoothed_step_lift: Dictionary:
	get:
		return _stair_predictor.get_step_lifts() if _stair_predictor != null else {}
var predicted_step_targets: Dictionary:
	get:
		return _stair_predictor.get_predicted_targets() if _stair_predictor != null else {}
var debug_vertical_velocity: Dictionary = {} # side -> pre-IK animation velocity
## Surface-to-surface measurement used by the gait tracker: vertical distance
## from the animated sole/toe lowest point to the secondary ground ray hit.
## INF when no secondary contact; exposes the controlled character's own
## value so harness readouts don't borrow the 0.35m walker's rays.
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
## Asymmetric shaping of the shared pelvis reach-limit sink: the sink value
## itself engages instantly (a delayed sink stretches the leg), but the value
## the pelvis is allowed to RISE back toward is rate-limited so a per-footfall
## reach-limit release does not pop the whole body up 5-8cm in one frame.
var _smoothed_shared_drop := 0.0

## External harnesses read the post-IK skeleton-space pose here instead of
## Skeleton3D.get_bone_global_pose() at their own (idle/deferred) time, where
## the skeleton may still hold the pre-IK animated pose (AGENTS.md).
func get_final_bone_global_pose(bone_idx: int) -> Transform3D:
	return _final_bone_poses.get(bone_idx, Transform3D())
var _forced_support_side: StringName:
	get:
		return _stair_predictor.get_support_side() if _stair_predictor != null else &""
var _knee_pole_local: Dictionary = {} # side -> Vector3
func reset_runtime_state() -> void:
	if _leg_solver != null:
		_leg_solver.reset_runtime_state()
	if _gait_tracker != null: _gait_tracker.reset_runtime_state()
	if _ground_sampler != null:
		_ground_sampler.reset()
	_prev_animated_foot_pos.clear()
	_prev_leg_bone_poses.clear()
	_prev_leg_bone_poses_frame.clear()
	_has_prev_pelvis_pose = false
	_pelvis_base_pose_frame = -1
	_smoothed_shared_drop = 0.0
	_leg_fresh_pose_cache.clear()
	_leg_fresh_pose_cache_frame = -1
	_smoothed_ground_weight.clear()
	_falling_streak.clear()
	_rising_streak.clear()
	_weight_stuck_time.clear()
	_landing_fell.clear()
	_step_down_static_streak.clear()
	_idle_frozen.clear()
	_idle_freeze_streak.clear()
	_idle_unfreeze_streak.clear()
	_idle_freeze_yaw.clear()
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
var _grounded: bool = true
var _debug_force_disabled: bool = false
var _pose_suppressed: bool = false

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

func set_pose_suppressed(value: bool) -> void:
	if _pose_suppressed == value:
		return
	_pose_suppressed = value
	reset_runtime_state()

func _ready() -> void:
	_ground_sampler = GROUND_SAMPLER.new(self)
	_residual_corrector = RESIDUAL_CORRECTOR.new(self)
	_phase_locked_corrector = PHASE_LOCKED_CORRECTOR.new(self)
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
				# Relative to the *foot's* rest transform, not the toe's - the
				# toe's own bind pose isn't perfectly flat either (same bias
				# _derive_sole_down_local found on the foot), so anchoring
				# straight to the foot avoids compounding a second bone's bias.
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

## The rig's rest/bind pose is the one guaranteed flat-footed reference for
## "which direction is the sole normal". Returns the EXACT rest local-space
## direction of world down - not snapped to a cardinal axis (an earlier snap
## was ~26.6 degrees off, kinking the toe/leaf via _toe_rest_offset).
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

## Picks a local "forward" reference orthogonal to sole_down_local to keep the
## foot's rebuilt twist/roll well-defined instead of an unstable single-vector
## rotation. The rest-pose toe offset is the natural choice; a cardinal axis
## fallback works for a toe-less rig (RIGHT/UP/FORWARD stay mutually orthogonal).
func _derive_forward_local(sole_down_local: Vector3, toe_offset_local: Vector3) -> Vector3:
	var raw := toe_offset_local
	if raw.is_zero_approx():
		raw = Vector3.FORWARD if absf(sole_down_local.dot(Vector3.FORWARD)) < 0.5 else Vector3.RIGHT
	var forward := raw - sole_down_local * raw.dot(sole_down_local)
	if forward.length_squared() < 0.0001:
		var fallback := Vector3.RIGHT if absf(sole_down_local.dot(Vector3.RIGHT)) < 0.5 else Vector3.UP
		forward = fallback - sole_down_local * fallback.dot(sole_down_local)
	return forward.normalized()

## Built from two explicit reference vectors (ground-down, rest toe-forward)
## Derives the grounded foot basis aligned to desired_down while preserving
## authored foot yaw (falling back to rest forward if foot is vertical).
func _compute_new_foot_basis_world(
		skel: Skeleton3D, side: StringName, desired_down: Vector3,
		foot_pose: Transform3D) -> Basis:
	var to_world := skel.global_transform
	var local_frame: Basis = _foot_frame_local[side]
	var anim_forward: Vector3 = (to_world.basis * foot_pose.basis) * local_frame.z
	var world_forward := anim_forward - desired_down * anim_forward.dot(desired_down)
	if world_forward.length_squared() < 0.01:
		var foot_idx: int = (_bone_indices[side] as Dictionary)["foot"]
		var rest_b: Basis = to_world.basis * skel.get_bone_global_rest(foot_idx).basis
		var rest_forward: Vector3 = rest_b * local_frame.z
		world_forward = rest_forward - desired_down * rest_forward.dot(desired_down)
	world_forward = world_forward.normalized()
	var world_right := desired_down.cross(world_forward).normalized()
	return Basis(world_right, desired_down, world_forward) * local_frame.inverse()

## Measures how far this leg's own planted bind geometry extends below the
## foot bone's origin, once at rig setup - bone origins sit at joints, not
## the lowest skinned sole point, so origins + a toe-tip margin alone still
## look sunk into the floor. Data-driven (no per-asset constants): CPU-skins
## every skinned vertex through the flat planted pose (foot at ZERO, toe/leaf
## at full-weight rest offsets) and reports the deepest point below the foot.
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
	if skel == null or _pose_suppressed:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	if locomotion_mode == LocomotionMode.RESIDUAL_STAIR:
		_residual_corrector.process(skel, space, delta)
		return
	if locomotion_mode == LocomotionMode.PHASE_LOCKED:
		_phase_locked_corrector.process(skel, space, delta)
		return
	_stair_predictor.update_travel_direction(delta)
	if delta > 0.0:
		_landing_grace_time = maxf(0.0, _landing_grace_time - delta)
	_gait_tracker.update_animation_discontinuity(delta)

	# Find the shared pelvis drop needed to keep both ground targets reachable.
	var to_world := skel.global_transform
	var per_leg: Dictionary = {} # side -> {hip_pos, target, normal, upper, lower, overreach}
	var shared_drop := 0.0
	var current_frame := Engine.get_physics_frames()
	if _leg_fresh_pose_cache_frame != current_frame:
		_leg_fresh_pose_cache.clear()
		_leg_fresh_pose_cache_frame = current_frame
	for side: StringName in _bone_indices:
		var indices: Dictionary = _bone_indices[side]
		var lengths: Dictionary = _leg_lengths[side]
		var hip_idx: int = indices["hip"]
		var foot_idx: int = indices["foot"]
		var upper_length: float = lengths["upper"]
		var lower_length: float = lengths["lower"]
		# Captured here, before _apply_support_pelvis_and_legs() sinks the
		# pelvis - reading hip/knee/foot/toe/leaf any later in the same tick
		# would return poses already skewed by that same-tick sink, since the
		# pelvis is their parent. Shared with the leg solver's own fresh-pose
		# read (see foot_ik_leg_solver.gd's solve()) so both see this same
		# true baseline instead of two different, inconsistently-timed reads.
		if not _leg_fresh_pose_cache.has(side):
			_leg_fresh_pose_cache[side] = {
				"hip": skel.get_bone_global_pose(hip_idx),
				"knee": skel.get_bone_global_pose(indices["knee"]),
				"foot": skel.get_bone_global_pose(foot_idx),
				"toe": skel.get_bone_global_pose(indices["toe"]) if indices["toe"] >= 0 else Transform3D(),
				"leaf": skel.get_bone_global_pose(indices["leaf"]) if indices["leaf"] >= 0 else Transform3D(),
			}
		var fresh: Dictionary = _leg_fresh_pose_cache[side]
		var hip_pose: Transform3D = fresh["hip"]
		var animated_foot_pose: Transform3D = fresh["foot"]
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

		# Read before contact sampling, which does not update the velocity reference.
		var anim_speed := _animated_vertical_speed(
				side, animated_foot_pos, to_world, delta)
		_gait_tracker.prepare_contact_phase(side, anim_speed, delta)
		# Loop-seam suppression reads 0.0 here - safe, not genuine idleness.
		# Trusting it fired the deep 4m idle fallback mid-sprint and snapped
		# the foot to distant geometry (confirmed live at the loop point).
		var likely_idle := (absf(anim_speed) <= idle_step_down_speed and not _velocity_suppressed) \
				or _landing_grace_time > 0.0 # see _landing_grace_time's doc comment
		# Use authored yaw; Euler extraction can flip equivalent representations when
		# the true orientation hasn't changed, reading as spurious rotation.
		var body_yaw := (player_body.get_parent() as Node3D).rotation.y
		var frozen: bool = _gait_tracker.update_idle_freeze(side, anim_speed, delta, body_yaw)
		var contact: Dictionary = _ground_sampler.sample(
				skel, space, side, animated_foot_pose,
				foot_pos, to_world, delta, likely_idle, frozen)
		per_leg[side] = {"hip_pos": hip_pos, "hit": contact["hit"], "upper": upper_length,
				"lower": lower_length, "vertical_velocity": 0.0}
		if not contact["hit"]:
			debug_contact_hit[side] = false
			debug_contact_distance[side] = -1.0
			debug_step_down[side] = false
			# Weight must still decay while contact is gone, or it sits stale
			# (often 1.0) and reasserts full correction the instant it resumes.
			if delta > 0.0 and ground_weight_fall_time > 0.0:
				var prev_weight: float = _smoothed_ground_weight.get(side, 0.0)
				_smoothed_ground_weight[side] = maxf(0.0, prev_weight - delta / ground_weight_fall_time)
			# Also refresh the shared velocity reference here, or a multi-frame
			# contact gap freezes it and the next real measurement diffs the
			# stale pose over one frame's delta - a huge phantom anim_speed
			# that flips likely_idle=false, disabling the deep idle fallback
			# and stranding an idle foot over a void with weight 0.
			if delta > 0.0:
				_prev_animated_foot_pos[side] = animated_foot_pos
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
		var deeply_penetrated := foot_pos.y - ground_target.y < -0.01
		if frozen and deeply_penetrated:
			frozen = false
			_gait_tracker.invalidate_idle_freeze(side)

		# A foot hanging past a landing's edge reads the deep idle fallback
		# as a floor beyond its own leg reach - an unreachable void the settle
		# branch below must dangle at max reach, not try to sink toward.
		var over_void: bool = (step_prediction_enabled and animated_contact_hit
				and animated_contact_distance > upper_length + lower_length)
		if frozen and over_void: # frozen re-adds the sole offset void_dangle removes
			frozen = false
			_gait_tracker.invalidate_idle_freeze(side)

		# Straddling toe tip reads probe ~0 (reaching the next higher tread) while the
		# ankle floats over the lower surface it must step down to; probe contact
		# above the ankle's ground target identifies the straddle.
		var straddling_riser: bool = animated_contact_hit and (
				animated_contact_position.y - ground_target.y > GROUND_CONTACT_DISTANCE)
		var classification := _step_down_classification(
				side, hip_pos, ground_target, animated_contact_hit,
				foot_pos.y - ground_target.y if straddling_riser else animated_contact_distance,
				anim_speed, upper_length, lower_length)
		var step_down: bool = classification["plant"]
		# Past a landing's edge, beyond leg reach: nothing is there to plant on,
		# so stop aiming the foot at a point at all (a reach target - full or
		# shortened - always reads as "touching something," confirmed live on
		# both variants) and let it hang loose on its own animated pose
		# instead, same as any other unsupported/no-target leg. Re-checked
		# every frame like the old dangle was, not gated on settle/plant.
		var void_dangle: bool = (over_void and not frozen and int(
				_step_down_static_streak.get(side, 0)) >= STEP_DOWN_STATIC_STREAK)
		if void_dangle:
			_smoothed_target[side] = foot_pos
			_smoothed_normal[side] = raw_normal
			ground_target = foot_pos
			debug_retracted[side] = false
			step_down = false
		elif classification["settle"]:
			# Frozen: keep the settled target fixed - this search reruns
			# every frame otherwise. Lerp into its result at smooth_rate
			# like ordinary raycast tracking instead of a hard snap.
			if not frozen:
				var retracted := _retract_to_reachable(space, side, hip_pos, ground_target,
						upper_length, lower_length)
				debug_retracted[side] = retracted["found"]
				if retracted["found"]:
					ground_target = retracted["target"]
					var is_flat_tread: bool = (retracted["normal"] as Vector3).dot(Vector3.UP) >= 0.999
					if _smoothed_target.has(side) and not is_flat_tread:
						_smoothed_target[side] = _ground_sampler.move_target_smoothed(
								_smoothed_target[side] as Vector3, retracted["surface"], delta)
						var amount := clampf(delta * smooth_rate, 0.0, 1.0)
						_smoothed_normal[side] = (_smoothed_normal[side] as Vector3).lerp(
								retracted["normal"], amount).normalized()
					else:
						_smoothed_target[side] = retracted["surface"]
						_smoothed_normal[side] = retracted["normal"]
			# Either way, reach as far as a deep-but-human crouch allows.
			step_down = true
		else:
			debug_retracted[side] = false
		debug_step_down[side] = step_down
		var gait_flags := {"step_down": step_down, "frozen": frozen,
				"penetrating_contact": deeply_penetrated,
				"skip_velocity_gate": _landing_grace_time > 0.0}
		var gait: Dictionary = _gait_tracker.update(side, animated_foot_pos, foot_pos, ground_target,
				animated_contact_hit, animated_contact_distance, to_world, delta, gait_flags)
		var vertical_velocity: float = gait["vertical_velocity"]
		var ground_weight: float = gait["ground_weight"]
		var landed: bool = gait["landed"]
		if landed and not void_dangle:
			_smoothed_target[side] = raw_target
			_smoothed_normal[side] = raw_normal
			ground_target = raw_ground_target
		var flat_contact: bool = (raw_normal.dot(Vector3.UP) >= 0.999
				and not _stair_predictor.has_latched_target())
		var crouch_idle_clearance := (player_body.anim_player.current_animation
				== "moves/unarmed_crouch_idle" and animated_contact_hit
				and animated_contact_distance < step_min_rise)
		var stationary_noop: bool = (ground_weight >= 0.999
				and absf(vertical_velocity) <= velocity_noise_floor
				and foot_pos.distance_to(ground_target) <= flat_idle_noop_distance)
		var preserve_idle_pose: bool = flat_contact and (crouch_idle_clearance
				or (not step_down and stationary_noop))
		var target := foot_pos if preserve_idle_pose else foot_pos.lerp(ground_target, ground_weight)
		var swing_lift := 0.0
		if step_prediction_enabled and not void_dangle:
			swing_lift = _stair_predictor.update_swing_lift(
					space, side, foot_pos, animated_foot_pose.basis, raw_target,
					animated_lowest_point, ground_weight, landed, delta,
					{"step_down": step_down, "pelvis_sink": _smoothed_shared_drop})
			target += Vector3.UP * swing_lift
		if step_down and step_down_transition_lift > 0.0 and _landing_grace_time <= 0.0:
			# Straight lerp from raw animated foot to a lower retracted target -
			# both endpoints clear the tread, but the path between can still clip
			# its edge mid-transition (worst toe clearance at ground_weight~0.49).
			# Not swing_lift (assumes airborne). Gated off _landing_grace_time:
			# step_down also fires after an ordinary jump landing, regressing
			# FOOT_IK_MOVING_LANDING_CHECK - that's airborne-grace, not a descent.
			target.y += sin(PI * clampf(ground_weight, 0.0, 1.0)) * step_down_transition_lift
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
		per_leg[side]["chain_weight"] = 1.0 if swing_lift > 0.0001 else ground_weight
		per_leg[side]["preserve_idle_pose"] = preserve_idle_pose
		debug_contact_hit[side] = animated_contact_hit
		debug_contact_distance[side] = (
				animated_contact_distance if animated_contact_hit else -1.0)
		if preserve_idle_pose:
			continue
		var max_reach := upper_length + lower_length - 0.001
		var horizontal_dist_sq := Vector2(
				hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
		var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
		var needed_drop: float = (hip_pos.y - target.y) - max_vertical_diff
		shared_drop = maxf(shared_drop, needed_drop)
	shared_drop = minf(shared_drop, step_down_max_crouch)
	# Deliberately NOT smoothed: shared_drop exists specifically so the leg
	# doesn't have to stretch while the pelvis catches up - delaying it via a
	# lerp (tried once) reintroduces exactly that stretch during the delay,
	# plus a body-penetration regression once the pelvis finally does catch
	# up abruptly (caught by FOOT_IK_BODY_PENETRATION_CHECK). Reverted.
	_apply_support_pelvis_and_legs(skel, to_world, per_leg, shared_drop, delta)
	for i in skel.get_bone_count():
		_final_bone_poses[i] = skel.get_bone_global_pose(i)
## Mirrors foot_ik_gait_tracker._measure_velocity so the step-down static
## test uses the same per-frame foot speed the weight logic sees. Skeleton
## space, so root stair-hover translation cannot masquerade as foot motion.
func _animated_vertical_speed(side: StringName, animated_foot_pos: Vector3,
		to_world: Transform3D, delta: float) -> float:
	var velocity := 0.0
	# Same loop-reset jump _measure_velocity() guards against - missed here it
	# spiked anim_speed, hard-resetting the static streak (a full-body pop).
	if delta > 0.0 and not _velocity_suppressed and _prev_animated_foot_pos.has(side):
		var previous: Vector3 = _prev_animated_foot_pos[side]
		var world_delta := to_world.basis * (animated_foot_pos - previous)
		velocity = world_delta.dot(_smoothed_normal[side] as Vector3) / (
				delta * maxf(player_body.locomotion_playback_scale, 0.001))
	# Deliberately frozen during a genuine swing otherwise (see
	# _prev_animated_foot_pos's doc). Within landing grace we already
	# distrust anim_speed, so refresh here or the leg exits grace still stale.
	if _landing_grace_time > 0.0 or _gait_tracker.is_locomotion_landing_imminent(side):
		_prev_animated_foot_pos[side] = animated_foot_pos
	return velocity

## Classifies a stationary foot hovering over a lower surface (riser
## straddle). Needs a static streak so a swing apex can't fake "stationary".
## Within step_down_pelvis_drop it plants via the ordinary sink; beyond that
## "settle" makes the caller retract toward the hip. contact_distance: ankle
## clearance when straddling, else probe dist.
func _step_down_classification(side: StringName, hip_pos: Vector3, ground_target: Vector3,
		contact_hit: bool, contact_distance: float, anim_speed: float,
		upper_length: float, lower_length: float) -> Dictionary:
	if not step_prediction_enabled or force_plant_mode:
		_step_down_static_streak[side] = 0
		return {"plant": false, "settle": false}
	# Decay by 1 (not a hard reset to 0) only for marginal noise just above
	# idle_step_down_speed - ordinary idle jitter can tick anim_speed
	# slightly over that line without the foot being less stationary; a hard
	# reset there flickered step_down/ground_weight continuously. A genuine
	# swing start still needs a full reset or the foot plants toward the old
	# target before it's lifted, sinking into the tread it's swinging over
	# (caught by the body penetration check).
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

## When a stationary foot's target needs more pelvis sink than
## step_down_pelvis_drop, pull it horizontally back toward the hip (re-probing
## each step) instead of moving the whole capsule (a whole-body version once
## marched the character down an entire staircase). Nothing reachable = void.
func _retract_to_reachable(space: PhysicsDirectSpaceState3D, side: StringName, hip_pos: Vector3,
		ground_target: Vector3, upper_length: float, lower_length: float) -> Dictionary:
	var max_reach := upper_length + lower_length - 0.001
	var from_xz := Vector2(ground_target.x, ground_target.z)
	var to_xz := Vector2(hip_pos.x, hip_pos.z)
	# Bare ankle_offset alone under-cleared the toe here (a retracted leg
	# still has a toe extending forward) - same fix as
	# FootIKGroundSampler's effective_offset.
	var offset := maxf(ankle_offset, _sole_depth_below_foot.get(side, 0.0))
	for i in RETRACT_STEPS + 1:
		var xz := from_xz.lerp(to_xz, float(i) / RETRACT_STEPS)
		var hit: Dictionary = _ground_sampler.raycast_ground(
				space, Vector3(xz.x, hip_pos.y, xz.y), idle_settle_search_down)
		if not hit["hit"]:
			continue
		var normal: Vector3 = hit["normal"]
		var surface: Vector3 = hit["position"]
		var target := surface + normal * offset
		var horizontal_dist_sq := Vector2(
				hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
		var max_vertical_diff := sqrt(maxf(0.0, max_reach * max_reach - horizontal_dist_sq))
		var needed_sink: float = (hip_pos.y - target.y) - max_vertical_diff
		if needed_sink <= step_down_pelvis_drop:
			return {"found": true, "target": target, "surface": surface, "normal": normal}
	return {"found": false}

## Asymmetric shaping of the shared pelvis reach-limit sink. ENGAGE must be
## instant: a delayed sink leaves the leg stretched until the pelvis catches
## up (the documented shared_drop lerp regression), and re-planting higher
## makes an immediate drop safe. Only the RELEASE back toward the animated
## pose is capped by shared_drop_release_rate, so a per-footfall release
## cannot pop the pelvis 5-8cm in one frame (live stair-walk hip snaps
## -8.33/-6.70/-6.06/-7.79cm; a lower pelvis only bends knees, never
## stretches or penetrates). On a continuous slope the residual is ~0
## (predictor inactive) and pose-continuity forbids lag there. The residual
## is never cleared mid-climb: support can flicker inactive one frame exactly
## when the gap closes, and a gate there made the release instant (12cm
## jump). No frame guard - the phantom delta=0 pass would lock the frame; the
## release only advances on delta>0 and the engage branch is idempotent.
## `stationary` also rate-limits the ENGAGE (shared_drop_idle_engage_rate):
## the hip is not moving, so a gradual sink bends knees toward the planted
## target - the controlled idle-settle crouch instead of an instant 12-26cm
## drop. Walking engages stay instant.
func _shape_shared_drop(raw: float, delta: float, stationary: bool) -> float:
	if not _stair_predictor.is_active() and _smoothed_shared_drop <= 0.0001:
		return raw
	if stationary and delta > 0.0:
		if raw > _smoothed_shared_drop:
			_smoothed_shared_drop = minf(raw,
					_smoothed_shared_drop + delta * shared_drop_idle_engage_rate)
		else:
			_smoothed_shared_drop = maxf(raw,
					_smoothed_shared_drop - delta * shared_drop_release_rate)
		return _smoothed_shared_drop
	if raw >= _smoothed_shared_drop or shared_drop_release_rate <= 0.0:
		_smoothed_shared_drop = raw
	elif delta > 0.0:
		_smoothed_shared_drop = maxf(raw,
				_smoothed_shared_drop - delta * shared_drop_release_rate)
	return _smoothed_shared_drop
func _apply_support_pelvis_and_legs(skel: Skeleton3D, to_world: Transform3D,
		per_leg: Dictionary, shared_drop: float, delta: float) -> void:
	if step_prediction_enabled and _stair_predictor.is_active():
		shared_drop = _stair_predictor.ensure_support(per_leg, shared_drop, delta)
	var stationary: bool = player_body != null and player_body.anim_player != null and (
			player_body.anim_player.current_animation == "moves/unarmed_idle"
			or player_body.anim_player.current_animation == "moves/unarmed_crouch_idle")
	shared_drop = _shape_shared_drop(shared_drop, delta, stationary)
	# Pelvis and thigh roots move together so skinning across the seam cannot tear.
	if shared_drop > 0.0 and not _bone_indices.is_empty():
		var first_leg: Dictionary = _bone_indices.values()[0]
		var pelvis_idx := skel.get_bone_parent(first_leg["hip"])
		if pelvis_idx >= 0:
			# This call can run twice in one physics tick (real + phantom
			# delta=0 - see AGENTS.md); the second call would otherwise read
			# back the first call's own sink as fresh animation, chaining an
			# ever-growing sink within the tick. Cache the true baseline once.
			var current_frame := Engine.get_physics_frames()
			if _pelvis_base_pose_frame != current_frame:
				_pelvis_base_pose = skel.get_bone_global_pose(pelvis_idx)
				_pelvis_base_pose_frame = current_frame
			var fresh_pelvis := _pelvis_base_pose
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
		var preserve_idle_pose: bool = leg.get("preserve_idle_pose", false)
		if not leg["hit"] or (preserve_idle_pose and shared_drop <= 0.0001):
			_leg_solver.release_to_animation(skel, side, delta)
			continue
		# A shared pelvis sink moves the common ancestor of both legs. Releasing
		# a nominally preserved leg here lets that foot follow the pelvis through
		# its own higher tread while the opposite leg settles downward.
		var target: Vector3 = leg["ground_target"] if preserve_idle_pose else leg["target"]
		var gw: float = 1.0 if preserve_idle_pose else float(leg["ground_weight"])
		var cw: float = 1.0 if preserve_idle_pose else float(leg.get("chain_weight", gw))
		_leg_solver.solve(skel, side, leg["hip_pos"] - Vector3.UP * shared_drop, target,
				leg["upper"], leg["lower"], gw, cw, delta)
