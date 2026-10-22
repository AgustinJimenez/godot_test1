#!/usr/bin/env bash
# Where the game's GPU time goes, by taking things away: the same person walks the same forest path
# (tests/manual/planet/planet_lab_forest.gd, a fixed wander seed) once for each thing switched off; the
# GPU ms the frames lose is what that thing costs. The shares do not add up to 100 %: shadows and
# trees overlap, and taking one away changes what the others cost. Godot gives no per-pass GPU times
# to scripts (the editor's Debugger > Visual Profiler shows them, run the game from the editor).
# Usage: scripts/gpu_breakdown.sh [SECONDS_PER_RUN=25] [extra lab args...]   (about 1 minute a run)
set -u
SECONDS_EACH="${1:-25}"
shift 2>/dev/null || true
GODOT="${GODOT:-godot}"
BASE=(--path . res://tests/manual/planet/planet_lab.tscn -- --plants --grounded "--forest-walk=${SECONDS_EACH}"
	--weather=clear --hour=11 --fixed-fps 60 "$@")
declare -a NAMES=("everything on" "sun shadows off" "trees hidden" "small plants and grass hidden" "ground hidden"
	"water hidden" "clouds hidden" "sun glow pass off" "tree impostors off" "bark parallax off" "bark photos off (procedural)")
declare -a ARGS=("" "--no-shadow" "--hide=trees" "--hide=plants" "--hide=ground" "--hide=water" "--no-clouds"
	"ENV:NO_SUN_GLOW=1" "ENV:NO_IMPOSTORS=1" "--bark=pom-off" "--bark=photo-off")
base_gpu=""
printf '%-34s %7s %8s %9s %8s %9s\n' "switched off" "fps" "1%low" "gpu ms" "saved" "of total"
for index in "${!NAMES[@]}"; do
	extra="${ARGS[$index]}"
	env_set=()
	extra_args=()
	case "$extra" in
		ENV:*) env_set=("${extra#ENV:}") ;;
		"") ;;
		*) extra_args=("$extra") ;;
	esac
	out=$(env LAB_PLAIN=1 "${env_set[@]}" "$GODOT" "${BASE[@]}" "${extra_args[@]}" 2>&1)
	fps=$(echo "$out" | grep -a "FOREST_WALK fps" | sed 's/.*avg=\([0-9.]*\).*/\1/' | head -1)
	low=$(echo "$out" | grep -a "FOREST_WALK fps" | sed 's/.*1%low=\([0-9.]*\).*/\1/' | head -1)
	gpu=$(echo "$out" | grep -a "FOREST_WALK gpu" | sed 's/.*gpu ms avg=\([0-9.]*\).*/\1/' | head -1)
	if [ -z "$gpu" ]; then
		printf '%-34s %s\n' "${NAMES[$index]}" "(no result)"
		continue
	fi
	if [ -z "$base_gpu" ]; then
		base_gpu="$gpu"
		printf '%-34s %7s %8s %9s\n' "${NAMES[$index]}" "$fps" "$low" "$gpu"
	else
		awk -v n="${NAMES[$index]}" -v f="$fps" -v l="$low" -v g="$gpu" -v b="$base_gpu" \
			'BEGIN { printf "%-34s %7s %8s %9s %8.1f %8.0f%%\n", n, f, l, g, b - g, 100.0 * (b - g) / b }'
	fi
done
