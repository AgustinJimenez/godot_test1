#!/bin/sh
# v2 foot IK suite. One command, run as v2 grows:
#   1. project checks (lint/import/parse)
#   2. the pure two-bone solver regression (no scene)
#   3. the lab acceptance scene (walks every surface: flat, ramps 15/30/45, stairs 0.10/0.20/0.35)
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/foot-ik-v2.XXXXXX")
trap 'rm -f "$log"' EXIT
status=0

run() {
	label=$1
	pattern=$2
	shift 2
	if ! "$@" >"$log" 2>&1; then
		cat "$log"
		printf 'FAIL %s\n' "$label"
		status=1
		return 0
	fi
	if ! grep -q "$pattern" "$log"; then
		cat "$log"
		printf 'FAIL %s (missing "%s")\n' "$label" "$pattern"
		status=1
		return 0
	fi
	grep "$pattern" "$log"
}

run "Project checks" "Project checks passed" \
	"$project_dir/scripts/check.sh"

run "Foot IK v2 solver regression" "FOOT_IK_V2_SOLVER_CHECK PASS" \
	godot --headless --path "$project_dir" --script \
	res://tests/manual/foot_ik_v2/foot_ik_v2_solver_check.gd

run "Foot IK v2 lab (all surfaces)" "FOOT_IK_V2_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-check

# The user's report as a test: stand on the closest ramp and strafe left/right while a ray cast
# from above compares the sole/toe against the REAL ramp surface (independent of the modifier).
run "Foot IK v2 ramp strafe (user scenario)" "FOOT_IK_V2_RAMP_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1200 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-ramp-check

exit "$status"
