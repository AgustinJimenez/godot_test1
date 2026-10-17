# 054 - Universe foundation: seed, star systems, planets

Status: **stages 1-2 done (2026-10-17): `Star`, `StarSystem`, `UniverseSettings` (+ `planet_settings(system, planet)`) in `systems/planet/`; `planet_lab -- --universe=SEED [--systems=N] [--any]` prints the table and `UNIVERSE_CHECK PASS`; next: stage 3 (the star drives the sun)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Decisions (user, 2026-10-17): **many star systems are wanted** ("if possible, let's do it"); the focus is
the planet and the star, **not the player yet**; the flat world may be retired once the universe exists
([053](053_flat_world_parity.md)). Stars differ in colour and that changes life: see
[064](064_stars_and_life.md).

**Start small (user, 2026-10-17): the first version is ONE star and ONE planet, polished well; more planets
and many systems come later.** Build the data model for many (a list of systems, of stars, of planets) but
generate and show only one of each at first.

**Start menu parameters (user, 2026-10-17), for now:**
- *Home planet:* **sun-like and habitable** or **any** kind of star and planet.
- *Star colours:* **physical** or **readable** (see [064](064_stars_and_life.md): both exist, we look at
  the results and decide later which one stays).

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
5. Menus: the start menu creates a universe (seed; the two parameters above; the number of systems is 1 and
   the number of planets 1 for now); the Planet page shows the star and the planet's data (read-only until
   travel exists).
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
- **Decided:** a start-menu parameter (sun-like and habitable, or any); the universe size starts at one
  star and one planet.
- **Decided (user, 2026-10-17): keep both times, and do not make the time display a feature yet** ("I
  don't know if having the time noted is critical"):
  - *Universe time* is one number, seconds of play since the start (`PlanetClock.time` today), the same for
    every planet.
  - *Standard (Earth-like) time* is a fixed conversion, 1 standard day = 24 h = 1,440 s of play at 1x (the
    game compresses time 60x), and is what a Kepler orbit is measured in: `Star`/`Planet` data keep the
    true values (`day_standard_hours`, `year_standard_days` from the distance and the star's mass).
  - *Planet (local) time* is what the clock uses: `day_seconds` and `year_days` of the planet. The year is
    clamped to a game range (~6 to ~64 local days) so seasons are playable; the true year stays in the data.
  - Show local time (already in the Planet page) and, optionally later, the standard time and the true
    year next to it in the planet info panel; nothing else depends on it.
  - If it turns out not to matter, drop the standard time display and keep the numbers in the data.

## Notes (autonomous session, 2026-10-17, user away)

- Stage 3 begun: the star's colour tints the sun lamp, the sky and the clouds (`Star.light_tint`,
  `PlanetSettings.star_mass` / `star_readability`, lab `--star-mass=M --star-readability=R`). The Sun is exactly
  white, so the default planet looks the same. `PLANET_CHECK` and `SAVE_CHECK` pass.
- Pictures (seed 1337, 17:30, clear, no plants): a red dwarf (0.15) gives a grey-green sky and warm rocks, 0.55 a
  slightly warm one, 1.6 a bluer one. Only 75% of the colour difference is applied (the eye adapts,
  `Star.ADAPTATION`). **The user has not judged these**: compare `--star-mass=0.15|0.55|1.0|1.6
  --hour=17.5 --weather=clear --bare --view-alt=3 --view-pitch=8`.
- Still open in stage 3: sun disc size, brightness from distance, insolation into `PlanetSeasons`.
- Stages 4-6 partly done: insolation (L / a^2) drives `PlanetSeasons`; `UniverseSettings.home_settings()`; the start
  menu makes a universe (seed, home planet sun-like or any, star colours slider) and saves are version 3 with a
  `universe` block; `docs/planet_generation.md` has the Universe section. `UNIVERSE_CHECK`, `SAVE_CHECK` pass;
  `--home=7|1|99 --planet-check` pass. **`--home=42 --planet-check` FAILS** (`worst_gap` 4.4 m against 3 m on an
  11 km planet, tall relief on a small sphere, the same radius with the default seed passes): a terrain steepness
  question for small planets (see 057/061), not caused by the star changes.
- Not done: the Planet page shows no star data yet; the sun disc does not change size; the universe clock as one
  shared time is only data (local time is what runs).
- The sun's disc follows radius / distance (`PlanetAtmosphere.sun_size`, sky shader `sun_size`; the ellipse varies it
  through the year); checked with `--look-sun --view-alt=3 --insolation=1|4` (4 doubles the disc). Default unchanged.
