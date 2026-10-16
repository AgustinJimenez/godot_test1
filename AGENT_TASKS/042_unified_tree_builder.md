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
