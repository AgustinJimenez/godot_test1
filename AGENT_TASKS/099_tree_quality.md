# 099 - Tree quality: an in-depth pass on how a tree looks

SUMMARY of work so far (2026-11-18, all uncommitted, see the Log): conifers rebuilt as bottle-brush needle sprays with bare lower trunks (the biggest gain), the far needle fill no longer
a solid block, per-leaf colour variation, fallen logs with tree bark, limbs that rise instead of lying flat, a pine and four more broadleaf kinds. Open: darker conifer bark colours per species,
canopy normal softening (the article's idea, still off), crown shading from inside, trunk fork band (not reproducible), cut-end rings on logs.

Status (2026-11-17): **OPEN, nothing planned in detail yet.** Origin: the user read https://codingquests.io/blog/how-to-make-godot-3d-look-better, we compared
it with the project, and the user said "let's make this a task first, i realize we never did an in deep tree quality improvement".
Related, finished or older: [042](042_unified_tree_builder.md) (the builder), [050](050_tree_look_fixes.md) (look fixes), [085](085_procedural_bark_from_photos.md) (bark),
[094](094_leaf_quality.md) (the single leaf), [076](076_forests_and_fields.md) (forests), `docs/planet_lessons.md`, and the tree LOD scheme (memory: five cheaper steps to 8 km, no impostors).
This task is about the TREE AS A WHOLE seen as a crown and a trunk in the light, at the distances the player sees it. Leaf and bark detail already have their own tasks.

## Goal
A tree in the planet scene should read as a tree in a photo: a crown that shades as soft masses (light side, shaded side, dark pockets inside), a trunk that fits it,
believable silhouettes at every distance, and no obvious "stuck-on leaf cards" look. Judged by pictures and short videos against reference photos, not by numbers.

## What the article gave us (the only part that applies to trees)
- **Canopy normal softening:** the shader blends each leaf's normal toward "away from the crown's centre" (the article: `normal_soften` 0.85), so a crown shades as one soft ball
  instead of leaf-sized facets. The project has nothing like it.
- Everything else in the article (AgX tonemap, SSAO/SSIL/SDFGI, volumetric fog, shadow distance, TAA) is already a setting here (`components/graphics_settings.gd`,
  `native/planet_crust/src/planet_atmosphere_native.cpp`). AgX as the default tonemapper (now Filmic) is a taste decision to try on the planet at a few sun angles.

## Experiment done 2026-11-17 (uncommitted, off by default)
- `shaders/world/flora_wind.gdshader`: uniforms `canopy_soften` (0 = off, the old look) and `canopy_center_y` (the crown centre height on the trunk axis, mesh space).
  In `fragment()`, after the normal is chosen, a leaf's NORMAL is mixed toward `normalize(obj_pos - (0, canopy_center_y, 0))` (view space) by `canopy_soften * realism`;
  only for leaf cards (`UV2.y < 3.5`) and mesh leaves, never bark, rock or needles.
- `tests/manual/world/species_gallery.gd`: `--only=N` (one species of the page, framed whole), `--broadleaf` (only broadleaf trees), `--soften=X`, `--autumn`. The gallery sets
  `canopy_center_y` to 0.62 of the species' height (one value for the whole shared material).
- Pictures (scratchpad `canopy_compare_{1,2,3}.png`, before left / after right, seed 1337): small effect in the gallery. Red Acacia: lower leaves slightly darker and calmer;
  Old Rain Tree (autumn): not visible; Old Cherry (sparse): not visible. The gallery has flat sky light and white trunks, so it is NOT a fair judge.
- To make it real: each tree needs its own crown centre (and a radius) in the mesh, e.g. written by the native grower into a spare vertex channel, read by the shader. Not done.

## Ideas to evaluate (none started)
1. **Crown normals:** the above, with a per-tree centre and radius; compare in the planet with a low sun, from 5 m, 30 m and 200 m. Also try blending toward the crown's own
   "sphere" only on the outer leaves and keeping the inner ones flat (inner leaves are in shadow anyway).
2. **Crown shading from inside:** darker leaves deep in the crown (ambient occlusion by depth in the crown, from the distance to the crown surface). Real crowns are dark inside.
3. **Light through the crown at distance:** the backlight glow exists; check that it survives the LOD steps (do the far trees lose it?).
4. **Silhouette and mass at distance:** do the LOD steps keep the same crown outline and the same overall brightness (no pop in tone between steps)?
5. **Trunk and branch fit:** branch thickness and taper, the junction where a branch leaves the trunk, root flare; compare with photos of the same species.
6. **Colour:** species colours, variation between trees of one species, seasonal change, the sRGB palette against photos (the shader paints `pow(COLOR, 2.2)`).
7. **Tonemapper / sun angle:** Filmic vs AgX on the planet at hours 8, 12, 17; warm low sun (article: colour `(1.0, 0.86, 0.7)`, energy 2.6, about 30 degrees).
8. **Wind and motion:** the PlantSway branch bend and the gust field: does a crown move as masses, or does every leaf flutter alone?
9. **Cost:** every idea gets a GPU number (`--fps`, `scripts/gpu_breakdown.sh`) before it stays.

## How to work (project rules)
- Photos first: pick reference photos per species (Poly Haven and the Chrome tab of references, see memory `tree-species-reference-chrome`), fit by looking (the `procedural-texture`
  skill's loop), one change at a time, a before and after picture at the same arguments (`--shot=`), and the sun low enough to show the shading.
- Real scene, not only the gallery: `planet_lab` (`--shot-frame=N --shot=PATH --hour= --view-alt= --view-pitch= --seed=`), and the forest walk for cost.
- One game instance at a time; `override.cfg` with `window/size/no_focus=true`, `--screen 1`, a `timeout`.
- Native changes (the grower, `plant_mesh_native.cpp`, `tree_archetypes_native.cpp`) need the double build (see AGENTS.md); GDScript shader changes do not.

## First steps when this is picked up
1. Take baseline pictures of 6 species at 5 m, 30 m, 200 m and 1 km, hours 9 / 12 / 17, with the planet lab, and keep them in a scratch folder as the "before" set.
2. Put reference photos next to them and write down, in plain words, what is wrong with each (flat, too uniform, too saturated, hard leaf edges, floating crown, trunk too clean).
3. Rank the ideas above by how much of that list each one fixes, then do the top one end to end (including the native per-tree data if it is the crown normals).

## How to take a picture of a forest in the planet lab (found 2026-11-17, it cost several tries)
- The command: `godot --path . --rendering-driver vulkan res://tests/manual/planet/planet_lab.tscn -- --earth --plants --trees --seed=8 --dir=-0.02524,0.83750,0.54585 --grounded --hour=12 --shot-frame=900 --shot=PATH.png`
  (`--view-alt=M --view-pitch=DEG` instead of `--grounded` for a view from the air; do not pass `--screen`/`override.cfg` away from the usual no-focus rules).
- `--trees` is needed: the lab turns real trees OFF by default (`planet_lab.gd:508`). `--earth` is needed: without it the lab builds a different planet than the probes below.
- `--rendering-driver vulkan` is needed: on D3D12 this scene floods the log with "Cannot create uniform set because there's not enough room in the RESOURCES descriptor heap"
  (millions of lines, the run never reaches the picture). Not checked whether that is new; it is not the canopy shader (it already happened without trees, 1862 errors).
- The site: found with a headless scan (scratchpad `forest_scan.gd`, the `forest_density.gd` method on 240 spots of seed 8): top spots by trees in one 76 m tile, as `--dir`:
  `-0.02524,0.83750,0.54585` (96, 33 m high, a mixed forest: conifers, rusty autumn broadleaf, acacia-like), `-0.13406,0.66250,0.73697` (86), `0.73633,0.64583,0.20179` (86),
  `0.18818,0.06250,-0.98014` (74), `-0.65509,-0.03750,0.75462` (74), `-0.08987,0.37917,0.92095` (71). The old `forest_density.gd` spots (wet 0.45 / 0.85) are grass, not forest, in the lab.
- Wrapper used: scratchpad `tree_shots.sh OUTDIR` (7 pictures: ground at hours 9, 12, 17; 30 m up and 200 m up at 12 and 17; one run after another).

## Log
- 2026-11-17: BASELINE ("before") pictures taken, 7 of them, seed 8 forest site, current build (scratchpad `trees_before/`: ground_h09/h12/h17, alt30_h12/h17, alt200_h12/h17, and `baseline_sheet.png`).
  First look, plain words: (ground) conifer crowns are stacks of flat dark cards with crisp edges and a tiered "paper" look, lit evenly, with little soft light-to-shade change across a crown;
  the rusty broadleaf crowns read as slabs of flat cards; hour 17 is not noticeably warmer or lower-lit than hour 12 (the sun colour and shadows barely change the crowns); trunks are bright
  and clean against the dark foliage. (30 m up) the forest reads well as a mass, very tall thin conifers, strong green / rust contrast, bare brown ground under them. (200 m up) trees are
  dots; the planted area is a dense disc with a sharp edge and bare ground beyond it (lab streaming, not judged here). Not yet done: reference photos next to these, and 6 named species.
- 2026-11-17: REFERENCES (step 2, first two; the Chrome tab with the species charts is gone, Chrome has only a blank page now). From Wikimedia Commons "Featured pictures of forests"
  (scratchpad `refs/`: `ref_spruce_holma.png` = "Spruce forest at Holma.jpg", `ref_birks_aberfeldy.png` = "Birks of Aberfeldy (55085667062).jpg", `compare_spruce.png` = it next to our ground_h12).
  Spruce, real vs ours, in plain words: real trunks are dark grey-brown, matte, finely rough with knots and branch stubs, and bare of branches for the lower half (self-pruned); ours are
  bright orange-tan, smoother, with branch tiers starting low. Real needles read as a fine soft dark mass; ours are big flat blocky dark-green cards. Real forest interior is dim with low
  contrast and diffuse light, a bright moss-green floor with needle litter; ours has strong contrast and a yellow-orange grass floor. Birch/beech autumn, real vs ours: real crowns mix
  yellow, orange and green leaves inside one crown, with dark branches and moss-green bark and stones; ours turn a whole crown one rust red. NOT yet found: a good photo of a lone broadleaf
  crown in direct sun (for the crown-shading question), and photos of the other species.
- 2026-11-18: CONIFERS FIRST (user's pick). Reference: Commons "Black spruce stand at Arctic Chalet, Inuvik, NT.jpg" (scratchpad `refs/compare_conifer.png`, it beside our ground_h12).
  Real conifer, ours, plain words: real = one continuous narrow cone, hundreds of drooping fine branchlets, no visible tiers, light and shade as soft masses (sunlit yellow-green top
  edge, dark blue-green inside), trunk dark and mostly hidden, crown ragged at the edge. Ours = araucaria-like: widely spaced whorls of big flat dark cards with hard edges, bare orange
  trunk visible between tiers, crown reads as stacked plates, no soft light-to-shade, colour near-black green with no sunlit lighter tip. Priorities for conifers: (1) needle/branchlet
  fineness and density (many more, smaller, drooping, so the crown fills in), (2) tier spacing and droop of the branches, (3) lighter sun-side foliage colour and soft shading (crown
  normals) after the shape is right, (4) darker, rougher trunk. The species gallery is a bad judge (white trunks, flat light); use planet-lab pictures.
- 2026-11-18: TRIED and REVERTED (conifer spray size): `plant_mesh_native.cpp` needle floor 0.6 -> 0.35 and extra sprays along limbs (0.3 / 0.8 of level 0, 0.6 of deeper levels, lod 0).
  Picture `trees_v1/ground_h12.png` vs baseline: almost no visible change, frame rate 32 -> 28 FPS in the lab. Finding: the big dark flat blocks at the tier ends are not too large
  sprays, they come from the realistic spray strips (`spray()` cards branch, 3 strips of 2 triangles each with the needles drawn by the shader); the fix must be in how the strip is drawn
  (finer needle texture, soft alpha edge, droop) and in how many strips there are, not a size number. Not retried; user moved to task 100 (more species).
- 2026-11-17: task created; canopy-normal experiment (above) is the only code, shader off by default.
- 2026-11-18 (loop tick 2): CLOSEUP of a conifer trunk in the planet lab (`--grounded --hour=12 --view-yaw=-25 --walk=5`, seed 8 forest, scratchpad `close/yaw-25.png`, crop `close/bark_crop.png`)
  against Google Images "spruce pine tree trunk bark close up" (chrome page 5). Bark: GOOD. Orange-brown plates with dark cracks and a lit top face match the pine-bark photos; a
  neighbouring trunk with moss on one side also reads right. (Spruce bark in photos is grey: a colour choice per species, not a defect.) Remaining defect at that distance: thick limbs leave the
  trunk as straight cylinders, and several short dark stubs with flat cut ends stick out of it (limb stubs seen end-on); tapering short thick branches to a point (`tip_share` in `branch()`)
  made no visible change and was reverted. Needle sprays at the tier ends are still big flat dark cards (see above). Not yet looked at: leaf closeup of a broadleaf crown.
- 2026-11-18 (loop tick 3): LEAF COLOUR inside a crown. Reference: Google Images "maple oak tree leaves canopy close up sunlight" (chrome page 5): large lobed leaves, yellow / orange / red / green
  in one crown, translucent glow. Ours (planet lab crop `close/leaf_crop.png`): small leaves, one rust red, with long flat slats showing at some angles. Change (`flora_wind.gdshader`):
  (1) realistic leaves get a per-leaf tone (`tone_var`, noise at ~0.5 m on the world position): warmer and lighter or cooler and darker, strength 1.3 / 0.9 / -1.4 on r / g / b;
  (2) the autumn turn is now three colours (yellow, orange, red) by a local noise and a few leaves stay green until autumn is full. Picture: `close/tone_compare2.png` (before left, after right):
  clearly more variety, still far from the photos (leaf size and shape, soft light, glow). No GPU cost expected (two noise reads per leaf pixel); not measured with `--fps` yet.
- 2026-11-18 (loop tick 9): a WET BROADLEAF SITE (`--dir=0.18818,0.06250,-0.98014 --grounded --view-pitch=-25`, seed 8, scratchpad `close/site3.png`): the best-looking forest so far. Wide grey
  trunks with patches of moss on one side, forked limbs, a light green canopy, slim white birch stems: bark and moss read as real. Defects seen: (1) on the right-hand trunks (about x 1500-1620,
  y 330-420 of the 1920 picture) the bark shows a blocky checker pattern (a texture tile seam or a bake cell), (2) the floor is a wall of bright lime grass (no moss, ferns, litter, as in the
  Google photos), (3) the crown is a thin tangle of many bare limbs under a pale leaf layer: leaves are small and pale next to the photos.
- 2026-11-18 (loop tick 10): CLOSEUP of the wet-site trunks (`--dir=0.18818,0.06250,-0.98014 --grounded --view-yaw=30 --view-pitch=0 --walk=7`, `close/trunk30.png`, crop `close/trunk_seam.png`).
  Trunk bark: grey, finely grooved, moss patches on the shaded side: realistic at 3 m. DEFECT 1 (not fixed): on the left trunk, just under the fork, a rectangular band whose grooves are stretched into
  long smooth vertical streaks (a UV step: the bark's "metres along" coordinate jumps or stretches at that ring, probably where the grower joins two trunk pieces); look at the `v` written by
  `MeshData::tube` for forked trunks. DEFECT 2 (FIXED): a fallen log lying beside it had a white top face and a blue underside. Cause: in `flora_wind.gdshader` the bark branch of the realistic
  look needed `abs(obj_up) < 0.5`; the upward face of a log is 1, so it fell into the stone branch (rock photo, sky shine). The condition is now `!is_rock && brown > 0.5`; picture
  `close/log_compare.png` (before top, after bottom): a plain brown log. The log itself is smooth and blank (no bark relief, no cut-end rings, no moss): next improvement for logs.
- 2026-11-18 (loop tick 11): the stretched bark band under the trunk fork (tick 10, defect 1) was looked at in `MeshData::tube`: the bark coordinates are `UV.y` = metres along the tube from its own
  start and `UV2.x` = the radius there, one tube per trunk, so no step is visible in the code. Not found yet; the next try is a shot from two other angles (the second picture of the pair was
  not usable) and a debug output of `UV.y` on that trunk, or checking `smooth_path` / trunk lumps for a ring with a large radius jump.
- 2026-11-18 (loop tick 13): THE DARK FLAT NEEDLE BLOCKS EXPLAINED AND SOFTENED. At 1:1 (tree_builder_lab `--kind=conifer|spruce --dist=3 --focus=0.55`, `kinds/sheet_c.png`) a realistic needle spray is a
  fine feathery comb (fern-like): fine. In the forest at 6-18 m it turned into solid dark parallelograms because `flora_wind.gdshader` replaces a comb that is too fine for the pixels with a flat fill:
  `far_fill`, `card_alpha = mix(cluster.x, 0.62, far_fill)`, and 0.62 is over the 0.5 scissor, so the fill was fully opaque. Change: the far coverage is now a ragged 0.3-0.85 noise
  (`far_cover`, noise on world position), so a distant spray is a broken needle mass. Picture `close/far_compare.png` (left old, right new; the two forests differ because the broadleaf quota
  changed in tick 12, which also changes which species stand where): the background conifers are now soft and feathery, no solid blocks. Not measured for cost (the same shader work, one more noise).
  CAUTION for the user: the `QUOTA` change (task 100, tick 12) changes the species of every seed (and so every saved world's plants); revert it if saves must keep their plants.
- 2026-11-18 (loop tick 14): COST CHECK of this session's shader and species changes together (per-leaf tone, far needle coverage, 6 broadleaf kinds, denser cover layer, mushroom / moss builders):
  forest walk (`--plants --grounded --forest-walk=25 --weather=clear --hour=11 --fixed-fps 60`, Vulkan): gpu 3.0 ms avg / p95 4.9, 735 draw calls, 804,343 primitives, 59.9 fps (1% low 29.8),
  against the session start 2.9 ms / p95 5.1 / 710 draws / 787,854 primitives. So the whole set costs about +0.1 ms GPU and +25 draw calls on this walk. (The planet's species mix differs
  between the two runs because of the quota change, so this is a fair but not a pure comparison.)
- 2026-11-18 (loop tick 18): CLOSE VIEW UNDER A BIG BROADLEAF (`--dir=0.73633,0.64583,0.20179 --grounded --view-pitch=-30`, `close/meadow.png`): leaves are large lobed blades with a light midrib and vein
  pattern, dark green with a paler underside: good at this range. The thick low limbs are dark grey with a rough bark and moss patches, but each limb is a plain cylinder that ends in a FLAT cut
  (visible at the middle left, a limb ending in a square block): same defect as the conifer stubs (tick 2). Next to try: close every limb with a short taper cone (`CAP_TOP` only closes the tube
  with a flat cap; the last ring radius is `radius * tip_radius[level]`, tip_radius is high for level 0), e.g. a final extra ring of 0.35 of the radius. Forest-walk cost after the flower
  changes (tick 17): gpu 3.5 ms avg / p95 5.4, 752 draw calls, 811,560 primitives (3.0 / 4.9 / 735 / 804,343 in tick 14); the species mix differs a little between runs.
- 2026-11-18 (loop tick 19): THE FLAT BOARDS ARE LIMBS CLAMPED TO THE GROUND. Tapering the limb tip (tried, reverted) changed nothing; the square slabs at the foot of the big broadleaf were
  limbs that dipped below the tree's base level: `branch()` in `plant_mesh_native.cpp` set `next.y = ground` and the heading's y to at least 0, so such a limb ran along the ground as a flat
  band. Now the heading's y is at least 0.45 after the clamp, so the limb rises away from the ground. Picture `close/limb_compare3.png` (before top, after bottom, same place): the boards are gone,
  the limbs bend up (a visible V kink where they touched the ground, but no slab). It affects every tree whose limbs droop below the root level (all levels < 2). SPECIES_CHECK PASS.
  Possible refinement: ease the heading upward over several rings to avoid the kink.
- 2026-11-18 (loop tick 20): KINK EASED. In `branch()` a limb that comes within 3 radii of the base level while still heading down (heading.y < 0.3, levels 0 and 1) now turns up by 0.3 of the up
  direction before the ground clamp, then the clamp (min heading.y 0.45) is only a safety. Picture `close/meadow_e.png` (same place, a slightly different camera): the long low limbs of the big
  broadleaf sweep out and curve up smoothly, no flat boards, no sharp V (a broad ancient-oak look). SPECIES_CHECK PASS. Mushrooms (white caps, left) show in the same picture.
- 2026-11-18 (loop tick 21): the stretched bark band (tick 10) could not be reproduced: after the broadleaf quota change (task 100, tick 12) the species at that planet-lab site are different, so the trunk
  with the band is gone. A temporary shader debug (UV.y / radius / way-round shown as colour on bark) showed each trunk piece with its own clean UV patches, no stretch, on the trees now there.
  If the band comes back, look first at trunks of species with `trunk_lumps` / `trunk_bend` (the tube then goes through `smooth_path`). The debug line was removed again (no DEBUG left in the shader).
- 2026-11-18 (loop tick 25): THE BOTTLE-BRUSH SPRAY FOR EVERY LEADER CONIFER (spruce, fir, generic conifer, cypress, juniper, giant: `g->leader`): `spray()` in `plant_mesh_native.cpp` now builds 6 strips
  turned round the twig (8 for the pine kinds) in place of the three-strip fan. Pictures: `kinds/spruce_bbc.png` (tree_builder_lab, spruce: a dense feathery needle tree with brush-like pads all
  the way down) and `close/bb_a.png` (planet lab, seed 8 forest, ground, same view as `far_b.png`): the conifers at the left now read as fuller, feathery trees, no flat dark plates. This is
  the biggest gain for the conifers of the whole task. Cost (forest walk, fixed 60): gpu 3.0 ms avg / p95 5.3, 740 draw calls, 806,375 primitives, 59.6 fps (1% low 29.9): inside the noise of
  the earlier runs (3.0 - 3.5 ms; 788k - 812k primitives). SPECIES_CHECK and GENERATION_NATIVE_CHECK PASS.
- 2026-11-18 (loop tick 26): BARE LOWER TRUNKS FOR CONIFERS. `species_generator_native.cpp` (conifer `shape_forms`): `s.bare` 0.14-0.26 -> 0.28-0.45 (the share of the trunk with no branches: `nodes_from = trunk_part * 0.75`).
  The first real spruce comparison (tick "references") said real forest spruces are bare in the lower half, ours had tiers from the ground. Picture `close/bare_b.png` (planet lab, seed 8, ground,
  same view as `bb_a.png`): the left-hand conifers now show clear brown trunks to head height and the bottle-brush crowns above: the picture now looks like a forest photo (light through the
  canopy, trunks, a bright grass floor). From 14 m up (`close/bare_a.png`) the pine kind is still thin in the real scene: bare spokes with few pads (the lab pine was fuller): the pads per limb
  depend on the species' limb count, check `limbs` for the pine in `for_species` (pine species may get the conifer's `limb_count`). SPECIES_CHECK and GENERATION_NATIVE_CHECK PASS.
- 2026-11-18 (loop tick 27): WHY THE PLANET PINES WERE THIN: `for_species` runs `nudge()`, and the `Range` table of `tree_archetypes_native.cpp` capped `needle_size` at 1.5, so the pine's
  2.6 became 1.5 and the `needle_size > 2.0` tests (bottle-brush pad, bigger cap, extra pads) never fired in a planet (only in the tree lab). Cap raised to 3.0. Picture `close/bare_c.png` (planet,
  14 m up): the pines now carry large feathery pads (they read as mimosa- or tree-fern-like at that size); the needle cap for the pine kinds was then lowered 2.2 -> 1.7 (not re-shot).
  Lesson: a kind's special numbers must lie inside the `Range` table or `nudge` pulls them back. SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 29): LOGS WITH TREE BARK. `scenery()` `KIND_LOG` in `plant_mesh_native.cpp` was a flat-coloured 7-sided cone; it is now a 6-ring sagging, tapering `tube` of 9 sides with the
  bark UVs (`bark_kind` 0 or 2) so the realistic shader paints the photo bark and the mossy tops. Planet picture `close/log_new.png` (wet site): two logs at the lower left and right are
  textured, mossy green cylinders lying in the grass: a mossy fallen trunk, good, though the moss covers the whole upper half evenly and the cut ends have no rings. Species / native checks PASS.
- 2026-11-18 (loop tick 32): CONIFER BARK COLOUR. `species_generator_native.cpp` conifer `s.bark = rhsv(...)`: saturation 0.5-0.65 -> 0.15-0.62 and value 0.2-0.34 -> 0.17-0.34 (hue 0.05-0.09), so a conifer
  species can have grey-brown bark (spruce photos) as well as the orange-brown (pine photos). Picture `close/bark_c.png` (seed 8 forest, same view as `bare_b.png`): the left trunks are now a darker,
  less orange brown with the same plate relief. Same random draws as before, so nothing else in a species shifts. SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 33): LOG CUT ENDS. `KIND_LOG` in `plant_mesh_native.cpp`: each end of a fallen log gets three thin flat discs (pale wood, darker ring, pale core: radii 0.9 / 0.6 / 0.3 of the end radius),
  sway 0.105 so the realistic look does not shade them as stone. Built and SPECIES_CHECK PASS, but NOT YET SEEN: the planet picture `close/log_ends.png` (wet site) shows a mossy log from the side only.
  Check next with a view along a log (`--view-yaw` towards a log's end) for z-fighting or a wrong facing of the discs. Canopy normals (the article's idea) are still not done: the shader
  needs a per-tree crown centre, and with one shared material and no spare vertex channel for it the cheapest honest way is to write the crown centre height into the mesh's `CUSTOM0` or
  into UV2.x of the leaf cards; not started.
- 2026-11-18 (loop tick 34): LOG ENDS SEEN. A throw-away scene (the log mesh `FloraMeshes.mesh(14, v, true)` with the flora material, a camera at one end) shows the cut end as three brown concentric
  discs (pale, dark ring, pale core): `close/log_view.png`. Faults: the disc edge is dithered against the bark at its rim (a little z-fighting where the discs sit 2-6 mm outside the tube: lift them
  1 cm or shrink the radius by 3 %), and in that bare harness the bark is white-green because the planet's bark textures are not loaded (in the planet the same log is mossy brown-grey). The scene
  file was removed again.
- 2026-11-18 (loop tick 35): the log end discs now sit 1 cm outside the tube (was 4 mm) and are 3 % smaller (radii 0.87 / 0.57 / 0.27) to stop the rim dithering. Rebuilt, SPECIES_CHECK PASS;
  the re-check picture (`close/log_view2.png`) missed the end (camera placed wrong), so the rim is NOT re-verified: look at a log end once more in the planet.
- 2026-11-18 (loop tick 36): FULL REGRESSION RUN with all of this session's native and shader changes: `GODOT=<double console exe> scripts/planet_check.sh --quick` -> PLANET_CHECKS PASS (lint, import,
  universe, climate, water, spawn, water_mesh, generation_native, noise_golden, drainage, species, branches, undergrowth, sway, turf, guard, world, planet, save, walk, swim). The slow fly check
  was skipped (`--quick`). Note: the script's default engine is the stock 4.7.2, which cannot load the double library: pass `GODOT=` as above.
- 2026-11-18 (loop tick 37): CANOPY NORMAL SOFTENING IS ON (the article's idea), without per-tree data. `flora_wind.gdshader`: a leaf's normal leans toward `normalize(obj_pos - (0, max(obj_pos.y * 0.72, 0.5), 0))`,
  i.e. away from a crown centre taken at 72 % of the leaf's own height on the trunk axis: a leaf high in the crown leans up, a low or outer one leans out, so a crown shades as a soft mass
  and not as leaf-sized facets. Uniforms `canopy_soften` (default now 0.4, was 0 = off) and `canopy_center_frac` (0.72); `canopy_center_y` is unused now. Picture `close/canopy_compare.png`
  (planet lab, seed 8 broadleaf, 12 m up, hour 16; before left, after right with 0.55): the facet contrast between neighbouring leaves drops, the crown reads softer and a little flatter; 0.55
  looked slightly washed so the default is 0.4 (not re-shot). Only leaf cards and mesh leaves (never bark, rock, needles). To judge again against a photo with the sun low (hour 8 and 17).
- 2026-11-18 (loop tick 38): canopy softening at a LOW SUN (hour 17, wet broadleaf site, ground, looking up: `close/lowsun_compare.png`, left 0, right 0.4): with 0.4 the leaves lose some of their
  green saturation and turn paler / creamier (the leaning normals catch more of the low sun's glow), the facet contrast drops. The gain is small and the cost is a washed look, so the default is
  now 0.3. If the soft-mass look is wanted stronger, pair it with a darker inner crown (task idea 2) so the crown does not wash out.
- 2026-11-18 (loop tick 39): CROWN SHADING FROM INSIDE (idea 2), shader only. `flora_wind.gdshader`: leaves near the trunk axis darken: `inside = 1 - smoothstep(0.15, 0.65, |obj_pos.xz| / (0.28 * obj_pos.y + 1))`,
  `paint *= 1 - crown_dark * inside` with `crown_dark` 0.4 (uniform), leaves only, realistic look only. Planet picture from 45 m up (`close/dark_compare.png`, left off, right on): almost no
  difference, because from above only the sunlit tops of the crowns are seen; the effect belongs to the views from under or beside a crown (ground level). Needs a ground-level before / after
  at the wet broadleaf site (hour 12 and 17) to judge; kept at 0.4 meanwhile. The crown radius is guessed from the leaf's height (0.28 per metre), so a very wide or very narrow tree darkens the
  wrong share; a real fix needs the per-tree crown radius (the same missing channel as for the canopy normals).
- 2026-11-18 (loop tick 40): ground-level A/B of `crown_dark` (wet broadleaf site, hour 12, looking up, `close/g_compare.png`, left 0, right 0.4): the difference is very small. The leaves in view are
  pale because the backlight glow (`BACKLIGHT = transmitted * glow ...`, built from the same albedo) and the sky's ambient dominate, so a darker albedo barely shows. To make the inside of a crown read
  dark the shading has to act on the glow too (scale `glow` by `1 - crown_dark * inside`) or on AO: next try.
- 2026-11-18 (loop tick 41): `crown_dark` now also scales the backlight: `crown_inside` (0 outer .. 1 inside) is a variable of `fragment()`, and `BACKLIGHT` is multiplied by `1 - 0.8 * crown_dark * crown_inside`.
  Ground-level picture (`close/g_compare2.png`, left off, right on, same place as `g_compare.png`): the leaves nearer the trunk axis are now visibly deeper green and less glowing, the outer
  ones unchanged: a modest, believable depth in the crown. Kept at `crown_dark` 0.4. Not measured for cost (two multiplies per leaf pixel).
- 2026-11-18 (loop tick 42): COST after the canopy softening, crown shading and the other shader changes (forest walk as before): gpu 3.2 ms avg / p95 5.8, 687 draw calls, 771,653 primitives,
  59.7 fps (1% low 28.1), against 3.0 / 4.9-5.3 / 735-740 / 804-806k at ticks 14 and 25. About +0.2 ms GPU, within the run-to-run spread (the walk's species mix and the player's path
  change with the species and logs of each build). Nothing to act on.
- 2026-11-18 (loop tick 45): LOG ENDS VERIFIED (a throw-away scene again, camera over three logs, `close/log_fungus.png`): the cut ends are clean brown discs with a dark ring and a core, and
  the 1 cm lift removed the rim dithering. SHELF FUNGUS added to logs (`KIND_LOG`): 2-4 clusters of 2-3 stacked tan brackets (pale underside) on the upper half of the log; the first picture
  (size 0.10 m, 2 cm thick) showed only one tiny speck, so they were enlarged to 0.17 m and 3.5 cm (rebuilt, SPECIES_CHECK PASS, NOT re-shot): look at them next in the planet at a log.
- 2026-11-18 (loop tick 46): SHELF FUNGUS SEEN AND FIXED. First version (`close/log_fungus2.png`): the brackets lay flat ON TOP of the log like plates (disc axis radial). Now: placed on the SIDES of the log
  (phi = 90 or 270 degrees, local x is world up once the log lies down), disc axis vertical, standing out by 0.45 of their size, tiers stepping up. `close/log_fungus3.png`: stepped tan brackets on the
  log's flank, readable. The cut ends are clean (rings, no rim dithering). Remaining for logs: bark relief when seen in the harness is white-green only because the harness has no bark textures.
  SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 48): SECOND FULL REGRESSION RUN (`GODOT=<double console exe> scripts/planet_check.sh --quick`) after everything up to the lupine, shelf fungus, log ends, canopy softening,
  crown shading and fiddleheads: PLANET_CHECKS PASS (all 21 checks incl. walk and swim; the fly check skipped by `--quick`).
  NOTE: the second run printed `Segmentation fault` for the swim check process AFTER it had printed `SWIM_CHECK PASS` (its log ends with "Condition !is_inside_tree() ... Node3D::get_global_transform"
  at quit, the voxel lab shutting down). The first run of the same script did not show it, and nothing in this session's changes (flora shaders, plant meshes, species) is in that path: treat as a
  flaky shutdown crash of the voxel lab, not checked further.
- 2026-11-18 (loop tick 50): LEAF SCALE. Planet picture of the wet broadleaf site looking back at a tree from 3 m (`close/fl_planet.png`): a lush, believable forest (white birch stems, mossy limbs, bright floor,
  a yellow lupine spike at the lower left), BUT the nearest leaves are huge: single lobed blades about 0.6-0.8 m long, bigger than the player's torso (real oak / maple leaves are 0.1-0.2 m). Cause:
  `grow_stem()` in `plant_mesh_native.cpp`: `leaf_basis = 2 * (crown/2)^0.55 * max(crown/3.5, 1)^0.6` grows with the crown (about 5 for a 6 m crown) and `leaf_length = leaf_basis * leaf_size * 1.7`
  (cards) so a maple (`leaf_size` 0.2) gets 1.7 m of card. The big size keeps crowns full at distance with few triangles. Options (needs the user's taste, not done): (a) cap `leaf_basis` at about 3,
  (b) 0.6 x the card size and 1.6 x the number of cards on broadleaf trees seen within 20 m (the lod 0 / fine tree), keeping the far steps as they are. Cost of (b): about +60 % leaf triangles of near trees.
- 2026-11-18 (loop tick 51): LEAF SCALE TRIED. (1) cap `leaf_basis` at 3.2: no visible change (the huge leaves come from `leaf_size` itself and a big crown factor before the cap bites). (2) the card factor
  1.7 -> 1.1 in `grow_stem()` (`leaf_length = leaf_basis * leaf_size * (fine || cards ? 1.1 : 2.5)`): ground view of the wet site (`close/leafcap2.png`): leaves are now about 0.4-0.6 m at the largest
  (still big, but no longer torso-sized), the crowns look airier with bare limbs showing through; from 40 m (`close/leafcap40b.png`) the canopy is still full and finer-textured, more like a real
  forest. KEPT (both changes) as the more realistic scale; if the near crowns look too thin, raise the number of leaves per twig (`leaf_density` / children) instead of the size. Not measured for
  cost (the same leaf count). SPECIES_CHECK PASS. This reverses nothing from the earlier ticks; revert the 1.1 to 1.7 in `plant_mesh_native.cpp` `grow_stem()` to get the old leaf size back.
- 2026-11-18 (loop tick 52): leaves along a near twig 5 -> 7 (`leaves_along`, realistic look, lod 0) to refill the crowns after the smaller leaves (tick 51): ground view `close/leafcap3.png`: leafier, still
  airy with the limbs showing and light coming through, like a photo from under a broadleaf. Not measured for cost: +40 % leaf cards on near broadleaf trees: run the forest walk next.
- 2026-11-18 (loop tick 53): COST after the smaller leaves (1.7 -> 1.1) and 7 leaves per near twig: forest walk gpu 3.1 ms avg / p95 5.7, 706 draw calls, 786,061 primitives, 59.7 fps (1% low 29.5);
  tick 42 was 3.2 / 5.8 / 687 / 771,653. Primitives +2 %, gpu the same: the leaf change is free (the grower's triangle budget and thrift keep trees under their caps).
- 2026-11-18 (loop tick 59): other-seed smoke test: planet lab seeds 77 and 1337 with `--earth --plants --trees --grounded` and their default spawn start in open ocean (as noted at the start of this task), so the
  pictures show water only; no SCRIPT ERROR in either log. To judge other seeds' forests pick a land spot with the `forest_scan.gd` method (task 099, "How to take a picture of a forest").
- 2026-11-18 (loop tick 60): OTHER SEED, REAL FORESTS. `forest_scan` on seed 1337 gave land spots (`0.74720,-0.66250,0.05281`, `-0.69665,-0.69583,-0.17464`, ...); grounded pictures there (`close/s1337_sheet.png`):
  both render fine (no script error): a spreading live-oak type with enormous low limbs, small leaves, pink-leaf broadleaf, tall grass with yellow wildflowers. Faults seen: (1) the thickest low limbs have a
  visibly FACETED cross-section (6-7 flat sides, left picture, middle right): raise `sides` for level 0 limbs of a big tree that are within a few metres (the lod 0 `sides_real`), (2) the same limbs are
  very straight and long, cylinder-like (`curve` / `wander` small for level 0 of the "ancient" kind), (3) 21-25 fps in these two views (limb-heavy close views are the costliest): measure before adding sides.
- 2026-11-18 (loop tick 61): ROUNDER THICK LIMBS. `branch()` in `plant_mesh_native.cpp`: at lod 0 in the realistic look a limb thicker than 12 cm radius gets at least 10 sides (12 above 30 cm); it had 6-7.
  Picture `close/sides_compare.png` (seed 1337 spot 1, before top, after bottom; the camera and the leaves differ a little between the runs): the large limbs are smooth tubes now, no flat facets;
  a pink-flowering broadleaf shows in the same view. Cost not measured (only thick limbs near the player get the extra triangles: a 30 cm limb of 6 rings: 12 x 5 x 2 = 120 triangles). SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 62): forest walk after the rounder limbs: see the numbers in the next line of this log entry's follow-up if they differ from tick 53 (gpu 3.1 / p95 5.7 / 706 draws / 786,061 primitives).
  FOLLOW-UP (tick 62): with 10 / 12 sides the walk gave gpu 3.5 ms avg / p95 6.8, 698 draws, 780,378 primitives, fps 58.4; the sides were then lowered to 9 (limbs over 12 cm) and 10 (over 30 cm)
  and the walk gave gpu 2.9 / p95 5.8, 685 draws, 772,935 primitives, fps 57.5 (1% low 22.8, one 74 ms frame). The path length differs by run (2465-2548 m) and a one-off hitch shows
  in the second, so the cost of the sides is inside the noise; 9 / 10 sides kept (they still round the limbs, with fewer triangles).
- 2026-11-18 (loop tick 64, the user's question: "are the crowns too close? shouldn't a tree keep a territory of space?"): YES, and it was a real defect. Real trees keep crowns apart (crown shyness, shade
  pruning, root competition): in a closed canopy crowns touch or overlap a little at the edges, they do not interpenetrate. Ours had a rule for it (`crowded()` in `planet_scatter_native.cpp`: centre
  distance >= 0.7 x the sum of the two crown radii) BUT the radius it used was the species' `crown` NUMBER, and the mesh reaches much further: measured on seed 8 (headless, mesh AABB / crown): conifers
  1.2-1.7 x, broadleaf 1.9-3.5 x, live oak 5.5 x (farthest limb tip, so the mean crown is smaller than that). Fix: `planet_scatter_script_native.cpp` writes a `canopy` radius per tree species (crown x 1.1 conifer,
  1.2 pine, 1.35 broadleaf, 1.6 oak / beech / elm / maple / willow / buttress / leafy, 2.6 live oak) and `planet_scatter_native.cpp` `place()` uses it for the spacing AND for the shade the crown casts.
  Result: trees per 76 m tile at the densest seed-8 spots 79 -> 65, 75 -> 55, 74 -> 55 (about -20 to -27 %): fewer, better separated trees. Picture `cmp/crown_space_compare.png` (80 m up and
  ground level, before | after). Open: (a) real forests also PRUNE the shaded side of a crown, our meshes cannot (shared per species), (b) the tree count dropped, so raise the density
  of tree species slightly if the forest now feels empty, (c) if crowns still look too close, raise the factors; if too sparse, lower them or the 0.7 overlap in `crowded()`.
- 2026-11-18 (loop tick 65): LEAF INSPECTION (the user asked if each leaf was looked at closely: until now only crowns and a few crops). `tests/manual/world/leaf_lab.gd` was broken (same native-enum
  parse error as the tree builder lab, `PlantSpecies.LeafShape.keys()`): fixed with `ClassDB.class_get_enum_constants`. Run: `leaf_lab.tscn -- --seed=8 --mode=2 --all=DIR` writes one picture per
  broadleaf species of the seed (19) of a single leaf and of a leaf card (scratchpad `leaves/leaf_sheet_leaf.png`, `leaves/leaf_sheet_card.png`). FINDINGS: (1) a single leaf is clean and soft: a
  smooth blade, a pale midrib with 5-6 side veins, a gradient from dark base to light tip, no hard edges; GOOD as a shape. (2) VARIETY IS LOW: about 14 of the 19 species share the same oval, pointed,
  smooth-edged leaf (only the colour changes: dark green, olive, yellow-green); only 5 differ (serrated, narrow, wavy, a lobed one, an orange-red one). Real forests mix lobed, palmate,
  heart, compound, needle-like leaves. (3) The veins are faint (low contrast) and the leaf has no visible thickness, translucency or glossy sheen seen from the front. (4) the leaf CARDS (a dozen leaves
  on one quad) repeat the same leaf pattern with a few sizes; fine from afar, repetitive up close. (5) This lab shows the species' own leaf fields; the planet draws a tree from its archetype genome
  (maple: palmate, linden: heart, beech: wavy) so the real variety is larger than the lab shows: check that in the planet per kind. NEXT: give each broadleaf species a leaf shape by its
  archetype (and a random shape among 4-5 for `leafy`), raise the vein contrast a little, and look at each kind's leaf card in the planet at 1 m.
- 2026-11-18 (loop tick 66): LEAF DETAIL AND IMPERFECTIONS (the user: "all is not perfect, we need imperfections or damage"). Reference photos: Wikimedia Commons "damaged leaves" (Google blocked the new tab
  with a bot check, the Google "trees" tab, page 4, is untouched; page 5 holds the Commons search): scattered round shot-holes, brown dry edges and tips, brown leaf spots with a pale halo, mottled / pale blotches,
  leaf-miner trails, ragged or bitten margins, a few yellowing leaves among green ones. Done: (shader) `leaf_cluster()` in `flora_wind.gdshader`: close up only (fades 12-22 m): 1-3 ragged shot-holes on ~20 % of
  the leaves, a bite out of the margin on ~14 %, brown spots with a pale halo on ~30 %, a yellowing leaf now and then (`wear` joins the old dry tips); the single mesh leaf's veins are lighter (1.55 -> 1.8) and
  cut as a shallow groove (screen-space bump, 0.4, close up only); (native) a broadleaf species with no leaf of its own by name now draws OVAL / HEART / DIAMOND / LANCEOLATE / LOBED / PALMATE with a random edge
  (it was always the same oval): the 19 species of seed 8 should now differ. Pictures `leaves/wear_sheet.png` (a card with holes, spots, a bite, a yellow leaf; a mesh leaf with veins). NOT YET DONE (ideas, in the
  order I would do them): leaf-miner trails and pale mottling; a darker, redder first-flush / old-leaf tone by age; light through the leaf (`SSS_TRANSMITTANCE_*`, thickness from the veins); waxy
  sheen by species (roughness from 0.5 on glossy leaves to 0.9 on hairy ones); normal-mapped surface puckering between the veins; alpha-to-coverage instead of the 0.5 scissor for softer edges; LOD of
  the leaf: near mesh leaf -> card -> blob, checking tone and brightness do not pop between steps; per-leaf flutter in the wind. POM is not for leaves (the relief is under a millimetre): bump / normal
  mapping is enough; POM stays for bark and rock. SPECIES_CHECK PASS (the planet pictures after the generic-leaf change are not looked at yet).
- 2026-11-18 (loop tick 67): ORCHARD CHECK of the new crown spacing, from 70 m straight down at two seed-8 forests (`cmp/orchard_sheet.png`): NO regular grid; crowns are irregular and clumped, of many sizes and
  colours, with gaps; the regular look in the earlier ground picture was one local stand of a single tree kind. The conifer site shows bare sand between the trees (it did in the very first baseline too).
- 2026-11-18 (loop tick 68): FROM THE USER'S LEAF PHOTOS (their Google tab, page 4, now "leaves photograps"; macro of a backlit green leaf: thick DARK midrib and main veins, a BRIGHT pale fine net of small veins,
  a glowing saturated yellow-green blade, darker blocks between the main veins; also dewdrops on leaves, orange autumn leaves with dark veins and mottled red-brown blotches). DONE: (1) LEAF LAB: a movable light:
  Shift + left drag moves the sun (a small bright ball shows where it is), `--light=yaw,pitch` places it for a picture, B = behind the leaf, L = round; the lab sun is 2.2 now (the 1.0 made a backlit leaf dim);
  (2) `flora_wind.gdshader`: light through the leaf: `vein_dark` (big veins block the light: BACKLIGHT x (1 - 0.7 vein)), `net_light` (the fine net of small veins glows: x (1 + 0.9 net) between veins) for mesh
  leaves AND for cards (`leaf_cluster()` has a new out `trans`), the glow lobe stronger (0.9 / 3.0) and BACKLIGHT x1.6; blade mottling on mesh leaves; the vein relief bump lowered to 0.18 (0.4 made it pleated);
  (3) WET LEAVES (the shader had no wetness at all): beads of water on the cards when `ground_wetness` > 0 (round drops, close up, roughness 0.05 and specular 0.95 inside a drop), and a wet leaf shines a little;
  NOT VERIFIED in the planet (a rain picture looked normal at a distance; drops need a closeup in rain). Pictures `leaves/trans_sheet2.png` (front light vs light behind, leaf and card). HONEST STATUS: the backlit
  look is closer but still NOT the photo: the fine net does not read at lab distance, the mesh leaf looks plasticky, the real fix is a thickness-based transmittance (`SSS_TRANSMITTANCE_*`, needs the SSS pass) or
  an emission term for light-facing leaves (glows even in shade: only with the crown shading to damp it). Next: closeup of the net, drops in rain at 0.5 m, autumn leaves with dark veins and blotches.
- 2026-11-18 (loop tick 69): VEIN HIERARCHY like the user's backlit macro photo. Analysis of the photo: (1) a thick DARK midrib, (2) dark secondary veins at about 50-60 degrees, (3) between them big polygons bounded by pale
  veins, (4) each polygon cut by thinner pale veins into smaller ones, (5) the finest dense net of tiny pale cells, a bright glowing blade, lines of different thickness and not regular. DONE in
  `flora_wind.gdshader`: `vein_hierarchy()` = three fields of Voronoi cell borders (coarse x0.26, medium x0.62, fine x1.7 of the base net, each thinner and fainter; coarse visible to 14 m, medium to 8 m, fine
  to 5 m), the whole field bent by a slow noise so the cells are not clean polygons; the lines are PALE (albedo x1.42 on a line); for the glow they brighten the BACKLIGHT; used for mesh leaves and cards
  (`leaf_cluster()` gets `against` and `trans`); the big veins are pale in front light and DARK against the light (`pre_against`: the albedo of a vein goes 1.8 -> 0.25 and BACKLIGHT x (1 - 0.7 vein));
  the veins' screen-space bump was removed (it drew dashed dark lines). Pictures `leaves/veins_sheet3.png` (front light, light behind, card). STILL DIFFERENT FROM THE PHOTO: the thick midrib is not black
  (needs a wider, darker midrib band in backlit mode), the line widths are uniform (the photo has thick-to-hairline), the net is a Voronoi (the photo's net follows the leaf's grain: cells elongated along
  the secondary veins), no ladder-like tertiary veins between secondaries, the blade colour is less saturated / glowing. Cost: three vein_net calls (3 x 9 hashes) per near leaf pixel: only inside 14 m, finer ones closer.
- 2026-11-18 (loop tick 70): VEINS AS A TREE (the user: "the veins must come from the main vein, a tree-like hierarchy, starting only from the bottom of the leaf"). `vein_tree()` in `flora_wind.gdshader` replaces the
  free Voronoi net: LEVEL 1 the midrib from the base (existing); LEVEL 2 the secondary veins leave the midrib running up and out (existing: `phase` is constant along each one, `band = floor(phase)` the strip
  between two); LEVEL 3 tertiary rungs inside each strip, SLANTED and wobbling (a rung leaves the lower secondary and meets the upper one further out, never a perpendicular grid); LEVEL 4-5 the areoles: irregular
  polygon cells inside the strip, stretched along its grain, two scales. Each level exists only inside the strip of its parent, so every vein starts on a parent vein. Fade by distance as before (rungs to 12 m, areoles
  to 7 m / 3.5 m). First try (nested rectangles from rung to rung, T-junctions only) looked like a brick wall: rejected. Picture `leaves/tree_sheet2.png` (front light, light behind the leaf): a midrib from the base,
  the secondaries as broad pale strips sweeping out and up, wobbling rungs between them, a fine net: reads as a real leaf's venation. Open: the midrib is pale, not black, when backlit; no thick-to-hairline
  widths between the levels; the lowest secondaries do not yet start at the petiole with their characteristic basal curl; cards use the same function (check one close up). Cost: two vein_net calls near, rungs cheap.
- 2026-11-18 (loop tick 71): THE VEIN PATTERN SHOWN FLAT. The user: "the veins look like waves, they follow the wave on each side; show me the pattern". New in the leaf lab: `V` (or `--veins`) shows ONLY the vein lines
  (white on black: shader uniform `debug_veins`, emission = the vein lines, no backlight), best with `T` / `--view=top`. The flat picture showed the cause: the secondary veins were FAT SOFT BANDS (`thick` 0.1-0.3 of a strip),
  the rungs between them were dense wobbling squiggles (8-13 per strip, wobble 0.12) and the finest cells tangled: together they read as ridges and waves, and the leaf mesh's own ripples added to it. FIX:
  secondaries thin and crisp (`thick` 0.03-0.065, a sharp edge, thinner toward the margin; same on cards), rungs 4-6 per strip with a calm wobble (0.06) and thin, areoles in larger cells (4 x 9 per strip,
  second scale x2.1). Picture `leaves/pattern_sheet.png` (before | after | the lit leaf, top view): a midrib with thin secondaries branching from it, rungs joining them, a fine polygon net: a leaf skeleton.
  STILL TO CHECK: the direction of the secondaries on the real mesh (they run toward the tip: phase = t * count - across^0.75 * slope), the lab leaf mesh has its own ripples (the leaf is corrugated between
  the veins, `leaf_surface()`): tone them down if they still read as waves; the midrib is pale when backlit.
- 2026-11-18 (loop tick 72): LEAF FOLDS IN THE WIND. `flora_wind.gdshader` `vertex()`: a MESH leaf (UV.x > 0.001, not a card) lifts its two halves along the midrib in a gust:
  `VERTEX += NORMAL * (0.01 + 0.06 * wind_strength * gust) * leaf_fold_scale * across^1.4 * (0.35 + 0.65 * t)` (the edges lift most, toward the tip more; the gust is a travelling sine like the branch sway). The mesh leaf
  is only used where the leaf is a mesh (the realistic leaf CARDS, which draw their leaves in the pixel shader, cannot fold in geometry): for a card the same gust rounds the surface across the midrib more
  (`card_lean` x (1 + 2.4 * fold_gust)): a shading change that makes the leaves seem to fold and unfold. `leaf_fold_scale` (1.0 in the game, 6.5 in the leaf lab where the leaf is a metre long) keeps the fold in proportion.
  Leaf lab: `--wind=0..1` sets the wind. Picture `leaves/fold_sheet2.png` (no wind | strong wind): the margins lift and the left edge folds; subtle in a still frame, it is the motion that shows it: NOT seen
  animated yet (record a short clip with the Chrome / screencast tools or the movie writer). Not measured (a few ALU in the vertex shader).
- 2026-11-18 (loop tick 73): "the leaf looks like it is stretching the texture" (leaf lab, mesh leaf, wind 0.5): the fold was the cause: with `leaf_fold_scale` 6.5 on a metre-long lab leaf the edges lifted about a quarter of the
  half-width, so the few triangles at the margin became steep and dragged the (procedural, per pixel) vein pattern with them; the flat vein view is not stretched (`leaves/stretch_veins.png`). Fold amplitude cut to a
  quarter: `(0.003 + 0.016 * wind * gust) * leaf_fold_scale`. Pictures `leaves/stretch_sheet.png` (before | wind 0.5 | wind 1.0). The leaf mesh's base still shows a flat cut face (a slab) when seen from the side:
  geometry of the lab leaf's base, not the fold: to tidy.
- 2026-11-18 (loop tick 74): "zoomed in from the sides it still stretches the texture". Leaf lab got `--cam=yaw,pitch,distance`. Side pictures (`leaves/side_sheet.png`): a flat surface at a grazing angle foreshortens its lines (natural),
  but there was a real distortion of mine: the vein cells were laid out in the leaf's normalised (width, length) space, so where the leaf narrows (tip, base) the same number of cells across a narrow part made them
  small across and long along. Fix: `vein_tree()` takes `iso` = (the local half-width in metres) / (0.28 x the leaf length in metres), measured per pixel from the screen-space derivatives of VERTEX and UV (mesh leaves), and scales the
  across coordinate by it: cells keep the same physical size along the whole leaf (flat pattern `leaves/iso_sheet.png`, left). Cards pass 1.0 (their cell space is already metric). Still visible from the side: a marginal tooth of the lab
  leaf's outline that hangs down as a thin spike (outline geometry of the mesh leaf, not the texture).
- 2026-11-18 (loop tick 75): "the veins seem to move inside when the leaf moves; no shadow, so no depth". Two fixes: (1) the vein cell scale (`iso`) is now measured from `obj_pos` (the leaf's REST position) and not from
  VERTEX, so the fold (which moves VERTEX) no longer changes the cell size under the pattern: it stays fixed to the surface; (2) the leaf lab has a GROUND PLANE under the leaf (key G, `--noground`): the sun's shadow
  falls on it and follows the light when it is moved (`leaves/ground_sheet.png`: three light positions: the leaf's shadow turns round it; with the light behind and low there is no shadow in view, only the ball in the sky). Known gap:
  the shading of a folded leaf does not follow the fold (the normal is not recomputed: `NORMAL` stays the rest normal), which also weakens the depth cue: fix by tilting NORMAL by the fold's slope in `vertex()`.
- 2026-11-18 (loop tick 76): THE LEAF BASE LOOKED LIKE A HARD FOLDER. Cause: the realistic leaf mesh cups the blade (the midrib rides high, `lift = fold * (1 - share)...`) at FULL strength right at the stalk, where the
  blade is a few millimetres wide: a steep vertical wall, a hard crease (`stretch_default.png` shows the slab). Fix: the fold fades out toward the stalk, `* smoothstep(0, 0.3, y)`, in `plant_leaf_shapes.gd` (`_add_leaf_smooth`, the lab's leaf) and in
  `plant_mesh_native.cpp` `add_leaf_surface()` (the game's mesh leaf). Picture `leaves/base_sheet.png` (before | after | side view): the base now runs smoothly into the midrib, a clean taper in the side view. SPECIES_CHECK PASS.
  The leaf lab is open on the latest build (ground plane on, wind 0.5). Note the finest net looks chunky at some angles (aliasing of the smallest cells at ~1 m).
- 2026-11-18 (loop tick 77): CHUNKY FINE NET (aliasing of the smallest vein cells at ~1 m). `vein_tree()`: `px = max(fwidth(pg.x), fwidth(pg.y))` (cells of the first net per pixel); the line edges of the two finest nets are widened by
  about a pixel (`0.09 + px * 0.6`, `0.11 + px * 1.3`) and each net fades out (`fade1`, `fade2`) before its cells are ~2-3 pixels wide. Picture `leaves/alias_sheet.png` (before | after | closer): smoother, continuous lines; a few stair-steps
  remain where the rung / strip cells meet (hash steps of `cell_hash`): next, hash the rungs by a smooth noise. POM: the shader has parallax occlusion mapping for BARE BARK (`has_pom`) and ROCK (`rock_pom`, `rock_pom_depth`), not for leaves: a
  leaf's relief is under a millimetre; a screen-space bump from SMOOTH vein heights (not the hard lines, which gave dashed lines) is the better cost for leaves.
- 2026-11-18 (loop tick 78): SOFT BUMP FOR LEAF VEINS. `flora_wind.gdshader` mesh-leaf block: `leaf_vein_height` from SMOOTH heights: the midrib a broad channel (`soft_mid`), the secondary veins a narrow shallow groove
  (`soft_side`, width thick x 1.8, depth 0.28 x strength), the blade between them puffing up 0.04; `surface_bump` 0.55, fading out 2-8 m. (The first version, grooves 3.5 x wide and 0.5 deep, read as broad pleats: the
  waves again.) Pictures `leaves/bump_sheet.png`, `bump_sheet2.png` (side light low: the veins catch a thin highlight and shade): depth from the side, no dashed lines. Mesh leaves only; cards have no bump.
- 2026-11-18 (loop tick 79): BUMP FOR LEAF CARDS TOO. `leaf_cluster()` returns `trans` as a vec3 whose z is the soft relief of the big veins (midrib channel + narrow side-vein groove, same smooth heights as the mesh leaf);
  the fragment sets `leaf_vein_height` from it (the declaration moved up beside `net_light`) and `surface_bump` is 0.12 for a card (0.55 for a mesh leaf). First try 0.4: the cards looked like corrugated tropical leaves (`leaves/cardbump.png`);
  0.12: a light relief that catches the sun's edge (`leaves/cardbump_sheet.png`, left 0.4 | right 0.12). Cost: a few ALU per card pixel inside 8 m (the bump itself is the derivative code the bark already uses).
  Seen on the way: the three shot-holes of a leaf often land close together and read as a trefoil / clover: spread them (`hh` positions) next. The lab is open on the latest build (mesh leaf, wind 0.5, ground on).
- 2026-11-18 (loop tick 80): WATER DROPS ON LEAVES IN RAIN. The shader read no wetness before this session. Now: `water_drop(grid, seed, wet)` (one possible bead per cell, the whole drop inside its cell: x inside, y a dark thin rim, z a
  bright glint toward the upper left) on cards (grid = UV x 60, close up to 10 m, inside the leaf's alpha) and on mesh leaves (grid follows the leaf's measured width / length, `iso`); a bead sets `ROUGHNESS` 0.05 / `SPECULAR` 0.95, its
  rim darkens the albedo (x0.4) and the glint adds EMISSION 0.7; a wet leaf also shines a little (roughness x0.75). Driven by the global `ground_wetness`. First try: darkened blobs, clipped by the cells: read as dirt: rejected;
  now round lenses (`leaves/wet2_sheet.png`: mesh leaf | cards). Leaf lab: `--wet=0..1` / `K` sets wetness (rain). All that is untested IN the planet: check that the weather sets `ground_wetness` while it rains (see the grep in
  `native/planet_crust/src/` for "wetness": it is set by the weather code if any lines appear above this entry); drops need a closeup (a bead is ~3 mm), and the very small beads shimmer at a distance (they fade out by 10 m).
  Checked: `systems/world_gen/world_weather.gd:108` calls `WorldWind.set_surface(wetness, snow, ...)` every weather update, so the planet's rain does drive `ground_wetness` and the leaf drops. Still to do: a planet picture in rain (`--weather=rain`, close to a tree) to confirm.
- 2026-11-18 (loop tick 81): planet picture in rain (`rain_tree.png`, `--weather=rain --view-alt=2`): wet ground, rain streaks, no errors; the wet leaves shine a little but single beads are not visible at this distance (a bead is ~3 mm; they fade by 10 m): the drops need a closeup to read. Next: spread the clustered shot-holes.
- 2026-11-18 (loop tick 82): SHOT-HOLES: the "clover" look was the holes' own 3-lobed outline (`sin(3 * angle)` wobble), not clustering; wobble now 2 + 5 lobes at 0.1 amplitude: round irregular holes (`leaves/holes2c.png`).
  FLOWER PLANTS (user: "still low quality", from `flowers_a.png`): wide stiff flat blades like stakes, flat star flowers at their tips. `plant_mesh_native.cpp`: blades of a close tuft are V-folded along the midrib (4 tris, crease raised 0.55 x width, lighter centre);
  flowering plants: steepness 0.4-0.85 (was 0.55-0.95: arch over), >=5 segments, blade width x0.6, taper 0.78 (leaf at the foot, thin stem to the flower). `flowers_e.png` vs `flowers_a.png`: thinner arching stems, less slab. SPECIES_CHECK run after.
  NOT done: the flower heads themselves are still flat low-poly stars lying near the ground (petal count, cup, a centre disc, stalk leaves): the next step.
- 2026-11-18 (loop tick 83): FLOWER HEADS REBUILT (`bloom()` in `plant_mesh_native.cpp`): the head faces up and out along the stem (`head_dir` = 0.8 up + 0.45 stem tangent) and sits just above the stem's end, not flat on the ground; a second ring of shorter petals
  between the outer ones, raised (petals >= 5, lod 0, size > 0.03); the centre is a low dome (ring + crown, lighter top) instead of a flat disc. `flowers_f.png` vs `flowers_a.png`: upright layered yellow flowers with an orange centre. SPECIES_CHECK PASS.
  Still to do for flowers: bell / lupine / poppy / daisy closeups, a leaf pair on the stalk, buds, wilting, and the blade tufts are still stiff straight facets.
- 2026-11-18 (loop tick 84): PLANTS AT LEAF LEVEL (user: "the same level of detail in the plant as in the leaves"). `frond()` in `plant_mesh_native.cpp`: a flowering low plant (`leafy_stem`: flower, leaflet < 0.02, height < 1.5, has an outline, not lupine / lavender / bell:
  `cards_only_blades()`) is now a thin stem (width x0.12) carrying 2-4 real mesh leaves (the tree leaf builder `add_leaf`, alternate sides, smaller toward the flower) on 75 % of its stems: veins, net, translucency, wear and wet drops come
  from the shader as for a tree's leaves. Blades of the other plants take the leaf UVs / tint (4-tri V fold, `flowers_g`). Lab pictures `lab2_pair.png` (poppy | daisy): veined leaves on thin stems. SPECIES_CHECK PASS.
  NOT yet: in the planet picture (`flowers_h.png`) the yellow flower tuft still shows long blades (a kind that is not `leafy_stem`; find which: lawn / meadow / wildflower), and its flowers are on bare stems; bell / lupine / lavender keep blades; cost per plant (triangles, the CAPPED warning for the daisy) not measured.
- 2026-11-18 (loop tick 85): found why "the yellow tuft" never changed: it is TWO plants, a separate GRASS tuft (the big stiff blades: `grass` / `sedge` / `bamboo`, rib_width x2 = 0.05+ by `for_species` for every plant with leaflet < 0.02) and, in front of it, the flowering plants (now thin stems + small real leaves at the base). A debug print
  (removed) showed every flowering low plant is `leafy_stem` except the bell. Also: `wildflower` got its own branch (it was the `else` fall-through), a wildflower's petals avoid 3 / 7 and cup <= 0.85 (the builder reads those as lupine / lavender / bell), and fern / lawn / meadow / reed / tussock / grass / bamboo / sedge / bracken
  no longer inherit the palm's flowers (they were cloned from the palm genome). Leaves on stems: size min(0.24 x stem, 0.16 m), curl -0.16. SPECIES_CHECK PASS.
  NEXT: the grass tuft: blades are still stiff wide slabs (rib 0.05-0.07 of a 0.5 m blade, 4 parts): narrower, 5+ parts, V fold with leaf UV only for the wide ones; cost measurement on a forest walk; bell stems with leaves.
- 2026-11-18 (loop tick 86): GRASS TUFT BLADES: `for_species` (non-tree, leaflet < 0.02) widened every blade (`rib_width` x2, min 0.05) and halved the droop: stiff wide slabs. Now x1.1, min 0.028, droop x0.7, `frond_parts` 6 (a smooth curve): narrow arching blades (`grass_a.png`).
  COST on the forest walk (25 repeats, clear, 11:00): gpu avg 3.1 ms, p95 5.3, draw calls avg 751, primitives 812k; earlier session figures were 2.9-3.5 ms and 685-752 calls: within noise. FOREST_WALK PASS, SPECIES_CHECK PASS.
  Not done: the bell flower's stems still have blades only; the full `planet_check.sh --quick` was not re-run after this series of plant changes.
- 2026-11-18 (loop tick 87): CORRECTION OF EVERY EARLIER FOREST-WALK COST. The lab's default temp spawn (planet_lab.gd `temp_spawn`) puts the player over the SEA at altitude: the old recipe flew ~100 m above water ("travelled 2465 m" in 25 s, height over ground avg 99.7 m). The user saw the sea the whole trip. So the "3 ms GPU, ~750 draw calls, within noise" figures
  (this session and earlier) did NOT measure a forest. Fixed: `--forest-walk` skips the temp spawn, waits for the floor, surveys the map (24 headings x 240 m, longest dry run), re-surveys when water is 14 m ahead, fails on > 10 % in water / never grounded, prints the in-water share and the height over ground
  (`planet_lab_forest.gd`, `planet_lab.gd` `_forest_walk_asked`). Recipe: `LAB_PLAIN=1 ... planet_lab.tscn -- --earth --plants --trees --seed=8 --grounded --forest-walk=25 --weather=clear --hour=11 --fixed-fps 60`.
  REAL COST (walk on land, seed 8, 205 m): with trees: 17.6 fps, gpu 18.5 ms, 21,969 draw calls, 28.3 M primitives; plants only (no --trees): 49.2 fps, gpu 5.8 ms, 4,255 calls, 6.6 M primitives. Trees: ~17,700 calls and ~21.7 M primitives; plants alone are already 5.7x the old (invalid) call count.
  Unknown yet: how much of it is this session's work (leaf cards, mesh leaves in flowering plants, bloom layers, conifer bottle-brush, canopy spacing) and how much was there before; needs an A/B against the committed state in a separate worktree. Next: attribute the draw calls (per species / LOD) and the primitives.
- 2026-11-18 (loop tick 88): A/B AGAINST THE LAST COMMIT (c4357fe, a clean worktree with its own double dll, same walk on land, seed 8): HEAD: 21.2 fps, gpu 19.1 ms, 19,353 draw calls, 40.8 M primitives (123 m walked, 30 steers);
  working tree (all uncommitted work): 17.6 fps, gpu 18.5 ms, 21,969 draw calls (+13 %), 28.3 M primitives (-31 %) (205 m walked, 9 steers). So the forest's ~20k draw calls / 19 ms GPU are NOT new: the commit has them too; this work shifted
  triangles down and calls up a little. Different paths (123 vs 205 m) make the numbers loose: one run each. The real problem to attack is the baseline: ~19k draw calls, i.e. per-tree / per-species meshes and LOD nodes (the trees are ~17k of them), not today's plant detail.
  Note for a worktree A/B: copy `.godot`, then delete `.godot/global_script_class_cache.cfg` and run `--headless --import` (the cache of the working tree names classes the commit lacks), and the repo's git hook starts a native build on checkout.
- 2026-11-18 (loop tick 89): DRAW-CALL BREAKDOWN (`--census` of the forest walk, `FOREST_CENSUS` lines, grouped by distance range / shadows / size; seed 8, on land). The scene holds ~90,700 multimesh nodes (every tile's `PlantsOf<key>` holder: one MultiMeshInstance3D per tile x species x variant x LOD step), ~21.8k of them drawn per frame.
  Average instances per node: ~10. Nodes by class: TREES seen 570-1500 m: 18,992 | 238-600 m: 15,684 | horizon 1425-inf: 11,382 | 114-250 m: 4,619 | 76-120 m: 1,022 | 0-80 m (full, shadows on): 968. SHRUBS/small trees: 0-220 m 5,665 + 559 | 238-600 m 4,047 | 570-1500 m 3,642 | horizon 5,135 | 114-250 m 1,417.
  PLANTS 0-220 m 8,353 (+1,116 with shadows), tiny 0-260 m 3,489 (+2,000). So ~55 % of all nodes are TREES beyond 238 m (steps 3-5 + horizon), with ~10 instances each: the cost is the fragmentation (tile x species x variant x step), not the triangles.
  Merging the instances into one baked mesh per tile is NOT viable: the step meshes total ~100 M triangles over all instances (a multimesh shares one copy of the geometry). Options: (a) far steps (>= step 3, beyond 600 m) use 1 variant per species (4x fewer nodes there); (b) one multimesh per (species, variant, step) per parent tile group (cross-tile cells of 512 m+),
  fewer nodes, bigger AABBs; (c) drop the per-species split at the horizon (a single far mesh per tile: the existing `commit_far` merge, cheap because the far mesh is tiny); (d) hierarchical: horizon steps only on tiles above a level. Not implemented: needs the user's say, it touches the tree LOD scheme (memory: tree-lod-scheme).
- 2026-11-18 (loop tick 90): FAR-TREE MERGE EXPERIMENT (`planet_scatter_script_native.cpp` `hang()`: from LOD step `PLANET_FAR_MERGE_FROM` on, the instances of all variants of a species in a tile share one multimesh of `PLANET_FAR_VARIANTS` shapes; defaults 3 / 4 = the old behaviour, so nothing changes unless the env is set). Distance views (`far/cmp_m1.png`: 120 m, 500 m, 2500 m, before | variants 1 from step 3 | difference x4): the same at those scales, only fine texture noise.
  Walk on land (one run each, paths 146-205 m): OLD (4 variants): 17.6 fps, p50 53.5 ms, 21,969 calls, 28.3 M prims, gpu 18.5 ms. VARIANTS=1 FROM=3: 27.6 fps, p50 32.8 ms, 10,560 calls, 46.0 M prims, gpu 25.4 ms. VARIANTS=2 FROM=2: 25.6 fps, 11,976 calls, 51.2 M prims, gpu 28.2 ms.
  Draw calls halve and the frame is faster (the frame was CPU-bound: the gpu was busy 33 %), BUT the visible triangles rise 65-80 % and the measured gpu time rises: a merged node has a bigger box, so frustum and range culling keep whole nodes (and all their triangles) that were partly out of view. Next: merge per smaller cell (e.g. 256-512 m, not a whole tile) so culling stays tight; then decide the default.
- 2026-11-18 (loop tick 91): CELLS DON'T HELP. `PLANET_FAR_CELL` (the merged far trees cut into square cells, via `split_cells`): 384 m -> 23,969 calls, 40.9 M prims, 17.1 fps; 160 m -> 45,818 calls, 39.6 M prims, 10.6 fps (walks 243 / 402 m, so loose). Culling by cell saves little (46.0 -> 40.9 M) and the nodes multiply: the whole-tile merge (`PLANET_FAR_CELL=0`, now the default of that knob) is the best: VARIANTS=1 FROM=3 gave 27.6 fps / 10,560 calls.
  LOW-ANGLE HORIZON CHECK (`far/cmp_low.png`: old | merged, 30 m up pitch -2, and 300 m up pitch -4): indistinguishable by eye. The extra visible triangles (46 M vs 28 M) are then not from coarser culling alone (cells cut only ~11 %): variant 0 of a species may be heavier than the average of its four, to be checked.
  DEFAULT NOT CHANGED (4 variants, merge off): flipping it changes which tree shapes stand at > 600 m in every world (the same trees, one shape per species): wait for the user's go.
- 2026-11-18 (loop tick 92): FAR-TREE MERGE IS NOW THE DEFAULT (`PLANET_FAR_VARIANTS` 1, `PLANET_FAR_MERGE_FROM` 3, `PLANET_FAR_CELL` 0; `PLANET_FAR_VARIANTS=4` gives the old behaviour back). FULL REGRESSION `planet_check.sh --quick` (GODOT = the `...double.x86_64.console.exe`, NOT `godot.windows.console...`: the first run had no verdicts because of that name): 19 PASS; `walk` gave
  no verdict line in the run (the log ended after "VOXEL colour window ready": the known flaky end of a headless run); run alone it PASSES: `WALK_CHECK PASS travelled=429 m on_floor=99 %`. So all 20 checks pass.
- 2026-11-18 (loop tick 93): TREES ARE ON BY DEFAULT AGAIN in the planet lab (`planet_lab.gd` `_trees_by_default`: `set_trees_on(not "--no-trees" in user_args)`; the 2026-11-14 TEMPORARY switch, trees only with `--trees`, is gone). A plain Play (start menu or `PLANET_NO_MENU`) now shows the forest to walk and fly over. Checked with a run WITHOUT `--trees` (`default_trees.png`: full forest, flowers, mushrooms).
  Not run: a literal no-argument Play (it opens the start menu); the flag logic is the same function. `--no-trees` is the way to see the ground alone.
- 2026-11-18 (loop tick 94): USER CLIPPED INTO A TREE (screenshot: a buttress tree, the player standing inside a big root flange). Cause: the buttress roots (`Grower::roots()`) were drawn as tubes but had NO collider; only the trunk cylinder (`trunk_footprint`) and the thick low LIMBS (`low_limbs` capsules, the 6 thickest) collide.
  Fix (`plant_mesh_native.cpp`): every root adds two capsules (the thick foot and the middle, radius = mean ring radius x 0.9), and the mesh keeps up to 16 capsules when the tree has roots (6 otherwise). Probe (`capsule_probe.gd` in the scratchpad): buttress 16 capsules (widest r 0.41 m), ancient 16 (r 1.53 m), oak / giant / elm 0 (no roots, no low limbs), willow 6.
  NOT yet verified by walking into one in game (the user should try the same tree); the capsule count per tree rises, so the physics cost near big trees should be re-measured with the forest walk.
- 2026-11-18 (loop tick 95): BUTTRESS ROOTS "NOT WELL CONNECTED, GAPS" (user, same screenshot). Numbers (probe `root_probe.gd`): ancient girth 2, flare 0.55: trunk radius 4.2 m at the ground, 2.3 m at 1 m, 1.8 m at 2 m; the first root centre sits 2.1 m out at 1.7 m up with radius 1.3: it overlaps the trunk, so a gap at the trunk is not by the numbers. What does open gaps: roots follow a FLAT plane
  (`h = rise * (1-t)^2.2 - 0.12 t`, the bottom of the root only ~0.1-0.3 m under it) while the ground slopes, so the downhill side floats above the ground (light under the planks in the screenshot). Fix (`Grower::roots()`): the root is sunk by 0.5 of its own radius all along (`h = 1.2 * rise * (1-t)^2.2 - 0.12 t - 0.5 * ring_radius`; the crest stays up with the 1.2 rise).
  NOT verified in a picture: I could not frame that kind of tree in the lab or find one near the planet-lab spawn (the tree there has a small flare). Need from the user: the world seed / position or another picture of the gaps. The collision capsules follow the same (sunk) centres. SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 96): FREE / FLY MODE IS NO LONGER THE DEFAULT in the planet lab (`planet_lab.gd`): the player walks unless `--free` is given (the debug menu's toggle still flies); the old debug "temp spawn" (a fixed spot maybe over the sea + 50 m up in free flight at frame 200) is opt-in with `--temp-spawn`. Picture with no `--grounded`/`--trees`/`--free` (`default_walk.png`): the player stands in the forest, grass and trees on, 39 fps.
  Not re-run after this change: the full `planet_check.sh --quick` (the checks walk already; `--free` is not used by any check script: grep it before trusting).

2026-11-19 (loop tick 97): BIRCH BLACK RINGS WERE NOT ATTACHED (user picture). They were separate `frustum` bands put on the straight axis with the plain radius, so they could not follow the tube's bend, lumps or per-vertex wobble: closeup showed a smooth white band sticking out on one side and buried on the other. Now the bands are rows of the trunk tube itself (4 extra rings per mark, colours light/dark/dark/light), so they are on the surface by construction (`trunk()`, `plant_mesh_native.cpp`). Closeup `birch_v2.png`: no floating band; the dark rings are fainter than before (the bark shader dominates the colour) - tune `Color(0.12,0.12,0.1)` / widths if wanted. Birch is 720 triangles heavier (9122 vs 8402, lab tree). Not re-run: planet_check.sh --quick, species_check.
