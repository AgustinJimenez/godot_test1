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
2. **Terrain exists only as noise at metre scale.** (2026-10-18: pale scree colour on moderately steep high slopes; no real talus shape.) No cliffs where hard rock outcrops. Idea: a thermal-erosion pass on the tile (steep slopes relax to the angle of repose).
3. **Glaciers.** (2026-10-18: above the snow line the valleys are wide with a flat floor and steep walls, a U instead of a V, native and script alike; glacier ice is blue-white on gentle ground where it is very cold, on the map too. Still missing: cirques, moraines, ice that flows and fills the valleys as a surface.) Cold high ground should carve U-shaped valleys, cirques and moraines, and fill them with ice.
4. **Lakes.** (2026-10-18: the drainage's lake cells now pass their water level to the native crust: the ground sinks under it with a soft shore and the Terrain map paints the water; only on the 512-cell grid, so lakes are big ones; the water layer is still off.) Inland basins are bowls, not lakes. Lakes should sit where the drainage ends in a closed basin
   (it already finds them: `lakes=581` in DRAINAGE_CHECK) with a flat surface and an outlet river.
5. **Deltas, estuaries, fjords, canyons, karst and volcanoes** are missing (see 057, 067). (2026-10-18: canyons: where it is dry and the ground raised, a river's valley sides climb 1.85 instead of 0.35 per metre away (not yet looked at from the ground); dunes exist, native only: ~170 m ridges 7 m high on flat, hot, dry ground.)
6. **Sea floor.** (2026-10-18: island arcs are broken into chains with gaps and the mid-ocean ridge is offset in steps like transform faults; trenches stay. Still missing: abyssal plains, seamount chains, fracture zones. Tried 2026-10-18 and removed: seamounts from the foothills noise (speckle over the whole sea) and from the massif noise (not visible); they need a plate-aware source, such as the hot spots along a plate's motion.) Plate boundaries show as parallel double lines; real ones have trenches, ridges with
   transform faults, abyssal plains, seamount chains and island arcs.

## Climate and weather

7. **Clouds** (2026-10-18: the belts now vary by longitude, warm pools and cold tongues, and the storm tracks lean). Still arranged in latitude belts.
   Real cover is broken by the warm and cold waters under it, has diagonal fronts, tropical clusters and
   hurricanes (see 068).
8. **Temperature**: land heating and currents are crude (a few degrees from cell neighbours). (2026-10-18: sea ice is drawn on the map from the sea's mean temperature, a ragged gradual edge; it does not yet reflect light in the climate.) Missing:
   snow albedo from real snow cover, El Nino-like swings, a proper monsoon wind.
9. **Rain** (2026-10-18: the climate grid is 384x192 now, with the per-cell terms scaled; rain shadows to ~100 km) follows the winds on a grid: no rain shadows finer than ~200 km, no orographic rain from
   the real ridges.
10. **Seasons of the plants**: leaves, snow cover on the ground and the dry season do not change the colours.

## Life and the surface

11. Plants and animals are off by default and not tied to the biome map the planet produces.
12. **Soil** (2026-10-18: the ground colour now mixes in a soil tone by rain, warmth and slope: dark and deep where wet and mild, pale and thin where dry, none on steep rock; same in the native and script crusts). Still missing: soil depth that changes the shape, wetlands, desert crust, the plants' own seasonal colours.
13. **Water layers** (sea, rivers, lakes) are off by default; river widths and the shore are not checked on
    the whole Earth.

## How to check

- `scripts/planet_check.sh --quick` (the native step runs without erosion: the script crust has none).
- Look at the map: `planet_lab --earth --seed=N --show-map --map-layer=0 --map-zoom=Z --shot=PATH`.
- The player must stand on the same ground the tiles draw: `PlanetNoise.height` asks the native crust.

## Fixed numbers that are the same on every planet (audit 2026-10-18)

Done: the rain belts and wind edges (`PlanetClock`-free: `PlanetClimate.circulation`, drawn from the seed, used
by the native and script rain and by the weather); the cloud belts, their strength and breaking.

Still fixed, in order of how much they show:
- **Zonal wind profile** (done 2026-10-18: `circulation.wind_k`, -cos(k lat), drawn from the seed and shared by the weather, the rain edges and the heat carry; a real spin-rate link is still open).
  (native too). Real planets have 1 to 4 cells per hemisphere by how fast they spin. Idea: a `cells` number from
  the day length and use it in both.
- **Heat model** (2026-10-18: `PlanetSettings.greenhouse`, rolled 0.85..1.25 by `vary()`, scales the light the energy balance sees; the star's light was already `insolation`): EMIT, FLOOR, SEA_TAU, LAND_TAU, MIX, the HOT cap: one planet's physics. Should follow the
  star's insolation and the air/sea share of the planet (`PlanetSettings.insolation` already scales the light).
- **Sea level** share of land (2026-10-18, widened: water amount x0.3..2.8 log-uniform, land 22 to 67 % over ten seeds; earlier: x0.55..1.6 and tilt 8..38 from the seed with `PlanetSettings.vary()`; land came out 43 to 64 %). Real planets span water worlds to deserts: the roll could be wider and the plates' continental share could vary too.
- **Plate boundary sizes** (BOUNDARY, SOFT, CONTINENT, OCEAN heights) and the HYPSO curve.
- **Rain model constants** (RAIN_BASE, RAIN_SCALE, the 0.996 decay, the 192x96 grid).
- **Erosion tunables** (EROSION, EROSION_SCALE, octaves): the same look on every world; a wet planet should be
  more eroded than a dry one (scale by the climate's rain at the point).
- **Biome thresholds** (snow line at -0.5 to -4.5 C, beaches at 4 m, tree line).

- 2026-10-18: deltas (a big river near the sea flattens the ground to ~3 m over a wide fan; native) and wetland colour (dark green-brown on low flat wet ground; native and script). Neither looked at on the ground yet; the map's illustrated colours do not show the wetland.

## How to look at a place (2026-10-18)

`planet_lab --earth --seed=N --dir=x,y,z --shot-frame=1500 --shot=PATH` starts the player at that unit direction. To find
a direction (a desert, a coast), run a small `-s` script that builds `PlanetNoise` and scans a spiral of points by
`climate.sample(dir)` and `height(...)`. Seen so far from the ground: a desert on seed 8 (pale sand, gentle dune
swells of 7 m over ~170 m: soft, not sharp ridges).

- 2026-10-18: the haze follows the climate: `PlanetAtmosphere.haze_wanted` (0.55..2.05 x the base fog by warmth and rain) and `dust_wanted` (hot and dry: extra density and a tan tint), set from `climate.sample` in `PlanetWorld._pick_the_weather` and eased in. Seen: the desert on seed 8 is tan-hazed. Open: the delta of seed 8 (--dir=-0.95545,-0.29145,-0.04661) renders as a flat olive plane though the height profile varies: unexplained.

- 2026-10-18: map max zoom 60 -> 1500 (about 15 m a pixel; the grid lines get finer with the zoom) and the map opens at it. At that zoom the map showed: (1) hundreds of inland puddles (hills and gullies dipped the low basins below the sea: fixed in both crusts, the same 8 m bowl as the macro ground); (2) a big river as a ~1 km flat strip with a dark cliff on one side (the canyon walls of a river in dry ground: a huge flood plain, the floor is up to 30% of a drainage cell wide); (3) faint straight lines along the drainage cell borders (valleys cut at a cell edge: not fixed); (4) the river's water is not drawn (rivers are valleys only while `hydrology_on` is off): the map could paint `river_waters` where the channel is.

- 2026-10-18 (autonomous run): river water is drawn on the Terrain map when a pixel is under 400 m (a channel of half the valley floor, from the nearest piece). Fjords: where the cold is permanent a glaciated valley may cut up to 12 % of the relief below the sea near the coast and the inland bowl floor is lifted there (both crusts); NOT yet seen on screen (the polar coast I looked at on seed 8 is a flat shelf, not mountains). The sea ice already feeds the climate: the heat model's `frozen` albedo applies to the sea cells too. The river of seed 8 ends abruptly in the open at the east of --dir=-0.95545,-0.29145,-0.04661 (pieces are listed in the 9 cells round their middle, so it is not a cell seam: look at river_network's ends). The lakes of the 512 drainage grid are blocky (rectangular cells with straight edges, dark in the map).

- 2026-10-18 (autonomous run): seamount and island chains from fixed hot spots (9 from the seed, `PlanetNoise._hotspots`): a plate drifting round its spin axis carries each volcano along the circle through the hot spot, smaller with age (native only, with the erosion switch). The seed 8 map shows diagonal strings of islands in the open ocean. The seed 8 river end / `flat olive plane` seen at --dir=-0.95545,-0.29145,-0.04661 is a real flat coastal plain of ~10 m: not a bug.

- 2026-10-18: map blur after zooming out and in: a close chart made at a lower zoom enclosed the view, so no sharp one was charted (now `_sharply_covered` also needs ~0.7 chart pixels per screen pixel); the loading note comes back whenever the view is not sharp. Lakes of the 512 drainage grid no longer sink hills inside their cell (only ground within ~30 m of the water fills) and the spawn skips lakes: the default seed-8 spawn had been inside a 20 km wide flat lake.
