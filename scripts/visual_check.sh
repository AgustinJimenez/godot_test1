#!/usr/bin/env bash
# Visual regression: renders fixed views of the planet (a window is needed) and compares them with the accepted pictures in
# tests/visual/baseline (scripts/visual_compare.py). `--accept` stores what was just rendered as the new baseline (look at
# the pictures first: $OUT_DIR). A failing picture leaves its difference in $OUT_DIR/diff. Run it after a change to the ground,
# the sky or the light; a change that is meant to alter a picture is accepted afterwards.
set -uo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DEFAULT_GODOT="/e/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"
cd "${PROJECT_ROOT}"
GODOT="${GODOT:-${DEFAULT_GODOT}}"
OUT_DIR="${OUT_DIR:-${TEMP:-/tmp}/visual_check}"
accept=""
[[ "${1:-}" == "--accept" ]] && accept="--accept"
rm -rf "${OUT_DIR}"
export APPDATA="${OUT_DIR}/appdata" # (a fresh user folder: the pictures must not depend on the graphics settings saved on this machine)
mkdir -p "${OUT_DIR}/diff" "${APPDATA}"

# name | extra lab arguments | LAB_GROUND (the ground detail) ; the dirs are on seed 1337 unless said
shoot() {
	local name="$1"
	shift
	LAB_GROUND=3 "${GODOT}" --path . res://tests/manual/planet/planet_lab.tscn -- --weather=clear --no-clouds \
		--fixed-fps 60 --shot-frame=900 --shot="${OUT_DIR}/${name}.png" "$@" >/dev/null 2>&1
}
common=(--hour=15 --seed=1337)
shoot desert_dunes "${common[@]}" --bare --dir=0.45221,0.67183,-0.58664 --view-alt=1.5 --view-pitch=-15
shoot desert_close "${common[@]}" --bare --dir=0.45221,0.67183,-0.58664 --view-alt=0.8 --view-pitch=-50
shoot desert_far --hour=17.5 --seed=1 --bare --dir=-0.7687,0.6392,-0.0225 --view-alt=40 --view-pitch=-12
shoot desert_sunset --hour=18 --seed=1337 --bare --dir=0.45221,0.67183,-0.58664 --view-alt=3 --view-pitch=-5 --view-yaw=90
shoot desert_plants "${common[@]}" --plants --dir=0.45221,0.67183,-0.58664 --view-alt=1.5 --view-pitch=-35
shoot green_country "${common[@]}" --plants --view-alt=1.7 --view-pitch=-8

python scripts/visual_compare.py "${OUT_DIR}" tests/visual/baseline "${OUT_DIR}/diff" ${accept}
