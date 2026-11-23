# Task 102: parametric humans (Blender/MPFB to Godot): bodies, sliders, base underwear

Goal (user, 2026-11-21): keep the game procedural, so human characters are generated from parameters the player picks (gender, height,
weight, muscle, later more), not hand-made one by one. First spike: two base bodies in a Godot scene with sliders. Detail for the
tools and the Blender setup is in `docs/blender_workflow.md` (read it first; this file is the handoff).

Rules: nothing committed yet (the user has not confirmed); one Godot lab window at a time, close my earlier ones first (memory
close-old-godot-windows), launch on the second monitor in the background (`--screen 1 --windowed`); keep generator scripts in
`tools/blender/` (a PC crash once wiped the scratchpad); stage explicit paths only.

## Design (agreed in chat)

Bake in Blender, blend in Godot. Blender and MPFB cannot run inside the game, so a headless Blender run (once, offline) exports each
base body with blend shapes (a stored "move every vertex by this" shape); in Godot the sliders only set shape weights, nothing is rebuilt.
Rejected: a hand-written parametric mesh (slower, worse than MakeHuman's data). Skin, eyes and hair should also be procedural in Godot.

## State (2026-11-21)

Working and checked by screenshots (not by hand-dragging the sliders):
- Blender 5.3 + MPFB 2 installed headless (`--online-mode` needed; the addon entry must exist before enabling, see the docs).
- `tools/blender/make_bodies.py`: per gender, MPFB human at the macro extremes, vertex deltas stored as shape keys, helper geometry cut
  (13,380 vertices), exported to `assets/models/humans/{male,female}_body.glb`. Six shapes: `height_short/tall`, `weight_light/heavy`,
  `muscle_low/high`. Male 1.75 m, female 1.61 m; `height_tall` adds 0.70 m, `height_short` removes 0.36 m.
- `tools/blender/make_underwear.py`: briefs (both) + bandeau (female) cut from the body's own faces by flat planes, 4 mm out along the
  normal, same shapes as the body so it follows every slider. Bakes waistband/hem masks into the vertex colour (currently unused).
- `shaders/human_underwear_fabric.gdshader`: plain single-colour knit cotton (model-space triplanar weave, faint bump, light sheen that
  fades by pixel footprint). The user wants it very basic: no dark waistband line, no stitching.
- Lab `tests/manual/humans/human_body_lab.tscn/.gd`: Female/Male buttons, Height/Weight/Muscle sliders, right-drag turn, wheel zoom,
  underwear always on (the user removed the toggle). Capture flags: `-- --capture=<png> --gender= --height= --weight= --muscle= --close`.
- Slider mapping (lab constants): height -1..1 maps to 0.6 of a full shape; weight heavy x3.0, light x1.25; muscle high x2.0, low x1.25.
  Pushing a light shape to x3 folded the female waist/hips, so light stays near its designed range. Extremes of weight and muscle were
  checked on both bodies at slider -1 and +1: clean, cloth follows. The bandeau is slightly rumpled at high muscle (cloth copies bumps).

- Eyes (done 2026-11-21): `tools/blender/make_eyes.py` -> `{male,female}_eyes.glb` (two spheres following all six shapes via the saved eye landmarks), `shaders/human_eye.gdshader` (procedural iris/pupil/sclera, colour and pupil size are parameters), lab eye colour picker + pupil slider. Checked on both bodies at several colours and at height -1/+1. Brows, lashes, hair not started.
- Eye controls added (2026-11-21): per-eye colour, iris size, pupil, sclera tint, veins (lab UI + shader parameters; see docs). Veins/sclera effects are subtle because the lids hide the eye.
- Brows and lashes (2026-11-21, second version): real hair strips (320 per brow, curled tapered lashes), `tools/blender/make_face_hair.py`, `shaders/human_face_hair.gdshader`, lab colour picker + brow density + Face close-up toggle. Checked close up and far on both bodies. Known: faint dotted outer-corner lashes, one long thin tail hair on the left brow. Head hair not started.
- Head hair (2026-11-21, NATIVE C++): `HumanHair` in `native/planet_crust` (see docs/blender_workflow.md), `shaders/human_hair.gdshader` (Kajiya-Kay two-highlight lighting, wind + head-inertia sway in the vertex stage, root darkening), lab presets/sliders/Wind/Shake, check `tests/manual/humans/human_hair_check.gd` PASS. DRAPES over the head now (rewritten 2026-11-21 after the user said it stayed straight and did not fall over the head): strands start along the scalp, gravity bends them each step, the head holds them up, a neck column keeps back hair behind the neck. Long hair, bob and the short cut look right from front, side, top and back. The "beard" under the chin was a scalp-detection bug (head centre pulled forward by the face, roots below the hairline, jaw underside), fixed. Earlier: long hair with a parting looks best; the Short preset is a short back and sides (side_trim) with a swept top. Motion: `components/hair_sway.gd` (HairSway) swings the hair from a character's movement and turning (verified in the lab only; no real character uses these humans yet). Dyed ends added (tip colour/amount); side and back views checked (the "bald patch" from behind is the ear showing through a short back and sides). Curly now has real coils (helix around each strand, radius scales with curl and length). Highlight streaks fixed (tinted, clamped, shine 0.4). Release + single + double (debug and release) libraries built without errors 2026-11-21 (double build not yet loaded in the double engine); any later C++ edit needs the rebuild again. Open: grey cap showing over the ear, a few flyaways, hair does not collide with clothing/shoulders beyond a nearest-vertex push, no LOD. Only the single debug DLL was rebuilt; release + `--double` libraries still to rebuild.
- KNOWN ISSUE found while checking eyes: weight +1 and muscle +1 together (gains x3 and x2) make the male shoulders lumpy/faceted. Single extremes were clean; combined extremes need a cap on the summed shape weights.

## Not done / next

- Height extremes and all three sliders at their extremes together: not checked. A real hand-drag of the sliders: not done.
- Rig: the bodies have none, so no animation, Foot IK or retargeting yet. Next big step: a rig that follows the height (check
  `HumanoidRetargeter`, the Character Editor and `docs/asset_budgets.md` first so there is one body system, not two; the mesh is 13k
  vertices, may be heavy for crowds).
- More sliders (age, proportions, race, face) and procedural skin (tone, age, freckles; the Blender skin prototype is only a start and its
  nodes do not export). Eyes, brows, lashes and head hair exist (see State); the skin in the lab is a plain Godot material.
- Licence: MakeHuman targets are said to be CC0 and the addon code GPL; confirm before shipping (nothing but the data is shipped).
- Official Blender Lab MCP (needs Blender 5.1+, GUI-installed add-on): its page returned 403, not read, not installed. 6xvl/blender-skill
  has useful notes but its bridge has telemetry on by default (`DISABLE_TELEMETRY=1`); nothing from either is installed.
- Commit: the untracked files are `assets/models/humans/` (glb + .import), `tests/manual/humans/`, `tools/blender/`,
  `shaders/human_underwear_fabric.gdshader(.uid)`, `docs/blender_workflow.md`, this file, and the `AGENTS.md` pointer line.
  Wait for the user's go-ahead. `bash.exe.stackdump` in the root is a stray crash dump, not ours.

## Earlier item (DONE, option B was taken): eyes, eyebrows, eyelashes, hair (user, 2026-11-21: "first hair, brows, lashes, eyes, at least we must be able to change the colour of the default ones")

Option A (preferred if the licence and download work): the MakeHuman system assets, CC0, as MPFB asset packs (MPFB's own addon ships none):
"MakeHuman system assets" (proxies, eyes, teeth), Eyebrows 01, Eyelashes 01, Hair 01/02/03 and the hair/eye material packs. Eye materials 01
and 02 are CC0 but "System eye materials 03" is CC-BY (attribution needed): avoid or credit it. Each asset is fitted to the base mesh, so for
the sliders re-fit it at every morph (the way `make_bodies.py` samples the body: `HumanService.add_mhclo_asset`) and store shape keys. In
Godot the colour must be a parameter: a shader/material colour (iris, brow, lash, hair tint), not baked into a texture.
Option B: build eyes (sphere + iris shader), brows and lashes (cards) and a hair cap in `tools/blender/` and Godot shaders ourselves; no
download, fully procedural, but hair quality is the hard part.
Source for pack names and licences: https://static.makehumancommunity.org/assets/assetpacks/index.html. Packs read (2026-11-21), zips at
`https://files2.makehumancommunity.org/asset_packs/<pack>/<pack>_cc0.zip` (files.makehumancommunity.org is the other mirror; the site said
its community services shut down 2026-10-21, so mirrors may move): `makehuman_system_assets` 267 MB CC0 (eyes blue/brown/green/grey/ice...,
teeth, tongue, proxies, hair short01-04/long01/bob01-02/ponytail01/afro01/braid01, eyebrow001-012, eyelashes01-04), `eyebrows01` 10 MB CC0,
`eyelashes01` 3 MB CC0, `hair01` 217 MB CC0, `system_hair_materials01` 82 MB CC0, `system_eye_materials01` 13 MB CC0. `hair02` and `hair03` are
CC-BY (credit needed). Whether packs can be installed without the Blender GUI (unzip into a folder) is not confirmed: the pages only describe
the "apply assets > library settings > asset packs" button; check the Asset Packs FAQ or MPFB's source.
Colour pickers per part exist in the lab (eyes, brows/lashes, hair). Option A (the MakeHuman asset packs) was not used.

## Future task items (ideas listed 2026-11-21, in the order I suggested; the user asked for them to be written down)

1. A rig that follows the body (scales with height) so the bodies animate, with Foot IK and retargeting. Check `HumanoidRetargeter`, the
   Character Editor and `docs/asset_budgets.md` first: one body system, not two.
2. (done, see State) eyes, brows, lashes, hair with changeable colours.
3. More body sliders: age (MPFB has it, most visible after weight), proportions, chest and hip size (same bake as height/weight), later face shape.
4. Procedural skin: tone, age, freckles as shader parameters; replaces the plain lab material (the Blender skin nodes do not export).
5. Procedural outer clothing cut from the body the same way as the underwear (t-shirt, trousers); loose clothing needs the existing cloth fitting.
6. A random-person button: roll every slider within sensible limits, save the result as a small recipe (foundation for NPC crowds).
7. Housekeeping: height extremes and all sliders together at their extremes; a lower-detail mesh for crowds; confirm the MakeHuman data
   licence before shipping; smooth the bandeau at high muscle; commit the work once the user says so.

## Log

- 2026-11-21: MPFB spike, body shape keys, lab, underwear (ragged hems fixed with plane cuts), fabric shader (simplified at the user's
  request), weight gain split after the female min-weight fold, muscle shapes added. A PC crash lost the scratchpad (underwear script was
  rewritten into `tools/blender/`).

## Status snapshot (2026-11-21, late)

- Done and checked by screenshots (never by hand-dragging sliders): bodies with six blend shapes, underwear, eyes, brows, lashes, procedural head hair (native `HumanHair`, drapes over the head, curls, dyed ends, wind and head sway via `components/hair_sway.gd`).
- Hair bugs found and fixed through measurement, not guessing: hair under the chin (scalp detection: head centre pulled forward by the face, roots below the hairline, jaw underside), flat plates on Buzz (ribbon wider than hair), pale streaks (highlight term).
- Builds: single debug, single release, double debug and double release libraries built without errors. The double build was not loaded in the double engine. Any later C++ edit needs the rebuild again (`GODOT_CPP_DOUBLE=E:/Godot/cpp/godot-cpp-double GODOT_API_DOUBLE=E:/Godot/cpp/dump/extension_api.json scripts/build_native.sh --release --double`).
- Review pending: an Opus 5.5 (xhigh) read-only review of all the humans work was started; its findings go here, real bugs first. The reviewed files were frozen while it ran.
- Open: grey scalp cap over the ear on short cuts, a few flyaways, jagged edge ahead of the ear, no LOD (about 55k vertices per head), no collision with clothing or shoulders beyond a nearest-vertex push, hair not used by any real character yet, skin and body textures still a plain material, head hair/brows/lashes share no colour link.
- Not committed. Untracked: `assets/models/humans/`, `tests/manual/humans/`, `tools/blender/`, `native/planet_crust/src/hair_sway_native.{h,cpp}` and `human_hair_native.{h,cpp}`, `shaders/human_*.gdshader(.uid)`, `tools/blender/landmarks/`, `scripts/humans_check.sh`, `docs/blender_workflow.md`, this file. Modified: `AGENTS.md` (one pointer line), `native/planet_crust/src/register_types.cpp`. Stage explicit paths only.

## Opus 5.5 xhigh review (2026-11-21) and what was done about it (second pass 2026-11-21: all below fixed unless marked OPEN)

Read-only review of all humans work. Fixed already (native debug DLL rebuilt, `human_hair_check.gd` PASS with new checks):
- B1 FIXED: hair blend shapes are now NORMALIZED with full positions and the base normals/tangents (zero normal/tangent deltas decoded to a backward vector and pulled every hair normal back at non-zero sliders; mesh bounds came from the offsets, so tall bodies could cull the hair). Check now asserts shape normals == base and bounds contain the `height_tall` hair.
- B2 FIXED: `human_hair.gdshader` `light()` no longer multiplies by ALBEDO (the engine multiplies diffuse light by albedo itself, so it was albedo squared). Brightness changed: shine/ambient may need re-tuning; captures were started (`s_*.png` in the scratchpad) but NOT yet looked at.
- B4 FIXED: one `Dice` per lock (`seed + lock * 0x2545F4914F6CDD1D`) so a float rounding difference cannot shift every later lock; seed read through int64; lock count computed in double and clamped; index bounds validated at the start of `build`.
STILL TO DO (in priority order):
1. Re-look at the hair after B2 (captures `s_male_short`, `s_female_long`, `s_male_tall_heavy`, `s_female_blond_bob`), re-tune `shine`; check tall/heavy for the normals fix.
2. B3: `build()` reads the body through `surface_get_arrays`/`surface_get_blend_shape_arrays`, which stall the GPU and are not worker-thread safe; read the body once into packed arrays per gender, cache them, pass arrays in, build the ArrayMesh on the main thread; use `ptr()`/`std::vector` in the loops; measure build time (docs claim "a few ms", unmeasured; Buzz is ~68k vertices, Curly ~94k).
3. B5: hair rigidly follows ONE body vertex per lock, so it will not scale with the head at Height +-1 or follow shoulders at Weight/Muscle +1: fit a similarity transform per shape from the scalp offsets, blend toward nearby body vertex offsets; look at the hair at Height +-1 and Weight/Muscle +1. When the rig exists copy bone weights from the bound vertex (bind by position, the importer reorders vertices).
4. B6 `components/hair_sway.gd`: convert movement into the hair mesh's space (actors face -Z, hair +Z), sample in `_physics_process` or use the interpolated transform, use `instance uniform` for sway/wind. B7: eye/underwear/hair-cap shaders draw patterns in model space (will slide once skinned): store rest-pose coordinates in UV2.
5. Scalp/collision are tuned in absolute metres for two bodies: derive from eye landmarks (landmarks JSON, `eye_drop` has three different defaults), distance field instead of nearest-vertex push, neck column radius per angle; ear-rim vertices count as scalp; combing vector collapses where the normal is parallel to it (likely flyaways); cap uses full strand lighting with an arbitrary tangent (likely the grey cap over the ear): give the cap no highlight.
6. Housekeeping: commit `*_landmarks.json` (needed to re-run make_eyes/make_face_hair), remove dead code (`centre_sum`, `centre_x`, String fallback in `param`, `make()` in make_bodies.py), fix docs that disagree (blender_workflow.md says "pure", "a few ms", "curl wobbles"; make_underwear.py header; lab header says four shapes), wire `human_hair_check.gd` into a suite, `_process(delta)` -> `_delta` in the lab, replace stale sections of this file (the "bald and eyeless" line and "Current item ... Not started"), add `human_hair_native.*`, `register_types.cpp`, `hair_sway.gd` and the hair/face-hair/eye shaders to the commit list, do not stage `bash.exe.stackdump`.
- Rebuild release + double after these C++ edits: `GODOT_CPP_DOUBLE=E:/Godot/cpp/godot-cpp-double GODOT_API_DOUBLE=E:/Godot/cpp/dump/extension_api.json scripts/build_native.sh --release --double`.

### Update after the review fixes (2026-11-21, last tick)
- Shader: with the duplicate ALBEDO gone, `light()` diffuse is `LIGHT_COLOR * ATTENUATION * diffuse * 0.15` (was `/pi` with albedo squared; 0.42 was tried and was too bright, an arithmetic slip of mine). Dark brown now reads brown; blond (c8a050) still reads lemon-yellow and saturated: next, desaturate bright hair (tip lightening multiplies linear channels) and re-tune `shine`.
- Tall + heavy male (Height +1, Weight +1): hair still present and lit sensibly (blend-shape normals/bounds fix works); not yet checked at Height -1 or Muscle +1, nor close-up of the neck/shoulders (review item B5).
- All C++ edits since the last full build (NORMALIZED shapes, per-lock dice, bounds checks) are in the single debug DLL only: rebuild release + double with the command above before anything else uses them.
- Remaining list from the review is unchanged (B3 cached body arrays, B5 binding, B6/B7, scalp/collision constants, housekeeping).

## Review follow-up (2026-11-21, user: "there was a review, and bugs to fix, do that, and any godot script that was written, turn it into native cpp")

Fixed (checked by `scripts/humans_check.sh` = PASS, and by captures of both bodies at Height/Weight/Muscle extremes):
- Hair after B2: re-looked at male/female, short/long/bob/buzz, tall/short, heavy+muscle. First finding: the hair rendered WHITE in every capture, not because of B2 but because my own cap fix put a `return` in `light()` (a shader compile error); restructured with an `if`. With the shader compiling the hair is brown and the highlights are quiet at `shine` 0.4 (no re-tune needed; a very light blond is a bit saturated).
- B3 DONE: `HumanHair.prepare(body)` reads the body once into plain arrays (kept in the mesh's meta), `build_arrays(data, params)` grows the hair on any thread (the check runs it on a `Thread` and compares), `make_mesh(built)` makes the mesh on the main thread; the loops use `std::vector`. Measured on a debug build: grow 30-100 ms, make mesh 15-40 ms per rebuild (the docs claimed "a few ms": corrected).
- B5 DONE: every hair vertex follows each blend shape by a least-squares fit of the whole scalp (scale + move) plus the local residual of its root vertex (fading along the strand), and hair hanging near the neck/shoulders follows the nearest body vertex. The check asserts the scalp cap moves with the body's head in every shape (within 2 cm); captures at Height +-1 and Weight/Muscle +1 show the hair on the head.
- B6 DONE and converted to C++: `HairSway` (`hair_sway_native.{h,cpp}`, `components/hair_sway.gd` deleted): samples movement in `_physics_process`, converts into the hair mesh's own space (`forward` property: the glb faces +Z), spring in `_process`, writes the shader's `instance uniform vec3 sway` on the hair MeshInstance3D (it takes `hair`, not a material). The lab's Shake button still swings the hair (checked by capture).
- Item 5 partly: `eye_drop` has one source now (`default_params_for("male"|"female")`: 0.108 / 0.107 from the eye landmarks, asserted by the check); the combing direction no longer collapses where it is parallel to the normal; the scalp cap gets no highlight (the grey patch over the ear; look at the side view: gone in the capture).
- Item 6 DONE: landmarks committed to `tools/blender/landmarks/` (they only existed in an old scratchpad), dead code removed (`centre_sum`, `centre_x`, String key fallback, `make()` in make_bodies.py), docs corrected (`blender_workflow.md`: pure/threads, ms, curl, HairSway), lab header (six shapes), `_process(_delta)`, stale sections of this file replaced, `scripts/humans_check.sh`.
- GDScript to native: the only runtime GDScript written for the humans was `HairSway`; the lab (`human_body_lab.gd`) and the check (`human_hair_check.gd`) stay GDScript (test tools, like the planet lab).
OPEN:
- B7 (eye/underwear/hair-cap patterns drawn in model space slide once the body is skinned): needs rest-pose coordinates in a custom vertex channel; do it with the rig, when the meshes are re-exported.
- Item 5 rest: scalp/hairline constants are still absolute metres for two bodies, the neck column radius per angle, ear-rim vertices counted as scalp, distance field instead of nearest vertex, collision with clothing.
- Jagged hairline ahead of the ear, a few flyaways, no LOD, `HairSway` and `HumanHair` not used by a real character yet.
- Builds: debug double, release double, debug single, release single built by PowerShell scons (the Git Bash build script cannot start the compiler since the 2026-11-21 outage; see AGENTS.md).

## Rig (2026-11-21, user: "yes, install Blender Skills and start the rig with MPFB's rigs")

- Blender Skills (EL4CTEO, MIT, 28 skills): cloned into the scratchpad and read (names and README) but NOT installed: installing it as a Claude Code plugin is the user's command (`/plugin marketplace add EL4CTEO/blender-skills`,
  `/plugin install blender-agent-skills@blender-agent-skills`); the rig was made from MPFB's own rig files, no skill was needed yet.
- Done and checked: `tools/blender/make_rig.py` (MPFB Mixamo rig, 52 bones, refitted at all six macro extremes), `assets/models/humans/{male,female}_rigged.glb` + `_rig.json`, native `HumanRig` (setup/apply/shape_weights/load_data),
  `human_rig_check.gd` PASS (in `scripts/humans_check.sh`), `human_rig_lab` (bones inside the body at height -1/0/+1, arms up and squat deform correctly on both bodies). Details: `docs/blender_workflow.md` "Rig".
- Next: skin the underwear (copy the body weights), attach eyes/brows/lashes/hair to the head bone, retarget a Mixamo walk onto this skeleton with `HumanoidRetargeter` (names match; proportions differ), Foot IK on the rig, export filter for the JSON,
  then B7 (rest-pose coordinates for the shaders). SkinTokens (rigs arbitrary meshes) is only for creatures.

## Rig, second step (2026-11-21): clothes and head items skinned, Mixamo walk retargeted (user: "yes")

- Done and checked (`human_rig_check.gd` PASS with new asserts: the underwear has bones and weights that add up to 1 and a skin of its own under the skeleton; turning the head bone moves the rigid eyes): `HumanRig.transfer_skin /
  skin_to_bone / attach_skinned / attach_rigid`; `human_rig_lab` shows the body with underwear, eyes, brows, lashes and hair on the rig, poses (arms up, squat) and `walk` (key 4, retargeted by `HumanoidRetargeter`).
  Captures: both bodies, height -1/0/+1, heavy and muscular: the clothes deform with the body, the head items stay on the head, the walk reads as a walk.
- Known: small slits in the underwear in extreme poses at heavy weight (nearest-vertex weights); model-space shader patterns slide in poses (B7); the retargeted clip is made per skeleton shape (proportions follow Height); the hair is rigid on the
  head (long hair does not swing from the skeleton, `HairSway` only); `human_body_lab` still shows the unskinned bodies (the rig lab is the one with poses).
- Next: Foot IK on this skeleton (v2 is the only foot IK; check it accepts the Mixamo-named skeleton), put a `Player`/NPC on these humans (HumanoidActor's clip library already takes a skeleton prefix), smooth the weight transfer, B7,
  export filter for the rig JSON, commit when the user says so.

- 2026-11-21 (after the limit reset): bright hair colours are pulled toward grey by luminance in `human_hair.gdshader` (blond c8a050 now reads pale blond, not lemon; it is slightly washed, tune if wanted). Checked the female body at Height -1 with the short cut: hair sits on the scalp, nothing floating (B5 worry not seen at this extreme; Height +1 on the female, Weight/Muscle +1 close-ups and the neck/shoulders are still unchecked). Release + double rebuild for the review's C++ fixes was started (log `build_all2.log` in the scratchpad); confirm it printed "the native planet crust is ready" before relying on it.
- PARALLEL WORK DETECTED (2026-11-21 ~19:55): another session ported `HairSway` to native C++ (`native/planet_crust/src/hair_sway_native.*`, replaces `components/hair_sway.gd`, which no longer exists), added `human_rig_native.*` (HumanRig), `scripts/humans_check.sh` and a rig check, and updated the lab (`_hair_sway.hair = _hair_mesh`). Two `scripts/build_native.sh --release --double` runs were active at once (one was mine); if a library looks corrupt or a link fails, wait for all scons processes to end and run `scripts/build_native.sh --force --release --double` once. Do not edit hair_sway/rig files from the hair session without checking `git status` first. My removed `hair_space` line in the lab was for the old GDScript class.
- Hair binding at slider extremes (review item B5), looked at 2026-11-21: female Height +1 with the Buzz cut covers the scalp; female Height -1 with the short cut sits on the scalp; male Weight +1 + Muscle +1 with Long hair rests on the traps/shoulders with at most a few strands near them. No visible failure, so the binding was NOT rewritten (keep an eye on the neck/shoulder strands and Height +1 with long hair). The other session already did the review's B3 split (`prepare` / `build_arrays` / `make_mesh`, worker-thread safe) and B6 (native `HairSway`); `human_hair_check.gd` PASS prints build times: about 25-50 ms to grow plus 10-17 ms to make the mesh (docs corrected from "a few ms"). Remaining hair work: scalp/collision constants in absolute metres (derive from eye landmarks), neck column radius per angle, cap highlight (grey over the ear), flyaways where the combing vector collapses, LOD, colour link between head hair, brows and lashes.
- 2026-11-21: grey scalp cap over the ear is GONE (the other session's `cap_flag` in `human_hair.gdshader` = no strand highlight on the cap): short male front and side views show clean hair, ear fully visible, a tidy edge. Remove "grey cap over the ear" from the open list. Still open: scalp/collision constants (absolute metres), neck column per angle, flyaways where combing collapses, LOD, head hair/brow/lash colour link.

## Second review (Opus 5.5 high, 2026-11-21): findings fixed

Details in `docs/blender_workflow.md` "Second hair review". Bugs fixed: skinned hair/eyes culled at Height +-1 (custom_aabb), hair attached after setup moved twice (`HumanRig.adopt`, `setup` re-callable), curly ribbons flipped their side (side carried point to point), near-body follow lookup too small (9 cm grid), HairSway turn kick (change of turning speed, velocity held at the limit, runtime class), seed shift (dice mixes the seed), zero-length locks, locks clamp 9000, cap diffuse and UV2 rest place in the shader, stale `prepare` cache, docs. New checks: `human_sway_check.gd`, curly/seed/side_trim/custom_aabb/adopt/re-setup asserts, `scripts/humans_check.sh --render` (shader errors). All libraries rebuilt.
Still open: B7 for eyes/underwear shaders, scalp constants in absolute metres, ear-rim scalp vertices, collision with clothing, weight smoothing for the underwear transfer, Foot IK on the rig, a real character wearing these humans.


## Strand prototype (2026-11-21, user: "remove the asset pack, let's see the prototype")
- The MakeHuman pack comparison was done and the pack REMOVED (user: it looks worse than ours: solid texture shells, no individual hairs). Nothing of it is in the repo; lab matches the committed version except the strand additions below.
- Prototype: `HumanHair` param `strands` (0 = ribbons; >0 = that many single hairs per guide lock, hair-thin ribbons of `strand_width` 0.6 mm, up to 1400 guides, spread by `clump` 7 mm and nearly parallel to the guide), shader uniform `single_hairs`, lab sliders "Individual hairs per lock" / "Hair spread", capture flag `--strands=N`. Native debug DLL rebuilt (single); release + double NOT rebuilt.
- Result (screenshots, bob and short male at 8 and 12 hairs per lock): individual hairs ARE visible but it reads frizzy and dotted, not sleek; ribbons still look cleaner at this distance. Cause: a 0.6 mm ribbon is about 1 pixel wide and `ALPHA_SCISSOR_THRESHOLD` 0.45 breaks it into dots. Next: widen to ~1 mm and drop the scissor for single hairs (alpha-to-coverage / MSAA or TAA), colour variation per hair, thinner taper, then measure build time and GPU cost (about 11k-17k hairs x 22 vertices x 6 blend shapes). Decide ribbons vs strands vs hybrid (ribbons far, strands near) after that.
- STRAND PROTOTYPE RESULT (2026-11-21): with single hairs opaque across their width (shader `single_hairs`: alpha 1.0, was a soft edge + scissor that left 40% of the hair) and 4x MSAA in the lab (`get_viewport().msaa_3d = MSAA_4X` in `_ready`), the strands look like real hair: smooth individual strands, clean silhouette, bob and short male (10 hairs per lock, 0.9 mm). WITHOUT anti-aliasing hair-thin strands alias into stipple, so strand hair needs MSAA/TAA in the game's settings (check `components/graphics_settings.gd` presets). Still to do: measure build time and GPU cost (about 15k hairs x 22 vertices x 6 blend shapes), try Curly/Long/Buzz in strand mode, per-hair colour variation, LOD (ribbons far, strands near), rebuild release + double libraries. Strand edits are uncommitted.
- OPEN BUG (user, video second 3 and after): a pale patch on ONE side at the back of the head (behind the ear, mid-height), visible on Long and Bob in strand mode, seen from behind (`--yaw=170/200`). Ruled out: the under-layer (made solid and darker: no change), the back-lit glow (switched off: identical), the hairline behind the ear (lowered, `(azimuth - 1.3) / 0.9`: no visible change). It looks like skin showing through thin hair on that side only (the other side is covered), so suspect the scalp/cap triangles and roots there (asymmetric scalp mesh or the ear-rim handling, `crown` x offset from `parting`, the `from_axis > 0.6 * half_width` rule). Next: render the cap alone (hide strands) from behind to see where the cap stops, then extend roots/cap there. Also: crown tufts (a star of hairs sticking up at the top), video script `--spin` and MSAA in the lab, scroll fix in the lab panel (wheel over the panel scrolls it) are done.
- ROOT OF ONE HAIR (2026-11-21, lab `--solo` / `--solo-root`, `--hair-set=seed:N`): the single hair grown at the crown rises off the scalp in a small inverted V (a tent about 1 cm wide) before it bends down, because the start direction is `flow * 0.95 + normal * 0.15` and at the crown the combing is nearly zero (`radial` falls back to +Z). This is the likely cause of the "crown tufts" (a star of hairs sticking up at the top). Fix to try: at the crown start the hair along the scalp (normal weight ~0) and use the combing from the nearest non-crown direction; or fade the normal part to 0 after the first segment. The dome in the picture is the solid scalp layer (`single_hairs` cap), not hair.
- Crown tent fix ATTEMPT (2026-11-21): cut the normal part of the start direction (`flow * 0.95 + normal * 0.15` -> `normal * 0.04`, `human_hair_native.cpp`), rebuilt, check PASS. The single-hair root capture (seed 5, `--solo-root`) is UNCHANGED (the same small tent at the crown) and the crown tufts and the pale side patch are still visible from behind. So the start direction is NOT the cause. Next to try: dump that hair's first points (positions) from GDScript (`HumanHair.build_arrays` -> arrays) to see which step creates the V (clearance push-out, the head-ellipsoid margin, or the neck column), and whether the V is real geometry or the ribbon's side vector flipping at the first points (`side.dot(previous_side)` flip in the ribbon code).
- CROWN TUFTS FIXED for straight hair (2026-11-21): the one-hair dump (`dumphair.gd`: seed 5, Long, 1 lock, 1 hair, 7 points) showed NO V and no flipped width; the tent in the root picture was the first segment peeking over the dome. The real cause: segments were all `length / (steps - 1)` = 57 mm, a straight chord across a skull of about 9 cm radius, so hairs left the crown at once. Now segments are short at the root and longer at the tip (0.3 x the mean to 1.7 x; first segment about 16 mm, running back along the crown) in `human_hair_native.cpp`. Curly hair (`curl > 0.05`) keeps even segments: a coil bigger than the short segments flipped the ribbon (the curly check failed at 4% flips). `human_hair_check.gd` PASS. From behind, Long with `curl:0` is a smooth sheet, no star of tufts at the crown; the pale patch on the left is much fainter but still faintly there. TODO: make the root spacing work with curl (scale the coil radius by the segment length), apply to Long (curl 0.2) and the presets; rebuild release + double.
- Crown fix extended to curly hair (2026-11-21): segments are short at the root and longer at the tip for ALL hair now (the `curl > 0.05` exception is gone); the coil radius is scaled by `min(1, segment / mean segment)` so a coil never exceeds its segment (that was what flipped the ribbon). `human_hair_check.gd` PASS. Checked from behind (Long, strands 12: smooth sheet, no crown star, the pale patch on the left is now a faint soft area) and Curly from the front (a full mass of coils, still reads curly). Not yet re-checked: Bob/Short/Buzz from behind in strand mode, ribbons mode with the new spacing, release + double libraries (not rebuilt), `human_sway_check`/`human_rig_check` (the other session's checks: run `scripts/humans_check.sh` with the double engine after the double build).
- MEASURED COST of the hair (2026-11-21, standard engine, female, headless, `HumanHair.build_arrays` + `make_mesh`; memory is an estimate of the uncompressed arrays incl. six blend shapes, the engine compresses some of it):
  Long ribbons (2600 locks): 88,615 vertices, 84k triangles, grow 139 ms + mesh 16 ms, ~27 MB.
  Strands x4 (9,600 hairs): 127k vertices, 110k triangles, 144 + 23 ms, ~39 MB. x8: 253k vertices, 218k triangles, 274 + 47 ms, ~78 MB.
  x12 (28,800 hairs): 379k vertices, 326k triangles, 412 + 69 ms, ~117 MB. Bob and Short at x12 have the same vertex count (7 points per hair whatever the length): short hair costs as much as long hair in strand mode.
  So: strand mode is 4x the vertices and ~4x the memory of ribbons, and ~0.4 s to build on one thread. Fine for a hero character built on a worker thread; not for crowds. Ideas: fewer points for short hair, no blend shapes on the strands (bind to the head bone when rigged), LOD (ribbons far, strands near), a cheaper count (x6 looks about as dense under the solid layer).

## Hair simulation (2026-11-21, user: "simulation, if other games can have it, we can have it too")
- Built (native, uncommitted): `HumanHair` now exports the guide strands (`hair_guides`: 2446 guides x 7 points for the Long preset at strands mode, `hair_guide_count`, `hair_guide_steps`), colliders (`hair_colliders`: capsules ax ay az bx by bz r in the body's space: head sphere r 8.5 cm, neck, shoulders) as metadata of the hair ArrayMesh, and puts `CUSTOM0` (guide id, point along it) on every vertex (mesh flag `ARRAY_CUSTOM_RGBA_FLOAT`, array not in blend shapes). New node `HairSim` (`native/planet_crust/src/hair_sim_native.{h,cpp}`, registered runtime-only): world-space Verlet per guide (pinned root following the hair mesh's transform, gravity, damping, even-link constraints x4, soft pull back to the rest place in the head's frame: `root_stiffness` / `tip_stiffness`, capsule push-out, 0.35 m safety limit), fixed 1/60 s steps, writes the offsets (mesh space) into an RGBF texture (width = points, height = guides); `human_hair.gdshader` has `sim_tex` + `use_sim` and moves each hair by `mix(texel k0, texel k1, frac)`; the old `sway` is off while `use_sim`. Lab: simulation on by default (`--nosim` off), stiffness 0.22 / 0.004, damping 0.99, `--osc=<seconds>` swings the body back and forth for videos.
- Result: no explosions in the swing videos; the fast swing trails the hair behind the head; the hair hangs over the shoulder with no obvious clipping in the frames looked at (stills only). NOT yet verified: clipping in all frames, jitter, the hair at the Weight/Muscle extremes, a walking character, the cost per frame (CPU: 2446 guides x 7 points x 4 iterations x 3 capsules per 1/60 s tick, texture upload 17k RGB floats; not measured), the double-precision build (not rebuilt), release build, wind (still the old shader wind), colliders for the arms/upper body (shoulder capsule only), that the colliders follow the rig bones (they are the rest-pose body, fixed in the mesh space), per-hair children use their guide's offset (no individual flutter), ribbon mode also uses guides (not looked at).
- Lab `--osc=<seconds per half turn>` is now a seeded random sequence of 90-180 degree turns either way with 0-0.5 s rests and ease in/out (same sequence at every speed). Body collision (margin raised 3 -> 9 mm because the cloth shell is 4 mm, the swing video now turns +-160 degrees; user: the hair clipped through her breasts in the video; only head/neck/shoulder capsules existed): `HumanHair` now also puts the body surface (vertices + normals from the head down to 0.75 m under the top, `hair_surface_points`/`hair_surface_normals`) in the mesh metadata; `HairSim` hashes it (4 cm cells, local space) and pushes every hair point out along the nearest vertex's normal (margin 3 mm), in each iteration and as a final two passes after the displacement limit. `HairSim.surface_collision` (bool, default on) and `get_penetration_count()` (points deeper than 2 mm under the nearest vertex's tangent plane). Test (scratchpad `pen.gd`, not in the repo): head swung +-80 degrees every 52 frames plus forward kicks every 40: 0 points inside with collision, 361-518 without. Limits: the surface is the rest-pose body (not the bones, not the Weight/Muscle blend shapes, not clothing: the top/bra is a 4 mm shell so hair clips through the cloth only where the cloth is thicker than the skin margin), nearest-vertex test, so a very thin or very concave part may still let a point through. All four libraries (standard/double, debug/release) rebuilt after this.
- Fixes after the user's close-up review (2026-11-22): (a) the "gap between shoulder and hair" was the rough shoulder capsule (up to 9 cm radius, bigger than the real shoulder): `HairSim.capsule_collision` is now off by default, only the body surface collides (surface gap 9 -> 6 mm; the capsules stay in the mesh metadata); (b) the pale patch behind the ear was the shine highlight, not the scalp (gone with `shine=0`): primary highlight strength 0.2 -> 0.11 and tinted 0.8 by the hair colour, secondary exponent 28 -> 60, strength 0.28 -> 0.2, per-strand highlight shift 0.35 -> 0.7 (shader defaults). Lab flag `--nopanel` hides the control panel for renders. Not looked at: other presets/colours (light hair may now show less shine than before), the loose lock lying over the right shoulder at 135 degrees (simulation lets a few hairs swing out), the pale grey streak at the left edge at 225 degrees (not looked at again after the highlight change: it was in the shine band too).
- 100k hairs (2026-11-22, user: "can we try 100k?"): `strands` cap raised 16 -> 24 (lab slider 0..24). Long preset, `locks 6000` (5,642 guides after the hairline) x `strands 18` = 101,556 hairs, 1,422,727 vertices, built in about 2 s (headless, including the load). The simulation cost does not grow with it (still 5,642 guides x 7 points). GPU cost (1.4 M vertices, MSAA 4x, hair-thin ribbons) NOT measured; the swing video (random turns, slow 3 s / fast 0.9 s per half turn) looks dense and moves as before.

### Hair simulation cost (fps readout and a faster step)
- The lab shows fps and GPU/CPU frame time (top right) and the hair count/vertices (under the height readout). `--bench=<seconds>` prints averages (after a 3 s warm-up) and quits.
- Measured before: sim on = 7-12 fps even with 7.5k hairs; `--nosim` = 60 fps. The cost was the CPU step: body-surface collision did up to 36 lookups per point per step, each 27 `unordered_map` finds.
- Fixed in `hair_sim_native.cpp`: flat counting-sort grid (one range per z row), collision only in the final 2 passes (not inside every length iteration), rest places worked out once per guide, guides split in 32 chunks on `WorkerThreadPool` (guides do not touch each other).
- After: 60 fps (vsync cap) at 7.5k, 40k-vertex ribbon and 101,682 hairs; GPU 3.1 ms at 100k. Penetration test: 0 points inside the body with collision on (718 without).

### Hair vs a real photo (side view, slicked-back taper)
- Compared the lab's side view with a real photo of a slicked-back men's cut. Fixes so far: hairline raised over the ear and a long diagonal slope behind it down to the nape (was a vertical cut with a muff of hair over the ear); solid dark scalp layer (no pale see-through patches); crown cap (no lock stands up); `sweep` parameter (0 = combed away from the crown, 1 = combed back, held on the head, pulled toward the skull) and a "Slick back" preset.
- Still different from the photo: no sideburn/temple point in front of the ear, no clumped long locks with a sheen (ours reads as many short strands), the fade from the short sides into the longer top is only a linear length ramp, the front hairline is a plain curve.
- Hairline reworked against two anatomy references (Kenhub side view, a scalp-region chart): measured the ear at azimuth 1.70..1.93 on the male body; hairline now has a temple recess, a sideburn down to mid-ear height in front of the ear (az 1.3..1.65), starts 1.1 cm over the ear top, and slopes down behind the ear (from az 1.95) to the nape. Roots taper short (25% of length) at the hairline on the sides/back.

### Hair swing tuning (measured)
- `HairSim.get_mean_tip_offset()` (metres, head frame) added for tests. Test: head turns 90 degrees in 0.3 s then stops; hair 20 cm. Peak tip offset / swings counted after the stop / time to settle within 15%:
  - old lab values (damping 0.99, tip stiffness 0.004): 6.2 cm / 1 / 0.42 s
  - damping 0.93, tip 0.03 (now in the lab): 3.9 cm / 2 / 0.33 s
  - damping 0.90, tip 0.05: 3.0 cm / 2 / 0.28 s
  - damping 0.88, tip 0.08: 2.3 cm / 2 / 0.23 s
- Real short hair should settle in about 0.3-0.6 s with 1-2 swings (to be confirmed against a reference video).
- Halved again (user: "reduce half of it"): damping 0.88, tip stiffness 0.10 is now in the lab: peak 2.1 cm / 2 swings / 0.22 s (0.85 + 0.10: 1.9 cm / 0.20 s; 0.85 + 0.14: 1.5 cm / 0.15 s).
- Halved once more: damping 0.85, tip stiffness 0.25: peak 0.94 cm, 0 swings after the stop, settles in 0.05 s (nearly rigid). Stiffer still: 0.80 + 0.40 = 0.5 cm.
- 0.85 + 0.25 looked weird (nearly rigid, no overshoot). Now in the lab: damping 0.87, tip stiffness 0.14: peak 1.6 cm, 2 swings, 0.17 s. (0.86 + 0.16: 1.4 cm, 1 swing, 0.08 s.)
- Reverted at the user's request to the original lab values (damping 0.99, tip stiffness 0.004; peak 6.2 cm, 1 swing, 0.42 s). Tried and measured stiffer values are listed above.

### More points per hair
- Tested points per hair (5/8/11/16) with the original swing values: peak tip offset 5.1/5.6/6.2/7.1 cm - more points swung slightly more, because 4 length-constraint passes hold a longer chain less firmly. Fix: the sim now runs max(iterations, points/2) passes per step. With that the swing no longer depends on the point count (11 points 6.0 cm, 14 points 6.2 cm, 16 points 6.4 cm).
- Automatic point counts raised: ribbons 7..14 (was 5..11), single-strand mode up to 9 (was 7). Cost: default ribbon hair 69k vertices (was 54k); 100,000 hairs 1.83M vertices (was 1.42M), GPU 5.0 ms (was 3.1 ms), still 60 fps.
- The swing itself is set by damping and stiffness (see above); a bending stiffness along the strand is the next idea.

### Hair weight
- `HairSim.weight` (1 = normal): gravity x weight, stiffness / weight, air loss (1 - damping) / weight, so heavy hair sags more, is harder to pull back to its style and swings longer. Lab: "Hair weight" slider (0.5-2) in the Motion tab.
- Head-turn test (original swing values, hair 20 cm): weight 0.5 / 1 / 1.5 / 2 -> peak swing 5.4 / 6.2 / 6.6 / 7.3 cm, resting sag below the style 0.9 / 2.4 / 3.9 / 5.3 cm, settle 0.50 / 0.42 / 0.37 / 0.63 s.

### Wiggle on small movements
- Measured with a 3 degree head turn (tip offset, as drawn). Before: 8-10 direction reversals over 3 s (damping 0.99 lets small swings ring), and the physics state was 4x rougher at 144 fps than at 60 (steps are 1/60 s, the picture followed each jump).
- Fixes in `hair_sim_native.cpp`: (1) friction on slow points: `calm_damping` (0.8) blends in below `calm_speed` (3 mm per step) so small wiggles die out like friction between hairs, big swings keep the normal damping (90 degree turn peak unchanged: 6.2 cm); (2) the picture is drawn between the last two steps with the head's transform from the same moment, so the motion is the same at any frame rate.
- After: 2-3 reversals, half the path length, same at 60 / 75 / 144 fps. Lab: "Friction on small movements" slider (Motion tab, 0 = none, default 0.2).

### Wind drives the simulation
- The lab's wind used to be a vertex-shader bend (no collision), so hair clipped into the head. `HairSim.wind` (Vector3, m/s2, world space) now pushes every point like gravity does, with gusts (per-guide phase) and more on the tips; divided by weight; the body collision keeps the hair out of the head (test: wind 8 m/s2 -> tips 5.6 cm out, 0 points inside the body, 2278 without collision). Lab wind slider 0..0.08 -> 0..8 m/s2; the shader wind is only used with `--nosim`.
- Weight at rest: hair that already hangs along gravity has nothing to sag, so tip offset at rest is exactly 0 for any weight/friction; they only show while the hair moves (an earlier note labelled the post-turn drift "resting sag": that was wrong).

### Bending stiffness (from TressFX's local shape constraints)
- `HairSim.bend_stiffness` (0..1): each point keeps its rest distance from the point two places back, so a hair resists kinks and keeps its shape. Alone it barely changes the whole-strand swing (90 degree turn, 20 cm hair, original damping: peak 6.2 / 6.0 / 5.9 / 5.8 cm for bend 0 / 0.25 / 0.5 / 1.0). Combined with a stiffer root (tips free) it does more: bend 1.0 with root stiffness 0.22 / 0.4 / 0.6 / 0.8 -> 5.8 / 5.2 / 4.6 / 4.2 cm.
- Lab (Hair tab, Motion section): "Bending stiffness" (default 0.5) and "Root stiffness" (default 0.22, as before). Collision still holds under wind (0 inside); 100k hairs still 60 fps.

### TressFX comparison (lab --tressfx, addons/tressfx, tests/manual/humans/tressfx_bridge.gd)
- Our guides are written as a .tfx (16 points per strand, power-spaced toward the root so the two pinned points stay short; `root_density` 2.5), 15 follow hairs, fibre radius 0.3 mm, whole strand held to the authored shape (global_range 1.0, global_stiffness 0.9); our dark scalp layer is drawn under the strands. `--tfx=name:value,...` sets any TressFXHair property (`mat_` prefix = strand material parameter; `nocollider:1`, `showours:1`, `root_density:N` are bridge options).
- Found with an overlay: TressFX draws our guides exactly (strands run along the middle of our ribbons). The short hair standing off the skull and hanging straight down is the shape of OUR guides (gravity drape from the crown), not TressFX. New HumanHair parameter `hug` (0..1): pulls the strand toward the skull like `sweep` does; lab slider "Hugs the head", Short preset 0.7.

### Hair round (2026-11-22, evening): feel, quiff, presets, hairline

- HairSim (native): added `local_stiffness` (TressFX-style local shape: each segment keeps its angle to the previous one), `air_drag`
  (quadratic drag across a strand), `strand_damping`, `max_swing` (limit on the distance from the style place, share of the strand length),
  exact strand lengths (root-to-tip pass after solving and again after the skin push, no stretching in fast turns), sleeping guides
  (a still guide stops being simulated after 0.5 s, wakes with head movement, wind, kicks or any setter), skin collision smoothed over the
  vertices within 1.4 cm in one scan (the old nearest-vertex push made strands creep: 2 collision checks per step, 58 fps while turning
  against 12 fps for the first version of the smoothing), pushes out of the skin lose their speed and sideways slide, `get_busiest_guide` and
  `get_guide_points` for tests.
- Lab: right mouse drag tilts the camera (`--pitch`), `--sim=prop:value` (any HairSim setter), `--style=key:value` (hair values after the
  preset), `--captureat=<frame>`, sliders for tip stiffness, air drag, strand damping, max swing, local shape, quiff, swept. Stiffer defaults
  (root 0.35, tip 0.25, local 0.5, bend 0.8) because the first ones moved like a liquid (slow, no spring).
- HumanHair (native): `quiff` (the front lifts off the forehead and rolls back: less gravity and skull pull near the root, a volume bulge,
  a cap of 1.2 + 3.4 cm rise) and `swept` (the front falls to the side away from the parting); hair at the very top of the head lies closer
  to the skull (volume lifts the sides, not the crown: no tuft ridge); the scalp cap's cut now follows the true hairline (signed height in
  the vertex alpha, smooth value noise in the shader) instead of stepping by triangle.
- Presets: Dapper (default, individual hairs 5 per lock, parting 0.5), Pompadour, Side part, Undercut, Crew cut, Messy crop, Wavy medium, Afro.
- UE5 source (E:\repo\UnrealEngine, study only): Niagara hair solver uses constraint-relative damping, anisotropic air drag, angular springs, a
  volume constraint on four points and velocity/pressure grids for hair-to-hair; ideas copied in words only.
- Open: sides and back of the new presets not checked, temple edge still angular on short styles, motion of the new styles untested.
- Round 2: checked the backs of Dapper, Pompadour, Undercut and Afro (covered, no holes). The shaved part of the Undercut read as a black hole; the scalp layer
  (cap) is now 1.8x brighter (hair colour x 0.56) so it reads as dark stubble.
- Round 3: motion check of the presets (lab capture at frame 400, `busiest` = guides still moving). Dapper, Pompadour and Afro had 2-3 strands that never
  stopped (up to 7 mm per step): the strands ride 3-8 mm over the skull and the simulation kept them 6 mm off it, so the pull to the style and the skin
  fought (creep). The skin margin in HairSim is now 3.5 mm: Pompadour and Afro settle completely, Dapper has one guide at 0.8 mm per step; penetration
  test still 0 points inside the body (with collision). fps with the head turning: 55-56 for Dapper, Pompadour, Wavy medium, Afro, Long.
- Round 4: sides of Pompadour, Crew cut, Messy crop, Side part checked (covered; the sideburn in front of the ear is a deep square-ish notch, the ear top has a few
  stray hairs: open). New presets: Curtains, Quiff, Fade, Shaggy (12 in all with Buzz, Short, Bob, Long, Slick back, Curly, Dapper, Pompadour, Side part,
  Undercut, Crew cut, Messy crop, Wavy medium, Afro = 16 total). Curtains and Shaggy fringes were hiding the eyes: lowered (0.55, 0.4).
- Round 5: sideburn slope is longer (azimuth 1.15..1.55 instead of 1.3..1.5, ends 1.2 cm above the old low point): the notch in front of the ear has no square corners
  any more. Fade: side_trim near 1 gives a longer gradient (3.5 cm + 4 cm x side_trim) and shorter ends; hairs down to 1.5 mm are grown (was 4 mm) so stubble
  exists at the edge of a cut. Still open: the cap under a fade is a flat dark brown (no gradient into skin colour), ear-top strays.
- Round 6: shaved areas look like stubble over skin: the builder writes how shaved each scalp vertex is (side_trim x (1 - height on the head)) in the cap's
  vertex colour green, the shader (`human_hair.gdshader`, uniform `stubble_skin`) lightens the scalp layer there and mixes in some skin with noise, where
  unshaved scalp stays as dark as before (a first try lightened all of it and the top of every style looked thin). Fade and Undercut read as clippered sides.
- Round 7 (lab window of the user was open, so no DLL build this round): natural hair colour swatches in the Hair tab (Black, Dark brown, Brown, Auburn, Ginger,
  Blonde, Platinum, Grey, White; sRGB values as the picker shows them) that also update the picker. Colours checked by capture with `--hair-colour`.
- Round 8: the stubble tint (round 6) also lit the cap behind the front hairline of styles with a lifted front (Dapper looked sparse there, the scalp showed
  through as a lighter patch): "shaved" is now multiplied by (1 - how far to the front the vertex is), so only the sides and back are clippered.
- Round 9: the stray hairs at the top of the ear came from the ear's own top-rim triangles counted as scalp: the hairline over the ear is 2 cm above the eye line (was
  1.1 cm) and the bump ends at azimuth 1.86 (was 1.93 + 0.2 slope), so the stubble/hair wraps behind the ear. A small pale bite of bare skin remains above the ear on
  the fade styles (a ~1 cm sliver); still open: the hard line between hair and clippered sides on the Fade.
- Round 10: presets Bowl cut, Side fringe (fringe lowered to 0.25: the first version hid the eyes), Bedhead; 19 presets in all. Long fringes are sparse (the scalp shows
  between the bangs): open (more locks at the front for long hair).
- Round 11: long hair with a fringe grows extra locks along the front hairline (fringe_extra = locks x (1.5 + 3 x fringe), kept only in the first 4.5 cm of the
  front hairline, thinned by the fringe amount): Bowl cut, Side fringe and Curtains have a curtain of bangs instead of a few thin locks (about 10,000 hairs, 190k
  vertices on these styles).
- Round 12: hair density back to ~100k hairs (the user had it working before; my estimate of 20 ms GPU was wrong): strands presets use 40 hairs per lock x 5 points
  (long-hair styles 32 x 6): Dapper 97,960 hairs / 588k vertices, 57 fps with the head turning, GPU 2.9 ms, build 0.44 s; Bowl cut 87k hairs / 786k vertices, GPU 3.1 ms;
  Afro 98k hairs, GPU 3.4 ms. Slider "Individual hairs per lock" now goes to 48. A preset now also resets `strands` and `points` when it does not name them (the ribbon
  styles had kept the individual-hair mode of the style before them).
- Round 13: checked the dense (~100k hairs) styles: smoother, solid masses of fine strands. Dapper showed a flat dark block of scalp layer at the front parting (the hard split
  opened a 2 cm gap and the lifted quiff left the front hairline bare). Fixes: the sideways push right at the parting line is softened (30% at the line, full from 2.2 cm
  away); the extra front locks (round 11) also grow for a quiff (front_density = max(fringe, 0.8 x quiff)): Dapper is now 105k hairs, no block. Scalp layer base colour a little
  lighter (x 0.43 of the hair colour) so the whorl at the crown does not read as a dark spot.
- Round 14: motion of the dense styles (head still, frame 420): Dapper had 4 guides flapping up to 12 mm per step (the quiff strand tips toggling between two folded
  positions: 5-point guides with big angles cannot hold local shape 0.5 + bend 0.8). 6 points per hair (was 5) fixes it (Dapper 0.6 mm, 1 guide; Pompadour 1 mm; Quiff,
  Messy crop 0); 7 points gives 0. Dapper at 106k hairs, 761k vertices: 57 fps, GPU 0.9-3 ms.
- Round 14 (user: "remove the paint you added on the head"): the solid scalp layer (cap) under the hair read as paint on the head. New shader uniform `scalp_layer` (0..1,
  multiplies the cap's alpha; 0 = the cap is not drawn) and a lab slider "Scalp layer under the hair (0 = none)", default 0. Dapper, Undercut and Bowl cut look natural
  without it (skin shows where there is no hair: the clippered sides are skin, with hair roots at the edge); a few pale specks of skin show between hairs at the part.
  The stubble tint and the shaved factor in the cap (round 6) only matter when the slider is above 0.
- Round 15: with the scalp layer off, a top view of Dapper showed slits of skin at the crown/part (the hair splays out from the whorl). Extra locks around the crown (root within 5 cm
  of the crown point, accepted 15%) fill them: Dapper is 120k hairs / 868k vertices, 59 fps with the head turning (GPU 1.5 ms); a few thin slits remain at the part line itself.
- Round 16 (user: "can we see how it looks at 150k hairs", then "i see some bald spots behind"): `strands` 50 on Dapper = 150k hairs / 868k vertices, 59 fps, GPU 1.2 ms (60 per lock =
  181k hairs, same GPU time: the vertex count is set by the guides, the hairs per lock are drawn from them); the slider goes to 64. Bald spots: with the scalp layer off, speckled slits
  of skin showed at the nape and lower back (the hair is cut short there and tapers into the hairline). Extra locks (30%) in the lowest 7 cm above the hairline at the back fill them:
  Dapper is now 160,920 hairs / 1.16M vertices, 59 fps with the head turning (GPU 1.7 ms).
- Round 17: backs of 8 presets (Pompadour, Undercut, Fade, Afro, Wavy medium, Bowl cut, Messy crop, Shaggy) checked at yaw 200: no bald spots (a few specks near the ears of Pompadour).
  A full build of the dense hair takes 0.4-0.8 s, so dragging a hair slider stalled: while a slider moves the lab now builds a preview with a sixth of the hairs per lock (min 4) and
  the full hair 0.3 s after the last move (`_hair_preview`, `_hair_last_change_ms`). Not tried by hand (no drag in the capture runs): check it when dragging Length or Volume.
- Round 18: Shaggy was long straight hair with a fringe: now length 12 cm, volume 1.7, curl 0.4, gravity 0.55, fringe 0.25. A coil needs points (6 per hair flattened every curl): Shaggy, Wavy
  medium and Afro use 10 points per hair; Afro now has clear curls (120k hairs, 1.44M vertices); wavy hair is only slightly wavy at curl 0.4. The crown of the long styles (Wavy medium) still
  shows a few slits at the part.
- Round 19: Shaggy (curl 0.6) and Wavy medium (curl 0.7) now read as tousled/wavy with 10 points per hair. Crown extra locks are densest at the whorl (4% + 30% x closeness^2). A bare
  star of skin remains at the exact whorl on the long styles when seen from above (Wavy medium, Shaggy): not explained by root density (about 40 extra locks within 1 cm); to check: whether
  the simulation or the first segment direction at the crown (flow undefined there) leaves it. Build time of dense hair (1.4-1.9 s with 10 points) is a freeze when clicking a preset.
- Round 20 (user: "from behind-below i see bald patches", "must we use 1 cm hair to see how it is covered?", "maybe shorter"): a coverage test with short hair (`--style=length:0.012,side_trim:0,
  quiff:0,swept:0,sweep:0`, also 5 mm) shows the head covered except for small clusters of skin at the crown/upper back (same spots at 12 mm, 5 mm and with `--nosim`, so it is the generation,
  not the simulation). A root map (top view, 8 mm cells, `roots.gd` in the scratchpad) shows 3-9 guides in every cell: roots are everywhere, so the gaps are not missing roots. Changes: the nape
  hairline is 2.3 cm lower (eye_y - 0.088: hair to the middle of the neck's back), a thin random fill (2% of 3 x locks draws) everywhere, triangles with one corner above the hairline count when
  their middle is above it, the sideways push of the parting fades toward the back (it split the hair along a line down the back), first point of a strand 3.5 mm above the skin and clearance
  +2 mm (the nearest-vertex plane runs under the skin in a dent). Only reduced the crown specks. Open: why the crown cluster stays (strands near the whorl may be pushed under the skin by the
  ellipsoid margin push or the first-segment direction; try drawing the roots as points, or hairs from the crown with a fixed outward direction).
- Round 21: where do the crown specks come from? A map of drawn hair vertices (top view, 6 mm cells, `cover.gd` in the scratchpad) shows more than 30 hair vertices in every cell over the head,
  and no cell where the hair's highest point is under the skin: the hair is there, but the ribbons leave pixel gaps. Wider ribbons shrink them (1.8 mm and 3.5 mm tests), so the default
  `strand_width` is 0.0014 (was 0.0009): only a few thin slits remain at the whorl in Dapper. Added a whorl to the flow: within 3.5 cm of the crown the combing direction spirals (up to 1.4 x a
  sideways component) instead of fanning straight out (no visible change in the short-hair test, kept: the top view shows a natural whorl).
- Round 22: motion check of 17 presets with the head still (frame 420, `busiest` = largest move of one guide in a step / guides still moving): Dapper 7-9 mm (12-14 guides), Fade 10 mm (9),
  Undercut 6 mm (6), Crew cut 2.4 mm (12), Bedhead 5-7 mm (1), Long 19-38 mm (1 guide), the rest under 2 mm. Dapper was 0.6 mm before the quiff extra front locks of round 14: with
  `front_density = fringe` only it is 0.9 mm (4 guides), so the extra locks that stand up add unstable strands; Fade (quiff 0.5, parting 0.35) is unstable without them. Tried and not
  working: halving a step that reverses the previous one, damping that grows with the time a strand keeps moving, easing the quiff ceiling (`headroom` scale on the rise): the first
  two removed again, the third kept (harmless). Pompadour, Quiff (parting 0 / 0.1) are stable; the unstable ones have a parting of 0.3-0.5, so the sideways split or the `part_soft` push is the
  next suspect (strands that cross the parting line). Long: one guide swings 2-4 cm per step: look at it.
- Round 23: found the cause of the strands that never settle (Dapper, Fade, Undercut, Crew cut, Bedhead): the local shape constraint at 0.5. With the head still, `--sim=` runs on Dapper:
  local_stiffness 0.3 or lower, air_drag 0.4 or iterations 8 each make it settle; bend, tip and root stiffness, strand damping and weight do not. The lab default `_hair_local` is now 0.3 (was
  0.5): Dapper, Undercut 0 guides moving, Fade 2 at 0.5 mm, Crew cut 1, Bedhead 3 at 0.8 mm. (Earlier note: the parting was a suspect; parting 0 only reduced it.) Long still has one guide that
  swings 4 cm per step: its first point is 1-3 cm from the scalp place and moves between frames, so it is not pinned (a lock grown on the neck? to check: its root is at the level of the eyes, far
  to the side).
- Round 24: (1) the "Long swings 4 cm" of round 23 was a measuring artefact: `busiest` returns a different guide every frame, so a trace that follows it mixes guides (the "root that moves"
  was two guides); followed alone, guide 1786 of Long has a 1 cm jitter at the tip only. Earlier round-22 traces had the same flaw: the per-guide numbers stand, the traces do not.
  (2) Overview of the 21 presets showed the old ribbon styles (Buzz, Short, Bob, Long, Slick back, Curly) as sparse and ragged next to the dense ones: they now use individual hairs too (Buzz 22
  hairs per lock, Short 40, Bob 32, Long 28 x 9 points, Slick back 40, Curly 36 x 10 points): 120k-165k hairs each (Buzz 155k, Curly 147k). (3) Hairline edge of single hairs: whole locks are no
  longer dropped by chance near the edge; instead the hairs per lock fall with the distance to the hairline (10% at the edge, full from 1.6 cm), and a short lock spreads its hairs less
  (clump x min(1, length / 5 cm)): Dapper has a clean edge. Buzz, Short and Fade still show separate dark blobs along the front hairline and a V of bare skin at the part (short fronts with
  a parting 0.2-0.35).
- Round 25: tried to even out the ragged front hairline of Buzz, Short and Fade (single hairs): extra thin locks along the hairline (30% of draws within 1.4 cm of it), hairs per lock at the edge
  40% (was 10%), the parting's sideways push softer at the line (50% instead of 30%). The captures hardly changed: the blobs are not a matter of density at the edge. Likely cause: front
  hair of a short style is combed back (fringe 0.35 / 0.2 lerps the front flow toward the back), so the hairs rooted at the hairline run away from it and the strip just behind the edge is covered
  by few strands; a real hairline is covered by hairs that start in front of it (growth direction forward, then falling back). To try: for the first 1.5 cm from the hairline, make the strands start
  in the forward direction (flow.z > 0 for 1-2 segments) before they turn back.
- Round 26: build time of the dense hair had grown to 1.5-2.7 s per click (HumanHair.build: `build_arrays` 1.17 s of 1.4 s for 1.2M vertices, `make_mesh` 0.24 s). The two halves were
  already separate (pure data, then the mesh), so the lab now builds on a worker thread: `HumanHair.prepare` on the main thread, `WorkerThreadPool.add_task(HumanHair.build_arrays)`,
  `HumanHair.make_mesh` when it is done (`_hair_task_id`, `_poll_hair_task`, `_finish_hair_task`). The old hair stays until the new one is ready, one build at a time (the dirty flag
  starts the next). First hair and captures wait for it. Test `--switch=Long --bench=12` (a preset change 2.5 s in): longest frame 17 ms, avg 59 fps (build 2.3 s in the background).
  (A precomputed frame per guide in the strands loop did not change the time: the cost is per vertex.)
- Round 27: the V of bare skin at the front of Short, Fade and Buzz (not a parting problem: halving the sideways push, capping it at 0.3 and making it zero at the line changed nothing) came from
  the fringe branch: `if (flow.z > 0) flow = lerp(swept_back, flow, fringe)` turned the whole forward half of the head back toward the crown, so the combing flow reversed at the crown line
  and left a hole where the two halves meet (a vertex-density map of Short showed the front-centre cells at a fifth of the density at the sides; `fringe:1` removed the hole). The flip now only
  applies at the front of the head (front_here > 0.45): the V is closed in Short/Fade/Buzz except for a thin streak at the hairline; but the flow now fans out of the real crown, and a bare patch of
  about 2 cm shows there (back of the top of the head, seen from the front and above) in Short, Fade, Buzz and a smaller one in Dapper. The swirl at the crown (round 21, now 0.15 radial + 1.6 tangent at
  the centre, radius 5 cm) did not close it: next, try roots at the crown with a fixed forward direction, or an extra ring of short locks around the crown, or cap the crown flow angle.
  Also in this round: the parting push is capped at 0.3 and scaled by the hair length (short hair splits less); it is zero at the line and full 3 cm away.
- Round 28: the bare patch at the crown (round 27) is closed: within 9 cm of the crown the flow goes back (lerp toward the along-the-scalp "back" direction, 1.4 x closeness, max 0.95), and the
  parting does nothing on hair shorter than 3 cm (`part_length_scale` = (length - 3 cm) / 10 cm, 0..1): a top view at pitch 75 of Buzz, Short, Crew cut, Dapper and Side part shows an even
  swirl-free cover. Remaining: a few specks at the back of the top of the head and a hole at the lower back (crown-to-nape, seen at pitch 75) in Side part (parting 0.55) and a thin streak in Buzz.
- Round 29: the parting push is now zero behind the crown (fades over 5 cm behind it): the back of Side part, Buzz and Pompadour (yaw 180, pitch 40) is covered, with only a few specks at the nape.
  Correction to round 28: the "hole at the lower back" of Side part seen at pitch 75 is the front (the camera looks from the front, so the bottom of the picture is the forehead): it is the
  parting V at the front hairline of Side part (parting 0.55), still open.
- Round 30: extra locks along the parting line (|x - crown.x| < 2.5 cm, 35% of the extra draws) fill the strip where the hair diverges: Side part's V is closed except a few specks;
  Undercut has a small notch at the front end of the line; Pompadour (parting 0.1, quiff 1) still has a 1.5 cm bare strip along the line (it is 216k hairs / 1.45M vertices now: the quiff extra
  front locks and these add up). Next: cap the total of extra locks, and fill the line by making the two sides' flow converge toward the line instead of away from it near the crown.
- Round 31: speed with the extra locks: Pompadour 217k hairs 59 fps (GPU 3.6 ms), Dapper 213k 58 fps (3.7 ms), Short 147k 59 fps (2.9 ms): no cap on the extra locks needed. The parting slit
  came from the sideways push at the line (with `sweep:0` Pompadour had none): the two sides now lean slightly toward each other at the line (part_soft -0.5 at the line, 0 at 6 mm, 1 from 3 cm),
  so the hair crosses over it: Dapper, Undercut and Side part are closed (a few specks), Pompadour (quiff 1, sweep 0.5) still has a 1.5 cm slit near the crown: probably the quiff ceiling / lift
  (it has `lift` only in the first 10 cm from the hairline, so the slit is just behind it): next try is a wider cross-over for quiff styles.
- Round 32: the cross-over at the parting is wider and stronger with the quiff (width 3 + 3 x quiff cm, lean -0.5 - 0.5 x quiff): Quiff and Dapper are closed, Pompadour's slit is down to about 5 mm.
  Open: Fade (side_trim 1, parting 0.35, quiff 0.5, length 7 cm) has a 1.5 cm bare patch at the crown and a streak to the front hairline.
- Round 33: Fade's patch at the crown: tried side_trim 0.5, quiff 0, parting 0, sweep 0, hug 0.2: no change; length 0.07 -> 0.10 closes it, so the preset is now 10 cm on top (the crown hairs
  of a 7 cm style, trimmed by the side/crown taper, are too short to cover the gap the flow leaves there). A generator fix would be to keep a minimum length near the crown.
- Round 34: tried the generator fix noted in round 33 (hair near the crown is never trimmed: `crown_keep`, 7 cm radius): no change for a 7 cm Fade, so the trim was not the cause; the 10 cm preset
  stays (longer hair drapes over the gap). The crown_keep rule is kept (harmless). Cause still unknown: 7 cm hair with a crown flow going back leaves a 1.5 cm hole, 10 cm closes it, so the
  strands near the crown are too short in the plane of the scalp to reach over it: try growing them longer along the first segments (a flatter start) near the crown.
- Round 35 (research pass, the user asked for open-source/docs references): searched the web; no open-source generator models whorls/partings. The Blender "Hair Tool" docs (read) place
  roots with Poisson spacing (a `Min Distance` that drops roots closer than it, and a relax step; the Stubble thesis PDF is over the fetch size limit, not read; TressFX, VHair (MIT, Unity),
  oxiphysics-softbody (Apache-2.0) and HairStrandsRendering (MIT) are the permissive references). Applied the idea: roots were drawn purely at random by area (white noise: clumps and gaps =
  the bare specks); the main locks now use dart throwing with `min_gap` = 0.7 x sqrt(scalp area / locks) (hash grid; up to 3x draws until `lock_count` are accepted; extras after).
  Result: Fade at 7 cm (no 10 cm workaround any more) has only a few specks at the crown (before: a 1.5 cm hole); Pompadour/Crew cut still have a small patch; Buzz (2.5 cm hair) is
  speckled: the hair is too short to bridge the spacing (Buzz now 40 hairs per lock: 152k hairs/1.87M vertices, 58 fps, GPU 3.2 ms, build 1.8 s).
- Round 36: after the even root spacing, the remaining bare spots are a few mm at the exact crown point (Side part, Undercut, Messy crop, Bedhead; Short/Dapper are closed). More crown extras
  (6 x locks draws, 70% extra acceptance within 1.5 cm of the crown) made the holes smaller (about 5 mm) but not gone: strands that grow out of the crown lie flat, so nothing covers the very
  point. Idea: a few short upright "cover" hairs there, or a root-less cap texture under the crown only (the old scalp layer, limited to 1.5 cm around the crown).
- Round 37 (user: "can we see the follicles?"): lab option `--follicles` / checkbox "Show follicles (hair roots), hide hair" (Hair tab): the first point of every guide strand as a cyan dot
  (MultiMesh of small spheres, 3.2 mm; hair hidden). Dapper: 6,392 follicles. The dot map shows the density is uneven: packed at the hairline and the crown (the extra locks), loose at the
  upper sides and back (where the main locks are spaced by `min_gap`) - the back and sides are the areas where each guide has to cover the most scalp with 40 hairs.
- Round 38 (user: "it must be evenly distributed, right? 150k?"): new generator parameter `extras` (1 = the extra locks of rounds 11-36 at hairline/part/crown/nape, 0 = only the
  Poisson-spaced follicles). Lab default now `extras` 0 and `locks` 4200 (about 3.7k guides x 40 hairs = 149k hairs for Dapper; 2.6k guides = 103k hairs for Fade (smaller scalp area:
  the spacing is by area); Crew cut / Buzz 5.2k guides x 32-40). The follicle map is even (no clusters). Cost: the slits come back along the parting and at the front hairline/crown (the
  extras were hiding them); a lab checkbox "Extra locks at hairline, part, crown" turns them on again (those add 30-60% more hairs). Open: close the slits by geometry instead (hair flow
  crossing at the part, hairs rooted at the hairline growing forward first).
- Round 39: with even follicles (extras 0) the hairs of a follicle within 1.8 cm of the parting line or 3 cm of the crown spread up to 2.6x wider (`radius0 = clump x (1 + 1.6 x closeness)`): Dapper
  and Bedhead are closed, Fade, Undercut, Side part and Short have only specks; Pompadour (quiff 1) keeps a 7 mm slit, Buzz/Crew cut (short hair) a few specks at the crown and the front hairline.
  Side effect: the top silhouette is a little frayed (spiky tips above the crown). Note for builds: the DLL link fails while any Godot window is open (kill the lab first, check `tasklist`).
- Round 40: (1) check at ~150k: with extras off, Dapper/Pompadour/Afro 148,960 hairs (57-59 fps while turning, GPU 2.8-4.5 ms, build 1-1.9 s), Fade 103,720 (smaller scalp area), Bowl cut 119k,
  Long 104k; Buzz was 210k because a short style's lock width (2 mm + 25% of length) multiplied the follicle count: for single hairs `lock_count` is now exactly `locks` (4200 asked, about 3.7k
  accepted by the spacing), so every 40-hair style has 148,960 hairs (Crew cut now 40 hairs too, Curly 36, Bob 32, Long 28). (2) Short hair (2-3 cm) spreads its hairs wider
  (clump x (0.8 + 0.2 x min(1, length/5 cm)) x (1 + 1.5 x max(0, 1 - length/4 cm))): Buzz, Crew cut, Short and Dapper are covered at the front and crown (a few specks at the crown) where
  before Buzz and Crew cut had a 4-5 cm bare triangle behind the front hairline. Still frayed tips at the silhouette.
- Round 41: overview of the 21 presets: the long styles (Bob, Long, Curtains, Wavy medium) had a fringe of separate strings. Long hair now spreads the hairs of a follicle wider
  (x (1 + 2.2 x clamp((length - 8 cm) / 20 cm))) and the hairs are up to 2.3x wider (strand_width x (1 + 1.3 x same ramp)), Bob and Long have 40 hairs per lock (7 and 8 points): 148,960 hairs,
  1.2M / 1.37M vertices, 58 fps with the head turning (GPU 4.3-4.4 ms, build 1.6-2.0 s). Looks like a mass of hair with a lighter fringe now; the top still has a few stiff upward strands
  (antennas) on Long and a stray fan of hairs at the sides of the head (thin lines at the silhouette).
- Round 42: the stiff upward strands on top of the long styles came from hairs spread out of their follicle's lock (the offset around the guide has an "up" component): in strands mode a hair
  point no longer rises above top_y + 8 mm + 4 mm x volume (not for a quiff: its hair is allowed to stand). Profile captures of Long, Bob, Wavy medium and Shaggy show a smooth top line.
- Round 43: colour/shine check (Dapper in near-black #1a1008 and blond #c8a060, Wavy medium ginger #8a3a14, Pompadour brown from behind): colours read correctly, the highlight is soft but visible on the
  brown/ginger, nearly none on black; the ginger is flat and very saturated (little variation between strands). No change made. Ideas: per-strand hue/brightness variation from the dye (COLOR.r
  is only brightness), a darker root zone for light colours, a stronger highlight for dark hair (`shine` per colour luminance).
- Round 44: `human_hair.gdshader`: dark hair has a stronger and whiter highlight (`dark` = 1 - smoothstep(0.05, 0.35, luminance): primary highlight x (0.3 + 0.18 x dark), a white lobe of the second
  highlight x 0.08 x dark) so near-black hair shows its shine instead of a flat mass; every strand gets a little hue shift (red +-5%, blue -+7% by `random_b`) so ginger/brown are not one flat colour.
- Round 45: motion check of all 21 presets with the head still (frame 420) after the generator changes of rounds 35-44: no preset has a guide moving more than 1.7 mm per step (worst Side part 1.7 mm,
  Fade 1.6, Dapper/Wavy medium 0; at most 4 of 3,700 guides move; the earlier 6-14 mm flapping is gone).
- Round 46: presets French crop (5 cm, short fringe straight down, sides cut), Slick undercut (16 cm combed back, sides off, small quiff) and Mop top (14 cm, thick fringe to the brows, volume 1.3): 24 in all.
  All look like the names in the captures; Mop top has a grey-white glare band on the fringe (the highlight of long flat hair facing the light): open.
- Round 47: the grey-white band on the fringe of Mop top (and the side of Pompadour from behind) is the specular highlight: with `--shine=0` it is gone. The highlight cap in `light()` is now
  0.06 + 0.12 x `dark` (was 0.3, then 0.16): the band is dimmer and beige instead of white; black hair keeps a visible shine (cap 0.18); the TT glow, `specular_disabled` and the environment
  were not the cause (tested). The band's width is what is left (straight parallel hair gives a wide highlight): narrower exponents or a normal wobble per strand would break it up.
- Round 48: the highlight's per-strand shift (`strand_shift`) is spread twice as wide (random_a x 1.5 and a 0.45 step noise along the strand): the glare on Mop top and Pompadour is now a patchy
  sparkle of strands instead of one band, black hair keeps its shine. No script/shader errors.
- Round 49: the crown specks/slits are covered with a small dark patch under the hair (not paint over the whole head): the scalp-cap vertex alpha is now 0 except within 3 cm of the crown and along
  the parting line (1.2 cm each side, from 4 cm behind the crown forward); the lab slider is now "Crown patch under the hair (0 = none)", default 1 (the shader uniform `scalp_layer` is unchanged).
  Top views of Undercut, Pompadour, Side part, Fade (pitch 25) have no skin showing at the crown or along the part. The whole-head layer the user asked to remove stays removed.
- Round 50: white speckles at the silhouette of short brown hair (seen with shine 0.4, gone with shine 0): the highlight cap is now 0.035 + 0.14 x `dark` and the highlight is tinted by the hair colour
  more (mix factor 0.9 - 0.6 x dark^2): brown/ginger have a soft sheen, black keeps its shine; a few pale strands remain at the far silhouette (back-lit). (The loop prompt arrived about ten times in a row: one round done.)
- Round 51: check of the 24 presets' newest members. Still head: Mop top, French crop, Slick undercut, Curly, Long, Pompadour: at most 4 guides moving, 1.5 mm per step at worst. Turning (bench): Mop top 149k hairs 59 fps
  (GPU 4.7 ms), Curly 134k 58 fps (5.2 ms), Slick undercut 104k 55 fps (GPU 5.9 ms: 7 points per hair, the heaviest so far). All above 55 fps; the frame is GPU-bound around 5-6 ms for the 7-10 point styles.
- Round 52: looked at pale edges on the silhouette from below (Dapper, Pompadour, Afro, Wavy medium, camera pitch -15). Dimming the back-lit glow (`through` x 0.07, scaled by hair brightness; was x 0.25)
  changed nothing visible, so the pale edge is not the TT lobe: it is the thin tips (width 4% of the hair, alpha-blended with the light sky behind) and the tip lightening. Kept the dimmer glow. Open: a
  minimum tip width (or a darker tip colour) to keep the silhouette from washing out against a light background.
- Round 53: the pale silhouette edge (round 52): tip lightening 0.15 -> 0.04 (shader default) and the tip width 4% -> 15% of the hair width (`1 - 0.85 x s^1.4`): Pompadour and Afro edges are brown now; Dapper keeps a
  pale fringe at the top edge (sky-blended single hairs seen from below). Hairs are a little blunter at the tip than the pointed tips of round 4 (15% instead of 4%).
- Round 54: presets Pixie (6 cm, swept side fringe), Ivy league (9 cm, clear side part) and Long waves (30 cm, curl 0.18, 12 points: 134k hairs, 2.06M vertices, 58 fps, GPU 5.2 ms): 27 presets. Pixie
  and Ivy league look right. Long waves (and any long curled hair) looks like straw: the flat ribbons of long hair (up to 2.3x wide) and the coils are coarse and angular; at curl 0.5 it was worse. Open: smooth
  the coil (more points per turn, less ramp) or draw long hair as bundles instead.
- Round 55: the straw look of long hair came mostly from the width: long-hair ribbons grew to 2.3x (round 41) and showed as flat sticks with a glare when turned to the light. Now x (1 + 0.5 x ramp) (1.5x
  at 28 cm): Long and Bob are fine strands again, Long waves is softer; a glare patch remains on the side of Long waves (curled strands face the light at many angles). The coil radius is small (2 mm at
  curl 0.18), so the coil was not the cause.
- Round 56: backs of Buzz, Slick back, Curly, Afro, Shaggy, Bedhead (yaw 160): covered, no bald spots. All show a pale glare patch low on the side of the head (the light is from the front-left); default shine is now
  0.28 (was 0.4, shader and lab slider): the patch is softer. A lighting-independent look would need the highlight to depend less on the view direction.
- Round 57: full-frame capture of Wavy medium showed the hair covering the whole face (preset: fringe 0, swept 0.7): swept lowered to 0.2; long hair now combs the whole forward half back by `fringe`
  (front_here threshold 0.45 - 0.4 x clamp((length - 10 cm) / 10 cm)): Long (fringe 0.2) shows the face with a split fringe. Wavy medium, Long waves and Shaggy-like curled long presets STILL fall over the face
  with fringe 0 / 0.2, swept 0, parting 0, curl 0 (tested one by one): the difference from Long (28 hairs, 8 points, volume 0.9, curl 0.2) is not explained; check points/strands (36, 12 points) and the lab's
  preset reset keys (strands/points/curl/volume are overwritten by each preset, `fringe` too). Open.
- Round 58: tested Long with the Long-waves values one by one: `strands:36,points:12` alone makes the hair fall over the face (curl/volume/length did not). Cause: the gravity bend is applied per step, so
  more points bend the strand more over the same length. The bend is now scaled by min(1, 5 / (points - 1)) (`pull_here`): Long (8 points) now parts at the sides and shows the forehead, Afro is unchanged
  (10 points, curl); Long waves and Wavy medium still cover the face (the bend is smaller but not enough): next try a stronger forward-flow limit for the front hairs of long hair (clamp the first 3 segments' downward turn).
- Round 59: MEASURING ERROR FOUND. The `--hair-preset=` command-line path did not reset `quiff`/`swept`/`hug`/`sweep`/`strands`/`points` for presets that do not name them (the preset BUTTON did): captures
  of Buzz, Short, Bob, Long, Slick back and Curly (the presets without a quiff key) were made with the starting Dapper's quiff 0.8 / swept 0.3. That is why Long looked parted and "Long waves"/"Wavy
  medium" (which do name them) covered the face, and why round 58 chased the point count (the points change was real but not the cause; kept). Fixed the CLI path to reset them. Real Long (no quiff)
  covers the face entirely. Long, Wavy medium and Long waves now have quiff 0.6, swept 0.6, parting 0.4, fringe 0: the front lifts and the hair falls to both sides, the face and eyes are visible.
  Earlier captures of those six presets (rounds 24, 40, 41 and the all-presets overviews) were not what the buttons produce: re-check Bob, Short, Buzz, Slick back and Curly by button values.
- Round 60: re-checked Buzz, Short, Slick back, Curly, Crew cut with the corrected command-line path (button values): all fine (covered, forehead and eyes free; Curly is a curly mop). Bob (fringe 0.3) covered
  the eyes: now fringe 0, parting 0.3, swept 0.6, quiff 0.5: a bob with a lifted, side-swept fringe, eyes visible.
- Round 61: the white stripe on the lower side/neck hair of Curtains, Bowl cut, Mop top, Bedhead (seen in the corrected-path overview; the same one as the "glare patch" of rounds 47-56): it is the highlight
  (`shine 0` removes it), but not NaN (isnan/safe-normalize guards did not change it) and not large: with a cap of 0.04 on the specular term it is still a white stripe, with 0.0001 it is gone. The units
  here are far smaller than I assumed (a cap of 0.04 reads as white on brown hair whose albedo is about 0.05). `light()` now clamps the glint to 0.003 + 0.25 x the hair's luminance (brown about
  0.015): the stripe is a soft sheen, black hair keeps a dim sheen. This replaces all earlier cap values (0.3, 0.16, 0.06, 0.035 + 0.14 x dark) which were still far too strong: rounds 47, 50 and 56 only
  made the stripe narrower. The NaN guards (h, t1, t2 divided by max(length, ...)) are kept.
- Round 62: with the small glint cap black hair looked flat: cap + 0.008 x `dark` (0.003 + 0.25 x luminance + 0.008 x dark): black hair has a grey sheen on the lower side hair, brown/ginger/blond a soft one, no white
  stripes (Dapper in #0a0806, #3a2410, Curtains black, Pompadour ginger, Afro blond, Long brown checked).
- Round 63: top views (pitch 35) of Fade, Undercut, Slick undercut, Pixie, Ivy league, French crop, Quiff, Side part with the corrected path: all covered with a natural whorl; only a few light specks at the crown
  of Undercut and Slick undercut and a dark band (scalp patch) along the front hairline of Slick undercut/Ivy league. No code change.
- Round 64: the crown/parting patch (round 49) now stops 6 cm in front of the crown (was: to the hairline). The grey band along the front hairline of Ivy league and Side part stays: it is the sheen
  (glint cap of round 62) of the combed-back front hair, not the patch.
- Round 65: regression check after rounds 55-64 (corrected path). Turning: Dapper/Pompadour 149k hairs 57 fps (GPU 3.8-4.0 ms), Long waves 134k 58 fps (4.8 ms), Curly 134k 58 fps, Mop top 149k 59 fps, Afro 149k 58 fps.
  Head still: at most 7 guides moving (Long waves, 2.6 mm per step), others 0-1 mm. No regression.
- Round 66 (user sent a crop: thin angular ghost lines above the top of long hair; "it must be more circular, not sharp, the curves"): the offset-height clamp and an outward-offset removal for spread hairs changed
  nothing (identical captures); the sharp corners are in the guide path itself (drape moves one point at a time: pushed off the head, held under the ceiling, turned by gravity). Fix: 3 passes of neighbour averaging
  of the strand points after the drape (0.5 own + 0.25 each neighbour, root fixed, tip drawn toward the extrapolation of its neighbours), before the curl. Long and Bob top lines are smooth curves now; Wavy medium
  has one ghost polyline left at the crown, and some small tufts at the front crown stand up in sharp zigzags (the quiff lift / the crown flow turn): next.
- Round 67: side views of Wavy medium, Pompadour, Dapper, Afro, Curly, Long waves after the path smoothing: Pompadour/Dapper quiffs are soft tufts, Afro/Curly rounded masses, Long waves a smooth dome. A single
  thin ghost polyline still stands above the crown of Wavy medium (a curl-0.7 hair: the helix is added after the smoothing, so its corners are not rounded). Idea: smooth once more after the curl, lightly.
- Round 68: one more neighbour-averaging pass on each single hair's own path (after the spread and the clamps, strands mode only): the ghost polyline above the crown of Wavy medium is a faint thin curve now;
  Long's top is a smooth dome, Afro rounded curls. Cost: none at runtime (build time only).
- Round 69: front views (distance 0.7) of Dapper, Curly, Buzz after the smoothing: clean hairlines (a slight rectangular corner at the temples of Dapper/Buzz: the hairline model's temple step), settled with
  the head still (0-1 guides moving). Open: round the temple corners (the hairline function has a sharp step between the front and the sideburn).
- Round 70: the temple corner: the hairline now slopes from the front down to the sideburn over azimuth 0.7..1.4 (was 0.9..1.3) and the sideburn starts at 1.05 (was 1.15): the temples of Dapper, Buzz and Short
  are round curves in the front, three-quarter and side captures; no skin gap above the ear. The widow's-peak notch in the middle of the front hairline of Dapper (parting) stays.
- Round 71: side views of 8 short presets: Fade and Undercut (side_trim 1) showed bare skin behind the ear with a hard outline. The cut sides and back now keep stubble: a lock's length is at least 3.2 mm x side_trim
  (x 0.8-1.2, thinner toward the hairline) where side_trim > 0.5 and the root is on the lower 60% of the head. Fade, Undercut and Slick undercut now have a dark stubble area under the longer top (a gradient
  from the top). The stubble is a little heavy (reads as a short beard-like mass behind the ear): lower the minimum or fade it faster toward the skin.
- Round 72: stubble minimum lowered to 2.2 mm x side_trim (x 0.7-1.2, x (0.3 + 0.7 x feather)): the sides of Fade/Undercut look like short dark stubble that thins at the hairline. The mass still reads dense because
  the hairs of short locks are spread 1.5-2.5x wider than long ones (round 40) and are 1.4 mm wide: for stubble a narrower spread would show more skin through it.
- Round 73: stubble does not fan out (the extra spread of short locks, round 40, now only applies from 4 mm of length: spread x (1 + 1.5 x short-ness x clamp((length - 4 mm) / 12 mm))): the cut sides of Fade and
  Undercut are speckled stubble with skin showing through, like clippered hair; Buzz/Crew cut (2-3 cm) are unchanged and covered, with one 3 mm bare spot at the crown of Crew cut.
- Round 74: check after the stubble/spread changes: Fade 144.5k hairs 57 fps (GPU 2.3 ms), Undercut 144.6k 57 fps, Crew cut and Buzz 148k 57-58 fps, Dapper 148k 57 fps, Afro 148k 58 fps (GPU 3.8 ms);
  builds 0.9-1.5 s; head still: 0-2 guides moving, 0.9 mm at worst. No regression.
- Round 75: female body (`--gender=Female`): Dapper, Long, Bob, Afro, Pixie, Curtains all grow and cover correctly on the female head (hairline, ears, parting follow the mesh). Long on the female has a few
  stray long strands across the face; no code change. The presets are tuned on the male head: a female default style (and per-gender defaults) is not set up yet.
- Round 76: pressing the Female / Male button now also applies that body's default style (`DEFAULT_STYLE`: Male Dapper, Female Long waves) once per switch (`_style_gender`): the female no longer keeps the
  male's short style. Long waves on the female: long wavy hair with a lifted, side-split fringe; a spiky tuft at the crown and a thin white strip at the left temple (skin through a gap) remain.
- Round 77 (after the PC restart): top views at pitch 30 of female Long waves, Bob and male Long waves with quiff 0: a small white (not skin-pink) speck at the exact crown, 5-8 mm, on every long style. Widening
  the crown patch (cap alpha within 4.5 cm of the crown instead of 3 cm) did not change it, so it is not the cap alpha: the speck is bright white like an unlit surface. Suspects: a hole in the body mesh at
  the top of the scalp (look at the body alone from above), or the cap triangle there being culled/degenerate (the crown point is a pole of the head mesh). Check with `--nohair` from above.
- Round 78: the white hole at the crown/parting (1-2 cm on Bob, Dapper, Pompadour, Long waves with `extras` 0): `extras:1` closes it, `extras:0` leaves it; the scalp patch under the hair does not cover it (the mesh is too
  coarse there for vertex alpha: it stays at the crown pole), and neither does a thicker cap (3.5 mm: reverted). The two extra-lock groups that matter are now always on, whatever `extras` says: the crown
  group (6 x locks draws) and the parting line group (|x| < 2.5 cm, 35%). Dapper, Undercut, Fade, Bob, female Long waves have a small speck or none; Pompadour keeps a 1 cm slit. Cost: about 30% more hairs
  (Dapper 197k, 180-199k on the others).
- Round 79: all 27 presets built and ran 5 s each with no script or engine errors (button-equivalent `--hair-preset`, frame 300). The generator, simulation and lab are stable enough to commit: everything
  since 7516c3e is still uncommitted (hair_sim_native, human_hair_native, human_hair.gdshader, human_body_lab.gd, notes, addons/tressfx + tressfx_bridge.gd).
- Round 80: tried a wider/denser parting-line fill for quiff styles (width 2.5 + 1.2 x quiff cm, 35 + 25 x quiff %): Pompadour went to 242k hairs and kept its slit (a zigzag along the line), so it was reverted.
  The slit is geometric (the two sides' flow crosses the line at an angle): needs the hair of a quiff style to cross the line in the first segments, not more hairs.
- Round 81: the cross-over lean for quiff styles is stronger (part_soft at the line -0.5 - 1.2 x quiff, was -0.5 - 0.5 x quiff): Pompadour's crown slit is closed (194k hairs, as before), Dapper has a small
  speck, Quiff a few specks where the lifted front meets the crown.
- Round 82: check after the cross-over and the always-on crown/part extras: Pompadour 195k hairs 57 fps (GPU 4.0 ms), Dapper 198k 57 fps (3.8), Slick undercut 192k 57 fps (3.9), Quiff and Afro 165k 57-58 fps
  (2.9 / 4.0); head still: at most 5 guides moving, 1.8 mm per step at worst. No regression.
- Round 83: presets Spiky (7 cm, volume 1.6, gravity 0.05, quiff 0.5) and Surfer (17 cm, curl 0.3, combed back 0.6, 9 points): 29 in all. Surfer reads as medium swept-back hair; Spiky is a tousled short cut, not
  spikes (strands follow the head, gravity does not stand them up): real spikes need a "stand off the skin" control (a per-style outward direction for the first segments).
- Round 84: new generator control `spike` (0..1, lab slider "Spikes (stands off the skin)"): the first segments point away from the head (direction = flow x (0.95 - 0.5 x spike) + normal x (0.04 + 1.4 x
  spike)), the gravity/skull pull on the first 75% of the strand is cut by up to 85%, and the height ceiling over the crown rises by up to 3.5 cm. Spiky preset (spike 0.75, 7 points, quiff 0): the hair radiates
  from the crown in spikes; spike 1 with 9 cm hair is a spiky crop. Not tested: spike with long hair or with the simulation under a fast turn (the sim pulls the strands back to the style, the strands are stiff).
- Round 85: spike under motion and with other lengths: Spiky 165k hairs 58 fps while turning (GPU 2.8 ms), 2 guides moving at 0.8 mm with the head still. Captured during the oscillating turn (back views): the spikes keep
  their shape (no stretch, no collapse). Spike 0.5 with 16 cm hair is a round mushroom cap (the standing part falls at the 75% mark), spike 1 with 10 cm and side_trim 0.9 a flat-top: the control is meant
  for 5-9 cm hair; on longer hair it gives a hat shape (a limit on the slider or a length-dependent fall would help).
- Round 86: `spike` is faded out with the hair length (full up to 8 cm, zero from 18 cm): the 16 cm test is a normal bob with a few strands standing at the crown (no mushroom), spike 1 with 10 cm a spiky crop,
  the Spiky preset (7 cm) is unchanged. A pair of stray strands lies flat out to the left at the crown of the 16 cm case (spiked strands that the fade leaves half-stood): minor.
- Round 87: all 29 presets (now with Spiky and Surfer, and the `spike` control and its length fade) run 200 frames each with no script or engine errors.
- Round 88: female body with Surfer, Spiky, Ivy league and Mop top: all grow and cover correctly (Spiky is a short spiky cut, Mop top a bob with a full fringe to the brows, Ivy league a neat short cut with a bang). No change.
- Round 89: new presets Feathered (20 cm, side-swept, layered volume) and Cropped waves (9 cm, curl 0.45): 31 in all. Feathered grew wings: long hair sticking out horizontally at both temples; cause found by
  elimination: `sweep` (the "comb holds hair against gravity" term `held`) on 20 cm hair. `held` now fades with length (full to 12 cm, none from 25 cm) and Feathered has sweep 0.15: wings gone. Slick undercut,
  Slick back and Surfer keep their combed look.
- Round 90: Feathered checked after the `held` fade: wings gone, but with sweep 0.15 / quiff 0.4 the front hair covered the eyes; preset now sweep 0.3, quiff 0.6 (side-swept front, eyes and forehead free,
  no wings). Cropped waves (9 cm, curl 0.45): a neat short wavy cut, covered.
- Round 91: profile overview of all 31 presets (yaw -90): the long styles show a grey translucent patch over the cheek (the highlight; `shine 0` removes it). Cause: the glint was clamped per channel to the cap, which
  turns a brown (r > g > b) glint into grey; it is now scaled (`min(1, cap / max channel)`), and the highlight is tinted by the hair colour except for near-black hair (mix 0.97 - 0.75 x blackness). The patch is
  now a warm sheen on brown/ginger, a soft grey on black; blond has none. Also seen in the overview: speckled stubble sides on Fade/Undercut (fine), a few specks at the back of Pompadour.
- Round 92: re-captured the three Curtains colours after the glint change (the round-91 picture was stale): ginger has no grey patch, brown a faint cool one over the cheek, black a soft grey sheen. A capture run
  sometimes leaves no PNG (2 of 3 missing once): re-run it.
- Round 93: speed of the newest presets while turning: Feathered 176k hairs 58 fps (GPU 4.4 ms, build 2.0 s), Surfer 175k 58 fps (4.6), Spiky 165k 59 fps (2.9), Cropped waves 165k 59 fps (3.0), Long waves 177k 57 fps (4.5,
  build 2.6 s). No regression.
- Round 94: lowering the glint cap (0.002 + 0.16 x luminance) did not change the grey patch over the cheek of long brown/black hair (identical captures): so it is not limited by the cap, the raw glint is below it and
  the patch is its natural size; reverted to 0.003 + 0.25 x luminance. A real reduction needs a lower `shine` for those colours or a narrower lobe (exponent), not the cap.
- Round 95: tighter highlight lobes (exponents 160 / 110 instead of 90 / 60) did not shrink the grey patch over the cheek either (captures nearly identical); reverted. The patch is gone with `shine 0` but neither the cap
  nor the exponent moves it: suspect the second highlight (`spec2`, tinted by ALBEDO x 1.3, no cap on its share) or the strand_shift spread making many strands catch the light; next test: zero spec2 alone, then zero spec1 alone.
- Round 96: zeroing each part of the light() code one at a time on brown Curtains (profile): without the first highlight (`spec1`, 0.3 x white-ish) the patch over the cheek turns warm brown; without the second highlight
  or the back-lit glow it stays. So the grey is `spec1`: its strength is halved (x 0.5).
- Round 97: all 31 presets re-run (150 frames each) after the highlight changes of rounds 91-96 (glint scaling, spec1 x 0.5): no script, engine or shader errors.
- Round 98: stubble density: locks shorter than 6 mm grow 80% of the hairs (0.5 made lace-like holes, 0.8 gave the same look as 0.5 in captures: the speckle is by lock, not by hair, since each short lock is a small clump).
  The cut sides of Fade/Undercut/Slick undercut are speckled dark stubble with skin showing, like a clippered head; the stubble reads sparse near the top of the cut, dense at the nape.
- Round 99: final check of the current build (stubble change included): all 31 presets run 150 frames without errors; Fade 192k hairs 57 fps (GPU 2.6 ms), Dapper 198k 57 fps (3.1 ms), Long waves 177k 58 fps (4.2 ms).
- Round 100 (user: "slick undercut, on the back side I see skin spots"): the spots were the speckled stubble band at the back where the long top meets the cut hair (my own rounds 72, 73, 98: fewer hairs, no fan-out,
  thinner minimum). Reverted toward a solid cover: stubble hairs fan out again (spread ramp from 1 mm, not 4 mm), full hair count, stubble minimum 3.0 mm x side_trim (0.5 + 0.5 x feather). Back views of Slick
  undercut, Fade, Undercut, Pixie, Crew cut: no skin spots; the cut area reads as short dark hair with a visible edge under the top. Slick undercut 195k hairs, 59 fps turning (GPU 3.9 ms).
  Lesson: the "clippered with skin showing" look is not wanted; coverage over realism of stubble.
- Round 101 (user screenshot, Hair shine slider near its maximum, seen from below at the side: the back/side hair is flat grey-beige): the shine slider was at ~1. At shine 1 and 0.28 the glint was the same
  grey, so it was sitting AT the cap (any shine above a small value saturates it): the cap was the real strength. The cap is now 0.001 + 0.06 x luminance + 0.006 x dark (was 0.003 + 0.25 x luminance + 0.008 x dark) and
  the white lobe of the 2nd highlight fades with the hair brightness (not `dark`): from below, the hair is brown with a faint grey sheen, at shine 0 pure brown. The slider now only matters below about 0.3.
  (Round 94 lowered the cap and saw "no change": that capture was probably stale: always check the file time.)
- Round 102 (user: "maybe make hair shine to 0 by default"): default `shine` is 0 in the shader and in the lab slider (was 0.28): hair is matte brown from every angle; the slider still brings the highlight back.
- Round 103 (user: the skin shows through gaps where the hair is stiff; "the paint was noticeable, find a better way"): a dark scalp as the SKIN'S OWN colour, nothing drawn over the head. HumanHair now writes
  `hair_scalp_weight` (per body vertex: 0 at the hairline, smoothstep to 1 over 2.5 cm above it; mesh meta). New `shaders/human_skin.gdshader` replaces the lab's StandardMaterial3D skin (same albedo 0.6/0.4/0.32,
  roughness 0.55, SSS 0.2) and mixes in `scalp_color` (= hair colour x 0.55, follows the colour picker) by that weight, read from a texture by VERTEX_ID (width 1024, R32F). The old "crown patch" layer defaults to 0 now.
  Top/side/back views of Pompadour and Fade: no pale specks at the crown or the part, the face skin is unchanged. Open: the skin shader is only in the lab: the game's body materials need the same shader + upload.
- Round 104 (user: "i still see some skin"): the scalp weight now starts at 0.55 at the hairline (was 0) and rises to 1 over 2.5 cm: the edge row of the scalp is half dark. Captures (Dapper front/side, Fade side,
  Buzz top, Pompadour back) show no pale skin through the hair; left: a dark star hole at the crown of Buzz and a thin light line along its front hairline. Without a screenshot of the exact angle and style I cannot
  tell which spots the user sees: ask for one (style, angle, and whether the head was moving: hair that lags behind a turn exposes the scalp, which is dark now but still skin-lit).
- Round 105: (1) the white specks the user showed (Dapper, quiff base, seen from the left-top side: my captures had used the wrong side): they were scalp skin seen at a grazing angle, glossy (specular + SSS), so white
  even though the scalp colour is dark. The skin shader now makes the scalp matte (roughness -> 1, specular 0, SSS off with the scalp weight): the specks are tiny tan dots now. (2) CORRECTION OF EVERY HAIR COUNT IN
  THESE NOTES: the lab readout was guides x hairs-per-lock, but near the hairline a lock grows fewer hairs than that, so it overstated. Real hairs = (vertices - ~600) / (2 x points): Dapper 113.7k (not 197k), Pompadour
  112k, Long waves 113k, Buzz 95.8k, Afro 95.8k, Fade 112.7k. The "150k" of rounds 38-77 was really ~90-100k; the always-on crown/part extras of round 78 raised it to ~110k, not 30% to 200k. The readout is fixed.
- Round 106 (user: "make sure we have always like 150k or 200k"): FOUND A CAP: the generator clamped `strands` (hairs per lock) to 24 (human_hair_native.cpp, `Math::clamp(..., 0.0, 24.0)`), so every "40 per lock" preset had
  really been 24, and the "60 per lock = same GPU time" test of round 16 was the same cap. The cap is now 96. The lab aims every style at TARGET_HAIRS = 170,000 REAL hairs: it scales the preset's hairs per lock by
  `_strand_scale` (learned: after a build more than 8% off the target it rescales and builds again, twice at most; reset when a slider moves), up to 96 per lock. Result: Dapper 170.8k, Fade 169.1k, Long waves 169.7k,
  Curly 171.8k, Buzz and Afro 159.8k (6% under: the per-lock cap), all at 58-60 fps while turning (GPU 4.2-5.0 ms); builds 1.7-3.8 s (Long waves). Vertices 2.0M (Dapper) to 4.1M (Long waves: 12 points).
  Every earlier hair/vertex count in these notes before this round is for 24 per lock at most.
- Round 107 (user: "a person can have any hairstyle but always the same follicles, right?"): yes. The follicle set no longer depends on the style: the style-dependent extras are gone (fringe/quiff front extras are
  a fixed set as for a medium fringe, the parting-line extras always, the old fill/back/edge extras off), a lock is never dropped for being short (min length 1.5 mm: a cut style makes the hair short, it does not
  remove it), and the lab uses one hairs-per-lock for all styles (40 x the learned scale). Real hairs per style are now within ~2% of each other: Dapper 171.6k, Fade 169.4k, Buzz 167.9k, Long waves 169.7k, Afro 167.9k,
  Pompadour 168.4k, Bob 168.9k (6.15-6.3k guides). Dapper 58 fps (GPU 3.6 ms, build 1.5 s), Long waves 60 fps (5.2 ms, build 3.6 s). Fringes and bobs are fuller. All presets run without errors.
  The `extras` parameter remains in the generator but is ignored.
- Round 108 (user: "how thick are the hairs? like real life?"): no: a hair was a ribbon 1.4 mm wide (real 0.05-0.1 mm), because thin ribbons at the old (24 per lock, <120k) counts left gaps. Added the lab slider
  "Hair thickness" (`strand_width`, 0.2-3 mm) and compared 1.4 / 0.9 / 0.6 / 0.4 mm at 170k hairs: no gaps at the crown, part or silhouette down to 0.4 mm; thinner is finer and a little darker. Default now 0.8 mm
  (generator default and fallback). Side effect of the fixed follicles (round 107) + thinner hair: long styles with fringe 0 let front strands fall over the eyes (Long waves, Long, Wavy medium); front extras now
  use front_density 0.15 (was 0.45) and these three presets use swept 1, quiff 0.9, parting 0.5, sweep 0.3: eyes and brows free. Build note: a build fails ("scons: building terminated") while ANY lab window is open
  (kill them all first, including the windowed `Godot_v4.7.2-stable_win64.exe`).
- Round 109 (brows and lashes loop, first round): baked finer face hair with `tools/blender/make_face_hair.py` (run: copy `assets/models/humans/{male,female}_body.glb` and `tools/blender/landmarks/*_landmarks.json` into one scratch
  folder, `blender -b --factory-startup --python tools/blender/make_face_hair.py -- <folder>`, copy the four `*_brows.glb` / `*_lashes.glb` back to `assets/models/humans`, then `godot --headless --path . --import`: the lab
  does NOT see new glb files until they are re-imported). Brows: 560 hairs per brow (was 320), 6.8 mm long (5.2), 0.55 mm wide (0.9); lashes: 34 upper roots x 2 (24 x 3), 18 lower roots (12), 0.6 mm wide (1.1). The brow's
  outer end is 3.5 mm shorter (the long thin tail seen from the side). Front and side captures: fuller, finer brows with a short tail, lashes a fine fringe, no heavy black spikes. Still: the upper lashes in the middle
  of the lid are longer and darker (spidery); brow colour is the lab's own colour (not tied to the head hair colour); brows have no gradient from a darker root to a lighter tip.
- Round 110 (brows and lashes): brows and lashes now follow the head hair colour (lab: `_hair_color` = head colour lightened 10% at start and whenever the head colour changes, unless `--brow=` is given; the Brows tab picker can still
  override it); face-hair shader: a hair is darker at the root and lighter at the tip (x0.7 .. x1.12), lash_darken 0.55 -> 0.42 (lashes were jet black); upper lashes 7.8 mm (9). Checked on brown/ginger-blond, black and blond heads:
  the brows match the hair; the black head's brow reads dark grey (the 10% lightening and the tip shading) - could be less. Rebaked glb files (the four), re-imported.
- Round 111 (brows): the brows looked silver-grey, much lighter than the head hair even with the same colour: the face-hair shader had SPECULAR 0.3 / ROUGHNESS 0.55, so the sun made a white sheen on thin dark strips. Now
  SPECULAR 0.04, ROUGHNESS 0.8; the lab's brow colour is the head colour lightened only 3% (was 10%). Front and three-quarter close-ups: the brows are dark brown like the hair, with visible strands and a darker root.
- Round 112 (lashes): a fuller and more uneven fringe: 46 upper roots x 2 (was 34), 26 lower roots (18) 3.4 mm long (4.0), length per lash x0.6-1.05 (was 0.75-1.1). Close-ups of both bodies, front and three-quarter: a dense
  natural fringe with longer lashes toward the outer lid, a soft lower row; no isolated heavy spikes. Re-baked and re-imported. Lashes are still one colour (the head colour, darkened by 42%): no curl control in the lab yet.
- Round 113 (brows, light hair colours): blond hair gave lemon-yellow brows and lashes (the brightness multipliers pushed channels past 1) and brows the same colour as the hair. Fixed: `human_face_hair.gdshader` pulls
  bright colours toward grey (as the head hair shader does); the lab derives the brow colour from the head colour with `_brow_colour_for` (light hair gets darker brows: darkened by up to 50% by luminance). Close-ups
  of blond, ginger and white hair: dark-blond/olive brows, copper brows, grey brows; dark hair is unchanged. The blond brows read a little olive-green (the grey pull keeps the hue of a yellow-brown): could be warmer.
- Round 114 (brows, blond hair): the grey pull of the face-hair shader now goes toward a warm grey (x1.12, 1, 0.8) and the lab's `_brow_colour_for` adds a little red for light hair (+12% red, -8% green, -12% blue at full
  light): blond heads get honey-brown brows, white heads grey ones, ginger and brown unchanged. (+25% red looked orange, +4% still olive: 12% is the middle.)

## Licence rules for outside references (2026-11-23)
- The repo is PUBLIC on GitHub (AgustinJimenez/godot_test1) and has NO licence file yet; the runtime code is C++ (GDExtension), the labs are GDScript.
- Reading other projects for IDEAS is fine (techniques and methods are not copyrightable). Copying code, porting it to C++, or shipping its assets is not, unless the licence allows it:
  - MIT / Apache-2.0 / BSD (TressFX, VHair, oxiphysics-softbody): may be read and adapted with attribution.
  - GPL / AGPL (CharMorph code is GPL-3.0, its database and the MB-Lab meshes/json are AGPL-3.0): a port to C++ is still a derivative work; assets in the repo would make the repo AGPL. DO NOT copy, translate or ship them. Only note ideas in our own words.
  - Unreal Engine source (E:\repo\UnrealEngine): study only, nothing pasted (see 083).
- If the owner decides to take GPL/AGPL material, that needs a licence file and an owner decision first.

### CharMorph (https://github.com/Upliner/CharMorph), read 2026-11-23, ideas only
- Blender addon (author Upliner); base meshes and morphs from MB-Lab, own database format; hairstyles, real-time asset fitting, Rigify face rig; the rig is added only when the character is finalized.
- Hair = Blender hair particle systems (not cards) kept in a library .blend; each style is a named particle system copied onto the character; the "scalp" is built from a vertex group on the MORPHED body and the hair is re-fitted (shrinkwrap, offset per character) after each morph.
- Not found yet: eyebrows, eyelashes, shape-key names, the hair library (the data is a separate repo, CharMorph-db). Next: read the data repo layout and conventions (no copying).
- CharMorph data repo (CharMorph-db, a submodule), read 2026-11-23, ideas only: layout = `characters/` (antonia, mb_female, mb_male, reom + aliases.yaml), `tweaks/` (YAML: eyes, muscles, rigify_default), `textures/`,
  `hair_colors.yaml`, `mb_bones.yaml`, `shared_lib.blend`; no top-level hair/clothes/rig folders. A character export is YAML (or MB-Lab JSON): `type`, a `morphs` map (name -> value), `meta`, `materials`.
  Hair: one particle system per style on a library hair object; scalp built from vertex group `scalp[_name]` of the morphed body (else the whole body); density/length painted in vertex groups `hair_<character type>` / `hair`;
  default HAIR type, interpolated children, root radius 0.01; "refit" re-runs the fit; optional shrinkwrap (project, outside surface, per-character offset). Hair colour = a table of 12 named entries (`hair_colors.yaml`: Blender
  hair BSDF, MELANIN / COLOR / ABSORPTION, tint, roughness, ior, viewport colour). Assets (clothes) have a "fitter": binder soft/hard, mask none/per-asset/combined, weights none/original/object; each asset has a `license` field.
  Nothing found about eyebrows, eyelashes or beards. Not read: morphing.py, rig.py, lib/fitting, the character folders, any asset licence value, the db licence (no LICENSE file visible at its root).
  Ideas we could use in our own words: (1) a table of named hair colours (melanin-style: dark brown, blond, ginger, grey) instead of free colour picking: our lab swatches are the start of this; (2) density and length painted per
  region (we use hairline and side_trim functions: a paintable weight map would let artists shape a cut without code); (3) saving a character as a small data file (type + morph values) rather than scene state.

### Blender Character Project docs (https://blendercharacterproject.org/docs/html/Hair.html, = the CharMorph 0.2 documentation), read 2026-11-23
- The Hair page is only a gallery of which characters ship which hair; it does NOT explain the hair system, parameters, colour model or numbers.
- Code: GPL (version not named). Per-character content licences: Antonia CC-BY 4.0, Reom CC-BY 4.0, Vitruvian CC0, MB-Lab AGPL 3.0. The docs pages carry no licence statement.
- Hair is stored as curves/strands (Reom, Vitruvian: hairstyles converted to curves); Reom's eyebrows are Blender hair systems modelled on the MakeHuman eyebrows (12 styles, Eyebrows001-012); Vitruvian's are MakeHuman
  "mind_eyebrows" meshes (by Mindfront) converted to strands (14 variants, default mind_eyebrows_11). Eyelashes and beards: not covered.
- Possibly reusable in a public repo: Vitruvian (CC0 at character level), but its eyebrows/hairstyles are credited to third parties (Mindfront via MakeHuman, Renderosity Zoro_d, MakeHuman 04Saken) with no licence given on the page:
  check each asset's own source/licence (the MakeHuman asset packs list the CC0 eyebrow, eyelash and hair packs) before using anything.

### MakeHuman asset packs (https://static.makehumancommunity.org/assets/assetpacks/), read 2026-11-23, from the pack pages (zips not opened yet)
| pack | author | licence | size | items | note |
|---|---|---|---|---|---|
| Eyebrows 01 (eyebrows01_cc0.zip) | Mindfront | CC0 | 10 MB | 14 (mindfront_eyebrows_01..14), typed "clothes" | the same eyebrows Vitruvian uses |
| Eyelashes 01 (eyelashes01_cc0.zip) | Mindfront | CC0 | 3 MB | 5 (mindfront_eyelashes_01..05) | page text says "high-res eyebrows" (copy-paste error) |
| Hair 01 (hair01_cc0.zip) | Cortu, culturalibre, Elvaerwyn, Faydaen, learning, littleright, punkduck, RehmanPolanski, sonntag78, MargaretToigo | CC0 | 217 MB | 25 (bobs, braids, buns, bangs...) | low-poly, stylized |
| Hair 02 (hair02_ccby.zip) | Elvaerwyn | CC-BY | 68 MB | 21 | high-poly: needs credit |
| Hair 03 (hair03_ccby.zip) | culturalibre, grinsegold, punkduck | CC-BY | 38 MB | 14 | needs credit |
| Bodyparts 05 (bodyparts05_cc0.zip) | culturalibre, grinsegold, RehmanPolanski, WDG | CC0 | 6 MB | 5 beards / moustaches | become "clothes" in MPFB2 |
| Hair editor (functional) | Tomas Klecer | page names none; index says functional packs are CC0 | 18 MB | hair.blend, fur.blend (geometry nodes) | |
- Downloads: files.makehumancommunity.org/asset_packs/<pack>/<pack>_cc0.zip (or _ccby.zip), mirror files2.makehumancommunity.org. MPFB2: "apply assets" -> library settings -> "install asset pack" (pick the zip);
  MakeHuman 1.x: unzip into data/. The site announced (2026-10-21, 2026-11-08) that community services shut down / move to Discord: download hosts may disappear.
- Core assets are CC0 (code: MPFB GPL, MakeHuman AGPL). Unknown until opened: file types (.mhclo/.obj/.mhmat/.png), mesh vs cards vs strands. CC-BY attribution wording: not on the pages (old wiki FAQ).
- Rule kept: nothing goes into the repo unless its own item says CC0 (or CC-BY with a credits file written). Downloads go to the session scratchpad first.
- OPENED the Mindfront packs (downloaded to the session scratchpad only: `mh_eyebrows/`, `mh_eyelashes/`, nothing in the repo): each item folder has `<name>.mhclo` (header says `# author Mindfront (Sweden)` and `# license CC0`),
  `<name>.obj`, `<name>.mhmat`, `<name>.thumb`. The meshes are real geometry, no textures (mhmat: black diffuse, no maps): eyebrows_11 = 24,984 vertices / 18,567 faces (both brows, about 12.5k verts each); eyelashes_01 =
  11,088 vertices / 8,316 faces. They are in MakeHuman units (dm, y up: the brow sits at y 7.42) and are fitted to the MakeHuman base mesh `hm08` through the mhclo: for each of the obj's vertices, three base-mesh vertex
  indices, three barycentric weights and an offset (scaled by x_scale/y_scale/z_scale from reference vertex distances). OUR BODY KEEPS THE hm08 BODY VERTICES FIRST (13,380 body verts, then helpers: `make_bodies.py` BODY_VERTS),
  so the mhclo indices (e.g. 181, 208, 209: forehead height z=1.65 m in our glb) point at the same places on our mesh: the Mindfront brows and lashes can be fitted to our bodies and bound to our shape keys exactly like
  `make_face_hair.py` does. First 3 reference vertices of the eyelashes (6814, 6828, 6837) are at foot height in our mesh, so lash mhclo may use a different index set: check before binding.
  Plan: a Blender script `tools/blender/fit_mindfront.py` (our own code, no MakeHuman code) that reads the CC0 mhclo/obj, rebuilds each vertex = sum(weight x our vertex) + offset x scale, adds UVs/vertex colours our face-hair shader needs,
  binds it to our shape keys and writes `*_brows_mf.glb` / `*_lashes_mf.glb` to compare against ours; credit Mindfront in a CREDITS file if we keep them (CC0 does not require it, but it is the right thing).
- Round 115 (MakeHuman CC0 packs, FIRST FITTED RESULT): the Mindfront CC0 brows and lashes are fitted to our bodies and look much better than ours: lower, fuller, natural brow shape, a fine real-looking lash fringe.
  Findings: (1) each Mindfront hair is a 3-sided tube of 3-4 rings (0.08 mm thick): 2,139 hairs in the 14-item brows (about 1,070 per brow), 924 lashes in eyelashes_01; (2) the mhclo indices refer to the MakeHuman base
  mesh in ITS OWN order, not to our glb (the glTF round trip splits and re-orders vertices: the first attempt put hairs on the feet); `tools/blender/fit_mindfront.py` (new, our code) re-creates the base mesh with MPFB
  (to get hm08 order), rebuilds every vertex = sum(weights x base) + offset x scale (axes MakeHuman x,y,z -> ours x,z,-y; units dm -> m), takes each hair's ring centres as a polyline, builds OUR tapered strips (width 0.4 mm
  brows / 0.3 mm lashes, a parameter), and binds them to our shape keys with the same nearest-vertex method as make_face_hair.py; (3) outputs `{male,female}_brows_mf.glb` and `{male,female}_lashes_mf.glb` in
  assets/models/humans (about 2.3 MB and 1 MB each); `assets/models/humans/CREDITS.md` credits Mindfront (CC0). The lab uses them by default now (`--classic-face-hair` loads ours). Run: `blender -b --factory-startup --python
  tools/blender/fit_mindfront.py -- assets/models/humans <unzipped item folder> <label> <out folder> [width_m]` then copy and `godot --headless --import`. Other brow styles (01-14) and lash sets (01-05) are in the
  scratchpad zips: try them by changing the item folder. Not yet checked: shape-key following at height +/-1, the female face, the head-hair colour link and density slider (green channel = random 0..1 is set).
- Round 116 (Mindfront brows, checks): (1) the fitted brows follow the body shape keys: height +1 / -1, weight +1 and muscle +1 captures (close-ups, distance 0.3) keep the brows on the brow ridge, no floating or sinking,
  and the density slider thins them (density 0.4 visibly sparser); (2) more styles baked from the same CC0 pack and selectable in the lab with `--face-hair=_mf03|_mf06|_mf09` (default `_mf` = style 11): 03 = thin and
  straight, 06 = thick and arched, 09 = medium arched, 11 = thick, flat and low (default). Files `{male,female}_brows_mf03/06/09.glb` added to assets/models/humans (2.3 MB each); the lashes are shared (`_mf`).
  Brow style could become a lab selector (with all 14) and a generator parameter: not done. Hair 01 (CC0, 217 MB) not downloaded yet.

### Hair 01 pack opened (downloaded to the scratchpad only, 228 MB): THE PACK PAGE SAYS CC0 BUT SEVERAL ITEMS DO NOT (2026-11-23)
Each item's `.mhclo` header carries its own licence line. Rule from now on: read the header of EVERY item before using it; the pack page is not enough.
- Eyebrows 01 (14) and Eyelashes 01 (5): all 19 headers say CC0 (author Mindfront). OK to use (done: credits in assets/models/humans/CREDITS.md).
- Hair 01 (25 items): CC0 per header: toigo_inverted_bob, toigo_inverted_bob_with_bangs, toigo_blunt_bob, toigo_blunt_bob_with_bangs, toigo_curled_under_bob, toigo_curled_under_bob_with_bangs (MRT), faydaen_hair_1,
  culturalibre_hair_05, culturalibre_hair_06; cortu_short_messy_hair says "Cortu Johnstone - CC0" (the other cortu_* items and the cloud/shaggy/bangs ones have no licence line: assume nothing, check the page).
  NOT usable: AGPL3 in the header: sonntag78_blond_with_headband, sonntag78_junglebook_hair, learning_anime_hair, littleright_bobcut_hair, elvs_double_mh_braid, elvs_unkempt_french_braid,
  elvs_french_braid_variation, culturalibre_hair_01, culturalibre_hair_02, rehmanpolanski_hair_bun_brown; CC BY 4.0 (credit needed): o4saken_long01, elvs_reverse_french_braid_bun (header "CC_by").
- What the hair items are: low-poly shell/card meshes with textures (not strands): e.g. cortu_short_messy_hair 832 vertices / 546 faces, 0.5 MB diffuse + normal map, alpha-to-coverage; toigo bobs 1.5k vertices with three
  10 MB PNGs each (diffuse, normal, specular); culturalibre_hair_05 2.6k vertices, a 5 KB texture. Fitted to the MakeHuman base mesh through the mhclo the same way as the brows (tools/blender/fit_mindfront.py works for it).
- What they would give us: styles we cannot grow (bobs with bangs, buns), as low-cost far-LOD or card hair; as REFERENCE shapes the bobs and the short messy cut are useful to compare with our Bob / Messy crop.
  Big textures (30 MB) would not be copied into the repo; if used, only the CC0 items, textures downscaled, credits added.
- Round 118 (Hair 01, first fitted hair shell): `tools/blender/fit_mh_mesh.py` (new, our code, same mhclo fitting as fit_mindfront.py but keeps the obj's faces and UVs as one mesh) fitted the CC0 `cortu_short_messy_hair`
  (832 vertices, 546 faces, diffuse 0.5 MB) to both bodies and bound it to our shape keys; lab option `--mh-hair=hair_messy:short_messy_diff.png` shows it (alpha-scissor material) in place of our hair. Result: it sits on the head
  and follows the body shape keys; it looks like a loose, ragged cap of long thin cards, thin and light (the texture is white/pink: it is a tintable grayscale-ish map, we do not tint it yet) with stray single wisps; our hair
  is a solid 170k-strand mass, much denser and darker, which is what we want for near views. The shell is useful as a far-LOD or as a style we cannot grow (bangs, wisps). Files: assets/models/humans/mh_hair/ (2 glb, 1 png),
  credited in assets/models/humans/CREDITS.md. Next (optional): tint the texture with the lab hair colour, and try toigo_blunt_bob (CC0, 1.5k vertices, three 10 MB textures: downscale first).

### MakeHuman asset packs: the full index (2026-11-23, index page + 4 pack pages read; about 77 packs; remember: licence is per ITEM header, see the Hair 01 warning)
Page for each pack: https://static.makehumancommunity.org/assets/assetpacks/<slug>.html
- System (CC0 per page): `makehuman_system_assets` (267 MB, about 98 items: proxies, eyes, eyebrows, eyelashes, teeth, tongue, hair, clothes, skins), `makehuman_system_poses`, `system_clothes_materials01`,
  `system_hair_materials01` / `02`, `system_eye_materials01` (13 MB, 13 human eye materials by bobby_03, Mindfront, Nyloseth, spamrakuen, WojackOWL), `system_eye_materials02` (non-human). CC-BY: `system_eye_materials03`.
- Skins (CC0 per page): `skins01` natural female (99 MB, 23 items; MargaretToigo, CutOff3D, OnlyTheGhosts, Nyloseth...), `skins02` natural male, `skins03` non-natural.
- Targets (CC0): `ears01`, `nose01`, `cheek01`, `arms01`, `hands01`, `animal01`; CC-BY: `animal02-04` (JALdMIC). Poses (CC0): `poses01-05`.
- Meshes CC0: `eyebrows01`, `eyelashes01` (Mindfront), `hair01`, `bodyparts01/04/05` (horns, nails, beards), `hats01/02`, `glasses01`, `gloves01`, `jewelry01`, `masks01`, `pants01`, `shirts01`, `shoes01`, `skirts01`, `suits01/02/05`,
  `dress01`, `equipment01`, `underwear01/04`. Mesh CC-BY: `hair02/03`, `bodyparts02/03/06`, `dress02/03`, `hats03/04`, `shirts02/03`, `shoes02/03`, `pants02/03`, `suits03/04`, `underwear02/03`, `glasses02`, `jewelry02`, `masks02`, `skirts02`, `equipment02/03`.
- Functional (CC0 per the index): `haireditor`, `visemes01` (Microsoft), `visemes02` (Meta/Oculus), `faceunits01` (ARKit-style face units).
- What could help us next: `ears01`/`nose01`/`cheek01` (face shape targets, our bodies have only 6 shape keys), `skins01/02` (skin textures; we have a flat colour), `faceunits01`/`visemes` (face expressions and lip sync: our face has none),
  `system_eye_materials01` (more eye looks), `bodyparts05` (CC0 beards and moustaches: facial hair), `underwear01`, clothes. Each item's own header must say CC0 before use; targets/skins also need their per-item licence checked.
- Not read: skins02/03 pages, the 73 other pack pages (sizes/authors), the system-assets zips (not downloaded), the Asset Packs FAQ release notes.
- Round 120 (skins02, natural male skins, page says CC0 for all 13 items; 76 MB zip downloaded to the scratchpad only): each skin is a 2048 x 2048 PNG diffuse (Mindfront and Aksel also ship NRM and SPEC maps, 2k each); the
  .mhmat files carry no licence line except `rehmanpolanski_skin_viking_tattoos`, whose header says AGPLv3 (DO NOT USE it); the rest rely on the pack page's per-item table (CC0). The skins use the MakeHuman UV layout, which OUR BODY
  KEEPS: the diffuse maps map straight onto our male body (tested in the lab: `--skin-tex=<absolute png>` loads a png from outside the project into the new `skin_tex` uniform of `shaders/human_skin.gdshader`). Result: a huge step
  from the flat skin colour: toigo_light_skin_male_bronze gives a warm tan, mindfront_skin_male_african_middleage gives pores, creases and colour variation on the forehead and around the eyes (close-ups, front/3-4). NOT added to
  the repo (4 MB each; the licence evidence for most is the page table only): decide with the owner which skins to ship (downscaled to 1k, credited in CREDITS.md). The head-hair scalp tint still works on top of it.
  To do: use the NRM and SPEC maps (normal_texture, roughness from spec), a skin selector in the lab, skins for the female body (skins01: 23 items, 99 MB), check the eyelid/lip region for UV stretching, the hair-root colour vs the skin.
- Round 121 (bodyparts05 beards and moustaches + faceunits01; downloaded beards zip 6.6 MB to the scratchpad only): the page says CC0 for all 5, but the item headers disagree again:
  CC0 per header: rehmanpolanski_beard_viking (6,557 vertices), rehmanpolanski_moustache_viking (1,598), culturalibre_faun_beard (5,218; header "CC-0"). AGPL3 per header (DO NOT USE): wdg_scruffy_beard, grinsegold_beard_sigmund_wip.
  They are clothes-type meshes (mhclo + obj + textures), so tools/blender/fit_mh_mesh.py fits them as is; they are card/shell beards like the hair shells (no strands). Not fitted yet.
  faceunits01 (Mika Suominen, 0.2 MB, "ARKit style faceunits", targets usable standalone): the page states NO licence: do not use until the licence is confirmed (the licence page was not read). Would give us face expressions / lip sync.
  Both site news items "Community services shut down" (2026-10-21) and "moving to discord": the zip mirrors may disappear, so keep any CC0 file we depend on in the repo with its credit.
- Round 122 (beard fitted): `rehmanpolanski_beard_viking` (CC0 per header, 6,557 vertices, 2,841 faces, 1 MB texture) fitted to both bodies with fit_mh_mesh.py and shown in the lab (`--mh-hair=beard_viking:BeardViking.png`).
  It sits on the jaw and cheek and follows the body, but it is a ragged card beard with visible edges, light grey texture (needs tinting by hair colour) and it covers only the sideburn/jaw side in the captures (the front view
  was not checked). Useful as a shape reference for a native strand beard (our HumanHair could grow beard strands from a jaw weight map using this card layout as the guide). Files in assets/models/humans/mh_hair/ (not staged yet), credited.
- Round 123 (haireditor, system_hair_materials01, opengameart): 
  `haireditor` (functional pack, https://files.makehumancommunity.org/functional/haireditor.zip): Tomas Klecer's Blender geometry-nodes `hair.blend` and `fur.blend` template styles (needs an 18 MB geometry-nodes file); NO licence stated on the page: do not use,
  and it is Blender node setups, no use for our native C++ runtime anyway (could only be a visual reference for style shapes).
  `system_hair_materials01` (82 MB, 38 materials, every row CC0, zip name ends _cc0): colour textures for system hair by MargaretToigo (braid01 x10 colours, long_01 x8, short_04 x6), dariush086 (ponytail01 x8), bogdan666 (short_02 x3),
  culturalibre, joepal, MTKnife: textures for the card hairs (not strands), so only useful for the shell-hair comparison; formats not stated, not downloaded.
  OpenGameArt: found only third-party uploads (e.g. "MakeHuman System Assets (Eyes)" CC0, https://opengameart.org/content/makehuman-system-assets-eyes) and the official licence page https://static.makehumancommunity.org/about/license.html:
  core assets are CC0, extras per item (the FAQ says CC0 of the core does NOT cover assets downloaded from the user-contributed repositories: each needs its own licence check, as found). An opengameart upload's licence line must be read per upload.
  Reading of the pack catalogue is now complete enough: remaining useful steps are fitting work, not more reading. The MPFB asset list (MPFB's own downloads) is not read.
- Round 124 (MPFB asset documentation, search only): MPFB's asset pages are https://static.makehumancommunity.org/mpfb/docs/assets.html (concepts), the Asset Packs FAQ https://static.makehumancommunity.org/assets/assetpacks/faq.html and release notes
  (e.g. release_20221122.html: binaries moved host, all packs listed on the Asset Packs index). A pack is just the user-contributed assets zipped for convenience; the MPFB asset downloader fetches single items. They were opened in MPFB2 and MakeHuman
  with a cursory check only, so the per-item licence rule still stands. Nothing to add to our pipeline: the packs I already unzipped are the same data. The reading part of this investigation is finished.
- Hair colour jump between the quiff and the back (user report, round 125): the lit side of a lock that sticks up toward the key light was much brighter than the back mass (wrapped diffuse dot*0.5+0.5). Flattened the wrap to dot*0.25+0.75 in shaders/human_hair.gdshader light(): the jump is smaller, whole head a little brighter and flatter. Still visible a bit at the quiff boundary: next idea is to fade the root-shade term with the strand's distance from the scalp.
- Round 126: hair width 0.1 mm test (user asked). Lowered the clamps to 0.05 mm (native strand_width min and the lab slider). At 0.1 mm (real hair is 0.07 mm) with the same 170k hairs the mass gets see-through: skin shows at the hairline, temple and nape, the edge is a haze of single hairs; 0.8 mm is solid. A real head would need more hairs or each hair a thicker ribbon in screen space (pixel-width minimum in the shader).
- Round 127: hair width 0.4 mm (user choice): solid from behind and 3/4 front (no skin at hairline/temple/nape), finer texture and softer edge than 0.8 mm. Set --hair-set=strand_width:0.0004 in the lab to see it; the default in human_hair_native.cpp is still 0.0008 (not changed yet).
- Round 128 (comparison with Unsplash reference photos viewed in Chrome DevTools, nothing downloaded): missing in ours = lock-level clumps, broad highlights, short fade/taper at sides and nape, layered messy top, crisp single hairs at the edge, warm streaks. Done first: per-lock clump variation in shaders/human_hair.gdshader (varying lock_rand from the guide index CUSTOM0.x: brightness 0.72..1.28, warm/cool shift, and the highlight shift per lock). Visible now as lighter and darker streaks. Next: taper at sides/nape in HumanHair (native), broader highlights.
- Round 129: the back hairline rises with side_trim (back_y += 0.045 * side_trim^2 in human_hair_native.cpp hairline lambda): Fade (1.0) now ends well above the nape with a clear neckline like the reference photos, Dapper (0.75) a little higher. DLL rebuilt. Still to do: stubble/skin gradient below the clipper line, broader highlight bands.
- Round 130 (reference page 'Realistic 3D hair' by Lakshya Digital / Techland Dying Light renders, viewed in Chrome only): pro hair shows warm golden lighter locks between darker ones, big sheets of swept hair with clear highlights, a distinct short clippered patch at the back, flyaway strands on the silhouette. Added to human_hair.gdshader: one lock in five is a lighter, warmer streak (x1.4, 1.28, 1.05) and a wider per-lock brightness range (0.6..1.3). Next: clipper-patch stubble texture, broad highlight sheets, flyaways.
- Round 131: default hair width now 0.4 mm (C++ default and clamp fallback); clippered scalp stubble shows follicle dots (human_hair.gdshader, cap branch); back of Fade/Undercut now reads as a short clippered patch below a clear neckline. Committed after this round.
