# 042 - One tree builder driven by traits

Status: **stage 1 done (2026-10-15), stages 2-5 not started**. Follows [041](041_procedural_flora_species.md).
Branch: `godot-4.7-upgrade`.

## Why

Broadleaf, conifer and (later) palm are separate forms with separate builders, but in nature they are
points on a scale of a few traits. Two builders (`PlantCrownBuilders`, `PlantConiferBuilders`) already
share about 70% of their logic (tube joints, burying children, taper, continuous wind weight, leaf or
needle placement, budget limits); every bug fixed in one had to be fixed in the other. A trait-driven
builder also makes mixed species possible (larch, cypress, ginkgo, eucalyptus).

## Decision

One `Form.TREE` (layer CANOPY) replaces `CONIFER`, `BROADLEAF`, `BARE_TREE` (and `PALM` at step 3). A
tree is a **genome** of traits; one builder grows any genome.

| Group | Traits |
|---|---|
| Trunk | height, girth, taper, lean, bare part, leader strength (one trunk to the top .. forks into limbs) |
| Branching | arrangement (whorled, spiral, opposite), branches per node, node spacing, angle from the trunk, droop, tip lift, curve, depth (1-3), length ratios |
| Crown envelope | profile out from the trunk by height: cone, oval, dome, column, umbrella, vase, weeping |
| Foliage | kind (blade, needle, frond, tuft), leaf outline, size, lobes, edge, pattern, leaves per node |
| Colour | bark, leaf, tip |

Species are drawn, not hand-made: pick one or two **archetypes** (spruce, pine, oak, birch, willow,
cypress, ...: trait presets with ranges), blend their traits by random weights, nudge every trait a
little (mutation). The climate (cold, dry, wet) tilts which archetypes are likely but does not decide.
**Exoticness** (0 = only believable trees) later allows pushing a trait to an extreme or switching it
(umbrella crown, baobab, tufts, fronds). The user chose: first only the normal, believable draws;
exotic ones come later as an experiment.

## Rules the builder must keep (all learnt in 041)

- Every tube starts inside its parent (a share of the parent's radius, never past its far side).
- Rings stand at right angles to the path; ends are capped only where nothing continues.
- A branch that continues its parent starts at the parent's tip, same radius, same number of sides.
- Branches taper to points; nothing ends bare (twigs end in a leaf, bud or needle spray).
- Wind weight (vertex alpha) grows continuously from the trunk to the leaf tips.
- Round trunks (12+ sides low-poly), rounded trunk top, no flat cut.
- Tree mesh at most 12000 triangles in the realistic look (SPECIES_CHECK).

## Stages (each checked in the plant lab before the next)

1. `TreeGenome` + `TreeBuilder`: reproduce today's leafy trees and conifers from presets; compare by
   eye in the lab (and triangle counts) against the current builders.
2. Generator: archetypes, blend, mutate; lab key G shows random draws, a key sets the exoticness.
3. Exotic traits, palm as a "frond" foliage kind.
4. Into the world: one tree form in `SpeciesGenerator` (quota, niche from the traits, names from the
   traits); `species_check` builds about 1000 random genomes and fails on budget, NaN or joint-rule
   violations; measure render cost with `world_render_stats`.
5. Delete the old builders (`PlantTreeBuilders.broadleaf/conifer/palm/bare_tree`, the two crown files).

## Risks

- Seeds will give different species than before (fine: experiment).
- The triangle budget is the main one: every draw is clamped to it.
- A big refactor: keep the old builders until stage 4 has parity.

## Reused as they are

`PlantTreeBuilders.tube`, `PlantLeafShapes` (outlines, per-leaf variation), the needle spray, the
leafless debug build, `plant_lab` (K and H keys), `world_render_stats`.

## Stage 1 result (2026-10-15)

Built: `tree_genome.gd` (`TreeGenome`: the traits, plus `from_species` reading a leafy or conifer
species) and `tree_grower.gd` (`TreeGrower.build(builder, genome, rng)`: trunk, limbs at the top of a
forking trunk or whorls up a leader trunk, the levels of branching with the joint rules, leaves along
twigs or needle sprays at the ends). `PlantMeshes.use_tree_grower` (default true) picks it over the old
builders; the plant lab's Y key flips it (the label shows `[TreeGrower]` or `[old builders]`).
`PlantLeafShapes.outline_for(shape, aspect, lobes, edge, detailed)` takes loose numbers now.

Parity: a Beech and a Wild Spruce, low-poly, same species and angle with Y on and off: the Beech is
the same picture; the spruce has the same shape and tiers (individual branches differ because the
dice are drawn in another order). Triangle counts and the species check are unchanged (largest tree
11982). Not compared: realistic by eye, the other species.

**Cost finding (needs a decision).** Measured per tree, seed 1337: conifers average 6,231 triangles
low-poly (worst 6,828) and 9,481 realistic (worst 10,397); leafy trees 6,395 (7,632) and 10,206
(11,982). The ball and cone trees they replaced were a few hundred to about two thousand. A forest
seen from the ground (`world_render_stats`, seed 1337) went from 2.09M triangles per frame
(only the leafy trees converted) to 5.4M low-poly and 10.4M realistic once the conifers were
converted too; the CPU frame is 6-8 ms and the frame rate 120 in this headless-GPU-less measurement,
but the GPU cost on a real card is not known and 10M triangles a frame is a lot. The 12000 limit in
`species_check` is per mesh and says nothing about a whole forest. Needed: a mid-distance LOD
(`TreeGrower` with a `lod` argument: fewer rings and sides, fewer branches, leaves and needles) used
by the scatter between the near full trees and the far proxies (`PlantMeshes.build_far`), and a
look at where the scatter switches (`world_scatter.gd`, FAR_KEY).

## Mid-distance LOD (2026-10-15)

`TreeGrower.build(..., lod)`: lod 1 is the same tree, lighter: fewer rings and trunk sides, a child
less per branch, a whorl spacing 1.8x, no realistic geometry, bigger leaves and needles, 3 leaves
a twig. Averages (seed 1337): conifer 6231 -> 1846 triangles, leafy 6395 -> 2106 (the realistic look
uses the same lod 1 mesh: 9481 / 10206 -> 1846 / 2106).
Wiring: `PlantMeshes.build(..., lod)`, `SpeciesRegistry.mesh(id, variant, detailed, lod)` (cached),
`WorldSettings.tree_lod_distance` (50 m), `WorldScatter.focus` (static, the player's x/z) so a tile is
built with the version for its distance, and `ProceduralWorld._update_tree_lod` swaps the batches of
tiles the player has come closer to / moved from (6 a frame, scan twice a second). Plant lab: B toggles
the distance version.
Forest cost (`world_render_stats`, seed 1337): low-poly 5.4M -> 2.5M triangles per frame, realistic
10.4M -> 4.8M (90 m gave 3.25M / 6.4M). Still above the 2.1M / 4.7M with only the leafy trees
converted, since every conifer is converted too. Not done: a lod 2 for the 50-200 m band (the far
proxies start at the far tiles), measuring the GPU on a real card, checking the swap for pops.

## Tree builder lab (2026-10-15, user request)

The user said the trees were already good enough and asked for a scene to SEE the build and its
parameters and press "generate random". `tests/manual/world/tree_builder_lab.tscn`: one tree, a panel
with a slider for each trait of the `TreeGenome` (trunk, where the branches leave, branches, leaves),
dropdowns (leaf shape, edge, pattern, foliage), checkboxes (leader, whorls, planar children, carry on,
frosted), the triangle count; every change regrows the tree at once. Buttons: Generate random (starts
from a leafy or conifer preset and moves each trait toward a random value by the Randomness slider:
0.3 gives believable trees, 1 anything, including mixed trees), New dice (same traits, other branches),
Leafy / Conifer preset, realistic, no leaves, distance version, wind. Mouse: left drag turns, wheel
zooms, right drag moves the target up and down. Sliders hold the plausible ranges.
`TreeGrower.build` now stays inside 12000 triangles for any genome: it grows the tree again from the
same dice with `thrift` 1, 0.7, 0.5, 0.35 (fewer branches, whorls and leaves) and returns true if even
that was cut short (the lab shows CAPPED). Found with a random mixed tree (conifer whorls carrying
single leaves, 0.3 m apart) of 148,000 triangles, and a divide by zero when a twig had one leaf node
(minimum two). Real species are unchanged (they fit the first try).

Follow-up (same day): a user screenshot showed a mixed tree (leader trunk, whorls, broad leaves, 0.3 m
spacing) with leaves low down and a bare spike above ("inverted"): the budget ran out in the lower
whorls. `thrift` now goes down to 0.12 and also scales the branches per whorl (minimum 3); nine
such genomes (spacing 0.3 - 1.0, 4 - 8 limbs) fit the budget uncapped with 34-42% of the vertices in
the top 40% of the tree. Lab: "Copy properties" puts every trait, the dice and the look on the clipboard.

## Leaf veins (user remark: big leaves look too simple, they need a pattern; same day)

Leaf size unchanged. Colours at the corners of a 6-point leaf cannot make a pattern, so leaf vertices now
have a UV (`MeshBuilder.add_tri_uv`; across 0..1 with 0.5 on the midrib, along 0..1 stalk to tip;
every other triangle has UV (0, 0)) and `flora_wind.gdshader` draws, where `UV.x > 0`: a light midrib,
side veins running up and out from it (`fract(along * 7 - across * 2.6)`), the blade lighter along
the middle and darker toward the edge and the tip. No extra triangles, both looks, autumn colours
and wind are untouched. Looked at in the tree builder lab (amber and green leaves). Not done: veins
on needles and palm fronds, a vein colour per species, per-pixel serration.

Leaf variation (user: all leaves look alike, even on one tree; same day): every leaf now has its own size
(0.6 - 1.5 of the nominal, small ones commoner), width (0.8 - 1.2), asymmetry, bent tip, shade
(some leaves up to 18% darker) and two random numbers (`UV2`, `MeshBuilder.add_tri_uv(..., leaf_dice)`)
from which the shader gives it its own vein count (3.5 - 9.5), slope, thickness, strength (opacity),
midrib width, edge darkness and whether the two sides line up. Needs the plant material to read UV2;
no triangles added.

## Very thick, very tall and very spreading trees (user photos: a baobab / umbrella tree, a sequoia, an old live oak; same day)

New traits in `TreeGenome`: `root_flare` (the foot widens into buttress roots), `column` (a leader
trunk stays thick far up instead of narrowing to a cone; < 0 is a cone), `limb_length`, `limb_thickness`.
Wider ranges in the tree builder lab (height to 45 m, trunk radius to 2.6 m, crown radius to 14 m, limb
curve to 3). Leaf size now grows with the crown but slowly (`leaf_basis`, an exponent of 0.55, and clumps
x(crown/3.5)^0.6 above a crown of 3.5) so a wide crown has more leaves, not door-sized ones; a crown
over 3.5 also carries more branches on a long limb and one more leaf per twig; limbs of a spreading tree
(angle > 65) bend round the vertical, not up and down. Existing species are unchanged (species check
passes, largest tree 11982).
Lab buttons: Umbrella (14 m, trunk r 1.45, crown 4, limbs at 82 deg: measured 14.5 m tall, 11.7 m reach, nothing
under ground), Giant (42 m, trunk r 2, flare 0.7, column top 0.22, first whorl at half height), Spreading oak
(12 m, trunk r 1.5, trunk part 0.35, limbs at 78 deg, crooked). Found by measuring the vertices headless: a
first umbrella was 26 m wide and went 3.5 m under ground (limbs 1.3 x too long, sag), a first oak
went 4.4 m under ground. Not done: bark texture and moss on the old oak, a lab slider for the flare shape.

Giant's needles were too small for its 2 m trunk (user): needle sprays now scale with the trunk radius
above 0.4 m (`stout = (girth / 0.4)^0.75`, 1 for every existing species), so the giant's sprays are about 2.9 x
bigger and its crown reads as a crown. Looked at in the lab (low-poly).

## Dragon blood tree and ancient live oak (user photos, same day; FIRST PASS)

New traits: `tips_only` (needle sprays only at the very ends of the branches, facing up so together they
make a canopy) and `leaf_density` (some twigs bare, the others fewer leaves). Lab sliders for both and
`needle size` up to 1.5; buttons Dragon tree and Ancient oak.
- Dragon tree (leafy-form trunk 9 m, radius 1.3, trunk part 0.55, 8 limbs at 66 deg, 7 branches per limb and
  7 twigs per branch, tufts at the ends): reads as a thick trunk forking into a tuft canopy; it is NOT yet the
  flat disc over a visible lattice of fine branches (the 12000 triangle budget thins the branches: ~11000
  triangles; the real tree has hundreds of fine forks).
- Ancient oak (14 m, trunk radius 2, limbs 1.45 x, leaf density 0.45): a sparse dark spreading crown; the limbs are
  thinner and spikier than the huge sagging ones of the photo. My first tries (limb curve 1.5-1.8, then 0.7
  with limbs at 86 deg) were a coiled / spiky heap on the ground: do not raise the limb curve above ~1.2.
Not done: sagging limbs that reach and rest on the ground, moss on the limbs, bark colour variety, the
fine branch lattice (would need a 4th branching level cheap enough: ribbons or fewer sides).

## Archetype-based random draw

`systems/world_gen/flora/tree_archetypes.gd` (`TreeArchetypes`) holds the named kinds (leafy, conifer,
umbrella, giant, oak, ancient, dragon, willow, cypress) as genomes, plus `draw(rng, leafy, conifer,
randomness, exotic, info)`: pick one or two kinds, blend traits by a random weight, nudge every numeric
trait inside `RANGES`, and with probability `exotic` push one trait somewhere unusual; `_settle`
makes the traits agree. The lab's "Generate random" uses it (new Exoticness slider; the label shows the
recipe, e.g. "cypress 77% + giant 23%"). Check: 300 draws, worst 11992 triangles, no NaN. Stage 2 will
draw the world's species from the same table.

## Later additions (archetypes)

- Kinds added: willow, cypress, bush (1.6 m), shrub (0.7 m), groundcover (0.3 m), clump (multi-stem,
  `stems`/`stem_spread`), palm (`Foliage.FROND`: `fronds`, `frond_length`, `frond_arch`, `frond_droop`,
  `leaflet`; ~1500 triangles). Ranges go down to 0.2 m height; leaf size scales down for crowns <0.8 m.
- Minimum crown radius (10-12% of height) so branches are never stitched to the trunk.
- Budget check keeps a 150-triangle margin: 300 random draws stay under 12000.
- Still to do: cactus/succulent, grasses/ferns/flowers, dead trees, bark texture, per-tree variation in
  the world scatter, a small-plant triangle budget (a 0.3 m groundcover can use ~10k triangles).

## Second batch (dead tree, cactus, fern, grass, wildflower)

- New kinds: dead (grey rough bare tree), cactus (candelabra: short green trunk, arms bending up),
  fern, grass (frond blades with no leaflets, `leaflet` < 0.02, wider midrib via `rib_width`),
  wildflower (blades plus a flower fan at each tip: `flower` colour, `flower_size`).
- New traits: `rib_width`, `flower`, `flower_size`, `bark_rings` (palm trunk rings), `bark_rough`.
- Triangle budget scales with size: `1500 + 2000 * height`, capped at 12000, so a 0.3 m plant cannot
  use 10k triangles. Regrow steps are finer (1.0, 0.94, 0.88 ... 0.12) so a tree just over the limit
  loses a little, not half its leaves.
- Per-tree variation in the world already exists in the scatter (size spread, yaw, tint, two grown
  variants per species); not changed.
- Checks after this batch: 300 draws worst 11873 triangles, no NaN; species_check PASS (largest mesh
  11134); world_lab --world-check PASS.
- Still open: moss/lichen on bark, vines, fruit and cones, a save/load for liked trees, the world
  stage itself (species drawn from the archetype table, delete the old builders), saguaro arms from the
  side of a trunk, a ground tuft of leaves under the wildflower.

## Third batch (thick winding limbs, no clipping, blossom, flower variation)

- Traits: `twist` (S-curves, limbs wind in 3D), `avoid` (a growing limb/branch steers away from other
  limbs and branches, so they do not pass through each other; branches only, not twigs), `twig_radius`
  (twigs thinner than branches), `limb_length` up to 3.0, limbs rest on the ground instead of going under it.
- Flowers: shared `_bloom` (petals 4-10, `flower_cup` 0 flat .. 1 tulip, centre colour); ground plants
  carry one per frond tip; trees carry `blossom` (SINGLE, RACEME hanging stems like a bird cherry, UMBEL
  round clusters). Kinds: cherry, blossom. Random draws vary colour, petals, cup, centre.
- Ancient oak (Angel Oak): now 48 m wide, ~26 m tall with long thick winding limbs that do not
  clip; it still does NOT look like the photo (a skeleton of spikes near the ground, the trunk is hidden,
  the foliage is thin). Needs: a visible huge trunk, limbs that fork into thick curving branches,
  foliage clumps, moss. Wide-crown twig bonus is skipped at twig level when `avoid` (budget).
- Checks: 300 draws worst 11840, species_check PASS, world-check PASS.

## Fourth batch (from reference photos: buttress roots, fluted bases, rain-tree dome)

- New traits: `flutes`/`flute_depth` (ridges up the trunk, deeper at the foot), `trunk_bend` (S-shaped
  trunk), `trunk_lumps` (swellings), `roots` / `root_reach` (roots running over the ground, starting at
  the flared foot), `compound` (feather leaves: a stalk with pairs of leaflets, 9 triangles).
- New kinds: raintree (wide dome, compound leaves, avoid), buttress (fluted, bent, lumpy, 2 fused stems,
  roots). Ancient oak got roots/lumps/bend/flutes. Random draws add these imperfections now and then
  (`_imperfect`).
- Findings from the photos: a real dense dome needs far more leaves than 12k triangles buy; the rain
  tree here reads as a wide acacia, not a solid mass. Ideas not done: foliage clump blobs (a few big soft
  leaf masses under the leaves), bark texture/normal map, moss, vertex colour variation inside a ring
  (grooves darker than ridges), roots that flow smoothly into the trunk (now they are separate tubes
  with pointed ends).
- Foliage clumps (`foliage_mass`): flat jittered eight-sided pads at twig tips in the leaf colours, so a
  crown reads as layered mass (raintree 0.7, ancient 0.6). They look like stylised canopy pads; the
  realistic look may want a softer shape later.

## Fifth batch: ancient oak retune

- The ancient oak spent its budget on serrated heart leaves (14 triangles each) on a wood skeleton.
  It now has small smooth oval live-oak leaves, a dark green, `leaf_density` 0.6, and big foliage
  clumps (`mass_size` 2.2, new genome trait: clump size as a multiple of a leaf) at twig tips so
  the crown reads as a leafy mass. `children` [6, 5, 0]. Lab has a "clump size" slider.
- Still not the Angel Oak photo: reads as a tall bush of limbs; a flatter, wider, lower crown and a
  more visible trunk are open.

## Grass types

New low-plant kinds: `lawn` (short dense), `meadow` (tall, golden tips), `reed` (tall upright),
`pampas` (arching fountain, cream plumes at the tips), `tussock` (drooping golden mound), beside
`grass` and `wildflower`. All are frond plants with bare blades (`leaflet` 0).
