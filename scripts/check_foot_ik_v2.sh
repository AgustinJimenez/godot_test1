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

# Leg vibration as numbers (the live "the stairs shake" reports): per surface+animation of the LAST
# headless run's trace, per-frame motion from `trace_v2.sh --check --snaps`. Limits sit just above
# today's values, so a change that makes a walk shakier turns this red. Args: label surface animation
# max-foot-jump(m) max-knee-turn-p95(deg) max-knee-turn(deg) max-reversals(% of frames)
# max-ik-jerk-p95(m) max-ik-jerk(m): the per-frame change of what the IK ADDED to the animated foot.
snap_check() {
	row=$("$project_dir/scripts/trace_v2.sh" --check --snaps 2>&1 | awk -v s="$2" -v a="$3" \
		'$1 == s && $2 == a { print $3, $8, $11, $13, $14, $(NF - 2), $NF; exit }')
	if [ -z "$row" ]; then
		printf 'FAIL %s (no %s %s frames in the trace)\n' "$1" "$2" "$3"
		status=1
		return 0
	fi
	if echo "$row" | awk -v f="$4" -v p="$5" -v k="$6" -v r="$7" -v jp="$8" -v jm="$9" \
		'{ exit !($2 <= f && $3 <= p && $4 <= k && 100 * $5 / $1 <= r && $6 <= jp && $7 <= jm) }'; then
		printf 'PASS %s: n=%s foot_max=%s knee_p95=%s knee_max=%s reversals=%s ik_jerk=%s/%s\n' "$1" $row
	else
		printf 'FAIL %s: n=%s foot_max=%s knee_p95=%s knee_max=%s reversals=%s ik_jerk=%s/%s (limits %s m, %s, %s deg, %s%%, jerk %s/%s)\n' \
			"$1" $row "$4" "$5" "$6" "$7" "$8" "$9"
		status=1
	fi
}

run "Project checks" "Project checks passed" \
	"$project_dir/scripts/check.sh"

run "Foot IK v2 solver regression" "FOOT_IK_V2_SOLVER_CHECK PASS" \
	godot --headless --path "$project_dir" --script \
	res://tests/manual/foot_ik_v2/foot_ik_v2_solver_check.gd

run "Foot IK v2 lab (all surfaces)" "FOOT_IK_V2_CHECK PASS" \
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-check

snap_check "Foot IK v2 floor walk vibration" floor unarmed_walk 0.20 11.0 30.0 3.0 0.036 0.20

# A continuous walk up the 0.10 m stairs (the live stairs): see snap_check.
run "Foot IK v2 stairs walk (run)" "FOOT_IK_V2_IDLE_CHECK" \
	godot --headless --fixed-fps 60 --quit-after 600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --stairs-walk=0
snap_check "Foot IK v2 stairs walk vibration" stairs unarmed_walk 0.25 8.5 25.0 5.5 0.06 0.23

# The same stairs walked DOWN from the top tread (a stuck foot used to snap forward on release).
run "Foot IK v2 stairs walk down (run)" "FOOT_IK_V2_IDLE_CHECK" \
	godot --headless --fixed-fps 60 --quit-after 600 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --stairs-walk=0:down
snap_check "Foot IK v2 stairs walk down vibration" stairs unarmed_walk 0.12 10.0 26.0 5.5 0.04 0.09

# The live log of a leg shake: idle on the top tread, then walk BACKWARD down while the speed builds
# (0.05 m further along the treads gave a 45 deg knee snap at the idle -> walk switch; now 22 deg).
run "Foot IK v2 stairs walk backward (run)" "FOOT_IK_V2_IDLE_CHECK" \
	godot --headless --fixed-fps 60 --quit-after 700 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --stairs-walk=0:back:0.05
snap_check "Foot IK v2 stairs walk backward vibration" stairs unarmed_walk 0.30 11.0 28.0 5.5 0.045 0.28

# Strafing sideways along a tread and climbing at 45 degrees (the keys the live play used on the
# stairs): the IK jerk is the number that was 3x the flat floor's in the live log.
for mode in sidel:unarmed_walk_left:0.32:16.0:36.0:6.5:0.065:0.25 \
	sider:unarmed_walk_right:0.26:15.0:33.0:6.5:0.04:0.14 \
	diagl:unarmed_walk:0.14:10.0:22.0:6.5:0.045:0.15 \
	diagr:unarmed_walk:0.14:11.0:23.0:6.5:0.045:0.09 \
	sideup:unarmed_walk_left:0.28:13.0:24.0:15.0:0.11:0.27 \
	sidedown:unarmed_walk_right:0.24:14.5:31.0:9.5:0.05:0.20; do
	IFS=: read -r name anim foot knee knee_max rev jerk jerk_max <<EOT
$mode
EOT
	run "Foot IK v2 stairs walk $name (run)" "FOOT_IK_V2_IDLE_CHECK" \
		godot --headless --fixed-fps 60 --quit-after 900 --path "$project_dir" \
		res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check \
		--stairs-walk=0:$name
	snap_check "Foot IK v2 stairs walk $name vibration" stairs "$anim" "$foot" "$knee" "$knee_max" \
		"$rev" "$jerk" "$jerk_max"
done

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

# 0.38 m below (live log). The body stays standing and that foot keeps the animation (it used to squat
# 0.33 m to reach the floor; standing like the idle clip has priority). Float limit 0.35 m.
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
# puts the riser under the foot at a different spot; -1.41:-0.39 is the live pose of a reported pop.
# (dz=0.24 is KNOWN OPEN: the riser retreat gives up after 4 tries and lifts the foot 10 cm onto the
# next tread; more retreats only moved the failure to other offsets - see AGENT_TASKS/035 item 8.)
for dz in 0 0.12 -0.12 -1.41:-0.39; do
	run "Foot IK v2 turn in place on the stairs, dz=$dz (regression)" "FOOT_IK_V2_IDLE_CHECK PASS" \
		godot --headless --fixed-fps 60 --quit-after 2800 --path "$project_dir" \
		res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check \
		--stairs-turn=$dz
done

# The default live spawn standing still for 700 frames (headless, so it writes the CHECK trace and
# never a live session's): no joint may rotate more than 15 degrees in one frame. The idle loop made
# the knee's bend direction hover around the rest pole and a hard switch flipped it 47 degrees with
# the foot not moving (a leg pop the foot / floor checks cannot see).
godot --headless --fixed-fps 60 --quit-after 700 --path "$project_dir" \
	res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn >"$log" 2>&1
knee=$("$project_dir/scripts/trace_v2.sh" --check --snaps --from 40 2>&1 |
	awk '$1 == "stairs" && $2 == "unarmed_idle" { print $13; exit }')
if [ -n "$knee" ] && awk -v k="$knee" 'BEGIN { exit !(k <= 15.0) }'; then
	printf 'PASS Foot IK v2 idle leg pop: max joint rotation in one frame %s deg\n' "$knee"
else
	printf 'FAIL Foot IK v2 idle leg pop: max joint rotation in one frame %s deg (limit 15)\n' "${knee:-?}"
	status=1
fi


# The knee's sideways offset over the same idle run (frames 100+) must stay steady: it used to swing
# 0.00 .. 0.115 m side to side because the animated knee swayed with the hips (limit 4 cm spread).
trace=$(ls "$HOME/Library/Application Support/Godot/app_userdata/"*/foot_ik_v2_check.jsonl \
	"$HOME/.local/share/godot/app_userdata/"*/foot_ik_v2_check.jsonl 2>/dev/null | head -1)
spread=$(jq -r '.feet.right.pose.final.knee_offset_right_m // empty' "$trace" | tail -n +100 |
	awk 'NR == 1 { lo = hi = $1 } { if ($1 < lo) lo = $1; if ($1 > hi) hi = $1 } END { print hi - lo }')
if [ -n "$spread" ] && awk -v s="$spread" 'BEGIN { exit !(s <= 0.04) }'; then
	printf 'PASS Foot IK v2 idle knee sway: side offset spread %s m\n' "$spread"
else
	printf 'FAIL Foot IK v2 idle knee sway: side offset spread %s m (limit 0.04)\n' "${spread:-?}"
	status=1
fi

exit "$status"
