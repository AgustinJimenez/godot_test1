# 097 - The voxel engine build on macOS (for the user to test later)

Started 2026-11-08. User: "i can test macos build later, note it as a task".

## Why
Task 096 runs the voxel planet on a custom Godot 4.7.2 DOUBLE precision engine with the godot_voxel module (v1.7) compiled in, built on Windows only
(`E:\Godot\double\src`, scons `platform=windows target=editor precision=double arch=x86_64 d3d12=yes debug_symbols=no`, the module cloned into `src/modules/voxel`).
The project also builds its native library for macOS (`native/planet_crust`, universal), so the same has to hold for the voxel engine if the voxel planet is kept.

## What to do on a Mac
1. Godot 4.7.2 source at commit `ed1daf0` (the "4.7.2-stable" bump), `godot_voxel` tag `v1.7` cloned into `modules/voxel`.
2. `scons platform=macos target=editor precision=double arch=arm64` (and x86_64 if Intel is needed); the Windows build took 14 min for the whole engine, ~5 min for the module added later.
3. The double `planet_crust` library for macOS (`scripts/build_native.sh --double`, see `native/planet_crust/README.md`): the double dylib was never built on a Mac; godot-cpp
   MASTER is needed for the double build, and it dropped `Math_PI` / `Math_TAU` (SConstruct has a fallback now, Windows-tested only).
4. Run `tests/manual/voxel/voxel_walk.tscn -- --secs=30` and `real_planet.tscn` with that editor: expect `WALK PASS` and the same heights (raycast ground 191.0 m, noise 191.2 m, seed 1337).

## Open questions
- The voxel module on macOS: Metal / MoltenVK rendering of the mesh blocks, thread count, the GDScript generator speed on Apple silicon.
- Export templates for macOS with the module (see task 096: none exist for the double build).
