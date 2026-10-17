# 061 - Other kinds of planets

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.

**Note (2026-10-17):** do it together with [064](064_stars_and_life.md): the star decides much of what a planet is
(temperature, locking, plant colours).
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Planets that are not temperate Earths: desert, ice, ocean, volcanic and airless worlds, and gas giants to
look at from afar. All from the same code with different settings, following "real causes".

## Where we are

- `PlanetSettings` (radius, relief, ocean fraction, species count, plates, axial tilt, day and year length,
  air height...) already changes a lot; radius works from a few km to Jupiter (a pass was run on the double
  build); `PlanetAir` has `air_scale` and `MIN_AIR_SCALE`; the sky's colour comes from Rayleigh and Mie
  coefficients that are constants (Earth's).
- There is no gas composition, no pressure, no airless planet (the sky shader has space black above the
  air, so an air of zero thickness is nearly supported), no star colour.

## Plan

1. **Atmosphere settings.** Pressure (scale of the density), composition as scattering colours (blue
   Rayleigh on Earth, orange-brown on a dusty planet, pale on a thin one), haze amount; airless: black sky,
   hard shadows, stars at noon.
2. **Climate by the star and the distance** ([054](054_universe_foundation.md)): a hot desert, a cold ice
   world with permanent snow, a water world with ocean fraction ~1, a tidally locked planet (day side hot,
   night side cold, the sun fixed in the sky: spin = orbit).
3. **Surfaces.** Airless: craters, regolith colours, no rivers, no plants; ice: bright, cracked sheets, no
   plants but lichens; volcanic: dark rock, lava, ash; desert: dunes, few plants (cacti).
4. **Gas giants** (seen from space, not landed on): a banded sphere (a shader with latitude bands and
   storms moving with the wind model), rings (a lit disc with shadows), moons that can be landed on.
5. **Gravity.** Each planet has a gravity from its mass and radius (the player's jump, fall and walking
   speed scale or stay as they are; decide), shown in the info panel.
6. **Presets** in the universe menu: "Earth-like", "Desert", "Ice", "Ocean", "Airless", "Volcanic".
7. **Check.** A lab run per preset that screenshots noon, dusk and orbit, and runs `--planet-check`.

## Done when

- Six presets run and look different at the spawn and from orbit; their checks pass; the doc lists the
  settings behind each.

## Risks and open questions

- Plant species fit by temperature and rain: on a cold or dry planet the species generator may produce few
  or none (an empty planet is valid, a crash is not).
- Gravity changes the player controller: ask before touching it (the user judges movement by feel).
