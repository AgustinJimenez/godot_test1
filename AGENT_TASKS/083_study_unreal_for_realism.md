# 083 Study the Unreal Engine source for realism ideas (POM, lighting, materials)

Status: written 2026-10-22, while the clone of `E:\repo\UnrealEngine` was still running (only `.git`
there, no files yet). Nothing below has been read in the source yet: the "where to look" paths are
from memory and must be checked against the checkout.

## Rules for this study (Epic's EULA, from the page www.unrealengine.com/ue-on-github)

- Studying and learning is allowed, copying code is not. Any Unreal code in our product puts the
  whole product under the Unreal EULA (5 % royalty above $1 M lifetime revenue).
- So: read, understand, write the idea down in our own words, then write our own code from scratch
  in our GLSL / Godot shaders / native C++. No pasting, no line-by-line transcription, no copied
  constants tables or long formulas kept verbatim.
- Do not paste Unreal code into this repo, the task notes, commits or public places (forum
  snippets are limited to 30 lines and only to discuss them). Notes name files and describe ideas.
- No Unreal code that is combined with GPL / LGPL / CC-BY-SA code (not relevant to us today).

## What we want to learn (questions, in priority order)

1. Parallax occlusion on trunks, branches, rocks, ground (our `bark_height()` + 20-step POM in
   `shaders/world/flora_wind.gdshader`):
   - how the step count adapts to view angle and distance (we use a fixed 20 and a 20 m fade);
   - how they refine after the coarse march (secant / relaxed cone / binary search) so the plate
     edges are not stair-stepped;
   - self-shadowing of the height (a second short march toward the light) and its cost;
   - how silhouettes are handled (POM fakes depth inside the polygon only): is there a pixel-depth
     offset, and what do they do on cylinders (tree trunks) where the edge shows the lie;
   - how the transition between POM, plain normal map, and flat colour is blended with distance;
   - whether a displacement map and tessellation / Nanite displacement is the better long term path
     for near trunks (we cannot use Nanite, but the idea of real geometry at a few metres might
     map to a native-built mesh).
2. Lighting realism:
   - sky light and ambient: how they separate direct sun, sky dome and bounce; our look is flat in
     the shade;
   - shadows: cascades, distance fade, contact shadows (screen-space short rays), what a tree
     canopy needs (leaves lit from behind);
   - subsurface / two-sided foliage (light through leaves): how thin translucency is faked; this is
     the biggest missing realism in our canopies;
   - specular occlusion, horizon occlusion on rough bumpy surfaces (bark in the shade must not
     shine);
   - exposure / eye adaptation and tone mapping curve (we have a post stack plan in 081).
3. Materials:
   - how vegetation shaders pack per-instance variation (colour, wetness, age) cheaply;
   - bark / rock layering: height-based blending of moss, lichen, dirt, snow (we do some by hand);
   - how normals are re-oriented on leaf cards so a card does not look like a flat quad.
4. Atmosphere and distance:
   - aerial perspective / height fog model and how it ties to the sun colour;
   - volumetric cloud and fog shadows (079 has our list).
5. Foliage at a distance (ties to the impostor work in 081): how they build billboards and when
   they cross-fade from real mesh to impostor; how they avoid popping.

## Where to look (paths from memory, verify after the clone finishes)

- `Engine/Shaders/Private/` : `ParallaxOcclusionMapping*`-like helpers are usually inside the
  material expression code in `Engine/Source/Runtime/Engine/Private/Materials/` (HLSL translator);
  search the tree for "ParallaxOcclusionMapping", "POM", "BumpOffset", "SubsurfaceProfile",
  "TwoSided", "ContactShadow", "SkyAtmosphere", "HeightFog", "VirtualShadowMap".
- Lighting passes: `DeferredLightingCommon.ush`, `ShadingModels.ush`, `Lumen/` (global
  illumination ideas only), `ScreenSpaceRayCast.ush`, `ContactShadows.usf`.
- Vegetation: speed tree and "PixelProgrammableMaterial", foliage shading model
  (`SHADINGMODELID_TWOSIDED_FOLIAGE`), `Engine/Plugins/Experimental/` for procedural vegetation.
- Search with grep / codegraph over the checkout, read the few files that matter, write notes.

## How to do it (when the clone is done and the machine is free)

1. Wait for the clone to finish (do not start heavy work while the user is using CPU/RAM: grep and
   reading are fine, indexing the whole tree is not).
2. For each question above: find the file, read it, then write 5 to 10 lines into
   `AGENT_TASKS/083_findings.md` in our own words: the idea, why it looks better, the cost, and how
   it would fit our shader. No code blocks from Unreal.
3. Turn findings into small tasks for us, smallest and most visible first, each verified with
   `tests/manual/world/bark_view.tscn`, `leaf_view.tscn`, `rock_view.tscn` and
   `scripts/visual_check.sh`:
   a. adaptive POM steps + a refine step on the plate edges (bark_view close shots);
   b. POM self-shadow, cheap version;
   c. fake light through leaves (backlit canopy) in `flora_wind.gdshader`;
   d. bark specular / horizon occlusion so shaded bark does not shine;
   e. contact shadows if Godot has a switch for it, else a small compute pass.
4. Record before/after pictures in `E:/Temp/claude/ground_eval/` and the frame cost (GPU ms from
   `--fps`) next to each change.

## Not done yet

Everything: no source read, no findings, no code. This file is the plan only.

## More things to study (added 2026-10-22), grouped by what they would give us

Same rules: read, note in our own words, rewrite from scratch. Paths from memory, to verify.

### Terrain and ground (our crust, tiles, ground plates)
- Landscape material layer blending: height-based blending (the layer with the taller bumps wins
  at the border, so grass sits between pebbles instead of a soft mix) and how many layers are
  sampled per pixel. Ours blends by weight only.
- Runtime virtual textures: baking ground colour/normal into a cache so far ground costs one
  sample (our "BAKE_UP_TO" plates are the same idea: compare cache sizing and refresh).
- Procedural Content Generation (PCG) framework and the older Procedural Foliage Tool: how they
  spawn by density, slope, height and *competition between species* (seeds, shade, ages). Ours is
  the native scatter; compare the ecology model and the clustering (plants grow in groups).
- Landscape grass types: grass spawned from the layer under the camera only, culled by distance and
  how the density is faded with distance (compare with our turf chunks, 26/36 m).

### World streaming and big worlds (our floating origin, tile pop-in)
- Large World Coordinates: how they keep precision far from the origin (ours: `PlanetFrame`
  rebase). Look for ideas that remove rebase hitches.
- World Partition / HLOD: streaming cells, hierarchical LODs for far cells, the loading budget per
  frame. Directly relevant to tree pop-in and the 6 km plant range (task: smoother arrival).
- Instanced static mesh culling: hierarchical instance culling, per-instance LOD, "start/end cull
  distance" with random offset so instances do not vanish in a visible ring; dithered LOD fade.

### Vegetation motion and detail
- Wind in vegetation: how trunk, branch and leaf wind are layered (pivot-based vertex animation
  stores each leaf's pivot so a leaf flutters about its own stem, not the tree). Ours uses a single
  vertex-colour weight; study the pivot idea for leaves.
- Foliage normal fixing: flattened or spherical normals on a canopy so a tree shades as one volume
  not as many cards (we noticed cards look flat).
- Impostors: octahedral impostor atlas (views over the whole sphere, not only a ring), depth stored
  for correct parallax and shadowing. Ours is an 8-view yaw ring: elevation views are the open
  item in 081.

### Sky, atmosphere, light
- Sky atmosphere (the single-scattering LUT model): transmittance, multi-scattering and sky-view
  lookup tables, aerial perspective volume. Compare with our atmosphere and the sun glow pass.
- Volumetric clouds and their shadows on the ground; cloud layer lighting (silver lining, dark
  base) for task 079.
- Exponential height fog with a second layer and the inscattering colour from the sun.
- Auto exposure (histogram) and the tone mapper's filmic curve: why the same scene looks richer.

### Water
- The Water plugin and single-layer water shading: refraction from the opaque scene, depth-based
  absorption colour, shore foam, wave normals from several scrolling layers or Gerstner waves.
  Ours is the open "water" item in 081.

### Effects and ground interaction
- Niagara-style GPU particles for dust, sandstorm, leaves, rain splashes; collision against the
  depth buffer (cheap) and lit particles.
- Deferred decals and how footprints / impacts are projected (compare with our native imprint).
- Snow / sand deformation using a render target under the character (compare with our dents).

### Post and image quality
- Bloom (convolution vs. dual filter), depth of field (circle of confusion, bokeh), per-object
  motion blur, TAA vs. TSR upscaling, film grain, vignette: our 081 post stack list. Look for the
  cheap, good-looking versions.

### Characters (for later, the user has foot IK work)
- Skin subsurface scattering (screen-space profile) and eye shading; hair card shading.
- Control Rig / foot placement IK: how the pelvis offset and foot rotation to the slope are solved
  (compare with our foot IK v2; only reading, our version is the reference we keep).
- Physics-based ragdoll blending (not now).

### Engineering practice
- Shader permutation / quality switches: how a feature falls back on low settings (we have
  quality levels for the sun glow and shadows).
- GPU profiling markers and stat commands: how they split a frame so a cost has a name (we only
  have `--fps`).

## Suggested order for the next reading sessions

1. Vegetation: pivot wind, foliage normals, impostors (biggest visible gain for forest scenes).
2. Streaming and instance culling (fixes pop-in, which the user reported).
3. Sky atmosphere and fog (079).
4. Water (081).
5. Post stack (081), then particles for dust.
