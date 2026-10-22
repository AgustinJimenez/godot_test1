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

## Contact shadows and ambient occlusion (questions 2 and "ambient light"), read 2026-10-22
- Unreal's contact shadows (`ScreenSpaceShadows.usf`) are a screen-space march in the depth
  buffer from each pixel toward the light, about 60 samples over a short distance, started from
  the light's screen position, with a few "hard" samples near the surface and a fade over the last
  ones, plus a surface thickness so thin things do not cast. They add the small dark creases that
  a shadow map is too coarse to give (the foot of a plant, pebbles, bark plates).
- Godot has no screen-space contact shadow switch for the sun that I could find; it would need our
  own compute pass (like the sun glow pass). Not done; the bark cavity AO (above) covers the bark.
- Ambient occlusion: Godot's SSAO is already on at default quality (graphics setting `ssao`) with
  the engine's default radius 1 m and intensity 2. Tried tuned values in the lab:
  radius 1.6 / intensity 2.6: no visible change; radius 2 / intensity 6: plant feet and trunk
  bases darker, but the sand close-up gets grainier and darker; radius 4 / intensity 40: far too
  dark. Reverted, nothing shipped: the sand look is the user's choice and the win was small.
  Open: apply a stronger SSAO only above the forest floor (plants/trees), or per material through
  the shader's own `AO` output like the bark now does (safer than a global setting).

## Bark self shadow (open item 1), done 2026-10-22 (published idea, own code)
From the hit point of the parallax march, four steps toward the sun across the bark height: where
the bark surface stands higher than the ray, a plate is in the way. The result darkens the bark's
`cavity` (which feeds AO and the direct light share), at most to 55 %, fading with distance with
the parallax (near). Result on bark_view at 1.2 m: furrows are darker on the side away from the
sun; no errors. Cost: four more bark_height evaluations per bark pixel within about 20 m. Not
measured: GPU time in a forest view; the shadow direction is only right for the sun, not for
other lights (a lamp would need its own march); thin limbs.

## Leaf flutter about its own stem (open item 2, part 1), done 2026-10-22
Idea (from how vegetation shaders are layered: trunk sway, branch sway, then a small per-leaf
motion): a leaf should not move as a rigid block with its branch; its tip moves more than its
stem end. Our wind moved every vertex of a leaf the same. Done: for leaf geometry (UV2.y in
1.5..3.5, not bark) the vertex is pushed along its normal by two summed sines (own phase from
position), times the square of how far along the blade it is (UV.y), times the sway weight, with
amplitude 0.006 + 0.035 x wind m. Not verified: how it looks in motion (stills only; the lab is
not pixel exact, run to run 9 % of sampled pixels differ, with flutter 19 %), whether UV.y really
runs stem to tip on every leaf kind (it does on the leaf surface mesh; pinnate / cards use their
own UV and are not touched), frame cost (a few ALU in the vertex stage).
Not done yet from item 2: crown-wide ambient darkening (needs the crown's size per tree).

## Poly Haven bark study (2026-10-22): what real bark height looks like, and the procedural copy
Source: polyhaven.com (CC0, "absolute freedom", no attribution needed), API at
api.polyhaven.com (assets list, /files/<name> for direct links). Catalog: 886 textures; the bark
ones are chinese_hackberry_bark, eucalyptus_bark, fever_tree_bark, japanese_cedar_bark,
jolcham_oak_bark_01, metasequoia_bark, palm_tree_bark, tree_bark_03, trident_maple_bark. Also
useful later: forest_ground_04..06, forest_leaves_02..04, rock_* / rocks_ground_*, mud, moss
sets. Downloaded the 1k diffuse + displacement of the nine barks to the scratchpad only (not in
the repo) and measured the height maps (256 px, std dev of height, and the distance where the
autocorrelation falls below 0.5, across and along):

| bark | std | across px | along px | along/across |
| oak (jolcham) | 0.059 | 2 | 4 | 2.0 |
| maple (trident) | 0.077 | 3 | 10 | 3.3 |
| cedar (japanese) | 0.050 | 2 | 5 | 2.5 |
| metasequoia | 0.056 | 4 | >120 | very long ropes |
| eucalyptus | 0.039 | 2 | 4 | 2.0 |
| fever tree | 0.009 | 2 | 1 | almost smooth |
| hackberry | 0.033 | 4 | 5 | 1.2 |
| palm | 0.072 | 20 | 7 | 0.3 (horizontal bands) |
| tree_bark_03 (ash-like) | 0.052 | 2 | 6 | 3.0 |

What the pattern is: (1) low contrast, a soft relief, not hard tiles; (2) the features are small,
1 to 4 cm if a tile is about 1 m, with 2 to 3 times longer reach along the trunk in most barks;
(3) a few deep fissures only (hackberry, oak have them, eucalyptus and the fever tree almost none);
(4) colour is low saturation with big mottled patches (lichen, moss) and tiny speckle, darker
and warmer in the crevices. Our bark was made of Voronoi plates with hard edges: high contrast,
large blocks, square-ish: that is the "pebble / low poly" look.
Done: `bark_height` now wraps the old plates (`bark_height_cells`) and adds two layers of
anisotropic value noise (about 2 and 1 cm across, stretched along the trunk by a ratio per kind:
oak 2, maple/ash/pine 3, cedar 8, palm 0.3, birch 0.6), the second layer turned so no square
grid shows, and flattens the plates by 22 % toward mid height. Result on bark_view: oak reads as
stringy natural bark, cedar as real fibrous bark. Not verified: forest views at 10 to 30 m (the
visual check passes, the forest baseline did not change beyond its threshold), GPU cost (two
value-noise samples per height evaluation, about 27 evaluations per bark pixel within 20 m: it
replaced nothing, so it adds cost; to measure), thin branches.
Next: (a) the colour: large lichen/moss patches and a warm tint in the crevices; (b) kind-specific
fissures (oak, hackberry) as sparse deep cracks; (c) maple still has broad squared patches from
the plate layer; (d) the same study for ground: forest_ground_*, forest_leaves_*, rocks.
