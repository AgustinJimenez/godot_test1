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
