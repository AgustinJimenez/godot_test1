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

# run_scene_all LABEL QUIT_AFTER SCENE GODOT_ARGS EXPECTED... - like run_scene, but requires
# every EXPECTED pattern to be present (not just one), for a scene that reports several
# independent sub-results in one shared run. GODOT_ARGS is a single word-split string (may be
# empty) passed through to the scene after "--".
run_scene_all() {
	label=$1
	quit_after=$2
	scene=$3
	godot_args=$4
	shift 4
	if ! godot --headless --fixed-fps 60 --path "$project_dir" "$scene" \
			--quit-after "$quit_after" $godot_args >"$log_file" 2>&1; then
		cat "$log_file"
		printf '%s\n' "$label failed."
		exit 1
	fi
	if rg -q "SCRIPT ERROR" "$log_file"; then
		cat "$log_file"
		printf '%s\n' "$label did not pass (SCRIPT ERROR)."
		exit 1
	fi
	for expected in "$@"; do
		if ! rg -q "$expected" "$log_file"; then
			cat "$log_file"
			printf '%s\n' "$label did not pass: missing '$expected'."
			exit 1
		fi
	done
	rg "FOOT_IK_.*_CHECK PASS" "$log_file"
}

if ! "$project_dir/scripts/check.sh" >"$log_file" 2>&1; then
	cat "$log_file"
	exit 1
fi
printf '%s\n' "PROJECT_CHECK PASS"

run_scene "Foot IK clearance geometry" "FOOT_IK_CLEARANCE_GEOMETRY_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_clearance_geometry_check.tscn

run_scene "Foot IK release pose" "FOOT_IK_RELEASE_POSE_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_release_pose_check.tscn

run_scene "Foot IK candidate evaluation" "FOOT_IK_CANDIDATE_EVALUATION_CHECK PASS samples=720" \
	150 res://tests/manual/foot_ik/foot_ik_candidate_evaluation_check.tscn

run_scene "Foot IK slope target lifecycle" "FOOT_IK_SLOPE_TARGET_LIFECYCLE_CHECK PASS" \
	10 res://tests/manual/foot_ik/foot_ik_slope_target_lifecycle_check.tscn

run_scene "Foot IK authored collider shape" "FOOT_IK_AUTHORED_COLLIDER_SHAPE_CHECK PASS" \
	5 res://tests/manual/foot_ik/foot_ik_authored_collider_shape_check.tscn

run_scene_all "Foot IK core preview" 360 res://tests/manual/foot_ik/foot_ik_preview.tscn \
	"-- --foot-ik-check" \
	"FOOT_IK_STRETCH_CHECK PASS" "FOOT_IK_AIRBORNE_CHECK PASS samples=[1-9]" \
	"FOOT_IK_BODY_PENETRATION_CHECK PASS samples=[1-9]" \
	"FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=[1-9]" \
	"FOOT_IK_STAIR_LOCOMOTION_CHECK PASS steps=[1-9]" \
	"FOOT_IK_STAIR_SETTLE_CHECK PASS samples=[1-9]"
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
	2750 res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn

run_scene "Foot IK idle support ownership" "FOOT_IK_IDLE_SUPPORT_OWNER_CHECK PASS" \
	500 res://tests/manual/foot_ik/foot_ik_idle_support_owner_check.tscn
run_scene "Foot IK toe riser clearance" "FOOT_IK_TOE_RISER_CHECK PASS" \
	560 res://tests/manual/foot_ik/foot_ik_toe_riser_check.tscn
elapsed=$(($(date +%s) - start_time))
printf 'FOOT_IK_FAST_CHECK PASS elapsed_seconds=%d\n' "$elapsed"
