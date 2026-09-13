# Shared list of "simple" Foot IK checks - single scene, single expected pattern, fixed
# quit-after and args - run identically by check_foot_ik.sh (fail-fast, the full sequence)
# and check_foot_ik_all.sh (continue-past-failures, known/new tracking). Before sourcing this
# file, the caller must define: check LABEL PATTERN QUIT_AFTER SCENE [ARGS...]
# 018 finding I: this list used to be hand-copied into both scripts, which is exactly how a
# newly-added check (constraint expiry, mode switch) silently went missing from one of them.
#
# NOT here, still hand-maintained per caller: the multi-pattern foot_ik_preview.tscn
# "--foot-ik-check" block (check_foot_ik_all.sh records its 6 patterns as 6 separate known/new
# results, not one combined pass/fail, so unifying it would silently change that script's
# passed-count semantics) and every quantitative-grading/sibling-script check (ramps, ramp
# sweep, ramp locomotion, stair repeat, locomotion, project/clearance subscripts) - only
# check_foot_ik_all.sh grades those quantitatively.

check "Foot IK release pose check" "FOOT_IK_RELEASE_POSE_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_release_pose_check.tscn
check "Foot IK candidate evaluation check" \
	"FOOT_IK_CANDIDATE_EVALUATION_CHECK PASS samples=720" \
	150 res://tests/manual/foot_ik/foot_ik_candidate_evaluation_check.tscn
check "Foot IK spacing plan check" "FOOT_IK_SPACING_PLAN_CHECK PASS cases=39" \
	5 res://tests/manual/foot_ik/foot_ik_spacing_plan_check.tscn
check "Foot IK final target contract check" "FOOT_IK_FINAL_TARGET_CONTRACT_CHECK PASS cases=20" \
	80 res://tests/manual/foot_ik/foot_ik_final_target_contract_check.tscn
check "Foot IK slope target lifecycle check" \
	"FOOT_IK_SLOPE_TARGET_LIFECYCLE_CHECK PASS" \
	10 res://tests/manual/foot_ik/foot_ik_slope_target_lifecycle_check.tscn
check "Foot IK authored collider shape check" \
	"FOOT_IK_AUTHORED_COLLIDER_SHAPE_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_authored_collider_shape_check.tscn
check "Foot IK toe riser check" "FOOT_IK_TOE_RISER_CHECK PASS" \
	560 res://tests/manual/foot_ik/foot_ik_toe_riser_check.tscn
check "Foot IK mode switch reset check" "FOOT_IK_MODE_SWITCH_CHECK PASS" \
	10 res://tests/manual/foot_ik/foot_ik_mode_switch_check.tscn
check "Foot IK constraint expiry check" "FOOT_IK_CONSTRAINT_EXPIRY_CHECK PASS" \
	15 res://tests/manual/foot_ik/foot_ik_constraint_expiry_check.tscn
check "Foot IK idle support owner check" "FOOT_IK_IDLE_SUPPORT_OWNER_CHECK PASS" \
	500 res://tests/manual/foot_ik/foot_ik_idle_support_owner_check.tscn
check "Foot IK split idle feedback check" "FOOT_IK_SPLIT_IDLE_FEEDBACK_CHECK PASS" \
	620 res://tests/manual/foot_ik/foot_ik_split_idle_feedback_check.tscn
check "Foot IK animation comparison check" "FOOT_IK_ANIMATION_COMPARISON_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_preview.tscn --animation-comparison-check

check "Foot IK randomized edge-landing sweep" "FOOT_IK_EDGE_LANDING_SWEEP_CHECK PASS" \
	10000 res://tests/manual/foot_ik/foot_ik_edge_landing_sweep_check.tscn
check "Foot IK ledge safety check" "FOOT_IK_LEDGE_SAFETY_CHECK PASS" \
	3300 res://tests/manual/foot_ik/foot_ik_ledge_safety_check.tscn
check "Foot IK landing stability check" "FOOT_IK_LANDING_STABILITY_CHECK PASS" \
	240 res://tests/manual/foot_ik/foot_ik_landing_stability_check.tscn
check "Foot IK split-stance walk support check" "FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS" \
	320 res://tests/manual/foot_ik/foot_ik_split_stance_walk_check.tscn
check "Foot IK split-height knee flexion check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn
check "Foot IK idle loop left-leg seam check" "FOOT_IK_IDLE_SEAM_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_preview.tscn --idle-ik-seam-check
check "Foot IK over-height weight-oscillation check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_weight_oscillation=true
check "Foot IK mismatched grounded landing commitment check" \
	"FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_grounded_commit_mismatch=true
check "Foot IK stale grounded landing commitment check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_stale_grounded_commit=true
check "Foot IK shallow split-height pose check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_shallow_split_pose=true
check "Foot IK committed edge-landing check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_committed_edge_landing=true
check "Foot IK delayed landing support restore check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_delayed_support_restore=true
check "Foot IK delayed lower-support snap check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_delayed_lower_snap=true
check "Foot IK idle-loop knee continuity check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn replay_idle_loop=true
check "Foot IK negative rendered-knee check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn replay_negative_knee=true
check "Foot IK unreachable acquisition check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_unreachable_acquisition=true
check "Foot IK turning corner knee flexion check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.649,0.575,4.231 turn_from=89.2 yaw=-47.1210208763382
check "Foot IK landing contact-clearance check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.602571,0.600571,3.860138 yaw=91.1223801700297 \
	replay_landing_clearance_jump=true require_prelanding_move=true
check "Foot IK late-input predictive landing check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.053116,0.6001,3.915929 yaw=-88.3279926862266 \
	replay_late_landing_input=true require_prelanding_move=true
check "Foot IK partial upper-foot support check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.636244,0.600522,3.98567 yaw=-101.164602401024 require_lowest_support=true
check "Foot IK edge-push target reversal check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.219313,0.6001,3.865484 yaw=92.7266550022823 replay_edge_push=true
check "Foot IK forward-shin standing limit check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.549901,0.6001,3.960056 yaw=-54.9599094584513
check "Foot IK predictive landing safe-zone check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.053116,0.6001,3.915929 yaw=-88.3279926862266 \
	replay_prelanding_jump=true require_prelanding_move=true
check "Foot IK mirrored upper-leg deformation check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.758182,0.600149,4.085211 yaw=73.7044620505809 time=1.86666666666666
check "Foot IK shallow-corner knee flexion check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.769,0.551,4.278 turn_from=89.6 yaw=-24.6610895549845
check "Foot IK edge stance check" "FOOT_IK_EDGE_STANCE_CHECK PASS" \
	6200 res://tests/manual/foot_ik/foot_ik_edge_stance_check.tscn
check "Foot IK walk-to-idle stance check" "FOOT_IK_WALK_IDLE_STANCE_CHECK PASS" \
	5500 res://tests/manual/foot_ik/foot_ik_walk_idle_stance_check.tscn
