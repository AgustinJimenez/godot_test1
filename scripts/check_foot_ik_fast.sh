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

# Only this curated high-signal subset of the shared list actually runs here - everything
# else is a silent no-op (018 finding I: keeps this subset in sync with the canonical labels
# in foot_ik_checks.inc.sh instead of hand-copying scene/pattern/quit-after values here too).
FAST_LABELS='
Foot IK release pose check
Foot IK candidate evaluation check
Foot IK spacing plan check
Foot IK final target contract check
Foot IK slope target lifecycle check
Foot IK authored collider shape check
Foot IK stale grounded landing commitment check
Foot IK shallow split-height pose check
Foot IK randomized edge-landing sweep
Foot IK ledge safety check
Foot IK landing stability check
Foot IK split-stance walk support check
Foot IK idle loop left-leg seam check
Foot IK idle support owner check
Foot IK split idle feedback check
Foot IK spawn contact check
Foot IK toe riser check
Foot IK mode switch reset check
Foot IK constraint expiry check
'
check() {
	label=$1
	if ! printf '%s\n' "$FAST_LABELS" | grep -qxF "$label"; then
		return 0
	fi
	pattern=$2
	quit_after=$3
	scene=$4
	shift 4
	if [ "$#" -gt 0 ]; then
		run_scene "$label" "$pattern" "$quit_after" "$scene" -- "$@"
	else
		run_scene "$label" "$pattern" "$quit_after" "$scene"
	fi
}
. "$project_dir/scripts/foot_ik_checks.inc.sh"

run_scene_all "Foot IK core preview" 360 res://tests/manual/foot_ik/foot_ik_preview.tscn \
	"-- --foot-ik-check" \
	"FOOT_IK_STRETCH_CHECK PASS" "FOOT_IK_AIRBORNE_CHECK PASS samples=[1-9]" \
	"FOOT_IK_BODY_PENETRATION_CHECK PASS samples=[1-9]" \
	"FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=[1-9]" \
	"FOOT_IK_STAIR_LOCOMOTION_CHECK PASS steps=[1-9]" \
	"FOOT_IK_STAIR_SETTLE_CHECK PASS samples=[1-9]"
run_scene "Foot IK planted idle" "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" \
	2750 res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn

elapsed=$(($(date +%s) - start_time))
printf 'FOOT_IK_FAST_CHECK PASS elapsed_seconds=%d\n' "$elapsed"
