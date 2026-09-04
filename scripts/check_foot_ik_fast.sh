#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-fast.XXXXXX")
start_time=$(date +%s)
trap 'rm -f "$log_file"' EXIT

run_scene() {
	label=$1
	expected=$2
	quit_after=$3
	scene=$4
	shift 4
	if ! godot --headless --fixed-fps 60 --path "$project_dir" "$scene" \
			--quit-after "$quit_after" "$@" >"$log_file" 2>&1; then
		cat "$log_file"
		printf '%s\n' "$label failed."
		exit 1
	fi
	if rg -q "SCRIPT ERROR" "$log_file" || ! rg -q "$expected" "$log_file"; then
		cat "$log_file"
		printf '%s\n' "$label did not pass."
		exit 1
	fi
	rg "$expected" "$log_file"
}

if ! "$project_dir/scripts/check.sh" >"$log_file" 2>&1; then
	cat "$log_file"
	exit 1
fi
printf '%s\n' "PROJECT_CHECK PASS"

run_scene "Foot IK core preview" \
	"FOOT_IK_(STRETCH|AIRBORNE|BODY_PENETRATION|POSE_CONTINUITY|STAIR_LOCOMOTION|STAIR_SETTLE)_CHECK PASS" \
	360 res://tests/manual/foot_ik/foot_ik_preview.tscn -- --foot-ik-check
run_scene "Foot IK stale grounded landing commitment" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn -- replay_stale_grounded_commit=true
run_scene "Foot IK shallow split-height pose" "FOOT_IK_KNEE_FLEX_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn -- replay_shallow_split_pose=true
run_scene "Foot IK randomized edge landing" "FOOT_IK_EDGE_LANDING_SWEEP_CHECK PASS" \
	10000 res://tests/manual/foot_ik/foot_ik_edge_landing_sweep_check.tscn
run_scene "Foot IK ledge safety" "FOOT_IK_LEDGE_SAFETY_CHECK PASS" \
	3300 res://tests/manual/foot_ik/foot_ik_ledge_safety_check.tscn
run_scene "Foot IK landing stability" "FOOT_IK_LANDING_STABILITY_CHECK PASS" \
	240 res://tests/manual/foot_ik/foot_ik_landing_stability_check.tscn
run_scene "Foot IK split stance" "FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS" \
	320 res://tests/manual/foot_ik/foot_ik_split_stance_walk_check.tscn
run_scene "Foot IK idle loop seam" "FOOT_IK_IDLE_SEAM_CHECK PASS" \
	400 res://tests/manual/foot_ik/foot_ik_preview.tscn -- --idle-ik-seam-check
run_scene "Foot IK planted idle" "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" \
	2350 res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn

elapsed=$(($(date +%s) - start_time))
printf 'FOOT_IK_FAST_CHECK PASS elapsed_seconds=%d\n' "$elapsed"
