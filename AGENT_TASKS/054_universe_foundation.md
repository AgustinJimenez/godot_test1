# 054 - Universe foundation: seed, star systems, planets

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Decisions (user, 2026-10-17): **many star systems are wanted** ("if possible, let's do it"); the focus is
the planet and the star, **not the player yet**; the flat world may be retired once the universe exists
([053](053_flat_world_parity.md)). Stars differ in colour and that changes life: see
[064](064_stars_and_life.md).

## Goal

A universe made of many star systems, each with a star and planets, all derived from one seed, each planet
still built the way the one planet is built today. No travel yet (that is [055](055_space_travel.md)).

## Where we are

- One planet: `PlanetSettings` (seed, radius, relief, ocean fraction, plates, species count, day and year
  length, axial tilt, start hour and year, air height...) makes it; `PlanetClock` (orbit, spin, tilt) and
  `PlanetMoon` (its one moon) are per planet; the star is implicit (one white sun, energy 1.35,
  direction from the clock).
- `UniverseSave` (v2) already stores a list of planets, each with its settings, and which one is current.
  The start menu's "seed" is the first planet's own seed.
- Decided before: a universe is the container; a planet is built one at a time ([043](043_planet.md)).

## The layers

1. **Universe**: a seed and a size (how many systems; it can be a few hundred). Systems sit at positions in
   a region (a galaxy patch: a disc with arms, or a plain random volume to begin with); each system's seed
   comes from the universe seed and its index, so system N is always the same without storing it.
2. **System**: one star (or two: a binary is a later step, keep the data model a list of stars) and 0-12
   planets and their moons, orbits by Kepler's laws from the star's mass.
3. **Star**: a spectral class from its mass ([064](064_stars_and_life.md)): temperature, luminosity, radius,
   colour, lifetime, flare activity.
4. **Planet**: orbit (distance, eccentricity later), size class (rocky, large rocky, ice, gas), and the
   settings of `PlanetSettings` derived from the above (temperature from the star, tilt and spin random in
   ranges, tidal locking when close to a dim star).
5. **Planets are built from `PlanetSettings` as today**; only the derivation is new, so everything that
   works on one planet keeps working.

## Plan

1. `UniverseSettings` + `StarSystem` + `Star` (resources, pure data, deterministic from seeds) and a lab
   that prints a table of N systems (type, planets, distances, years) with `--universe=SEED`.
2. Derive each planet's `PlanetSettings` from system seed, planet number and the star; check the same ids
   give the same planet in two runs.
3. Make the star data drive the sun in the sky (colour, brightness, angular size), the light in the cloud
   and sky shaders, and the planet's insolation (the seasons model has an energy balance to feed).
4. The universe clock: one time for all planets; each planet's year and day follow its orbit and spin.
5. Menus: the start menu creates a universe (seed, number of systems, a preset like "sun-like only" or
   "all kinds of stars"); the Planet page shows the system's planet list and the star (read-only until 055).
6. Save: version 3 with the universe settings (migrate v2: one system, one planet).
7. A map of the universe (list first, then a picture): later, with [060](060_map_and_ui.md).

## Done when

- The same universe seed gives the same stars and planets in two runs; planet 1 of two different systems
  differ in sun colour and brightness; a save reopens the same one; `SAVE_CHECK` covers the universe
  settings; `docs/planet_generation.md` has a "Universe" section.

## Risks and open questions

- `PlanetWorld.clock`, `PlanetClock.copy()` (used by the cover-picture thread), `PlanetChart` assume one
  planet and one star: list the places before changing them.
- How many systems and how far apart (realistic is empty and slow): leave it a parameter; decide when
  travel exists.
- **Question for the user:** should the home planet of a new universe always be sun-like and habitable (a
  safe start), or can the start be anywhere (a red dwarf's tidally locked world)?
