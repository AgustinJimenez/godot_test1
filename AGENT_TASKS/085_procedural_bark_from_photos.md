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
