#!/usr/bin/env bash
# Copies the planet's voxel generator module (native/voxel_planet_module) into the double precision engine's source tree,
# next to the voxel module (task 096). Then rebuild the engine (see AGENT_TASKS/096_caves_godot_voxel_spike.md).
#   scripts/install_voxel_planet_module.sh [ENGINE_SRC]      (default E:/Godot/double/src)
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine="${1:-E:/Godot/double/src}"
if [[ ! -d "${engine}/modules/voxel" ]]; then
	echo "no ${engine}/modules/voxel: put godot_voxel v1.7 there first" >&2
	exit 1
fi
rm -rf "${engine}/modules/voxel_planet"
mkdir -p "${engine}/modules/voxel_planet"
cp "${root}"/native/voxel_planet_module/* "${engine}/modules/voxel_planet/"
echo "installed into ${engine}/modules/voxel_planet"
