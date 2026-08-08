#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-locomotion-check.XXXXXX")
trap 'rm -f "$log_file"' EXIT

if ! godot --headless --fixed-fps 60 --quit-after 900 --path "$project_dir" \
		res://tests/manual/foot_ik/foot_ik_locomotion_regression.tscn \
		>"$log_file" 2>&1; then
	cat "$log_file"
	exit 1
fi

if rg -q "FOOT_IK_LOCOMOTION_(CHECK|SUITE) FAIL|SCRIPT ERROR" "$log_file"; then
	cat "$log_file"
	exit 1
fi

for locomotion_case in walk sprint; do
	if ! rg -q "FOOT_IK_LOCOMOTION_CHECK PASS case=${locomotion_case} " "$log_file"; then
		cat "$log_file"
		printf '%s\n' "Foot IK ${locomotion_case} A/B continuity check did not pass."
		exit 1
	fi
done

if ! rg -q "FOOT_IK_LOCOMOTION_SUITE PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK locomotion suite did not complete."
	exit 1
fi

rg "FOOT_IK_LOCOMOTION_CHECK PASS|FOOT_IK_LOCOMOTION_SUITE PASS" "$log_file"
