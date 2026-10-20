# 049 - Water and coasts

Status: **partly done (2026-10-17): no overlaps** (rivers end at the shore, sources in the sea are dropped, the ground between nodes is used for the level, nothing grows within `BANK` 4 m of a river, the river material draws after the sea and lakes; `WATER_CHECK` in `planet_check.sh` counts river points over the sea or above a lake); the plan below is not started. Follows [043](043_planet.md). Branch: `main` (it was `godot-4.7-upgrade` until 2026-10-20).
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Rivers, lakes and the sea that look right where they meet the land, and that behave right under and
on the player.

## Where we are

- Hydrology on a coarse cube grid (`PlanetHydrology`: stream-power erosion, rivers, lakes), `river.gdshader`,
  `planet_water.gdshader` (sea), `PlanetSwim` (swimming, a splash), a foam line and a pale shelf at the coast.
- Open ideas already listed in 043: rivers ending in cliffs at steep coasts; tides.
- Rain ripples exist on ground puddles only, not on water. Underwater: fog colour and a darkening, no caustics.

Sea caves and underground rivers that sink and re-appear are in [066](066_caves_and_underground.md).

## Plan

1. **River mouths.** Where a river reaches a steep coast it should widen into an estuary or fall as a
   waterfall; today it can stop at a cliff edge. Carve the mouth in the height function near the coast;
   deltas where the slope is low.
2. **Tides.** The moon's pull (`PlanetMoon`) raises and lowers the sea level by a few metres with the
   moon's phase and the sun; a tidal flat appears at low tide. The sea level is a number in the height
   function: make it a function of the clock and check the cost (tiles' water meshes, colliders).
3. **Waves.** Wind-driven waves (amplitude and direction from the planet's winds), breaking foam at the
   shore, a depth-dependent colour; a cheap Gerstner sum in the water shader with a distance fade.
4. **Rain on water** (ripples) and a splash for things hitting the water; wetness of the shore.
5. **Underwater.** Caustics on the sea floor, god rays from the sun through the surface, a colour that
   follows the depth and the sky, plankton specks; swimming with an air meter is out of scope.
6. **Lakes at height and frozen water.** Ice in cold biomes (a surface that you can stand on at a
   threshold of the temperature), snowmelt rivers by season.
7. **Rivers in the map** layer as lines (the Terrain layer shows them already; check the others).

## Done when

- Screenshots of an estuary, a waterfall into the sea, a tidal flat at low and high tide, a stormy sea and
  a frozen lake.
- `--swim-check` still passes; a tide check shows the sea level rising and falling over a month.

## Risks and open questions

- Moving sea level interacts with spawn finding, colliders on the beach and the planting rule (nothing
  grows in water): a plant on a shore that floods needs a rule.
- The hydrology is on a coarse grid: fine river detail near the player may need a second pass.
