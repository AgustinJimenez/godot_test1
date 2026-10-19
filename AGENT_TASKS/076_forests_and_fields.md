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
Not done: the depth (CUSTOM2.g) is not used by the shader yet (thin soil should show more bare rock), and the odds are
not used by the placed pebble and rock instances (`_pebbles`, `_rock_at` have their own odds by biome).
