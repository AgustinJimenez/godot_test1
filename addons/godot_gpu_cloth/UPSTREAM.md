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
- `auto_collider_bone_overrides` selects a radius percentile/scale per bone: small torso capsules avoid puffing out the waist, full shin capsules keep the calves inside the trousers.
- `cloth_output.glsl` normalizes area-weighted normals after scaling by their largest component. The upstream `dot(normal, normal) > 1e-8` test replaced valid normals on small triangles with UP, causing bright spots. True zero sums still use UP.
- Solver teardown releases valid uniform sets before their dependent buffers, checks peer sets on the render thread, and detaches output textures before freeing them. `RID.is_valid()` alone does not detect a set automatically destroyed when a peer frees its buffers.
- Optional `body_collider_preparer` / `body_collider_packer` callbacks accept packed mesh/skin/shape data and current bone poses. The human labs use native `HumanRig` methods to pack the exact arm surface with all four bone weights; no per-triangle GDScript skinning. Its outward-wound triangles enable signed nearest-surface contact (extra skinned-target binding, 32-byte push constants). This native path restores contact after fishing/peer constraints; the original proxy path retains its two-sided contact mode.
