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

## Shirt over the trousers (2026-11-26, user: "the shirt, where it touch the pants, some parts are clipping")

Seen: in the body lab turn, the trousers showed through the shirt's hem at one back hip (a large patch, a ring of the belt), and specks at the
middle of the back. Two causes, both found by measurement (`--cloth-overlap` in the rig and body labs, `tests/manual/humans/cloth_overlap_probe.gd`):
- **The garments' shapes**: measured in Blender, the shirt's hem was built up to 2 cm INSIDE the trousers at the middle of the back (both bodies;
  the trousers bridge the lower back's hollow, the shirt's floor follows the body's normal). `make_clothes.py` now builds the trousers first and
  pushes every shirt point over them to at least `SHIRT_OVER_PANTS` = 12 mm outside the finished trouser surface (8 mm left specks: the trousers
  are drawn 3 mm further out than the shirt). The trousers are unchanged (byte-identical rebuild).
- **The pelvis capsule**: the add-on fits the Hips bone's capsule from the pelvis to its child with the most weighted vertices, the RIGHT thigh:
  lopsided, it pushed the glued trousers out at one hip, through the shirt (why only one side). Both labs shrink it to nothing
  (`auto_collider_bone_overrides["mixamorig_Hips"] = (0, 0.1)`); the thigh and spine capsules cover the hips.
- Result: shirt particles inside the trousers went from 12 at rest (29 stuck after a turn) to 0 at rest, 3 at ~1 mm during the turn; the big patch
  is gone. A small notch at the side of the hem stays visible at rest from behind.
- Tried and removed: a "hip band" in the shirt's native contact (the hip surface pushed 14 mm out, so the one-sided contact would keep the shirt
  outside the trousers). It changed nothing visible and made the sleeve motion checks worse (a sleeve near the hip picked the inflated hip as its
  nearest triangle). Shirt-trouser peer resolution (8 / 24 / full) and peers off also changed nothing for this.
- Sleeve motion checks after this (still RED, as before): male f90 faces inside 4 (min -2.72 mm), male f150 vertices inside 4 (min -2.02) / faces 6,
  female f90 pass, female f150 vertices 3 (min -2.26) / faces 2. At or better than the numbers recorded above.
- Body lab debug switches: `--cloth-overlap`, `--cloth-peers=off`, `--cloth-peer-res=`, `--cloth-pants-offset=`.
- Fast turns (user: "if i rotate the character back and forth too fast, i see the shirt clipping with the pant for split second"): the free hem
  swung in by more than its 12 mm clearance. `make_clothes.py` caps the shirt's cloth freedom where it covers the trousers at
  `SHIRT_OVER_PANTS_FREEDOM` = 0.3 (was up to 0.6 there). Fast half turns (`--osc=0.25`): 10 shirt points inside the trousers, 12 mm deep -> 3 / 10 mm
  (0.3) -> 1 / 6 mm (0.2). The user's own motion is a quick wiggle: `--wiggle=15,0.3` (15 degrees from side to side in 0.3 s, steady speed, turning
  back at once: right, left, right, left). The user said "better" with 0.3.

## Neckline (2026-11-26, user: "check the shoulder area where the cloth starts, is not wrapped around the neck-shoulder, i see a gap")

- The back and sides were cut by one level plane below the neck joint: across the slope of the shoulders the edge stood off the skin and left raised
  corners where it met the V (on her the cut ran far out over the shoulders). Now round: a cylinder round the neck's axis (neck to head joint),
  the neck's own radius plus `NECK_EASE` = 1 cm, stopped `NECK_DROP_BACK` below the neck joint (the axis carried down runs through the upper back
  and opened it along the spine). The neck area is triangulated first and the crossing edges split exactly on the cylinder; the split points are
  always kept (interpolated, some fell a hair inside and the edge came out ragged). The V applies only inside its width.
- Simulated, the neck band then stood up in flaps at the sides of the neck: the upper spine's capsule is lopsided like the pelvis one (Spine2 to the
  LEFT collarbone, 7.5 cm round) and pushed the glued band up. Shrunk in both labs (`auto_collider_bone_overrides`), the neck capsule kept.
- Elbow motion checks after these shirt changes (vertices / faces inside): male f90 0 / 8 (was 0 / 4), male f150 6 / 6 (4 / 6), female f150 4 / 9
  (3 / 2). With the old hem freedom (0.6) and the new neckline: 0 / 8, 5 / 6, 0 / 0. Restoring the Spine2 capsule did not bring them back. These
  counts swing with unrelated changes to the shirt; the elbow contact itself is task 104's open problem.
- Calves (user: "i did the fast small rotation again, on the back side of the lower legs, i see clipping with the leg"): measured with
  `--cloth-legs` (body lab; each trouser particle below the knee against the body's rest surface, signed along its normal). The wiggle at 15 deg /
  0.3 s: at most 2.7 mm inside (hidden by the 4 mm render offset); faster (0.15 s), thin or heavy bodies: 5.5-6.9 mm, on the back and outside of
  the calf just below the knee (the calf bulges behind the shin's round capsule; the free lower leg, 0.45-0.85, swung into it). Freedom now 0.3 at
  the knee to 0.45 at the bottom (`PANTS_KNEE_FREEDOM`, `PANTS_SHIN_FREEDOM` in make_clothes.py): no particle inside in any of those runs, the
  closest 6-8 mm outside; the walk still folds and swings. A bigger shin capsule (1.15x) did not help. The exact-surface contact the sleeves use
  would also work for the legs (~1.5-2 ms a character more).
- Elbow motion checks after this (vertices / faces inside): male f90 0 / 14, male f150 6 / 8, female f90 and f150 PASS. They keep moving with
  changes away from the arms (this one changed only the trousers).
- Seeing through the shirt from below (user: "sometimes i see the inside of the shirt from some angles and i see the other side, not the inside
  of the cloth"; the skin goal was stopped by the user at the same time):
  - The shader drew the shirt's inside only a hem's width from an opening (plus the sleeves), a workaround for the armpit overlap. Now the whole
    shirt's inside is drawn but within `ARMPIT_NO_INSIDE` = 9 cm of each armpit (vertex colour alpha; make_clothes.py).
  - The pale surface seen inside, past the hem, was a FOLD at the middle of the lower back (found by drawing back faces red with nothing discarded:
    it stayed, so it faced the camera). The shirt over the hips was placed, and held off the trousers, along the skin's own normals; at the top of
    the cleft between the buttocks those face each other, the points crossed over. Now placed and floored out from the body's middle line there
    (`place_dir`, `hips_axis`); an unfold pass relaxes the few triangles still folded (one at the front of the hem). The shirt's push outside the
    trousers is spread over the cloth round each point (single points moved up to 2 cm also folded). Inward-facing area of the lower shirt:
    male 29.5 -> 11.2 cm2, female 87 -> 7.3 cm2, what is left is the rolled hem lip; no shirt point closer than 6 mm to the trousers.
  - Elbow motion checks after this: male f90 0 / 7, male f150 6 / 10, female f90 and f150 PASS.
- Thickness (user asked): the cloth is one surface; every opening has a 3 mm rolled rim turned in and the shader draws the inside darker, so an
  edge reads as cloth with a thickness (real linen is ~0.5-1 mm; only edges show it).

## Next: every garment, not one shirt and one pair of trousers (decided 2026-11-26)

User: "those are basic shirt and pants, we can't have the same amount of work on every type of cloth, it must work on every cloth". Garments stay
built from the body like the shirt and trousers ("the same way you did both shirt and pants"; how far that goes is open, Blender is the fallback
for shapes it cannot make); later leather and steel armour.
Chosen approach: **garment recipes and one general builder**. A recipe says which body regions a garment covers, where it ends (hems, sleeves,
neckline), how loose it is, its material and its layer. One builder makes any recipe and builds an outfit from the bottom layer up, each garment
kept outside the ones below (the shirt-over-trousers rule, generalised). Freedom maps, the inside mask, collision regions and solver settings come
from the recipe and the material (cloth simulated; leather stiff and held close; steel plates rigid pieces on the bones, not simulated). The labs
load any list of garments instead of exactly two. The fit-to-body stage is kept separate so a hand-modelled Blender mesh can enter there later.
Not built yet: the design doc and the plan come first.

What is general already: the solver setup (flip_normals, render offset, the normals fix), the shrunk pelvis and upper-spine capsules, the clothes
shader (inside, imperfections, rim), the body-shape baking in the body lab, and make_clothes.py's welding, rolled rim, smoothing and unfold steps.
Tuned to the shirt and trousers: the freedom maps, the shirt-over-trousers clearance and freedom cap, the round neckline and V, the hip
placement, the sleeves' exact arm contact, the trousers' shin capsules, and the labs' two-piece wiring.

## Working rules

One Godot game at a time; stock 4.7.2 console executable for these labs (TressFX cannot load in the custom double engine). Windowed, screen 1, no focus. Stop verification games before handoff. Preserve the user's project.godot change, stackdump and TressFX temporary DLL files.

Previous investigation and superseded tuning notes: `archive/103_cloth_simulation_investigation.md`.
