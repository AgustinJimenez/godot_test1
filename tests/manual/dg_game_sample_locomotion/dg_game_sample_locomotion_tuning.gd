class_name DGGameSampleLocomotionTuning
extends Resource
## Tuning surface for the DG_GAME_SAMPLE locomotion port.
##
## Speeds: walk 3.0 / jog 3.75 / sprint 7.5 m/s come from the constructor at
## 0x140833d70 (fields +0x4d4 = 300, +0x4d0 = 375, +0x4cc = 750 cm/s).
## Attribution to UBendCharacterMovementComponent is a strong candidate, not
## proven by RTTI. Every other value here is still a plausible default: the
## transition predicates compare unnamed class fields (e.g. [this+0x858] vs
## [this+0x834]) and the shipped BendGame/*.ini files carry no MaxWalkSpeed-style
## values, so those knob names live in CDO data that needs the unshipped PDB.
## Tune by feel and never claim the unverified values are the game's.

@export_group("Ground speeds (m/s)")
@export var walk_speed := 3.0
@export var jog_speed := 3.75
@export var run_speed := 5.6
@export var sprint_speed := 7.5
@export var crouch_speed := 1.35
## Heading-relative multipliers; DG_GAME_SAMPLE slows strafing and reverse movement.
@export var strafe_speed_scale := 0.82
@export var backward_speed_scale := 0.68

@export_group("Acceleration")
## Seconds to reach the target speed from rest (and to brake back to rest).
@export var accelerate_time := 0.34
@export var decelerate_time := 0.24
@export var air_control_scale := 0.25

@export_group("Facing")
## Degrees per second the capsule may rotate while moving.
@export var turn_rate_deg_per_s := 480.0
## Multiplies turn rate by strafe angle: 0 deg = straight ahead, 180 = reverse.
@export var turn_rate_scale_curve: Curve
@export var jump_velocity := 4.2
@export var gravity_scale := 1.0

@export_group("Turn in place")
## Enter the turn state from idle when the requested heading is this far off.
@export var turn_in_place_enter_deg := 55.0
## Leave the turn state early once the remaining error is this small.
@export var turn_in_place_early_out_deg := 6.0
## Capsule rotation speed while turning in place.
@export var turn_in_place_rate_deg_per_s := 300.0
@export var turn_in_place_windup_s := 0.09
@export var turn_in_place_settle_s := 0.10
## A tap released inside this window chains the next turn (ConsumeTurnInPlaceTap).
@export var turn_in_place_tap_window_s := 0.24
## Minimum time before a turn may be cancelled by input release.
@export var turn_in_place_min_hold_s := 0.16

@export_group("State thresholds")
## Raw input magnitude below this counts as "no movement request".
@export var input_deadzone := 0.18
## Planar speed under this counts as standing still for Move -> Idle.
@export var idle_speed_threshold := 0.30
## Reversing while slower than this can enter the turn state instead of moving.
@export var move_to_turn_max_speed := 1.2
@export var move_to_turn_min_angle_deg := 100.0

@export_group("Posture")
@export var stand_height := 1.80
@export var crouch_height := 1.10
@export var capsule_radius := 0.34
@export var crouch_transition_time := 0.12


## Turn-rate multiplier for a heading offset, sampled from the exported curve.
func turn_rate_scale_for_angle(angle_deg: float) -> float:
	if turn_rate_scale_curve == null:
		# Fallback: full rate straight ahead, tapering as the heading diverges.
		return clampf(1.0 - absf(angle_deg) / 180.0 * 0.55, 0.45, 1.0)
	var sample := clampf(absf(angle_deg) / 180.0, 0.0, 1.0)
	return turn_rate_scale_curve.sample(sample)
