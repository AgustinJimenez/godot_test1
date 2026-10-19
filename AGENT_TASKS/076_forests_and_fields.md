# 076 - Forests, fields and crowding (2026-10-19)

How plants are spread (native, `PlanetScatterNative`; the script loops in `PlanetScatter` are only the fallback and do not
have these rules):

- **Forest or field is set by rain, with a mosaic.** `closed_share` = smoothstep over the wetness (0.25..0.7: below that
  grass, above that forest) plus two large noises from the direction on the planet (about 300 m: groves and meadows,
  about 1.5 km: regions, both continuous across tiles) minus steep ground; the chance a canopy spot is planted is multiplied
  by it (shrubs by 0.4 + 0.6 of it, horizon trees by it too). Real causes: rainfall decides forest, savanna or grassland;
  fire, grazing and soil keep the edge ragged. It is not only competition.
- **Crowns keep apart.** A tree is placed only if its crown (the species' `crown` times its size) is not within 70 % of the
  two radii together of a tree already placed (a 10 m cell hash inside the tile; not across tile edges).
- **Shade.** The ground layers (grass, flowers, ground cover, shrubs) are thinned by the canopy over the spot
  (each crown shades most at its middle, up to 85 %) by `1 - shade * (1 - shade_tolerance)`; tolerance per growth form:
  mushroom 0.95, fern 0.9, shrub 0.55, grass 0.3, flowers and reeds 0.2, cactus 0.
- Measured (`tests/manual/planet/forest_density.tscn`, seed 8, trees per hectare by wetness): 0.30 -> 7, 0.45 -> 87,
  0.60 -> 118, 0.85 -> 139 (grassland, savanna, woodland, forest). Real forests have 100-500 large trees a hectare.
- Not done: trees across tile edges still ignore each other's crowns; fire, grazing and soil depth are not modelled
  (a tree line by cold comes from the species' heat niche); the openness could also come from the drainage (wet valleys
  forest, dry ridges open) and from the seasons' dry spell.

## Soil with grain and depth (`shaders/world/planet_ground.gdshader`, `stones()`)
Loose stones of three sizes (grit 7 cm, pebbles 22 cm, cobbles 60 cm cells; High and Ultra, within 24/55/90 m) lie in the
soil, from 3D cells in the planet's wrapped coordinates (continuous over tiles, same after a rebase): one jittered stone
a cell (some cells empty), each with its own radius, height, shade (pale quartz, dark basalt, or the ground's own tone
greyed) and dome that tilts the normal; a darker, damper band hugs each stone and the hollows get ambient occlusion, so
the soil has depth and is not one painted colour. Grass hides them, sand keeps only its grit, pebbles and cobbles thicken in
some patches and on slopes. Costs 8 cells x 5 hashes a size class (about 120 hashes) and about 1 ms of GPU: 150 fps at High
with 13 M primitives. Not done: real parallax (the depth is the normal, the occlusion and the dark gaps), stones as meshes
very near (`PEBBLES` instances exist further out), wet stones darker than the soil, frost and moss on the north side.

## Soil and stones follow the geology (2026-10-19)
`PlanetCrustNative::ground_materials` gives every vertex six bytes from the rocks of the place (`rock_weights`, the same
nine rocks and weights as `rock_colour`) and the climate: how **angular**, how **coarse**, how **pale** and how **flaky** its
stones are (table per rock: granite coarse, angular, pale; basalt dark, angular; limestone pale and rounded; sandstone fine
and slabby; shale and schist plates; gneiss and andesite between), the soil's **organic** matter (128 neutral; black earth
in mild, moderately wet places and peat in cool wet flats above; the ash of cold wet forests, loess and desert dust below)
and its **iron** (red laterite where it is hot and wet, red sandstone). They ride in the mesh as CUSTOM1 (the four stone
numbers), the alpha of CUSTOM0 (organic) and the alpha of the flat colour (iron), and are smooth numbers, so places grade into
one another. `planet_ground.gdshader` tints bare soil by them (grass and snow hide it) and shapes the stones: angular ones
are edged (an L1 metric), flaky ones are flat plates, coarse rock thickens the pebbles and cobbles, pale rock gives pale
stones. `rock_colour` is untouched, so the native check against the script still passes. The mesh gets the extra array
only on the native path (`MeshBuilder.append_smooth(..., material_bytes)`); the script path has none and reads zeros.
Not done: the soil's depth (thin on slopes and ridges, deep in valleys: from the slope and the drainage), more soil
colours in `rock_colour` itself (it has a script twin), wet soil and wet stones, frost and moss on the north side.

## Where stones lie: odds by area (2026-10-19)
Stones are not everywhere. `ground_materials` also gives a **stoniness** (0 clean soil .. 1 stone field), the soil's
**depth** and the river **gravel** (CUSTOM2). Stoniness = 0.12 + hard coarse igneous rock (granite, gneiss, andesite, basalt
weather to gravel, shale and sandstone to fine soil) + steep ground (scree and thin soil) + high ground + frost (the cold
shatters rock above the tree line) + dry ground (desert pavement) + river gravel bars (distance to the river, rounded
stones) - deep, wet, organic soil (buries its stones); then two large noises decide whole regions (about 1.5 km across)
that are stone free and patches (about 150 m) that are stony. The shader multiplies each size class's coverage by it
(grit by 0.1 + 0.9 x stoniness, pebbles from 0.1 to 0.6, cobbles from 0.35 to 0.9). Measured on seed 8 (flat land points,
`tests/manual/planet/stoniness_check.gd`): 52 % clean (under 0.2), 15 % 0.2-0.4, 11 % 0.4-0.6, 9 % 0.6-0.8, 13 % above 0.8.
Research (web, 2026-10-19): soil science (the six pedogenesis factors: parent material, climate, relief, organisms, time)
says depth falls with slope and rises in valleys, coarse hard parent rock gives coarse stony soil; game pipelines
(stochastic "texture bombing" anti-tiling, height and slope blending as in Unity/Unreal terrain shaders, Horizon Zero Dawn's
rule graphs for placement) are rule layers over masks: that is what this is. No published rule set for stone probability
was found: the numbers above are ours, to be tuned by eye.
Done afterwards: the soil depth (CUSTOM2.g) makes thin soil show more bare rock (`w_rock` rises by up to 0.25 where the soil
is thin), and the placed pebble and rock instances follow the same odds (`PlanetCrustNative::stoniness_at`, called by
`PlanetScatterNative`: pebbles x (0.1 + 1.5 stoniness), rocks x (0.3 + 1.4 stoniness)). Still not done: the rock spires, logs
and stumps keep their own odds by biome; the spires (cones) look like obelisks and want a better shape.

## Rock formations (spires), 2026-10-19
The old spires were smooth cones. `PlantMeshNative.scenery(SPIRE)` now builds formations of cut stone blocks (the stone shader
draws their grain and joints): variant 0 a tor (four boulders stacked and offset), 1 a cluster of six to nine columns of
different heights, 2 a leaning standing slab with a fallen one. They stand where the ground is stony (odds x (0.2 + 1.6
stoniness)) in rocky, snowy and desert biomes. `tests/manual/world/rock_lab.gd -- <png> spire` shows them.

## Knife edges and walls on ridges (2026-10-19, reported with a screenshot: a long steep dark face with a sharp crest)
`tests/manual/planet/steep_walls.gd` samples land lines of 120 m at 1 m (game scale 0.1) and counts walls (more than 2.2 m of
climb in 1 m, a 65 degree face) and knife edges (the slope changing by more than 1.6 within 2 m). Seed 3: 41 walls and 22
knife edges in 839 lines; with the eroded ridges off (`PLANET_NO_EROSION=1`) 6 and 0, so the erosion noise made them
(rivers had no part: `PLANET_NO_DRAINAGE=1` changed nothing). The cause is the ridged noise's crease, `1 - |n|`, a cusp.
`erosion_noise.h` now uses a rounded absolute value, `sqrt(n^2 + 0.09) - 0.3`, with the matching smooth side sign, and caps the
coarse slope that offsets the finer octaves at 1.5 lattice units. Seed 3: 18 walls, 8 knife edges; seed 8: 12 -> 3 walls and
10 -> 2 edges. `PlanetMapCache.VERSION` is 6 (the terrain changed: old map pictures are not read).
Left: about 2 % of lines still have a 65-70 degree face, most with a 5 m step at one metre at a height near 450 m in both
seeds checked (two heights 446 and 451 with nothing between: probably the edge of a lake cell of the drainage, which sets
the ground down to the water's level: `lake_weight` is per cell); to chase: where the lake's weight stops, the ground
should blend over tens of metres. To find the user's wall, the world seed and the place are needed (the position is in the
recorder file, `user://`, F9 marks it).

## Things on slopes (2026-10-19, reported: a big stone and a trunk floating on a hill)
Everything was placed upright at one point of the ground, so on a slope the downhill side of a rock or a trunk hung in the
air. `PlanetScatterNative` now tilts and sinks each thing by the ground under it (the slope's normal and gradient are read
before each candidate): rocks lean 75 % to the ground's normal and sink by scale x (0.12 + 0.8 x slope), logs and stumps lean
90 %, spires 20 % and sink by scale x (0.12 + slope), pebbles, leaves and sticks lie on the slope, trees lean 30 % (a tree
grows against gravity: nearly upright) and sink by their trunk's radius x 1.3 x slope + 0.15, low plants lean 50 %. The
instance transform is a full rotation (the MultiMesh buffer already had it). Colliders are not tilted (a rock's box is yaw
only: on a steep slope it can differ by a few decimetres).

## Collisions of trees and rocks (2026-10-19, reported: walking through trunks and branches)
- **Trunks**: the collider was a fixed guess (radius `max(girth * 0.9, 0.18)`, height 1.5 to 4 m). `PlanetScatter._trunk_footprint`
  now reads the genome: the foot's radius (girth flared by the buttress roots, narrowed up a tapering trunk) and the bare
  trunk's height (all of a conifer's, up to 14 m). The cylinder follows the leaning, sunk tree (the full rotation comes from
  the native placement: 14 floats a cylinder).
- **Thick low limbs**: `PlantMeshNative.grow` keeps the six thickest limb segments of 7 cm or more under 2.4 m as capsules (the
  mesh's meta `capsules`, two points and a radius each); `PlanetScatter._add_limb_colliders` puts a capsule collider on each for
  every tree placed on a tile with colliders. On seed 8's lab walk: 1443 trunks, 4396 limb capsules, 544 rocks and logs, 115 fps.
- **Rocks, logs, stumps**: the box colliders are rotated with the thing (15 floats a box).
- Not done: branches that bend when pushed and slow the character; foliage, grass and thin twigs have no collision (see the
  proposal in the conversation of 2026-10-19: bending in the shader from a few pusher positions, a drag from the undergrowth
  around the player, thick branches as the capsules above).

## Pushing through undergrowth

- Native `PlanetScatterNative` records the stems (x, z, reach, drag) of every shrub, fern, grass tuft and reed placed on a tile (tile meta `stems`); `drag(stems, x, z)` is the walker's held-back share (0 open .. 1 thicket).
- `PlanetUndergrowth` (a node of the Player) slows the walk by that, easing in and out (at most 55%), and feeds the player's position to the shader global `pusher_a`; `flora_wind.gdshader` bends nearby plants away from it (`shove_from`). `pusher_b`/`pusher_c` are free for animals.
- Check: `tests/manual/planet/undergrowth_check.tscn`. Debug switches: `PLANET_NO_UNDERGROWTH`, `PLANET_NO_PLANT_COLLIDERS`, `PLANET_NO_LIMBS`; `LAB_PUSH="x,y,z,reach"` for `rock_lab.gd`.

## Reference models (measurements only, nothing imported)

Three Sketchfab packs, all CC-BY-4.0, kept outside the repo (the user's Downloads): "Oak trees pack (17var, LODs, seasons,
gameready)" and "Grass pack (lowpoly, game-ready)" by LOLIPOP, "Rigged & Animated Weeping Willows" by Jagobo. Only numbers
were taken from them (read with a small Python glTF reader), so nothing needs attributing in the game.

| Oak (LOD0 bark and clusters) | Height | Trunk radius | Forks / crown base | Crown radius | Crown height / width |
|---|---|---|---|---|---|
| Medium | 10.5 m | 0.2 to 0.4 m | 3 m | 4 m | 0.87 |
| Big | 19.6 m | 0.5 to 0.8 m | 2 to 3 m | 9.5 m | 0.85 |
| Large | 26.5 m | 0.6 to 0.8 m | 2 m | 11 to 12 m | 1.0 |

Oaks: trunk radius is 3% of the height, the crown as wide as it is tall (radius 45% of the height) and widest a third up;
the branches reach the full crown radius with the leaf clusters at their tips. Willow: 24 m tall, 32 m wide, leafy to 1.4 m
above the ground. Grass tufts: 0.2 to 0.25 m, about 11 blades each, fanned out to 0.3 m.
The `oak` and `willow` archetypes were changed to those proportions (they had a 1.5 m radius trunk under a crown of 3.6 m).
`rock_lab.gd` takes `arch:oak` (or any archetype) to preview a tree kind. Grass was not changed.

## Branches that bend for real (PlanetSway)

- `PlantMeshNative.grow` gives every vertex its branch (CUSTOM0.x, 0 = trunk) and the mesh a `branches` meta: ten floats a
  branch (parent, level, foot, tip, radius, length). `BRANCH_CHECK` verifies the ids against the geometry.
- `PlantSwayNative`: each branch is a damped spring turning about its foot (rotation vector relative to its parent), pushed
  out of the way of the walker's capsule; thin twigs turn up to 1.2 rad, thick limbs hardly at all. Sleeps when at rest.
- `PlanetSwayTree` draws one tree with `bendable` on in `flora_wind.gdshader`: the turns come from a 2 x N float texture and are
  stacked up the parents. `PlanetSway` takes the trees and shrubs within 8 m of the walker out of their MultiMesh (instance
  shrunk to nothing; the tile's `sway_sets` meta lists the batches) and gives them back beyond 11 m once at rest.
  Off with `PLANET_NO_SWAY`. The older shader-only bump still moves grass and plants that have no branches.
- Headless renderers do not keep MultiMesh instances: the transform and colour come from the tile's own buffer.
- Check: `--plants --grounded --sway-check` (SWAY_CHECK) puts the walker in a shrub and needs a branch turned.
- Plants without branches (grass, ferns, flowers, reeds, palm fronds): each frond or blade is a chain of up to three bending links
  (`Grower::frond` registers them in the same branch table). Plants lower than 1.4 m (`SMALL_PLANT`) are taken live only within 2.4 m
  (given back past 3.4 m, at most 160), the rest within 8 m (24 at most). Measured with 11 live: no frame-rate change, +2 ms process.

## Trees in the finer meshes at the default ground detail

The planet built every plant in the light meshes (polygon leaves, flat needle sprays, few-sided branches) below ground detail 2,
which is what Low and Medium use. `FloraMeshes.fine_trees` (set from ground detail >= 1, off with `PLANET_LIGHT_TREES`) now builds
trees and shrubs, which are few and near, in the fine ones (leaf cards, strips of leaflets, smoother branches and bark) through
`SpeciesRegistry.mesh`; grass, ferns and flowers (7x the triangles when fine) still wait for ground detail 2. Measured on the spawn
view: +7% primitives, +1.5 ms GPU (7.6 -> 9.1 ms, 129 -> 107 fps on the 4090).

## Turf: short grass all over the ground (PlanetTurf)

- `PlanetScatterNative.scatter` also returns `turf`: how well turf grows at each vertex of the padded grid (rain, warmth, slope, stones, shade
  of the crowns, patches; 0 on the beach, under 0.9 m and in the cold), kept as the holder's `turf` meta with the positions and the grid's
  own axes (`ax`, `az`: the grid is not lined up with the tile's xz).
- `PlanetScatterNative.turf_chunk(positions, field, cells, size, x0, z0, x1, z1, spacing, density, seed)` places the tufts of a square of
  the grid on a jittered grid (the same spots whatever the field says); `PlanetTurf` makes the 16 m chunks within 26 m of the walker
  (3 a look), lets them go beyond 36 m, one MultiMesh of `FloraMeshes.turf_tuft()` each (three crossed cards, 6 triangles). The blades
  are drawn by the plant shader (`grass_blades`, UV2.y of 8 marks a tuft; no far fill). About 24 000 tufts at the spawn; no measurable frame cost.
- `PLANET_NO_TURF` switches it off. Check: `--plants --grounded --turf-check` (TURF_CHECK).
