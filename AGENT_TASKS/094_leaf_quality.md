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
