# GPU Cloth Sim upstream

- Source: https://github.com/alien-life/gpu-cloth-sim
- Commit: `bd917afd15a8389370c7e12ec9c074555834cf68`
- Plugin manifest version: `3.0.0`
- Imported: 2026-07-27
- License: MIT; see `LICENSE`

Only the `addons/godot_gpu_cloth/` package, upstream README, and license are
vendored. The large upstream demo assets are intentionally excluded.

## Local patches

- 2026-11-26 (task 103): `gpu_cloth_solver.gd` accepts any `cloth_material` whose shader declares the substrate uniforms (`_declares_substrate`),
  not only the two plugin shaders matched by path, so `shaders/human_clothes.gdshader` (same vertex hook) keeps the villager clothes' look.
