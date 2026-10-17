# 047 - Sky and sunsets

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Sunsets and sunrises that look like sunsets on every planet size, a dusk and dawn that are worth seeing,
and a sky that costs what it should.

## Where we are

- The sky is single scattering through a spherical air (`PlanetAir`, `planet_sky.gdshader`), the sun's colour
  is the air's transmittance, the ambient light is the sky rendered into the environment (realtime radiance
  128), fog colour from the air at the horizon (capped by the light the scene has).
- The air shrinks with the planet but not below a quarter of the Earth's (`PlanetAir.MIN_AIR_SCALE`) so the
  sky is bright at cloud height. The price: the sun's path through the air at sunset is short on a small
  planet, so sunsets are pale and hazy rather than red; twilight lasts longer.
- The clouds' sun colour at a cloud is an analytic air-mass formula with a `cloud_path` factor
  (`planet_cloud_march.gdshaderinc`), not the full air model.
- Stars are random points with `exp(-luma * 14)` fade; the moon has phases; the sun disc is a smoothstep.
- Not measured: the cost of the realtime sky radiance (re-rendered each frame) and of the sky shader
  (14 x 5 steps per pixel).

## Plan

1. **Decouple the colour of sunsets from the planet's size.** Add a second, thin "dust and haze" layer
   with a scale height of a few hundred metres and a strong forward scattering (Mie) whose optical depth is
   tuned per planet so the horizon sun passes through ~the Earth's amount of extinction. Keep the Rayleigh
   part for the blue sky. Test at radius 5, 20, 100, 6371 km: orange to red at the horizon on all.
2. **Sky and sun look.** A softer sun disc with limb darkening and glare, a visible twilight band
   (Earth's shadow) opposite the sun, belt of Venus; clouds picking up the colours (already, check).
3. **Stars and night.** Star colour and brightness per planet (from the star's type, see
   [054](054_universe_foundation.md)), a milky-way band, fewer stars under the moon's glare, twinkle that
   depends on elevation.
4. **Aurora and airglow** (optional): near the poles by the planet's axis, brighter in a storm of the star.
5. **Cost.** Measure the sky shader and the radiance update (`--fps` with the sky toggled); options: update
   the radiance at 10 Hz and interpolate, 64 instead of 128 radiance size, fewer steps in the sky shader
   with a cheaper light march, a lookup texture for the transmittance.
6. **Fog and ambient at sunset** from the same model, so the ground is not lit blue under an orange sky.

## Done when

- Screenshots at hour 6, 7, 17, 18, 19 on radius 5, 20 and 6371 km show a clearly warm sunset on all.
- The sky costs <= 0.5 ms at 1080p on the lab GPU, measured and written down.
- `docs/planet_generation.md` "Levels of the air" updated; lessons section 5 updated.

## Risks and open questions

- A second layer changes `PlanetAir` (CPU) and the shader (GPU): they must agree (they share formulas by
  hand today). Consider generating the CPU table from the GPU model or the reverse.
- Making the Earth look right must not break the small-planet blue day.
