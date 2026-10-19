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
