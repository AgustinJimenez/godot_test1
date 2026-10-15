# 041 - Procedural flora species

Status: **implemented, uncommitted, waiting for the user's live look** (2026-10-15). Brainstormed with
the user, then built end to end while they were away (they asked for exactly that: design, build,
test, review at the end). Builds on [040](040_procedural_world.md). Branch: `godot-4.7-upgrade`
(the whole project was moved to Godot 4.7.2 the same day to install the Godot AI MCP plugin; the
plugin and the upgrade are separate from this task).

## Goal

Vegetation that looks like real life: many categories and visible variety, not 19 hand-written kinds
with 2-6 variants each. Instead of hand-coding each plant, the world generates **species** when it is
built: a species is a set of properties (height, trunk, branching, crown, leaves, colours, wind sway,
environment preferences) that decides what its plants look like and where they grow.

## Decisions (user answers, in order)

1. **When are species created?** Each time a world is generated, from the seed (not a fixed
   hand-made library). Later, as the world expands while the player explores, more species may be added
   in the background with some probability (NOT built yet, see "Growth over time").
2. **Scope: all plants** - trees, shrubs, grasses, flowers, ferns, cacti, reeds, mushrooms.
3. **Where a species grows: environment preferences** (moisture, heat, height above water, slope),
   not biome lists. New species need no biome-table edit; forests thin out and change gradually.
4. **Species count: about 36 per world** (a setting, `WorldSettings.species_count`).
5. **Approach: parametric growth forms.** One builder per growth form, driven by the species'
   numbers. Rejected: full L-systems (too heavy and hard to keep low-poly, poor fit for grass and
   flowers). Possible later upgrade for trees only: a light real-branching step.

## What was built (`systems/world_gen/flora/`)

| File | Job |
|---|---|
| `plant_species.gd` | `PlantSpecies`: one species. `Form` (12 growth forms), `Layer` (5 scatter layers), shape numbers, colours, niche (moisture/heat/above-water/slope + density + clump settings), `fitness()`, `footprint()` (trunk collider) |
| `species_generator.gd` | `SpeciesGenerator.generate(seed, count)`: quota per form (36 = 3 conifer, 4 broadleaf, 1 palm, 1 bare tree, 6 shrub, 2 cactus, 4 grass, 2 tall grass, 2 reed, 6 flower, 3 fern, 2 mushroom), species of one form spread over the climate (stratified), shape and colour draws, names ("Snow Fir", "Meadow Birch", a willow is a broadleaf that droops) |
| `species_registry.gd` | `SpeciesRegistry.for_settings(settings)`: the species of a seed (cached, last two seeds), per-layer lists, mesh cache behind a mutex (tile worker thread + main thread both read it) |
| `plant_meshes.gd` | dispatch: species + variant + detailed -> mesh; `build_far` for horizon trees |
| `plant_tree_builders.gd` | conifer, broadleaf (forking trunk, lumps, weeping, birch bark patches, leaf cards in the realistic look), palm, bare tree, far proxies |
| `plant_ground_builders.gd` | shrub (berries/blossom), cactus (columnar with arms or barrel), grass and tall grass (seed heads), reed (cattails), flower (stems in a clump), fern (leaflets when realistic), mushroom |

Changed: `world_scatter.gd` (rewritten around species: `_scatter(layer)`, `_pick()`, per layer grid
spacing, chance = sum of the species' fit x density up to a per-layer cap that equals the old biome
maximum; rocks, logs, spires and the new stumps stay biome-driven), `flora_meshes.gd` (now only rocks,
stumps, logs, spires; enum values kept so rocks keep their shapes), `procedural_world.gd` (detail swap
handles species meshes), `world_settings.gd` (`species_count`), `.gdlintrc` (excludes `godot_ai`, the
third-party plugin, otherwise `scripts/check.sh` lint fails on 1000+ of its lines).

How it behaves: every grid point on a tile scores each species of the layer by `fitness x density`
(x a clump noise for patchy species), the plant is chosen in proportion, and a species that does not
fit the spot is simply not there. Per-instance size spread, yaw, mesh variant (2-3 per species) and a
small tint difference. Colliders only for trunks and cacti. Far tiles use cheap cone/ball proxies.
Frosted (snowy) conifers are the cold-niche species. Autumn, wind, snow and the realistic look work
unchanged (same shader, same vertex-colour conventions).

## Verification (all green on 2026-10-15, Godot 4.7.2)

- `godot --headless --path . res://tests/manual/world/species_check.tscn` -> `SPECIES_CHECK PASS`:
  36 species, unique names, every form and layer present, deterministic per seed, different seeds
  differ, ordinary land is covered by trees and grasses (45/45 spots), 174 meshes in 450 ms, none over
  12000 triangles (largest 5120, detailed broadleaf).
- `godot --headless --path . res://tests/manual/world/world_lab.tscn -- --world-check --flora` ->
  `WORLD_CHECK PASS` and `FLORA_CHECK PASS species=36 of 36 layers=5/5` (the check is part of
  `--world-check` now).
- Lint: `gdlint .` clean (gdtoolkit 4.5.0).
- Look: `tests/manual/world/species_gallery.tscn` (keys: 1-4 pages, R new seed, D realistic, A autumn)
  and the live `levels/procedural_world.tscn` in low-poly and realistic, several seeds, F4 re-roll.
- Performance versus the old flora, same lab walk (`-- --perf`, headless, three runs each):
  frame avg 8.7 -> 8.8 ms, p99 9.0 -> 10.0 ms, worst frame 206 -> 235 ms, world build 2.75 -> 3.0 s.
  Cause: 21 percent more plant instances (20.2k vs 16.6k in 325 tiles) and 12 percent more batches,
  101 distinct meshes instead of 59. Cheaper species scoring changed nothing (scoring is not the cost).

## Not done / next

- **Growth over time** (user's later idea): species appearing as the world expands. Keep it
  deterministic ("same seed = same world" must not depend on exploration order): derive extra species
  per region from (seed, region) and let a tile use the base list plus the species of the regions
  around it. Ids stay stable, the registry only ever appends. Not built (YAGNI until asked).
- Tune after the user's look: grass is the bulk of the instances (the two broad grasses are ~10k of
  20k); species names pick generic adjectives ("Meadow Fern"); conifers are all the same cone-stack
  silhouette apart from size and tier count; no real branching yet; flowers are flat petal discs.
- Per-species size spread, colour jitter and the density caps are the knobs to turn first.
- Ideas: more growth forms (vines, bamboo, agave, tree ferns), seasonal flowering per species,
  species-specific wind sway, the World menu page could list the seed's species.
- The Godot editor does not pick up new `class_name` scripts until a headless `--import` has rewritten
  `.godot/global_script_class_cache.cfg` (a `filesystem_manage scan` did not). Run it once after adding
  a new global class, then the next play works.

## Even forks and tiers (2026-10-15)

The user saw trees "divided" with uneven divisions. Broadleaf crowns had forks at random angles and
lengths and lumps scattered at random, so the canopy broke into detached blobs. Now
`PlantTreeBuilders.broadleaf` places the forks at equal angles (phase random per mesh, +-0.1 rad)
with equal reach, one lump of leaves at each fork tip, one on the axis and the rest on a ring
between the forks; a single fork is dropped (it only looked like a crooked branch). Conifer tier
radius jitter went from +-10% to +-3% so the tiers shrink evenly. Looked at in the species gallery
(low-poly and realistic, two seeds). If the user meant something else by "divided" (e.g. the
trunk pieces of palms), ask which species.

### The "divided" trees were the trunks (same day, found from a user screenshot)

The user still saw divided trees after the crown change: the trunk of a broadleaf tree was three
separate stacked cones, each straight and each with its own random rim wobble and its own dark to
light colour ramp. On a leaning tree the pieces were shifted sideways by `tilt * t^2` per piece, so
they did not meet (visible steps), and the colour banded at every joint. Palm trunks (5 stacked
pieces) had the same fault. Now `PlantTreeBuilders._tube` builds one continuous tube through shared
rings (`_trunk` 5 rings, palm 9 rings with a slight bulge on every other ring for the ringed look);
`_trunk_centre` is the single formula for the lean, also used by the birch bark marks (which now
follow the taper too). Lesson: the gallery framed whole trees from far away and hid this. The
gallery now has a close-up mode: C toggles it (eye level, close to one species), Left / Right pick
the species.

### Plant lab and the cactus arms (same day)

User screenshot of a cactus: the arms were plain cylinders crossing the trunk and floating cylinders
beside it. The arm's rotation had the wrong sign (`Basis(BACK, side * PI/2)` points a piece along
+Y into -side), so each horizontal piece went INTO the trunk while its upward piece stood at the
correct outer end, detached. Now the arm is placed with `Basis.looking_at(dir) * Basis(RIGHT, -PI/2)`
(the same way the broadleaf forks are), arms leave in opposite directions (the third at a right
angle) at different heights, and each upward piece starts where its horizontal piece ends.

New lab `tests/manual/world/plant_lab.tscn` (the user asked for "a lab where we can generate
randomly and see the results"): one growth form at a time, a row per species, a column per random
individual. F / Shift+F form, G new random species (new seed), V new random individuals, D realistic,
A autumn, C close-up of one row (Left / Right individual, Up / Down species). Command line:
`--form=CACTUS --seed=N --detailed`. Individuals are `PlantMeshes.build(species, random_variant,
detailed)`. Use it after any change to a plant builder: look at several G / V rerolls in both looks,
and in close-up, not only at the gallery's overview.

### Mushroom clumps clipping (same day)

A clump of 2-4 mushrooms put each one at a random spot within +-20 cm, while a cap is as wide as its
stalk is tall times `crown` (up to 1.3), so neighbouring caps cut into each other.
`PlantGroundBuilders.mushroom_layout` now places every next mushroom beside an earlier one at least
the two cap radii plus 3 cm away, retrying 24 times (no free spot: that mushroom is left out).
`species_check` tests it: 900 random clumps over three seeds, the least room between two caps is
3.7 cm. The plant lab's close-up now frames the plant by its size (a mushroom was a speck).
