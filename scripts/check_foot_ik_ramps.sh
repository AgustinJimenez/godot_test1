#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-ramp-check.XXXXXX")
trap 'rm -f "$log_file"' EXIT

if ! godot --headless --fixed-fps 60 --quit-after 60000 --path "$project_dir" \
		res://tests/manual/foot_ik/foot_ik_ramp_matrix_check.tscn >"$log_file" 2>&1; then
	cat "$log_file"
	exit 1
fi

if rg -q "FOOT_IK_RAMP_(CASE|MATRIX_CHECK) FAIL|SCRIPT ERROR" "$log_file"; then
	cat "$log_file"
	exit 1
fi

if ! rg -q "FOOT_IK_RAMP_MATRIX_CHECK PASS cases=245" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK ramp matrix did not complete."
	exit 1
fi

rg "FOOT_IK_RAMP_(CASE|MATRIX_CHECK) PASS" "$log_file"
