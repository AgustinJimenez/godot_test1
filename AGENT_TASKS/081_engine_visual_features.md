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

## 2. Dust and sandstorm volumes, and sand that moves (our Niagara and heterogeneous volumes)
- What: a ray-marched dust volume (storms, haze in the desert, smoke), puffs of dust at footsteps and landings, sand blowing off
  crests in the wind, sand sliding down a slip face.
- Research: froxel volumetrics (the `volumetric_fog` of Godot and its limits), raymarched volumes with 3D noise (Horizon Zero Dawn
  clouds, Sebastian Aaltonen's talks), GPU particles with collision against a height field, sand avalanche (angle of repose) in
  cellular automata, "Journey" sand rendering (GDC 2013, Nathan and John Edwards).
- Uses the dune and ground shaders (078) and the wind from `planet_weather.gd`.

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
