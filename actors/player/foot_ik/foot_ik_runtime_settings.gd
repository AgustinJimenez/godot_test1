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
var lower_foot_acquire_speed := 4.0
var lower_riser_clearance_radius := 0.32
var idle_stance_rehome_speed := 2.0

var max_upright_shin_swing_degrees := 45.0
var upright_shin_steer_start_degrees := 30.0
var minimum_knee_pole_alignment := 0.5
var joint_correction_speed_degrees := 120.0
var standing_joint_speed_degrees := 90.0
var crouch_joint_speed_degrees := 45.0
