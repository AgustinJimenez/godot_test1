#!/usr/bin/env bash
# What the ground shader's parts cost on the GPU: the forest walk (tests/manual/planet/planet_lab_forest.gd,
# the same path every run) with one part of planet_ground.gdshader left out each run (`cost_off` bits,
# set from PLANET_GROUND_OFF in planet_tile.gd). GPU ms saved against the full shader = what that part
# costs. One run each is noisy (about 0.4 ms); never run two at once.
# Usage: scripts/gpu_ground_breakdown.sh [SECONDS_PER_RUN=25] [extra lab args...]
set -u
SECONDS_EACH="${1:-25}"
shift 2>/dev/null || true
GODOT="${GODOT:-godot}"
BASE=(--path . res://tests/manual/planet/planet_lab.tscn -- --plants --grounded "--forest-walk=${SECONDS_EACH}"
	--weather=clear --hour=11 --fixed-fps 60 "$@")
declare -a NAMES=("full ground shader" "plates' parallax march" "scans (photographic soil)" "chips' parallax"
	"all the crumbly gravel" "litter (twigs, leaves, needles)" "fine bump, meadow, rock, snow" "cloud shadows"
	"all the near detail")
declare -a MASKS=(0 1 2 4 8 16 32 64 128)
base_gpu=""
printf '%-34s %7s %9s %8s %9s\n' "left out" "fps" "gpu ms" "saved" "of total"
for index in "${!NAMES[@]}"; do
	out=$(env LAB_PLAIN=1 PLANET_GROUND_OFF="${MASKS[$index]}" "$GODOT" "${BASE[@]}" 2>&1)
	fps=$(echo "$out" | grep -a "FOREST_WALK fps" | sed 's/.*avg=\([0-9.]*\).*/\1/' | head -1)
	gpu=$(echo "$out" | grep -a "FOREST_WALK gpu" | sed 's/.*gpu ms avg=\([0-9.]*\).*/\1/' | head -1)
	if [ -z "$gpu" ]; then
		printf '%-34s %s\n' "${NAMES[$index]}" "(no result)"
		continue
	fi
	if [ -z "$base_gpu" ]; then
		base_gpu="$gpu"
		printf '%-34s %7s %9s\n' "${NAMES[$index]}" "$fps" "$gpu"
	else
		awk -v n="${NAMES[$index]}" -v f="$fps" -v g="$gpu" -v b="$base_gpu" \
			'BEGIN { printf "%-34s %7s %9s %8.1f %8.0f%%\n", n, f, g, b - g, 100.0 * (b - g) / b }'
	fi
done
