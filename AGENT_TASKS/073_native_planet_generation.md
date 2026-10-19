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

## 2. Plant meshes native (2026-10-19, `PlantMeshNative`)
`native/planet_crust/src/plant_mesh_native.cpp` is the tree grower (`TreeGrower`), the leaf shapes, the tube
builder and the smooth normals in C++ (`PlantMeshes.build` calls it with `TreeGenome.to_dictionary()`; without
the library the scripts grow the plant as before). All 36 species x 3 variants of seed 8, flat and realistic
(`tests/manual/world/native_plant_bench.gd`): 175 / 187 ms native against 1275 / 1476 ms in script (about 7.5x,
debug library), the triangle counts within 1-2 %. The grower's dice are PCG32 of its own, so the meshes are not
the script's exact ones. Species check and quick suite pass.
Still script: mushrooms, the far trees, the rocks (`FloraMeshes`), the placement (`PlanetScatter`).

## 3. Plant placement and far-tree merge native (`PlanetScatterNative`)
`PlanetScatter`'s loops (every layer's jittered grid, the species pick with the niche fitness and the patch noise,
rocks, pebbles, debris, logs, spires, the horizon trees, the colliders) run in C++ and answer with MultiMesh buffers
(16 floats an instance) ready for the tile to hang; the horizon trees of a tile are merged natively too. The script loops
remain as the fallback (no library, or the script hydrology). The climate grid setup (grid directions, elevation and
ocean) and the seasons' sea mask are native/batched: climate startup 166 -> 115 ms.
Measured per tile (714 tiles, High, seed 8): grid + heights 10.9 ms (the crust, native), normals/colours/triangles
1.7 ms, mesh node 1.0 ms, water 0.9 ms: the tile build is native already. What is left in script is node work the
engine owns (adding MultiMeshInstance3D, colliders, tile placement), the 0.3 s quadtree selection (1-2 ms; 20 ms
while the world loads) and orchestration (atmosphere, weather, menus).

## 4. Quadtree selection and the scenery meshes native
`PlanetSurfaceNative` chooses the tiles (the quadtree split, each tile's distance, collider and plant detail) and
orders the ones to build (`select`, `order`): the 20 ms hitch of the first selections is gone, ground ready 1.7 -> 1.3 s
on the seed 8 meadow. `PlantMeshNative` also builds the scenery (rocks, pebbles, stumps, logs, spires, fallen leaves and
sticks), the far trees and the mushrooms (`scenery`, `far_tree`, `mushroom`); its dice are the engine's own PCG32, so the
meshes are the script's exactly. The scripts (`MeshBuilder`, `FloraMeshes._rock`..., `PlantTreeBuilders.far`,
`PlantGroundBuilders`) stay as the fallback.

## 5. Map pictures (2048x1024 whole Earth, 2026-10-19, `PlanetChartProfile` / `tests/manual/planet/chart_times.gd`)
Every picture logs its phases (CPU per phase, summed over threads, plus the native cloud, sea-ice and land-colour time) to
`user://planet_map.log`, and to the output with PLANET_CHART_PROFILE=1.
Before -> after: Clouds 1160 -> 633 ms, Satellite 813 -> 442, Cloud mask 714 -> 328 (the cloud pattern is worked out for
every other pixel of a row and blended: 3.3 s -> 1.45 s of CPU), sea ice 822 -> 238 ms CPU (no trig per latitude step),
and the smoothing, despeckle and coast lines (60-430 ms) now run on the last chart thread, so the main thread only makes
the image (0.0 ms). Terrain is 1.2-1.4 s: the heights of the whole planet (5 s of CPU over all threads), cached for the
other layers.
