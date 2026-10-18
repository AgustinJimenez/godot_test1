# 069 - What still keeps the planet from being realistic

Status: **open list (2026-10-18)**. The map is the way the user looks at the world, so a gap that shows on
the map comes first. Each line says what is wrong, what real planets do, and the idea for it.
Read `docs/planet_lessons.md` first.

## Done in the 2026-10-18 session (for context)

Hypsometric heights, snow line and beaches, a warmer climate, land heating in dry places and ocean currents,
clouds without wind shear and with swirls, an illustrated Terrain map with a true hill shading, a Satellite
layer, and **eroded ridges** (native `erosion_noise.h`: ridged gradient noise, each octave warped and damped by
the slope of the coarser ones, so valleys branch). Inland basins below the sea are shallow bowls now.

## Land shape (the biggest gap)

1. **Erosion is a texture, not a process.** (2026-10-18: the gullies now stand on the broad slope of the
   massifs and chains, so they run downhill toward the rivers; still not joined to the drainage network.)
   Tributaries do not join the network and valleys do not deepen toward the sea. Idea: run the
   drainage solve on a finer grid near the player and carve its tributaries as the finer valley levels.
2. **Terrain exists only as noise at metre scale.** No talus slopes, no cliffs where hard rock outcrops, no
   scree. Idea: a thermal-erosion pass on the tile (steep slopes relax to the angle of repose).
3. **Glaciers.** Cold high ground should carve U-shaped valleys, cirques and moraines, and fill them with ice.
4. **Lakes.** Inland basins are bowls, not lakes. Lakes should sit where the drainage ends in a closed basin
   (it already finds them: `lakes=581` in DRAINAGE_CHECK) with a flat surface and an outlet river.
5. **Deltas, estuaries, fjords, canyons, karst, dunes and volcanoes** are all missing (see 057, 067).
6. **Sea floor.** Plate boundaries show as parallel double lines; real ones have trenches, ridges with
   transform faults, abyssal plains, seamount chains and island arcs.

## Climate and weather

7. **Clouds** are still arranged in latitude belts: the equatorial band is a bell curve in latitude only.
   Real cover is broken by the warm and cold waters under it, has diagonal fronts, tropical clusters and
   hurricanes (see 068).
8. **Temperature**: land heating and currents are crude (a few degrees from cell neighbours). Missing: sea ice,
   snow albedo from real snow cover, El Nino-like swings, a proper monsoon wind.
9. **Rain** follows the winds on a 192x96 grid: no rain shadows finer than ~200 km, no orographic rain from
   the real ridges.
10. **Seasons of the plants**: leaves, snow cover on the ground and the dry season do not change the colours.

## Life and the surface

11. Plants and animals are off by default and not tied to the biome map the planet produces.
12. **Soil**: no soil depth, no wetlands, no desert crust. The ground colour follows rock, not soil.
13. **Water layers** (sea, rivers, lakes) are off by default; river widths and the shore are not checked on
    the whole Earth.

## How to check

- `scripts/planet_check.sh --quick` (the native step runs without erosion: the script crust has none).
- Look at the map: `planet_lab --earth --seed=N --show-map --map-layer=0 --map-zoom=Z --shot=PATH`.
- The player must stand on the same ground the tiles draw: `PlanetNoise.height` asks the native crust.
