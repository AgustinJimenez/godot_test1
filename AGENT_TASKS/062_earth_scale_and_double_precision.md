# 062 - Earth scale and double precision

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Run Earth-size (6,371 km) and larger planets as a supported mode: fast to start, no jitter, and a clear
decision on the single and double precision builds.

## Where we are

- The default planet is 20 km (so a walk round it takes minutes); Earth size passed `--planet-check
  --radius=6371000` on the double precision editor build (built from the 4.7.2 tag, `precision=double`,
  d3d12=yes; no export templates). Above ~1,000 km the single precision build shows jitter.
- Jupiter size passed too. Hydrology is 96 cells per cube face; the tile LOD gives ~15 levels on Earth;
  the cloud cover picture is 256 x 128 (156 km per texel); the sky and the clouds use the air scale.
- Not measured on Earth size: start time, tile and plant counts, memory, the map and the climate build
  times, the cloud march (the noise scale is in metres, so it should be the same).

## Plan

1. **Measure** on the double build: start time, memory, tiles by level, draw calls, hitches, the climate
   and hydrology build times, the map and the chart; write them in the doc.
2. **Scale-up fixes:** the hydrology grid is too coarse at Earth size (rivers look blocky): a refined
   local pass near the player or a hierarchy of grids; a finer cover picture around the player for clouds
   ([048](048_cloud_polish.md)); relief and the size of features against the radius.
3. **Spawn and the world.** Spawning on a continent (the finder uses sea and slope today). Time scale for
   big planets: with a day of 1,440 s of play the equator turns under the sun at ~28 km/s, and the clouds
   are carried by `WIND_TURN` (0.035 turn a day) at ~1 km/s on an Earth-size planet (3 m/s on 20 km): the
   weather would race. Decide the day length and the wind scale per planet size and write the rule down.
4. **Double build.** Make it reproducible: a script that builds it (documented command), a check that runs
   the planet checks on it, and a decision: support it for Earth size, or cap the default build at 1,000 km
   with a clear message in the menu.
5. **Export templates.** If a game is ever exported, the double build needs `template_release
   precision=double` too; document the cost and do it only on a decision.
6. **Free-mode speed.** A planet this big needs speeds beyond 600 m/s to cross (a logarithmic slider or a
   "cruise" mode; see [055](055_space_travel.md)).

## Done when

- A table in `docs/planet_generation.md`: radius, start time, memory, fps, hitches for 20 km, 640 km,
  6,371 km, 70,000 km; the start of an Earth-size planet takes less than the agreed time.

## Risks and open questions

- Hours of compile time and ~GBs of disk per build; keep the build in `E:\Godot\double` and do not commit it.
