# 051 - Life and sound

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

A planet that moves and sounds alive: animals, insects and birds, and an ambience that follows the
weather, the biome, the time of day and where the player is (under the sky, in a forest, on the water).

## Where we are

- `PlanetFauna` exists (animals placed by `fauna.update(...)` near the player, by biome and light); birds
  and butterflies (`WorldLife`) exist in the flat world and are not on the planet ("Not done" in 043).
- No rain sound, wind ambience, thunder or water sound on the planet; the flat world has some sound by
  `WorldWeather`. Footsteps exist for the player in the project; per-surface footsteps on the planet are not
  checked.

Sound speed and loudness depend on the air's density: see [065](065_atmosphere_composition.md).

## Plan

1. **Ambience bus and layers.** Wind (by `WorldWind` strength, louder in the open, softer in a forest),
   rain (by `rain_fall`, different on leaves, ground, water), thunder (delay by distance from the flash),
   sea surf near the coast, river noise near a river (loudness by the distance to the nearest river from
   `PlanetHydrology`), night insects and day birds by biome and hour.
2. **Birds and butterflies** on the planet: reuse `WorldLife` with the planet's frame (they must live in
   the world's near space, as the rain and clouds do, under the player), by biome and time.
3. **Fauna.** More kinds by biome (fish in the sea, small land animals, large herds on plains), simple
   behaviour (wander, flee, graze), kept to a count near the player; a day/night cycle for them.
4. **Footsteps by surface** (grass, sand, snow, wet ground, rock, water) from the ground shader's inputs
   (snow cover, wetness) and the biome.
5. **Music** (optional, quiet): a state-driven bed by time and weather; no licences to copy.
6. **Audio budget.** Cap voices, distance fades, and test that nothing runs when the planet is paused.

## Done when

- A walk from a beach to a forest to a mountain changes what is heard; rain and a storm sound like rain
  and a storm; thunder follows the flash.
- Birds fly in the day over a forest and not over the sea at night; counts are bounded and measured.

## Risks and open questions

- Sound assets: we have none for the planet; generate them procedurally (noise filters) or pick free
  sources with a licence note, and record the licences in the task.
- Animals interact with collisions and the floating origin (they live in the planet frame and are turned
  with it).
