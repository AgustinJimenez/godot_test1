#!/usr/bin/env bash
# Builds outfits with tools/blender/build_outfit.py into a scratch folder and checks them with tools/blender/garment_check.py:
# the villager and woodsman outfits (both bodies) and a shirt with nothing under it. Prints BUILD_TEST PASS or BUILD_TEST FAIL; exit 0 / 1.
# Usage: bash tools/blender/garments/test_build.sh <scratch folder holding {male,female}_body.glb>
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.3/blender.exe}"
work="$1"
rigs="$(pwd)/assets/models/humans"
status=0
alone="${work}/shirt_alone.json"
printf '{"name": "alone", "garments": ["shirt"]}\n' > "${alone}"
for outfit in "$(pwd)/assets/models/humans/outfits/villager.json" "$(pwd)/assets/models/humans/outfits/woodsman.json" "${alone}"; do
	"${BLENDER}" -b --factory-startup --python tools/blender/build_outfit.py -- "${work}" "${rigs}" "${outfit}" > "${work}/build.log" 2>&1
	if ! grep -aq "^DONE" "${work}/build.log"; then
		echo "BUILD_TEST FAIL build $(basename "${outfit}")"; grep -a "Error\|Traceback\|line " "${work}/build.log" | head -5; status=1; continue
	fi
	for gender in male female; do
		out="$("${BLENDER}" -b --factory-startup --python tools/blender/garment_check.py -- "${work}" "${gender}" "${outfit}" 2>&1 | grep -a "GARMENT_CHECK")"
		echo "${out}"
		echo "${out}" | grep -aq "GARMENT_CHECK PASS" || status=1
		if [[ "${outfit}" == "${alone}" ]] && echo "${out}" | grep -aq " over "; then
			echo "BUILD_TEST FAIL the shirt alone reports a layer under it"; status=1
		fi
	done
done
[[ ${status} -eq 0 ]] && echo "BUILD_TEST PASS" || echo "BUILD_TEST FAIL"
exit "${status}"
