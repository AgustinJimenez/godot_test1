class_name FootIKRuntimeSettings
extends RefCounted
## Runtime policy switches and tuning shared by Foot IK collaborators.

var airborne_safe_zone_enabled := true
var grounded_split_recovery_enabled := true
var upper_foot_reposition_enabled := true
var idle_lower_support_enabled := true
var lower_riser_rehome_enabled := true
var idle_stance_rehome_enabled := true
var idle_freeze_enabled := true
var locomotion_target_lock_enabled := true

var landing_correction_speed := 3.0
var max_airborne_correction := 0.40
var landing_footprint_depth := 0.10
var landing_root_clearance_radius := 0.36
var max_split_ik_height := 0.35

var upper_foot_acquire_speed := 2.0
var preferred_upper_knee_flexion_degrees := 70.0
var retained_upper_knee_flexion_degrees := 80.0
var upper_support_radius := 0.10
# Matches upper_foot_acquire_speed/idle_stance_rehome_speed (see 013's "340:right:foot" finding -
# at the old 4.0, this setting's own per-frame cap (4.0 * delta) exceeded
# foot_ik_idle_plant_stability_check's MAX_LIVE_POSE_JOINT_STEP purely from legitimate motion,
# with no bug anywhere in the solve chain). Every acquire/rehome speed in this file now shares
# the same rate, so none of them can individually produce a step this check would flag.
var lower_foot_acquire_speed := 2.0
var lower_riser_clearance_radius := 0.32
var idle_stance_rehome_speed := 2.0

var max_upright_shin_swing_degrees := 45.0
var upright_shin_steer_start_degrees := 30.0
var minimum_knee_pole_alignment := 0.5
var joint_correction_speed_degrees := 120.0
var standing_joint_speed_degrees := 90.0
var crouch_joint_speed_degrees := 45.0


func allows_support_height_difference(difference: float) -> bool:
	# Collision hits on a nominal boundary vary slightly between frames.
	# All support owners must agree before deciding to transfer a planted foot.
	return is_finite(difference) and absf(difference) <= max_split_ik_height + 0.001


## A near-vertical face is not ground. The primary contact sample used to accept
## whatever normal it hit, so a ramp slab's own ~75-degree end cap was conformed to
## like a floor and buried the foot ~7cm inside it (012's deep 15-degree uphill_cross
## clips). Mirroring the character's own floor_max_angle keeps IK and movement agreed
## on what is standable; the tolerance absorbs a normal sitting exactly on the limit,
## so a 45-degree ramp stays walkable under a 45-degree limit. Riser/stair probes must
## still see vertical faces, so this is opt-in per query, not applied to every raycast.
func is_walkable_normal(normal: Vector3, character: CharacterBody3D) -> bool:
	var limit: float = character.floor_max_angle if character != null else deg_to_rad(50.0)
	return normal.dot(Vector3.UP) >= cos(limit) - 0.01
