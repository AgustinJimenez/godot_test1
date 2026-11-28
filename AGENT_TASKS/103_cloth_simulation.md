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

## Garment recipes, plan 1 done (2026-11-26)

Plan `docs/superpowers/plans/2026-11-26-garment-recipes-1-builder.md` (executed inline; ledger in `.superpowers/sdd/2026-11-26-garment-recipes-1-builder/`).
- Garments are recipes (`assets/models/humans/garments/*.json`), outfits lists of them (`assets/models/humans/outfits/*.json`), materials and their
  shader look in `garments/materials.json`, the sliders' strongest shapes in `assets/models/humans/body_shapes.json`.
- `tools/blender/build_outfit.py` (rules in `tools/blender/garments/fit.py`, the freedom rule in `freedom.py`) replaces `make_clothes.py`; it
  writes `<gender>_<outfit>_<garment>.glb`. `tools/blender/garment_check.py` gates a build (layer gap in every body shape at the sliders'
  strongest, folds under a hem, the openings, the neckline). The labs load any outfit; `tests/manual/humans/cloth_setup.gd` sets every solver from
  its garment (no shirt / trousers special cases left).
- Found and fixed on the way: in the slider shapes (heavy, muscle at 2x) the shirt sat up to 12 mm inside the trousers (the layer push now runs in
  every body shape); the rolled lips were wound at random (wrong normals; they also made most of the "fold" area: now 1.9 / 4.8 cm2 male / female);
  a garment hanging over the hips is placed out from the body's middle whether or not there is a layer under it.
- Results: waist overlap during the wiggle and fast turns at most 1 point, under 0.5 mm (before: 3 points, 10 mm); calves 0 inside, closest
  6.5-6.9 mm; every check passes but the elbow motion checks (male f90 0/4, male f150 7/8, female f150 2/0 at -1.1 mm: within task 103's range).
- Next plans, in order: 2. task 104's contact fix; 3. drape (skirts, long coats), exact contact on legs and torso, near / middle / far distances;
  4. leather and new garments; 5. steel.

## Weave, wrinkles, no patches (2026-11-27)

- Patches removed (user: "no 'patches'"); stains, holes, wear and frayed hems stay.
- The weave (user asked for SPOM like a photo of a basket weave): a plain-weave height field (`weave_at`: round threads, uneven width,
  wander, twist, two-tone yarn), lit through a cotangent frame (follows the simulated cloth), gaps and the threads' shade averaged in at a
  distance (no shimmer), and up close (a thread over ~7 pixels) parallax occlusion along the view ray plus the threads' shadows toward the sun
  (`sun_dir_world`, set by both labs from their sun). Every number is a shader parameter (`gap_shade`, `thread_roundness`, `thread_shadow`,
  `thread_width`, `thread_width_spread`, `thread_wander`, `yarn_twist`, `fibre_scale`, `yarn_mix`, `weave_bump`, `pom_depth`, `pom_steps`,
  `pom_shadow_steps`, `pom_near`), settable per material in `materials.json` "look". The screen derivatives are taken before any branch
  (inside the per-plane loop they were undefined: dashed lines along the triangles and a blown-out picture).
- Bend wrinkles: creases round the limb at the elbows and knees (wandering, deepest on the inside of the bend, a share kept at rest,
  darker valleys), from the joints, the limbs' directions and how bent they are (`ClothSetup.limb_bend`); the body lab from its rest pose, the
  rig lab every frame of the walk onto the solvers' materials. Parameters: `wrinkles`, `wrinkle_rest`, `wrinkles_per_metre`, `wrinkle_reach`,
  `wrinkle_wave`, `wrinkle_shade`. (The body lab sent the joints only before an outfit's materials existed: now also after loading one.)

Next (user, going AFK: "continue with the cloth work, then shoes, then leather clothes, then metal clothes or armors"): leather peasant shoes
(reference: pointed turnshoes with a cord wrapped round the ankle), then a leather garment, then metal armour.

## Shoes, a leather jerkin, ring mail (2026-11-27, user AFK)

- Garments not simulated: a material's `"simulated": false` (shoes) makes the labs draw the static skinned mesh and give it no solver
  (`ClothSetup.is_simulated`); a material's `"shader"` picks the shader (`ClothSetup.shader_path`). The lifecycle check expects one solver per
  simulated garment and the others drawn.
- Peasant turnshoes (`garments/shoes.json`, villager outfit; recipe field `shoe`: sole, toe_point, cords). The builder puts the foot on a last
  (`fit._shape_shoe`): slices from heel to toe, each slice's width and height from the body, smoothed, never smaller than the foot; every point
  below the ankle on a rounded box cross-section (superellipse) at its own angle, relaxed over that surface (the toe gaps had landed out of order);
  past the toes a point narrowing to a close; the heel kept off the last (the cross-sections collapsed it into a hole); the top's hem follows
  the ankle; the top level (square to the shin it dipped at the instep). Then two coverage passes: every shoe point outside the foot by the
  ease, and every foot point inside the shoe's faces (the largest push per corner, at most 3 mm a round, 12 rounds with one smoothing pass
  each; more rounds and the two fought: the toes grew spikes). Measured (ray along each foot normal): 0 foot points uncovered at the toes,
  0-1 elsewhere. Two cord rings round the ankle.
- `shaders/human_leather.gdshader`: pebbled grain (cellular), soft creases, mottle, wear (scuffs at the toes and edges, dust low), sole and
  welt stitches from R as a height ramp (`fit.SOLE_RAMP`: a 0/1 mask per point came out jagged), twisted cords on B, hem stitches on garments;
  `footwear` 1 for shoes (materials.json look). It has the solver's substrate uniforms, so simulated leather works too. All values are
  parameters.
- Leather jerkin (`garments/jerkin.json`, outfit `woodsman`: trousers, shirt, jerkin, shoes): sleeveless, layer 2, a short V, to 4 cm below
  the hips. New in the builder: sleeveless armholes cut by an upright plane (`ARMHOLE_IN`, `ARMPIT_DROP`; by the skin labels the straps came out
  torn), and the cut edges smoothed along themselves instead of pinned (a loose garment's pinned edge stuck out in flaps; the villager still
  passes every check). `garment_check`: two armholes for a sleeveless top; an open neckline may sit its ease off the skin; the close points'
  places are printed.
- Ring mail (`garments/mail.json`, material `mail`, outfit `man_at_arms`: trousers, shirt, mail, shoes): elbow-length sleeves, layer 2,
  `shaders/human_mail.gdshader`: European four-in-one rings drawn on the rest place (three planes), wire profile, rows leaning, gaps dark,
  grime, rust spots, polished tops, metallic; fades to its average under ~2 px a ring. Every value a parameter.
- Open:
  - The jerkin and the mail fail the 6 mm layer gap at a few points (1-10 per shape), mostly the belly and the waist over the trousers'
    waistband, worst at the extreme shapes (muscle_high -14 to -26 mm on the male). Pushing the rolled lips out of the lower layers made it
    much worse (the nearest lower surface was often its own inward lip) and was reverted.
  - In simulation the shirt shows through the mail (the female's back near the spine, the underside of both genders' mail sleeves); static
    (`--cloth=off`) it is clean. Not the peers' resolution (16: same), not the mail's freedom (0.3, now set: same); colliding outer layers with
    the body 1 cm further out per layer made the back worse (reverted). A third simulated layer needs task 104's contact work.
  - Fixed after (user: "man at arms ... while rotating back and forth for split second, the cloth beneath clips"): the peer contact was
    unsigned (a particle pushed out to whichever side of the other garment it was on), so once a quick turn carried a shirt particle
    through the mail it was held outside. Now layered: the solver's `peer_layer` (from the recipe's layer, `ClothSetup.configure`) makes the
    contact one-sided (higher layer kept outside the nearest triangle of the lower, lower inside the higher; `_outward_winding` tells a
    proxy's outside), in both `cloth_collide_peer.glsl` and the anchor sanitizer `cloth_skin_collide_peer.glsl` (its unsigned push sent the
    shirt's anchors out through mail that had sagged onto them), at `layered_peer_thickness` 8 mm, with peer proxies at 16 cells for
    outfits with a third layer (at 8 the shirt's proxy sat ~7 mm inside it on the back's curve). Only for outfits with a layer 2
    (`connect_peers`): one-sided on the villager, the shirt sank 13 mm into the trousers at the hip on the most muscular body, so two
    layers keep the unsigned contact (every check back to its earlier numbers). In the --wiggle=15,0.3 quick turn the backs stay clean;
    small specks remain on the mail sleeves near the elbow and at the female's shoulder.
  - Then (user: "the leather cloth, i see some artifacts in the front side, and the chainmail, i still see some cloth below clipping out"):
    - Under-layers drawn in where a higher layer covers them: `ClothSetup.apply_covered` (both labs, at outfit load) marks each vertex
      of a garment covered by a higher one (a higher garment's vertex within 5 cm, its edge mask G fading it out at that garment's edges;
      the most covered point in reach, full to half the reach) in a texture by vertex index; `human_clothes` / `human_leather` draw those
      parts `covered_inset` 1 cm in (sim or static). The mail's quick turn now shows no shirt.
    - The one-sided contact only where the other garment's surface faces the particle squarely (|cos| > 0.85, was 0.5): beside a
      sleeveless jerkin's armhole the shirt's sleeve pushed the jerkin into the chest (pits).
    - Stiff materials bridge the body's hollows (material `bridge`, leather and mail): in side view, per 1.5 cm upright strip of the front and
      the back, the profile's convex envelope; points behind it move out to it (front / back judged from the body's middle line, not the
      normal, which points down in the fold under the bust), then Taubin smoothing; after the unfold pass (before it, the unfold relaxed the
      bridged points back), then outside the lower layers again. Outward-only Laplacian smoothing first: moved ~200 points, left the crease.
    - Leather freedom 0.35 -> 0.12 (in simulation the jerkin sank under the bust onto the capsules, which have no bust).
    - Leather grain: smooth noise bumps (the cellular grain's cell junctions were black dots), quintic noise (the creases' light stepped
      along the noise grid), the bump's tilt clamped.
    - Debug: `--cloth-layered=off` (unsigned contact for every outfit).
  - Fit rules for every garment (user: the groin "too adjusted", the shirt's elbow "a little bit too big"; design
    `docs/superpowers/specs/2026-11-27-crotch-and-sleeve-taper-design.md`, plan `docs/superpowers/plans/2026-11-27-crotch-and-sleeve-taper.md`):
    groin bridge (front dipped 19 / 55 mm, seat 47 / 46 mm male / female; now 0.3 / 2.0 and 3.8 / 5.2), sleeve taper (19 mm over the upper arm,
    ~15 by the cuff), recipe fields `crotch_drop`, `sleeve_taper`; lips sized at their own point. The villager passes every check.
    Open: the female mail's inward area under the hem 5.9 -> 22.7 cm2 and the jerkin's 11-12 -> 15 cm2 after the trousers' groin bridge (the
    mail's front follows the belly and its hem dips into a V at the front); tried: a gentler fade (no change), bridging those hems too (male mail
    6.6 -> 15.8, reverted). Mail: no stiff bridging (it made the hem's inward area 19-30 cm2), straight sleeves (`sleeve_taper` 1).
    A pattern sheet (each garment's flat pieces with measures) was discussed as a debugging aid and deferred.
    Then: the taper starts at 0.45 along the arm (from 0.3 the 150-degree elbow check went to 40 faces); the groin smoothing stays inside the
    bridged strip (3 cm wider reshaped the hips' sides); each body shape's movement is smoothed over the bridge (the cleft's walls came back
    under a muscle shape and the female's shirt read 3-4 mm inside the trousers in the lifecycle check); lips are sized in every body shape.
    Now: lifecycle PASS; villager garment check female PASS, male one point at 5.5 mm (6) at the waistband's side on the most muscular shape;
    elbow motion checks male f90 0/17, male f150 11/20, female f150 2/5 (before this change 0/10-14, 6/6-12, 1/2-5/9).
  - Feet tab (user: "a tab about feet, at least to modify realisticly the feet size, camera focus there when tab open"; design
    `docs/superpowers/specs/2026-11-27-feet-tab-design.md`): six foot shapes (MakeHuman targets) in make_bodies.py, every human asset rebuilt
    (rebuild_humans.sh; the Mindfront packs were in another session's scratchpad), sliders, length / EU readout (male 26.2 cm, EU 42), camera on
    the feet. humans_check --render passes but the three known elbow motion checks. Open: the shoes' toe box is lumpy in game (worst on the
    female) though the Blender build covers the foot (probe: 0-1 points uncovered) - to look at (skinning of the toe point?).
  - Shoes rebuilt with their own shape (user: "the shoe clips on the leg skin, the shoe edges looks weird, and seems wrapped on the foot
    instead of having own shape"): `garments/footwear.py` lofts a last and a collar instead of reshaping the body's foot (its toe gaps tore in
    game, each point following its toe bone); weights and shape moves averaged from 8 body points; the cords now carry skin weights (they had
    none and stayed at rest). Tried: superellipse exponent 3 (the sole's edges came through), a 1.2 cm collar flare (a brim). Left: two pin-sized
    specks from below (a sole corner, the tip), a small step where the collar meets the last at the front, a boxy heel.
    Then (user: skin poking out from the side, "like 2 objects are clipping"): last and collar fused by a voxel remesh into one surface and
    smoothed, the top cut and rolled in, the sole 4 mm under the foot, the instep in front of the ankle covered (it showed through 9 mm out as a
    dark slit), the cords thicker and on the surface. In game from the sides: one piece, no skin. Still boxy at the heel.
  - Leather with SPOM (user asked; references: two photos of distressed / pull-up leather): `human_leather.gdshader` now draws long wavy folds
    (isolines of a slow warped noise, stretched along a direction turned off the noise's grid, a fixed width in cells from the noise's slope) and a
    fine broken crackle between them (walls of a warped cellular pattern at two scales, in patches, fading along their length), paler and warm
    (`crease_tint`), over dark and pale patches (`dark_patch`, `mottle`); close up the creases have depth: parallax along the view and their own
    shadows toward the sun (`sun_dir_world`), on the three axis planes with a frame from the planes' own axes (a frame from screen derivatives is
    per triangle: the parallax jumped at every edge). Tried and replaced: round pebbles (the wrong leather; value noise made them square),
    plain cell walls (dried mud), folds stretched along the noise's grid (straight lines and rectangles), a fixed fold width in noise values
    (wide bands). Cost (GPU, 1152x648): whole body 2.8 ms (villager 2.5); leather filling the screen 9.3 ms, 5.4 without the close-up depth
    (13.7 before the folds were taken once per pixel instead of at every march step).
    Then the long folds off by default (user: "i don't think we need the big waves, just small ones"): `fold_depth` 0 skips them (and their
    cost); leather filling the screen 6.0 ms.
    Then the crease cells 3x smaller (`grain_scale` 330, user asked); and a pit on the shoes' inner side (user: "some weird 'bump'"): the inner
    ankle bone widens the collar past the last's rounded top corner, and the fused surface had a dent there; 50 outward-only smoothing passes
    after the fuse (`FILL_DENTS`) leave a soft shallow dip on the male, none on the female.
  - Bump heatmap (user: "a technique to spot irregular bumps, temp by height maybe?", then "can't you enable it in the code in the editor?",
    "more sensitivity"): body lab Body tab "Debug: bumps heatmap" / `--bumps`, `--bump-range=m` (default 1 mm full colour). Found on the shoes
    at 0.5 mm: upright stripes ~1 cm apart along the sides and the toe - the last's profile took each slice's raw foot extremes and a smoothing
    that never lowered a slice kept every jump as a ridge (more slices made it worse); now a running maximum over 3 slices each side, then 10
    smoothing passes (`PROFILE_REACH`, `PROFILE_SMOOTH`), and 52 slices x 48 points. Left: the sole edge's band (a real edge) and one single
    point ~0.5 mm proud on the male's outer side.
  - The cords (user: "on some parts it clips in the shoe ... it looks painted"): real ropes of three twisted strands (`CORD_STRANDS`,
    `CORD_LAY` 9 mm, `CORD_GROOVE` 0.3 of the radius, 12 points round, 64 along), the groove depth in G for the shader (`cord_groove_shade`);
    the path from 64 ray hits (28 let the shoe bulge between them), smoothed and pushed out until the rope's middle is `clear` off the shoe's
    surface everywhere. (Adding the groove layer to the mesh drops vertex references taken before it: created first.)
    Then 256 points along and 16 round, grooves 0.45 deep (64 along put ~2 points in a strand's turn: the twist smoothed away).
  - The shoe rebuilt to the user's 16th-century reference sheet (vamp, quarter, inside counter, welt, outsole, heel; "yeah, match it"):
    `footwear.py` lofts only the last (no collar, no wound cords), fuses and smooths it, cuts the opening below the ankle bone
    (`opening_below_ankle` 1.8 cm) from the heel to the throat (`throat` 0.5 of the foot) on two planes, rolls its edge in; a leather thong
    (`lace` radius) across the throat with a knot and two ends over the vamp (drawn as cord); a welt (3 mm out), an outsole (5 mm) and a heel
    (8 mm, the back 28% of the foot) as their own solid under the upper; the vamp's seam (G with the hem). Recipe `shoe` keys extended.
    To look at: the quarter's straight topline and boxy heel, the heel's sharp step, the lace's size.
    Heatmap of the new shoe: the sole slab read solid red (the smoothing collapses a thin, sharp-edged piece): the heatmap now leaves out a
    separate piece thinner than 2 cm in some direction (`BUMP_THIN_PIECE`: the sole slab, the lace). The upper: white at 1 mm; at 0.5 mm
    only faint bands where the side turns into the top and the sole (the shape's own corners) and two faint marks at the female's toe.
  - Laces drawn as leather with the grain's depth (they were cord: plain); AGENTS.md now says no flat painted surfaces (SPOM or geometry) and
    that every item is checked from all round and into its openings. Mail rings and the colour-only stitch lines still to do under that rule.
  - Inside the shoe from above (user: "the 'floor' is invisible, i see the grass below"): the floor was there, 2 mm under the ground, and the
    ground's grass was drawn over it. The wearer now stands on the outsole (`ClothSetup.footwear_lift`, both labs), the default sole is flat
    (`heel` 0). `--hide-body` added to look inside garments.
  - The shoe's outline from above and below was irregular (user): wavy sides, a square heel, lumps along the sole - the running maximum that
    kept the last at least the foot's size made steps and plateaus. Now a smooth upper envelope: the widths and heights smoothed (18 passes),
    then the foot's excess over it smoothed and added back 6 times (`PROFILE_SMOOTH`, `PROFILE_LIFTS`), the middle line one gentle curve (30
    passes). The female's sole now reads heel / waist / ball / point; the male a little uneven still. No skin round the forefoot in game.
    Then (user: "must not you do it this way?" - sole outline drawings; then toe shapes pointed / almond / round / square): the outline and the
    height are a designed template through a few measurements (Catmull-Rom; the nearest measurement raised until the foot is held), the middle
    a quadratic; `toe_shape` in the recipe (the villager: almond). Smooth from above and below; no skin in game.
    Then (user: "it looks deformed, like a C shape", and a sole diagram with the axis through the heel's centre, 23 mm inner / 21 mm outer at
    the ball): a straight axis from the heel's centre to the toes' tip, inner and outer widths drawn separately; four stations (six made
    waves), the curve smoothed, coverage by broad smooth swells (raising the nearest station overshot: lumps). Straight and asymmetric now;
    the male's outer edge has a slight swell left.
    Then (user: "the corners are not that smooth"): the cross-section a rounded rectangle (`_rounded_box`, ray-cast from its middle) with big
    top rounds (`TOP_ROUND` 0.6 of the smaller half-size) and small ones at the sole (`SOLE_ROUND` 6 mm, flat to its edge so the foot's sole
    edge stays covered) instead of a superellipse (a hard corner along the whole shoe); a width station right at the heel's back (measured
    over the whole back, the heel kept its full width to the end: square corners). Round heel, round toe box; heatmap clean.
    DONE 2026-11-27 (measured with a SHOE_DEBUG print, since removed): the heel circle took the widest outline value for t < 0.3, which is where
    the waist-to-ball widening already starts (heel radius 48 mm used vs 33-40 measured): `HEEL_REACH` 0.18. From below the heel is now narrower
    than the ball (male 33/40 mm, female 32/37 mm at the heel); rebuilt villager / woodsman / man_at_arms, `garment_check` shoes openings 2 on both
    bodies (the remaining FAILs are the known jerkin / mail layer gaps), shoe glbs copied and imported, looked at in game from the side and front.
    Heatmap and inside views done (below). Docs: docs/blender_workflow.md updated for the heel;  footwear paragraph (still describes Catmull-Rom + swells).
    Then (user: compare with a sole outline drawing, egg-shaped, inner waist, toe leaning in): four changes in footwear.py - the toe stations
    floored at 0.9 / 0.64 of the ball (`TOE_FLOORS`: a steady taper to a rounded tip; the foot's own last 3% is only the big toe and left a
    boxy forefoot then a spike), 5 stations (`WIDTH_STATIONS`), the toes leaning 5 degrees to the wider (inner) side (`TOE_LEAN`), the heel
    station nearer the heel. Tried and reverted: a sole width from the typical (70th percentile) near-ground width instead of the largest
    (`_fit_stations(cover=False)`): it gave the reference's deep inner waist but the foot showed through the shoe's side at the arch (the foot is
    that wide there near the ground). A real waist needs the sole narrowed under the foot with the upper covering the arch from above: not done.
    Heatmap at 0.5 mm: smooth (white), small marks only at the lace and the opening's edge; inside from above: floor drawn, no ground showing.
    Then (user: "smooth natural shape similar to any real shoe"): looked at the shoe from the side in Blender (`shoe_views.py` in the scratchpad:
    orthographic side / 3/4 / top): a slab - a dead flat topline and a vertical toe wall. Now the opening's topline is a curve (`TOPLINE`: the heel
    counter 1.6 cm higher at the back, dipping 6 mm at the ankle bones, rising a little to the throat; done by dropping every point by the curve,
    cutting on the level plane, lifting back) and the almond toe slopes down (height factor 1 - 0.88 u^1.15, toe 0.95 of `toe_point`). Rebuilt all
    three outfits, imported, garment_check shoes openings 2; in game no skin through the sides, the heel from behind reads as a shoe.
    The sole's waist, a different construction: the sole outline now follows the foot only at ground level (`SOLE_BAND` 1.2 cm, was 3) and the
    wall flares out over it to the foot's full width by 4.5 cm (`SOLE_FLARE_TOP`, was 6.5): the sole is waisted on the inner side and the upper
    covers the arch from above (a narrower band alone showed the foot through the side). In game from the inner and outer sides: no skin through
    the sides, the sole edge visible round the arch. From below the silhouette still includes the upper's overhang at the arch, so it is less
    waisted than the footprint drawing; a real shoe's sole is also less waisted than a footprint.
    Measured against the user's footprint drawing (sole outline, width / ball width by share of the length from the toe; mine from the built
    sole's underside, male): toe 0.05 0.57 vs 0.51, 0.1 0.70 / 0.66, 0.2 0.90 / 0.87, ball 0.3-0.4 0.98-1.0 / 0.98-0.99, 0.5 0.90 / 0.87,
    waist 0.6 0.78 / 0.70, 0.7 0.70 / 0.64, heel 0.8-0.9 0.61-0.59 / 0.67-0.65 (within 0.08 everywhere; the female's heel is wider, 0.73-0.87,
    her ball is narrower). `TOE_FLOORS` now 0.8 / 0.5. Tried: SOLE_BAND 0.8 cm with a narrower waist reach: the waist came out shallower
    (0.89 at 0.6), reverted. Checks after this: test_build FAIL only on the known shirt / jerkin layer gaps (shoes openings 2 on both bodies);
    cloth_check: lifecycle, normals and sleeve rest PASS, the three known elbow motion checks FAIL as before.
    Compared by eye with real low shoes (Wikimedia Commons "Turnshoes.jpg", a plain pair of turnshoes, and "Rogar, mestecko, boty.jpg", a laced
    low shoe; looked at in the browser, nothing saved): a real upper is one continuous dome over the toes with a rounded nose, not a box with a flat
    top. So: `TOP_ROUND` 0.85 (the cross-section's top corners nearly fully round, was 0.6) and the almond toe's height closes together with its width
    in a convex nose (`dome` in `_toe_shape`: (1 - u^2.2)^(1/2.2) * (1 - 0.25 u), the toe 1.15 of `toe_point` = 4 cm; a straight slope made a flat
    bevel with a square cap at the tip). In game from both sides and the front: rounded toe, no skin through the toes or sides.
    `HEEL_TO_BALL` 0.68 (the ball station at least heel / 0.68): no change for the male (heel 0.60); the female's heel-to-waist stays wide
    (0.72-0.87) because her foot is that wide near the ground (flat midfoot), the coverage drives it. Full humans_check --render after all of this:
    every check PASS (render, cloth lifecycle, native, rig, hair, sway, recipe, freedom) except the three known elbow motion checks (task 104).
    The sole's waist, done properly (a narrower sole alone showed the foot at the arch): the sole outline's waist station is pinched
    (`WAIST_PINCH` 0.86) and the wall's width at every height is at least the foot's width at that height (`NEED_HEIGHTS`: the foot measured at
    6 / 14 / 24 / 36 / 50 mm above the ground, per slice, envelope smoothed, +1.5 mm; `need_at`), so the wall bulges out over the waisted sole
    like a lasting margin. Sole outline vs the footprint drawing (male, width / ball): waist 0.60 of the length 0.70 / 0.70, 0.7 0.65 / 0.64;
    female waist 0.79 / 0.76 / 0.75 (was 0.87 / 0.84 / 0.82). In game from the inner and outer sides, both bodies: no skin through the arch.
    garment_check shoes openings 2 and villager PASS; full humans_check --render: every check PASS but the three known elbow motion checks.
    Then the sole's waist and heel as shares of the ball (`SOLE_WAIST_MAX` 0.66, `SOLE_HEEL_MAX` 0.60 on the stations; the built sole adds the
    ease and welt): measured on the built sole, waist 0.60 / 0.70 / 0.65 along: male 0.69 / 0.63, female 0.72 / 0.67 (the drawing 0.70 / 0.64),
    heel male 0.60, female 0.65-0.66 (the drawing 0.65-0.67). A small skin patch low at the female's arch (a band with no foot points filled from
    a neighbour): `NEED_HEIGHTS` finer (3 / 9 / 16 / 25 / 36 / 50 mm, +-5 mm), running maximum over 4 slices each side, +4 mm: gone, both
    bodies, inner and outer sides, from the front and above. Last full humans_check --render: PASS but the three known elbow motion checks.
    Side by side with the laced low shoe photo at the same 3/4 angle (Blender render of the built shoe, `shoe_views.py`): mine had a tall bulbous
    toe box and a high wall at the throat. Changed: toes plumper (`TOE_FLOORS` 0.9 / 0.68), toe length 0.95 of `toe_point`, height stations
    with reaches 0.04-0.08 (wide ones made a plateau; short ones a ramp), and the throat 0.62 of the foot (`throat` in shoes.json, was 0.5):
    a longer opening, a lower vamp, a lace over the ball. In game both bodies, inner and outer: no skin through; bump heatmap at 0.5 mm white
    except the rim and the topline. humans_check --render: PASS but the three known elbow motion checks.
    Measured side profile against a real side-on drawing (Wikimedia Commons "Bundschuh Uetersen Mangus Petersen 1860.png": a low laced
    shoe, 696 px long; profile = top height above the sole line / length, heel to toe; scratchpad `side_profile.py`): heel 0.25-0.28 (mine 0.25),
    the vamp by the throat 0.32-0.36 (mine 0.41-0.48 with the lace thong standing up), toe 0.23 at 0.7, 0.205 at 0.9, 0.18 at the tip (mine
    0.19, 0.25 -> 0.13, 0.08: a pointier, lower toe than that ruched ancient shoe; the laced low shoe photo's toe is lower, like mine).
    FOUND AND FIXED the tall wall at the throat: it was not the foot. Printed the height stations: with 6 stations the coverage loop raised the
    mid-foot one (0.5) to 13 cm over a foot 4-7 cm high (it raises the nearest station by each deficit, and the ankle slices' shin points sit
    next to it). `HEIGHT_STATIONS` is now a station every 10% (reach 0.05): the top follows the foot, a low toe box rising gently over the instep,
    the throat wall a few cm, not 13. Side profile now (height / length, from the toe end): 0.08, 0.11, 0.13, 0.17, 0.21, 0.28 over the instep,
    then the heel 0.25 - against the side-on drawing's 0.18 / 0.2 / 0.23 toward the toe and 0.25-0.28 at the heel. In game both bodies, both
    sides, from the front and above: low natural shoe, no skin through. The two experiments below are what I tried before finding this.
    Then the toe box deeper (`TOE_BOX_LIFT` 12 mm, faded in over 0.55-0.85 of the foot; the nose exponent 2.4 / 0.12): side profile now (height /
    length from the toe end) 0.11, 0.15, 0.17, 0.21, 0.25, 0.29 over the instep vs the side-on drawing 0.18, 0.195, 0.205, 0.23, 0.24 (within
    0.02-0.04 over the forefoot, the tip lower: a ruched toe). Plumper toe box like the laced low shoe photo. In game both bodies from both
    sides and above: no skin through; shoes openings 2; full humans_check --render PASS but the three known elbow motion checks.
    Then a tongue (the real shoes have one): a 2 mm leather flap, 5 cm long (`TONGUE_LENGTH`, recipe field `tongue`, 0 = none), lying on the
    instep behind the throat and tucked under the vamp's edge; its height from a smoothed centre line of the foot's top (the highest skin
    point within 2 cm, 6 smoothing passes) with a gentle round-over to the sides (a first version took each point's own skin height: crumpled
    and spiked). Skin weights and body-shape moves from the nearest body points like every new point (a loop variable named `j` shadowed the
    joints dict: the second foot failed). In game: no clipping seen; garment_check shoes openings 2; humans_check --render PASS but the three
    known elbow checks. Slotted lacing and a stitched welt edge are still not built (the shader draws the sole / welt stitches).
    Checked the finished shoe (male and female) from the side, both sides, 3/4, the front and above in Blender (`shoe_views.py`): a stray thin
    strip rose from the throat up the shin side - the tongue following the foot's top up toward the ankle; now its height is capped below the
    topline (`opening_z - 6 mm`) and it is 4.5 cm long: the tongue lies in the opening, no stray geometry. Rebuilt all outfits; shoes openings
    2, humans_check --render PASS but the three known elbow checks.
    `TOE_BOX_LIFT` 20 mm: side profile (height / length from the toe end, mine vs the side-on drawing) tip 0.127 / 0.184, 0.05 0.165 / 0.195,
    0.1 0.192 / 0.205, 0.2 0.235 / 0.237 (equal), 0.3 0.270 / 0.228: the forefoot within 0.013 and over the instep a little higher than that
    drawing; only the very tip lower. In game both bodies: no skin through, tongue under the lace; full humans_check --render PASS but the three
    known elbow checks.
    The toe lift fades in later (0.65-0.90 of the foot, was 0.55-0.85): over the instep 0.248 vs the drawing's 0.228 (was 0.270), 0.2 still
    equal (0.237), tip 0.127 vs 0.184, 0.1 0.192 vs 0.205.
    Nose exponent 2.7 / 0.08: tip 0.139 vs the drawing's 0.184 (2.4 gave 0.127; 3.2 gave 0.153 but a square-looking toe against the laced shoe
    photo's round one: kept the round one). Profile now: tip 0.139, 0.05 0.174, 0.1 0.192, 0.2 0.237 / 0.237, 0.3 0.248 / 0.228.
    Tried (reverted): the almond toe's length 0.95 -> 0.7 of `toe_point`: the profile matched the side-on drawing better (tip 0.156 vs 0.184,
    0.05 0.189 vs 0.195, 0.1 0.209 vs 0.205) but the toe became a squared box next to the laced shoe photo's round one. The round toe is kept:
    the side-on drawing is a ruched shoe with a blunt toe, the photo a low round one, so matching its numbers means a squarer toe than the photo.
    USER (2026-11-27, the goal cleared): "the shoes, looks bloated from the side views". The numbers chased above (a toe lift of 20 mm, room
    `sole` 7 mm over the foot, the heel counter 1.6 cm above the opening) had made the profile tall and fat. Slimmed: `TOE_BOX_LIFT` 0.004,
    shoes.json `sole` 0.003 (room over the foot, was 0.007), `TOPLINE` heel rise 0.006 / 0.008 (was 0.016 / 0.015), `opening_below_ankle` 0.026
    (was 0.018: the heel counter 8 mm lower). Side profile (height / length from the toe end) now 0.10, 0.12, 0.13, 0.17, 0.20 over the instep:
    LOWER than the side-on drawing (0.184, 0.195, 0.205, 0.237, 0.228) - the look matters more than that drawing's numbers. In game both bodies,
    both sides: sleek, no skin through. (Settings before: scratchpad `footwear_pre_slim.py`, `shoes_pre_slim.json`.)
    Feet tab debug fields (user, temporary): the bump heatmap check box, "Heatmap range" (0.1-3 mm for full colour) and "Heatmap detail" (smoothing
    passes 2-60, ~1 cm at 12; `--bump-passes=n`) - hidden unless the lab starts with `--bumps` (they live in `feet_debug` in `human_body_lab.gd`).
    USER (screenshot, a triangle of leather on the foot at the instep): the tongue. Lowering the opening (`opening_below_ankle` 0.026) put
    the foot's top above the tongue's height cap (`opening_z - 6 mm`), so the tongue lay UNDER the skin and a corner came through. The tongue is
    switched off in the recipe (`"tongue": 0.0` in shoes.json; `tongue` added to the recipe's allowed shoe keys; the code stays). A tongue
    needs its height from the skin, not a cap below the topline, and a topline that clears the instep: not worth it for now.
    Tongue re-checked in game after the cap (male outer side, 3/4 from the front, female outer side): lies under the lace at the throat, no skin
    clipping through it, nothing standing up.
    Tried: throat 0.72 of the foot and a blunter, higher nose (exponent 2.6, 0.15): the wall at the throat stayed 0.42 (it is the foot's own instep
    height + ease + sole at that point, not the lace) and only became a steeper step; the tip rose from 0.077 to 0.089. Reverted to the
    shipped values (throat 0.62, nose 2.2 / 0.25). A lower throat wall would need the vamp to slope up from the toes over the instep (a tongue
    lying on the instep), which is a different construction.
    Tried and reverted this round: letting the layer push reach 3 cm above a lower layer's top (`PUSH_ABOVE_TOP`): helped the belly points but
    the muscular male jerkin / mail got worse (23 points under 6 mm vs 3-10).
    Earlier state of this item (paused, user out of tokens; user: "let's see the shape from below" - still irregular, flat ends, heel as wide as the ball):
    - Done in footwear.py, NOT yet imported to the game (assets/ glbs are the previous "rounded corners" build; the new build is only in the
      scratchpad rebuild folder): monotone cubic (`_pchip`, `_fit_stations`, coverage by raising the nearest station) instead of Catmull-Rom +
      swells (steps/pinches); WIDTH_STATIONS 4 (heel 0.15, waist 0.42, ball 0.7, toes 0.93); the heel a true half circle of the heel's own
      width with its back far enough behind the foot to hold it (`heel_back`); the toe `(1-u^p)^(1/p)` per shape (`TOE_ROUNDNESS`); the
      sole slab built from the closed outline offset out by the welt (`SOLE_POINTS`; a lofted slab had flat ends); a sole outline from the
      foot's width near the ground (`SOLE_BAND` 3 cm, `sole_section`) with the upper flaring to full width by `SOLE_FLARE_TOP`. Removed dead
      `_superellipse`, `_line_fit`, `_quadratic_fit`, `_catmull_rom`, `_template`, LAST_ROUNDNESS, HEEL_ROUND. Builds; ends round, sides smooth.
    - Still wrong: from below the heel is about as wide as the ball (SOLE_BAND made no visible change). Next: measure why - print per-slice
      full / near-ground half-widths and fitted values (a SHOE_DEBUG print; the debug build failed only because the output folder must be a
      file path like the normal rebuild: use `$S/rebuild`). Suspects: the heel station's reach (0.05..0.25) or the coverage loop raising the
      heel station; the MPFB heel genuinely wide near the ground; `r_hi/r_lo` (max over t < 0.3). A real sole: heel ~65-70% of the ball.
    - Then: the toe still blunt for almond; rebuild woodsman/man_at_arms, garment_check (shoes openings 2), copy glbs, import, check in game
      from all angles + inside + heatmap; update docs/blender_workflow.md footwear paragraph (it still describes the Catmull-Rom + swells).
  - Layer-gap check corrected (2026-11-27): `garment_check.py` measured the gap along the nearest face's normal; where the nearest point is a
    waistband's rim and the garment's point lies to the side of it (3-8 cm away, a mostly sideways offset) that read ~0 or negative: a false
    "inside". Now `gap = d` (the plain distance) when |signed| < 0.5 d. Failures on the real outfits fell from 1-10 points per shape to 0-2 (male
    jerkin 6 points at -20 mm in muscle_low at the back middle (0.01, 0.14, 0.92); female jerkin / mail 2 points in height_short at the back
    hem (0.00, 0.10, 0.67); one mail / shirt point per outfit). Every remaining failure sits at the BACK MIDDLE of the waist / hem: the cleft
    between the buttocks, i.e. the "back hem dip" below - one cause, not many. (Diagnostic scripts in the scratchpad: layer_diag.py.)
    Tried (reverted): `_push_outside` 12 -> 40 rounds: the male mail then passes the layer gap, but the male jerkin's worst point in
    muscle_low went from -20 to -34 mm (4 points) and the female mail gained 2 points in muscle_high. The push moves points along the lower
    layer's normal, which at the back middle (the cleft) points sideways and shoves the hem into its neighbours: more rounds only move the
    problem. A real fix is structural: build the garment's back middle hem across the cleft (bridged, like the trousers' groin bridge) and
    keep stiff garments' hems out of it.
  - The back of the hem dips at the middle on the jerkin and the mail (the cleft between the buttocks); the jerkin follows the bust
    where stiff leather would bridge it.
  - Shoes: small creases near the sole at the toe; the leather grain reads a little like suede up close.
- Checks: humans_check passes (the recipe test lists the new material); cloth_check passes but the known elbow motion checks (male f90 0/10,
  male f150 6/6, female f150 5/9; they moved a little from 0/4, 7/8, 2/0).

## Working rules

One Godot game at a time; stock 4.7.2 console executable for these labs (TressFX cannot load in the custom double engine). Windowed, screen 1, no focus. Stop verification games before handoff. Preserve the user's project.godot change, stackdump and TressFX temporary DLL files.

Previous investigation and superseded tuning notes: `archive/103_cloth_simulation_investigation.md`.
