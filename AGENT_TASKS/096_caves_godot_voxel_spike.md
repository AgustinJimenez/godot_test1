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

## Plan
1. Scratch project OUTSIDE this repository (do not touch this project's files or `project.godot`). Use the stock 4.7.2 exe plus the GDExtension 1.7x zip (unzip at the scratch project root).
2. Make a small flat voxel terrain with a cave (3D noise carved, or a tunnel); check it loads, shows the cave, and gives collision a character can walk into.
3. Check Jolt (set the scratch project to Jolt) and note what happens.
4. Report: what works, what does not, the install path, and the cost. This tests the plain library only, NOT the planet integration.
5. Only then decide the integration route: (a) voxel terrain for caves only, entered through meshes on the heightmap planet; (b) caves as separate
   scenes loaded at entrances (no library, placed by hand); (c) full voxel planet (large change, only if the spike shows spherical support); (d) our own small C++ voxel/marching-cubes GDExtension for caves only.

## Not decided
- Which route (a / b / c). Decide after the spike with the user.

## Log
- 2026-10-29: task written. Nothing tested yet.
