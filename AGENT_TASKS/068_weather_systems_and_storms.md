# 068 - Weather systems and storms

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Question that started it (user, 2026-10-17): does the weather make storms when the conditions are met, like in
real life? Today: partly. This task makes storms real structures with real causes.

## Where we are (what the code does now)

- `PlanetWeather.at(dir, ground, clock)` gives the weather at a place and time: **CLEAR, CLOUDY, RAIN, STORM,
  FOG, SNOW**. It is a pure function of the date (nothing stored; time can run backward).
- **Cloud readiness** = moisture x lift: moisture from the sea's temperature and the rain climate; lift from
  the trade-wind belt (follows the sun with the seasons), the storm tracks of the middle latitudes, and
  mountains; held down under the subtropical highs. The cloud cover is a noise pattern carried east or west
  by the zonal winds and morphing slowly.
- **Rain** where the cover is thick (> 0.8), readiness > 0.45 and a cell value > 0.05. **STORM** only as a
  subcase of rain: readiness > 0.8, a strong cell (> 0.3) and warm (> 20 C). **SNOW** below 0.5 C.
  **Fog** on a wet, still morning.
- `WorldWeather` turns the chosen state into effects: clouds, rain and snow, wind strength, wetness,
  lightning and thunder (storm only), ground wetness and snow cover; the wind direction follows the zonal wind.
- So yes: storms appear when the place is moist, lifted, warm and under a strong cell; they move with the
  winds and come and go with the seasons. But they are a *state at the player's position*, not an object.

## What is missing compared with real storms

- No **structure**: no front that moves and passes, no low-pressure system, no cyclone with a track and an
  eye, no squall line, no individual thunderstorm cell that grows, rains and dies in an hour.
- No **instability**: real thunderstorms need warm moist air near the ground under cold air aloft (convective
  available potential energy) plus a trigger; the model uses temperature above 20 C as a stand-in.
- No pressure field: wind is the zonal pattern plus noise; there is no pressure gradient, no wind shift as a
  front passes, no pressure drop before a storm.
- Storms are not seen *coming*: the cloud layer ([048](048_cloud_polish.md)) shows the cover but not a tall
  anvil cell on the horizon; rain falls on the player or not.
- No blizzard (snow plus strong wind and low visibility), no hail, no dust storm (needs
  [065](065_atmosphere_composition.md)), no tornado or waterspout, no tropical cyclone (needs a warm sea,
  distance from the equator, low wind shear), no monsoon, no drought or flood years.
- Lightning is a timer while the state is STORM; no strikes on tall things, no fires, no thunder delay by
  distance.

## Plan

1. **Pressure and wind field.** A coarse pressure field as a function of the date (large-scale highs and
   lows from the zonal pattern, the land-sea contrast and the seasons, plus travelling waves along the storm
   tracks); wind = geostrophic flow around it (with the Coriolis factor from the spin: fast spin gives
   bands, slow spin one big cell, see 065); surface wind from the gradient. Keep it a pure function of the
   date.
2. **Fronts and lows.** Mid-latitude lows travelling along the storm tracks (a moving centre each, spawned
   by hashing the date in windows, lasting days) with a warm and a cold front; passing one changes the
   wind direction, the temperature and the weather in a recognisable sequence (cirrus, thickening cloud,
   rain, clearing and a cold gust).
3. **Convective cells.** Thunderstorms from instability: warm, moist near the ground (the sea or wet land in
   the afternoon in summer) with a trigger (a front, a mountain, daytime heating); each cell is a short-lived
   tall cloud (3-10 km, an anvil) with heavy rain, hail optional, lightning, a gust front; cells drift with
   the winds and die in an hour or two; a function of the date and position (a hash of grid cell and
   hour), as the clouds are, not a stored simulation.
4. **Tropical cyclones.** Over warm seas (> 26 C) beyond ~5 degrees from the equator, in the warm season: a
   spiral system with a track (curving poleward and east), an eye, a rain band structure, a storm surge on
   the coast ([049](049_water_and_coasts.md)); lifetime days; rare. A look from orbit (the spiral in the cloud
   picture) is the payoff.
5. **Winter weather.** Blizzards (snow plus wind plus a white-out fog), freezing rain optional, snow
   squalls off a warm sea or lake.
6. **Dust and ash storms** with the air model ([065](065_atmosphere_composition.md)) and volcanoes
   ([067](067_volcanoes_and_crust_activity.md)): a wall of dust on dry windy ground, an ash plume's fall.
7. **See it coming.** Feed the systems into the cloud cover picture and the cloud march so a front is a line
   of cloud, a thunderstorm an anvil on the horizon, a cyclone a spiral from orbit; the radar-like layer in
   the map (rain intensity, systems with their tracks) as a debug and play view.
8. **Effects.** Wind shifts and gusts (sway amplitude, rain direction), the pressure drop in the HUD later,
   lightning with thunder delayed by distance (the sound travels ~340 m/s; per planet by the air:
   [065](065_atmosphere_composition.md)), rain intensity by cell, hail, flooding rivers after heavy rain
   (hydrology with a rain input, [049](049_water_and_coasts.md)).
9. **Safe for now** (user, 2026-10-17, as for eruptions): storms are scenery; no damage to the player.
10. **Checks.** A lab mode that prints the weather and the systems around the player over a month of play
    (`--weather-log`), and a check that the same date gives the same systems in two runs, that going back in
    time gives the same state, and that storms occur where and when the rules say (a count by latitude and
    season: more at the storm tracks, a cyclone season, none over cold seas).

## Done when

- The same planet shows a front passing in a recognisable sequence, thunderstorm cells growing and dying
  in the warm afternoons, and (on a warm planet) a cyclone with a track, all of them as functions of the
  date, visible from afar and from orbit; the doc has a "Weather systems" section.

## Risks and open questions

- Cost: systems must be evaluated at the player, the cover picture (256 x 128 every few seconds, on a
  thread) and the map; keep each system's contribution a cheap function with a spatial lookup of the few
  systems near a point.
- Time controls run thousands of times faster and backward: windows of a hash by date keep it consistent but
  a system that lasts days looks different when time is sped up; check at 1000x.
- A planet's size changes everything (a storm 1,000 km wide on a 20 km planet): scale systems by the
  radius and the number of systems by the area; write the rule down.
- The weather is a large part of "real causes": keep the model simple enough to explain in the doc.
