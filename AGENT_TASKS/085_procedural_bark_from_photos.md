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
