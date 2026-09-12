#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-check.XXXXXX")
trap 'rm -f "$log_file"' EXIT

# 018 finding I: this script never ran project lint/import/parse itself, so a clean run here
# did not guarantee a clean scripts/check.sh - only check_foot_ik_fast.sh caught that gap.
if ! "$project_dir/scripts/check.sh" >"$log_file" 2>&1; then
	cat "$log_file"
	exit 1
fi
printf '%s\n' "PROJECT_CHECK PASS"

godot --headless --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_clearance_geometry_check.tscn \
	--quit-after 5 >"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_CLEARANCE_GEOMETRY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_CLEARANCE_GEOMETRY_CHECK PASS" "$log_file"

check() {
	label=$1
	pattern=$2
	quit_after=$3
	scene=$4
	shift 4
	if [ "$#" -gt 0 ]; then
		godot --headless --fixed-fps 60 --path "$project_dir" "$scene" \
			--quit-after "$quit_after" -- "$@" >"$log_file" 2>&1 || true
	else
		godot --headless --fixed-fps 60 --path "$project_dir" "$scene" \
			--quit-after "$quit_after" >"$log_file" 2>&1 || true
	fi
	if rg -q "SCRIPT ERROR" "$log_file" || ! rg -q "$pattern" "$log_file"; then
		cat "$log_file"
		printf '%s\n' "$label did not pass."
		exit 1
	fi
	rg "$pattern" "$log_file"
}
# 018 finding I: shared with check_foot_ik_all.sh so a newly-added check cannot silently go
# missing from one of the two scripts, as constraint-expiry/mode-switch once did here.
. "$project_dir/scripts/foot_ik_checks.inc.sh"

godot --headless --fixed-fps 60 --quit-after 360 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_preview.tscn \
	-- --foot-ik-check >"$log_file" 2>&1 || true

if rg -q "FOOT_IK_(STRETCH|AIRBORNE|STAIR_(LOCOMOTION|SETTLE))_CHECK FAIL|SCRIPT ERROR" "$log_file"; then
	cat "$log_file"
	exit 1
fi

if ! rg -q "FOOT_IK_STRETCH_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stretch check did not produce a result."
	exit 1
fi

if ! rg -q "FOOT_IK_AIRBORNE_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK airborne release check did not run."
	exit 1
fi

if ! rg -q "FOOT_IK_BODY_PENETRATION_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK rendered-body stair penetration check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK idle pose-continuity check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_STAIR_LOCOMOTION_CHECK PASS steps=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stair locomotion continuity check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_STAIR_SETTLE_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK post-stair settling check did not pass."
	exit 1
fi

rg "FOOT_IK_(STRETCH|AIRBORNE)_CHECK PASS|FOOT_IK_BODY_PENETRATION_CHECK PASS" \
	"$log_file"
rg "FOOT_IK_POSE_CONTINUITY_CHECK PASS" "$log_file"
rg "FOOT_IK_STAIR_LOCOMOTION_CHECK PASS" "$log_file"
rg "FOOT_IK_STAIR_SETTLE_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn \
	--quit-after 2750 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stationary planted-foot stability check did not pass."
	exit 1
fi
rg "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" "$log_file"

"$project_dir/scripts/check_foot_ik_ramp_locomotion.sh"
"$project_dir/scripts/check_foot_ik_stair_repeat.sh"
"$project_dir/scripts/check_foot_ik_locomotion.sh"
