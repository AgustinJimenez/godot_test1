# 078 - Sand relief and footprints that dent (desert ground)

Status (2026-10-20): **steps 1 (sand shading) and 2 (dent footprints) built, awaiting the user's look (lab: `soil=sand detail=3 dents=1`).** Written after the user asked for desert sand with marks left by steps (and by
anything that falls on it) and asked for "the most realistic approach". The user calls the family of ground-relief tricks "SPOW
texture" (the code keeps the names `spom` / `mosaic`; task 077 has the plates). Work and judging happen in
`tests/manual/ground/ground_lab.tscn` first, then in a desert of the planet.

## What exists already (checked 2026-10-20)

- **A desert exists.** `TerrainNoise.Biome.DESERT` (`planet_noise.gd`), and the native terrain makes **dunes**: low sand ridges
  on flat, hot (`smooth(8, 20)` on the temperature) and dry (`smooth(0.28, 0.08)` on the rain) ground, `crest^2 * 7 m`, a
  wavelength of 170 m across the local east axis, bent by the hills noise (`planet_crust_native.cpp`, "dunes"). So the large
  shape is there; the small one (ripples, grains) is not.
- **Sand in the ground shader:** a `sand_map` texture, used on "pale level ground" found from the painted colour
  (`on_sand` in `planet_ground.gdshader`), and sand "keeps only its grit" in the stones layer. There is no per-place "this is
  sand" value from the crust; the shader guesses from the colour.
- **Footprints exist, as decals:** `systems/planet/planet_footprints.gd`: one `Decal` a step (0.85 m), at most 48, alternating
  feet, kept in planet space, faded over 120 s, in snow, sand and marsh, behind the graphics setting `decals`. A decal is a
  painted colour on the ground: **it does not dent** (no depth, no rim, no light on its edge).
- **Wind:** `planet_weather.gd` has the east-west wind by latitude (trade winds blow west, mid latitudes east); the dunes use
  a fixed east axis, not that wind.
- The ground shader already reads heights per pixel (the plates, `mosaic_height_now`, task 077) and writes the depth of what
  it finds, so a dent can be added to a height it already reads.

## What the research says (2026-10-20; sources of mixed quality, marked)

- **Look of sand (what shipped):** Journey's sand is mostly shading, not geometry (GDC 2013, John Edwards; the page is locked,
  the best public breakdown is Alan Zucconi's series, which is his reading of the talk: https://www.alanzucconi.com/2019/10/08/journey-sand-shader-1/).
  Grains are tiny mirrors (glitter); the grain normals come from a Gaussian random texture (most close to the surface normal);
  ripples are a normal layer blended by the dune's orientation and steepness, like triplanar mapping.
- **Glints:** research treats sparkle as counting the flakes in a pixel that reflect to the eye
  (https://arxiv.org/pdf/2306.05051), or a procedural microfacet BRDF with many sharp lobes
  (https://diglib.eg.org/handle/10.1111/cgf14141). Heavier than needed; the usable idea is several grids of flakes at
  different scales so that nothing tiles or pops.
- **Wind ripples (physics):** a few cm to about 10 cm apart, crests a few mm (to 1 cm) high; coarser grain, coarser ripples; they run
  across the wind; the windward side is about 8-10 degrees, the downwind side 20-30 degrees, steepest at the crest. Spacing from
  saltation (Bagnold 1941) is disputed (https://arxiv.org/pdf/cond-mat/9910252). The slope numbers are from a field-notes blog
  (https://digital-desert.com/blog/ripples/): plausible, not peer reviewed. At 1 cm a ripple is too shallow for a big
  parallax march: **its look is the light on its slope.**
- **Tracks:** the usual method is a texture round the player stamped where feet land and read when the surface is shaded, not
  a mesh change. Rise of the Tomb Raider's snow calls it deferred deformation (the dent is rebuilt while shading;
  https://www.taylorfrancis.com/books/9780203705179/chapters/10.1201/b22483-18); Unreal trails use a grey mask
  (https://www.kodeco.com/5760-creating-snow-trails-in-unreal-engine-4). The realistic part is that the pushed-aside sand
  makes a rim and steep walls collapse, soil by soil (drift-diffusion, https://diglib.eg.org/items/fa4da1ef-6250-4bd7-8c21-a7ecbb4059f5/full).
  Dry sand slumps to its angle of repose, about 30-35 degrees (general knowledge, not from those sources). How shipped games
  fade tracks was not found; blending back to flat over time is the common guess.
- Not worth it here: a volumetric sand simulation.

## Plan

### Step 1: sand that looks like sand (shading first; biggest gain, cheapest)
1. **A sand share from the crust.** Native `material_at` (the same ten bytes as the woodland value; a free byte is needed, or
   the stones' third channel if sand and river gravel never need both) says how sandy the place is: dry, hot, flat, sandstone or
   dune ground, and the beaches. The shader stops guessing from the colour.
2. **Ripples as a normal layer:** across the local wind direction (the dune ridge direction, so a dune field lines up), wavelength
   about 6-10 cm varying slowly (a few noises), asymmetric profile (windward about 9 degrees, downwind about 25), and the ripples
   thin out and bend round pebbles and on the steep dune faces; a second, coarser set (megaripples) where the grain is coarse. Light only
   (no march), faded by distance; maybe a few mm of parallax in the plate march's height term for grazing views.
3. **Grain and glitter:** a Gaussian-normal fine grain, and three grids of flakes (about 1 mm to 1 cm of screen footprint) that
   flash in the sun with a hash of the grid cell and the view; no flicker (stable under camera movement), faded by
   distance.
4. **Dune faces:** slumps (small avalanche streaks) on the steep faces and a lag of pebbles in the troughs.
5. **Lab:** `sand` preset values and sliders (ripple size, ripple height, glitter, wind angle, sand share) in the ground lab;
   a render of each against a photograph for the look.

### Step 2: footprints that dent
1. **A dent picture** like the height bake (`PlanetGroundBake`): a camera-following torus (8 bits, about 1024 px over 12 m: 1.2 cm
   texels), drawn into by a stamp pass (a footprint shape: heel and toe, a pushed rim) when a foot lands; the feet already have contact
   events (foot IK); later also a stone that falls, a dropped item, rain, animals. Replaces the decals on sand; snow and mud
   keep decals until they get the same.
2. **Reading it:** the ground shader subtracts the dent from the sand height (the plate march's height term), takes the light from
   its gradient, and darkens inside (the sand underneath is damper and darker). It adds the depth push to what the shader writes, so
   a stone beside a footprint sits right.
3. **Slumping and fading:** a small canvas pass over the picture each few frames: diffuse the height, then clamp the slope to
   the angle of repose (edges soften first), and drift the whole thing to flat over minutes (wind fills it); ripples show again.
4. **Only on soft ground:** the sand share (and later snow, mud). Collision does not change.
5. **Limits to state:** looks only; marks exist only inside the picture (about 12 m round the player), so walking away and
   back loses them (a bigger or tiled picture is the way to keep more).

### Step 3 (later)
Snow and mud as variants (different depth, rim, repose angle, colour); marks from animals and falling things; wind ripples that
bend round the footprint and re-form; the same relief trick on bark and rocks (the "SPOW" for trees and rocks the user mentioned:
split the generic march, depth write and strata out of the ground shader first).

## How to judge and measure
- Look at: ripples in grazing sun at 0.2, 1 and 1.7 m eye height; glitter while the camera moves (no flicker); a line of
  footprints at noon and at sunset; fading over minutes (`--time-scale` in the planet lab).
- Cost: `godot --gpu-profile --disable-vsync` in the lab (task 077 has the method and the baseline: 4.5 ms standing view); the
  dent picture's redraw timed alone (the canvas pass), the planet's worst case (standing, looking down at sand).
- Checks: `planet_check.sh --quick`, lint, the walk check (no new slow frames); a lab option that stamps a trail by script
  so a render is repeatable.
- Open questions for the user: which grounds beyond sand, what else leaves marks, how long marks last (default: sand, feet,
  a few minutes).

## Done: step 1 (2026-10-20)

- `shaders/world/planet_sand.gdshaderinc`: ripples from 2.56 m cells (1024 m is a whole number of them: no jump at the planet's coordinate
  wrap or at a rebase), each cell its own direction (across the east-west wind, turned up to 23 degrees), wavelength (0.75-1.35 of
  9 cm) and phase, the eight cells round a point blended (squared weights); an asymmetric profile (rise to the crest at 0.72 of the
  period: about 9 degrees windward at 7 mm, 23 degrees downwind). Glitter: three grids of flakes (4 mm, 13 mm, 4 cm), a fifth of the
  cells with a mirror turned at random, shown by a narrow lobe on the half vector (sun + eye), fixed to the ground; the grids finer than
  a pixel are dropped. Uniforms `sand_ripples`, `sand_ripple_height`, `sand_ripple_length`, `sand_glitter`, `sand_wind_turn`
  (lab sliders "sand:").
- `planet_ground.gdshader`: replaces the old sine ripples (one fixed direction, 3.4 m apart, symmetric). On sand (`sand_ground`, from
  the painted colour, level, not wooded) the plates (colour and relief) give way (`plates_here`), the photo sand texture is weakened
  (it has ripples and pits of its own), the crevice shading and the hand-wide bump are eased. Written to `EMISSION`: a mirror throws the sun
  back, so the glitter does not depend on the direct light (it is not shadowed: a shadowed grain would still flash; fine for now).
- Cost (lab, standing view, detail 3): sand 4.38 ms against 4.83 ms for plated soil; ripples + glitter about 0.05 ms.
- The lab needs `detail=3` (or 2) to show it (the ground detail setting; the lab's default is 1). The planet shows it at High and Ultra.
- Still guessed: the sand share comes from the painted colour (no crust value yet), the wind is the planet's y axis crossed with up (not
  the weather's wind), the ripples are not yet shorter on the downwind side of a dune's crest.

## Done: step 2 (2026-10-20)

- **Not a picture, analytic:** `planet_dents.gdshaderinc` works a footprint out where the ground shader shades (no render target, no
  ping-pong, no torus to clear, nothing to lose when the player walks away). `PlanetDents` (`systems/planet/planet_dents.gd`) keeps up to 240 stamps in
  planet space, every 0.25 s puts the 32 nearest the camera in a 32 x 3 float texture (position wrapped to 1024 m + the clock it was made at;
  the way the toe points + which foot; up) and the shader reads them with `texelFetch`. Age is `dent_now - born`.
- **The print:** heel and ball of the foot as two ellipses (heel 4 x 5.5 cm, ball 6 x 10 cm half sizes), the weight on heel and ball (the arch
  40 % shallower), a rim of pushed sand 25 % as high outside it, 3 cm deep when new. **Ageing:** the depth falls as `exp(-age / (0.4 life))`
  (life 240 s: 13 % left at 3 minutes, so the wind fills it), the edges slump (the softness grows from 4 mm to 24 mm), the "pressed" share
  (smoother, darker sand: the ripples are crushed inside) falls linearly to 0 at life.
- **In the shader:** the dent's slope tilts the normal (finite differences over 4 mm in the ground's tangent plane), the pressed sand is
  40 % darker, the floor of the dent gets up to 50 % ambient occlusion, the ripples fade out inside it. Only on `sandy` ground. The 3D
  stones and the plates are not affected (sand has none of the plates).
- **The player stamps** in `PlanetFootprints._press` on DESERT and BEACH ground (a left and a right foot every 0.85 m, the same events as
  the old decals; the decals remain for snow and marsh). It follows the `decals` graphics setting (on at High and Ultra, off by default
  otherwise). Walk check on a forced-sand run: 240 stamps kept over 427 m, no shader error, the walk check passes.
- **Lab:** `dents=1` lays a trail of nine prints (alternating feet, the oldest `dent_age=150` s, the newest 0): e.g.
  `ground_lab.tscn -- soil=sand detail=3 dents=1 pitch=32 dist=0.9 yaw=15 fx=0 fz=-0.5 dent_age=30`.
- **Not done:** no parallax march into the dent (the far wall does not hide the floor: at a grazing angle a print reads as a lit rim and a
  darker floor, not as a deep hole); no depth written for the dent (a stone beside a print is placed on the plane); only the player
  stamps (not a falling stone, rain, animals); no snow or mud dents (decals); the print does not shear when the foot slides; the
  number of stamps seen is 32 within 0.3 m of a point (a crowd of old prints on one spot would show the nearest 32).
