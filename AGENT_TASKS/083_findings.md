# 083 findings (own words; no Unreal code copied)

Source: checkout of EpicGames/UnrealEngine, branch `release`, at `E:\repo\UnrealEngine`
(shallow clone). Read 2026-10-22.

## Parallax occlusion (question 1): the repo has no POM

- The engine source only has the simple "bump offset" parallax (one shift of the texture
  coordinate along the view). The full parallax occlusion node is a material function stored in
  binary content (`.uasset`), which is not in the repository. So nothing to read there.
- Plan: use public papers instead (parallax occlusion mapping: Tatarchuk; relief mapping with
  secant refinement; cone step mapping). Questions stay open in 083 (adaptive steps, edge
  refinement, self shadow).

## Light through leaves (question 2): two-sided foliage shading

What I read: `Engine/Shaders/Private/ShadingModels.ush` (the two-sided foliage model).
- The model lights the leaf normally from the front, then adds a separate "transmission" term for
  light that arrives from the *other side* of the leaf.
- Transmission has two parts: (1) a wrapped diffuse on the back face, i.e. the cosine of the angle
  to the back normal with a wrap of 0.5 so the glow does not die at grazing angles (and divided
  by (1 + wrap)^2 to keep energy); (2) a forward-scatter lobe that is strongest when the viewer
  looks straight toward the light through the leaf (view and light opposed) and falls off fast
  otherwise (a GGX-shaped lobe with roughness about 0.6).
- Both are multiplied by a "subsurface colour" (the leaf's own tint), so backlit leaves glow in
  their colour (yellow-green) instead of white.
Why it looks better: a canopy seen against the sun lights up like stained glass, while the same
canopy from the sun's side stays plain. Without the view-dependent lobe, the glow is the same from
every angle and reads flat.
Our state: `BACKLIGHT` in `flora_wind.gdshader` is Godot's built-in wrapped transmission, constant
in the view (0.35 x paint). It has no forward-scatter lobe.
Cost: a few ALU per leaf pixel, no texture, no extra pass.
Done (task 083 a): our own forward-scatter term from the sun direction (`cloud_sun_world`) and the
view; see the shader comment. Verified: see git log.

Tuning result (2026-10-22): at x1.1 the change against the sun was barely visible, at x8 it was
mild (leaves slightly brighter): most leaves on that view are in the shade of other canopy, so
only a few receive direct sun to pass through. Settled on 0.3 + 2.5 * lobe^4. Not verified:
a view with the sun low behind a single tree, and the frame cost (a few ALU per leaf pixel).

## Bark parallax (question 1), done 2026-10-22 from the published technique, not Unreal's code
- Steps now adapt to the view angle: 9 head-on up to 24 at grazing (was a fixed 20), and two
  halving steps after the march replace the one straight-line guess, so plate edges are sharper.
- Result on bark_view (species 0 and 2, 1.5 m and 4 m): look the same head-on, branches slightly
  crisper at the edges. Not measured: GPU time (expected a small saving head-on, a small cost at
  grazing angles), grazing views of thin limbs, self shadow of the bumps (still open).

## Specular occlusion and bark in the cracks (question 2), done 2026-10-22
What I read: `ReflectionEnvironmentShared.ush` has a small function for specular occlusion: it
takes the ambient occlusion, the angle between the view and the surface and the roughness, and
gives how much of the reflected light can really arrive; deep creases reflect little, and the
effect is stronger when looking at the surface edge-on (the reflection vector would point into
the surface wall). So a surface that is dark in its cracks also stops shining in them.
Ours: the bark shader never set an ambient occlusion, so cracks lit and shone like plate tops.
Done: `AO` = the bark's cavity (low deep in cracks, 1 on plate tops, faded to 1 beyond about
40 m) and `AO_LIGHT_AFFECT` 0.5 on bark, so the sun is also a little less strong in the cracks,
a cheap stand-in for the plates shading each other (the self shadow still open in 083).
Godot applies AO to ambient light and to reflections, which gives the specular occlusion.
Result on bark_view: cracks slightly darker, plates read as more raised. Not measured: GPU cost
(one multiply), a forest view from a distance of 10 to 30 m (the fade could be tuned).
