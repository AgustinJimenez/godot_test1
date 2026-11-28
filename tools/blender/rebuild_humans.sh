#!/usr/bin/env bash
# Rebuilds every human asset that carries the body's blend shapes, in order, into a work folder:
#   bodies + landmarks (make_bodies.py) -> eyes -> underwear -> clothes (every outfit, build_outfit.py, then garment_check.py) -> our classic brows/lashes -> the Mindfront brows (styles 11, 03, 06, 09) and lashes.
# Run after changing the shape keys in make_bodies.py. Does NOT copy anything into the project: compare, then copy the .glb files into
# assets/models/humans and the landmarks into tools/blender/landmarks, and run `godot --headless --import`.
#   bash tools/blender/rebuild_humans.sh <work folder> <folder with the unzipped Mindfront packs: mh_eyebrows/x, mh_eyelashes/x>
# The rigged bodies (make_rig.py) carry only the six body shapes and are not rebuilt here.
set -uo pipefail
work="$1"
packs="$2"
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.3/blender.exe}"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "${work}"
status=0
run() {
	local name="$1"; shift
	"${BLENDER}" -b --factory-startup --python "$@" > "${work}/${name}.log" 2>&1
	local code=$?
	if [[ ${code} -ne 0 ]] || grep -aq "Traceback" "${work}/${name}.log"; then
		echo "${name}: FAILED (see ${work}/${name}.log)"
		status=1
	else
		echo "${name}: ok"
	fi
}
run bodies tools/blender/make_bodies.py -- "${work}"
run eyes tools/blender/make_eyes.py -- "${work}"
run underwear tools/blender/make_underwear.py -- "${work}"
for outfit in assets/models/humans/outfits/*.json; do   # (every outfit's garments, inside out; the skin weights come from the rigged bodies in the project)
	name="$(basename "${outfit}" .json)"
	run "outfit_${name}" tools/blender/build_outfit.py -- "${work}" "$(pwd)/assets/models/humans" "$(pwd)/${outfit}"
	for gender in male female; do
		run "check_${name}_${gender}" tools/blender/garment_check.py -- "${work}" "${gender}" "$(pwd)/${outfit}"
	done
done
run face_hair tools/blender/make_face_hair.py -- "${work}"
run brows_mf tools/blender/fit_mindfront.py -- "${work}" "${packs}/mh_eyebrows/x/eyebrows/mindfront_eyebrows_11" brows_mf "${work}"
for style in 03 06 09; do
	run "brows_mf${style}" tools/blender/fit_mindfront.py -- "${work}" "${packs}/mh_eyebrows/x/eyebrows/mindfront_eyebrows_${style}" "brows_mf${style}" "${work}"
done
run lashes_mf tools/blender/fit_mindfront.py -- "${work}" "${packs}/mh_eyelashes/x/eyelashes/mindfront_eyelashes_01" lashes_mf "${work}" 0.0004 1.3
exit "${status}"
