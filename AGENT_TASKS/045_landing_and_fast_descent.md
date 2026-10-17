# 045 - Landing and fast descent

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.

**Note (2026-10-17):** this is about the free-flying camera/player moving fast over the ground; keep it small
because the player is not the focus now, but a dive through the tile streaming is a planet problem too.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Flying (free mode) up and then coming back down fast must be safe: the ground, its collider and the
plants under the player are ready before they arrive, or the player is held; nothing falls through.
We tested climbing and long flights at low height, never a dive from altitude.

## Where we are

- The tile set follows the distance in space (height included), so while the player climbs the fine
  tiles and colliders go away, and when they come down they have to be built again.
- Colliders only exist on the finest tiles within ~316 m (`PlanetSurface._collides`); the queue sorts the
  missing tiles by distance and builds up to 12 per update (every 0.3 s), on worker threads.
- The start has a loading screen that holds the player until the ground within 2 km and the plants within
  60 m are ready (`PlanetWorld._wait_for_the_ground`); nothing like it exists for a dive.
- Free mode has a speed slider (2-600 m/s); at 600 m/s a 6 km dive is 10 s, a 60 km one 100 s.
- `--fly-check` flies at low height only. `--climb=N` lifts the player and freezes them.

## Plan

1. **Reproduce.** Add `--dive-check` to the lab: lift the player to N m, then move them straight down at a
   given speed to the ground; report if they pass through the ground (height above the ground at each
   step, and whether a collider existed under them), the time to a collider, and the HITCH numbers.
2. **Predict.** Choose tiles for where the player will be in ~1 s (position + velocity), not only where
   they are, so the finest tiles are queued early for a dive.
3. **Hold.** If the player is lower than X m above the ground and the collider under them is not built,
   hold their vertical speed (or clamp them above the ground) until it is; show nothing (a short hold at a
   few hundred metres is invisible), never the loading screen.
4. **Order.** Colliders first, then the ground meshes, then plants (as at the start), and nothing else
   competes with them for the worker threads during a dive.
5. **Water.** A dive into the sea: the swim code (`PlanetSwim`) must pick up from a fast fall; check the
   splash and the depth of the sea tiles.

## Done when

- `--dive-check` from 700 m, 2.5 km and 6 km at 100, 300 and 600 m/s never passes through the ground, and
  lands on a collider within a fixed time.
- The dive into the sea ends swimming, not under the sea floor.
- Documented in `docs/planet_generation.md` (a "Landing" paragraph) and `planet_lessons.md`.

## Risks and open questions

- A player who is not in free mode cannot dive (gravity), only fall off a mountain: terminal velocity
  and the same code path; check that case too.
- Predicting by velocity wastes work if the player changes direction; keep the prediction cheap.
