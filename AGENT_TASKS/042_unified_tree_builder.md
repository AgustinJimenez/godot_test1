# 042 - One tree builder driven by traits

Status: **design, agreed in chat 2026-10-15, not started**. Follows [041](041_procedural_flora_species.md).
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
