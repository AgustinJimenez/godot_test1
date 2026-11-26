# Task 103: cloth simulation for the parametric humans' clothes

Goal (user, 2026-11-26): the villager clothes (task 102: a shirt and trousers cut from the body, `tools/blender/make_clothes.py`) should behave like
cloth: hang, fold and swing with the character, instead of being a fixed shell that only follows the body's shapes. The user asked "are we doing cloth
simulation?" after seeing the gap between a loose sleeve and the arm, then "yes i want, what's the best approach? do we have a physics engine? box3d may
help? ... or check online", and chose the recommendation below.

Rules (as task 102): nothing committed until the user says so (never `project.godot`, `bash.exe.stackdump`, `locked_*.dll.bak`, tressfx `~...TMP`);
one Godot run at a time, windowed runs with override.cfg `no_focus` on screen 1; the stock 4.7.2 console exe for the human labs (tressfx);
`bash scripts/humans_check.sh --render` must stay green.

## Investigation (2026-11-26)

What the project has:
- Physics engine: **Jolt** (`project.godot` `3d/physics_engine="Jolt Physics"`). No soft body is used anywhere.
- A vendored **GPU Cloth Sim** add-on: `addons/godot_gpu_cloth` (upstream https://github.com/alien-life/gpu-cloth-sim, MIT, commit bd917af, v3.0.0,
  imported 2026-07-27, see `UPSTREAM.md`). Position-based dynamics on compute shaders; everything stays on the GPU (positions / normals in storage
  textures read by the render mesh's vertex shader, no per-frame CPU readback). What matters for us:
  - skinned garments: `skeleton` export, the solver reads ARRAY_BONES / ARRAY_WEIGHTS and skins every particle's *attachment target* per substep;
  - a per-vertex cloth weight from a vertex-colour channel (`cloth_weight_channel`): 0 = glued to its skinned target, 1 = free PBD, blends between
    ("tight chest, loose hem on the same garment"); `skin_attach_radius` bounds how far a free particle may leave its target;
  - body colliders from one `body_mesh`: auto-fitted bone capsules, a sphere cloud, or a decimated skinned triangle mesh; `body_collider_thickness`,
    `collider_friction`, a sanitizer that pushes skinned targets out of colliders (no rest jitter);
  - shirt + trousers: `peer_cloth_solvers` (each other's geometry as a collider), optional self-collision.
  - An earlier trial (`tests/manual/outfit_cloth/`, README) on the Quaternius peasant outfit: static fit and a gentle spine twist stable, thigh motion
    destabilised the trousers, invalid RenderingDevice resource errors at quit on Godot 4.6.2 / Metal; never enabled in project.godot.

What was found online:
- **Box3D** (Erin Catto, June 2026, MIT, a Box2D fork extended to 3D, alpha): a rigid-body engine, no cloth or soft bodies found, no Godot integration.
  Not useful for clothes. https://box2d.org/posts/2026/06/announcing-box3d/ , https://github.com/erincatto/box3d
- **Godot SoftBody3D on Jolt**: Godot recommends Jolt for soft bodies; the documented cloth case is a cloak pinned to one bone (BoneAttachment3D) with
  the character in the collision-ignore list. A whole shirt on an animated body is awkward (collides only with physics shapes, pins per node, CPU,
  physics interpolation does not apply to soft bodies). https://docs.godotengine.org/en/stable/tutorials/physics/soft_body.html
- **The usual game recipe**: XPBD distance constraints, a parallel solver (graph colouring / multi-colour Gauss-Seidel: plain Jacobi on the GPU makes
  cloth stretchy), and long-range attachments to the skinned body to stop stretch (Mueller et al. 2012,
  https://matthias-research.github.io/pages/publications/sca2012cloth.pdf ; GPU skirt with XPBD https://sueraywang.github.io/project/xpbdmmd ;
  Velvet CUDA XPBD https://github.com/vitalight/Velvet ). Body proxies (capsules / spheres) quality decides the collision quality.

## Decision (user, 2026-11-26)

Option 1: the vendored GPU cloth add-on on our own garments, tried in the rig lab (an animated character: cloth only matters when it moves).
Rejected for now: SoftBody3D (awkward for full garments, CPU), our own native XPBD solver (most work, close to what the add-on already does),
Box3D (no cloth).

## Plan

1. Rig lab: attach the villager shirt and trousers to the skeleton (`HumanRig.attach_skinned`, as the underwear) so they move with the walk.
2. `make_clothes.py`: a cloth-weight channel in the vertex colour (the add-on reads one channel; R = belt and G = hem are taken: use B or A):
   glued at the shoulders, the upper chest and back, the waistband and the belt; free on the shirt below the chest, the sleeves past the elbow and
   the trouser legs (bounded to a few cm by `skin_attach_radius`).
3. Run the add-on's solver on both pieces: body colliders from the body mesh, the shirt and trousers as peers. Walk pose and a turn.
4. Measure: stability (the trousers at the thighs, the earlier failure), GPU ms per character, errors at quit on Windows / Vulkan; compare captures
   with the static clothes. Then decide: tune and integrate, or fall back to a native solver.

## Progress

- 2026-11-26: task file written; investigation above.
- Step 1 done: the rig lab (`tests/manual/humans/human_rig_lab.gd`) wears the villager clothes by default (`--clothes=underwear` for the old look),
  skinned with `HumanRig.attach_skinned` like the underwear (the underwear is hidden under them). They follow the walk.
- Step 2 done: `make_clothes.py` writes the cloth weight into vertex colour B (R = belt, G = hem): 0 at the shoulders / upper torso / neckband /
  gathered cuffs / waistband / seat, rising to 0.8 at the shirt's hem, 0.15..0.7 down the sleeves (forearm), 0.35 on the thigh to 0.7 down the shin
  (the bound trouser cuff glued again). The solver reports anchored / blend counts (no particle at exactly 1: all "blend").
- Step 3 done: `--cloth` adds a `GPUClothSolver` per garment (channel 2, the body as collider, shirt and trousers peers). Our shader keeps the look:
  `human_clothes.gdshader` has the add-on's substrate hook (`gpu_driven`, positions / normals / welded-index textures, `skel_to_mesh_transform`;
  the pattern stays on the rest position), and a LOCAL PATCH in the vendored add-on accepts any shader that declares those uniforms
  (`_declares_substrate`, noted in `addons/godot_gpu_cloth/UPSTREAM.md`; before it the add-on force-replaced our material).
  Capture: `--cloth` lets the walk play and takes the frame at `--capture-frame=` (150).
  CORRECTION (same day): the "stable walk" first noted here was the plain skinned clothes. The rig lab set `material_override` on the garments and
  the solver puts its material on the mesh's SURFACE (`set_surface_override_material`), which an override hides: the simulation ran unseen
  (found because changing the weights, the damping and the travel gave pixel-identical frames). The lab now clears the override.
- Step 4, cost (1280x900, RTX 4090, one character, uncapped frame time via `--gpu-time`; the viewport's measured GPU time leaves the solver's compute
  out, so it is useless here):

  | body collider | ms a frame | process ms |
  |---|---|---|
  | no cloth | 0.61-0.64 | 2.27 |
  | decimated body mesh, voxel res 48 (3,198 tris) | 14.5 | 16.0 |
  | bone capsules (`auto_collider_lod` 1) | 1.74 | 3.26 |
  | none | 1.39 | 2.67 |
  | none, no shirt-trouser peers | 1.09 | 1.87 |

  The mesh collider costs ~13 ms of CPU a frame (the add-on re-skins it in GDScript every frame): unusable. Bone capsules: ~1.1 ms a character, no
  visible poke-through in the walk. (Voxel res 12 gave only 224 triangles: too coarse; capsules it is.)
- Known: "Attempted to free invalid ID" errors at quit (24 in a run) on Windows / Vulkan too, the add-on's RID cleanup (seen on Metal before).

- With the simulation really drawn (2026-11-26): it does not look right yet. The shoulders and the collar puff out like a cape, the shirt's hem flips
  and shreds at the waist, the trousers hang baggy. Tests: `--cloth-channel=0` (the belt mask: almost everything glued) gives trousers that follow
  the body exactly, so the frame / skinning are right and the trouble is in the free cloth; `--cloth-flip=on|off` (the add-on assumes inward normals,
  ours point out) changes nothing visible. Suspects: the shirt's hem over the trousers' waistband (3.5 cm overlap) and the peer collision there;
  the shoulders are "upper arm" in make_clothes.py and get weight 0.2 (should be 0); too few iterations (4) / substeps (2) for 0.07 m of travel.
  The costs above stand: the solver computed all along.

- Found the puffing (2026-11-26): the add-on pushes every particle's skinned target out of its colliders before it simulates (the "sanitizer"), and
  its auto-fitted bone capsules are round while a torso is oval: radii that reach the chest's width stood out far in front and behind, so even glued
  cloth was pushed out to a cylinder (boxy shoulders, a puffed collar). Shirt: capsules at the 50th percentile radius x 0.8 (they sit inside the body).
  Trousers: the full capsules (percentile 0.85, x 1.0): the legs are round, and with the small ones the shins pushed through the cloth.
  Not the cause: the shirt-trouser peers (on / off identical), the add-on's `flip_normals` (our normals point out; off now).
  Also: the shoulders are glued now (make_clothes.py gave the upper arm 0.2), the hem fully free (1.0), the trousers 0.45 on the thigh to 0.85 down
  the shin, damping 0.985, travel 0.04.
- Result: the shirt hangs and folds and moves with the walk, the trousers are loose with folds at the knees, a few small spots behind the shin show
  skin in some frames. 8 iterations x 4 substeps looked the same as 4 x 2 and cost 4.5 ms a frame instead of 1.72 (no cloth 0.61): 4 x 2 kept,
  about +1.1 ms a character. Lab flags for tuning: `--cloth-iterations= --cloth-substeps= --cloth-travel= --cloth-capsule-percentile=
  --cloth-capsule-scale= --cloth-collider=capsules|mesh|none --cloth-peers=on|off --cloth-channel= --cloth-flip=on|off`.

Next:
- The poke-through spot behind the knee while it bends (the calf's bulge is outside the leg capsule): the trousers' capsules at 1.1x the fitted radius
  (`--cloth-leg-scale=1.1`) do not remove it. Try: the add-on's `cloth_render_offset` (a visual push along the normal) of a few mm on the trousers, or
  a manual collider behind the knee. Also seen from behind: the trouser cuff opens when the leg lifts (its dark inside shows).
- The motion is subtle: the shirt's hem and the trouser legs barely swing. Tune: higher free weights (1.0 at the hem), less damping, more travel,
  a turn / a stop to see the swing.
- Body sliders: the solver reads the garment's base mesh at init (blend shapes are not part of its rest shape): bake the current height / weight /
  muscle into the garment (and the body collider) before the solver starts, and restart it when a slider moves.
- Per character ~1 ms: for a village, simulate only near the camera (a distance LOD: skinned clothes farther away).

- User feedback (2026-11-26): "i don't want the cloth to be closed on the hand parts, i don't see cloth simulation while rotating the character".
  - The sleeves are open again (no gathered cuff); the shader draws a sleeve's whole inside (vertex colour alpha 1 on the sleeves), so a look up a
    loose sleeve sees cloth, not the sky. The torso's inside is still drawn only near its openings (the armpit overlap).
  - Why no simulation was seen while rotating: the user rotates in the BODY lab, which has no cloth simulation (only the rig lab with `--cloth`), and
    in the rig lab the drag turned the camera, which the cloth cannot feel. The rig lab's drag and `--sweep` now turn the body itself: the cloth swings
    (scratchpad GIF sent to the user).
  - Tuning from the turn: open sleeves at 0.85 free sagged off the A-pose arms (skin on top: the shirt's small capsules do not hold them): 0.4 max.
    The hem at 1.0 curled up over the belt and showed the dark inside: 0.6.
- Next: the simulation in the body lab (the editor the user rotates in). It needs a skeleton: load the rigged body hidden (its skeleton, and its mesh
  as the collider), skin the clothes to it, turn it with the visible body; and the slider shapes baked into the garments before the solver starts.

- Body lab (2026-11-26): the simulation runs there now ("Simulate" box by Clothes, on by default; `--cloth=off`). The rigged body is loaded hidden
  at the body's place (skeleton + collider), HumanRig set to the body's shapes, the garments and the collider BAKED to the current shapes
  (`_baked_mesh`), skinned to that skeleton; a slider change restarts it 0.4 s after the slider rests (static clothes shown meanwhile).
- Waist gap found: the trousers' full-size hip capsules pushed the waistband out over the shirt's hem (gone with no body collider). Small capsules
  (50th percentile x 0.8) for both garments, full ones (85th x 1.0) on the shins only, via a LOCAL PATCH `auto_collider_bone_overrides` in the add-on.
- Normals: `flip_normals` must be ON (without it the solver's normals point into the body: the lit shirt was dark, rim light made it look normal,
  bright specks where some pointed out). The earlier "no change" test ran while the simulation was hidden. `cloth_render_offset` 4 mm (needs flip
  on, else it pushes inward) hides the skin poking through behind the shins.
- Nipple / navel artefacts: the simulated POSITIONS there are right (read back, --cloth-dump: < 0.2 mm from rest); the solver's per-particle normals
  (sum of face normals) go wrong where the shell has tiny triangles inherited from the body's dense nipple / navel geometry. Tried without effect:
  100 smoothing passes, a lower floor, merging vertices within 3 mm, unfolding folded faces (reverted). Kept: the clothes shader falls back to the
  triangle's own facing where the simulated normal turns far from it (bright specks gone; soft dimples remain).
  Next: remesh the garments to even ~1 cm triangles in make_clothes.py (no tiny triangles left anywhere).
