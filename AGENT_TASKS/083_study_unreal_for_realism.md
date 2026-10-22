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
