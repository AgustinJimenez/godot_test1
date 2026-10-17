# 057 - Terrain realism

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Landscapes that read as real geology: mountain ranges at plate boundaries, valleys cut by rivers, cliffs
and strata, beaches, dunes, glaciers, a snow line, and smooth biome transitions.

## Where we are

- Tectonic plates blended smoothly (`PlanetTectonics`, 4 nearest plates), noise (`PlanetNoise`), a coarse
  hydrology with stream-power erosion (`PlanetHydrology`, 96 cells per face), climate from temperature and
  rain (`PlanetClimate`, `PlanetSeasons`), biome colours in the ground shader with planet-anchored detail
  (patches, bare soil, rock strata on steep faces, a bumpy normal).
- Known problems fixed before: walls at the coast and at plate junctions. Open: rivers ending at cliffs
  ([049](049_water_and_coasts.md)).
- There are no caves, overhangs, rock arches, scree, glaciers, deltas, dunes, volcanoes or craters.
- The terrain is a height field per tile (a mesh and a `HeightMapShape3D` collider): no overhangs.

## Plan

1. **Mountain ranges.** Fold mountains along convergent boundaries, rift valleys at divergent ones, a few
   volcanic arcs; relief and ridge sharpness (a ridged noise) driven by the boundary type and age.
2. **Erosion detail near the player.** A second, finer erosion pass (thermal, a few hundred metres) on the
   finest tiles that carves gullies along the slope; deterministic, from the tile's key and the height
   function (no stored data), on the worker threads.
3. **Snow line and glaciers.** A snow line from the temperature and the height (`temperature` by height
   exists), permanent snow above, a glacier tongue where the slope is low and the cold is steady, a pale
   blue ice material; seasonal snow that retreats by the year.
4. **Beaches and shores.** Sand where the slope is low and the waves reach, shingle, cliffs where steep;
   a gradual colour change from sea to land.
5. **Deserts.** Dunes (an anisotropic noise along the wind), dry riverbeds, salt flats, rock pavements.
6. **Volcanoes and craters** (rare features): a cone with a crater, lava rock colour, ash fall; impact
   craters on the airless planets of [061](061_other_planet_types.md).
7. **Caves and overhangs** need volumetric terrain: out of scope except as separate placed features
   (a cave mouth in a cliff as a mesh with a room behind it; see how `procedural_room_generation_plan.md`
   did rooms).
8. **Biome transitions.** Smooth blends with an ecotone (mixed species) instead of a line; check the
   ground shader's colours against the plants' fitness.
9. **Map layers.** Add Snow line, Erosion/rock type and Soil depth to the map's layers.

## Done when

- A set of screenshots (range, gully, glacier, beach, dune field, volcano) is in the doc; the planet
  checks pass; the extra per-tile cost is measured and within the tile build budget.

## Risks and open questions

- Everything must stay a pure function of the seed and the position (so tiles built in any order agree and
  saves do not store land).
- Heights feed colliders and plant placement: sharper relief changes the walkable slope everywhere; test
  with `--walk-check` on steep seeds.
