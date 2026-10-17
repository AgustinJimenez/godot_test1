# 054 - Universe foundation: seed, star, planets

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

A universe that holds several planets around a star, all derived from one seed, each planet still built
the way the one planet is built today. No travel yet (that is [055](055_space_travel.md)).

## Where we are

- One planet: `PlanetSettings` (seed, radius, relief, ocean fraction, plates, species count, day and year
  length, axial tilt, start hour and year, air height...) makes it; `PlanetClock` (orbit, spin, tilt) and
  `PlanetMoon` (its one moon) are per planet; the star is implicit (one white sun, energy 1.35,
  direction from the clock).
- `UniverseSave` (v2) already stores a list of planets, each with its settings, and which one is current.
  The start menu's "seed" is the first planet's own seed.
- Decided: a universe is the container; a planet is built one at a time ([043](043_planet.md) "The universe").

## Plan

1. **Universe seed and `UniverseSettings`.** A seed, a star, a list of planets with an orbit each
   (distance, period, phase) and a size class; derive each planet's `PlanetSettings` from the universe seed
   and the planet number (deterministic: planet N of seed S is always the same).
2. **The star.** Type (colour temperature, luminosity, size on the sky), which drives the sun's colour in
   the sky shader and the cloud shader (today a constant), the light energy, the stars' look on other
   planets, and a habitable distance. Planets get a temperature from the star's light and the distance
   (the seasons model already has an energy balance: feed it the insolation).
3. **Planets and orbits.** Positions on circular (later elliptical) orbits as a function of time; the
   planet's year follows its orbit; day length from its spin; the sun's direction is the star's direction
   from the planet's position (today: `PlanetClock` makes the sun go round the one planet).
4. **Moons.** Per planet, 0-2, each with an orbit, size and phase (`PlanetMoon` is one static moon now).
5. **The universe clock.** One time for all planets (`PlanetWorld.clock` becomes the universe's and each
   planet reads it); the time controls act on the universe.
6. **Menu.** The start menu creates a universe (seed, number of planets), the Planet page shows the planet
   list of the current universe (read-only until [055](055_space_travel.md)).
7. **Save.** `UniverseSave` gets the universe settings (version 3, migrate v2); check the old saves open.

## Done when

- The same universe seed gives the same star and planets in two runs; a save reopens the same one.
- The sun's colour and brightness on planet 1 and planet 2 differ by their distance and the star.
- `SAVE_CHECK` covers the universe settings; docs updated (`planet_generation.md` "Universe").

## Risks and open questions

- **Open (user):** one star system, or many (a galaxy of systems)? Start with one, keep the seed layout
  open for more.
- Per-planet clock and moon code assumes one planet; list the places (`PlanetWorld`, `PlanetClock.copy()`
  used by the cover picture thread, `PlanetChart`).
