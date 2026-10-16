# Tree and plant builder (reference)

Every plant in the procedural worlds except mushrooms is grown by one builder, `TreeGrower`, from a
set of numbers, `TreeGenome`. This is the stable reference; the history is
`AGENT_TASKS/041_procedural_flora_species.md` and `AGENT_TASKS/042_unified_tree_builder.md`.

## Pieces (`systems/world_gen/flora/`)

| File | Job |
|---|---|
| `tree_genome.gd` | all the traits of one plant (trunk, branching by level, foliage, flowers, bark, roots, fronds...) |
| `tree_grower.gd` | grows a genome into a mesh: trunk (flutes, bend, lumps, roots), limbs and branches as tubes, leaves, needle sprays, compound leaves, foliage clumps, fronds (palms, ferns, grass), flowers and blossom; a triangle budget with finer and finer regrowth until it fits (`thrift`) |
| `tree_archetypes.gd` | the kinds (`NAMES`: leafy, conifer, oak, ancient, willow, palm, cactus, fern, grass, lawn, meadow, reed, pampas, tussock, wildflower, cherry, blossom, raintree, buttress...), `draw` (a random plant: blends one or two kinds, nudges traits, adds imperfections, optional exotic push), `for_species` (the plant of a world species) |
| `plant_species.gd`, `species_generator.gd`, `species_registry.gd` | a world's species: the generator picks each species' kind from its climate niche (`archetype`) and sizes it from the kind |
| `plant_meshes.gd` | species -> mesh (`TreeGrower` for everything but mushrooms; small plants always in the light version) |
| `plant_tree_builders.gd`, `plant_ground_builders.gd` | shared `tube` and the far (horizon) tree; the mushroom |

## Tools

- Lab: `tests/manual/world/tree_builder_lab.tscn`: sliders for every trait, Generate random (filter:
  any, trees only, plants only), New dice, a person for scale, realistic or low-poly look, a "Kinds"
  switch with a button per kind, Copy properties.
- Checks: `tests/manual/world/species_check.tscn` (expect `SPECIES_CHECK PASS`, the largest mesh at
  most 12,000 triangles); `world_lab.tscn -- --world-check`; `world_render_stats.tscn` for the
  GPU cost (seed 1337 low-poly: 5.3 M triangles per frame, down from 12.4 M with the old builders).
- Keep `gdlint` clean and a file under 1,000 lines (`tree_grower.gd` is the big one).

## Rules of thumb

- A trait that is a number goes in `RANGES` of `tree_archetypes.gd` so a draw stays plausible.
- A new kind is a branch of `TreeArchetypes.make` plus a name in `NAMES` (and a noun in
  `SpeciesGenerator.KIND_NOUNS` / a weight in `_archetype` to put it in the world by climate).
- The same species always grows the same plant (dice seeded by the species and variant).
- Ground plants in a world are cheap: 4 parts per blade, at most 16 blades, built at lod 1.

## Not done

Bark texture or moss, the Ancient oak still does not match the Angel Oak photo, more broadleaf
species per world, a real foliage look for the rain tree (a dense dome costs more triangles than the
budget).
