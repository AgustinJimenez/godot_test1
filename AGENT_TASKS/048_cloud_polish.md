# 048 - Cloud polish

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Clouds that are as good as the rest of the sky: more kinds, shadows, rain that comes out of the clouds you
see, and a standing-above-the-clouds view.

## Where we are

- One raymarched layer, 700 m thick, 450 m above the ground under the player, drawn by the sky shader from
  below and by a sphere round the planet from in and above it (`planet_cloud_march.gdshaderinc`, shared).
- Where there is cloud comes from the planet's cover picture (256 x 128, remade every 2.5-5 s on a thread
  from `PlanetWeather`); the noise shapes the billows; the wind that carries the cover carries the small
  shapes.
- Rain and weather state are chosen from the planet's weather at the player (`PlanetWorld._pick_the_weather`),
  not from the clouds overhead.
- Clouds cost 0.4-0.9 ms at 1080p; the march skips clear sky and uses fewer steps on short ways.

## Plan

1. **Cloud sea.** A flat, thick layer of low cloud (stratus/fog sea) at the valleys or at a fixed height that
   you can stand above on a mountain; its top lit and flat, its base dark. Driven by the same cover picture
   at a different threshold, or a second picture (low cloud).
2. **High cloud.** A thin cirrus layer at ~5-8 km (cheap: one noise lookup, no march), a veil in front of the
   sun, halos at the sun and moon.
3. **Cloud shadows on the ground.** Project the layer's density toward the sun into the ground shader (one
   texture lookup) or the sun's shadow map; moving shadows are what makes a landscape feel alive.
4. **Rain from clouds.** Rain and storms where the cloud overhead is thick and dark (sample the density
   above the player), so you see the rain's cloud and the clear sky beyond; lightning inside the cloud
   (flash the density), thunder delay by distance.
5. **Cumulonimbus.** Towering storm cells where `PlanetWeather` says STORM: a tall cell (3-8 km) with an
   anvil, seen from far; needs a taller layer only there.
6. **Orbit view.** Check the terminator, the night side (city-less dark), the sun's glint on the sea.
7. **Look from the moon / night:** clouds lit by the moon.

## Done when

- A mountain top above a cloud sea, a clear day with cirrus, and a storm cell in the distance are all
  screenshotted and written into the doc.
- Cloud shadows move over the ground with the wind.
- No cost over 1.5 ms total for the sky and cloud passes at 1080p (see [047](047_sky_and_sunsets.md)).

## Risks and open questions

- The cover picture is coarse (156 km per texel on an Earth-size planet): a second, finer window picture
  around the player may be needed.
- Taller layers cost more steps: keep them bounded per pixel.
