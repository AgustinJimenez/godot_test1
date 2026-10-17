# 060 - Map, HUD and tools for the player

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Help the player find their way and read the planet: a better map, a compass and mini-map, waypoints, a
time and weather HUD, a photo mode.

## Where we are

- Full-screen map on M (`PlanetMap`, `PlanetChart`): a picture made on a thread, zoom and drag, a region
  first, layers 1-9 (Terrain, Elevation, Temperature now, Rain, Biome, Plates, Slope, Mean temperature,
  Clouds), time controls (speed both ways, jumps, a year slider), numbers under the cursor.
- The Planet page of the Esc menu: time, weather override, new planet, saves, Open the map.
- No compass, no mini-map, no markers, no place names, no HUD clock; the HUD shows health and the
  inventory hint.

## Plan

1. **Markers.** The player's position and heading on the map, the spawn, user waypoints (place, name,
   colour) saved in the universe save; a HUD arrow and distance to the selected waypoint.
2. **Compass and clock.** A compass strip with the sun and the moon; the local time, the day and the
   season, the temperature and the weather as a small corner HUD, hideable.
3. **Mini-map** (optional): a small round window from the same chart code at a fixed scale, rotating with
   the player.
4. **Names.** Generate names for continents, seas, ranges and rivers from the seed (a syllable grammar);
   show them on the map; a "planet info" panel (radius, gravity, day and year length, tilt, the star).
5. **Photo mode.** Freeze time, free camera with a field of view, hide the HUD, take a screenshot into a
   folder; depth of field and exposure sliders; the lab's `--shot` is the model.
6. **Map layers.** Winds, ocean currents, snow line ([057](057_terrain_realism.md),
   [058](058_climate_and_orbit_depth.md)); a legend for each layer.
7. **Universe map** when [054](054_universe_foundation.md) exists: the planets on their orbits, the star.

## Done when

- A waypoint set on the map shows a distance and a direction in the world; names and the info panel render;
  the photo mode saves a screenshot.

## Risks and open questions

- The chart is built on a thread at a fixed resolution (256 x 128 for clouds): larger charts cost time;
  measure the build for the minimap's update rate.
