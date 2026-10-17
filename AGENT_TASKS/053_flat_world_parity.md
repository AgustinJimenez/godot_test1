# 053 - Flat world parity and clean-up

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Bring the flat streaming world (`levels/procedural_world.gd`, `systems/world_gen/`) up to the planet's
quality where it shares code, and remove what the planet replaced.

## Where we are

- The flat world still uses Sky3D (`use_sky3d(true)` in `procedural_world.gd`); the planet does not (it has
  its own sky, `PlanetAtmosphere`). The user said "disable Sky3D for now" about the planet only.
- Its ground shader (`ground_lowpoly.gdshader`) has the old even wetness and snow; the planet's
  (`planet_ground.gdshader`) has puddles, ripples and uneven snow. `rain_fall` is already set by
  `WorldWind.set_surface` (called from `WorldWeather`).
- The flat world has a "World" page in the Esc menu (`ProceduralWorldMenu`); the planet has "Planet".
- The WorldClouds low-poly puffs are no longer used on the planet but still on the flat world.

## Plan

1. **Decide with the user** whether Sky3D goes (then the flat world needs a sky: the planet's air at a very
   large radius would do, with the clouds from `planet_cloud_march`), or stays for the flat world.
2. **Ground shader.** Port puddles, ripples and uneven snow to `ground_lowpoly.gdshader` through a shared
   include (`shaders/world/ground_weather.gdshaderinc`), so both ground shaders use one function.
3. **Clouds.** Try the raymarched layer on the flat world (a flat plane version of the march) or keep the
   puffs; the choice is the user's.
4. **Menu.** Same time and weather controls as the Planet page where they apply (the flat world has weather
   and a clock; see what `WorldAtmosphere` offers).
5. **Remove** dead code left by the planet work only after the flat world no longer needs it
   (`WorldClouds`, Sky3D plumbing), with the checks (`--world-check`, `species_check`) passing.

## Done when

- The flat world looks as wet and snowy as the planet; `world_lab -- --world-check` passes; no unused shader
  left; the doc says which sky each level uses.

## Risks and open questions

- Sky3D is an addon with its own look and day/night; dropping it is a visible change the user must like.
