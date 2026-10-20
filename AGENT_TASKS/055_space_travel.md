# 055 - Space travel between planets

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `main` (it was `godot-4.7-upgrade` until 2026-10-20).

**Parked (user, 2026-10-17):** the focus is the planet and the star, not the player. Do not start this before
[054](054_universe_foundation.md) and [064](064_stars_and_life.md) are done. Many star systems are wanted, so the
space frame must cover distances between stars as well as between planets.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Leave a planet, fly through space and land on another one, with one planet in memory as a real
world at a time and the others seen as points and discs.

## Where we are

- The planet's frame turns the planet under the player every 80 m and recenters at 2 km (`PlanetFrame`),
  so the player stays near the world origin; planets up to ~1,000 km work in the single precision build,
  larger ones (Earth 6371 km, Jupiter) need the double precision editor build (built, in
  `E:\Godot\double`, notes in `docs/planet_generation.md`; export templates for it were not built).
- Free mode moves up to 600 m/s; the camera far plane is set to 1.2 x the planet's radius; from orbit the
  planet is seen with the air rim and the cloud sphere; the Orbit view works at 60,000 m.
- Tile detail follows the distance in space, so at altitude the planet is a few coarse tiles.

## Plan

1. **Scale.** Decide the unit of space travel: millions of km are impossible in one float world. Use a
   second "space frame": positions of planets and the ship as doubles in a `UniverseFrame`, the rendered
   world is always near the origin (the same trick as `PlanetFrame`, one level up). Test with a planet
   100 million m away at 1080p without jitter.
2. **Leave.** From a planet's orbit (above the air, ~25 km at the minimum air scale) hand over from the
   planet world to space: keep the planet as a sphere with a cover picture and the cloud shell, stop
   streaming tiles.
3. **Space view.** Stars (the sky shader without an air), the star as a bright disc with glare, planets as
   lit spheres with phases from the sun direction, moons, orbits drawn as thin lines on request (a map
   mode for the universe, like the planet map).
4. **Travel.** Controls: free flight with speed steps up to a high "cruise" speed, a slow-down near a
   planet, an autopilot to a chosen planet (a fast jump is acceptable for an experiment sandbox).
5. **Arrive.** Within a radius, build the target `PlanetWorld` (the loading screen exists), start
   streaming from altitude (the dive: see [045](045_landing_and_fast_descent.md)), free the old one.
6. **Time.** The universe clock keeps running while travelling; the planets move on their orbits.
7. **Double precision.** Decide if the default build is enough (travel by jumps, planets <= 1,000 km) or if
   the double build becomes the supported one; build the export templates if so.

## Done when

- From planet 1, fly out, see the planets and the star, fly to planet 2, land; a save made in space and
  one on a planet both reopen.
- No visible jitter at any distance; the frame cost in space is <= 2 ms.

## Risks and open questions

- **Open (user):** how does the player travel (a ship, free flight, a button)? Scale of the universe:
  realistic (empty) or compressed (planets a few thousand km apart)?
- Building a planet takes seconds (the loading screen); arriving at 600 m/s gives little time. Prefer
  building it while approaching, from a distance, before the player is near.
