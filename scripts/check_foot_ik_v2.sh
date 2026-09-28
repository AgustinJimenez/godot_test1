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

# The last frame of a live session as a test: idle across the ramp slope after a run, a jump onto
# the ramp and two walk/stop cycles. Both toe tips must be on the floor (the downhill foot used to
# hang 4-8 cm up). Fails with --foot-ik-v2-no-pelvis-drop.
run "Foot IK v2 idle across ramp slope (live regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check

# Same history on the 30 degree ramp (the "next ramp" from the live log): the downhill foot's
# ankle sits >25 cm above the slope, which used to read as a swing foot and was never corrected.
run "Foot IK v2 idle across 30 deg ramp (live regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --ramp-index=1

# And the 45 degree ramp, which the replay's jump cannot reach, so the character starts on it. The
# downhill foot's floor is ~1.1 m from the hip there: only a deep (~0.36 m) pelvis drop reaches it.
run "Foot IK v2 idle across 45 deg ramp (live regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check \
	--ramp-index=2 --start-on-ramp

# Facing UP the 45 degree ramp (the live log's last frame): the rear foot's floor is out of reach even
# after a deep pelvis drop, so at rest the foot is also brought in toward the body. Toe tip AND heel
# are graded.
run "Foot IK v2 idle facing up the 45 deg ramp (live regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check \
	--ramp-index=2 --uphill

# Idle on the 0.10 m stairs with the shoe tip against the next riser (live log): the clearance pass
# used to lift the whole foot onto the higher tread (heel floating 10.6 cm); now it slides back.
run "Foot IK v2 idle on stairs, tip against a riser (live regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 900 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --stairs

# Standing on the stairs' edge with one foot on step 3 and the other off the side over the floor
# 0.38 m below (live log). That foot used to hang 30 cm up; it now squats to put it on the floor.
run "Foot IK v2 idle on the stairs' edge, one foot on the floor (live regression)" \
	"FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 900 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --stairs-edge

# A jump on the 45 degree ramp (live log): the standing-still squat used to fire in the air and on
# landing, pushing the pelvis 0.2-0.4 m down and back up. It must stay within 0.10 m for the jump.
run "Foot IK v2 jump on the 45 deg ramp keeps the pelvis up (live regression)" \
	"FOOT_IK_V2_IDLE_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 900 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --jump45

# Turn in place on the stairs, 2 degrees at a time through a full circle (v1's rotation-snap idea).
# A resting foot turned toward the next riser used to be lifted 10 cm onto it (heel 8 cm under the
# tread) and popped 0.28 m when a turn crossed a riser (now a step). Each offset along the treads
# puts the riser under the foot at a different spot.
for dz in 0 0.12 0.24 -0.12; do
	run "Foot IK v2 turn in place on the stairs, dz=$dz (regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
		godot --headless --fixed-fps 60 --quit-after 2800 --path "$project_dir" \
		res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check \
		--stairs-turn=$dz
done

exit "$status"
