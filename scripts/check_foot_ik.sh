#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-check.XXXXXX")
trap 'rm -f "$log_file"' EXIT

godot --headless --fixed-fps 60 --quit-after 360 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_preview.tscn \
	-- --foot-ik-check >"$log_file" 2>&1

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

"$project_dir/scripts/check_foot_ik_stair_repeat.sh"
"$project_dir/scripts/check_foot_ik_locomotion.sh"
