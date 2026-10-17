# 063 - Things to do on the planet

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Give the sandbox a reason to explore without turning it into a survival game (this is an experiment, not a
horror or survival project): small tools and interactions that use what the planet has.

## Where we are

- The player walks, runs, swims, flies in free mode, and has an inventory (Tab) and a health bar; the
  planet has biomes, weather, water, animals (`PlanetFauna`), a map and saves.
- No interactions with plants, rocks or water; no vehicles, no building, no day/night needs (a torch).

## Plan (pick what is wanted; each is small)

1. **Light at night.** A torch or lantern (a spot or omni light, flicker) and a headlamp; eyes adapt to the
   dark by the ambient light (the sky model gives the night's brightness).
2. **Gather and look.** Pick up sticks, stones, flowers, fruit; "field notes" that record species seen and
   where (a journal built from the species table; the names from [060](060_map_and_ui.md)).
3. **Boat and glider.** A raft or boat on the sea (buoyancy on the planet's water), a glider that uses the
   planet's winds (lift from the wind model and slopes); the free mode stays for debugging.
4. **Camp.** Place a tent, a fire (a light, smoke that follows `WorldWind`); sleep to pass the night (the
   time controls already exist: use them as a "wait until morning").
5. **Cameras and instruments.** A thermometer and barometer from the planet's models, an altimeter, a
   compass; a camera item that uses the photo mode ([060](060_map_and_ui.md)).
6. **Weather you can feel:** wet clothes, breath fog in the cold, sweat; footprints in snow and mud
   (decals by the ground shader's wetness and snow).
7. **Goals** (optional): find all biomes, reach the highest point, see an aurora, an eclipse; just a list.

## Done when

- At least the torch, the journal and a boat or glider work and are tested in the lab with a check each.

## Risks and open questions

- **Open (user):** which of these does the user want? Do not build a survival loop; ask before adding
  anything with health or hunger.
- Interactions with plants need ids of instances inside multimeshes (to remove one plant); the merged far
  trees cannot be picked: only the near ones can.
