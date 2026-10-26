# 094 - Quality of the individual leaf

Started 2026-10-26. User: "let's focus on the plant leaves, can we increase the quality of the individual leaf? must we make a lab viewer?"

## Lab (done)
`tests/manual/world/leaf_lab.tscn` (windowed, `--screen 1 --windowed`; orbit with the mouse, Left/Right species, Up/Down variant, 1 mesh leaf / 2 card / 3 crown,
W wire, D low/realistic, A autumn, B backlight, L sun, T top view, R seed, P picture). Command line: `--species=N --mode=1|2|3 --shot=PATH --all=DIR` (one picture per species).

## What the lab shows (first look, seed 1337)
- Mesh leaf (`PlantLeafShapes.add_leaf`, a triangle fan around one point with veins painted by the shader): a LOBED species is a faceted star, the lobes are flat spikes
  (3 lobes = 7 outline points a side), no curved edge, the fold at the midrib is a hard crease, the veins are straight streaks that do not follow the blade.
- Card leaf (`add_leaf_card` + `leaf_cluster` in `flora_wind.gdshader`): the leaf IS a nice smooth veined silhouette, but (1) every species gets the same pointed-oval leaf
  (the card ignores the species' shape / aspect / lobes / edge), (2) dotted ghost fragments along some edges (alpha cut leftovers), (3) a round white hole in some leaves
  (a bite? it reads as a bug), (4) no translucency to see in the lab without the sun behind.
- The planet uses cards in the realistic look at a distance and mesh leaves for small plants / near.

## Plan
1. Mesh leaf: a smooth outline (spline through the key points, 12-20 a side, lobes rounded with a notch curve), a midrib fold that curves, subdivision across so the blade
   bends (cup along the vein pairs), tip and base shapes per species, serrations as real small teeth.
2. Card leaf: pick the leaf shape from the species (pass shape / aspect / lobes / edge to the shader through the card's UV2 / vertex colour), remove the dither ghosts and holes.
3. Shader: vein relief on the normal, translucency (backlight) tinted yellow-green, a wax specular on the upper side, darker underside, edge browning.
4. Check in the lab (all species, front / top / backlit), then in the planet at 2 m and 10 m.

## Log
- Step 1 done (mesh leaf, realistic look only; the low-poly look keeps the old fan): `PlantLeafShapes._add_leaf_smooth` builds the blade as rings from the midrib to the rim (grid lines
  follow the veins, a rim point joins the midrib lower down), the outline goes through a Catmull-Rom spline (`smooth_outline`; lobed / toothed edges keep more of their corners), the blade
  cups and ripples. Dense outlines: ovals are sampled at 11 points a side (the width curve is the shape), toothed +6, lobed leaves come from `_lobed_dense` (rounded lobes swept forward, notches).
  Lab check: all 17 species of seed 1337 in the top view read as leaves (oak lobes, toothed, smooth ovals). Cost: ~120-250 triangles a leaf instead of ~14, so only where `MeshBuilder.detailed`.
- SPOM / parallax for veins: not needed. A leaf is a thin blade seen from a few cm to many m; the veins are shallow (< 1 mm), so a normal-map / bump from the veins in the shader gives the
  same look for no extra cost, and POM breaks at the grazing angles a leaf is seen from and at the silhouette (the silhouette is the geometry's job, and now is).
- Left in the lab: every oval species is the same oval (the species differ in aspect only), the vein stripes are the same straight bars on every leaf (shader), the cards ignore the species'
  leaf shape, the ghost dots and holes on cards.
- ROOT CAUSE of the ghost dots on leaf cards found (found with the lab, debug-painting cluster.x): the card's dice (UV2.x) is the same number on all corners, but its interpolation differs
  in the last bits from pixel to pixel, and `leaf_cluster` feeds it to chaotic hashes (`hash22(c + id * 13.7)`), so every pixel drew its own random leaves around the real ones. FIX: snap the
  dice to a 1/4096 grid in the fragment shader (cards, pinnate, grass, and the mesh leaf's two numbers). The same noise probably made the veins of mesh leaves shimmer. Lab: `--noshadow --nosun --distance=D`.
- Cards use the species' leaf now: `PlantLeafShapes.card_look(shape, aspect, lobes, edge)` packs them into one number (UV2.y of a card = 2 + it, 0 = no species = the old generic leaf), the shader's
  `leaf_cluster` / `leaf_profile` read it back (the same width curves as the mesh outline, lobes, saw teeth or waves on the edge, the aspect sets the width). Holes are rarer (10%) and ragged.
- Fine veins of a card are the borders of a jittered cell field (areoles, `vein_net`), not a sine grid. Leaves (cards and mesh leaves with UV) got a waxy sheen (roughness 0.5, specular 0.3),
  a yellower transmitted light (BACKLIGHT tinted), and a duller paler underside. The lab sets `cloud_sun_world` so the backlight lobe shows, and gives the leaf a sway alpha (the glow needs it).
- Still to do: curved side veins and the leaf's vein relief in the normal, the mesh-leaf shading to match the card's, a look at it all on the planet at 2 m / 10 m, a dotted midrib seen in the card close-up.
