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

Bark colour from the Poly Haven look (2026-10-22): crevices tinted warmer and redder
(x1.28, x0.94, x0.78 times the crack depth, up to 55 %), and a trunk-wide mottling in patches
about a hand to a forearm across (0.8 to 1.2 brightness, own noise per tree). Applied on trunks
only (not thin branches). Result on bark_view (oak, 1.5 m): slightly warmer crevices, softer big
patches; no errors. Not verified: forest view and other kinds side by side with the photos.

## Poly Haven ground, litter and rock study (2026-10-22): forest_ground_04..06, forest_leaves_03/04,
## rocks_ground_01, rock_boulder_cracked, mossy_rock (1k diffuse + displacement, scratchpad only)
What the pattern is:
- Forest soil (forest_ground_05/06): almost flat, very fine speckle, rare small bright flecks and
  tiny twigs; height range tiny. Colour mean about (88,68,46): yellow-brown, blue about half of
  red. forest_ground_04 (path-like): fine gravel and flakes on brown, mean (107,90,68).
- Leaf litter (forest_leaves_03): dense overlapping small leaves, dark brown with olive, the
  height is soft and blobby with large dark pockets, no sharp edges; mean (68,53,32).
  forest_leaves_04 (needle litter): orange-brown, many thin needles and twigs in random
  directions over bare soil, mean (130,94,58).
- Gravel pavement (rocks_ground_01): angular stones of very mixed sizes (a few big, many small)
  in a dark fine matrix, mean (135,125,110). Cracked mud (rock_boulder_cracked): a network of
  thin dark cracks around slightly domed polygons, mean (187,148,112). Mossy rock: yellow-green
  lichen in blotches that follow the cracks, dark thin cracks, soft big swellings.
Compared with ours (sampled from a lab forest picture, bare soil in sun): (108,77,66): the
blue is about 60 % of red against about 50 % in the photographs, so ours is slightly pinker and
greyer; this includes the sun and sky colour of the golden grade (the user's choice), so I left
the soil colour alone.
Ideas to copy later (procedural, own code):
1. Forest floor: the ground shader's soil could take a needle layer (thin random lines, orange
   brown, strongest under conifers) and a soft leaf-litter blob layer (dark brown / olive) with
   no hard edges, instead of only fine speckle. There is already a `scan_leaf_c` litter scan.
2. Gravel: stone sizes follow a heavy-tailed distribution (a few big, many small); check our
   gravel chips' size spread (planet_scatter gravel_chunk spacing is uniform).
3. Mud / dry ground: thin dark crack network around domes (we have `cracked_red_ground`-like
   desert? check) with the crack width fading with distance.
4. Lichen on rock and bark: blotches that follow the cracks, yellow-green, not round spots.
Not done: no ground-shader code changed (the sand and the golden grade are the user's choices;
the ground shader is 1000 lines and any change has to pass the visual check).

Oak fissures (2026-10-22), from the Poly Haven oak/hackberry look (a few deep furrows, long
smoother bark between): lanes round the trunk (6 per metre, wandering with a slow noise); a lane
has a furrow for a stretch of about a metre, then none; the furrow pulls the height to the floor
(85 %) and the `crack` value to 0 so the colour and the cavity AO follow. Two first tries failed:
a contour line of value noise covers huge areas (value noise stays near 0.5) and makes a big dark
block; with a narrow threshold the contours close into ovals. Lanes avoid both. Not verified:
other oak trunks and forest view; the effect is subtle at 1.5 m.

## Cost of the study's shader changes, measured (2026-10-22, lab forest, --fps, 11:00, plants on,
## render_gpu_ms at frame 1500, noise about +-0.5 ms between runs)
- before the study (d6b0e01): 17.5 to 18.1 ms, 55 fps.
- after parallax steps + cavity AO + self shadow (c696895): 19.1 ms.
- after leaf flutter + fine bark relief (815bf78): 21.4 ms (+2.8). The flutter alone was about
  1.5 ms (vertex stage on 11 M primitives; a cheaper version with a 35 m cut still cost 0.9 ms);
  its tip motion is only a few millimetres, so it was REMOVED. The bark march steps now use a
  lighter height (`bark_height_march`: plates plus one noise layer, no furrows).
- the march ran all its steps even beyond the fade range, where the offset is zero: now one step
  there (`near < 0.02`). Result: 16.4 to 17.3 ms, 58 to 59 fps: faster than before the study,
  with all the bark improvements kept.
Lesson: every per-pixel loop needs a distance gate; check `--fps` after each shader change.
Leaf flutter: dropped, the idea is documented above in case a cheaper way appears (e.g. in the
leaf mesh's baked vertex colour, no per-vertex trig).

Full regression run (2026-10-22, after a9bc782: bark parallax/AO/self shadow/relief/colour/fissures,
cedar, light through leaves, plants loaded to 6 km, more plant workers): the whole
`scripts/planet_check.sh` (not --quick) passes, including walk (413 m), swim and fly (18 km).
Note: the script needs LOG_DIR to exist (`mkdir -p`).

## Crown interior shading (open item 2, part 2), done 2026-10-22, native (plant_mesh_native.cpp `leaf`)
Idea: the inside of a crown gets little light (leaves above and around block it); a sky/sun lit
outer skin against a darker interior is what makes a canopy read as a volume. Done where the
leaves are made, so it is free at render time (baked into the leaf colour): for trees with a
crown wider than 1.5 m, a leaf's colour is darkened by up to 45 % near the trunk axis (distance
from the axis over the crown radius, smoothstep 0.2 to 0.9) and up to 20 % low down the tree.
Result: lab forest view and the visual-check forest view show deeper crowns, not harsh.
Not verified: other species and sizes (the formula uses the tree's own crown radius and height
but the leaf position is assumed to be in tree space with the trunk at x=z=0), winter / bare trees,
and a night view. Baseline for green_country accepted.

Crown shading check on other species (2026-10-22, species_gallery page 1, low-poly mode):
spruces, oaks, birch and palms all render with normal leaf colours, none turned dark or
uneven. Bare trees skip the shading (the leaf function returns before it). Still not looked at:
the realistic (D) mode of the gallery, other seeds, and a night view.

## Impostors seen from above (open item 3, part 1), done 2026-10-22 (planet_impostor.gdshader)
The billboard turned only about the tree's up axis, so from the air a tree card was an edge-on
strip. Now the quad's top leans toward the eye as the eye rises above the tree (elevation 26 to
72 degrees, up to 85 % lean), so the side picture always faces the viewer. Seen at 110 m altitude
looking 22 degrees down: the thin strips in the 80 to 220 m ring now fill out. At 250 m the
trees on screen are the cheap horizon meshes, not impostors, so that view cannot show it.
Cost: nothing measured (a few ALU in the vertex stage on far trees only). Not done: pictures
actually taken from above (true elevation views in the atlas), the dither cross-fade at 80 m, a
220 m+ tier, shadows. Not verified in motion or at 60 degrees looking down.

## Sky atmosphere (open item 4, read 2026-10-22): `Engine/Shaders/Private/SkyAtmosphere.usf` and
## `SkyAtmosphereCommon.ush` compared with our `shaders/world/planet_sky.gdshader`
How Unreal builds it (own words): three layers of density (air molecules, haze, and an ozone layer
that only absorbs), all as exponential or tent profiles of height; the expensive integrals are
done once into small look-up tables and then read by every pixel: (1) a transmittance table (how
much sun light reaches a point at a given height and sun angle), (2) a multiple-scattering table
(the light that bounced more than once, which keeps shadowed air and twilight from going black),
(3) a sky-view table (the whole sky around the camera as a latitude/longitude picture with extra
rows near the horizon, where a sunset changes fastest), and (4) a camera volume (a 3D texture of
in-scattering and transmittance by depth in front of the camera) that is applied to every opaque
surface and translucent thing, so distant mountains and trees take the sky's colour and fade
exactly as the sky behind them does.
Ours: one pixel does the whole march (14 steps crowded toward the eye, a 5-step light march at
each), single scattering with the three layers including ozone (a blue horizon, pink sunset), a
Mie lobe, ground and planet shadow. Good model; costs per sky pixel.
Differences that matter for the look:
1. No multiple scattering: the sky next to the sun's shadow and at deep twilight is darker and
   less colourful than real air. A cheap copy (own formula): add an isotropic term of the
   single-scatter energy times a factor of about 0.3 to 0.6 (the geometric series of bounces).
2. Aerial perspective: our ground, trees and clouds are faded by a separate exponential fog
   (planet_atmosphere `fog_*`), not by the same integral as the sky, so a far mountain's colour
   and the sky behind it can disagree (the usual hint: a visible band at the horizon).
   Copy: sample the same single-scatter function once per pixel for the fog colour, or bake it
   into a small table by height and sun angle and have the fog read it.
3. Cost: tables mean the sky costs a fixed small amount; ours depends on the screen share of sky.
Not changed: the golden sun and sky grade is the user's choice, so no code here. Next candidate if
asked: (1) as a uniform `multi_scatter` default 0 so it can be tried live; (2) a fog colour from
the sky's own function.

Multiple scattering option (2026-10-22, planet_sky.gdshader): uniform `multi_scatter`, default 0
(the current look is unchanged). With 1: the single-scatter energy sent every way, half of it,
added to the sky. Seen at 18:36, looking east and 25 degrees up from 2 m: the sky is brighter and
paler, the warm tint near the sun fades; at 12:00 almost the same. Set it on the sky material
(`material.set_shader_parameter(&"multi_scatter", 0.3)` in planet_atmosphere.gd) to try a value;
not wired to a setting or the debug menu. Not verified: deep twilight (the case it is for), the
ground and clouds under it (they use their own lighting), cost (a few ALU per sky pixel).

## Two corrections to the earlier notes (2026-10-22)
- Gravel size spread (Poly Haven idea 2): already heavy-tailed in `gravel_chunk` (radius from the
  dice cubed: many small, few large, capped at 5 cm on purpose). Nothing to do.
- Fog colour (sky study gap 2): `planet_atmosphere._apply` already takes the fog colour from the
  same sky function (PlanetAir.sky_color toward and away from the sun, a warm / cool split with
  fog_sun_scatter, dust and overcast tints). The remaining difference is only that the fog is one
  colour per frame, not per view direction and depth as Unreal's camera volume; small.

## Dithered cross-fade between tree versions (open item 3, part 2), done 2026-10-22
planet_scatter.gd: the near tree (to 80 m), the lighter tree (80 to 220 m) and the far tree
(beyond) now overlap by TREE_FADE (6 m; 12 m at the far switch) with Godot's visibility-range
fade (dither), so a tree no longer jumps from one version to the next. Cost measured: GPU
16.9 -> 17.65 ms (+0.7 ms, about 4 %: the fade variant of the plant shader). Seen in a still
view: no visible dither band. Not verified in motion (the pop itself), at night, and with
shadows (the lighter version casts none).

Silver Oak in species_gallery (seed 1337) looked far bigger than its neighbours: not a bug. The
species generator has an "ancient live oak" archetype (the Angel Oak: huge short trunk, limbs as
thick as small trees, tree_archetypes.gd / species_generator.gd), and that species drew it.

Triangle groups of the lab forest view at frame 1000 (mesh totals, not what is in view): plants
1.17 M (314 nodes), trees 4k+ tris 1.0 M (63), trees 2k+ 0.76 M (69), PlantsOf 0.54 M, trees 5k+
0.17 M, trees 3k+ 0.08 M. Trees and plants are where the triangles are; a real saving needs a
per-distance count of what is drawn (not yet done): next performance step is to log triangles
by distance band (0 to 20, 20 to 80, 80 to 220 m) before cutting anything.

## Near trees in cells (performance), done 2026-10-22 (planet_scatter.gd `_hang`, native `split_cells`)
Finding: a visibility range is tested on a whole node. A tile's near trees were one MultiMesh, so
while any part of a 128 m tile was within 80 m, every tree of the tile was drawn in full detail,
also those 100 m or more away (the lab count showed about a third of the near-tree triangles
belonged to trees beyond the near range). Fix: the near trees of a tile are split into cells of
40 m (`TREE_CELL`; native `PlanetScatterNative.split_cells`, a GDScript version hung the load),
each cell its own MultiMesh with its own range (and its own light version). Godot evidently tests
the range at the node's bounds, since the cost fell.
Measured (lab forest, --fps, frame 1500): GPU 17.65 -> 15.2 ms, fps 57 -> 62, primitives 11.15 M
-> 10.11 M, draw calls 1763 -> 2028 (more nodes). Full planet_check and visual check pass (sway and
fly included). Not measured: other biomes, CPU time of the cell split per tile (native, small),
hitches while flying (no new ones in the checks). Next: the same idea for plants (`SMALL_VISIBLE`
batches) and for rocks; try 32 and 64 m cells; the lab prints NEAR_TREES (rough, node bounds).
