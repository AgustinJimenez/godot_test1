# Graphics realism: findings against UE5

Investigation only (started 2026-11-10). Reference: UE5 source at `E:\repo\UnrealEngine` (`Engine/Shaders/Private`, `Engine/Source/Runtime/Renderer/Private`).
One area per entry: what we do, what UE5 does, the gap, a proposed change with effort (S = hours, M = a day or two, L = a week or more) and the
visual gain expected. Nothing here is implemented or measured unless the entry says so.

## State of play (2026-11-10, written after the overnight run)

Changed and seen working: height-dependent haze on the planet's own materials; voxel ground patchwork and snow squares (material copies); tonemap white 2.0
and softer leaf shine (ground level looks less washed); far sea sphere (turquoise shallows, surf, no black wedge); crest foam faded with distance
(no white speckles on the deep sea); Schlick fresnel for water; black cracks between voxel LODs (back faces drawn); cloud shape (baked cellular
noise), density (0.05), light samples and scattering octaves, IGN jitter (less grain). Lab test flags added: `--pose`, `--verbose-check` (AIR_STATE and
LIGHT_STATE), `--fixed-exposure`, `--cloud-shadows`, `--tonemapper=N`, `--free-dir-check`.
Changed, NOT demonstrated: cloud shadow on the voxel ground (needs the setting on and a better test), two-cascade shadows with a soft sun disc,
water far thresholds scaled to the planet, haze colour dimming, haze warmth toward the star.
Tried and reverted: crude sky multi-scatter, billowy value noise, ambient lift cut, AgX.
Open and biggest: D3D12 descriptor heap exhaustion with plants (58,000 errors per run; Vulkan has none: see the renderer section); the sky
multiple-scattering table; direction-dependent haze colour; the dusk look (haze density, a taste call); no ambient occlusion in the user's preset; a
cloud shadow map and long terrain shadows; Gerstner waves and caustics; the 1-FPS runs during the first frames after a shader change (comparisons
must wait for the ground). Everything is uncommitted; `project.godot` carries the four haze shader globals (plus the local `Double Precision` feature
line and a reordering that must NOT be committed).

Areas to cover: sky and aerial perspective (1), clouds, water, ground material, vegetation shading, shadows, ambient light / GI, exposure and
tonemapping, bloom and lens, wind, distant terrain (LOD, impostors), night, weather.

## 1. Sky and aerial perspective

Ours: `shaders/world/planet_sky.gdshader`, environment in `systems/planet/planet_atmosphere.gd`.
UE5: `SkyAtmosphere.usf`, `SkyAtmosphereCommon.ush` (Hillaire 2020, "A Scalable and Production Ready Sky and Atmosphere Rendering Technique").

What we do
- Single scattering marched per sky pixel: 14 steps along the view ray (crowded toward the eye), 5 steps toward the sun at each. Rayleigh, Mie
  (Cornette-Shanks, g 0.76) and ozone. Physically based and correct from the ground to orbit.
- Multiple scattering is a constant: `bounced = (sum_r * BETA_R + sum_m * BETA_M) * 0.5 / (4 PI)`, scaled by `multi_scatter` (default 0).
- Ozone follows the Rayleigh density (it is added to `BETA_R` in the optical depth), so it is thickest at the ground.
- The ground and everything on it get their distance haze from Godot's exponential fog (`fog_mode = EXPONENTIAL`, colour set from a CPU sample of
  the sky, `fog_sun_scatter = 0`). The fog does not know the view direction, the sun's side, or the altitude of the thing seen.

What UE5 does
- Four small LUTs instead of marching per pixel: transmittance (256x64), multiple scattering (32x32), sky view (192x104, latitude/longitude with
  the horizon given more texels) and a camera aerial perspective volume (32x32x16 froxels, in-scattered light and transmittance to each depth).
- Multiple scattering (`RenderMultiScatteredLuminanceLutCS`, line 1225): for each height and sun angle, integrate the second order isotropically
  over the sphere, also integrate `MultiScatAs1` (the share re-scattered), then sum the infinite series `L = L2 / (1 - MultiScatAs1)`. The ground
  bounce is in it (`Ground = true`, ground albedo). Sampled at every step of the main march.
- Ozone is a tent layer centred near 25 km (`AbsorptionDensity0/1` linear terms, `SkyAtmosphereCommon.ush` line 329), not an exponential.
- Mie has separate scattering and absorption (extinction about 1.11 x scattering); we fold that into the `* 1.1`.
- Aerial perspective is applied to every opaque and translucent pixel from the froxel volume (`GetAerialPerspectiveLuminanceTransmittance`): the
  same in-scattering integral as the sky, cut at the pixel's depth. Mountains go blue with distance on the side away from the sun and warm and
  bright toward it, and the haze on a far ridge matches the sky right behind it, so there is no seam at the horizon.
- The sun disc is the light's luminance times the transmittance LUT, so it reddens and dims at the horizon by itself.

The gap, most visible first
1. Aerial perspective. Our fog is one colour in every direction. Looking toward a low sun the far ground should glow with the Mie forward lobe;
   looking away it should be bluer and darker. A 3 km high peak seen from 30 km should have less haze than the plain below it; exponential fog
   by distance gives it the same. From high altitude and orbit the ground has no blue veil at all beyond what fog gives (fog is thinned to nothing
   by `air = exp(-altitude / 1500)`), while the sky rim is physically right: the planet looks pasted under its atmosphere.
2. Multiple scattering. With `multi_scatter` at 0 the sky is single scattering only: zenith too dark and too saturated, shadows under a clear sky
   too black-blue, twilight sky goes dark too fast. Our approximation when on is colourless and has no height or sun-angle dependence. On Earth the
   multiple scattered part is 20-40 % of the sky's light at midday and most of it at twilight.
3. Ozone profile. With ozone at the ground the horizon haze is tinted by it at all times; the real effect (the deep blue of the zenith at
   twilight, the "blue hour") comes from light passing sideways through the high layer. Ours will under-do the blue hour.
4. Cost and noise. 14 x 5 exponentials per sky pixel per frame, plus the radiance cubemap passes. UE5 pays 192x104 pixels a frame. This is
   performance, not looks, but it is what would pay for the froxel volume.
5. The sun disc uses `LIGHT0_COLOR` (already reddened on the CPU, fine) but the glare lobes (`pow(s, 48)` and so on) are not attenuated by the
   horizon haze the same way; minor.

Proposed changes
- A. Multiple scattering LUT (S-M). A 32x32 texture baked once per planet (it depends only on height and sun zenith angle, and on the air), on
  the CPU in `PlanetAir` or in a compute shader like `planet_sun_glow.glsl`. In `scatter()`, add `msLut(h, cosSunZenith) * (BETA_R * hr + BETA_M *
  hm)` per step, attenuated by the view transmittance. Replaces the `bounced` line. Gain: correct sky brightness and colour, lit shadows, a real
  twilight. This is the best ratio of gain to effort in this entry.
- B. Aerial perspective in the ground shaders (M). Simplest route that fits Godot: a small function in a `.gdshaderinc` used by
  `voxel_ground.gdshader`, `planet_ground.gdshader`, water and the impostors, called in `fog()` or at the end of `fragment()`/`light()`:
  analytic single scattering along the view ray for a constant-density-per-segment approximation (2-4 steps is enough for distances under
  100 km), using the same constants as the sky and the transmittance LUT from A for the sun. Then switch the Environment's depth fog off for the
  planet (keep it for mist and weather, which are real fog). Closer to UE5: bake the 32x32x16 froxel volume in a compute pass each frame and
  sample it as a global `sampler3D` uniform from every material; more work, but trees, grass and particles get it for free and it is cheaper per
  pixel. Gain: the largest single realism gain for far views, and the fix for the "pasted" planet from altitude.
- C. Ozone as a tent layer (S). Give ozone its own density, `max(0, 1 - abs(h - 25 km) / 15 km)` scaled by `air_scale`, with its own optical depth
  sums in both loops. Gain: blue hour, slightly more neutral horizon by day. Small but cheap.
- D. Sky view LUT (M, performance). Render the sky into a 192x108 latitude/longitude target once per frame (non-linear in elevation, see
  `SkyViewLutParamsToUv`), and have the sky shader sample it, marching per pixel only near the sun disc and from space. Frees the budget for B.

Open questions to check in the game before doing any of this: what `multi_scatter` is actually set to at run time (the uniform's default is 0);
how visible the fog/sky seam is at the horizon at noon and at sunset; the cost of the sky pass at 1080p (the radiance cubemap update mode matters).

## 2. Clouds

Ours: `shaders/world/planet_cloud_march.gdshaderinc` (shared by the sky and the shell `planet_clouds.gdshader`), cloud shadow in
`planet_ground.gdshader` and `flora_wind.gdshader`, set up in `systems/planet/planet_atmosphere.gd`.
UE5: `VolumetricCloud.usf`, `VolumetricCloudCommon.ush`, `ParticipatingMediaCommon.ush`, `VolumetricCloudRendering.cpp`,
`VolumetricRenderTarget.cpp`.

What we do
- One layer, 450 m to 1150 m above the ground, the cover from the planet's weather map. Density is five octaves of value noise (4.5 km to 100 m)
  plus a ragged-edge octave, with octaves faded out when smaller than a pixel. Flat base, rounded top.
- At most 16 view steps (step about 70 m or more), 2 light steps of 175 m toward the sun, full resolution, a white-noise jitter per direction,
  no reuse of earlier frames.
- Lighting: `direct = mix(exp(-d), exp(-0.25 d), 0.35)` (a two-lobe stand-in for multiple scattering), phase = blend of Henyey-Greenstein 0.55 and
  -0.25 plus a constant 0.45, sky light a fixed blue `vec3(0.28, 0.42, 0.7)` scaled by height in the layer and the sun's elevation.
- Distance: one haze factor by distance, no colour of its own beyond fading the cloud's alpha.
- The ground and the plants get a cloud shadow by re-evaluating the noise. `voxel_ground.gdshader`, `planet_water.gdshader` and
  `planet_impostor.gdshader` have no cloud shadow at all (grep finds no "cloud" in them): with the voxel ground on, the terrain is not shadowed
  by clouds while the trees standing on it are.

What UE5 does
- Clouds are traced at half or quarter resolution into a separate target (`VolumetricRenderTarget.cpp`), jittered with blue noise per frame
  (`BlueNoiseScalar(FullResPixelCoord, View.StateFrameIndexMod8)`, line 804), then reprojected and accumulated over frames and upsampled with the
  depth. That is what pays for 64-128+ view samples a pixel (`SampleCountMax` scaled by the distance marched) where we take 16.
- Empty space is skipped with a cheap "conservative density" (the material's coarse shape only); the expensive detail noise is evaluated only
  where that is above zero, and the march strides faster through empty stretches (`StepSizeOnZeroConservativeDensity`, lines 810-864).
- Multiple scattering is the octave approximation (Wrenninge 2015, as in Hillaire's Frostbite course): MSCOUNT lobes, each with scattering
  scaled by `MsScattFactor^n`, extinction by `MsExtinFactor^n`, and the phase pulled toward isotropic by `MsPhaseFactor^n`
  (`SetupParticipatingMediaPhaseContext`, line 413). Deep in a cloud the light still arrives, without the phase's direction: bright white cores
  and soft, dark bases, and the silver lining stays at the thin edges only.
- Two-lobe HG phase with material-set g (typically a strong forward lobe near 0.8 for the silver lining, and a weak back lobe).
- Shadows toward the sun: either a longer secondary march with a non-linear (x squared) sample spacing, or a cloud shadow map: a top-down
  texture of the extinction front depth, mean extinction and max optical depth (Beer shadow map), rendered once a frame. The same map shadows the
  ground, the water, translucents and the volumetric fog (light shafts under broken cloud), and a second map gives "sky AO": how much the cloud
  layer hides the sky light from the ground.
- Sky and ground light on the cloud: sky light is sampled from the real sky (SH of the sky atmosphere), and the bottom gets the ground's bounce
  (`GroundContribution`, a short downward integration; `SkyLightCloudBottomVisibility`, line 953). Bases are grey-blue over sea, warm over desert.
- Atmosphere on the cloud: the sun's light at each sample goes through the transmittance LUT (`AtmosphereTransmittanceToLight0`), so cloud tops
  at sunset are orange while the bases are already in the planet's shadow; and the aerial perspective volume is applied at the
  transmittance-weighted mean depth of the cloud (`tAPWeightedSum`, line 1222), so far clouds take the colour of the sky in front of them.
- Authoring: density comes from a material, usually a low-frequency Perlin-Worley shape eroded by a high-frequency Worley detail, with a height
  gradient per cloud type (the base "remap" trick). Worley noise is what gives the cauliflower billows; value noise gives soft blobs.

The gap, most visible first
1. Shape. Value noise with a fixed vertical profile reads as fog banks with bumps rather than cumulus. No cauliflower detail on the lit side, no
   variation in cloud height or type (everything is the same 700 m slab). This is the first thing a viewer notices.
2. Lighting depth. The two-exponential `direct` is a fair trick, but with 2 light samples over 350 m the self-shadowing is coarse: a cloud's
   sunlit side and shaded side differ less than they should, and there is no dark base. The fixed sky colour is wrong at sunset, at night under a
   moon, and under another star's sky.
3. Noise and banding. 16 steps with white-noise jitter and no temporal accumulation: visible grain when flying in or near the layer, and banding
   on long rays toward the horizon.
4. Shadows on the voxel ground are missing (see above); water and far impostors too.
5. No shadowing of the air by clouds: no crepuscular rays, and the volumetric fog under an overcast sky is as bright as under a clear one unless
   the weather code dims it by hand.
6. Far clouds fade to transparent instead of taking the haze colour, so the cloud deck near the horizon thins out where a real one piles up into
   a bright band.

Proposed changes
- A. Cloud shadow in `voxel_ground.gdshader`, water and impostors (S). Move the `cloud_shadow_*` functions of `planet_ground.gdshader` into a
  `.gdshaderinc` and call them from the other materials. This is a plain bug-level gap on the branch the game runs on. Gain: large when clouds
  are about (moving shadows on the land are one of the strongest outdoor cues).
- B. Worley-Perlin noise from baked 3D textures (M). Bake a 128 cubed shape texture (Perlin-Worley in R, three Worley octaves in GBA) and a
  32 cubed detail texture once (CPU or compute), sample them instead of `value_noise`. Erode the base shape with the detail at the edges, more at
  the base than at the top. One texture fetch replaces 8 hashes per octave, so it is also faster and leaves budget for more steps. Add a per
  region cloud type (height of the top from the weather map: stratus thin, cumulus tall) through the vertical profile. Gain: the largest for clouds.
- C. Cloud shadow map (M). A top-down (sun-aligned) texture round the camera, say 512 squared over 40 km, of optical depth through the layer,
  rendered when the sun or the wind has moved enough. Sampled by the ground, plants, water, the volumetric fog (as the light's projector or in a
  fog shader), and by the cloud march itself for the long-range part of the light path (replacing or extending the 2 light steps). Gain: correct
  shadows everywhere for one texture fetch, cheaper than re-evaluating the noise per ground pixel as now, and it enables light shafts.
- D. Half-resolution clouds with temporal accumulation (M-L). Render the cloud march to a half-size SubViewport or a compositor effect, jitter
  with an animated blue-noise (or interleaved gradient) pattern, blend with the reprojected previous frame, upsample depth-aware. Then raise the
  steps to 48-64. Gain: no grain, no banding, and it frees GPU time. Largest effort in this entry; Godot has no built-in for it.
- E. Multiple scattering octaves and powder (S). Replace `direct` with a 3-term sum: `sum_n a^n * exp(-b^n * depth) * phase(mu * c^n)` with
  a = 0.5, b = 0.5, c = 0.5, and use more forward g (0.8) on the first lobe. Raise the light samples to 4-6 with growing spacing (x squared).
  Gain: brighter cores, darker bases, a sharper silver lining.
- F. Sky and ground light from what is really there (S). Feed the cloud's ambient from the same CPU sky sample the fog colour uses (zenith and
  horizon colours), and add a ground-bounce term on the lower third from the average ground albedo under the camera. Gain: clouds that sit in the
  scene at sunset and at night.
- G. Haze on far clouds (S, after section 1 B). Blend toward the aerial-perspective colour at the cloud's mean depth instead of toward
  transparent.

Order suggested: A (bug), then B and E together (look), then C (shadows and shafts), then D when the frame budget asks for it.

## 3. Water (sea, lakes; rivers share most of it)

Ours: `shaders/world/planet_water.gdshader` (sea and lakes), `shaders/voxel/voxel_river.gdshader`, `shaders/world/river.gdshader`; underwater
handled by the fog in `systems/planet/planet_atmosphere.gd`.
UE5: `SingleLayerWaterShading.ush`, `SingleLayerWaterCommon.ush`, `SingleLayerWaterComposite.usf`; the Water plugin
(`Plugins/Experimental/Water`: `GerstnerWaveFunctions.ush`, `GerstnerWaterWaves.h`, `WaterInfo*.usf`, the quadtree water mesh).

What we do
- Waves: four sine waves with fixed directions along the axes and the diagonals (wavelengths about 20, 27, 11 and 7 m), moved in the vertex
  shader as height only; two layers of value-noise ripples for the fine normal. Wave amount scaled per place by a "roll" map (calm ponds).
- Body: colour is `mix(shallow_color, deep_color, sqrt(depth / 5 m))` put in ALBEDO, with the bed (screen texture, bent by the normal) added
  through EMISSION times `exp(-thickness * absorption)`. `thickness` is the view-space depth difference, so it grows when looking at a grazing
  angle. The water is a lit diffuse surface with a colour.
- Reflection: Godot's own environment reflection for the sky plus a 28-step screen-space march for the land; fresnel is `pow(1 - NdotV, 4)` with
  no base term in the bed mix. Roughness 0.025.
- Foam: at the shore from the depth difference, and on crests from the sine height plus a noise mask.
- No light of the sun scattered inside the water, no shadow of the land inside the water body, no caustics on the bed, no underwater view of the
  surface (fog only), no wave-height dependence on wind or weather.

What UE5 does
- Waves (the Water plugin): 16 Gerstner waves by default generated from a spectrum (`GerstnerWaterWaves.h`): wavelengths spread between a min
  and a max with a falloff power, directions spread round the wind's direction, steepness different for small and large waves, speed from the
  deep-water dispersion relation `sqrt(g * 2 PI / wavelength)` (`GerstnerWaveFunctions.ush` line 104). Gerstner waves move the vertices
  sideways too (`WPO.xy = -q * sin * dir * amplitude`), which sharpens the crests and flattens the troughs: the shape that reads as water.
  The waves are damped by the water depth near the shore through a "water info" texture (ground height and water height, top down).
- Single layer water is a volume, not a tinted surface (`SingleLayerWaterShading.ush` lines 160-240). From absorption and scattering
  coefficients per metre: `Transmittance = exp(-extinction * path)`; the scene behind is multiplied by it and by the mean transmittance from the
  water top down to that pixel (the light had to get down there too, line 206); and in-scattered light is added:
  `(ambient + sun * phase(PhaseG, refracted view ray) * DirectionalLightShadow) * scattering * (1 - Transmittance) / extinction`. So the colour
  of deep water is the sun's and the sky's light scattered back, it darkens in the shadow of a cliff or a cloud and at night, and it changes
  with the sun's direction. Nothing diffuse is lit at the surface.
- The path through the water is along the refracted ray (`WaterRefract` with the water's IOR, about 1.33) and refraction offsets are checked
  against a refraction mask so nothing in front of the water is dragged in.
- Fresnel is the full environment BRDF with F0 0.02 (2 % straight down, rising steeply past 60 degrees), applied to reflection and, as
  `1 - EnvBrdf`, to everything that comes out of the water. Reflections: screen-space plus planar or Lumen, falling back to the sky.
- The water is drawn after the opaque scene into its own pass with depth, so later fog, translucency and depth of field see the water surface.
- Underwater: a post-process material using the same absorption and scattering, plus the waterline. Caustics are left to materials or light
  functions (the engine has no built-in water caustics; the only "caustic" in the shaders is the eye's).

The gap, most visible first
1. The sea is lit as a coloured diffuse surface. In overcast or at dusk it stays turquoise where real water goes steel grey or black; in the
   shadow of a cliff it does not darken as a volume would; from above at noon it has no depth glow toward the sun. Because the body colour is a
   fixed pair of colours, the water does not take the planet's light (a red dwarf's sea would still be turquoise).
2. Wave shape and pattern. Four axis-aligned sines interfere into a regular diamond grid that is easy to see from a hill or from the air. No
   sharp crests. Wave heights do not follow the wind, and there is no swell longer than 27 m, so the open sea looks like a lake.
3. Depth by view distance, not by path in the water: at a grazing angle the shore band goes "deep" within a metre, and the shallow tint seen
   from above is lost when seen from the beach. Related: shore foam width depends on the view angle for the same reason.
4. Fresnel. `pow(1 - NdotV, 4)` without the 2 % base and with exponent 4 instead of 5 over-reflects at mid angles; the bed is dimmed by
   `1 - 0.7 * fresnel` at most, so at the horizon 30 % of the bed still shows through.
5. No caustics on the bed in shallow water, and no sun shafts underwater: the two cues that make clear shallow water look wet.
6. Far sea: beyond a few kilometres the normal is flattened, good against aliasing, but the roughness rises only to 0.125. The sun's glitter path
   on a real sea is wide because of the unresolved slopes; ours becomes a narrow mirror streak. No whitecaps by wind speed.
7. No cloud shadow on water (section 2 A).

Proposed changes
- A. Volume shading (M). Make the water unshaded-diffuse: ALBEDO near black, and build the colour in EMISSION as UE5 does:
  `bed * T_view * T_sun + (sky_ambient + sun_colour * shadow * phase) * albedo_w * (1 - T_view)`, with `T = exp(-extinction * path)`,
  `albedo_w = scattering / extinction` per channel (clear ocean: absorption about (0.45, 0.06, 0.02) per metre, scattering about 0.002-0.02;
  coastal water more scattering and greener), all times `1 - F`. The sun's colour and the ambient come from the same values the atmosphere code
  already has. The shadow term needs the directional shadow in the water shader: do the in-scatter in `light()` (ATTENUATION is the shadow
  there) instead of EMISSION. Gain: the largest for water; the sea follows the weather, the hour and the star.
- B. Path length along the refracted ray (S). `path = vertical_depth / max(cos(refracted angle), 0.2)` where vertical depth is the difference
  of world heights between the water surface and the bed pixel (reconstruct the bed's world position from the depth texture). Use it for the
  transmittance, the foam and the shallow fade. Gain: shores look right from every angle.
- C. Gerstner spectrum (M). 8-12 waves in the vertex shader with directions within about 60 degrees of the wind, wavelengths from 3 m to
  150 m by a power law, amplitude proportional to wavelength with a steepness cap, speed from the dispersion relation, horizontal displacement
  included, analytic normal from the sum. Wind speed and direction from the weather system set the amplitudes; the existing roll map keeps ponds
  calm, and depth damping can use the same map. The mesh needs enough vertices near the camera (a clip-map or a radial grid that follows the
  player). Gain: large, especially from height and at the shore.
- D. Fresnel (S). Schlick with F0 = 0.02 and exponent 5, used for the reflection weight and as `1 - F` on everything from below.
- E. Far-sea roughness from wave slope variance (S). Raise ROUGHNESS with distance according to the slope variance of the waves that were
  filtered out (the idea of LEAN/Toksvig mapping): about 0.15-0.25 for a breezy sea at the horizon. Gain: a broad glitter path instead of a
  streak.
- F. Caustics and underwater (M). Project a scrolling caustic pattern (two layers of a Voronoi-like texture, min-blended) onto the bed pixels
  inside the water shader where the depth is under about 8 m, scaled by the sun and its shadow. Underwater: a compositor effect with the same
  absorption and scattering instead of plain fog, and Snell's window when looking up. Gain: medium; mostly for lakes, rivers and beaches.
- G. Whitecaps (S, after C). Foam where the Gerstner Jacobian folds (crests pinching), scaled by wind speed, with a slow decay.

Order suggested: D and B (cheap, fix visible errors), then A, then C with E and G, then F.

# Progress (implementation, from 2026-11-10)

The user asked for the improvements to be made, not only listed. This section is the log: what the game really shows, what was changed, what
was seen after. Newest work at the end. Nothing is committed unless the user asks.

## How to take a picture that shows what the user sees

A plain Play Scene is NOT what the lab does when given flags. With no user args `planet_lab.gd` starts on foot, with plants, ground detail 3 and
the procedural surfaces; any flag (even `--shot=`) drops all that. So test runs use `LAB_PLAIN=1` in the environment and
`--plants --grounded --procedural`. The helper `scratchpad/shot.sh NAME [flags]` does that on the custom engine (voxel ground) and saves
`scratchpad/shots/NAME.png` and `.log`. New lab flags for this work:
- `--pose=alt,pitch,yaw`: at frame 200 the player is lifted `alt` metres in free flight and looks that way (pictures from the air).
- `--verbose-check` with `--shot`: prints `AIR_STATE` (altitude, fog density and colour, underwater) five frames before the picture.
- `--free-dir-check`, `--free-dir-alt=N`: the free flight direction check (it passes).

## Baseline, seen in the game on 2026-11-10 (11 h, default planet, start spot)

1. From the air everything drowns in blue. Fog density is 0.0017 per metre at the start spot (visibility about 1.5 km) and thins only with the
   camera's own altitude (`exp(-altitude / 1500)`), as one density for the whole ray. From 300 m the forest is blue-violet, from 1500 m the land
   is a flat blue sheet. This is section 1's gap 1 and it is the worst thing on screen.
2. Far trees are pale pink and lavender blobs while near trees are green: the far impostors do not have the colour of the trees they stand for.
3. On the ground the picture is washed out: pale, low contrast, acid yellow-green grass, pastel leaves, lifted shadows.
4. The clouds are grainy (white-noise jitter, section 2 gap 3).
5. Black dashed lines cross the ground from the air (seams between voxel LOD blocks).
6. No cloud shadow on the voxel ground (section 2 A).

## Done

- Cloud shadow on the voxel ground (section 2 A). `shaders/world/planet_cloud_shade.gdshaderinc` now holds the cloud shadow (moved out of
  `planet_ground.gdshader`, which includes it), and `voxel_ground.gdshader` uses it (`cloud_shade_keep`). It compiles and runs; NOT yet seen
  working in a picture, because the fog hid the ground in every picture from the air. Check again once the haze is fixed.

## Next, in this order

1. Haze by height (baseline 1): the ground, plant, impostor and water shaders write `FOG` from a shared `planet_haze.gdshaderinc`: the haze's
   density falls with the height above the planet (scale height set so the whole layer seen from above is about 0.3 of optical depth), integrated
   along the view ray, coloured toward and away from the sun. Needs three new shader globals in `project.godot` (the user must OK committing that
   hunk: the file is otherwise never committed).
2. Impostor colour (baseline 2).
3. Ground-level wash (baseline 3): find what lifts everything (ambient energy, volumetric fog, tonemapper, the sun glow effect).
4. Cloud grain, then the rest of sections 1-3.
5. LOD seams (baseline 5).

- Haze by height (baseline 1) DONE, seen working. `shaders/world/planet_haze.gdshaderinc` (`planet_haze(line, sun)`), written to `FOG` at
  the top of `fragment()` in voxel_ground, planet_ground, flora_wind, planet_impostor, planet_water, planet_shells, planet_chip, voxel_river,
  river. `planet_atmosphere.gd` publishes four new globals (`haze_air`, `haze_colour`, `haze_sun`, `haze_eye`), declared in `project.godot`
  `[shader_globals]` (that hunk must be committed for this to work elsewhere; the file's other local changes must not be). `HAZE_DEPTH` 0.18 is
  the optical depth of the whole layer seen straight down; the layer's height scale is `HAZE_DEPTH / density at the ground`, 60 to 1500 m.
  Pictures: from 300 m the forest is in its own colours with haze building to the horizon (before: blue-violet); from 1500 m the land, the
  trees and the coast are visible (before: a flat blue sheet). On the ground the picture is unchanged (the wash there is not the fog).
  Materials that do not write FOG (the player, anything with a StandardMaterial) still take the environment's fog; that only shows far away.
  Trap found: on the double-precision engine a world position in a shader is relative to the camera (`CAMERA_POSITION_WORLD` is about zero,
  `INV_VIEW_MATRIX * VERTEX` is the offset from the eye). So the haze takes the eye's place from a global and the line of sight from
  `mat3(INV_VIEW_MATRIX) * VERTEX`. The cloud shadow of the voxel ground uses `lab_pos - cloud_centre` (a world position made in `vertex()`
  from MODEL_MATRIX): CHECK it is right on the double engine, it may have the same trap.
- A run crashed once at start-up (segmentation fault during loading, no script error, the next run with the same files was fine): the unknown
  crash is still there, not caused by this work as far as seen. Also every run logs about 900 "not enough room in the RESOURCES descriptor heap"
  errors (D3D12), before and after this work.

## Seen once the haze was out of the way (new, from 1500 m)

7. The voxel ground is a patchwork of big squares: a dark green square round the walker (the 1.5 km colour window) against pale mint land (the
   whole-planet colour map), darker and lighter LOD blocks, cream squares. The two colour sources do not match, and the blocks are lit apart.
8. A black wedge on the land near the horizon (missing voxel blocks, the sea showing beyond it).
9. Far trees are sparse and pink (baseline 2) and stand out against the pale land.

Order now: 7 (the patchwork), 2 and 9 (impostor colour), 8, then 3 (the wash on the ground), then clouds.

- The patchwork (7) DONE, seen fixed from 1500 m. Cause: godot_voxel gives every terrain block its own copy of the ShaderMaterial, made when the
  block is made (`ShaderMaterialPool`), so a value set later on the lab's material never reached the blocks already there. After a rebase or a
  recentre the old blocks kept the old `world_to_planet`, read their height wrong and turned to snow; blocks older than the colour map never got it.
  Fix: `voxel_ground.gdshader` takes the planet's space from the global `planet_from_world` (the uniform is gone), and
  `lab_voxel_ground.gd` `_push_material()` hands the terrain a fresh copy of the material when the colour map or the colour window changes.
  Also a second, finer colour map for small planets (4096 x 2048, 30 m a pixel, 31 s on a worker after the ground is ready).
  Known: a "set_pixel on a null value" script error at quit when a window bake is still running (only at exit).

## Where the work stopped (2026-11-10, usage limit reached)

Not started: impostor colour (2, 9), the black wedge (8), cloud grain, LOD seams, everything in sections 1-3 not listed under Done.
In hand, the wash on the ground (3). Measured with `--verbose-check` (LIGHT_STATE line): tonemapper Filmic with white 1.0 and exposure 1.0,
ambient energy 1.0 with sky share 0.45, sun energy 0.97, and SSAO, SSIL, SDFGI and glow all OFF in the planet's environment although the
graphics settings default SSAO to on (the user's saved settings are in user://settings.cfg: read it; cloud shadows are also a setting, off by
default). Leads, none tried yet:
- Filmic with white 1.0 lifts the mid tones (the picture is pale and clips early): try white 4-6, or AgX.
- No ambient occlusion in dense foliage: check why `ssao_enabled` is false at run time, and try SSAO and SSIL on.
- Leaves: ROUGHNESS 0.5, SPECULAR 0.3, RIM 0.25 in `flora_wind.gdshader` mirror the bright sky on flat leaves; try roughness 0.65-0.75 and less rim.
- From 120 m looking down, real trees are pale teal under a whitish veil that the ground beside them does not have: foliage shading, not the haze.

- Ground wash (3), first step DONE and seen: `tonemap_white` 1.0 -> 4.0 in `planet_atmosphere.gd` (Filmic with a white of 1 clips highlights
  early). Same spot, 11 h, plain Play settings (shot `white4_ground` against `haze_ground`): the acid yellow grass is now green with yellow tips,
  the sunlit patches keep their detail, the foliage greens are deeper and the pale veil over the canopy is thinner. Still open there: no ambient
  occlusion (the user's saved settings have SSAO off), leaves still shiny (ROUGHNESS 0.5, RIM 0.25 in `flora_wind.gdshader`).
  Not checked: that the sky and sunset at 4.0 are not too dark, and the other tone mappers (`tonemap_white` only matters to Filmic and Reinhard).
- Leaf shine (3, second step) DONE, small: `flora_wind.gdshader` leaf ROUGHNESS 0.5 -> 0.64, RIM 0.25 -> 0.15. Same spot (shot `leaves_ground`): fewer
  white sky mirrors on flat leaves, the canopy reads greener and calmer. The picture is still hazy and low in contrast in the shade: ambient
  occlusion is the next thing to try (SSAO is off in the user's saved settings, preset 1; the planet lab could turn on a cheap one by default).

- Far trees (2, 9): NOT a bug as far as seen. From 40 m looking at the horizon (shot `far_trees`) the impostor trees are the same deep green as the near
  ones, with the haze taking them toward blue. The pink and lavender trees seen from 300-1500 m are a species colour (blossom, autumn leaves) that
  the card pictures show faithfully; the colour of one species could still be judged too bright from above (the "from above" picture is lit by the
  baking light at a fixed angle). Left alone.
- Ambient occlusion (3): not changed. The user's saved settings (preset 1) have SSAO off on purpose; turning it on by default would override that.
  If wanted, it belongs in the graphics preset, not in the lab.
- Cloud grain (4): not done. It needs the half-resolution temporal pass of section 2 D (a shader-only blur would smear the cloud edges).
Next candidates, in order of gain: section 3 A/B/D (water: fresnel F0 0.02 and exponent 5, depth along the refracted ray), section 1 A (sky
multiple scattering table), section 2 B (baked Worley noise for the cloud shape), the black wedge of missing blocks (8).
- Water fresnel (3 D) CHANGED, NOT SEEN: `planet_water.gdshader` fresnel is now Schlick with F0 0.02 and exponent 5 (was `pow(1 - NdotV, 4)`).
  The test shot (`sea_after`, pose 60 m, yaw -90) looked at forest, no sea in view, so the effect is unchecked. Need a pose toward the coast
  (the sea is to the left of the start spot at yaw ~ +90 from 1500 m); compare a grazing view of the sea before and after.
  Side note from that shot: a run took 1 FPS at frame 1100 (the 4096 colour map bake competes with the render), and black holes in the far trees
  (missing impostor/block pieces) are visible near the horizon.
- Water fresnel, checked (shot `sea_b`, 1500 m, yaw +35, pitch -15): the sea at both edges of the picture is a deep blue with a soft pale patch of
  sky reflection toward the horizon at the right; no white-out or mirror-flat look, so the 2 % base is safe. No "before" picture was taken at
  the same pose (the change was made first), so the size of the difference is not measured. A close grazing view of the sea from the shore is
  still the picture to take next.

- Sky multiple scattering (1 A): tried the existing crude fill (`multi_scatter` 0 -> 1) at 17.6 h from 300 m (shots `ms0_sky`, `ms1_sky`):
  the sky gets brighter and greyer, the blue and the sunset warmth wash out and the sun's glare is smothered. WORSE, so it stays 0 (default
  unchanged). The real fix is the height-and-sun-angle table of section 1 A (32 x 32, the second order over the sphere summed as a series), not
  a flat constant. Not done: needs a bake (CPU `PlanetAir` or a compute shader) and a texture in the sky shader.
- New finding from those shots: at 17.6 h the far ground is a flat milky white-grey from 300 m (and trees go grey), much whiter than the sky
  behind it. The haze colour is the air's colour AWAY from the sun mixed with the toward-sun colour, capped by `cap` (0.25-0.8) in
  `planet_atmosphere.gd`; with the low sun the capped value is near white. Next try: lower the cap at low sun, and use the sky's own colour at
  the horizon direction of the view instead of one colour for all directions (section 1 B in full).

- Dusk haze (follow-up to the 17.6 h finding): two tries, neither fixed it. (1) The haze colour published to the planet materials is now 0.72-0.8 of
  the fog colour (`planet_atmosphere.gd`, `haze_lit`); noon from 300 m (shot `noon_after`) looks right, with the land in its colours and a mild blue
  at the horizon. (2) Cutting the dusk ambient lift (`low_sun_fill` 1.6 -> 0.7) changed almost nothing, so it was put back. The milky ground at the
  horizon at 17.6 h is the haze itself: at a grazing 10 km the optical depth is about 14 (density 0.0014 per metre), so the far ground is entirely
  haze colour and the haze colour is bright and grey. The honest fix is the direction-dependent haze colour (the sky's colour at the same
  elevation, warm toward the sun) of section 1 B, and a lower density near the horizon at dusk; not done.

- Dusk haze, second pass (corrects the previous entry): the milky white sheet in the dusk shots is mostly the SEA seen at a grazing angle (the
  coast with forest is at the right edge of `dusk_dim_away`; the sheet has the sea's cyan foam marks). It reflects the bright dusk sky, which is
  physically right for the angle, but it is a featureless pale slab: no wave pattern shows, no sun glitter, no depth colour. That is section 3
  (water: waves, far roughness from slope variance, wide glitter path), not the haze.
  Changes kept: haze colour now 0.58-0.66 of the fog colour (was 0.72-0.8); `haze_sun` is now the real toward-minus-away sky colour difference
  carried on `pow(cos, 3)` (was the sun's light colour on `pow(cos, 8)`), so the haze warms toward the star. Noon from 300 m (`noon_dim`) looks
  right and a little deeper blue at the horizon than before; the toward-the-sun dusk shot (`dusk_dir`) has a warm bright horizon on the left.

- Far sea roughness (3 E): `planet_water.gdshader` far roughness `0.1 * smoothstep(300, 5000)` -> `0.24 * smoothstep(150, 6000)`. Shot `dusk_sea_rough`
  (same pose as `dusk_dim_away`): the sea slab is still a uniform pale sheet, so roughness alone does NOT fix it; the slab's brightness comes
  from the sky reflection weight (fresnel near 1 at a grazing 10 km) with almost no wave signal left in the normal at that distance (`long_keep`
  falls to 0.3 and the fine ripples are gone), so there is nothing for the glitter to modulate. Fix to try next: keep the long waves at full
  strength far out in the normal but filter them by slope variance (roughness) instead, and put a base body colour under the reflection
  (water at 10 km is never brighter than the sky above it: scale the reflection by about 0.7 and let the deep colour show through).

- Far sea waves and reflection (3 E, second try): `planet_water.gdshader` `long_keep` now falls only to 0.75 far out (was 0.3) and SPECULAR drops
  to 0.7 of itself between 1.5 and 8 km. Shot `dusk_sea_waves`: NO visible change in the pale slab, so what is drawn there is probably not this
  shader's output. The sea is the voxel sea (`lab_voxel_ground.gd` `_make_water(1, 4096, PlanetTile.water_material())`, a LOD terrain with
  `planet_water.gdshader`), whose far blocks may be the coarse LODs with flat or missing normals, or the environment's own sky reflection
  (a screen-space or reflection-probe term) may be what saturates it. Next: debug the slab with the shader's ALBEDO/EMISSION forced to one colour
  at `away > 3000` to see which part of the shader the pixels come from. The two edits are harmless and stay, but are unverified.

- Far "sea slab" debugged (follows the two entries above). Forcing the water shader's output to magenta beyond 3 km showed NO magenta, and with
  `--voxel-no-sea` (shot `slab_nosea`) the slab turns into pale rolling GROUND with a grey flat sea beyond it: the slab is the voxel GROUND, a
  large pale land (sand / dry-colour map) near the coast, seen through a haze, not the water. The coast on the right edge is the same land with
  forest. So: (a) the planet's colour map makes that region pale grey-white (check `colours_of` for a desert, salt flat or bare-rock rule giving
  near-white at this latitude, and the 1.25 gain in `voxel_ground.gdshader` `use_map`, which clips pale colours: its comment says sun-facing
  slopes already clip to white), and (b) with the haze at dusk it goes flatter still. The water edits made earlier (roughness, long waves, speculars)
  are therefore unrelated to this picture and unverified. Next: look at the same place with `--voxel-debug=4` (unlit albedo) to read its true
  colour, then fix the map's colour or the gain.

- Far slab, settled (corrects the previous entry): the earlier magenta test used `away > 3000`, but on this 20 km planet the horizon from 300 m is
  only 3.5 km away, so nearly nothing passed the test. Redone with `away > 600` (shot `sea_magenta2`): the slab turns lilac, so it IS the water,
  drawn through the haze (at 1-3 km the haze's optical depth is already 1.5-4: the sea is 80-98 % haze colour) plus the sky reflection. The
  "ground with `--voxel-no-sea`" picture was the seabed. The water shader edits are therefore live but their far thresholds (1.5-8 km) lie beyond
  the horizon of this planet: scale distances for a 20 km planet (1/6 of those numbers). Lesson for the rest of this work: distances in shaders
  must be judged against `planet radius`, the horizon is at sqrt(2 R h).
  What is left of the dusk look is the haze density itself (0.0014 per metre at the ground, visibility about 2 km): fine for mist, heavy for
  a clear evening. `PLANET_FOG` 0.00045 x `haze_wanted` (0.55 to 2.05) is the knob.

- Water distances rescaled to this planet (`planet_water.gdshader`: far roughness 25-1000 m, long waves 70-1000 m, reflection 250-1300 m). Dusk
  slab (`sea_scaled`) still unchanged: it is 80-98 % haze by 1-3 km, so no water detail can show through. Noon from 120 m (`sea_scaled_noon`,
  looking inland) is a clear, deep forest scene with the horizon trees properly hazed: fine. The haze (visibility about 2 km) is the thing that
  decides what the dusk sea looks like; changing `PLANET_FOG`/`haze_wanted` is a taste call for the user (a clearer evening would let the sea,
  the coast and the sun's glitter read), so it is NOT changed here.

## Voxel sea against the tiled sea (found 2026-11-10, biggest water gap on this branch)

Same pose (1500 m, pitch -40, 11 h), shots `wedge_vox` (voxel ground, the game on the custom engine) and `wedge_tiles` (`--no-voxel`, the same
planet with the tiled ground and its own water): the TILED version draws the coast properly, turquoise shallows to deep blue, white surf along the
beach, distant mountains in blue haze, a clean horizon. The VOXEL version draws the sea as a dark blue-grey mirror with white speckles, no shallow
turquoise, no surf, no depth gradient, and a black wedge of missing sea blocks (the dashed black grid near the horizon on the right). The same
`planet_water.gdshader` is used, so the difference is in how the voxel sea feeds it: (1) the water reads the DEPTH of the scene behind it for the
shallow-to-deep colour and the foam; the voxel sea is its own LOD terrain, and with `depth_draw_opaque` on its blocks and several LODs overlapping,
the depth texture may contain the water's own surface (thickness 0), or the screen texture under it may be the sea itself; (2) `COLOR.r` (the
`roll` waves factor) is white by default on the voxel mesh and `roll_map` is not set; (3) the far blocks are the coarse LODs with big triangles, so
`dFdx(VERTEX)` flat normals blend badly. First things to try: render the voxel sea as a transparent pass that does not write depth
(`depth_draw_never`) and compare; print the thickness as a colour; check that the black wedge is a gap between the sea terrain's view distance
(4096) and the ground's. This is worth more than anything else in the water section.
- First try on the voxel sea: `depth_draw_never` instead of `depth_draw_opaque` (shot `wedge_nodepth`): NO change at all (same grey-blue mirror, same
  black wedge), so the water's own depth writes are not the cause; reverted. Next: print `thickness`, `t` and `foam` as colours on the voxel sea
  (EMISSION debug) to see whether the depth read gives 0 or garbage; check `lab_voxel_ground.gd` `_make_water` (`VoxelLodTerrain` with a
  `VoxelMesherTransvoxel`, whose mesh may carry NO vertex colour and a different `NORMAL` convention) and whether `texture(depth_texture, ...)` sees
  the ground (it is another terrain drawn in the same pass: the sea is drawn in the transparent pass after the opaque ground, so it should).
- Voxel sea debugged with the shader's thickness, scene depth and distance written out as colours (shot `sea_dbg`): at the coast the water's
  thickness reads 40 m or more almost at once (the whole sea region on the right saturates to white), with shallow cyan only in thin streaks
  beside the black wedge. So the water thinks the sea is deep right off the beach: the seabed under the voxel sea is NOT in the depth texture
  (the voxel ground under the water is not drawn, or is the missing black wedge), and the depth read falls through to something far behind. The sea
  at the left horizon is not drawn by this shader at all (unchanged blue). Fix direction: give the water the seabed depth from the planet itself:
  a coarse height map of the planet around the camera (the same `heights_of` bake the colour window already does, `lab_voxel_ground.gd`
  `_bake_window`) as a texture the water reads (`roll_area`/`roll_map` already exist for this, set only by the tiled sea), so thickness =
  sea level minus ground height, not a depth-buffer difference. That also removes the "bottomless" look from any angle. Effort M.
- Voxel sea, second debug (shot `sea_dbg2`, 500 m, pitch -30, facing inland-to-sea): the sea beyond the coast, filling the upper third, shows the
  ORDINARY colours with the thickness debug on (it did not turn to the debug colours), so it is not drawn by `planet_water.gdshader` there. It is
  the voxel GROUND's own seabed, coloured by the colour map's ocean blue and lit like land (a smooth pale blue slab, no waves, no glints). The
  water shell (the debug colours of `sea_dbg`) exists only in patches: near the coast and at the right edge. So the "sea" the player sees from a hill
  is mostly seabed painted blue, which is why it has no depth gradient, no waves and no surf, and why the missing water blocks show as black
  (nothing under them but the culled inside of the seabed). Real fix is a continuous water surface out to the horizon: the sea terrain's view
  distance and LOD count (`_make_water(1, 4096, ...)`) need to cover the ground's, or a cheap analytic sea sphere (radius = planet radius +
  sea level) drawn with `planet_water.gdshader` under the voxel terrain as the far sea. The sphere is the simplest: one `SphereMesh` node, no
  voxels, and the shader's depth read then works against the seabed that IS drawn.

- FAR SEA SPHERE DONE and seen (the fix of the two entries above). `lab_voxel_ground.gd` `_make_far_sea()`: a `SphereMesh` (384 x 192) at sea level
  minus half a metre, drawn with `PlanetTile.water_material()`, placed with the terrain like the voxel water (added to `_water`). From 1500 m
  (shot `farsea_1500` against `wedge_vox`): the coast now has turquoise shallows fading to deep blue, white surf along the beach, the sea reaches the
  horizon as water, and the black wedge of missing blocks is gone (the sphere covers the gap). From 500 m the far sea is a hazy pale blue
  as before (the haze). Known: white speckles (sun glints on the fine ripples) cover the deep sea at 1500 m: that is the high-frequency ripple
  normal aliasing, `fine_keep` fades it from 40 to 500 m, which on this small planet should be about 1/6 of that (see the rescaling note).
  Only the voxel lab path creates the sphere; the tiled ground still draws its own water. A sphere at the player's feet may show a seam against the
  voxel water at the shore: not checked from the ground.
- Sea speckles: `fine_keep` now fades the fine ripples over 10-160 m (was 40-500). Shot `farsea_calm`: the white speckles on the deep sea at 1500 m are
  UNCHANGED, so they are not the ripples. Candidates left: the crest foam (`crest * streaks` from `waves()` and noise, drawn at any distance, with
  `streaks` a noise at 2.6 per metre that aliases to dots when far), or sun glints on the long-wave normal. Next: multiply the crest foam by
  `fine_keep` (it is a fine pattern too) and look again.
- Sea speckles FIXED: the crest foam was the cause. `planet_water.gdshader`: `foam = max(foam, crest * streaks * 0.8 * realism * fine_keep)`. Shot
  `farsea_nofoam` against `farsea_calm` (1500 m, 11 h): the white dots are gone; the deep sea is a clean blue with soft darker swell, the shallows
  stay turquoise and the surf line stays at the beach. Water changes now in place and seen working: far sea sphere, fresnel F0 0.02, crest foam
  faded with distance, ripples faded at 10-160 m. Still open in water: the sea is hazy from low altitude (the haze density, a taste call), the
  depth fade `depth_fade` 5 m / absorption were tuned for Earth-scale, no wave sharpening (Gerstner), no caustics.

- Shore views at 250 m, 11 h (shots `shore_a`, `shore_b`, `shore_a2`): looking along the coast (`shore_b`) is good: beach, turquoise shallows, surf lines,
  deep blue beyond, the far sea sphere joins the voxel water with no visible seam. Looking the other way (`shore_a`, yaw -70) the whole picture is
  washed to white: sky, haze and trees. Cause is the view toward the star: the sky's glare terms and the cloud forward scatter bloom it, and the
  haze takes the same bright colour (my `haze_sun` lobe added to it). Reduced the haze's toward-sun lobe (0.45 -> 0.25 of the colour difference,
  `pow(cos, 3)` -> `pow(cos, 5)`): `shore_a2` is only slightly better, so most of the white is the sky and the tone curve, not the haze.
  Not checked: what this direction looked like before any of this session's work (no picture was taken at that yaw); the same pose on the
  committed code would say whether the white-out is new. Do that comparison (git stash, shot, unstash) before trusting any of the haze or tonemap changes
  for views toward the sun.

- Tonemap white point comparison is CONFOUNDED, do not trust it yet. Toward-the-sun view at 250 m (`shore_a_white1` at white 1.0: deep blue sky, black
  holes in the ground because that run was at 1 FPS and the ground had not loaded; `shore_a` at 4.0 and `shore_a_white2` at 2.0: sky blown
  to white). The three runs differ in frame number (1100, 1100 at 1 FPS, 1500) and the user's preset has AUTO EXPOSURE on, whose adaptation depends on the
  frames elapsed, so brightness changes with the run, not only with the setting. Rule for any later comparison: same `FRAME`, same pose, wait for
  the frame rate to settle, and read the exposure (`LIGHT_STATE`) in the log; or turn auto exposure off in the test (`GraphicsSettings`).
  Current setting: `tonemap_white` 2.0 (between the old 1.0 and the 4.0 tried first). The ground view at 2.0 (`ground_white2`) keeps the gains
  seen at 4.0 (green grass with yellow tips, less pale veil). Whether the sky toward the sun is better or worse at 2.0 than at 1.0 is NOT known.

- Controlled tonemap comparison DONE (new lab flag `--fixed-exposure`: sets auto exposure off in memory only, the user's saved settings untouched;
  shots `tm_1.0`, `tm_4.0`, same pose, frame, hour). With the exposure fixed the sky is the same deep blue at white 1.0 and 4.0, so the white-outs of
  the earlier entries were AUTO EXPOSURE (the user's preset has it on) still adapting at frame 1100, not the tonemap, not the haze. At white 4.0 the
  picture is a little greyer and lower in contrast than at 1.0; so 2.0 stays as the compromise (the ground-level gain was seen at 2.0 and 4.0).
  Open question for a real Play: auto exposure with `auto_exposure_speed` 0.6 starts from a bright-adapted state and takes some seconds to
  settle: does a few seconds of white-out at start-up or when turning toward the sun happen in play? Worth a 20-second video, not a frame-1100 shot.
  Also seen again: runs that fall to 1 FPS (the 4096 colour-map bake plus the first frames) have the ground not loaded (black holes): another
  reason a screenshot at a fixed frame is a poor comparison; wait for `ground_ready` and the colour map instead.

- Cloud shadow on the voxel ground, checked (new lab flag `--cloud-shadows`, in memory only; the user's settings have `cloud_shadows` false, so on a plain
  Play it is OFF). Shots `cs_on/cs_off` (700 m, clear patch: identical, no cloud overhead there) and `cs2_on/cs2_off` (1200 m, `--weather=cloudy`): the
  "on" picture is slightly darker over the left half of the land and has darker bands on the far sea; no sharp shadow shapes are visible, because from
  1200 m the layer's shadow is soft and the picture has little cloud over it. So the shader runs and darkens, but this is NOT a convincing
  demonstration; a better one is a walker on the ground under a broken cloud at a low sun (shadow edges long and clear), or the cloud-shadow map
  of section 2 C. Setting stays off by default in the user's preset; to see it: Graphics settings, "Cloud shadows".

- Cloud grain (4), first step DONE: the ray jitter is now interleaved gradient noise of the screen pixel (`cloud_jitter(FRAGCOORD.xy)` in
  `planet_cloud_march.gdshaderinc`, passed to `cloud_march` by `planet_sky.gdshader` and `planet_clouds.gdshader`) instead of a white hash of the
  direction. Shot `grain_after` (120 m, looking up, fixed exposure): the cloud edges are a fine regular dither instead of the coarse powdery
  speckle of the earlier shots (`far_trees`, `dusk_dir`); the clouds read cleaner and smoother. The pattern is still visible at 1:1 as a fine
  hatch on thin edges; the real cure is still the half-resolution temporal accumulation of section 2 D (with IGN animated by the frame index, which
  needs a frame counter global). Shader signature changed: any other caller of `cloud_march` must pass the jitter (none exist).

- Cloud lighting (2 E) CHANGED, barely visible: `planet_cloud_march.gdshaderinc` now takes four light samples of growing length (the shadow
  march of UE5) and sums three scattering octaves (each half as strong, attenuated half as fast, phase pulled to isotropic) in place of the
  two-exponential mix. Shot `lit_after` against `grain_after` (same pose, hour, fixed exposure): the clouds are very slightly whiter and the
  grey bases about the same; no dramatic change. Reason: with `sigma` 0.022 per metre and a layer 700 m thick the clouds are optically thin
  (about 15 of optical depth at the very thickest, mostly under 5), so the octave terms differ little from the first. To get dark bases and bright
  cores the density has to rise (sigma x 2-3, with the edge gain lowered so the clouds do not grow fatter) or the layer be thicker. Not tried.

- Cloud density (2 E, follow-up) DONE and seen: `sigma` 0.022 -> 0.05 in `planet_cloud_march.gdshaderinc`. Noon (`dense_after`, same pose as
  `lit_after`): the clouds now have bright tops and grey-blue shaded undersides, a clear volume instead of flat white shapes; the sky still shows
  between them. Dusk (`dense_dusk`, 120 m, looking toward the low sun): soft grey-white clouds lit from one side, the sun's glow behind them; no
  blown-out sheet. Cost: not measured (same step counts; the shot ran at 26 FPS on the dusk frame, which also had the heavy ground load).
  Cloud edges still show the fine IGN hatch. Open: cloud shape (value noise; section 2 B), cloud-type variety, shadow map.

- Billowy cloud octaves (2 B, cheap try): replaced the 450, 214 and 105 m value-noise octaves by `1 - |2n - 1|` (shot `billow_after`). RESULT:
  worse. The creases make streaky, wispy sheets, and because the folded noise sits high on average the cloud cover rose until most of the sky was
  covered, a mackerel-sky look, not cauliflower. Reverted (the `billow()` helper stays unused). A real fix needs cellular (Worley) noise, whose
  cells are round bumps: 3D Worley costs a 27-cell search per sample, too much per march step in the shader; so bake it once into a 3D texture
  (128 cubed, `Texture3D`, from GDScript `Image` slices or a native bake, as the 2 B proposal says) and sample it.

- Cloud shape with baked cellular noise (2 B) DONE and seen. `PlanetAtmosphere.worley_texture()` makes one `NoiseTexture3D` (64 cubed,
  `FastNoiseLite` cellular, distance, seamless, normalised; the engine builds it on a thread) and `set_cloud_parameters` gives it to the sky and the
  cloud shell as `cloud_worley`. `planet_cloud_march.gdshaderinc` reads it for the 214 m and 105 m octaves as `1 - distance` (round bumps),
  centred so the cover stays the same (two texture reads instead of two value-noise evaluations, so it should be cheaper). Shot `worley_after`
  (same pose as `dense_after`): the clouds now have rounded, lumpy cauliflower tops with creases between the puffs, not smooth smears; the
  coverage looks the same as before. The IGN hatch on the thin edges is still visible. The frame rate read 22 FPS on that shot (the ground
  was still loading; not a cloud measure). Until the texture is ready the clouds draw without that detail (a moment at start).

- Black cracks between voxel LODs FIXED (cheap): `voxel_ground.gdshader` now has `render_mode cull_disabled`. The black dashes (`haze_300` crop `seam_crop`: a thin straight
  black line along a block boundary) were gaps between blocks of different LODs where the culled back side let the black inside of the planet show
  (the generator's lattice differs a little between LODs, so the surfaces do not meet exactly). With back faces drawn the cracks fill with ground
  colour: shot `crack_after2` (300 m, same pose as `haze_300`, ground loaded): no black lines anywhere. Not fixed: the cracks themselves (a
  one-voxel step may show as a thin discoloured line close up); and the first frames after a shader recompile hitch (1 FPS shots with the
  ground not loaded show the far sea sphere over everything, which is just the loading state). Stock engine: ran the lab headless with
  `--no-voxel`, no parse or shader errors.

## 4. Shadows (read only, nothing changed)

Ours (`planet_atmosphere.gd`, lines 308-317; `graphics_settings.gd`): the sun's shadow is ORTHOGONAL (one cascade) out to 90 m at the user's quality 1
(160 m at 2, 300 m at 3 is not 3: at 3 and above four cascades to 1.5 km with splits 0.03 / 0.12 / 0.4); no shadow from the sky or from clouds
on the ground except the cloud-shadow setting (off in the user's preset); AO is off in the user's preset; no contact shadows; no distance shadows.
UE5 (`ShadowProjectionPixelShader.usf`, `ShadowPercentageCloserFiltering.ush`, `ScreenSpaceShadows.usf`, `DistanceFieldShadowing.usf`, virtual shadow
maps): cascaded shadow maps with PCF/PCSS filtering, a short screen-space contact-shadow trace (`ScreenSpaceShadowRayCast.ush`), distance-field
shadows for far geometry, and per-light virtual shadow maps that keep texel density near 1 pixel at every distance.
Gap at the user's setting: past 90 m nothing casts a shadow, so the far forest and hills are unshadowed and read flat; at 90 m the single
cascade has soft, low-resolution edges close up (a 90 m box in one 2048 map is 4 cm a texel at best, fine, but it spreads over the whole view).
Cheap proposals (not done): (a) Godot's 2-split mode at quality 1-2 (`SHADOW_PARALLEL_2_SPLITS`, split at 0.15, fade) for twice the reach at
little cost; (b) turn on Godot's `light_angular_distance` (the sun's size, about 0.5 degrees) so shadow edges soften with the distance from the
caster as UE5's PCSS does; (c) a long horizontal cloud-and-terrain shadow cast from the heightmap near sunrise and sunset is the real gain for a
planet (long mountain shadows) and needs a shadow map of the terrain, section 2 C. An attempt to compare quality 1 and 2 splits at 9 h was
not usable: the morning shot is dark and ran at 1 FPS (shader recompile hitch).

- Shadows, change made but NOT demonstrated: `planet_atmosphere.gd` now uses `SHADOW_PARALLEL_2_SPLITS` (split 0.2) with a max distance of 150 m (quality 1)
  and 250 m (quality 2), and sets `light_angular_distance` 0.5 (soft, PCSS-like penumbrae). Comparison shots (`sh11_*`, `sh_a`/`sh_b`) were unusable:
  the picture reader rejected two of the images, and the frozen-time pair (`--time-scale=0`) is a dark scene in which the two look the same.
  Need: a bright noon forest edge with trunks and a clearing, same frame, same exposure, and a crop of the shadow edges 20-60 m away.
  Cost not measured (two cascades instead of one: about +1 ms expected). Revert both lines if it shimmers or costs frames in play.
- Shadow comparison retried (`shn_before` / `shn_after`, hour 12, fixed exposure, a small stacked JPEG): at the start spot the forest is dense and in
  shade, so both pictures are dark and look the same; no difference in shadow edges can be read. The change cannot be judged here. A place with open
  ground and isolated trees (the left, sandy part of the land seen from 300 m) is the right test site: walk there (`--pose` only lifts; use a
  spawn at that spot, `--view-dir`/home flags of the lab) and compare long tree shadows at 40-120 m.

## Renderer finding: D3D12 runs out of descriptor heap (found 2026-11-10, not caused by this session's shader work)

A run of the lab exactly as Play Scene starts it (no arguments, 3000 frames, the custom engine, the project's driver `d3d12`) logs 58,000 errors:
`Cannot create uniform set because there's not enough room in the RESOURCES descriptor heap` (4,900), `Parameter "us" is null` (4,900) and
`Uniforms supplied for set (3) ... are not the same format as required by the pipeline shader` (43,000, a material's texture set refused, so
that draw is skipped or drawn wrongly). The first run in this session that had plants on (`base_ground`) already had it, before any shader change
of mine, and runs without plants did not. The same scene on Vulkan (`--rendering-driver vulkan`, shot `vk.png`): ZERO of those errors, 223
other log lines, and the picture is complete. `project.godot` has `rendering_device/driver.windows="d3d12"`. So with plants on, D3D12 on this
build exhausts its descriptor heap (many unique materials and textures: the flora, the impostors, the voxel blocks' per-block materials), and
whatever is drawn with a refused set may be missing or wrong. Recommend trying `vulkan` for the project (one line, a user decision: it is in a
committed section of `project.godot`, so it needs the user's OK and a check on the other machines, macOS uses Metal anyway). Alternatives: fewer
unique materials (the voxel terrain makes one ShaderMaterial copy per block), or a smaller texture count per material.

## 5. Post-processing (read only)

Ours: `components/graphics_look.gd`. A colour grade by 4 levels (contrast, saturation, brightness; the user's preset uses 1, "Natural": contrast
1.06, saturation 1.1) through Godot's `adjustment_*`, optional SSR, SDFGI, glow (bloom with a 1.1 threshold, off at the user's preset), FSR, debanding,
auto exposure (on at the user's preset). No vignette, no lens flare, no film grain, no depth of field, no motion blur, no local exposure.
UE5 (`PostProcessTonemap.usf`, `TonemapCommon.ush`, `PostProcessBloom.usf` and `Bloom/`): one pass does auto exposure with a histogram and
local exposure, bloom (physical convolution or a dual-filter blur) before the tonemap, a slight vignette (`VignetteParams`), film grain,
chromatic aberration, and the filmic ACES-style tonemapper with a toe and shoulder set by `FilmSlope/Toe/Shoulder/BlackClip/WhiteClip`; the
colour grade is done in a LUT after, in wide-gamut (AP1) not in the display's range.
Gaps worth the effort, in order: (1) bloom is off for the user, so the sun, specular glints and the white surf look flat: a small, high-threshold
glow (`glow_intensity` 0.3, threshold 1.4, `glow_blend_mode` softlight/screen) costs little; (2) no vignette, so the frame has no focus: Godot has
none built-in, a screen-space `CompositorEffect` or a full-screen ColorRect shader with `vignette 0.12` is cheap; (3) the tonemapper: Godot's
filmic has no separate toe control; `AgX` (tone_mapper 4) gives a more natural highlight roll-off and desaturation of bright colours, which is what
makes bright skies and white foam look real; try it with `tonemap_white` left at 1.0; (4) exposure compensation: the auto exposure's
`auto_exposure_scale` 0.4 and sensitivities 40-400 are set for a daytime view; a dark forest floor under it is lifted a lot, which flattens the
shade/light contrast the planet should have. Nothing was changed here: (1) and (3) are taste calls that the user's graphics settings already
expose (glow, tone mapper), so the right move is to propose them as new defaults of a preset, not to override a saved preset.

- AgX against Filmic tested (new lab flag `--tonemapper=N`, in memory only; shots `tmap_2` Filmic with white 2.0 and `tmap_4` AgX, same view, hour,
  fixed exposure; both runs were at 1 FPS with the ground still loading, so the picture shows the far sea sphere, but the sky and clouds compare
  fairly). AgX is clearly greyer and flatter: the blue sky loses depth and the clouds go grey-white. Filmic is the punchier, richer one. For this
  game's look, AgX is NOT an improvement; the section 5 suggestion (3) is withdrawn. Filmic with white 2.0 stays.

## 6. Night (looked at, one change)

Shots `night` and `night2` (1 h, fixed exposure, looking up from 150 m): the night is almost black; a cloud deck covers most of the sky and shows only
as dark shapes, the player is a black silhouette, and the star field was sparse (about 370 stars across the whole sky: `step(0.9985, hash)` on a
140-per-radian grid). Changed: `planet_sky.gdshader` star threshold 0.9985 -> 0.9955 (about 1,100 stars, more like the naked-eye sky); the picture now
has visibly more stars between the clouds. NOT changed, gaps: no moonlight on the clouds or the ground in these shots (the moon was out of frame; check
the moon's phase and its light on the sun light `energy` curve), no Milky Way seen (it needs a clearer sky than this cloud cover gave),
no airglow or city-free horizon band, and the player gets no fill light at night (UE5 gives the moon a directional light with its own colour and
`MoonDiskColor`, and a skylight capturing the night sky).

- Frame cost check (lab `--fps`, uncapped, sky-heavy view from 100 m looking up 35 degrees, the clouds with all of this session's changes, 11 h, plants on):
  381 FPS, 43 draw calls, 265k primitives on the RTX 4090 (frame 300). So the cloud changes (denser, 4 light samples, octaves, 3D noise) cost no
  noticeable frame time on this card; a weaker GPU is untested (the cloud quality setting lowers the steps: 6, 10, 16).

- Before and after pictures (left before, right after; files in the scratchpad `shots/`): `compare_ground.jpg` (start spot, 11 h, ground level, plain settings):
  the acid yellow-green grass became green with warm tips, the foliage greens are deeper and the pale veil over the canopy thinner. `compare_300.jpg`
  (300 m up): the left half (before) is the blue-violet sheet with pink trees and black cracks; the right half (after) was taken while the ground was
  still loading at 1 FPS (the sea sphere shows between the trees), so use `haze_300` against `base_300` for that pair instead.

- Vulkan against D3D12, frame rate (same view, plants, 300 m, uncapped, two runs each; the second run of each driver overwrote the first log, so only the last
  pair of FPS lines survived): Vulkan 276-287 FPS steady after load; D3D12 280-338 FPS with one dip to 73 at frame 600, and 2,538 descriptor heap
  errors against Vulkan's 0. So D3D12 is NOT slower here; its problem is the error spam and whatever it skips (unknown), not speed. The 1-FPS
  screenshots seen elsewhere in this log happen in the first seconds after a shader change (compile and cache), on both drivers (Vulkan's first run
  showed 53 FPS at frame 300). Switching the project to Vulkan stays a user decision; there is no speed reason either way.

## 7. Vegetation shading (read only)

Ours: `shaders/world/flora_wind.gdshader` (one shader for plants, rocks, bark, leaves; vertex-colour palette, procedural bark and rock surfaces when
`realism` is up): Godot's standard PBR plus `BACKLIGHT` (a glow from the leaf, brighter when the eye looks along the sun's ray), `RIM`, `AO` from a
bark cavity term, leaf roughness 0.64 (was 0.5), `SPECULAR` 0.3 on leaves; wind in the vertex stage; snow and autumn tinting; no per-leaf
thickness, no translucency from the sun's actual shadow (the backlight does not know whether the leaf is in shadow).
UE5 (`ShadingModels.ush` `TwoSidedBxDF`, line 845, and `TransmissionCommon.ush`): a two-sided foliage model: the lit side gets normal
diffuse and specular, and the unlit side gets a transmitted term, `InvNoL` times the subsurface colour, so a leaf in front of the sun glows
with its own colour; the model works on a "normal distribution length" (a spread of normals over the leaf, SGGX) so a card of many leaves
shades as a rounded volume, not as a flat plane; the translucency respects the shadow map (a leaf shaded by another does not glow).
Gaps in order of effect: (1) the backlight in ours ignores shadow, so under a dense canopy all leaves glow equally (a flat, shadowless look from
below) while only sunlit leaves should: multiply the backlight by the light's `ATTENUATION` in `light()` (Godot gives `ATTENUATION` there, the
shader has no `light()` function for this now); (2) the leaf cards have one flat normal each: bend the normal toward the canopy's
up/outwards direction by the card's distance from the tree centre (a vertex-stage change, cheap), which is the rounded-volume trick of the
SGGX spread; (3) a subsurface colour per leaf type (yellow-green transmitted light, red-brown for autumn) already partly exists in
`transmitted`; (4) a distance fade of the leaf shininess so the far canopy is matte (far trees are impostors, so only the mid-range matters).
Effort: (1) S-M (a `light()` function, mind that adding `light()` changes the shading path for the whole shader), (2) S, (3) done, (4) S.
- CORRECTION to section 7, gap (1): Godot's own lighting multiplies `BACKLIGHT` by the light's `attenuation` (the shadow term included):
  `scene_forward_lights_inc.glsl` line 247, `diffuse_light += light_color * (1/PI - diffuse_brdf_NL) * backlight * attenuation`. So a leaf in the shadow
  of another does NOT glow in this engine, and no `light()` function is needed. The flat look under the canopy comes from the ambient light and the sky
  fill (no occlusion: SSAO is off in the user's preset) and from the shadow distance (90 m, now 150 m), not from the backlight. Gaps (2) and (4) stand.

- SSAO on and off (new lab flag `--ssao`, in memory only; shots `ao_off`, `ao_on`, stacked in `ao_cmp.jpg`; fixed exposure, so the forest floor is
  dark: with the user's auto exposure it would be lifted): with SSAO the creases under the grass and the shaded trunks are a little darker and the picture has
  more depth; the change is subtle at this view, not dramatic. It costs little (60 FPS both). Worth turning on in the Medium preset; the
  user's saved preset (1) has it off, so I did not change any default.

- Sky multiple scattering (1 A), DONE, seen (shots `ms2_12`, `ms2_17.6`, `ms2_19.2`, 300 m, fixed exposure; `ms0_sky` the old look). Not the
  table of UE5, a cheaper stand-in in `planet_sky.gdshader` `scatter()`: at each sample the extra bounce is taken from the lit air three
  scale heights straight overhead (its own sun transmittance, 4 steps, plus the way up), sent every way (1/4pi), and `multi_scatter` now
  defaults to 1. The first try (the local sun transmittance, 0.5) greyed the sky because it only copied the direct light; this one gives
  light where the direct line is shadowed. Seen: noon unchanged blue; 17.6 h keeps its blue and warm glow, not washed out; 19.2 h deep
  twilight has a dim blue-green fill instead of black with the warm band at the horizon. Cost: 14 x 4 extra steps per sky pixel (frame rate
  not re-measured). Caveat: poses differ between the `ms0` and `ms2` shots, so it is a look check, not a pixel difference.
- Sky multiple scattering, cost check: the on-screen counter in `ms2_19.2` reads 59 FPS (the display's cap) with the new sky, so the extra steps
  do not show at this view; a no-cap number was not taken.
- Direction-dependent haze colour DONE, seen (`hz_before`, `hz_after`, 17.6 h, 300 m, looking away from the star, fixed exposure):
  `planet_haze.gdshaderinc` multiplies the haze colour by a tint (0.9, 0.97, 1.12) that fades to none toward the star (smoothstep -0.2..0.6
  of the angle's cosine), so the haze away from the star is the sky's blue and toward it the star's light. Seen: the distant land and shallows
  are a little bluer and cooler away from the sun, the near ground unchanged. A subtle change, kept. Not checked looking toward the star.
Next: cloud/terrain shadow map, then Gerstner waves.
- Cloud shadow on the ground, second look (`cs_on`, 11 h, 600 m looking down, `--cloud-shadows`): no shadow patches visible on the voxel ground
  (the forest is evenly lit). Either no cloud was over the view or the voxel ground's shadow does not show. UNPROVEN still. To settle it: log the
  `cloud_shade_keep` value at the walker (script side) or pick an hour/pose with a dense cloud right overhead, and compare with the flag off.
  A true shadow map (sun-view cloud/terrain depth) is a larger build and is not started.
- Sharp-crested waves (3, Gerstner stand-in) CHANGED, NOT SEEN: `planet_water.gdshader` `waves()` / `wave_slope()` now use `crest_sine` (2*((1+sin)/2)^1.7 - 1,
  a sharp crest and broad trough, its slope `crest_sine_d`) in place of plain sines; compiles and runs. Pairs `gw_before/after` (30 m, yaw 90 looked at
  forest; 1000 m, yaw 35 shows only a thin edge of sea) do not show the water, so no visible difference is claimed. A real test needs a pose
  over open sea (a shore pose or the sea side of the coast). Not a true Gerstner (no horizontal displacement); that needs the vertex step to move xz.
- Sharp-crested waves, seen (`gw3_before` / `gw3_110`, 300 m, yaw 110, 11 h, shore in view, crop of the sea): the difference is small at this
  distance: the crest streaks and foam lines are a little crisper and more broken, the sea's colour is unchanged. Kept (no cost, no artifacts).
  NEW, seen in both: the shallows show a regular pattern of hexagon-like cells (in `planet_water.gdshader`, probably the ripple/caustic noise
  or the shallow tint reading a cellular noise); it looks artificial from the air. Next: find which term makes it (look at `ripple_noise` and
  the caustic/shallows code) and soften or break its regularity.
- Hexagon cells in the shallows, diagnosed in part (`hex_nofoam`: shore foam removed in the shader): the cells stay, so they are NOT the shore foam.
  They are a tint pattern of the shallow water, regular, ~5-10 m, with lighter outlines. Candidates left: the bed seen through the water
  (refraction of the screen texture, the sand/bed colour map), z-fighting between the far sea sphere (`_make_far_sea`) and the voxel water
  surface near the coast, or the water mesh's own facets (this material was "water_lowpoly": `flat_normal` mixed 0.1 into the normal). Next test: hide
  the far sea sphere (`_water` list in `lab_voxel_ground.gd`) and re-shoot; if the cells go, it is the sphere/voxel overlap.
- Hexagon cells in the shallows, SOLVED as to cause (`hex_nosphere`: far sea sphere hidden for one shot, line restored after): with the sphere gone the
  cells are dry sand: the voxel water has holes where the seabed pokes above the sea level, in a regular cell pattern. So they are the seabed's own
  relief (the generator's sand ripples, `5e3af15` "sand ripples and soft patches") at 0.0-0.5 m below/above the surface, not a water shader bug and not
  z-fighting. The sphere (0.5 m below sea level) fills the holes and the foam draws their outlines. Fix belongs to the ground: fade the sand ripple
  amplitude to nothing within ~1 m of sea level, or domain-warp the ripple coordinates so the cells are not regular. Not done yet.
- Correction to the cell entry above: the sand ripples (`planet_sand.gdshaderinc`) are shading only and fade out by 45 m, so they cannot make cells seen from
  300 m. The likelier cause is the voxel terrain itself: a beach bed almost flat at sea level (within +/-0.5 m) at a coarse LOD, whose SDF quantisation
  gives terraced cells that cross the waterline. Test next: shoot the same view at pose 40 m (fine LOD): if the cells are gone or smaller, it is
  LOD quantisation; fix by flattening the generator's shore slope less sharply or raising the sea sphere/voxel water by the cell's step.
- LOD test of the cells (`hex_40`, 40 m, yaw 110): inconclusive, the walker's own spot is inland and at 40 m the forest hides the shore, so no sea is in view.
  The lab pose lifts the player straight up from the start spot; to see the shore from a low LOD the player must be walked to the coast (needs a
  position flag, e.g. `--pos-yaw` or teleport to the beach), which the lab does not have yet. Parked: the cells are minor and seen only from the air.
- Lab flag `--walk=METRES` added (`planet_lab.gd`, after `--pose`): moves the player level that far the way it looks. `walk1` (`--pose=40,-10,110 --walk=450`):
  the player moved (the view changed) but is still in forest, no shore in view; the coast from the 300 m picture is further than 450 m or the yaw
  sign is the other way. Next: try `--walk=900` and yaw 70, or log `planet.water_at_world` along the line to find the shore, then rerun the
  cell test at ~10 m above the beach.
- `walk2` (`--pose=30,-12,110 --walk=900`): still forest, no coast, a clearing at the left. The shore seen in `gw3_110` was to the LEFT of the view,
  not ahead, so walking along yaw 110 misses it; the beach is nearer yaw ~150-170 at a few hundred metres. The cell question is parked for good
  unless it is seen from the ground in normal play (it is a distant-shore pattern only). Moving to the night (moonlight fill) item next.
- Night (6), seen: with `--fixed-exposure` 1 h is pitch black (sun energy 0, fog colour ~0.01), so that flag is useless at night: the game relies on auto
  exposure. With the default auto exposure (`night1`, 1 h, the start spot) the ground is dim, cool blue-green and readable, the glowing flowers
  show, the canopy has shape against the sky. It reads as a believable moonless/dim night, nothing broken, so no change made. Moonlight as a
  directional fill was not tested (the moon's phase that night was not checked); at a full moon the ground should be lit by it, check once with
  a full-moon date before adding a light.
- Moonlight (6), correction and seen: the moon IS a directional light already (`planet_atmosphere.gd`: 0.25 x phase x risen x night, shadowed by
  `moon_shadow`), so the "moonlight fill" candidate is done. `night_22` (moon down) is near black; `night_3` (moon up) is far brighter, the grass and
  canopy lit in cool blue. Seen at 3 h: hard black slanted stripes across the foliage at the top left (leaf-card shadows of the moon with the
  2-cascade split), looks like shadow banding/bias on thin leaf cards. Worth a check: raise the moon's `shadow_bias`/`shadow_normal_bias` or soften with
  a larger `light_angular_distance` for the moon too (the sun got 0.5). Not changed yet.
- Moon shadow stripes: tried `moon.light_angular_distance = 0.5` and `shadow_blur = 1.5` (`night_3` vs `night_3b`, 3 h): no visible change; the dark slats
  are still there, so they are the real shadows of the big fern fronds overhead (long thin leaf cards) rather than bias banding. Reverted, nothing kept.
- Cloud shadow on the voxel ground, PROVEN (`csdbg`: 11 h, 300 m looking down, `--cloud-shadows`, the shader's result painted magenta for one shot, the line
  restored after): patches of shade lie on the ground in the near-detail area with soft, irregular edges, the open ground between them clear. So
  `cloud_shade_keep` works on the voxel ground on the double engine (the "world position trap" does not bite here). Why the earlier plain shot
  showed nothing: the patches are soft and the real darkening is only 0.5-0.7 of the direct light, under a bright sky; the setting is off in the
  user's preset. Limits seen: only inside the detail area (outside it the ground has no cloud shade), and the shadow's noise is the old cloud
  shape (not the Worley octaves the sky uses now), so a shadow and its cloud do not line up exactly.
- Cloud shadow shape vs the Worley clouds: DECIDED NOT TO DO for now. Matching needs the 3D Worley texture in the ground shaders: a new `global uniform
  sampler3D` declared in `project.godot [shader_globals]` (another hunk in the never-committed file) and published by PlanetAtmosphere, or an analytic
  27-cell Worley per ground pixel (costly). The two Worley terms are the finest octaves (105-214 m), which only shape the shadow's edge;
  the 450 m+ blobs already match. Low gain for a new global and cost. Revisit if the shadows are turned on by default and look mismatched.
- Renderer switched to Vulkan at the user's go-ahead (`project.godot` line `rendering_device/driver.windows="vulkan"`, was "d3d12"; this file is never committed, so
  the switch stays local unless the user carries it). Run `vk` (300 m, yaw 110, 11 h): log says "Vulkan 1.4 - Forward+ - RTX 4090", 0 descriptor-heap
  errors (D3D12 gave 900-58,000), picture matches the D3D12 ones (same sea, shore, forest, clouds), 60 FPS. Remaining log errors: the 224 pre-existing
  `get_node_or_null` thread-guard errors and the usual leak lines at exit.
- `get_node_or_null` thread errors FIXED (not graphics, a log clean-up). Cause: four native helpers looked the GraphicsSettings autoload up by name
  (`get_node_or_null`), and two of them (`graphics_value` in `planet_scatter_script_native.cpp`, `graphics_int` in `planet_world_native.cpp`) run on worker
  threads, which the engine refuses (224 errors per run). New `native/planet_crust/src/graphics_lookup.h`: `graphics_settings_node()` finds the node on the
  main thread once and keeps its object id, which any thread can resolve; a worker that asks before the main thread has (not seen) gets the default.
  Built with the double build (`scripts/build_native.sh --double`); run `nt` (same pose as `vk`): 0 thread errors, only the exit-time leak lines remain,
  the picture is the same (trees and plants present). The stock (non-double) and release libraries were NOT rebuilt here; rebuild them before using them.
- True Gerstner waves (3): NOT DONE, with the reason. The sea's waves are 0.28 m high (`wave_height`) on wavelengths of 7-28 m. A Gerstner wave moves each
  point sideways by about the wave's height (amplitude x steepness), so here a fraction of a metre: invisible from any distance the sea is seen at
  (the view is from the shore or the air, never a metre above the surface). What would show is a bigger sea state, not the sideways motion: wave_height
  2-4x for open sea (`roll` = 1), longer wavelengths, whitecaps where the crest is steepest. That is a look/taste change (and the far sea sphere
  and shore shallows would need the swell to fade near the beach, `roll` already does for ponds). Needs a pose on the shore to judge; the lab can
  now `--walk` but the beach is at roughly yaw 150-170 a few hundred metres away.
- Bigger swell, tried at the user's go-ahead: `planet_water.gdshader` `wave_height` 0.28 -> 0.8 (`nt` before, `swell_big2` after, same pose: 300 m, yaw 110,
  shore in the lower left, fixed exposure). Seen: the deep water gets a visible chop and sun glints instead of a flat blue sheet; the shallows and the
  shore line are the same (the waves ride on the depth tint), no artifacts, no change at the waterline. Kept at 0.8. Not judged: the look from
  the beach or inside the water at 0.8 m waves (swimming/underwater views), and ponds (their `roll` already scales them down). If the sea looks too
  rough in play, 0.5 is the middle.
- User report (screenshot, 100 m over the sea, Vulkan): far clouds look grainy (a dotted pattern) and the sea shows rows/cells. Both seen and both mine:
  (1) clouds: the interleaved-gradient jitter with at most 16 steps of ~750 m on a far ray: the error is structured, at 1:1 it reads as a dotted
  hatch (I had put the dither in my own screenshots down to the downscale: wrong). Changed `planet_cloud_march.gdshaderinc`: up to 28 steps (quality 2;
  `cloud_steps_max` x 1.75, so quality 1 gets 17 and quality 0 keeps 10) and the jitter cut to 0.45 of a step. Seen (`grain_fix2`, 1:1 crop): the dots are much
  weaker, faint horizontal banding in places, cloud edges still lightly stippled. Better, not perfect: the real cure is a temporal accumulation or a
  small blur of the cloud result (not done). Cost: more steps on far cloud pixels, frame rate not re-measured.
  (2) sea rows: the four sine swells ran along the axes and the diagonals (x, z, x+z, x-z) and with `wave_height` 0.8 laid a lattice of rows over the
  sea. Now each swell has its own off-axis direction vector (`WAVE_K0..K3` in `planet_water.gdshader`); `grain_fix` sea crop: the lattice is gone, the swell is
  irregular. The cells in the shallows near the shore (the terrain's, see above) are still there.
- Cloud grain, second round (user: "looks worse", screenshot with horizontal bands): the 0.45 jitter traded dots for bands. Tried three: (fix3) full
  jitter + the density's fine octaves faded out by the step length (`max(t * PIXEL, step_len * 0.08)`, so detail finer than the step does not alias):
  smoother clouds, a fine diagonal hatch remains; (fix4) no jitter: strong horizontal banding, no noise. Kept fix3 (full jitter, 28 steps at quality 2,
  filtered detail). The hatch is the jitter's own pattern: the real cure is a blur or temporal accumulation. Option not tried: let the sky render in
  Godot's half-resolution pass (`AT_HALF_RES_PASS`) so the bilinear upsample smooths the dither; or march the clouds in a SubViewport at half size and
  blur it. Needs the user's say, it changes how the clouds are drawn.
- Cloud tests from inside and under the layer (current shader: 28 steps, full jitter, step-filtered detail; shots `cl_700_0_120`, `cl_1000_20_40`, `cl_300_60_0`, centre crops 1:1,
  11 h): at 700 m (in the layer) the clouds are smooth and puffy with soft lit tops and shaded bases, little grain; a few slanted streaks at far edges at the top
  right. At 1000 m, looking up and level, the near puffs are clean cauliflower shapes with crisp edges (good), but one far, flat cloud on the right has a strong
  diagonal hatch. From 300 m looking straight up the thin cloud at the zenith shows a fine dotted moire. So the grain is not everywhere: it sits on far,
  thin or grazing clouds, where each ray takes long steps through low density. Near/mid clouds are fine. Next if wanted: half-res sky pass or a blur,
  or more steps only where the ray is long and the density low.
- Cloud steps 28 -> 48 at quality 2 (`STEPS = 48`, cap `cloud_steps_max * 3`: quality 1 gets 30, quality 0 gets 18; short rays still use path/70, so only long
  rays pay): `cl48_300_60_0` (looking straight up) the zenith cloud is smooth, the dotted moire is gone; `cl48_1000_20_40` the far flat cloud's strong hatch is much weaker,
  one small patch of slanted hatch remains near the middle. Clear gain. Cost: the frame counter reads 60 (the cap) in both; a no-cap measurement was not taken.
  Remaining grain only on a few very thin/grazing clouds.
- Cloud step cost, measured uncapped (`--disable-vsync --fps`, RTX 4090, Vulkan, double engine, 11 h, 300 m looking straight up at the clouds, frames 900-1500):
  48 steps: 521 FPS (GPU render 1.3 ms); the old 16 steps: 565 FPS (1.2 ms). About 8 % slower in a view that is mostly cloud sky, 0.1 ms of GPU time. Fine.
  (No need for online research: it was a local measurement.)
- Dusk haze density (decision item): `HAZE_DEPTH` 0.09 / 0.18 / 0.30 at 18.1 h, 250 m, yaw 200 (`haze_0.09`, `haze_0.18`, `haze_0.30`): the three pictures are almost
  identical, so the knob is not worth a decision; the greyness of the view comes from the sky, clouds and the sea's pale reflection, not from this layer. Left at 0.18.
  Seen in all three: the sea at dusk is a pale, flat, glassy sheet (mirror of the bright low sky at grazing angles), correct for water but it hides the swell;
  a small darkening of the reflection or a wave normal at grazing angles would help (not done).
- Sea lattice FOUND and fixed (user's "rows or cells"): the regular diamond lattice over the open sea was neither the swell nor the value noise nor the mesh
  facets (rotating the ripple grids, breaking the short swells with a slow noise `short_gain`, and `flat_normal` mix 1.0 left it unchanged: `dusk_sea3/4/5`) but the
  screen-space mirror of the land: `mirror_of_the_land` marched fixed steps and its hits and misses fell in a lattice, and rays that did not rise
  hit the sea bed seen through the water. Switching the mirror off removed it (`dusk_nomirror`). Fix in `planet_water.gdshader`: the start of the march
  is jittered (IGN) and rays that do not rise from the planet's local up (`haze_eye` global) give no hit. Seen: `dusk_sea6` the dusk sea is a smooth sheet
  with the swell and shore foam, the lattice is gone; `day_sea7` (11 h, 100 m) the day sea is clean blue with fine chop, turquoise shallows and
  surf. Also kept from this round: the off-axis ripple grids and the `short_gain` breaking of the two short swells; far roughness 0.14 (was 0.24) and
  `long_keep` falling only 10 % (was 25 %); `flat_normal` mix 1.0 (pure smooth normal). Do these last three matter? Not visible in the pictures; harmless.
- Shore cells, lattice hypothesis REJECTED (`lat_base` vs `lat_fine`, `--voxel-lattice=1,1,4`, a temporary flag, removed): with the height lattices at 1 (every voxel) and exact
  levels up to 4, the cells and the comb of foam teeth along the waterline are the same. So they are not the coarse height interpolation of the voxel generator
  (`voxel_generator_planet.cpp`) nor the water volume's own lattice. What is left: the terrain's heights themselves carry a small cellular/plated relief (metre-scale,
  well under half a metre) that only shows where the bed is within that of the sea level, as polygon-shaped bars of sand with foam outlines. To check: print the
  planet noise height along a line across the shallows (`planet.noise.height`) and look for a cell pattern of a few tens of centimetres; if so fade that term to
  zero within ~1 m of the sea level (in the planet's noise, native), or let the foam use a smoothed depth. User's screenshot (the sea from 100 m): the same cells
  at the right, a comb of teeth at the shore, and regular rows of sun glints on the left.
- Glint rows (user's screenshot, sun glints in regular dashes on the left of the bay): `planet_water.gdshader` `short_gain` now also fades the two short swells'
  slope with distance (x 0.2 by 250 m) so far glints are not lined up in rows. `glint2_before/after` (14 h, 150 m, yaw 150): no sun glints in that view, so the
  two pictures look alike; the effect is NOT shown, only the code change, to be checked looking toward the sun (yaw ~ the sun's, from 100-200 m over the bay).
- Shore cells, height check and diagnosis (`--height-line=YAW,METRES,STEP`, new lab flag; `HEIGHT_LINE` log): along yaw 160 the planet's exact height crosses sea level at ~500 m and
  rises/falls at ~2 % slope in the shallows; after a cubic trend the relief is +-0.15 m (std 0.07 m) with wavelengths of 30-140 m (a 2 m term is tiny): no 5-10 m cell pattern
  in the noise. Pictures: with the water discarded (`cells_nowater`) the bed is a smooth sloping plain of a few big flat facets, no cells; with refraction off
  (`cells_norefr`) or the shore foam widened and weakened (`cells_foam`) the cells stay. So the cells are the waterline itself: on a 2 % slope a +-0.1 m error in
  the bed mesh moves the waterline by +-5 m, and the coarse voxel levels (8 m or more per voxel, heights sampled once per node, trilinear between) cut that small
  relief into polygons of sand above / water below. Not the lattice (tested), not the water shader. Options: (a) fade the noise's small octaves
  (the 2-30 m relief) to zero within ~1 m of sea level in the planet noise height (native; shores become glassy-smooth, cells go); (b) darken/tint the sand
  just above the waterline as wet sand so the polygons' edge is not a hard light/dark step (shader only, cheap, hides rather than cures); (c) sample the water
  surface thickness from the exact height instead of the depth buffer (not possible for a screen-space water). Not done: needs the user's pick between (a) and (b).
  `cells_foam` change reverted. The earlier sea-lattice and glint fixes stay.
- Shore cells, FIXED at the source (option a): `PlanetCrustNative::ground_height` (native, `planet_crust_native.cpp`) is now a wrapper: within ~2 m of the sea level it
  blends the height toward the mean of four neighbours 15 m round (`ground_height_raw` is the old function), so the small relief that moved the waterline by metres on the 2 %
  beach is gone while a plain slope is kept. Weight 1 inside 0.6 m of the sea level, fading to 0 by 2.2 m. Built with the double build. Seen (`cells_fix2`: 250 m, yaw 195, 11 h):
  a clean, smooth beach and a continuous shoreline with thin surf, no hexagon cells and no comb of teeth (a few small marks remain in the far left shallows).
  Side effect to know: the lab's SPAWN moved (the spawn search reads these heights: spawn (0.76, 0.36, -0.53), the coast is now at yaw 180-210, ~620 m away instead of yaw 160, ~500 m),
  so my earlier poses (`--pose=..,110`/`150`) no longer show the sea; use yaw ~195. Other users of the height: plants and voxel ground follow the same function (consistent).
  The stock-engine and release native libraries were not rebuilt.
- User's second sea screenshot (cells + comb at the shore, rows of glints, a fine lattice over the whole sea): the shore cells were still there because that run had the old native
  library (the fix needs the editor/game RELAUNCHED: the library is loaded once). The fine lattice over the far sea was still there in my own pictures after the first mirror fix:
  steps tried in `moire_after`..`moire4` (250 m, yaw 195, 11 h): (1) geometry swell fades out beyond 60-300 m (`near_swell`, vertices far off are too sparse for a 6-28 m swell: aliasing);
  (2) two more long swells (`WAVE_K4`, `WAVE_K5`) and a gentler crest exponent 1.4 (two or four swells cross in a regular lattice); (3) the short swells fade fully by 250 m;
  none changed the lattice much; (4) the screen-space mirror limited to 700 m and faded from 250 m: THIS removed most of the far lattice (the marched mirror's dither of
  hits, from the jittered start I added, was the pattern; sky reflection alone is enough that far). Kept all four. Seen in all pictures: one vertical seam in the sea (a step in tint)
  where the voxel water blocks hand over to the far sea sphere (left of centre in `moire4`): not fixed, the next thing to look at (the sphere's colour vs the voxel water's at the handover distance).
- User's third sea screenshot ("no improvement", window "Fps (DEBUG)"): a regular lattice of white sun glints over the bay, comb of teeth at the right shore, a calmer smooth left beach.
  Reproduced only when the sun is ahead: new lab output `SUN_YAW` (with `--verbose-check`) gives the `--pose` yaw that looks toward the star (15 h: 38, 8 h: -149 i.e. 211, 10 h: -137, 12 h: -15, 18 h: 51).
  At 8.5 h, 200 m, yaw 205 (`glintnow`): the same lattice of glints (smaller than the user's). Cause: the swell is a sum of a few sines, and at 20-50 m wavelength a few pixels
  across, their crossing is a regular diamond lattice that the sun's specular lights as dots. Change: `long_keep` now falls to 0.3 by 600 m (was 0.9 by 1000 m) and far roughness
  +0.22 by 800 m (was +0.14): `glintnow2` the lattice and the dots are gone, the far sea is a calm soft sheet (the price: less sparkle far out; near water keeps its chop).
  Also added: `thickness_bias` (the far sea sphere adds its 0.5 m back to its depth tint) and the roll-map window edge fades into the open sea; neither removed the one straight
  vertical-edged patch of lighter shallows left of centre in the pictures (so it is neither): it stays, unexplained; candidates: a coarser/finer voxel LOD block of the bed
  under the water (the bed seen through it changes at the block edge), or the hand-over of the voxel water to the far sphere (`_water` in lab_voxel_ground.gd).
  Online research was not needed: all of this is local rendering behaviour that I reproduce and measure. It does need the game RELAUNCHED to take the native fix.
- CLOUDS FOLLOWED THE PLAYER UP (user: "when I move up the clouds move away, you cannot reach one, it was possible before"): REPRODUCED and FIXED. Pictures at 50/400/700/1100 m,
  same yaw (`rise_*`): the same big cloud stays at the same size and place on screen at every altitude. Cause: the double-precision engine draws camera-relative, so the sky shader's
  `POSITION` (and the shell's `INV_VIEW_MATRIX` eye) is about zero, not the world's: `origin = POSITION - planet_centre` was a constant, the layer stood at one height over the
  eye whatever the altitude (the same trap as the haze). `planet_sky.gdshader` and `planet_clouds.gdshader` now take the eye from the `haze_eye` global (the eye from the planet's centre,
  published every frame by PlanetAtmosphere). Seen (`riseb_*`): at 400 m the clouds are above, at 700 m the layer is at the character's height (the character stands among the clouds'
  tops), at 1100 m the layer is below, the clouds are fixed in the world and can be reached and passed. The sky's air scattering used the same origin, so the sky colour at altitude is now right too.
- Same camera-relative trap in the cloud shadow on the ground: `cloud_shade_keep(world_pos - cloud_centre)` (planet_ground) and `(lab_pos - cloud_centre)` (voxel_ground) used a position made from
  MODEL_MATRIX, which on the double engine is relative to the camera, so away from the lab's origin the shade would be asked at the wrong height. Both now ask
  `haze_eye + mat3(INV_VIEW_MATRIX) * VERTEX` (the true eye from the planet's centre plus the view-space offset, correct on both engines). Compiles, no shader errors, renders
  (`csfix`, 300 m, 11 h, shadows on). Not shown as a before/after (the earlier magenta test was a one-off): it matters when the walker is far from the world origin.
  Grep of the other planet shaders found no other CAMERA_POSITION_WORLD / POSITION - centre uses.
- Straight-edged lighter patch in the sea, narrowed down (`seam3`, `patch_nosphere` = far sea sphere hidden for one shot, `patch_late` = frame 2600): it is not a loading artefact (still there at
  frame 2600) and not the sphere's depth tint or the roll-map window (both tried). With the sphere hidden, the patch shows the sand bed with wave glints and NO blue water, while the water
  to its right is intact: so the VOXEL WATER has a block-shaped hole there (the sphere, 0.5 m lower, fills it with a thin, lighter tint). The edge is straight and block-aligned. Suspects, in
  `native/voxel_planet_module/voxel_generator_planet.cpp` `generate_water`: the early-out when `centre_length + half < radius + lowest_ground - WATER_DEPTH - spacing` (the lattice's
  lowest ground vs the block) or the first one (block wholly above the sea). To confirm: log the skipped blocks' origins/LOD near this spot; that needs the voxel module rebuilt into the
  engine (scripts/install_voxel_planet_module.sh + scons), which I did not do unattended. Cheap mitigation not applied: raise the sphere closer to the level. The lab's `_make_far_sea`
  line was commented for the test and restored (verified).
- Shore after the height blur (`shore_chk2`, 350 m, yaw 195, 11 h): the beach is smooth, but the shallows show a regular BRICK pattern: rows of rectangles of water and sand, straight edges, all
  aligned. Hypothesis "voxel height lattice" tested again with the blur in (`shore_fine`, `--voxel-lattice=1,1,6`, temporary flag, removed): identical picture, so the pattern is not the terrain's
  height sampling (the exact height is smooth after the blur). It follows the voxel WATER: the sea is a thin slab (SDF = max(distance - level, (ground - WATER_DEPTH) - distance)); on a flat
  shallow bed the top and bottom faces meet and the slab's sign flips per voxel in rectangles (the mesher cannot cut a slab thinner than a voxel; at coarse LOD a voxel is metres), and on a
  plane exactly at a voxel node's height the float32 `p.length()` (0.002 m error at 20 km) flips signs too. Candidates for the fix, all in the voxel module (engine rebuild, not done unattended):
  (1) make the slab at least ~1 voxel thick at the level of the block (WATER_DEPTH >= 2 x step), (2) offset the sea level by a quarter voxel off the node lattice, (3) compute the distance from the
  centre in double or relative to the block. Cheap shader-side stopgap (not done): fade the shore foam/colour contrast out beyond ~150 m.
  Correction/limit of the above: WATER_DEPTH is 6 m (a slab 6 m under the ground line, hidden by the bed), so "slab thinner than a voxel" applies only at coarse levels (voxel >= 6 m, LOD 3+);
  the bricks are tens of metres across, which fits LOD 2-3 blocks. The honest status: cause not proven. The experiment that would settle it (the voxel module's `generate_water` logging the surface
  of a block near sea level, or forcing LOD <= 1 near the shore with `VoxelLodTerrain.lod_distance` larger) needs an engine rebuild or a bigger lod_distance (try `lod_distance` x2 in the lab next, cheap).
- SHORE BRICKS SOLVED (the cells, the comb of teeth, the rows of bricks): the cause is the LOD of the voxel WATER. `lod_distance` (how far each level of detail reaches, 48 by default) set to 160
  for both terrains (`shore_lod`): a perfectly clean shore, one continuous surf line, smooth shallows, no bricks. Split test (350 m, yaw 195, 11 h): water only 160 -> clean (`lodcost_water160`);
  ground only 160 -> bricks stay (`lodcost_terr160`). So the coarse water blocks cut the thin shallow slab into bricks; the ground was never the problem (the height blur and the generator lattice
  tests were side roads; the blur is harmless and stays). Costs measured uncapped (RTX 4090, Vulkan): both 160: ground ready after 180 s vs 20 s, 22 FPS vs 325, 1.7 GB vs 0.7 GB (unusable);
  water only 160: ready after 40 s, 312 FPS, 744 MB (almost free); water 100: 30 s, 318 FPS, residual dotted circles far right; chosen 160. `lab_voxel_ground.gd`: `WATER_LOD_DISTANCE := 160.0`
  set on the water terrains (sea and rivers); the ground keeps the default. Needs the game relaunched (it is a lab script, not a shader). The straight-edged hole in the voxel water is probably the
  same coarse-block cause (not re-checked at 160).
- The straight-edged lighter patch in the sea, checked at `WATER_LOD_DISTANCE` 160 (`patch_lod`, 8.5 h, 200 m, yaw 205, same pose as `seam3`): GONE. The sea is one uniform sheet from the shore to the horizon, no
  block-shaped hole. So it was the coarse water blocks too; no generator change needed.
- Regression look after the day's changes (cloud origin fix, sea changes, water LOD, haze/sky): `reg_17`/`reg_19` (300 m, fixed exposure, 17.6 h and 19.2 h; compare `ms2_*`): the sky and twilight read right
  (the clouds differ because they are now at their real height: a 450 m layer seen from 300 m is big and close, not the old fixed far one; twilight keeps its warm horizon band and dim fill). `reg_ground` (the start spot on foot,
  14 h, no pose): a lush, clear ground view (green grass, layered ferns and canopy, soft haze depth), nothing broken, 60 FPS. No errors from the shaders in any of these logs.
- Cloud grain, half-resolution pass tried and REVERTED: marching the clouds in Godot's sky half-res pass (`AT_HALF_RES_PASS`, read back with `HALF_RES_COLOR` in the full pass) so the bilinear upsample smooths the
  jitter. `return` is not allowed in `sky()`; restructured as if/else the sky rendered flat grey (`halfres`) and the editor segfaulted once. `planet_sky.gdshader` restored to the version with the
  origin fix and the multiple scattering (checked: no half-res code, clouds back in `halfres_back`). Remaining grain: a few thin, grazing clouds. Untried options: a temporal accumulation of the cloud shell
  (`planet_clouds.gdshader`, needs a history texture) or a small blur of the shell's output; both bigger jobs.
- Stock engine check (the standing rule: the lab must still compile there): `Godot_v4.7.2-stable_win64.exe --headless planet_lab.tscn` with `--plants --grounded --procedural --shot-frame=200`: no Parse Error, no
  shader error, the lab runs its frames (the only script error is `save_png` on a null image, which is the headless renderer having no picture; the run was stopped by the 120 s timeout). The voxel code stays
  behind `ClassDB` checks and the new lab code (`--walk`, `--height-line`, `SUN_YAW`, `WATER_LOD_DISTANCE` only used by the voxel script) names no voxel class in `planet_lab.gd`.
- Native libraries all rebuilt with the day's native changes (`graphics_lookup.h` thread-safe settings lookup, the shore height blur, the Caves map layer): debug single and double (built 10 Nov 18:00), release single
  and release double (`scripts/build_native.sh --release`, `--double --release`, 12 Nov 01:40). So the stock engine's library and an exported game's library are current too. (The `bin/` files are build outputs.)

## 2026-11-12 (later): fake trees off, coast patches investigated
- `PlanetScatter.set_fake_trees_on(bool)` (native): off = no impostor cards, no far/horizon tree meshes, the full tree only within 80 m. The lab turns it off by default for now (TEMPORARY); `--fake-trees` brings them back. Verified by shot: no distant tree blobs.
- Coast patches (light-cyan polygons with straight edges in the shallows, and small ponds on the beach): reproduced with `--voxel --pose=100,-30,195 --walk=520`. NOT caused by: the far sea sphere (`--voxel-no-far-sea`, same patches), the swell (`--voxel-calm`, same), the see-through seabed (fading it with distance changed nothing), nor the height blur (widening it to 5 m / 20 m left them in place; 60 m moved the spawn out to sea, reverted). They are real shallow dips just under sea level cut by the coarse voxel levels. Still open. New lab flags: `--voxel-no-far-sea`, `--voxel-no-water-mesh`, `--voxel-calm`.
- Crash (flying up/down): the log had only unsymbolised engine addresses (no PDB for the custom engine); a scripted `--fly-check` ran clean. Not reproduced.

## 2026-11-12 (later still): voxel load time
- Measured ("VOXEL ground ready", `--voxel --pose=100,-30,195 --walk=520`): no water terrain 19.0 s; water lod_distance 160 + view 4096: 41.9 s; 160 + view 1024: 38.0 s; lod_distance 96 + view 4096: 27.4 s; 96 + view 1024: 27.5 s. The GDScript side is negligible (frames ~2 ms uncapped; planet load 8.7 s is native; PlantMeshNative is 6-14x faster than the scripts; species+archetypes 4.5 ms).
- Kept `WATER_LOD_DISTANCE := 96.0` and the sea's view at 1024 (the far sea sphere covers the rest): ~14 s less load than 160/4096, shore still clean in the shots (w_96, w_96_v1024).
- Decision: the remaining systems/world_gen scripts (bakers: GPU orchestration; species/archetypes: once per world; the flat-world generator: unused by the planet) are not ported: no measurable gain.

## 2026-11-12 (end): the species stack is native
- Ported to C++ (native/planet_crust/src): PlantSpecies (plant_species_native), TreeGenome + TreeArchetypes (tree_*_native), SpeciesGenerator, SpeciesRegistry + PlantMeshes (species_registry_native). The GDScript originals were moved out of the project (kept in the session scratchpad only); callers updated (`SpeciesRegistry.create(seed, count)` instead of `.new`, `TreeArchetypes.names()/plants()` instead of the constants, `PlantSpecies.form_names()` instead of `Form.keys()`, `PlantSpecies.Layer.GRASSLAND` instead of `Layer.GRASS`: a native class cannot hold two enums with a GRASS).
- Checked: seeds 8 and 1337, 36 species each: species summaries, colours, archetype names and the genome dictionaries are identical to the script version (216/216 lines); mesh triangle counts of native_plant_bench unchanged (231463 / 273715); the lab renders the same (61.48 M primitives, same frame).
- Still script: tree_grower/plant_leaf_shapes/plant_*_builders (fallback used only by tree_builder_lab and the bench), flora_meshes.gd (materials, scenery kinds), the bakers.
- Later: FloraMeshes is native too (flora_meshes_native: materials, scenery meshes, turf tufts, gravel chips; `FloraMeshes.set_detailed/get_detailed` replace the static var). The fallback tree grower scripts (tree_grower, plant_tree_builders) are gone; tree_builder_lab and native_plant_bench use PlantMeshNative. Same render as before (61.48 M primitives, 33 FPS at 120 m); ground-level shot shows turf, rocks, logs, stumps. Left in GDScript on purpose: plant_leaf_shapes + plant_ground_builders (lab helpers only), mesh_builder.gd (the old flat-world generator), the bakers.
- One crash seen at startup in a lab run (a `--voxel --pose` run right after a headless editor run, "CrashHandlerException" right after LOADED); the two reruns were fine. Same kind as the one you saw; no symbols, not reproducible on demand.

## Low flight over the trees: crash and trees popping in (2026-11-12)

- Crash: reproduced with `planet_lab --plants --voxel --fly-check` (low free flight at 100 m/s) within seconds. A symbolised engine (`E:\Godot\double\src\bin\...double.x86_64.sym.console.exe`, built with `debug_symbols=yes extra_suffix=sym`) put it in `RendererSceneCull::Instance` destructor, `InstanceUniforms` freeing a corrupt HashMap, when `PlanetSurface::free_retired` freed a tile (a heap corruption). It still happened with trees hidden, no trees, plant colliders off, so it was not tied to any one kind of plant. With ONE planting thread the full 90 s flight (18 km) passes, so the planting threads race somewhere. Default is now one (`PLANET_PLANT_THREADS=N` tries more); a tile's plants take 4 ms median / 28 ms mean to grow, so one keeps up and the load time did not change.
- Trees popping in: plants were requested on a 0.3 s timer for the ground round where the player is, so a fast flyer had bare tiles ahead (25 tiles waiting on average, the nearest 160 m away). Now the plants are queued when a tile arrives, 8 are adopted a frame, and the tiles are chosen for where the flyer will be 0.7 s later (up to 200 m): 4 waiting, the nearest 535 m away. Old tiles also keep their trees until the replacement has its own (`PlanetSurface::covered`).
- Plants are made first for the tiles in the camera's view (up to 4 times the distance for those behind it).
- Free flight stays 30 m over the ground where trees grow (`PlanetWorld::TREE_CLEARANCE`), the map keeps its zoom when reopened.
- Debug aids: `--flora-log` in the lab, `PLANET_FLORA_DEBUG=1`.

## Trees only in squares round the flyer (2026-11-12)
Seen from 150+ m up the trees stopped a few hundred metres out and bare ground went to the horizon. Two causes: (1) `planet_surface_native.cpp` gave far trees (plant tier 1) only to levels max-4..max-2 within 40 tiles and none to level max-1 beyond the near ring; now every tile beyond the near trees up to 80 tile widths (about 10 km) at levels max-5 and finer gets them. (2) `PlanetScatter::hang` dropped the far-tree batches whenever the fake trees were off (the lab's default, so plain Play Scene); they are now always hung (the merged far mesh, one draw per tile). Lab repro: `--fly-check --fly-up --flora-log --shot-frame=400` (`--fly-up` climbs instead of diving; `FLORA_KEEPUP by_level` lists wanted/planted tiles per level). Far trees look pale pink-grey from the air (the existing far mesh and colours), not tuned yet.

## Cheaper trees at a distance that are still the same tree (2026-11-12)
Far trees (blobs) and the old lighter tree (regrown with fewer, bigger leaves) looked like different trees. Now `PlantMeshes` lod 1 and 2 of a detailed tree regrow the SAME tree (same dice, same branches and leaf places) and only draw less: every other (lod 1) or fourth (lod 2) leaf card / needle spray / feather strip, the survivors bigger by sqrt(share) (SpeedTree's leaf LOD), chosen by place; the tube sides cut to a half or a third (the dice are still thrown), no smoothed branch paths; the cut triangles count against the budget (`MeshData::phantom`) so the thrift loop lands where the full tree does. Triangles per tree: 11.3k -> 5.1k (lod 1) -> 4.2k (lod 2) on a big conifer, 6.4k -> 2.7k -> 2.3k on a small one. `PlanetScatter::hang` (fake trees off, the lab default): beyond the near trees lod 1 to 1200 m (PLANET_TREE_THIN) then lod 2; real trees reach 5 km (PLANET_TREE_REACH). Lab (`--fly-check --fly-up --tris`, 5 km): trees 770 M -> about 350 M triangles drawn, still only 4 FPS: the real trees to 5 km are too many whatever the leaf cost. The branches and trunks are most of what is left (the leaf cards were about a fifth of a tree).

## Ground-level FPS and the far forest as pictures of the same trees (2026-11-13)
Measured at the start spot, plain Play defaults (`--voxel --fps`): 376 M primitives, 7 FPS: almost all of it real tree meshes between 700 m and 5 km (trees behind trees are not culled: Godot only has frustum and occluder culling, and trees are not occluders). Fix: with the fake trees off, the real tree (lod 0) is within 80 m, the same tree with plainer leaves (lod 1) to `PLANET_TREE_THIN` (700 m), and beyond that the baked impostor of that same tree (`PlanetImpostors`, the nine pictures lit once; `light_trees(..., true)`). Until the picture is baked the card is hidden (no heavy lod 1 fallback drawn from afar). `PlanetImpostors` now bakes a variant's nine views in ONE frame (nine SubViewports) instead of nine frames, tasks ordered variant-major, and bakes 3 variants a tree (was 2): all 87 variants are ready 12.6 s after the start. Result: ground 7 -> 41 FPS (35 M primitives), 150 m up 66 FPS, 300 m up 76 FPS, the forest still covers the view to the horizon and the far trees match the near ones (`g2`, `p150`, `p300` in the scratchpad). The lod 2 mesh is no longer used by the scatter (kept in `PlantMeshes`).
- Near trees in the same scheme: with the fake trees off the real tree (lod 0) is now drawn to `TREE_FULL` (80 m) only, then lod 1, then the impostor; before, the near tiles drew the real tree at any distance. Ground level 41 -> 46 FPS (32 M primitives). `--hide=trees` shows the rest: 88 FPS with the trees hidden, so the trees are still half the frame in a dense forest (the real tree's branch tubes and the heavy bark/leaf shader within 100 m; lowering `PLANET_TREE_THIN` to 350 or 200 m gave 50 / 52 FPS). Tried and dropped: muting twig tubes in lod 2 (no twigs at that level: the limbs of level 1 are 40 % of lod 2, hiding them hollows the tree).
- Natives added this round (AGENT_TASKS/092): `PlanetAtmosphere` (planet_atmosphere_native, was planet_atmosphere.gd on top of WorldAtmosphere; the picture is the same as before, the planet needs no Sky3D or day clock) and `PlanetFauna` (planet_fauna_native; meshes still made by mesh_builder.gd once). `world_weather.gd` has `var atmosphere` untyped now (the flat world still passes its WorldAtmosphere). Left as script on purpose: planet_swim (reads ten properties of the GDScript Player each physics frame: a native version would be slower), planet_bark_bake (a coroutine run once), world_weather/rain/clouds (particle nodes, tiny per-frame cost).
- Checks: planet_check species PASS (its script used `PlantSpecies.Form`, now `form_names()`), noise_golden updated to the new hash (the shore height blur changed the heights on purpose), planet check PASS with `--no-voxel` and FAIL only with `--voxel` headless (headless has no voxel ground: off_floor=40; not related), `--fly-check` 18 km PASS with the impostors.
- Impostors seen from above (`h1500`, 1.5 km up, pitch -50): the cards were tall single side views leaning to the eye, so from the air the trees looked like thin dark sticks. The atlas now has three rows of eye heights (0, 35, 65 degrees; `PlanetImpostors::ELEV_DEG`, `ELEVS`) and the picture from above, 25 views in one frame, cells 96 px (was 8 views of 160: 1.4 MB less texture per variant than three rows at 160 would be); `planet_impostor.gdshader` faces the card to the eye (up projected on the view plane) and blends rows by the eye's height. The atlas was checked by dumping it (`IMPOSTOR_DUMP=path` writes the atlas of species 1 variant 0). Colour check against the real lod 1 trees from 300 m (pitch -30, `PLANET_TREE_THIN=6000` against 700): the mean colour of the forest bands differs by under 3 % (so the `tint` 0.58 is right) and the frame rate is 10 against 85. From 1.5 km the far forest is still a scatter of narrow dark trees (conifers 30-50 m tall, 8 m wide); NOT compared with real meshes from there (they run at 4 FPS), so whether the density and brightness are right from that height is open.

### Patches of trees blinking while flying forward (2026-11-13)

Measured with the lab's `--fly-check --flora-log --voxel` (the `--fly-speed=N` flag sets the speed). Three causes found:
- **Rebuilt-for-collider tiles dropped their trees.** A ground tile first made without a collider is made again once the walker comes within about 370 m; the new tile had no trees until the planter reached it. `PlanetSurface::inherit_plants` now hands the old tile's trees to the new one (the planter regrows them with trunk colliders and swaps). Tiles losing trees within 500 m: 6.3/s -> 2.8/s at 20 m/s (the rest are real level changes, where the replacement already has trees).
- **The planter was saturated at flying speed (one thread).** Detail 3 (undergrowth, 77 ms and 459 nodes a tile) took 40% of its time and was queued by distance alongside bare tiles; now bare tiles and tree detail go first (`queue_plants` adds 1e6 to the sort key of tiles that already have trees) and an old tile only waits for the trees of its replacement, not the undergrowth (`covered`). Tiles that big (levels 4-5, 1-2 km wide) never come within 700 m of the eye, so they no longer get the thinned-tree node at all, only the picture.
- Starved tiles (wanted trees, none yet): 78 -> 59 at 200 m/s, 3 at 20-50 m/s. At 200 m/s one thread still cannot keep up (84 s of planting in an 80 s run).
- `PLANET_PLANT_THREADS=3` still segfaults within seconds (checked again): the shared state that breaks is not found; more threads is the real fix for very fast flight.
- **Root cause of trees changing while moving (found from the recorded play log): the trees were re-rolled whenever a tile's level or detail changed.** Each tile seeded its random numbers from its own key (level included) and placed trees on its own jittered grid; the canopy spacing was also 13 m at detail 2 and 6.5 m at detail 3 (the 256 m ring). Now the canopy and understory use one lattice laid over the whole face (`for_grid` with a salt): a spot's random numbers come from its place on the face, so any tile covering it grows the same tree. Big far tiles (level < max-1) take every other lattice spot, so a finer tile only adds trees. Check (`PLANET_TREE_DEBUG`): the tree count of a tile at detail 2 and 3 is identical on all 206 tiles that had both (before, the spacing alone differed 4x). Left as before: rocks, pebbles, grass (near detail only) and the far-tree mesh.
- The recorder (`user://planet_live_lab.jsonl` for lab scenes, `planet_live.jsonl` otherwise) now stores `trees_starved`, `trees_nearest_starved_m`, `tiles_lost_near`, `plant_queue` in every sample. Flight at 111 m/s: fps 17-39 and 1-12 tiles waiting for trees at 200-250 m, so the planter still lags at that speed.
- Free flight: a ray straight down keeps the flyer 50 m (`free_mode_clearance`) above anything under it.

### The far trees as the same 3D tree in steps (2026-11-13)
The far card pictures looked fake from above on conifers (thin parallel slivers), so the real tree now thins out step by step before the picture:
- Steps (`PLANET_TREE_THIN` = where the last real step ends, default 1000 m): lod 0 < 80 m, lod 1 to 167 m, lod 2 to 400 m, lod 3 to 1000 m, then the picture. Each is the same tree (the grower throws the same dice at every step).
- lod 3 (new): a quarter of the leaf clusters, twice as long, tubes with every other ring and 3-4 sides, and branches thinner than 6 cm left out (`PLANT_LOD3_THIN`, metres, to tune): species 1 is 11347 / 5078 / 4204 / 714 triangles at lod 0 / 1 / 2 / 3.
- A tile only makes the steps it can be seen at (a tile of width S is never nearer than 1.29 S nor further than 4.8 S), so big far tiles and the finest tiles skip some nodes.
- Cost (lab, plain forest start): reach 700 m 44 fps ground / 96 fps at 400 m up; 1000 m 41 / 67 (the previous 700 m + pictures gave 41-46 / 55); 1500 m 33 / 40. Pictures are still used past the real steps.
- **No pictures any more (user's call: the same tree at every distance, only fewer triangles).** With the fake trees off, every tree is now the real tree in five steps: lod 1 to 120 m, lod 2 to 250 m, lod 3 to 600 m (about 700 triangles, thin branches left out), lod 4 to 1.5 km (about 260: an eighth of the leaves, tubes with every third ring, branches under 15 cm left out), lod 5 to `PLANET_TREE_REACH` (default now 8 km; about 50-230 triangles: a sixteenth of the leaves, branches under 40 cm left out). All are the same tree (same dice). The card pictures are no longer made for the scatter (PlanetImpostors is not asked to bake; the code stays for the fake-trees option). Lab: ground 34 fps, 400 m up 44, 1.5 km up 55; with trees hidden the same start is 43 fps, so about 15 M of the 50 M triangles are the far steps.

### Layers (arcs) in the clouds seen from far above (2026-11-13)
Seen from a few km up, the cloud shell showed sharp concentric arcs near the horizon. Causes in `planet_cloud_march.gdshaderinc`: (1) the haze of a cloud used the middle of the first stretch of the way, which jumps where a ray begins to dip under the layer's floor (now the middle of everything marched); (2) a ray that dips under the floor and comes up in the layer again (far side) lost that second stretch, so clouds were half as thick below the tangent (now marched too: `len_b`); (3) at most 48 samples over a 10 km way showed the layers' edges (now up to 128, `cloud_steps_max * 8`; short ways still take few). One faint arc remains near the horizon (detail is a little sharper below it); not found yet.
- **A cloud that fills the view showed the horizon through it.** `cloud_march` returned alpha = seen + (1 - haze) * (1 - seen), so a fully opaque cloud 3-6 km along the way was 20-40% see-through (the "melting into the air" of far clouds), and the ground and the sky behind it are different colours: a crisp terrain edge inside a storm layer. The melt now only applies when the first 1500 m of the way are clear (`near_seen`): inside a cloud nothing shows through; far clouds melt as before. Checked in the lab (storm, 700 m, inside the layer: uniform), a view from 3 km up and the ground.
- Cloud scattering as it stands (`planet_cloud_march.gdshaderinc`): Beer-Lambert extinction; two-lobe Henyey-Greenstein phase (forward 0.55, back -0.25); the light's way to the star in 4 growing steps; multiple scattering as 3 octaves (Wrenninge: each scatters half as much, is attenuated half as fast); the star's colour reddened by its path through the air (Kasten-Young); blue sky light by height; the far melt into the air; cloud shadows on the ground (a graphics setting). Not done: the powder term (dark edges of thin cloud), ground-bounce light on the undersides, aerial perspective from the sky's own transmittance (now one exponential), light from clouds above onto the ones below.
- Cloud lighting from godot-simple-sky (MIT; https://github.com/rlsl0422/godot-simple-sky): added to `planet_cloud_march.gdshaderinc` a powder term on the direct light (`mix(1, 1 - exp(-od * 2), 0.5)`), a narrow silver-lining peak (`pow(cos_sun, 24) * 0.35 * o1`) and the ground's light on the layer's underside (green-grey, by the star's light, strongest at the layer's floor). Their longer steps through empty space were tried and dropped: the steps no longer line up with the per-pixel jitter and the clouds showed horizontal streaks. Left for later: half-resolution cloud pass, baked 3D noise.
- Cloud cost measured (lab, trees and plants hidden, cloudy, GPU ms per frame with / without clouds): ground 8.9 / 7.6, 3 km up 1.5 / 0.7, inside the layer at 700 m 1.9 / 0.7. So the clouds cost about 0.8-1.3 ms; a half-resolution pass would save about half of that and baked 3D noise less, at some risk to the look (edges against the ground and trees). Not done; the trees are the frame's cost.
- Baked 3D value noise for the clouds (`PlanetAtmosphere.value_texture`, 128^3 FastNoiseLite, one fetch for the eight hashed corners) was tried and removed: the GPU time only fell by 0.1-0.3 ms (ground 8.9 -> 8.6, 3 km up 1.5 -> 1.4, in the layer 1.9 -> 1.6) and the clouds came out flatter and greyer (its spread is 0.106 against 0.185, and the cells are linear between 8 texels, so the cauliflower detail is soft; stretching the contrast did not bring it back). A half-resolution cloud pass was not done: the cloud shell is a spatial shader that reads the scene's depth, and a half-resolution target has no depth of its own (it would need a compositor effect and a GLSL copy of the march). `cloud_quality` (6 / 10 / 16 steps) is the knob for slow machines.

## Scattering pass: haze phase, leaf glow, water transmission

- `planet_haze.gdshaderinc`: the forward lobe round the star is now two lobes (wide `pow(toward,5)` plus a tight `pow(toward,24)` core that grows with the haze amount), a Mie-like phase.
- `flora_wind.gdshader`: leaf BACKLIGHT glow is a wide soft lobe plus a tight core (`0.3 + 0.6*a^1.5 + 2.2*a^6`), was `0.3 + 2.5*a^4`.
- `planet_water.gdshader`: realism-only emission for sun through wave crests (green-turquoise, only looking toward the star, star above the horizon, fades by 1.5 km) and a shallow-water back-scatter.
- Already present, so not redone: the leaf backlight and its yellow tint, per-channel water absorption, volumetric-fog light shafts (the `volumetric_fog` graphics setting), `multi_scatter` in the sky.
- Not done: sky light shafts through clouds (empty-space skipping in the march gave streaks before).
- Checked: one lab shot (ground, looking up) compiled with no shader errors. The water and the sun-facing views were not looked at.

## Port plan: Intel OutdoorLightScattering (epipolar sun shafts)

Source read: GameTechDev/OutdoorLightScattering (Apache 2.0 in `license.txt`; the readme says BSD; archived 2021). Only part of the shader text was read verbatim; the ray-march internals and the pass order are a summary, less certain.

Idea: march the sun's light only along "epipolar" lines that fan out from the sun's screen position (1024 slices x 512 samples), find where the scattering changes (refinement, compute), ray-march only those samples, interpolate the rest, then unwarp to the screen. A 1D min/max mip of the shadow map along each line lets the march skip long lit or shadowed runs.

What a Godot version needs:
1. A CompositorEffect (post-transparent) that reads scene colour and depth, with compute shaders for the slice endpoints, the refinement, the march, the interpolation and the unwarp.
2. A shadow map to march against. **Blocker:** I believe Godot does not give a CompositorEffect the directional light's shadow atlas. Not verified; needs a check in the engine source (we build the custom engine, so exposing it is possible but a fork change).
3. Without the shadow map there are two fallbacks: (a) screen-space shafts from the depth buffer (radial march toward the sun's screen point; works only with the sun in or near view, and cannot see shadows from off-screen casters); (b) march the real world instead: the terrain heightfield, the tree lattice (the scatter is a pure function of the cell hash) and the cloud noise, none of which need a shadow map.
4. Skipping the precomputed scattering LUTs: our sky already has its own single-scatter integral.

Order of work if wanted: (a) first, as a cheap test of the look; then decide on the engine change.

## Screen-space sun shafts (first version)

- `shaders/compute/planet_sun_glow.glsl` (the existing PlanetSunGlow compositor effect): each pixel marches 32 jittered steps toward the sun's screen position (85 % of the way), adds up the sky it passes (depth 0 = sky; geometry blocks), and adds the sun's colour by that share, fading with the distance from the sun. A sky pixel shows rays only where the way is partly blocked (`open*(1-open)*3`), or open sky would only wash out.
- Strength: `PlanetSunGlow.shafts` = glow strength x 0.22 (env `PLANET_SHAFT_GAIN` overrides the 0.22; `NO_SUN_SHAFTS=1` turns it off). It follows the glow's gating (off at night, underwater, on Off/Low shadow quality, sun behind the camera).
- Checked: compiles, runs, no errors. Lab shots at 07:30 and 06:24 with the sun in view showed NO visible rays, even at gain 1.5: those scenes (a flat grass plain, one character) have nothing tall across the sun, and clouds are not occluders in this method (they have no depth). The effect is unproven on trees; look at it in a forest with a low sun.
- Cost not measured (32 depth taps per pixel within about 0.45 screen heights of the sun).
