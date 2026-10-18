# 070 - Making the map and the world start faster

Status: **open list (2026-10-18)**. Numbers are from the full Earth, seed 8, a 6-core Windows PC, scripted runs
(`PLANET_TIMING=1`, `user://planet_map.log`). Read `docs/planet_generation.md` (the map sections) first.

## Where we are

Start with `--map-first` (the game's start), measured:

| Step | First time | Same world again |
|---|---|---|
| Making the planet (crust, sea level, climate, drainage) | ~2.0 s | ~2.0 s |
| Charting the map behind the black screen | ~9.5 s | ~2.1 s |
| Building the ground after the map is closed | ~1.7 s | ~1.7 s |
| **Total** | **~13 s** | **~6 s** |

Inside the planet step: sea level 45 ms, climate 161 ms, drainage solve 1.6 s, river network 0.24 s.
Inside the map warm-up: whole passes 320/640/1024/2048 (~2.5 s), the 29 tiles of the start view (~2.5 s), a first
picture of ten other layers (~1.5 s; each 0.07 to 0.33 s once the heights are shared).
The map's pictures are read from `user://map_cache/<key>/` on later runs (`PlanetMapCache`, raise its `VERSION`
whenever the crust, the climate or a layer's drawing changes).

## What was tried and did not help

- **-O3 instead of -O2** (godot-cpp builds the debug library with -O2, release with -O3): the same charts took 1.5 to
  1.6 s with -O3 against 1.46 to 1.50 s with -O2. No gain. Do not retry.
- **Plain C instead of C++**: the same compiler, and the code is already C-style loops over arrays. No gain expected.
- The WorkerThreadPool of the engine ran a group task on one thread; the library uses `std::thread` with a chunk counter.

## The ideas, from the cheapest

1. **Overlap the map with the drainage solve** (saves ~1.6 s of the start). The map's heights do not need the drainage
   (the valleys are cut by it, so the first passes would need a redraw of the rivers only). Start charting the
   whole-planet passes while `PlanetDrainage.build` runs on another thread, then draw the river valleys.
2. **Fewer octaves for the map** (the sharp chart takes ~1.5 s for ~3 million points, ~25 noise lookups each). The map
   already leaves out octaves finer than 3 pixels (`at_lod`); the Atlas could use 5 pixels, and the eroded ridges
   (9 octaves) can stop earlier on far views.
3. **Skip the 2048 whole pass until the map is shown** (1.6 s of the warm-up): the 1024 pass is sharp enough for a far
   view; chart the 2048 pass after the map opens.
4. **A smaller sharp tile level** or cap the start view's tiles (29 tiles ~2.5 s): chart only the tiles under the
   player first and the margin later.
5. **Threaded drainage solve** (1.6 s, now one thread): the priority-flood is serial; the water routing and the river
   network can be split by cube face.
6. **SIMD noise**: compute 4 or 8 noise values at once (SSE/AVX, NEON on the Mac). Could give 2 to 3x on the height
   chart, but it is a rewrite of the noise code, written by hand for both CPUs (`-march=native` is not portable).
7. **GPU colouring of the layers**: the heights go to a texture once and a shader makes the colours (layer, time,
   shading, coast lines), so changing layer or time costs one draw. Needs the coast lines and the blur in the shader.
8. **GPU noise** (the heights themselves in a compute shader): the biggest possible gain and the biggest job; the
   native crust stays the reference (the player stands on its heights).
9. **Cache more**: the shared heights (8 MB at 2048 x 1024) and the drainage result per world on disk, so a world
   opened again skips the 1.6 s solve too. Key them like the map cache (settings + a version).
10. **Start the map earlier**: the map charts nothing until the planet is made; the plates, the climate and the sea level
    (~0.25 s) are enough for the first passes.

## How to measure

- `PLANET_TIMING=1 PLANET_SCALE=1 godot ... planet_lab.tscn -- --earth --seed=8 --map-first --close-map=1500` prints the
  planet steps and "ground ready after"; the map log (`user://planet_map.log`) has every chart with its ms and
  "warm-up done: the map is ready".
- A timing script of the charts alone: build `PlanetNoise`, make a `PlanetChart` (layer, `rect`, `size`), `start`, poll
  `finished()`, `texture()`, and print the ms (see the session's `time_test.gd` idea in the log of 2026-10-18).
- Compare twice (the first run after a build is slower), and delete `user://map_cache` between "first time" runs.
