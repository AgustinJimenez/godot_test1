# 071 - How close to an Unreal Engine 5 look can the planet get?

Status: **investigation done, nothing built (2026-10-18)**. Read `docs/planet_lessons.md` first (how to measure).
Goal: a "triple A" look where it counts, every part behind the graphics settings (`components/graphics_settings.gd`,
presets Low / Medium / High / Ultra / Custom) so a weak PC can switch it off. Measure the frame time of each step
(`--report-fps` in the lab) before and after, and keep the 60 fps budget of the High preset.

## What is on today (checked in the code, Godot 4.7.2, Forward+ with D3D12 on Windows)

- Sky, sun, haze and fog are the planet's own physics (`PlanetAtmosphere`, `planet_sky.gdshader`, the haze follows the
  local climate). Clouds are drawn in the sky shader (+ a cloud shell from orbit). Exponential fog only.
- Viewport: render scale 0.65..1.15, anti-aliasing off / FXAA / SMAA / TAA / MSAA, shadows (4 levels), SSAO (High+),
  SSIL and glow (Ultra only). Tone mapper Filmic by default. `hdr` setting exists.
- The ground: vertex colours from the crust plus procedural 3D detail noise (soil patches, grain, rock layers, bumpy steep
  faces, wetness, snow), PBR roughness changes with rain and snow. No real photo textures, no normal/roughness/AO maps.
- Not used anywhere in the project: **SSR, SDFGI, VoxelGI/LightmapGI, reflection probes, depth of field, auto exposure /
  camera exposure, volumetric fog on the planet (explicitly off), FSR upscaling, debanding, occlusion culling, colour
  grading (`adjustment_*`)**.

## What the engine offers (the real property list of Environment / CameraAttributes / Viewport, 4.7.2)

SSR (`ssr_*`), SSAO, SSIL, SDFGI (cascades up to `sdfgi_max_distance`), glow (7 levels, bloom, HDR threshold), fog +
volumetric fog (temporal reprojection, GI injection, anisotropy, 140 m default length), tone mapping (Linear, Reinhard,
Filmic, ACES, AgX with white and contrast), `adjustment_*` (brightness, contrast, saturation, 3D LUT colour correction),
CameraAttributesPractical (DOF near/far, auto exposure sensitivity) and Physical (aperture, shutter, ISO-like exposure),
Viewport (`scaling_3d_mode` bilinear / FSR1 / FSR2 with `fsr_sharpness`, `use_debanding`, `use_occlusion_culling`,
`mesh_lod_threshold`, VRS, `texture_mipmap_bias`, anisotropic filtering). **There is no Lumen or Nanite**: the global
light is the sky ambient + SDFGI (a few hundred metres round the camera, not a planet) or nothing.

## What makes the biggest difference, in order of value for the cost

### Tier 1: cheap, big gain (do first)
1. **Tone mapping and colour**: AgX or ACES with a tuned white and contrast, `adjustment_*` with a small saturation and
   contrast lift, and a 3D LUT for a grade. Auto exposure (CameraAttributesPractical) so a cave and a snow field both read.
   Cost ~0. This is most of what "a game look" is.
2. **Upscaling**: FSR2 (`scaling_3d_mode`) at 0.67..0.77 render scale instead of the plain scale: sharper than now at
   the same cost, and what lets Ultra run on a medium PC. Debanding on (sky gradients).
3. **Glow/bloom on from High** (a low threshold, HDR on) with the sun and snow glinting; **SSAO + SSIL from High**.
4. **Shadows**: a longer first cascade distance and PCSS-like soft shadows (the project already asks for
   `soft_shadow_filter_quality` 3); check the shadow distance (`directional_shadow_max_distance` 90..300 m today).
5. **Volumetric fog near the ground** (the idea of 2026-10-18): on within ~1.5 km of the ground, shallow range, density
   from `PlanetAtmosphere.haze_wanted`, `light_volumetric_fog_energy` on the sun; fade out with altitude; High+ only.

### Tier 2: the ground (where the player looks most)
6. **Real PBR ground materials** blended by the crust's rock/soil/snow weights and the slope: triplanar (so a sphere
   needs no UV), albedo + normal + roughness + AO per material (rock, soil, sand, grass, snow), height-blended, with
   distance fade to the current procedural noise. Texture arrays keep it one draw. Free CC0 sets (ambientCG, Poly Haven).
7. **Detail scatter**: pebbles, grass tufts and rocks as MultiMesh chunks near the player (by biome, wind, LOD, a
   density setting). Plants are off by default and "for later" (the user, 2026-10-18); this shares that work.
8. **Wet ground and puddles** (the shader has wetness and puddle roughness already): SSR on wet ground and on water.
9. **Contact detail**: decals for footprints, tracks, impact marks; **dust and pollen particles** in the air.

### Tier 3: water, sky, camera
10. **Water**: a planar/projected water with depth colour, foam on the shores and rivers (the map already has
    `river_waters`), refraction, SSR reflections, caustics, and an underwater look (fog already exists). The water
    layer is off by default today.
11. **Clouds that shade the land and make shafts** (the clouds are in the sky shader today, so the ground does not know
    them): sample the same cloud pattern in the sun's light (a cheap shadow-map-less cloud shadow on the ground shader),
    and tie the volumetric fog shafts to it.
12. **Sun and lens**: a sun glare and a subtle lens flare, a light DOF at the weapon / photo mode only, film grain and
    vignette as optional settings, heat haze over hot sand.
13. **Night**: stars and the Milky Way in the sky shader, a brighter moon with a halo, aurora near the poles (the
    climate knows the cold), city lights later.

### Tier 4: lighting model (expensive, test first)
14. **SDFGI** in the first few hundred metres for real bounced light under trees and in canyons: it needs a static-ish
    scene and rebuilds as the tiles change; test the cost with the tile builder running (probably Ultra only).
15. **Reflection probes** following the player (sky + ground) for metal and wet surfaces; cheaper than SSR for rough ones.
16. **Occlusion culling and mesh LOD** (`use_occlusion_culling`, `mesh_lod_threshold`) once there are buildings and plants.

## The settings design (so it stays cheap)

Keep the five presets and add the keys: `upscaler` (off / FSR2), `volumetric_fog`, `reflections` (SSR), `exposure` (auto),
`ground_detail` (0..3: procedural only / PBR textures / + scatter), `cloud_shadows`, `water_quality`, `gi` (off / SDFGI).
Low keeps what it is today. Medium adds FSR2 + debanding + the tone-map grade. High adds glow, SSAO/SSIL, fog shafts,
PBR ground. Ultra adds SSR, cloud shadows, scatter, SDFGI, 1.0 scale with FSR2 quality.

## Honest expectation

Without Lumen, Nanite and a tuned art pipeline the engine does not reach UE5's global illumination or its geometry
density. A planet generated in code can still reach a convincing "AAA" look in the three places a player judges first:
**the sky and light** (already custom and good), **the colour grade and exposure** (Tier 1, almost free), and **the
ground and vegetation up close** (Tier 2, the main work and the main cost). The first step is Tier 1, measured on the
three screenshots the user uses (a desert, a forest, a snow range at dawn).

## How to check a step

`planet_lab --earth --seed=8 --dir=x,y,z --shot-frame=1500 --shot=PATH` (see 069 for finding a place), once per preset, plus
`--report-fps`. Compare the same three places before and after, and write the ms per frame next to each setting.
