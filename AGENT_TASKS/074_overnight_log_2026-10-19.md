# 074 - Overnight log, 2026-10-19 (the three tasks)

All of it is pushed to `main`; `scripts/planet_check.sh --quick` passes except `gdlint` (not installed here).
Mac: the native libraries need a rebuild there (C++ changed), and open the project once so Godot scans
the new script classes.

## The grey screen (fixed, two causes)
1. Nothing is drawn under ~70 m above the sea (far/near plane ratio past 2^24): the near plane is now
   never under far / 1e7 (`PlanetWorld`). Coasts, beaches and low plains looked grey.
2. A parse error of my own in `PlanetAir` made the whole world fail to load for a while (fixed, pushed).

## Task 1: the references (AGENT_TASKS/072 has the list and the loop log)
Ozone in the air model, plant-cover colour on the ground (green land), meadows (dry-grass patches, clumps,
flowers), a warm / cool haze split toward the sun, morning mist, dawn fill light, a screen-space mirror of
the land on the water (seen working on a lake), dust and pollen (setting `particles`), thinner base fog,
the default start is the world (the map only on `--map-first`). Cloud rings and orbit speckle fixed.

## Task 2: native C++ (AGENT_TASKS/073)
River and lake water queries native (`water_at`, `near_water`, `flow_at`), the script hydrology off by
default: ground ready in 1.3 s instead of 6.8 s at full Earth size. Plant batches: one `MultiMesh.buffer`
write and a native tint. Measured: what is left is the plants' mesh generation in script (1-4 s on the
first tiles) and the placement (~95 ms a tile); a native plant mesh generator is the next big step.

## Task 3: plants, rocks, terrain
The planet never had the realistic plant look on: now `FloraMeshes.detailed` (from the Fine ground detail)
and the `realism` global are set. Compound leaves and fern fronds use veined leaf outlines, crowns can
use cards of many small leaves, grass clumps have more and slimmer blades, pebbles, footprints and
meadow flowers on the ground. Tile occluders are made on the main thread (a crash at exit).

## Not done / next
- Plant meshes generated natively (the stall on the first tiles), denser fine grass near the player,
  real flower meshes, ground plants that are still fans of triangles (some species), rock meshes with
  noise displacement, bark textures, terrain debris (fallen branches, leaf litter by moisture).
- SDFGI resets some GPUs (off in every preset); close-up shore and river water not yet looked at.

## Added later in the night
- The game start (the lab with no arguments) has the plants on now (ground ready after 4.5 s at the
  game's size, High). The other lab starts and the checks keep them off.
- Veined leaflets only for low ground plants (the palm's triangle budget in the species check).

## Continued (after the user's "you did not continued")
- `PlantMeshNative` (task 2): the tree grower, leaf shapes, tube builder and smooth normals in C++: 7.5x faster than
  the scripts (see 073). Ground plants are now grown in the full realistic version at High/Ultra (before they were
  always the light one): grass tufts of up to 40 thin blades with 6 bends, flowers in whole clumps.
- The grass grid is 0.6 x as wide in the realistic look (`PlanetScatter.GRASS_FINE`): a meadow of tufts. Seed 8 meadow at
  High: ground ready after 1.7 s (it was 4.5 s with plants before the native meshes), 85 fps, 18.3 M primitives.
- Forest-floor debris (`FloraMeshes.LITTER` / `TWIGS`, `PlanetScatter._debris`, Fine ground detail and up): fallen leaves and
  sticks, thick in forests, some in meadows.
- Procedural bark (`flora_wind.gdshader` `bark_at`): the native tubes write UV.x = -(1 + way round), UV.y = metres along,
  UV2.x = radius, so furrows run along each branch (round trunks and horizontal limbs alike), cracks, grain, moss at the
  foot of a trunk, lichen, and a screen-space bump. Boulders (`MeshBuilder.add_rock`) are a ball cut by flat planes with
  strata, joints and grain in the shader (UV.x -0.25 marks a rock). `tests/manual/world/rock_lab.gd` renders the scenery
  or the species of one growth form (`form:PALM`) with a camera of choice: use it for close looks.
- Palm / fern leaflets, feather leaves and conifer needle branchlets are strips along the rib drawn by the shader
  (`pinnate`, UV2.y 4 + rows/100, needles 6 + rows/100) in the realistic look, at every level of detail (the lighter
  version of trees uses cards too, so no more big flat triangles when seen from above; 18.3 M -> 16.1 M primitives).
- Far trees have a crown of four lumps in their own tones.
- Still unrealistic (next): the far forest (beyond 220 m only sparse far trees on bare hills: dense canopy needs a
  far canopy layer or a terrain colour that carries the forest), compound/needle detail at mid distance, leaf
  shading (very light leaves under strong sun), tree trunks of low-poly angular look from 5 sides, flowers, reeds.
