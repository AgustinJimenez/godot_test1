#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-stair-repeat.XXXXXX")
trap 'rm -f "$log_file"' EXIT

godot --headless --fixed-fps 60 --quit-after 1200 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_stair_repeat.tscn >"$log_file" 2>&1

if ! rg -q "FOOT_IK_STAIR_REPEAT_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_STAIR_REPEAT_CHECK PASS" "$log_file"
