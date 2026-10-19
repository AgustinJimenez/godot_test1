# 071 - How close to an Unreal Engine 5 look can the planet get?

Status: **tier 1, the ground detail and the night sky are built (2026-10-18); the rest is open (see "Done")**. Read `docs/planet_lessons.md` first (how to measure).
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


## Done (2026-10-18) and what it costs

All of it is in `components/graphics_look.gd` (applied by `GraphicsSettings`, new keys in the presets and in the
settings menu). `PLANET_PRESET=low|medium|high|ultra` forces a preset for pictures and tests without writing the saved
settings. Frame time, uncapped, full Earth seed 8, on a strong GPU at 1920x1010 (`--fps`): **Low 0.68 ms, Medium 1.0 ms,
High 1.4 ms, Ultra 1.9 ms**. All far inside 16 ms here; measure on a weak GPU before trusting the High default.

- Tier 1.1/1.3: colour grade (None / Natural / Vivid / Filmic via `adjustment_*`), auto exposure (gentle, a limited range:
  a night is not lit up to day), a tuned bloom (soft light, HDR threshold 1.1), SSAO from High (as before).
- Tier 1.2: upscaler Off / FSR 1 / FSR 2 (only below 100 % render scale; FSR 2 replaces TAA/MSAA/FXAA), debanding.
- Tier 1.5: light shafts (volumetric fog) only within ~1.5 km of the ground, density from the local haze, off in space and
  underwater (`PlanetAtmosphere._shafts`).
- Reflections (SSR) Off / Low / High (Ultra). Not looked at on a wet place yet.
- Tier 2.6 (without downloaded textures): `ground_detail` Plain / Normal / Fine / Finest (global shader parameter): from
  Fine a bump a hand wide, darker crevices (AO), sand ripples, snow glints; Finest adds a second bump.
- Tier 3.13: the night sky has stars of different brightness and colour and a faint Milky Way (a band with dust lanes and
  fine grain, only computed where the sky is dark).

Presets: Low (nothing new, ground Normal), Medium (FSR 2, debanding, Natural grade, auto exposure), High (+ bloom, light
shafts, ground Fine), Ultra (+ SSR high, ground Finest). The render scales are unchanged (0.65 / 0.8 / 1.0 / 1.15).

## Not done yet (in the plan's order)

- 2.6 real PBR textures (needs CC0 files: downloading them was not asked; the procedural ground above is the stand-in).
- 2.7 detail scatter (shares the plants work: "for later"), 2.8 SSR looked at on wet ground, 2.9 decals and dust particles.
- 3.10 water (foam, refraction, underwater; the water layer is off by default), 3.11 cloud shadows and shafts under clouds,
  3.12 sun glare / lens flare / DOF in photo mode, aurora near the poles (the climate knows the cold).
- 4.14 SDFGI, 4.15 reflection probes, 4.16 occlusion culling and LOD: need a test of the cost with the tile builder running.
- Seen on the way, not part of this: the far ground at the horizon draws as a black, stair-stepped silhouette in the snow
  range (`--dir=-0.92717,0.00139,-0.37464`), and rectangular dark patches with straight edges close to the ground on the
  wet place (cloud/shadow or tile seams: look at `planet_ground.gdshader`'s `far` blend and the cascade distance).

## Update: clouds, lighting, surface textures

- **Cloud shadows** (`cloud_shadows`, High and Ultra): the ground shader marches nothing; it reads the
  same cloud layer (cover picture + the coarse noise octaves) along the ray to the star and darkens the
  ground under it. Scaled by `1 - overcast` (a full overcast already dims the sun). Cost: one cover
  fetch and 4 noise taps per ground pixel, no measurable frame change in the lab.
- **Bounced light** (`sdfgi`, Ultra only): the engine's SDFGI, 4 cascades. A subtle lift on flat
  ground; no clear frame cost seen in the lab (the tile builder's noise is larger). A reflection probe
  was not added.
- **Surface textures** (Fine and up, within ~70 m): tileable rock, soil and sand (normal + brightness,
  512 px) made by `scripts/make_ground_textures.py` (no downloads; run it again to remake them),
  blended triplanar by slope and sand colour, faded out by distance and under snow. Real photo-scanned
  PBR sets would look better; the script is the place to swap them in.

## The dark wall in the snow range (found and fixed)

It was not a skirt or a shader flaw: the height function had real cliffs (tens of metres within
centimetres). Cause: the erosion noise's warp used the gradient of a creased ridge, whose sign flips
where the noise crosses zero, so every finer octave's lookup point jumped there (now a smooth sign).
Two smaller steps were fixed with it: the plate-boundary pairs that dropped out under weight 0.002,
the fine octaves left out at coarse tiles (now replaced by their average) and the start of a
hotspot trail; the river valleys fade out before the edge of the cells they are known in.
`tests/manual/planet/height_jumps.gd` samples random land lines and reports any step over 8 m (22 of
596 lines before, 0 on seeds 8 and 3 after). The map cache version was raised (the heights changed).

## SDFGI is not on in any preset (it reset the GPU)

At a coast on seed 8 (`--dir=-0.71513,0.16242,0.67986 --view-alt=5`) the Ultra preset with SDFGI made
the D3D12 device get removed (`0x887a0005`, the game hangs). With SDFGI off the same view renders. So
the setting stays (manual, labelled experimental) but no preset enables it. Not understood why: the
planet is large and SDFGI wants a small scene; a custom `sdfgi_min_cell_size` per planet size may fix it.

## Water (looked at, one fix)

- Far sun glints were a speckle (the fine ripples alias below a pixel): the ripples now fade out by
  500 m, the long waves partly by 4 km and the gloss softens with distance, so the glint is one
  soft patch. Near water is unchanged.
- The water was otherwise sound: with the lab's camera really above the surface it refracts, absorbs,
  foams and reflects. What looked wrong in several pictures was the camera being UNDER the sea (the lab
  `--view-alt` is above the ground, so over a deep sea it is far below the surface, and the lab does
  not switch on the underwater fog the game uses with a player), and the yellow-green haze colour at the
  horizon that the sea (and the land) reflect.
- Lab note: `--sea --water` are needed to see any water; without them the sea is not drawn at all.

## Scatter, decals, occlusion culling (done, with the settings)

- **Pebbles** (`FloraMeshes.Kind.PEBBLES`, placed by `PlanetScatter._pebbles`): clusters of small stones
  every ~2.4 m near the player, thick on rocky, snowy, desert and beach ground, more on slopes, none in
  water; visible within 45 m, no shadow. Only with the plants on and the ground detail at Fine or
  more (High, Ultra).
- **Footprints** (`PlanetFootprints`, setting `decals`, High and Ultra): one Decal a step, alternating
  feet, on snow (a pale ground colour), sand and marsh; kept in planet space (the world turns under the
  player), at most 48 and gone after two minutes. The decal box is 2 m deep because the collider the
  ray hits and the drawn ground can differ by about half a metre; a shallower box was invisible.
- **Occlusion culling and mesh LOD** (`occlusion_culling`, High and Ultra): the viewport flag, mesh LOD
  threshold 1.0 instead of 2.0, and a coarse occluder under every tile of the six finest sizes
  (`PlanetTile._add_occluder`: 8 x 8 quads from the tile's grid, sunk by twice the skirt's depth so it
  cannot hide visible ground). In the snow-range lab view the draw calls fell from about 2,970
  (Medium) to about 1,100 (Ultra), which also has other changes; frames per second are lower on Ultra
  (about 255 against 395) for the other effects, not for this.
- Lab note: new `class_name` files need `godot --headless --import` once (the class cache), or the
  scripts that use them fail to compile; the editor does it on opening the project.

## The yellow-green horizon (found and fixed)

It was the sky shader's own sum, not the climate or the haze setting. The air along a view ray was
added up in 14 equal steps; a low ray is 300+ km long inside the air, so the first step already
started 30 km out and the dense air near the viewer was skipped: no blue was left and the horizon went
yellow (a Python copy of the shader gave (0.23, 0.21, 0.09) at 14 steps and (0.43, 0.54, 0.56), pale
cyan, at 200 steps). The steps now crowd toward the eye (cubed spacing, same 14 steps), which comes
within about 15-25% of the converged horizon and nowhere near yellow. The fog colour comes from the
same integral (`PlanetAir.sky_color`, 10 steps) and got the same spacing, so the far land is no longer
tinted yellow-green either. The sunset still warms the horizon toward the sun.

## Clouds stretched into rings round the player, from above (found and fixed)

Seen from above the layer the clouds were fine inside a circle round the camera and smeared into
concentric rings outside it. Cause (planet_cloud_march.gdshaderinc): the noise coordinate was scaled
by a `grain` that depended on the distance from the camera (billows "grow with the distance"), so the
noise field itself was bent into rings round the eye; and the fine layers switched on at a hard 9 km
(the circle). Now the noise never changes scale: the second layer of billows and the fine and ragged
layers fade out smoothly with the distance (`detail`, `far_fade`), so the same clouds are seen near
and far, only less fine.
