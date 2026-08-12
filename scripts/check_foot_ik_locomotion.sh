#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-locomotion-check.XXXXXX")
trap 'rm -f "$log_file"' EXIT

if ! godot --headless --fixed-fps 60 --quit-after 25000 --path "$project_dir" \
		res://tests/manual/foot_ik/foot_ik_locomotion_regression.tscn \
		>"$log_file" 2>&1; then
	cat "$log_file"
	exit 1
fi

if rg -q "FOOT_IK_LOCOMOTION_(CHECK|SUITE) FAIL|SCRIPT ERROR" "$log_file"; then
	cat "$log_file"
	exit 1
fi

for directional_clip in unarmed_crouch_left unarmed_crouch_right; do
	if ! rg -q "FOOT_IK_DIRECTIONAL_IN_PLACE_CHECK PASS clip=${directional_clip} " "$log_file"; then
		cat "$log_file"
		printf '%s\n' "Directional crouch clip retained root motion or a facing offset."
		exit 1
	fi
done

for locomotion_case in idle crouch_idle walk walk_back walk_left walk_right sprint sprint_left sprint_right crouch_walk crouch_back crouch_left crouch_strafe crouch_strafe_to_forward sprint_to_crouch_walk crouch_walk_to_sprint sprint_slow; do
	if ! rg -q "FOOT_IK_LOCOMOTION_CHECK PASS case=${locomotion_case} " "$log_file"; then
		cat "$log_file"
		printf '%s\n' "Foot IK ${locomotion_case} A/B continuity check did not pass."
		exit 1
	fi
	if ! rg -q "FOOT_IK_MATRIX_CHECK PASS case=${locomotion_case} " "$log_file"; then
		cat "$log_file"
		printf '%s\n' "Foot IK ${locomotion_case} full-pose/skin audit did not pass."
		exit 1
	fi
done

if ! rg -q "FOOT_IK_MOVING_LANDING_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK moving-jump landing reach check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_TURN_TARGET_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK rotating-idle target tracking check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_LOCOMOTION_SUITE PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK locomotion suite did not complete."
	exit 1
fi

rg "FOOT_IK_(DIRECTIONAL_IN_PLACE_CHECK|LOCOMOTION_CHECK|MATRIX_CHECK|MOVING_LANDING_CHECK|TURN_TARGET_CHECK|LOCOMOTION_SUITE) PASS" "$log_file"

# The settled-idle turn weight transition reproduced only at 30 FPS; 60 FPS
# alone can hide a frame-rate-dependent solver/pass-through state change.
godot --headless --fixed-fps 30 --quit-after 25000 --path "$project_dir" \
		res://tests/manual/foot_ik/foot_ik_locomotion_regression.tscn \
		>"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file"; then
	cat "$log_file"
	exit 1
fi
if ! rg -q "FOOT_IK_TURN_TARGET_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK 30 FPS rotating-idle continuity check did not pass."
	exit 1
fi
rg "FOOT_IK_TURN_TARGET_CHECK PASS" "$log_file"
