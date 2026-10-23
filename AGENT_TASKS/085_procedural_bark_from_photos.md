# 085 A procedural bark that matches the photographs (replace the bark images with code)

User's goal (2026-10-22): analyse the Poly Haven bark maps and replicate them as procedural code in
the shader, so the image files (`assets/textures/bark/bark_atlas.png`, 15.7 MB) can go. The photos
stay as the reference to compare against (`bark_view.tscn`, F6 in the editor, shows the photo bark
left and the procedural bark right: `--compare`; `--kind=N` picks the bark).

## Step 1 done: measuring (tools/bark/analyze_flakes.py, run with E:\anaconda3\python.exe: numpy,
## scipy, cv2 work there; scikit-image is broken)
Flakes cut out of the height map (local threshold + watershed), numbers on the real bark:
| bark | tile m | flakes per m2 | median area cm2 (p10 / p90) | median length x width cm | aspect | share running up the trunk | height sd |
| willow (oak) | 2.15 | 498 | 8.8 (2.0 / 44) | 6.1 x 2.3 | 2.6 | 93 % | 0.097 |
| pine | 2.0 | 261 | 22.9 (2.7 / 85) | 8.6 x 4.2 | 1.9 | 80 % | 0.067 |
| tree_bark_03 (ash) | 1.0 | 2434 | 1.8 (0.4 / 9.2) | 2.7 x 1.1 | 2.5 | 92 % | 0.128 |
Reading: the size spread is heavy-tailed (p90 about 20 times p10): a few big flakes, many small ones.
Flakes cover 87 to 92 % of the surface, leave thin low gaps, are 2 to 2.6 times longer than wide
and nearly vertical. These are the numbers the generator must reproduce, with the look of the edges
(overlap like roof tiles) judged by eye against the photo.

## What exists (searched 2026-10-22)
- Lefebvre and Neyret, "Synthesizing Bark" (Eurographics Workshop on Rendering 2002,
  evasion.inrialpes.fr/Publications/2002/LN02): fractures on circular strips that spread to their
  neighbours; makes geometry or texture; the model to copy in spirit (the cracks come from strips
  that tear and widen, so plates are separated by cracks that follow the trunk).
- Kratt et al., Computer Graphics Forum 2015 (cs.purdue.edu/homes/bbenes/papers/Kratt15CGF.pdf):
  bark cracking driven by the growth of the trunk (the stress decides the crack pattern).
- Pixar, "A Procedural Approach for Stylized Bark Shading" (SIGGRAPH 2023): Houdini tools, not
  available as code.
- MATch (SIGGRAPH Asia 2020) and DiffMat (github.com/mit-gfx/diffmat, PyTorch): fit the
  parameters of a procedural material graph to a photo by gradient descent. It works on Substance
  graphs (.sbs), which we do not have, but the idea fits: write our generator as a differentiable
  or cheap-to-evaluate function and fit its parameters to the photo statistics.
- Material Maker (MIT, built on Godot, exports shaders): a place to prototype node graphs, no
  bark graph found.
- No ready open-source GLSL bark shader was found.

## Plan
2. A generator in numpy first (fast to fit): strips along the trunk, a fracture field that tears
   them into overlapping pointed flakes (a shingled height: each flake higher at its lower end),
   a heavy-tailed size mix, thin low gaps, edge softness, fine noise on top, a colour ramp taken
   from the photo by height plus slow mottling. Parameters per bark type.
3. Fit: random search / CMA-ES on the parameters against the numbers above and the height
   histogram, the radial and angular spectrum, and the colour statistics; keep the best.
4. Port the same function to the shader (GLSL, hash-based, cheap: this runs in the parallax march
   about thirty times a pixel, so it must cost no more than the texture read it replaces; budget:
   GPU of the forest walk not above 15 ms) and compare with the photo with `bark_view --compare`.
5. Decide: replace the atlas for the bark kinds that match, keep the photo where it does not. The
   rock atlas is the same story afterwards.
Risks: the real flake overlap (shingles) is hard to get from a 2D noise; the parallax march calls the
height 20 to 30 times a pixel, so a heavy generator may cost more than the texture. A cheap
alternative to keep in mind: bake the procedural result into a small tile at load time
(one-time compute on the GPU) and sample that: no repeat visible if the tile is made per tree.

## Progress 2026-10-22 (evening): the generator and the fast fit
Files: `tools/bark/procedural_bark.py` (numpy generator, measurements, loss), `tools/bark/bark_fast.py`
(the same maths in numba: 20 times faster, identical output, and a fit on all 6 cores), `analyze_flakes.py`.
Python is `E:\anaconda3\python.exe` (numpy, scipy, cv2, numba, torch+CUDA all there).
Speed: one picture 0.5 s (numpy) -> 0.025 s (numba); a fit of 3 barks x 1200 tries 20 min -> 2.7 min.
Generator design (v3): flakes are pointed lenses (width, length, tip sharpness, soft rim) on a jittered
grid with 3 x 5 cells asked per pixel, each with its own size (heavy tail), turn and height; the
highest wins (the shingle), ragged edges, a slow warp, fine noise. 19 parameters per bark.
What the pictures say (gen vs photo, `scratchpad/ph/gen_vs_photo5.png`): the structure is right
(overlapping flakes pointing along the trunk) but the match is partial:
- willow: our flakes are too regular and lens-shaped; the photo has irregular blocky and splintered flakes.
- pine: ours are tall spikes; the photo has broad, rounded-rectangular scales with dark gaps between.
- ash: ours is wavy and stringy; the photo is rows of short ridges with deep grooves.
Lessons: fitting only statistics (size, aspect, spread) lets the optimiser cheat with shapes that
score well and look wrong; the loss needs shape terms (edge sharpness, flat share, the gap network),
and the flake SHAPE has to vary per bark (a blockiness parameter between lens and rectangle).
Next: (1) a blockiness / corner parameter and per-bark shape families; (2) a gap network (dark
cracks) as its own term in the loss; (3) compare renders of the generator at the same scale as the
photo in the game viewer, not only the height picture: the colour matters as much; (4) the colour
(a ramp by height and a slow mottling, fitted per bark) before porting to GLSL.
Honest status: not yet good enough to replace the photographs; the photo bark stays in the game.

## Round 2 (2026-10-22): a `block` parameter (lens 0 .. rectangle 1)
Pine now gets broad blocky scales with rough edges, much closer to its photo (loss 1.6). Willow and
ash still come out as long wavy "flames" (loss 2.4 and 2.7): the slow warp and the long thin flakes
the search likes bend them; the photos have short straight splintered flakes in rows with dark
grooves. The random search keeps finding statistics-matching shapes that look wrong, so the next step
is not more search but a better model for those two: (a) grooves as a separate line network along the
trunk (long dark cracks, flakes between them), (b) flakes cut by short transverse breaks (the photos'
horizontal splits), (c) warp limited to 1 cm, (d) a loss term on the gap network (share and length of
dark lines). Pine is the candidate to port first.

## Round 3 (2026-10-22): grooves and transverse splits added to the generator
Seven new parameters (groove spacing/width/cover, split spacing/width/cover, cut depth); warp limited
to 1.2 cm. Fit losses: willow 1.20, pine 1.12, ash 2.23 (before 2.4 / 1.6 / 2.7). Pictures
(`gen_vs_photo7.png`): pine has broad scales cut by faint grooves and splits, willow is still a field
of pointed lenses with hairline cuts, ash is a mass of small spikes. The cuts came out as thin
hairlines because the loss never asks for them (the statistics do not see lines), so the optimiser
picks small depths. Three rounds in, the generator reproduces the numbers but not the look of the
willow and ash photos; pine is the closest.
Honest assessment: the remaining gap is the part that makes the photograph convincing (broken,
irregular edges, flakes that lift away, shadowed gaps), which a hand-built noise model will keep
missing. Options: (A) keep the photographs (the user likes them) and use the generator only where a
photo is missing or to add variety (thin branches, far trees, birch, bark that must not repeat), no
atlas replacement; (B) keep going: a loss on the dark-line network, a learned model (DiffMat-style
fit with torch+CUDA on a differentiable version of the generator) and a style loss on a neural
feature of the photo; likely days, uncertain; (C) bake the generator into a tile at load time and
blend it with the photo to break repeats. Recommendation: A + C.

## Round 4 (2026-10-22): the smarter fit (neural style loss + CMA-ES), `tools/bark/bark_perceptual.py`
The loss is the Gram matrices of VGG19 features (relu1_1 .. relu5_1, weights from torchvision, cached in
E:\repo\ai_models\torch\hub) of the generated height picture against crops of the photo's height map, plus
a cheap size term (autocorrelation lengths across and along, FFT) because Gram matrices barely see
scale. The search is CMA-ES (`pip install cma` in the anaconda python), 20 candidates a generation,
pictures from the numba renderer, the network on the GPU (CUDA): 0.5 s a generation, 220 generations
(2 to 4 minutes) a bark. Fitted parameters are saved in `tools/bark/fits/<bark>.json` (round 4).
Result (`gen_vs_photo9.png`): clearly better than the statistics fit: ragged, splintered edges, dark
crevices, rows of ridges (ash) and tall splintered flakes (willow); the size now follows the photo.
Still wrong: pine reads as overlapping serrated LEAVES (the ragged-edge noise is too regular and
the flakes are lenses); willow flakes are too uniformly pointed; the colour is not done; nothing is in
the shader yet. Next: lower the ragged-edge frequency range, add a flake shape that is cut square at
the top (pine, willow), colour from the photo by height, then port ash first (it is the closest) to
GLSL (`flake_height`) and compare with `bark_view --compare`.

## Round 5 (2026-10-22): the generator runs in the game's own renderer (a bake at load time)
- `shaders/world/bark_bake.gdshader`: the flake model in GLSL, tiling (every scale is a whole number of
  repeats in the tile, cell hashes wrapped), plus a colour model from the photo: the mean colour, a ramp
  by height, the brightness following the cavity (how far a point sits below its surroundings), a slow
  mottling, a tone per flake, dark gaps. Draws colour in rgb and height in alpha: the atlas layout.
- `systems/world_gen/bark_baker.gd`: `await bake(name)` draws one tile (1024 px) in a SubViewport once:
  5 to 20 ms on the GPU for each bark (the first one pays the shader compile, about 350 ms).
- `systems/world_gen/bark_fits.gd` (generated, do not edit) from `tools/bark/export_fit.py`: the fitted
  numbers per bark. `tests/manual/world/bark_bake_view.tscn -- --out=DIR` saves the baked tiles.
- Result next to the photos (`baked_colour_vs_photo.png`): willow reads as willow bark in colour and
  flake character; ash is right but too contrasty; pine still reads as leaves.
- So the procedural bark can replace the 15 MB atlas at load time with no repetition problem (the seed
  gives each tree its own tile if wanted). NOT wired into flora_wind.gdshader yet: the atlas is
  still what the game draws. Next: pine fix, ash contrast, then feed the baked tiles to the existing
  `bark_photo` array instead of the png, compare in `bark_view --compare` and in the forest.

## Round 6 (2026-10-22): the procedural willow bark is in the game
`PlanetWorld._bake_the_bark()` bakes the fitted bark at load and sets it as `bark_photo` (the oak slot
only: `BarkBaker.make_array()` keeps the photographed atlas in the other five slots). Env
`PLANET_PHOTO_BARK=1` keeps the photographs for oak too. `bark_view.tscn --compare` now shows the
photographs (left) against the baked procedural bark (right). Judged side by side in the viewer:
- oak (willow): the right looks like the left, same flake character and colour; kept in the game.
- pine: leaves, not bark: NOT in the game.
- ash: too rough and stringy, and a visible horizontal seam where the tile repeats along the trunk
  (the tile is 1 m high; a mismatch there, to find: probably the mip/lod at the tile edge): NOT in the game.
Forest lab view with the baked oak: fps 67 to 68, gpu 14.2 to 15.3 ms (no change). planet_check
(full) and the visual check pass. The atlas PNG is still needed for the other five slots.
Next: the ash seam; a pine model (square-topped scales, no serrated edge); fits for maple, palm and cedar
(`export_fit.py` takes any number of barks); then the atlas can be deleted.

## Pipeline improvements to look at before fitting the other barks (2026-10-22)
The angled close-up (`bark_view --rise=1.6 --compare`) holds up: trunk and branches of the baked oak look as
good as the photograph from above and from the side. Ideas to make the PIPELINE better, in the order I would try:
1. A texture style loss in TWO resolutions plus an edge/gradient loss (steps in height) so the sharp splintered
   edges of real flakes are asked for, not only the Gram statistics.
2. A second photo of the same bark as a held-out check: fit on one crop, judge the loss on another, so we know
   the fit generalises and the generator is not copying one patch.
3. Fit the COLOUR with the same neural loss (RGB picture against the photo) instead of the hand model
   (mean, ramp, cavity, mottle): the moss, lichen and flake tone patterns the photo has are missing.
4. A normal-map / height loss through the actual shader: bake, light it from two angles in the game's
   renderer and compare with the photo lit the same way (the look under light is what matters).
5. A differentiable generator in torch (soft floors, the hashes fixed): gradient descent from the CMA result
   would polish the last 20 % in seconds; CMA stays for the discrete shape choices.
6. Per-species families: one generator with a species vector (aspect, scale, blockiness, groove) interpolated
   between fitted barks, so a new tree species is a point between barks, not a new fit.
7. Automate: one command `fit_bark.py <polyhaven name> <tile m>` that downloads, measures, fits, writes the
   fit, and renders the comparison sheet.

## Round 7 (2026-10-22): `tools/bark/fit_bark.py` (improvement 7) and what the maple showed
`python fit_bark.py <polyhaven name> [generations] [folder]` downloads the 1k maps and the real size
(Poly Haven refuses Python's default user agent: a header is set), fits (CMA-ES, neural loss, 3 cores
by default via limits.py: 200 generations took 6 minutes), saves `fits/<name>.json` and writes
`<name>_vs.png` (photo left, generator right). Tried on trident_maple_bark: loss 0.79, but the picture
is wrong: the photo is a soft mottled surface with small scattered flakes and wide shallow dips; the
generator can only make long vertical streaks. So the flake family does not span smooth or mottled
barks (maple, birch, beech, palm rings); those need another generator family (a low-frequency
height field with scattered small flakes), not more fitting. Not added to the game.
Lesson for the pipeline: the loss number cannot tell a good fit from a wrong model; the side-by-side
picture is the check, and the fit script now writes it every time.

## Round 8 (2026-10-22): a second generator family (smooth swelling + scattered flakes); maple in the game
Five new parameters (base_amp, base_cm, base_stretch, flake_cover, flake_amp): a smooth anisotropic
swelling under flakes that cover only part of the surface. The defaults reproduce the old generator
exactly (willow unchanged, checked numba vs numpy), so one model spans flaky and mottled barks.
Maple refit (250 generations): the picture now has the soft mottled surface and scattered small flake
shapes of the photo (`trident_maple_bark_vs.png`), still streakier than the real small round flakes.
In the game: the baked maple is slot 3 (kind 4) next to the baked oak (slot 0); the exporter now lifts
a dark photograph to a bark albedo of 0.1 (maple x2.09, as the atlas did). The shader array is 32 floats.
planet_check (full) and the visual check pass. In the viewer (`bark_view --kind=4 --compare`) the
procedural maple is a plausible bark of the same family, lighter and greyer than the photograph.
Not verified: the maple at other angles, other maple trees, the forest cost (the baked tiles are
sampled like the photos: no change expected). Pine, ash, palm and cedar still use the photographs.

## Round 9 (2026-10-22): cedar and palm fitted on all 6 cores (about 4 minutes each)
`fit_bark.py japanese_cedar_bark` (loss 1.69) and `palm_tree_bark` (2.52). Pictures (`*_vs.png`):
- cedar: the photo is dense, thin, dark vertical fibres with a few bright breaks; the generator makes
  wide pale ribbons with a speckle of bright spots (the fine noise): wrong. Needs a fibre family: many
  thin parallel strands (width 0.5 to 1 cm), each with its own length and darkness, rare gaps.
- palm: the photo is horizontal bands (the leaf scars, 10 to 15 cm apart) with fine vertical streaks and
  scratches; the generator makes a smooth gradient with a few splits: wrong. Needs a ring family: bands
  across the trunk (the old shader already had one for kind 5) plus fine streaks.
Neither goes into the game. State of the six slots: oak and maple procedural (in the game); pine (reads as
leaves), ash (too rough), palm (bands) and cedar (fibres) stay photographs. The generator now has two
families (flakes, swelling + flakes); a third (fibres) and a fourth (rings) are the next two additions,
each a handful of parameters with the same fit and the same side-by-side check.

## Round 10 (2026-10-22): a fibre family (cedar), three fits, not good enough
Five new parameters (fiber_amp, fiber_cm, fiber_seg_cm, fiber_break, fiber_var): thin parallel strands
along the trunk in pieces of their own length, some missing; in numpy, numba (identical) and GLSL
(`bark_bake.gdshader` has 37 numbers). The cedar fit now reproduces the photograph's dark fibrous
background, but every fit adds a few long bright strips or blocks that the photo does not have: with wide
fibres they were blocks (loss 1.15), with narrow ones thin bright lines (1.24), with the amplitude capped
wide pale ribbons (1.60). The optimiser uses them to imitate the photo's few bright breaks; they cost the
look. Ideas: cap the piece length (fiber_seg_cm 6 to 25, the photo's strands are 5 to 20 cm), cap
base_stretch, and penalise outliers in the loss (the brightest 0.5 % of the height picture).
Not in the game: cedar stays a photograph. The fibres/ring families exist but are not yet judged good.
State: oak and maple are procedural in the game; ash, pine, palm and cedar remain photographs, and the
atlas PNG stays for them. A pragmatic stopping point: 2 of 6 barks replaced, the pipeline, the viewer
(arrow keys) and the lessons written down; the other four are each a few more rounds of the same loop.

## Round 11 (2026-10-22, autonomous run): rocks, and the loss that finally works (a lit view)
- Cedar with an outlier penalty got WORSE (grey fog): outlier terms in the loss flatten the picture. Set
  aside; the outlier term stays at weight 4 in bark_perceptual (it may be too heavy, to retest).
- Rocks: `tools/bark/rock_gen.py` (numba generator, 24 parameters: warp, Voronoi blocks cut by cracks,
  strata, swelling, grain, pits, and a rubble layer of small sharp fragments that collects along the
  cracks) with its own fit (`rock_gen.py fit <folder> <name> <tile m>`). Four fits on rock_face_04:
  raw-height Gram loss gave a blob (1.81), +rubble patches (1.57), +rubble along cracks (1.15) were
  all too smooth and missed the plates and cracks.
- THE FIX: the style loss now sees a LIT view of the height (`shaded()` in bark_perceptual.py: light
  from the upper left and upper right plus the height as the 3 channels of the network input), so edges,
  cracks and steps count. Result (loss 0.99, `fits/rock_face_04_rock_vs.png`): smooth plates, thin dark
  cracks, rubble polygons along the cracks: it looks like the photograph. This also applies to every
  bark fit from now on (old bark fits used raw heights): refit pine, ash, cedar, palm with it.
- AGENTS.md lesson: judge the look the eye sees (lit relief), not the raw heights.
Next: the batch refit of the barks with the lit loss; GLSL port + baker for the rock generator;
then wood planks, soil, leaf litter, cliffs, leaves.

## Round 12 (2026-10-23): refit with the lit loss
- pine: overlapping rhombic scales with dark gaps and the right scale and layering, better than before
  but still lens/diamond-shaped where the photo has rounded rectangles with ragged side edges.
- ash: ridged flakes with dark gaps, closer in character, but too uniform and with vertical bright
  streak artefacts (the fibre/groove terms) that the photo does not have.
- cedar: a failed fit (a thin strip of diamonds, then fog) - the outlier terms and the lit loss
  conflict; cedar remains a photograph.
All three remain photographs in the game. The generator's flake outline needs a "rounded rectangle with
ragged sides" option (a superellipse with exponent 3 to 6 and a noise on its half width) to match pine
and ash; the diamond (|v|^tip) and the `block` blend are not enough. Next: that outline, then refit.

## Round 13 (2026-10-23): wider scale-outline exponent for pine: worse
tip range 1..9 (rounder scales): the fit went back to pointed leaf-like scales with odd dark crack arcs
(the groove term). Reverted to 1..3.5 and the earlier pine fit. The outline family is not what limits
the pine; the photo's scales are ragged on the SIDES (jagged vertical edges, the lit loss sees them),
which needs a side-edge noise much stronger than `rag_amp` allows (max 0.09). Next try: rag_amp up to 0.3
with its own scale per axis. Bark work is in diminishing returns: 2 of 6 barks replaced; continue the
list with leaves and soil, come back with the side-ragged outline.

## Round 14 (2026-10-23): pine with stronger ragged edges (rag_amp up to 0.3)
Height: much better (`fits/pine_bark_vs.png`): broad irregular scales with ragged edges and dark gaps,
much closer to the photograph; the scales still end in points at the bottom. In the game viewer
(`bark_view --kind=2 --compare`, baked pine on the right) the TRUNK reads as pine-like scales but its
colour is a pale grey-green against the photograph's red-brown with orange scale faces: the colour model
(mean + ramp by height) cannot give the two-tone scales (orange tops, dark grey gaps). Kept as
photograph in the game. Next for pine: a colour ramp in two hues chosen by flake height AND flake id
(each flake a tone), taken from the photo by fitting the neural loss on RGB (improvement 3 in this file).

Correction to round 14 (checked): the baked pine TILE has the right colour (mean 0.44, 0.36, 0.28 against
the photograph's 0.40, 0.33, 0.25), so the colour model is not the cause of the pale grey-green trunk in the
viewer. The cause is unknown: something between the baked tile and the trunk (the tile's mipmaps made by
`Image.generate_mipmaps` on RGBA with a height in alpha, or the plant shader's use of the height for the
cavity AO and the lichen mask, which differ from the photographs' height stretch: the baked heights have a
mean of 0.67 against the atlas' ~0.5). To check next: bake pine with the atlas' height stretch (mean
0.5), compare the trunk colour again.

## Round 15 (2026-10-23): a FAIR comparison, and the decision: the photographs are the default again
The viewer compared two trees at different positions, so each got its own lichen/moss pattern (bark_style comes
from the tree's position): an unfair comparison. `bark_style_force` (a shader uniform, set by the viewer)
gives both trees the same lichen. Fair result (`cmp9_k0.png`, `cmp9_k2.png`): the baked oak is clearly
coarser, wavier and paler than the photographed oak; the baked pine has the right scale shapes but is paler
and lacks the dark crevices and the red-brown tone. The user preferred the photographed look. So:
- `PlanetWorld` bakes the procedural barks ONLY with env `PLANET_PROCEDURAL_BARK=1` (was: always for oak and
  maple); by default the game uses the photographs for every bark.
- Also added: `alpha_map` (export_fit now gives the baked height the photograph's mean and spread, because
  the shader's lichen and cavity masks read it), `bark_style_force`.
Where the procedural bark falls short of the photograph at close range: the long wavy flame shapes (the
generator's lens flakes are too uniform in direction), too little dark in the crevices, a paler tone.
The closest next steps: crevice darkness (a second cavity term from the gap network), per-flake colour,
shorter flakes with more turn, and a fit that also sees a lit RGB render of the bark in the plant shader.

Round 16: crevice darkness in bark_bake (`mix(0.3, 1.0, smoothstep(0.0, 0.5, h))`, was 0.45 / 0.25): slightly better, the baked oak (`cmp10_k0.png`) is still coarser and wavier than the photograph: the flakes are about twice as wide, with long flame shapes. The lens outline is the limit; try the fit with `cell_cm` capped to half the fitted value and `angle` larger (flakes less aligned), and `len` lower.

Round 17: willow with cell_cm <= 5, len <= 2, angle <= 1.6: blobby mottled surface without flakes (worse).
Reverted the ranges and the fit. The willow generator stays at its round-9 fit (flakes about twice too wide).
The honest state: procedural bark matches the photographs' statistics and the right kind of structure but
not their look at close range; the photographs stay the default. Remaining ideas (not tried): a hybrid, the
photograph as a base tile and the procedural generator as a per-tree variation overlay (broken repeats, per
tree colour), which uses the generator where it is good (large scale variety) and the photograph where it is
good (fine flake detail); and a differentiable generator with a loss on lit RGB renders in the plant shader.

Birch (2026-10-23): Poly Haven has no birch bark; eucalyptus_bark (smooth, peeling strips) fitted as the nearest
(`fits/eucalyptus_bark.json`): the picture has the right kind of mottle with small peeled patches but a much higher
contrast than the photograph. Not used: birch keeps its existing procedural look (kind 1 in flora_wind.gdshader).

Palm (2026-10-23): the wood board generator fitted to palm_tree_bark (loss 1.44): horizontal bands about 10 cm apart
and fine vertical streaks come out right in structure, but one board (the top half) is far darker than the
rest (board_tone and the seam are exploited), and the scratches and pits are missing. A palm-specific ring
family would be: bands every 8 to 14 cm with a bright lip on one edge, a slow tone drift along the trunk, fine
vertical streaks, sparse scratches. Not built; palm stays a photograph.

Cedar via the wood generator on a rotated photo (2026-10-23): loss 3.24, wrong (boards of one tone with a knot; the
photo is a dense field of thin overlapping strips). The cedar's strips are flake-like (long thin overlapping
flakes) not grain; the flake generator with `aspect` up to 8 and tiny `cell_cm` (0.4-1.5 cm) is the right family
and was never given those ranges. Next try: a `fit_bark` variant with cell_cm (0.4, 1.5), cell_aspect (3, 9),
len (1.0, 2.5), angle (0, 0.3), no fibres.
Cedar with tiny elongated flakes (`fit_cedar_flakes.py`, loss 1.35): the flakes appear as thin pointed shards in
one strip, the rest of the tile is foggy: the search switched the flakes off over most of the tile with
`flake_cover` and filled the rest with the swelling. Forced `flake_cover` 1.1..1.2 (flakes everywhere) and
`flake_amp` >= 0.6, refitting.

## Round 18 (2026-10-23): the fix for the cheating search: a detail-profile loss
`detail_profile()` in bark_perceptual.py: the 10/50/90 percentiles of the local standard deviation at 4, 12 and 36 px
windows plus how UNEVEN the detail is over a 6 x 6 grid; added (weight 0.6) to the style loss, outlier weight back to 1.
TEST: cedar with the `flake_cover` exploit allowed again (range 0..1.2): the search chose flake_cover 1.2 (flakes
everywhere) by itself, loss 2.23. Picture (`cedar_flakes_vs3.png`): thin long pointed flakes over the whole tile,
vertical like the photograph's strips: the best cedar so far (still brighter and more contrasty; the photo is
darker with fewer bright spots). Saved as `japanese_cedar_bark_flakes_good.json`. The exploit that gave foggy
tiles, one-strip textures, giant knot rings and blotchy swell is closed by one loss term: the lesson is to ask the
loss for the thing the eye notices (even detail), not to cap the parameters.
Next: refit pine, ash, willow, wood, soil, rocks with the new loss (their old fits used the cheating-prone loss).

Round 19: pine and ash refitted with the detail loss (`refit_pair.png`): pine has the right big scales and
even coverage (no foggy areas), ash is a plausible stringy bark. Both now show the same two artefacts: curved
"smile" arcs (the groove/split cut terms, `cut_depth`) and vertical seams at the cell edges (the lattice of the
swelling term). Next: cap `cut_depth` at 0.3 and `base_amp` at 0.4 for the flaky barks and refit.

Round 20: willow with the detail loss (`bark_willow_02_vs.png`): the best willow so far: even coverage of long
pointed flakes of mixed size, dark crevices between them, the right grey range; the photograph still has more
angular, straight-edged slabs and a more visible diagonal criss-cross of flake direction (the generator's flakes
are all within +-0.4 rad of vertical, `angle` cap 0.8). Pine and ash are refitting with `cut_depth` <= 0.3 and
`base_amp` <= 0.4 (the arcs and seams).

## Round 21 (2026-10-23): the oak is procedural in the game again
Fair viewer (same lichen on both trees), willow refit with the detail loss, baked: the oak (kind 0) now has
similar flake scale, grey-brown tone and dark crevices as the photograph (`cmp11_k0.png`): the best match yet, so
`PlanetWorld._bake_the_bark` bakes it by default (env `PLANET_PHOTO_BARK=1` restores the photograph). Forest lab
view: 70 fps, GPU 14.2 to 14.7 ms (no change); planet_check and visual check pass. Pine (cmp11_k2): the right
scales but pale and flat, with a smooth blotchy surface: stays photograph. Ash (cmp11_k3, not yet looked at in
detail) and maple stay photographs for now; both are in `bark_fits.gd` so `bark_view` shows them.
Next: pine colour (two-tone), the comparison for ash and maple with the new fits, refit rocks/wood/soil with the
detail loss, then the hybrid.

Round 22: cedar baked with the best flake fit (`japanese_cedar_bark_flakes_good.json`, now copied over
`fits/japanese_cedar_bark.json` and exported to slot 5 / kind 6): in the fair viewer the trunk has the right dark
brown and vertical grain but is smooth: the photograph's fine fibrous strips are not resolved by the 1 cm flakes at
the tile's 1 mm/px. Stays a photograph. `BarkBaker.make_array(true)` now bakes every fit for the viewer only; the
game bakes the oak alone.

Round 23 (2026-10-23): THE CEDAR WAS A SCALE BUG, now procedural in the game. The cedar's photograph is 1 x 2 m
squeezed into a square atlas slot, so the plant shader stretched any square tile 2x along the trunk
(BARK_TILE[5] = (1, 2)): the baked cedar looked smooth because its 1 cm flakes were 2 cm long strips stretched.
Now BARK_TILE[5] = (1, 1) with a uniform `tall_slot` (2 for the photograph, set to 1 when the procedural bark is
baked: PlanetWorld and the viewer). With the right scale the baked cedar (fit: flakes everywhere, `_flakes_good`)
shows the photograph's fine vertical fibres, the same dark brown (`cmp14_k6.png`): in the game by default beside
the oak. Forest view 70 fps, GPU 14.1 ms, planet_check and visual check pass.
Lesson: when a baked tile looks smoother or blurrier than its fit, check the tile's metres per pixel in the
shader (BARK_TILE) before refitting.

Round 24 (2026-10-23): per-flake palette for the pine (`PALETTE_MIX` in BarkBaker, k-means colours with a chroma
feature from the photograph in `export_fit.clusters_of`, `bark_bake` `palette`, `palette_shares`, `palette_mix`):
the baked pine TILE now has orange scales among grey-brown ones (`pine_tile_vs3.png`), like the photograph's
colour mixture (the flakes are still pointed lenses and the gaps too light). Oak, cedar unchanged (mix 0).
But in the fair viewer the pine trunk is STILL pale grey-green with no orange (`cmp15_k2.png`): the plant shader's
lichen / moss / mottle paint (flora_wind, `crust`, `moss`, `mottle`, `orange` blocks, which read the baked height
as `h0` and the colour) covers the baked colour: the baked heights have a different histogram than the photograph's
(alpha_map matches mean and spread only). Next: in `bark_view` use `--debug=` (bark_debug 1: the height as grey, 2: the
cells) to compare the heights, then skip the lichen paint for baked kinds (it duplicates what the photo colour
already holds) or scale it by the baked tile's own lichen share.
