# 073 - Planet generation to native C++ (overnight task 2)

Measure first, convert what costs, match the old output with a check, one commit per step.

## Done
1. **River and lake water queries native** (`PlanetCrustNative::water_at / near_water / flow_at`, wrapped
   by `PlanetNoise.water_at / near_water / flow_at`): what the 645-line script `PlanetHydrology` answered
   for swimming, the current, the plants keeping off the water and the "is this wet" test. With
   `hydrology_cells` = 0 (the new default) the script hydrology is not built.
   Before (full Earth, rivers on): ground ready after 6.8 s, 1.1 s of startup in the script hydrology, and
   every tile on the slow per-point script height path (`hydrology != null`: 116-176 fps with plants).
   After: ground ready after 1.3 s, startup 0 ms there, tiles on the native path, ~490 fps at 700 tiles.
   `scripts/planet_check.sh --quick` passes (the water check builds the script hydrology on purpose).

## What still runs in GDScript (measured at full Earth, startup 2.1 s: drainage solve 1.6 s native,
climate 0.17 s, sea level 0.05 s)
- Tile building (`PlanetTile.build`: the skirt, running-water meshes, normals fallback): partly native.
- Plants (`PlanetScatter`, ~500 lines): the placement loops, one `_noise.biome` / `moisture` call per
  candidate point. The next conversion (and the frame cost of plants is big: see the draw calls).
- Map charts: native rows for every layer already.
- The script hydrology and its pieces (645 lines) are now dead code by default; remove once nothing uses it.

## Measured on the plants (full detail tile, 76 m, seed 8 greenest meadow, High, 2026-10-19)
- Placement of all layers: ~95 ms a tile (per-candidate queries cost 1-5 us each in script).
- Building the batches (`_flush`): 56-130 ms a tile in steady state (was 75-330: the per-instance
  `set_instance_*` calls are now one `MultiMesh.buffer` write and the far-tree vertex tint is native
  `tinted`), but **1-4.4 s on the first tiles**: the plant meshes of each species are generated in script
  the first time they are needed (`PlantMeshes`, on the worker thread, so the tiles wait).
- So the plants' real cost is mesh generation. The plan: task 3 replaces the plant meshes with a native
  generator (realistic, non-repeating), which also removes this stall.
