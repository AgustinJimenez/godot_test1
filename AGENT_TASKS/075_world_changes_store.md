# 075 - Storing what the player changes (design, nothing built yet)

Decision (2026-10-19, with the user): the planet is never stored. The ground, the water, the climate and the plants are
functions of the seed and cost about 14 ms a tile to rebuild; the whole planet would be 50 PB at Earth size (87 billion tiles
of about 600 KB) or 200 TB at game size, and generating it first would take years. What is kept on disk is what cannot be
recomputed or what is slow to recompute:

1. **The world's settings and seed** (the save, already: `UniverseSave`).
2. **The slow global data, per world** (a cache, thrown away freely): the river network (`PlanetDrainageCache`, 1.9 s on a
   full Earth -> 60 ms) and the map pictures (`PlanetMapCache`). Keys include the settings, a VERSION and the times of the
   native library and the scripts they come from.
3. **What the player changed** (not built yet: there is no digging, building or item system in the planet to feed it;
   `PlanetMap.world_changed(area)` is the hook the map already has for it).

## The changes store (3), when something can change the world
- A change is a small record in the tile's own terms: `(face, level-17 tile x, y, kind, position in the tile, parameters)`:
  a crater (radius, depth), a mound, a removed plant (its index in the tile's deterministic placement: the placement is
  stable for a seed, so "plant #k of this tile" names it), a placed object (id, transform), a burnt patch.
- One file per world, `user://worlds/<id>/changes.bin`, append-only records plus an index by tile (a dictionary of
  tile key -> file offsets, written at the end and rebuilt if missing). Only the finest tiles carry changes; a coarser
  tile asks for the changes of its children (a crater is big enough to show in the level above) through a small quadtree
  summary.
- Applying: `PlanetTile.build` and `PlanetScatter` ask the store for the tile's records after the crust's heights and the
  placement, and edit the heights (a crater is added to the native height array before normals, colours and the collider) or
  skip/add instances. The native placement takes an "exclude these plant indices" list and extra instances in its tile
  dictionary; the crust takes a list of height edits for a tile (native, so the edit costs nothing per vertex).
- Changing the world calls `world_changed` with the area so the map forgets those pictures (it already does).
- Size: a record is 32-64 bytes; a million changes are tens of megabytes. Nothing scales with the planet's size.

## Streaming
Tiles already stream by distance on worker threads; the store is read by those workers (a read-only memory map after the
index is loaded) and written only by the main thread. Prefetch by the player's velocity (build the tiles ahead of the move)
is a separate, cheap improvement of `PlanetSurface.update`.

## Spawning (done, 2026-10-19)
The character never starts in the sea, a lake or a river: `PlanetWorld.start` runs the asked-for direction through
`PlanetNoise.solid_spawn`, which keeps it if `is_solid_ground` (3 m or more above the sea, no river or lake water within
6 m, no cliff or sea within 8 m) and otherwise searches widening rings round it (to 30 km), and last falls back to
`find_spawn`. The character stays held (process disabled) until the ground within 2 km and the plants within 60 m are built;
then a ray from above finds the collider at the spawn and puts them on it (`_stand_on_the_ground`: it also fixes the 1 m the
height formula adds), and only then are they let in. A check starting in the sea on purpose sets
`planet.spawn_on_solid_ground = false` (the swim check). `--spawn-check` (in `planet_check.sh`): 120 random starts on seed
7, none ends up not solid (96 of them had to move). Future mining or digging must keep this true: the spawn point is
re-validated against the changes store (a dug pit or a flooded hole is not solid ground).
