#!/bin/sh
# Runs every Foot IK check entrypoint - check_foot_ik.sh's full sequence plus every sibling
# script it does NOT itself invoke - continuing past failures instead of stopping at the
# first one (unlike check_foot_ik.sh, which is set -eu with a hard exit per check). Reports
# every result and separates already-known baseline failures from new/unexpected ones, so a
# fix can be verified against the complete picture in one run instead of an ad-hoc /tmp
# continue-past-failures copy. See AGENT_TASKS/015_foot_ik_architecture_direction.md, point 6.
#
# Exit code is 0 only if every failure (if any) is already listed in KNOWN_BASELINE_FAILURES
# below. A newly-introduced failure - one not in that list - makes this exit 1.
#
# To accept a currently-new failure as an intentional baseline change, add its exact label
# (as printed in the "NEW (unexpected)" section) to KNOWN_BASELINE_FAILURES, with a comment
# saying why - never edit it just to silence a real regression.
set -u

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-all.XXXXXX")
trap 'rm -f "$log_file"' EXIT

# Exact labels currently known to fail, kept in sync by hand after each verified session.
# A label not on this list that fails is treated as a new regression (see exit code above).
# Established 2026-09-07: see AGENT_TASKS/013 (knee-flex/idle-plant residuals) and
# AGENT_TASKS/012 (ramp-edge residuals, now graded quantitatively via run_ramp_subscript below
# instead of by this label list - see AGENT_TASKS/018's finding I).
KNOWN_BASELINE_FAILURES='
Foot IK split-height knee flexion check
Foot IK idle-loop knee continuity check
Foot IK negative rendered-knee check
Foot IK unreachable acquisition check
Foot IK shallow-corner knee flexion check
Foot IK walk-to-idle stance check
check_foot_ik_ramp_locomotion.sh
check_foot_ik_locomotion.sh
'

# Quantitative baselines for the two ramp-matrix scripts (018's finding I) - established
# 2026-09-10 from a verified clean rerun of each script standalone.
RAMPS_MAX_FAILED_CASES=20
RAMPS_MAX_DEPTH_M=0.02
RAMP_SWEEP_MAX_FAILED_CASES=16
RAMP_SWEEP_MAX_DEPTH_M=0.11

_pass_count=0
_baseline_fail_count=0
_new_fail_labels=""

_is_known_baseline() {
	label=$1
	printf '%s\n' "$KNOWN_BASELINE_FAILURES" | grep -qxF "$label"
}

_record() {
	label=$1
	ok=$2
	if [ "$ok" = "1" ]; then
		_pass_count=$((_pass_count + 1))
		printf 'PASS      %s\n' "$label"
	elif _is_known_baseline "$label"; then
		_baseline_fail_count=$((_baseline_fail_count + 1))
		printf 'FAIL known %s\n' "$label"
	else
		_new_fail_labels="${_new_fail_labels}${label}
"
		printf 'FAIL NEW  %s\n' "$label"
	fi
}

# run_check LABEL PATTERN QUIT_AFTER SCENE [ARGS...]
run_check() {
	label=$1
	pattern=$2
	quit_after=$3
	scene=$4
	shift 4
	if [ "$#" -gt 0 ]; then
		godot --headless --fixed-fps 60 --path "$project_dir" "$scene" \
			--quit-after "$quit_after" -- "$@" >"$log_file" 2>&1
	else
		godot --headless --fixed-fps 60 --path "$project_dir" "$scene" \
			--quit-after "$quit_after" >"$log_file" 2>&1
	fi
	if grep -q "SCRIPT ERROR" "$log_file" || ! grep -Eq "$pattern" "$log_file"; then
		_record "$label" 0
		echo "  --- $log_file ---"
		cat "$log_file"
	else
		_record "$label" 1
	fi
}

# run_check_in_log LABEL PATTERN - greps the log from the most recent run_check/godot call
# without re-running godot, for scenes that produce several distinct check results at once.
run_check_in_log() {
	label=$1
	pattern=$2
	if grep -q "SCRIPT ERROR" "$log_file" || ! grep -Eq "$pattern" "$log_file"; then
		_record "$label" 0
	else
		_record "$label" 1
	fi
}

# run_subscript LABEL SCRIPT_RELATIVE_PATH - runs a sibling check_foot_ik_*.sh script
# (already self-contained with its own correctness checks) and records pass/fail purely by
# its exit code, since each already validates its own output before exiting non-zero.
run_subscript() {
	label=$1
	script=$2
	if "$project_dir/scripts/$script" >"$log_file" 2>&1; then
		_record "$label" 1
	else
		_record "$label" 0
		echo "  --- $log_file ($script) ---"
		cat "$log_file"
	fi
}

# run_ramp_subscript LABEL SCRIPT MAX_FAILED_CASES MAX_DEPTH_M - like run_subscript, but for the
# two ramp-matrix scripts already known to fail today: instead of trusting the whole-script
# label alone (018's finding I: a worse run inside an already-red script could hide behind the
# same "FAIL known" line forever), count the actual "FOOT_IK_RAMP_CASE FAIL" lines and their
# worst max_depth_m directly - the scene's own printed "failed_cases="/"worst_depth_m=" summary
# field was checked and found unreliable for check_foot_ik_ramps.sh specifically (it reported
# failed_cases=0 worst_depth_m=0.0 in a run that actually had 20 real per-case FAIL lines up to
# max_depth_m=0.0132), so this counts the ground truth instead of trusting that summary line.
# Only within-bound failures count as known; anything worse is a new/unexpected failure.
run_ramp_subscript() {
	label=$1
	script=$2
	max_failed_cases=$3
	max_depth_m=$4
	if "$project_dir/scripts/$script" >"$log_file" 2>&1; then
		_record "$label" 1
		return
	fi
	failed_cases=$(grep -c "FOOT_IK_RAMP_CASE FAIL" "$log_file")
	worst_depth_m=$(grep -o "max_depth_m=[0-9.]*" "$log_file" | cut -d= -f2 \
		| awk 'BEGIN{m=0} {if ($1+0>m) m=$1+0} END{print m}')
	detail="failed_cases=${failed_cases}/${max_failed_cases} worst_depth_m=${worst_depth_m}/${max_depth_m}"
	if [ "$failed_cases" -le "$max_failed_cases" ] \
			&& awk -v a="$worst_depth_m" -v b="$max_depth_m" 'BEGIN{exit !(a<=b)}'; then
		_baseline_fail_count=$((_baseline_fail_count + 1))
		printf 'FAIL known %s (%s)\n' "$label" "$detail"
	else
		_new_fail_labels="${_new_fail_labels}${label} (${detail})
"
		printf 'FAIL NEW  %s (%s)\n' "$label" "$detail"
		echo "  --- $log_file ($script) ---"
		cat "$log_file"
	fi
}

run_subscript "Foot IK clearance measurement check" "check_foot_ik_clearance.sh"

run_check "Foot IK release pose check" "FOOT_IK_RELEASE_POSE_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_release_pose_check.tscn
run_check "Foot IK slope target lifecycle check" \
	"FOOT_IK_SLOPE_TARGET_LIFECYCLE_CHECK PASS" \
	10 res://tests/manual/foot_ik/foot_ik_slope_target_lifecycle_check.tscn
run_check "Foot IK authored collider shape check" \
	"FOOT_IK_AUTHORED_COLLIDER_SHAPE_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_authored_collider_shape_check.tscn
run_check "Foot IK toe riser check" "FOOT_IK_TOE_RISER_CHECK PASS" \
	560 res://tests/manual/foot_ik/foot_ik_toe_riser_check.tscn
run_check "Foot IK idle support owner check" "FOOT_IK_IDLE_SUPPORT_OWNER_CHECK PASS" \
	500 res://tests/manual/foot_ik/foot_ik_idle_support_owner_check.tscn
run_check "Foot IK animation comparison check" "FOOT_IK_ANIMATION_COMPARISON_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_preview.tscn --animation-comparison-check

godot --headless --fixed-fps 60 --quit-after 360 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_preview.tscn -- --foot-ik-check >"$log_file" 2>&1
run_check_in_log "Foot IK stretch check" "FOOT_IK_STRETCH_CHECK PASS"
run_check_in_log "Foot IK airborne release check" "FOOT_IK_AIRBORNE_CHECK PASS samples=[1-9]"
run_check_in_log "Foot IK rendered-body stair penetration check" \
	"FOOT_IK_BODY_PENETRATION_CHECK PASS samples=[1-9]"
run_check_in_log "Foot IK idle pose-continuity check" \
	"FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=[1-9]"
run_check_in_log "Foot IK stair locomotion continuity check" \
	"FOOT_IK_STAIR_LOCOMOTION_CHECK PASS steps=[1-9]"
run_check_in_log "Foot IK post-stair settling check" \
	"FOOT_IK_STAIR_SETTLE_CHECK PASS samples=[1-9]"

run_check "Foot IK randomized edge-landing sweep" "FOOT_IK_EDGE_LANDING_SWEEP_CHECK PASS" \
	10000 res://tests/manual/foot_ik/foot_ik_edge_landing_sweep_check.tscn
run_check "Foot IK ledge safety check" "FOOT_IK_LEDGE_SAFETY_CHECK PASS" \
	3300 res://tests/manual/foot_ik/foot_ik_ledge_safety_check.tscn
run_check "Foot IK landing stability check" "FOOT_IK_LANDING_STABILITY_CHECK PASS" \
	240 res://tests/manual/foot_ik/foot_ik_landing_stability_check.tscn
run_check "Foot IK split-stance walk support check" "FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS" \
	320 res://tests/manual/foot_ik/foot_ik_split_stance_walk_check.tscn
run_check "Foot IK split-height knee flexion check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn
run_check "Foot IK idle loop left-leg seam check" "FOOT_IK_IDLE_SEAM_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_preview.tscn --idle-ik-seam-check
run_check "Foot IK over-height weight-oscillation check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_weight_oscillation=true
run_check "Foot IK mismatched grounded landing commitment check" \
	"FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_grounded_commit_mismatch=true
run_check "Foot IK stale grounded landing commitment check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_stale_grounded_commit=true
run_check "Foot IK shallow split-height pose check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_shallow_split_pose=true
run_check "Foot IK committed edge-landing check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_committed_edge_landing=true
run_check "Foot IK delayed landing support restore check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_delayed_support_restore=true
run_check "Foot IK delayed lower-support snap check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_delayed_lower_snap=true
run_check "Foot IK idle-loop knee continuity check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn replay_idle_loop=true
run_check "Foot IK negative rendered-knee check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn replay_negative_knee=true
run_check "Foot IK unreachable acquisition check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	replay_unreachable_acquisition=true
run_check "Foot IK turning corner knee flexion check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.649,0.575,4.231 turn_from=89.2 yaw=-47.1210208763382
run_check "Foot IK landing contact-clearance check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.602571,0.600571,3.860138 yaw=91.1223801700297 \
	replay_landing_clearance_jump=true require_prelanding_move=true
run_check "Foot IK late-input predictive landing check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.053116,0.6001,3.915929 yaw=-88.3279926862266 \
	replay_late_landing_input=true require_prelanding_move=true
run_check "Foot IK partial upper-foot support check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.636244,0.600522,3.98567 yaw=-101.164602401024 require_lowest_support=true
run_check "Foot IK edge-push target reversal check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.219313,0.6001,3.865484 yaw=92.7266550022823 replay_edge_push=true
run_check "Foot IK forward-shin standing limit check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.549901,0.6001,3.960056 yaw=-54.9599094584513
run_check "Foot IK predictive landing safe-zone check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=9.053116,0.6001,3.915929 yaw=-88.3279926862266 \
	replay_prelanding_jump=true require_prelanding_move=true
run_check "Foot IK mirrored upper-leg deformation check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.758182,0.600149,4.085211 yaw=73.7044620505809 time=1.86666666666666
run_check "Foot IK shallow-corner knee flexion check" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	start=8.769,0.551,4.278 turn_from=89.6 yaw=-24.6610895549845
run_check "Foot IK edge stance check" "FOOT_IK_EDGE_STANCE_CHECK PASS" \
	6200 res://tests/manual/foot_ik/foot_ik_edge_stance_check.tscn
run_check "Foot IK walk-to-idle stance check" "FOOT_IK_WALK_IDLE_STANCE_CHECK PASS" \
	5500 res://tests/manual/foot_ik/foot_ik_walk_idle_stance_check.tscn
run_check "Foot IK stationary planted-foot stability check" \
	"FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" \
	2750 res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn

run_subscript "check_foot_ik_ramp_locomotion.sh" check_foot_ik_ramp_locomotion.sh
run_subscript "check_foot_ik_stair_repeat.sh" check_foot_ik_stair_repeat.sh
run_subscript "check_foot_ik_locomotion.sh" check_foot_ik_locomotion.sh
run_ramp_subscript "check_foot_ik_ramps.sh" check_foot_ik_ramps.sh \
	"$RAMPS_MAX_FAILED_CASES" "$RAMPS_MAX_DEPTH_M"
run_ramp_subscript "check_foot_ik_ramp_sweep.sh" check_foot_ik_ramp_sweep.sh \
	"$RAMP_SWEEP_MAX_FAILED_CASES" "$RAMP_SWEEP_MAX_DEPTH_M"

echo ""
echo "=== Foot IK full suite summary ==="
echo "Passed: $_pass_count"
echo "Known baseline failures: $_baseline_fail_count"
if [ -n "$_new_fail_labels" ]; then
	echo "NEW (unexpected) failures:"
	printf '%s' "$_new_fail_labels" | sed 's/^/  - /'
	exit 1
fi
echo "No new/unexpected failures."
exit 0
