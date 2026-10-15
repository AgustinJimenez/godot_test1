#!/bin/sh
# Climbing labs, headless: the ledge (jump, hang, shimmy, mantle) and the wall of holds (up,
# sideways, diagonal, down, over the top) and a narrow beam (slow, arms out). One *_CHECK line each.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/climb.XXXXXX")
trap 'rm -f "$log"' EXIT
status=0

run() {
	label=$1
	scene=$2
	arg=$3
	pattern=$4
	godot --headless --fixed-fps 60 --quit-after 3600 --path "$project_dir" "$scene" -- "$arg" \
		>"$log" 2>&1 || true
	line=$(grep "$pattern" "$log" | head -1)
	case "$line" in
	*" PASS "*) printf 'PASS %s: %s\n' "$label" "$line" ;;
	*) printf 'FAIL %s: %s\n' "$label" "${line:-no result line}"; status=1 ;;
	esac
}

run "Climb ledge" res://tests/manual/climb/climb_lab.tscn --climb-check CLIMB_CHECK
run "Climb wall of holds" res://tests/manual/climb/climb_wall_lab.tscn --wall-check WALL_CHECK
run "Climb narrow platform" res://tests/manual/climb/climb_balance_lab.tscn --balance-check BALANCE_CHECK
exit "$status"
