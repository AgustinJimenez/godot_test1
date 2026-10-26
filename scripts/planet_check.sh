#!/usr/bin/env bash
# One command for every planet check: lint, import, then each lab check, one line per check and a
# final PASS/FAIL (exit 1 on any failure). `--quick` skips the slow fly check; `--lint-only` stops
# after lint. Godot is $GODOT, else `godot` on PATH, else the 4.7.2 install on this machine.
# Walk, swim and fly run headless at a fixed 60 fps; the logs stay in $LOG_DIR (default: a temp dir).
set -uo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DEFAULT_GODOT="/e/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"
cd "${PROJECT_ROOT}"

GODOT="${GODOT:-}"
if [[ -z "${GODOT}" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT="godot"
	else
		GODOT="${DEFAULT_GODOT}"
	fi
fi
GDLINT="${GDLINT:-gdlint}"
LOG_DIR="${LOG_DIR:-$(mktemp -d)}"
quick=0
lint_only=0
for arg in "$@"; do
	case "${arg}" in
		--quick) quick=1 ;;
		--lint-only) lint_only=1 ;;
		*) echo "unknown argument ${arg}" >&2; exit 2 ;;
	esac
done

failures=0

report() { # name verdict-line
	if [[ "$2" == *PASS* || "$2" == *SKIP* || "$2" == Success* || "$2" == "gdlint: ok" ]]; then
		echo "PASS  $1  ($2)"
	else
		echo "FAIL  $1  (${2:-no verdict line})"
		failures=$((failures + 1))
	fi
}

# run_check name seconds pattern scene [scene arguments...]
run_check() {
	local name="$1" seconds="$2" pattern="$3" scene="$4"
	shift 4
	local log="${LOG_DIR}/${name}.log"
	timeout "${seconds}" "${GODOT}" --headless --path . "${scene}" -- "$@" >"${log}" 2>&1 || true
	report "${name}" "$(grep -a -E "${pattern}" "${log}" | head -1)"
}

echo "logs: ${LOG_DIR}"
lint_out="$("${GDLINT}" . 2>&1)"
report lint "$(echo "${lint_out}" | tail -1)"
[[ ${lint_only} -eq 1 ]] && exit $((failures > 0))

"${GODOT}" --headless --path . --import >"${LOG_DIR}/import.log" 2>&1 || true
if grep -q "SCRIPT ERROR" "${LOG_DIR}/import.log"; then
	report import "SCRIPT ERROR in import.log"
else
	report import "PASS"
fi

lab=res://tests/manual/planet/planet_lab.tscn
run_check universe 300 "UNIVERSE_CHECK" "${lab}" --universe=42 --systems=3
run_check climate 300 "CLIMATE_CHECK" "${lab}" --climate-check
run_check water 300 "WATER_CHECK" "${lab}" --water-check --seed=7
run_check spawn 300 "SPAWN_CHECK" "${lab}" --spawn-check
run_check water_mesh 60 "WATER_MESH_CHECK" res://tests/manual/planet/water_mesh_native_check.tscn
run_check generation_native 60 "GENERATION_NATIVE_CHECK" res://tests/manual/planet/generation_native_check.tscn
run_check noise_golden 120 "NOISE_GOLDEN" res://tests/manual/planet/noise_golden.tscn
run_check drainage 300 "DRAINAGE_CHECK" "${lab}" --drainage-check --earth --cells=128
run_check species 600 "SPECIES_CHECK (PASS|FAIL)" res://tests/manual/world/species_check.tscn
run_check branches 300 "BRANCH_CHECK (PASS|FAIL)" res://tests/manual/world/branch_check.tscn
run_check undergrowth 300 "UNDERGROWTH_CHECK" res://tests/manual/planet/undergrowth_check.tscn
run_check sway 400 "SWAY_CHECK" "${lab}" --plants --grounded --sway-check
run_check turf 400 "TURF_CHECK" "${lab}" --plants --grounded --turf-check
run_check guard 400 "GUARD_CHECK" "${lab}" --grounded --guard-check --fixed-fps 60
run_check world 900 "WORLD_CHECK" res://tests/manual/world/world_lab.tscn --world-check
run_check planet 1200 "PLANET_CHECK" "${lab}" --planet-check --fixed-fps 60
report save "$(grep -a -E "SAVE_CHECK" "${LOG_DIR}/planet.log" | head -1)" # printed by the planet run
run_check walk 1800 "WALK_CHECK" "${lab}" --walk-check --fixed-fps 60
run_check swim 900 "SWIM_CHECK" "${lab}" --swim-check --fixed-fps 60
if [[ ${quick} -eq 0 ]]; then
	run_check fly 2400 "WALK_CHECK|FLY_CHECK" "${lab}" --fly-check --fixed-fps 60
fi

if [[ ${failures} -eq 0 ]]; then
	echo "PLANET_CHECKS PASS"
else
	echo "PLANET_CHECKS FAIL (${failures})"
	exit 1
fi
