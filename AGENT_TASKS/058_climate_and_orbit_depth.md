# 058 - Climate and orbit depth

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Deepen the "real causes" model: heat moved by the sea and the wind, an orbit that is not a circle, tides and
moon effects.

## Where we are

- Temperature is an energy balance over a repeating year kept as 48 snapshots (`PlanetSeasons`: land tau
  0.05 y, sea 0.2 y, snow albedo 0.3, a hot cap of 27 C, a mixing of 0.3 over three passes); the yearly
  mean is for biomes, `temperature_now` adds the season and the hour.
- Weather from moisture and lift: trade belt, storm tracks, subtropical highs, zonal winds
  (`PlanetWeather`); clouds from the cover; the cover is a function of the date.
- Orbit and spin are circular and constant (`PlanetClock`); axial tilt 23.4; the moon has a fixed orbit
  and phases (`PlanetMoon`, month 3.5 days); no tides.

## Plan

1. **Heat carried by the wind.** In `PlanetSeasons`, advect the temperature along the zonal wind (a
   few passes of an upwind scheme) so the west coasts of continents are milder than the east ones.
2. **Ocean currents.** A simple gyre pattern from the winds and the coasts that carries warm water to
   high latitudes (Gulf Stream like) and cold water along the west coasts; affects the sea temperature and
   with it the moisture and the coastal climate.
3. **Rain shadow and monsoon.** Moisture lost on the windward side of mountains (exists as lift), dry
   lees; seasonal reversal of the wind over a large continent (a monsoon) as a function of the seasons.
4. **Elliptical orbit.** Eccentricity (0-0.2): Kepler's equation for the planet's place, a seasons model
   that uses the distance (insolation ~ 1/r^2) and a perihelion date; the day-length model follows.
5. **Tides.** The moon (and the star) raise the sea; see [049](049_water_and_coasts.md) for the sea level
   side. Here: the model of the amplitude by the moon's distance, phase and the coast's shape.
6. **Moon.** A moon on its own orbit (inclination, eccentricity), eclipses (the moon's shadow on the
   planet, the planet's shadow on the moon) as a result of the geometry, not scripted.
7. **Climate maps.** Layers for the ocean currents, the wind vectors and the sea temperature in the map.

## Done when

- The map shows warmer west coasts at high latitudes; the yearly cycle changes with eccentricity; an
  eclipse happens when the geometry says so and not otherwise; seasons stay deterministic by date.

## Risks and open questions

- Every step is a model on a grid cell (the snapshots are 48 per year per grid): keep the memory and the
  build time bounded (the climate is built at the start; measure it).
- The seasons run backward as well as forward (time can run back): keep everything a function of the date.
