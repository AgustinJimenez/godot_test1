# 096 - Caves: test the godot_voxel library in a scratch project

Started 2026-10-29. User: "i think it is [a goal], let's make it a task" (caves / tunnels / overhangs in the planet terrain).

## Why a library at all
- The planet terrain is a heightmap (`HeightMapShape3D` collision under Jolt, see `AGENTS.md` and `docs/planet_generation.md`). A heightmap stores one
  height per point, so nothing can exist underneath it: no caves, tunnels or overhangs.
- Caves need a volume (solid or empty at every 3D point). https://github.com/Zylann/godot_voxel is a C++ module/extension for volumetric terrain
  in Godot 4 (MIT). From its page: smooth terrain with LOD (Transvoxel), blocky terrain, overhangs and tunnels, in-game editing, chunk streaming,
  custom generators, collision (Godot physics or a faster Minecraft-style option), instancing.

## What the page did NOT say (the spike must answer these)
1. Does a build exist for Godot 4.7.2? The page lists no 4.x versions. "Make GDExtension work" is on its roadmap, so it may need a custom ENGINE build
   (a different Godot binary from the stock `Godot_v4.7.2-stable_win64_console.exe`). If it does: stop and tell the user before building anything.
2. Does it work with Jolt (`3d/physics_engine="Jolt Physics"`) and with our double-precision setup?
3. Can it do a spherical planet? The page says nothing about it; this is expected to be the hard part.
4. Cost: frame time with a cave region loaded, and the load/mesh time per chunk.

## Research result (2026-10-29, from the releases page and docs; nothing downloaded yet)
- Releases page (github.com/Zylann/godot_voxel/releases): "Voxel Tools GDExtension 1.7" (tag v1.7x, Godot 4.5+, 3 files) works with an OFFICIAL Godot build,
  Windows x86_64 included, no custom engine (voxel-tools.readthedocs.io/en/latest/getting_the_module/). Warning there: less tested than the module builds.
- The module edition "Godot 4.7.2 + Voxel Tools 1.7" is a custom Godot build of our exact version (11 files), only needed if the extension falls short.
  "double" (large-coordinates) builds exist only for the module edition and come without export templates.
- Answers question 1: a prebuilt exists. Still open: Jolt, spherical planet, double precision (check whether this project's Godot is a double build), cost.
- Other routes found: Terrain3D heightmap holes + Blender cave meshes (same as route b below), Digger-style hybrid (heightmap + voxel caves, Unity),
  smaller marching-cubes projects (voxelman, a 4.1 demo; versions and upkeep unknown), or our own small C++ GDExtension (like `native/planet_crust`).

- Confirmed through the GitHub API (2026-10-29): release `v1.7x` (2026-08-20) has one file, `GodotVoxelExtension.zip` (53 MB). Release `v1.7` has
  `godot.windows.editor.double.x86_64.exe.zip` (87 MB) and `godot.windows.editor.x86_64.exe.zip`, both Godot 4.7.2 with Voxel Tools built in.
- This project also has its OWN double-precision editor build (`E:\Godot\double`, see `docs/planet_generation.md` "The double precision editor build"). The
  official GDExtension is single precision, so on a planet built around double precision the extension may show float jitter far from the origin: test far from (0,0,0).

## Plan
1. Scratch project OUTSIDE this repository (do not touch this project's files or `project.godot`). Use the stock 4.7.2 exe plus the GDExtension 1.7x zip (unzip at the scratch project root).
2. Make a small flat voxel terrain with a cave (3D noise carved, or a tunnel); check it loads, shows the cave, and gives collision a character can walk into.
3. Check Jolt (set the scratch project to Jolt) and note what happens.
4. Report: what works, what does not, the install path, and the cost. This tests the plain library only, NOT the planet integration.
5. Only then decide the integration route: (a) voxel terrain for caves only, entered through meshes on the heightmap planet; (b) caves as separate
   scenes loaded at entrances (no library, placed by hand); (c) full voxel planet (large change, only if the spike shows spherical support); (d) our own small C++ voxel/marching-cubes GDExtension for caves only.

## Spike result (2026-10-29)
Scratch project `E:\Temp\claudeoxel_spike\proj` (outside this repository; `main.gd` is the test; extension zip unzipped under `addons/zylann.voxel`).
Stock `Godot_v4.7.2-stable_win64_console.exe`, Jolt, GDExtension 1.7x, single precision, `VoxelTerrain` + `VoxelGeneratorNoise` (3D simplex SDF) + `VoxelMesherTransvoxel`.
- Loads on the official 4.7.2 build (all classes present). No custom engine build needed. No errors in the log.
- Smooth terrain with pits and openings renders (screenshot checked by eye).
- Volume, not surface: a column scan of the SDF found air under solid (caves/overhangs) in 7 of 441 sampled columns at the origin and 4 at an offset.
- Collision with Jolt: a dropped ball fell about 80 m, slowed on the generated collision and did not fall through (still rolling at the last frame, so
  "settled on the floor" is NOT proven; the ball might be in a cave).
- Far from the origin (offset 1,000,000 m on x and z): still loads, collides and renders. The screenshot shows thin dotted lines along block edges that the origin
  one does not: probably single-precision seams. Not measured further.
- NOT tested: frame time or chunk cost, a sphere/planet layout, editing (digging), LOD terrain (`VoxelLodTerrain`), the double-precision module build, how it would
  join our heightmap planet, textures/materials, walking a character into a cave.

## Cost measurements (2026-10-29, scratch project, RTX 4090, vsync off, windowed, a flight of 10-12 s at 40 m/s; `bench.gd` there)
Terrain is the same 3D-noise slab (40 m tall), so these are FLAT-WORLD numbers, not planet numbers.
| mode | view | blocks | load | frame avg / p99 | Godot memory | draw calls / triangles |
|---|---|---|---|---|---|---|
| VoxelTerrain | 128 m | 1,296 | 1.3 s | 0.35 / 0.58 ms | 165 MB | 182 / 105k |
| VoxelTerrain | 256 m | 4,624 | 2.2 s | 0.86 / 3.2 ms (worst 16 ms) | 290 MB | 672 / 404k |
| VoxelTerrain | 512 m | 17,424 | 6.3 s | 3.2 / 19 ms (worst 31 ms) | 1,306 MB | 2,578 / 1.53M |
| VoxelLodTerrain, 5 levels | 1 km | n/a | ~3 s | 0.38 / 1.4 ms | 132 MB | 137 / 141k |
| VoxelLodTerrain, 7 levels | 4 km | n/a | ~3 s | 0.39 / 1.4 ms | 133 MB | 133 / 137k |
| VoxelLodTerrain, 9 levels | 16 km | n/a | ~3 s | 0.43 / 1.4 ms | 144 MB | 195 / 184k |
- Plain `VoxelTerrain` memory and blocks grow with the cube of the view distance (voxel data pool 51 MB, 110 MB, 744 MB at 128, 256, 512 m): fine for a cave
  region of a few hundred metres, not for a planet.
- `VoxelLodTerrain` stays flat (about 0.4 ms, 140 MB) out to 16 km because far blocks use coarser levels. The load time (about 3 s) is only an upper bound
  from my detection (it waits 2 s idle); the block count is not reported for this mode. A real planet surface has far more surface per block than this slab
  (and a sphere layout is untested), so expect higher numbers; this only shows the engine part is cheap.
- Disk: the extension zip is 53 MB, the whole `bin` folder 130 MB (all platforms); the Windows DLLs are 10.8 MB (editor) and 9.7 MB (release template). Only the
  Windows files would ship.
- NOT measured: generation cost with a real planet generator (the noise generator is native and fast; a GDScript generator would be much slower), cost while
  digging, sphere/planet layout, memory with edits saved, colliders for LOD terrain, anything on the double precision build.

## Planet-sphere test (2026-10-29, scratch `planet.gd`, official 4.7.2 + GDExtension 1.7x, single precision, Jolt)
`VoxelLodTerrain` + `VoxelGeneratorGraph` built IN CODE (the graph class can be assembled with `create_node` / `add_connection`): a sphere SDF plus 3D hills noise
(250 m, wavelength ~3 km) plus optional 3D-noise caves (`max(terrain, cave)`), 9-12 LOD levels, view 4096 m, viewer at the north pole flying 60 m/s for 8-10 s,
a ball raycast-placed on the ground. Cave size NOT tuned (it looks like swiss cheese); material override did not apply to the LOD terrain (white surface).
| radius | caves | load | frame avg / p99 | Godot / video memory | triangles | ball on the ground? |
|---|---|---|---|---|---|---|
| 20 km | no | ~6 s | 0.38 / 0.9 ms | 121 / 47 MB | 84k | yes (gap 1.3-1.6 m, rolls on the slope) |
| 20 km | yes | ~6.6 s | 0.65 / 1.4 ms (worst 12.7) | 250 / 197 MB | 1.2M | yes |
| 200 km | yes | 8 s | 0.97 / 1.4 ms (worst 12) | 429 / 400 MB | 2.5M | yes |
| 6,371 km (Earth) | yes | 7.8 s | 0.99 / 1.5 ms | 420 / 394 MB | 2.6M | NO: the ball does not move at all (Jolt in single precision, as `docs/planet_generation.md` "Limits" already says); the terrain renders but with jagged edges |
- The voxel planet works at 20 km (our default radius) and 200 km on the stock build: LOD terrain, caves in the sphere, collision, ray casts.
- At Earth size on single precision the physics is stuck and the surface edges are jagged: a double-precision build is needed (see below), as for our heightmap planet.
- NOT tested: the prebuilt double-precision module editor (`godot.windows.editor.double.x86_64.exe.zip`, 87 MB, release v1.7), real planet shape (our `PlanetSettings`
  terrain, rivers, sea, plants), texturing (triplanar), frame time on a real surface (these are noise slabs), walking a character in a cave, digging, memory after
  long flights, load time with 9+ LODs on slower machines.

## Earth size on the double-precision module build (2026-10-29)
Prebuilt `godot.windows.editor.double.x86_64.exe` from release v1.7 (Godot 4.7.2 double + Voxel Tools, 181 MB exe, 85 MB zip), same `planet.gd`, scratch copy
`proj_module` WITHOUT the GDExtension (the module already has the classes). Radius 6,371,000 m, caves on, 12 LODs, view 4096 m:
- Loads in 10.2 s, frame 0.92 / 2.1 ms (worst 12.7), memory 699 MB (the single build used 420 MB), video 395 MB, 2.64M triangles.
- The ball falls and lands on the ground (gap 1.3-2.1 m) and rolls: collision and physics WORK at Earth size here, unlike on single precision (ball stuck).
- CORRECTION: I first called the jagged surface edges on single precision a precision effect. The double build shows the SAME jagged edges in the same picture, so they come from my
  untuned cave graph (thin cave walls, LOD), not from precision.
- Side note: `--headless --import` of that scratch project segfaulted the double exe; the windowed run was fine.
- Downsides: the double editor has no export templates ("double" builds come without them, see the releases page), and `voxel.gdextension`-style install does not
  apply: it replaces our own double build in `E:\Godot\double` (which has D3D12 and our options) with a Voxel Tools build. Having both means building the voxel
  module into OUR double engine (a custom engine build), or switching engines. Not tested: our own native libraries (`planet_crust`) against that exe.

## Next steps found by reading (2026-10-29, nothing built or changed yet)
- Our own double engine source is `E:\Godot\double\src` at commit `ed1daf0` ("Bump version to 4.7.2-stable"), the SAME commit the Voxel Tools v1.7 custom
  build was made from (`ed1daf0bf`). So adding the module is: clone godot_voxel (matching v1.7) into `E:\Godot\double\src\modulesoxel` and re-run the same
  `scons platform=windows target=editor precision=double arch=x86_64 d3d12=yes debug_symbols=no`; the engine objects exist in `bin/obj`, so the rebuild should be partial
  (module compile + link; time not measured). Keep the old exe by copying it first. No export templates exist for the double build either way.
- The planet's height is "pure functions of a direction" (`PlanetNoise.height`); the native `PlanetCrustNative.heights(dirs)` returns heights for a bulk of
  directions. A voxel generator can therefore be: SDF(p) = |p| - (R + height(dir(p))), evaluated per block. In the official build a generator has to be a GDScript
  `VoxelGeneratorScript` (a GDExtension cannot plug into the voxel classes), calling the bulk native height for the block's voxels (4,096 per 16-voxel block, fewer
  with a coarse grid). With the module built into our engine, a C++ generator inside the module would be possible. Both untested; the first test is the GDScript one.
- `docs/planet_generation.md` says the project has no native GDExtensions; that is out of date (`native/planet_crust`, foot IK libraries exist). Not fixed here.

## Not decided
- Which route (a / b / c). Decide after the spike with the user.

## Log
- 2026-10-29: task written. Spike run (see Spike result): the extension works on stock 4.7.2 with Jolt; planet integration and cost still open.

## Module built into our own double engine (2026-11-08)
- Cloned godot_voxel `v1.7` into `E:\Godot\double\src\modules\voxel` (engine source is at `ed1daf0`, the same commit) and re-ran the usual
  scons line (`platform=windows target=editor precision=double arch=x86_64 d3d12=yes debug_symbols=no`). Build time: 4 min 53 s
  (the new module changes the module list, so `main` and `gltf` recompile too). Log: `E:\Godot\double\build_voxel.log`.
- The previous exes are in `E:\Godot\double\backup_novoxel\`.
- Check: the new exe reports `4.7.2-stable (custom_build)` and `ClassDB` has `VoxelLodTerrain` and `VoxelGeneratorGraph`.
- Not yet checked: the Earth-size planet test on this exe, our native `planet_crust` / foot-IK libraries against it, export templates (none built).
- Earth-size run on OUR module build (same `planet.gd`, 6,371 km, 12 LODs, view 4096, caves on, 20 s): the ball lands (gap 1.3-1.7 m) and rolls, same as on the prebuilt exe.
  Memory 748 MB, video 421 MB, 2.6M triangles, 688 draw calls. The 16.67 ms frames are vsync (this run had it on; the earlier 0.92 ms numbers had it off), so no timing comparison.
  The last sample shows gap -2.6 m (ball slightly inside the surface on a slope or cave edge); not investigated. Picture: `E:\Temp\claude\voxel_spike\planet_ownengine.png`.

## Real planet height on the voxel engine (2026-11-08)
- The whole planet is native now (`PlanetSettings`, `PlanetNoise` with bulk `heights_of(dirs)`; the GDScript is gone), so the generator calls those directly.
- The double precision `planet_crust` DLL in `bin/` was STALE (Oct 20, 1.9 MB, from before the planet port): no Planet* class loaded, even in the old double exe.
  Rebuilt with `scripts/build_native.sh --double` (see README for the env vars); it failed first because godot-cpp master dropped `Math_PI` / `Math_TAU`.
  `native/planet_crust/SConstruct` now defines them when the godot-cpp headers lack them (the single build is unchanged).
- Check on the voxel exe (headless, project root): `ClassDB` has `PlanetNoise`, `PlanetSettings` and `VoxelLodTerrain` together; `PlanetSettings.earth(1.0)` radius 6,371,000 m, seed 1337;
  heights of 8 directions between -3.8 km and +1.8 km; `heights_of` 20,000 directions in 17.7 ms (~0.9 us a point).
- A scratch project needs `.godot/extension_list.cfg` listing the `.gdextension` for a headless run; an absolute DLL path in the `.gdextension` was not enough on its own in `proj_real`
  (the classes did not appear there; the repo root works), so use the repo as the project for the next step.

## Real planet as voxel terrain (2026-11-08)
Files: `tests/manual/voxel/real_planet_generator.gd` (GDScript `VoxelGeneratorScript`: sdf = |p| - (R + `PlanetNoise.heights_of(dir)`), blocks farther than 12 km
from the surface are filled without asking), `real_planet.gd` / `.tscn` (LOD terrain, viewer, ball with gravity toward the centre, report). Run it with the module engine
(`--path . res://tests/manual/voxel/real_planet.tscn -- --lods=12 --view=4096 --secs=15 --ball=1 --shot=PATH`).
Result, Earth size (R 6,371,000 m, seed 1337), spawn on land (noise height 191 m), windowed, vsync on, 12 LODs, view 4096:
- Loads in 99 s (the loaded point: no tasks left for 2 s). The generator ran 11,947 blocks in the whole run. Calls to `heights_of` from the 3 worker threads at once did not
  crash (no mutex), but whether the native code is thread safe is NOT verified (one earlier run with a mutex was serial and did not finish loading in 240 s).
- Cost is the native height: 28-40 ms a near-surface block of 18^3 voxels, of which `heights_of` is ~32 ms (5.5 us a land point; random directions, mostly sea, were 0.9 us).
  The GDScript loops around it are ~5 ms. So the generator is bound by `PlanetNoise`, not by GDScript.
- Correct shape: a raycast on the terrain hits 190.7 m above the radius where the noise says 191.2 m. The ball lands, rolls downhill (190-196 m) with gravity toward the centre.
- Memory 204 MB, video 247 MB, 164k triangles; 16.7 ms frames are vsync. The picture (`E:\Temp\claude\voxel_spike\real_planet2.png`) shows grey terrain with dark patches (no
  sky, no material, no environment light: the lighting is the unlit side, not looked into).
- Not done: surface colours / the ground shader, sea, rivers, plants, caves, character walking, loading time (99 s is too long; ideas: heights on a coarser lattice and interpolate,
  skip voxels far from the surface, cache, native generator via the module), thread safety check of `PlanetNoise`.

## Load time: heights on a coarser lattice (2026-11-08)
The generator asks the planet for a height every `lattice` voxels along each axis of the block and interpolates between them (separable lerps in GDScript); `lattice` 1 is exact.
Block of 18^3 voxels on land, 6 spots, near-surface (|sdf| < 3 voxels) error against the exact block:

| lattice | ms/block | worst error | mean error |
|---|---|---|---|
| 1 | ~21 | 0 | 0 |
| 2 | ~4.2 | 0.24 voxel (lod 6) / 0.02 (lod 0) | 0.008 |
| 3 | ~2.2 | 0.34 | 0.013 |
| 4 | ~1.85 | 0.40 | 0.017 |

Whole planet (Earth size, 12 LODs, view 4096, same spawn): loaded after 99 s (exact) -> 25 s (lattice 2) -> 9.2 s (lattice 4). Raycast hit stays 190.7 m (noise 191.2 m).
Pictures: lattice 4 blurs the distant ripples; lattice 2 keeps them (looks like the exact one). Default is 2 (`--lattice=N` sets it). Thin straight seam lines show at
patch edges with 2 and 4 (not seen in the exact picture); not investigated (LOD borders, or the interpolation anchored per block). Pictures: `E:\Temp\claude\voxel_spike\real_lat2.png`, `real_lat4.png`.
The block is now bound by the GDScript loops (~1.5-2 ms), not by the planet.

## The real player walks on the voxel planet (2026-11-08)
`tests/manual/voxel/voxel_walk.tscn` (`-- --secs=30 --shot=PATH [--lattice=2 --view=2048 --seed=N]`). The terrain is NOT turned: the generator asks the planet's noise
through a rotation (`frame`, a `Basis` that sends +Y to a chosen land direction), so the spot is at the top of the world and the player's up / gravity are the world's own.
The voxel viewer (with collisions) follows the player; the player is placed 3 m above a raycast hit once the terrain has loaded. A real `player.tscn`, sun with shadows, sky.
Result (Earth size, spawn on land at 191 m, view 2048, lattice 2, vsync on): loaded after 25.7 s; raycast ground 191.0 m (noise 191.2); the player sprints 30 s:
`WALK PASS travelled=147 m on_floor=91% worst_above_ground=0.03 m`, 1974 frames, worst frame 135 ms (1 frame over 33 ms; the first frames after the spawn, not looked into).
Picture `E:\Temp\claude\voxel_spike\walk1.png`: the character runs on white hills (default material, overexposed), feet on the ground, shadow on the terrain.
NOT done / not checked: the lab's sky, plants, water and ground shader; walking far (the terrain is not rebased: a km away the "up" is off by ~0.5 deg per km... fine for a test, wrong for
a real game, which needs the lab's `PlanetFrame` turn); foot IK on slopes; jumping, climbing, swimming; digging; caves.

## Ground colours, caves, digging (2026-11-08), all on the walking test
`voxel_walk.tscn -- [--caves] [--cave-visit] [--dig] --secs=N --shot=PATH`.
- Ground colours: `shaders/voxel/voxel_ground.gdshader` set as the terrain's `material` (NOT `material_override`). Height = |world position| - radius and slope = normal against the
  radial direction (the model matrix is in absolute world coordinates in the double engine, float precision 0.5 m at Earth size; my first try assumed camera-relative and painted
  everything the debug colour). Sand / grass / soil / rock on slopes / snow above 2200 m, with value noise. Crude: NOT the planet's biome colours (`PlanetNoise.colours_of`), no
  textures, no sea. Picture `walk4.png`: green hills with sand and bare patches in the distance (pale: the default sky light is bright, not tuned).
- Caves: `RealPlanetGenerator.setup_caves(seed)`: tunnels are where two simplex noises are both near zero (one noise alone gives sheets, not tunnels), `CAVE_WIDTH` 0.06 -> about
  4.4 m of radius, carved from the ground down to 200 m, only at LOD <= 3. `--cave-visit` finds the tunnel centre 20-100 m down near the spawn, starts the player inside it:
  voxel value there +3.98 (air), floor found, the real player stands in it (picture `cave1.png`: rock walls around the character, 61 m under the ground). The cave interior is lit
  by the sky ambient (no darkness), walls are the rock colour. Not done: entrances on purpose, big caverns, the cost of the cave noise in GDScript (per voxel, two noise calls;
  load time with caves was 28.5 s against 25.8 s without).
- Digging: `VoxelTool.mode = MODE_REMOVE; do_sphere(centre, 3)` under the player: voxel -1.19 -> +2.81, the player falls 3.3 m into the hole and stands on its floor again (3 s later).
  Edits live in memory (no stream / save here). Not done: building, collision cost of many edits, digging at coarse LODs, saving.

## Verification round (2026-11-08)
All on the walking test (`voxel_walk.tscn`), Earth size, seed 1337, spawn on land (191 m), the custom double + voxel engine.
- Thread safety of `PlanetNoise.heights_of`: 400 jobs on 8 worker threads over 8 sets of 600 directions, compared with the single-thread answer: 0 differences (also a repeat
  call equal). Evidence, not a proof; the generator runs without a mutex.
- Seams / holes (`--seam-check`: 40,401 physics rays, 3 m apart over 600 m x 600 m, from 200 m above): with `lattice` 2 everywhere ONE ray found no ground, at 103 m from the player;
  a probe with rays 0.1 m apart showed a real hole of about 0.7 m x 1.8 m in the collision. With exact heights (`lattice` 1) there were 0 misses and 0 hits off by >0.5 m; with exact
  heights for the two finest LODs only (`exact_lods` 1, the default now): 0 misses, 11 hits off by >0.5 m (worst 0.66 m at the far grid edge, coarse LOD). Cost: load 47 s
  (26 s with lattice 2 everywhere, 122 s exact everywhere). So the coarse lattice made the hole; it is not a Transvoxel problem.
- Long walk with jumps (`--secs=300 --jump`): 1393 m, never below the noise's ground (lowest -0.01 m), memory flat 286 -> 296 MB, one 140 ms frame at the spawn and none after, the
  voxel task backlog 29-153 while walking and 0 at the end.
- Fast flight (`--fly=100`, free mode, 30 km in 100 s): the generator cannot keep up (4,703 tasks queued at 60 s) so far terrain pops in late; memory stayed flat (286 -> 249 MB).
  (The 461 m "below ground" is the free-flying player passing through a ridge, free mode has no collision: meaningless.) A vehicle or fast flight needs a faster generator.
- Digging at scale (`--dig-many`, 200 spheres of 3 m within 60 m): 3.6 s of calls on the main thread (18 ms each, worst call 200 ms), two frames of ~140 ms; the player kept standing.
- Whole project on the custom engine: `planet_lab.tscn -- --planet-check` (headless, the heightmap planet) -> `PLANET_CHECK PASS steps=40 walked=2372 m rebases=39 tiles=333`.
  So the voxel module and the rebuilt double `planet_crust` library do not break the existing planet.
- Not verified: foot IK on slopes (looked fine in pictures only), swimming / sea, the full game scene, export (see below), macOS (task 097).

## Export template for the voxel engine (2026-11-08)
- Built `scons platform=windows target=template_release precision=double arch=x86_64 d3d12=yes debug_symbols=no` in `E:\Godot\double\src` (the voxel module is in the tree):
  12 min, OK -> `bin\godot.windows.template_release.double.x86_64.exe` (+ console exe). Only the release template; no debug template, no other platforms.
- Real export: the scratch project `E:\Temp\claude\voxel_spike\proj_module` (the Earth-size noise planet, no GDExtension) with an `export_presets.cfg` whose
  `custom_template/release` points at that template, `editor.exe --headless --path proj_module --export-release "Windows Desktop"` -> a single 84 MB `planet.exe`
  (embedded pck). Running the EXPORTED exe (`-- --radius=6371000 --lods=12 --view=4096 --caves=1 --secs=10 --ball=1`): the voxel planet loads, the ball lands and rolls, 690 draw
  calls, 2.64M triangles, 402 MB video memory. So a shippable double + voxel build is possible.
- NOT done: exporting the real game (it needs `planet_crust` as a double RELEASE library: `windows.release.double` in `planet_crust.gdextension` points at
  `planet_crust.windows.template_release.double.x86_64.dll`, never built: `scripts/build_native.sh --double --release` is untried), a debug template, size of the full game.
