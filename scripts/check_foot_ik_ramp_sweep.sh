#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
spacing_cm=${1:-20}
yaw_step=${2:-15}
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-ramp-sweep.XXXXXX")
trap 'rm -f "$log_file"' EXIT

set +e
godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_ramp_matrix_check.tscn -- \
	sweep=true spacing_cm="$spacing_cm" yaw_step="$yaw_step" >"$log_file" 2>&1
status=$?
set -e

rg "FOOT_IK_RAMP_CASE FAIL|FOOT_IK_RAMP_MATRIX_CHECK" "$log_file" || true
printf '%s\n' "Dense ramp sweep: spacing=${spacing_cm}cm yaw_step=${yaw_step}deg"
exit "$status"
