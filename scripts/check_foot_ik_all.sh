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
'
# check_foot_ik_ramp_locomotion.sh, check_foot_ik_locomotion.sh and "Foot IK stationary
# planted-foot stability check" used to sit in this plain label list too - a worse run inside
# any already-red check could hide behind the same "FAIL known" line forever (018 finding I;
# this bit a real ramp-spin regression on 2026-09-12 that this list alone did not catch). All
# three are now graded quantitatively below instead, same idea as the two ramp-matrix scripts
# already were.

# Quantitative baselines (018 finding I) - established 2026-09-10/12 from verified clean reruns.
RAMPS_MAX_FAILED_CASES=20
RAMPS_MAX_DEPTH_M=0.02
RAMP_SWEEP_MAX_FAILED_CASES=16
RAMP_SWEEP_MAX_DEPTH_M=0.11
RAMP_LOCOMOTION_MAX_FAILED_CASES=13
# check_foot_ik_locomotion.sh's known walk_left/walk_right failures, graded by their own worst
# single-frame added-rotation ("worst_frame_added_deg=") rather than the script's bare exit code.
LOCOMOTION_WALK_LEFT_MAX_FRAME_DEG=9.0
LOCOMOTION_WALK_RIGHT_MAX_FRAME_DEG=9.0
# "Foot IK stationary planted-foot stability check" ceilings: its turn-penetration gate
# correctly fails on a real, unfixed toe/leaf-through-riser clip during idle rotation on
# stairs - see AGENT_TASKS/019_foot_ik_toe_riser_clip_during_rotation.md.
IDLE_PLANT_MAX_DRIFT_LEFT_M=0.13
IDLE_PLANT_MAX_TURN_PENETRATION_M=0.11
IDLE_PLANT_MAX_LIVE_POSE_JOINT_STEP_M=0.11

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

# run_ramp_locomotion_check - like run_ramp_subscript, but for check_foot_ik_ramp_locomotion.sh's
# own aggregate "failures=N" count instead of per-case FAIL lines (018 finding I).
run_ramp_locomotion_check() {
	label="check_foot_ik_ramp_locomotion.sh"
	if "$project_dir/scripts/$label" >"$log_file" 2>&1; then
		_record "$label" 1
		return
	fi
	failed_cases=$(grep -o "failures=[0-9]*" "$log_file" | head -1 | cut -d= -f2)
	detail="failed_cases=${failed_cases:-?}/${RAMP_LOCOMOTION_MAX_FAILED_CASES}"
	if [ -n "$failed_cases" ] && [ "$failed_cases" -le "$RAMP_LOCOMOTION_MAX_FAILED_CASES" ]; then
		_baseline_fail_count=$((_baseline_fail_count + 1))
		printf 'FAIL known %s (%s)\n' "$label" "$detail"
	else
		_new_fail_labels="${_new_fail_labels}${label} (${detail})
"
		printf 'FAIL NEW  %s (%s)\n' "$label" "$detail"
		echo "  --- $log_file ($label) ---"
		cat "$log_file"
	fi
}

# run_idle_plant_stability_check - grades the scene's own known-bad metrics quantitatively
# instead of trusting its bare PASS/FAIL label (018 finding I; same idea as run_ramp_subscript).
run_idle_plant_stability_check() {
	label="Foot IK stationary planted-foot stability check"
	godot --headless --fixed-fps 60 --path "$project_dir" \
		res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn \
		--quit-after 2750 >"$log_file" 2>&1
	if grep -q "SCRIPT ERROR" "$log_file" \
			|| ! grep -Eq "FOOT_IK_IDLE_PLANT_STABILITY_CHECK (PASS|FAIL)" "$log_file"; then
		_record "$label" 0
		echo "  --- $log_file ---"
		cat "$log_file"
		return
	fi
	if grep -q "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" "$log_file"; then
		_record "$label" 1
		return
	fi
	drift_left=$(grep -o "drift_left_m=[0-9.]*" "$log_file" | cut -d= -f2)
	turn_pen=$(grep -o "turn_penetration_m=[0-9.]*" "$log_file" | cut -d= -f2)
	joint_step=$(grep -o "live_pose_joint_step_m=[0-9.]*" "$log_file" | cut -d= -f2)
	detail="drift_left_m=${drift_left}/${IDLE_PLANT_MAX_DRIFT_LEFT_M} "
	detail="${detail}turn_penetration_m=${turn_pen}/${IDLE_PLANT_MAX_TURN_PENETRATION_M} "
	detail="${detail}live_pose_joint_step_m=${joint_step}/${IDLE_PLANT_MAX_LIVE_POSE_JOINT_STEP_M}"
	if awk -v a="$drift_left" -v b="$IDLE_PLANT_MAX_DRIFT_LEFT_M" 'BEGIN{exit !(a<=b)}' \
			&& awk -v a="$turn_pen" -v b="$IDLE_PLANT_MAX_TURN_PENETRATION_M" \
				'BEGIN{exit !(a<=b)}' \
			&& awk -v a="$joint_step" -v b="$IDLE_PLANT_MAX_LIVE_POSE_JOINT_STEP_M" \
				'BEGIN{exit !(a<=b)}'; then
		_baseline_fail_count=$((_baseline_fail_count + 1))
		printf 'FAIL known %s (%s)\n' "$label" "$detail"
	else
		_new_fail_labels="${_new_fail_labels}${label} (${detail})
"
		printf 'FAIL NEW  %s (%s)\n' "$label" "$detail"
		echo "  --- $log_file ---"
		cat "$log_file"
	fi
}

# run_locomotion_check - grades check_foot_ik_locomotion.sh's known walk_left/walk_right
# failures by their own worst_frame_added_deg instead of the script's bare exit code (018
# finding I). Falls back to plain pass/fail if some other case fails instead.
run_locomotion_check() {
	label="check_foot_ik_locomotion.sh"
	if "$project_dir/scripts/$label" >"$log_file" 2>&1; then
		_record "$label" 1
		return
	fi
	left_deg=$(grep "FOOT_IK_LOCOMOTION_CHECK FAIL case=walk_left " "$log_file" \
		| grep -o "worst_frame_added_deg=[0-9.]*" | cut -d= -f2)
	right_deg=$(grep "FOOT_IK_LOCOMOTION_CHECK FAIL case=walk_right " "$log_file" \
		| grep -o "worst_frame_added_deg=[0-9.]*" | cut -d= -f2)
	other_case_failed=$(grep "FOOT_IK_LOCOMOTION_CHECK FAIL case=" "$log_file" \
		| grep -vE "case=(walk_left|walk_right) " | grep -c .)
	if [ -z "$left_deg" ] || [ -z "$right_deg" ] || [ "$other_case_failed" -gt 0 ] \
			|| grep -q "FOOT_IK_LOCOMOTION_SUITE FAIL" "$log_file"; then
		_record "$label" 0
		echo "  --- $log_file ($label) ---"
		cat "$log_file"
		return
	fi
	detail="walk_left_frame_deg=${left_deg}/${LOCOMOTION_WALK_LEFT_MAX_FRAME_DEG} "
	detail="${detail}walk_right_frame_deg=${right_deg}/${LOCOMOTION_WALK_RIGHT_MAX_FRAME_DEG}"
	if awk -v a="$left_deg" -v b="$LOCOMOTION_WALK_LEFT_MAX_FRAME_DEG" 'BEGIN{exit !(a<=b)}' \
			&& awk -v a="$right_deg" -v b="$LOCOMOTION_WALK_RIGHT_MAX_FRAME_DEG" \
				'BEGIN{exit !(a<=b)}'; then
		_baseline_fail_count=$((_baseline_fail_count + 1))
		printf 'FAIL known %s (%s)\n' "$label" "$detail"
	else
		_new_fail_labels="${_new_fail_labels}${label} (${detail})
"
		printf 'FAIL NEW  %s (%s)\n' "$label" "$detail"
		echo "  --- $log_file ($label) ---"
		cat "$log_file"
	fi
}

# 018 finding I: this script never ran project lint/import/parse itself, so a clean run here
# did not guarantee a clean scripts/check.sh - only check_foot_ik_fast.sh caught that gap.
run_subscript "Foot IK project checks" "check.sh"

run_subscript "Foot IK clearance measurement check" "check_foot_ik_clearance.sh"

check() { run_check "$@"; }
# 018 finding I: this shared list is sourced by check_foot_ik.sh too - see its own header.
. "$project_dir/scripts/foot_ik_checks.inc.sh"

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

run_idle_plant_stability_check

run_ramp_locomotion_check
run_subscript "check_foot_ik_stair_repeat.sh" check_foot_ik_stair_repeat.sh
run_locomotion_check
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
