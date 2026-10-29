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

## Not decided
- Which route (a / b / c). Decide after the spike with the user.

## Log
- 2026-10-29: task written. Spike run (see Spike result): the extension works on stock 4.7.2 with Jolt; planet integration and cost still open.
