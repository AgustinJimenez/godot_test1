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
