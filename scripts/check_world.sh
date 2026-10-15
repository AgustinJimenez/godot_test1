#!/bin/sh
# Procedural world, headless: builds the world around the origin and checks the player stands on
# the generated ground (WORLD_CHECK), then that the level scene itself loads and runs.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/world.XXXXXX")
trap 'rm -f "$log"' EXIT
status=0

godot --headless --fixed-fps 60 --quit-after 600 --path "$project_dir" \
	res://tests/manual/world/world_lab.tscn -- --world-check >"$log" 2>&1 || true
line=$(grep "WORLD_CHECK" "$log" | head -1)
case "$line" in
*" PASS "*) printf 'PASS World generator: %s\n' "$line" ;;
*) printf 'FAIL World generator: %s\n' "${line:-no result line}"; status=1 ;;
esac

run() {
	label=$1
	arg=$2
	pattern=$3
	godot --headless --fixed-fps 60 --quit-after 1500 --path "$project_dir" \
		res://tests/manual/world/world_lab.tscn -- "$arg" >"$log" 2>&1 || true
	line=$(grep "$pattern" "$log" | head -1)
	case "$line" in
	*" PASS "*) printf 'PASS %s: %s\n' "$label" "$line" ;;
	*) printf 'FAIL %s: %s\n' "$label" "${line:-no result line}"; status=1 ;;
	esac
}

run "World swimming" --swim SWIM_CHECK
run "World tower climb" --tower-check TOWER_CHECK
run "World rivers" --rivers RIVER_CHECK

godot --headless --fixed-fps 60 --quit-after 240 --path "$project_dir" \
	res://levels/procedural_world.tscn >"$log" 2>&1 || true
if grep -q "SCRIPT ERROR" "$log"; then
	printf 'FAIL World level: %s\n' "$(grep 'SCRIPT ERROR' "$log" | head -1)"
	status=1
else
	printf 'PASS World level loads and runs\n'
fi
exit "$status"
