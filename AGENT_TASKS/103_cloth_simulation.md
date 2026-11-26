# Task 103: simulated clothes for the parametric humans

Goal: the villager shirt and trousers should hang, fold and swing with the character. Use the vendored GPU Cloth Sim add-on, not a new solver. The user wants loose, open sleeves.

## Current state (2026-11-26)

- The body lab simulates by default (Simulate checkbox, `--cloth=off` for static clothes). The rig lab uses `--cloth` with `--pose=walk` or `--sweep=40`.
- A hidden rig follows the body sliders in the body lab. Garment and collider blend shapes are baked into the base mesh before starting the solver; a body slider restarts it after 0.4 s of rest.
- Cloth weights are vertex colour B: shoulder seam held, smooth transition to fully simulated sleeves after 35% of the upper arm, loose lower shirt, loose legs with bound trouser cuffs. Alpha marks sleeve interiors. Open sleeves are intentional.
- Current settings: 4 iterations, 2 substeps, damping 0.985, travel 4 cm, flip_normals=true. Shirt render offset 1 mm / arm contact thickness 4 mm; trousers keep 4 mm render offset / 6 mm contact thickness. Small torso capsules (percentile 0.5, scale 0.8), full shin capsules on trousers (0.85, 1.0). Garments collide with each other.
- Sleeve contact uses the actual arm surface (2,450 male triangles), not inflated cylinders. `HumanRig.prepare_cloth_arms` selects/compacts the arm mesh, including shared elbow weights and active body shapes; `skin_cloth_arms` skins it with all four weights and packs outward-wound triangles. Both methods in `human_cloth_native.cpp` are pure array operations, callable from workers. The add-on receives them through optional prepare/pack callbacks; other users keep the original mesh path.
- The native contact shader selects the nearest body triangle once and enforces its outside, within the animated target's contact reach. The original two-sided distance shell let cloth settle inside an arm. Native body contact also runs after fishing/peer constraints, before committing the free sleeve positions. No sleeve anti-sag pins or gathered wrists.
- RTX 4090, uncapped rig lab: static clothes ~0.60 ms/frame; accurate sleeve contact ~3.4-3.5 ms/frame (~285 FPS). Native packing itself ~0.074 ms. Native contact runs once per substep after the cloth constraints (repeating it in every stretch iteration cost ~8 ms/frame and was removed). The earlier capsule approximation cost ~1.7 ms total but did not seat the sleeves. The viewport GPU timer excludes this solver's compute work; use uncapped whole-frame time.

## Review fixes

1. **Small triangles were not inherently bad normals.** `cloth_output.glsl` summed area-weighted face normals then rejected any squared magnitude <= 1e-8. Valid small triangles consequently got an UP normal. Normalize after scaling by the largest component; only a zero sum takes the fallback. An actual GPU regression reproduces the old failure and passes after the fix. Removed the human shader's camera-dependent triangle-normal workaround. No garment remesh was needed to fix this bug.
2. **Cleanup order:** freeing buffers automatically destroys uniform sets that use them. The add-on freed buffers first and later tried to free those stale sets (`RID.is_valid()` only means nonzero). Now detach output textures, release still-valid uniform sets on the render thread first, then their buffers. Repeated paired-solver teardown no longer prints invalid-resource errors.
3. **Clothing/body ownership:** switching to underwear left simulated clothes running; changing gender freed their parent while arrays still held old solvers/pieces, causing repeated script errors. `_stop_cloth()` clears simulation ownership before replacing clothes or the body, and is reused by restarts.

## Validation and entry points

- `bash scripts/cloth_check.sh`: requires Vulkan and a real GPU. Runs the actual output compute shader at several triangle-area scales (including a truly degenerate sum), then the body lab lifecycle scene. Rejects engine/script errors as well as failed assertions; bounded logs retained on failure.
- `tests/manual/humans/human_cloth_check.tscn`: both bodies, height -1/+1, simulation off/on, underwear/villager switches, and final teardown. Checks both solvers initialized and their GPU materials are active. Passed after the fixes with no engine errors.
- `scripts/humans_check.sh --render` now includes these cloth checks.
- `human_cloth_native_check.gd` covers split elbow weights, inverse binds, body shapes, outward triangle order, a worker thread, and invalid data. `cloth_sleeve_probe.tscn` reads actual GPU positions and ray-tests the visible cloth from the upper arm/forearm skin: mean <=12 mm, minimum >=-1 mm, with a required hit count. The runner checks both bodies; no raw particle dumps.
- Before mesh refinement and the new moving acceptance, full `humans_check.sh --render` PASS, followed by the optimized cloth suite PASS (both bodies, height/weight/muscle extremes, outfit/simulation switches, rest clearance). Unlimited-travel sleeve check also PASS: contact reach is an independent setting, not disabled by a zero leash. Four native libraries rebuilt (single/double, debug/release) and the pure native check passed against all four; release libraries were loaded through a matching editor engine in an isolated scratch project.
- User approved sleeve-only refinement; both shirts now have arm edges subdivided to 12 mm, with shape/deform layers interpolated before offsets, smoothing, masks and open rims. Torso and trousers retain their original topology. Rest checks PASS for both bodies with 100% ray coverage, about 4-5 mm mean clearance and positive minima. Lifecycle/normal checks PASS. Moving face/edge acceptance remains RED (details below): do not describe the overall moving-cloth fix as complete. User explicitly requested a progress commit and push on 2026-11-26, including the known motion failures; verification games stopped.
- Full planet suite: every check except `noise_golden` PASS. The old library saved before this task produces the identical failing hash `618220f688eb3df6a9a89ba7d9a646cb` (1,565 values); this is pre-existing, not re-baselined. Final generation-native comparison PASS (`sea_gap=0`, `light_gap=0.00000005`).
- The strict lifecycle check uses the Studio background. The Forest preview intermittently leaked one material/shader/texture array on engine shutdown even with head hair disabled; this is separate from the fixed cloth invalid-ID errors. Investigate the forest preview caches separately rather than weakening the error check.
- `scripts/check.sh` reports success, but `.venv/bin/gdlint` is an existing two-line success stub: actual lint is NOT verified. A scratch-only gdtoolkit install was attempted and stopped after repeated DNS failures; no repository dependency files were changed.
- Review captures/logs: `C:/Users/agus_/.codex/scratch/cloth_review/` (local evidence, not committed). `after_close.png` is a close rest view with the normal workaround removed.

## Remaining work

### Sleeve drape decision (user confirmed)

User confirmed: loose fabric resting on the arms, not a close fit or gathered wrists. The shared cause of the earlier sag/pin adjustments was using per-frame skin attraction to compensate for undersized arm support: it held an inflated shell instead of seating fabric. The sleeve now owns its motion beyond the shoulder seam; the actual arm surface owns contact. Round/oval support trials were removed because they either underfilled elbows or held fabric above the skin. Keep the ray-based acceptance check: nearest-rest-vertex averages alone hid real elbow clips.

The approved refinement reduces the original male frame-90 center penetration from -3.86 mm to -0.78 mm; the existing 1 mm render offset covers that. However, the new durable `cloth_sleeve_motion_check.gd` also checks edge midpoints and frame 150: male frame 90 has four samples below -1 mm (minimum -2.73 mm); frame 150 has seven free vertices inside (minimum -2.51 mm), plus face/edge failures. Female frame 90 passes; frame 150 has three vertex failures. Collider CPU/GPU pose agreement stays 0 mm. Disabling friction did not clear it and was only a scratch experiment. Replaying the same shader once on the frozen failing points projects them correctly to +4 mm. Contact is not guaranteed in the final simulation state; more density alone cannot establish that invariant. See `104_cloth_contact_design.md` for the next proposed stage requiring agreement per AGENTS.md. Keep these failing checks enabled rather than weakening their thresholds.

Rest-test correction: `Geometry3D.segment_intersects_triangle` missed small triangles with metre-scale inputs. The same ray/triangles translated around the ray origin and scaled to centimetres restores 100% coverage; the 60% coverage and clearance requirements are unchanged. Refined rig timing settles at 271 FPS / 3.69 ms whole frame (RTX 4090), versus ~3.5 ms before refinement; native packing ~0.074 ms. Scratch evidence: `refined_rest_Male.log`, `refined_rest_Female.log`, `refined_timing.log`, `refined_suite.log`, `replay.log`, `refined_preview.png`. The new suite is intentionally failing on motion, not accepted as finished.

- Shirt still follows some chest/abdomen contours. That is garment geometry; the lighting bug above is fixed. Review shape against captures before changing topology. If remeshing, preserve all blend shapes, hems and vertex masks; a voxel remesh alone will lose them.
- Rendered walking captures: female front with a turn (`female_walk.png`) and male rear (`male_walk_back.png`), frame 150, no engine errors. The female shirt still follows the breasts too closely; the male cuff opens behind the lifted ankle. These frames do not establish smoothness through an entire live walk.
- Judge walking/turning live, especially behind the knees and at the waist; previous small calf poke-through was reduced by the render offset, not proven eliminated for every pose.
- Distance LOD for multiple clothed characters remains future work (static skinned clothes far away).
- User explicitly authorized committing and pushing this progress, including unfinished walking contact. This authorization does not mark the visual result accepted or approve the next contact-design stage.

## Working rules

One Godot game at a time; stock 4.7.2 console executable for these labs (TressFX cannot load in the custom double engine). Windowed, screen 1, no focus. Stop verification games before handoff. Preserve the user's project.godot change, stackdump and TressFX temporary DLL files.

Previous investigation and superseded tuning notes: `archive/103_cloth_simulation_investigation.md`.
