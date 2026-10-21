# 081 - Visual features Godot lacks against Unreal Engine 5 (the ones we are confident we can build)

Status (2026-10-21): **planned, nothing started.** From the user's question "what could we add that Godot lacks against UE5". Only the
features judged buildable are here; the others (Nanite itself, Lumen itself, Chaos, hair/cloth) are left out on purpose.

**Rule for every item: research first.** Before writing code, search the web for how the feature is done (papers, GDC talks, open
source shaders, Godot proposals and addons), write a short note under the item (what the options are, which one fits a
floating-origin planet in GDScript, shaders and the C++ extension, the expected cost, what to discard), show it to the user if the
choice changes the look or the cost, and only then build. Measure the frame cost before and after (planet look-down render and the
walk check), commit and push each step.

## 1. Impostors and automatic levels of detail for far trees (the Nanite we can afford)
- What: far trees become flat pictures (octahedral impostors: the tree rendered from many angles into an atlas, one quad shows the
  nearest views) and mid trees use simplified meshes, switching without popping.
- Research: octahedral impostors (Ryan Brucks' article and the UE `ImpostorBaker`, Godot addons for impostors), crossfade/dither
  LOD, Godot's `visibility_range` and `MultiMesh`, how the scatter (`planet_scatter_native.cpp`) places trees.
- Why first: the biggest frame-time win in forests, and the tree count can then grow.
- Measured 2026-10-21 (planet_lab `--fps`, seed 1337, eye 1.7 m, ground detail 3): desert 160 fps, GPU 5.9 ms, 2.3 M primitives;
  the default green country 71 fps, GPU 13.8 ms, 11.4 M primitives, of which about 3 M triangles are tree multimeshes
  (4k+ tris trees 1.34 M, 2k+ 0.87 M, 1k+ 0.43 M ...; tiers today: full under 80 m, lighter to 220 m, then a cone or ball).
  So the 80-220 m tier is where an impostor would pay.
- Research notes (web, 2026-10-21): the standard is octahedral impostors (Ryan Brucks, https://www.shaderbits.com/blog/octahedral-impostors;
  UE ImpostorBaker); Godot has an asset "Octahedral Impostor LOD" (https://godotengine.org/asset-library/asset/5528, 144 views, depth
  and normals, MultiMesh) and the older https://github.com/SIsilicon/Godot-Octahedral-Impostors (Godot 3 era); a forum thread
  (https://forum.godotengine.org/t/simple-bilboard-impostor-shader/1990) shows a per-instance view pick in the shader. Not read in depth.
  Decision pending: our trees are procedural per species and variant, so bake one atlas per (species, variant) on the first use
  with a SubViewport, like PlanetImprinter does.

## 2. Dust and sandstorm volumes, and sand that moves (our Niagara and heterogeneous volumes)
- What: a ray-marched dust volume (storms, haze in the desert, smoke), puffs of dust at footsteps and landings, sand blowing off
  crests in the wind, sand sliding down a slip face.
- Research: froxel volumetrics (the `volumetric_fog` of Godot and its limits), raymarched volumes with 3D noise (Horizon Zero Dawn
  clouds, Sebastian Aaltonen's talks), GPU particles with collision against a height field, sand avalanche (angle of repose) in
  cellular automata, "Journey" sand rendering (GDC 2013, Nathan and John Edwards).
- Uses the dune and ground shaders (078) and the wind from `planet_weather.gd`.

- Built 2026-10-21 (first part): `PlanetDust` (a burst of soft round flakes, GPU particles, one-shot) puffs at each sand footprint
  (`PlanetFootprints._dent_sand`). Open: puffs on landings, sand blowing off crests, avalanches on slip faces, the raymarched
  sandstorm volume (research not done).

## 3. A post stack: sun bloom, lens flare, depth of field, per-object motion blur
- What: what the UE post process volume does that Godot's environment does not: a flare and glow round the sun and bright
  lights, a bokeh depth of field, motion blur that also follows moving objects, a film look (grain, vignette, lens dirt).
- Research: the Godot `CompositorEffect` (compute shaders on the rendered frame, 4.3+) and its limits, bokeh DoF by
  scatter-as-gather, McGuire's motion blur, physically based lens flare (Hullin et al. 2011).
- Needs a graphics setting for each (the settings menu has the presets).

## 4. Tile geomorphing (no popping of the ground as you approach). BUILT 2026-10-21 (see below)
- Built: native `triangles` gives each vertex `morph` (metres up to the surface of the tile twice as coarse: odd vertices take the middle of their neighbours, along the quads' diagonal for the odd-odd ones); `MeshBuilder` puts it in CUSTOM3 (R_FLOAT); `PlanetTile._set_morph` sets the instance uniform `lod_morph` (start, end: the last tile width before the bigger tile takes over, 2 * split_factor widths from the tile's middle minus 0.75 width); the ground vertex shader slides the vertex. Checked: forcing the morph to 1 shows the coarse surface (no spikes), the visual baselines hold, planet_check --quick passes. NOT yet seen in motion (a walk over tile swaps); if the user still sees the ground rise, look at it with a screen recording.
- What: where a finer ground tile replaces a coarser one the vertices slide from the coarse positions to the fine ones, so the
  ground no longer rises or pops (probably the "sand rising" the user saw close to slopes).
- Research: CDLOD (Strugar 2010) and geomorphing in clipmaps, how `planet_tile.gd` / `planet_surface.gd` choose levels and what
  the skirts hide; compare with the native tile build (`triangles` in `planet_crust_native.cpp`).

## 5. Water, in stages
- What: waves (a sum of Gerstner waves tied to the wind), shore foam and wet sand, then the underwater look (fog by depth,
  caustics), then screen-space refraction.
- Research: Gerstner waves and FFT oceans (Tessendorf; Godot ocean addons), foam by depth difference, caustics by a scrolling
  projected texture, Sea of Thieves' water (SIGGRAPH 2018).
- Needs: `planet_water`/`planet_sea` meshes and the weather's wind.

## 6. Light probes near the player (the part of Lumen that is affordable)
- What: a small grid of probes round the camera that capture the sky and the bounce off the ground, updated a few at a time, so
  shadowed ground and objects take the colour of what is round them (warm sand bounce, green under a canopy).
- Research: DDGI (Majercik et al. 2019), radiance cascades (Alexander Sannikov), Godot's SDFGI problems here (it reset the GPU
  in a coast view: no preset enables it) and VoxelGI/LightmapGI limits; the cheap version is a sky-and-ground ambient (079 step 1).

## Out of scope for now
Nanite-style cluster rendering, full Lumen, virtual shadow maps (task 079 step 3 gives far terrain shadows instead), hardware
tessellation (not in Godot; parallax and geomorphing cover most of it), Chaos physics, hair and cloth.

### Post stack: first part BUILT 2026-10-21 (sun glow and flare)
- `PlanetSunGlow` (CompositorEffect, POST_TRANSPARENT so it runs in HDR before tone mapping) + `shaders/compute/planet_sun_glow.glsl`: adds a glow (exp + 1/r² + wide tail) round the sun and four soft flare ghosts along the line through the screen centre. The sun counts only where the depth picture shows sky round its pixel (9 taps, so a hill crest cuts it off smoothly). `PlanetAtmosphere._sun_glow` creates it, sets the `Compositor` on the world environment and feeds direction, colour and strength (`glow_strength` 1.5 x light_energy/sun_strength, so clouds, eclipses and dusk dim it; 0 under water). `NO_SUN_GLOW=1` switches it off.
- Traps found: the Godot projection in the compositor callback is y-up in clip space but the image is y-down: screen y = (0.5 + ndc.y/2) * h (the picture's own pixel size is the internal render size, not the window's); a `.glsl` edit needs `godot --headless --import` to be seen (cached SPIR-V).
- Open: a graphics setting for it, anamorphic streak, bloom of other bright lights, DoF, motion blur, grain/vignette.

### Impostors: first part BUILT 2026-10-21 (yaw-only atlas for the 80-220 m tier)
- Built: `PlanetImpostors` (node in PlanetWorld) bakes every tree variant (the lighter mesh, `variant % 2`) from 8 angles round the Y axis with a small orthographic SubViewport into one 1280x160 atlas (alpha cutout, see-through texels bled natively: `PlanetImprintNative.bleed`). `planet_impostor.gdshader` turns each quad about the tree's own up axis to face the camera and blends the two nearest views (alpha scissor, `tint` 0.58 because the picture is lit once when baked and the scene lights it again, normal = up/toward-camera mix). `SpeciesRegistry` keeps `impostor(id, variant)` and a list of tile instances still showing the lighter mesh; when a variant is baked `_swap` replaces them (so tiles built before the bake still get quads). `PlanetScatter._light_trees` hangs quads for baked variants. `NO_IMPOSTORS=1` turns it all off; `IMPOSTOR_DEBUG=1` prints the bake.
- Measured (planet_lab --fps, seed 1337, green country, frame 1500): primitives 11.35 M -> 9.41 M (-17 %), GPU 16.1 -> 15.2 ms, draw calls 1799 -> 1783. The baking takes about 130 ms a variant at 60 fps (120 species: runs in the first minute).
- Open: elevation views (looking down from a hill the sides are right but the top is flat), a real octahedral atlas with normals/depth, dither crossfade at the 80 m border (a pop today), bake the 220 m+ tier too (replace the cone/ball far trees), shadows from impostors (none), a graphics setting.

### Leaves and branches: realism, first part 2026-10-21 (user wants variation, undulations, imperfections, veins, less low-poly)
- Reference photos from the user (a nightshade plant with large soft leaves, holes bitten out, dry spots, a fallen leaf with a fine net of veins and a wavy margin).
- Done: every single leaf (`add_leaf`) is now a smooth surface (`add_leaf_surface`): folded up along the midrib, rippled toward the margin, drooping tip, a little twist, all different by the leaf's dice, with smooth averaged normals; the close look adds a ring half way in. Outlines have many more points (smooth margin instead of a diamond; lobed leaves keep their lobe count; palmate outlines are rounded by Chaikin). Small plants' compound leaflets (`low_plant`) are real leaves in every look, no longer one triangle each. Leaf-cluster cards (tree canopies, shader drawn): leaves have a curved midrib, a wavy margin, uneven width, holes, dry brown edges, a fine net of small veins and a normal that rounds across the midrib and ripples along it. Cost in the green country (planet_lab --fps): primitives 9.41 M -> 10.47 M (+11 %), GPU 15.2 -> 17.7 ms (the 17.7 ms includes the dense leaflet plants).
- Viewers: `tests/manual/world/leaf_view.tscn` (`-- --shot=PATH`, `LAB_LOW=1` for the light look), `species_gallery.tscn` got `--shot=PATH`.
- Open: grass blades and flower petals are still sharp flat polygons; real leaf veins as a normal map (veins now bars); a leaf in the canopy picks its tone per leaf (yellowing, young growth); thinner twigs and trunk flare; leaf translucency tuned per species.

### Bark with parallax occlusion, first part 2026-10-21 (user reference photos: plated pine bark with orange lichen, grey cracked bark, rounded chunky plates)
- Done: `flora_wind.gdshader` bark is now a field of plates (`bark_height`: a Voronoi cell field, rounded blocks, stretched along the trunk, cracks between, per-plate height/tone, grain strands) drawn with parallax occlusion (20 steps up close, fading out by 20 m, the depth 1-4.5 cm by the trunk's radius) and a normal from the height slope; each tree gets its own plate size and length by its position (`bark_style`); grey-green and orange lichen crusts and moss on the plates. The old furrow noise (`bark_at`) is no longer used for tubes. Debug: uniform `bark_debug` 1 = height, 2 = tone/crack/height; viewer `tests/manual/world/bark_view.tscn -- --species=N --dist=M --shot=PATH --debug=K`.
- Cost: green country 61 -> 51 fps in the worst case (GPU 17.7 -> 19.6 ms) with the lab at eye height among trunks.
- Known: a horizontal seam where the grower starts a new tube (UV.y restarts: visible on trunks at a ring); colours are darker than the photos (the vertex colour is dark brown, the lichen helps); the plates look more like river pebbles than flaky bark at a few metres; branches get it too but thin ones have only 3-4 plates round.
- Open: an alternative with real displaced geometry for the 2 m nearest to the player; fix the seam natively (continue UV.y across tubes); bark types by species (smooth birch, ridged pine, scaly), set by the species not the position.
