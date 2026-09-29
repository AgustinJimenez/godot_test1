#!/bin/sh
# Random-pose fuzz for foot IK v2 (v1's turn-in-place idea, at many spots): drops the character at
# random (x, z) on the 0.10 m staircase with a random start yaw, then runs the quick turn sweep
# there - fine yaw steps, 40 degree snaps and smooth turns at 3/8/20 degrees a frame both ways -
# grading clip / float against the real floor, impossible leg poses and one-frame foot pops.
# Deterministic per seed. A failing pose is printed as a flag you can paste to reproduce:
#   scripts/fuzz_foot_ik_v2.sh [trials=10] [seed=1]
# Repro one: godot --headless --fixed-fps 60 --quit-after 1600 --path . \
#   res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check --stairs-turn=DZ:X:YAW:quick
set -u

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
trials=${1:-10}
seed=${2:-1}
log=$(mktemp "${TMPDIR:-/tmp}/foot-ik-v2-fuzz.XXXXXX")
trap 'rm -f "$log"' EXIT
failed=0

# x in [-1.3, 1.3] across the 3 m wide stairs, z in [-1.7, 2.0] along them (dz is relative to 1.36),
# yaw anywhere
poses=$(awk -v n="$trials" -v seed="$seed" 'BEGIN { srand(seed);
	for (i = 0; i < n; i++) printf "%.2f:%.2f:%.0f\n", (-1.7 + rand() * 3.7) - 1.36, -1.3 + rand() * 2.6, rand() * 360 }')

for pose in $poses; do
	godot --headless --fixed-fps 60 --quit-after 1600 --path "$project_dir" \
		res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn -- --foot-ik-v2-idle-check \
		--stairs-turn="$pose:quick" >"$log" 2>&1
	line=$(grep "FOOT_IK_V2_IDLE_CHECK" "$log" | head -1)
	case "$line" in
	*PASS*) printf 'ok   %s\n' "$pose" ;;
	*) failed=$((failed + 1)); printf 'FAIL %s\n     %s\n' "$pose" "${line:-no result line}"
		grep -a "TURN_FAULT\|TIP_\|HEEL_" "$log" | head -3 | sed 's/^/     /' ;;
	esac
done
printf 'fuzz: %d of %s poses failed (seed %s)\n' "$failed" "$trials" "$seed"
[ "$failed" -eq 0 ]
