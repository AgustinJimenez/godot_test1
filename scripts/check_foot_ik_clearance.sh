#!/bin/sh
# Measurement prototype acceptance; passing does not mean the ramp pose is fixed.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-clearance.XXXXXX")
trap 'rm -f "$log_file"' EXIT

godot --headless --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_clearance_geometry_check.tscn \
	--quit-after 5 >"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_CLEARANCE_GEOMETRY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_CLEARANCE_GEOMETRY_CHECK" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_clearance_replay_check.tscn \
	--quit-after 13000 -- "$@" >"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_CLEARANCE_REPLAY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_CLEARANCE_REPLAY_CHECK" "$log_file"
