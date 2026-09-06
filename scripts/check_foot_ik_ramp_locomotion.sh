#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-ramp-locomotion.XXXXXX")
trap 'rm -f "$log_file"' EXIT

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_ramp_locomotion_check.tscn \
	--quit-after 13000 >"$log_file" 2>&1 || true

if ! rg -q "FOOT_IK_RAMP_LOCOMOTION_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_RAMP_LOCOMOTION_(CASES|CHECK)" "$log_file"
