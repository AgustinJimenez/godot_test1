# 086: research on alternatives to the hand-made generators (2026-10-23)

Why: in AGENT_TASKS/085 most free fits lowered the Gram (VGG style) loss by making features bigger or simpler, and the
pictures got worse. The method, not the numbers, is the problem.

## What the literature offers (web search, one pass: check the papers before relying on this)
1. **Differentiable procedural material capture: MATch / DiffMat** (Shi et al., SIGGRAPH Asia 2020; DiffMatV2 is used in
   PSDR-Room, arXiv 2307.03244). They turn photographs into procedural material graphs by gradient descent through
   differentiable versions of Substance-style nodes, with a style-transfer-like loss. This is the same idea as
   `tools/bark`, but (a) the graphs are made of generic nodes (noise, warp, cells, blend, levels) rather than one
   hand-written generator per material, and (b) the optimisation is by gradient descent, not CMA-ES on 15-40 numbers.
   Source: https://cfg.mit.edu/publications/match, https://dspace.mit.edu/entities/publication/c1487622-b0ae-4002-9a59-4f26c9388494
2. **Sliced Wasserstein loss** (Heitz, Vanhoey, Chambon, Belcour 2021, "A Sliced Wasserstein Loss for Neural Texture
   Synthesis"): replaces the Gram matrices, which only match second moments, by a loss on the whole distribution of
   VGG features; far better at keeping structure (cracks, cells, rows). The follow-up "Controlling Material Appearance
   by Examples" (arXiv 2206.14970) handles different sample counts (uniform resampling) and gives a sliced Cramer
   variant. Likely fix for our "lower loss, worse picture" problem. Source: https://arxiv.org/pdf/2206.14970
3. **Histogram-preserving blending for randomized tiling** (Heitz and Neyret 2018; Burley and Heitz, JCGT 8(4) 2019,
   https://www.jcgt.org/published/0008/04/02/paper.pdf): make an endless non-repeating surface from a SMALL photo: the
   photo is first transformed to a Gaussian histogram (3D optimal transport, a LUT), tiles are blended with
   random offsets on a triangle grid, then the histogram is restored. Preprocessing takes minutes for 256 x 256;
   runtime is three texture reads. This does not remove the image, but it would let the atlas shrink from 1024 to 256
   or 128 pixels per material and remove visible tiling.
4. Adobe patents on generating differentiable procedural materials from images exist (status unchecked): avoid
   copying their graph structure; the papers above are enough.

## Plan (smallest steps first)
- [x] A (done as an option: `SW_WEIGHT=1.0 python fit_pine_plate.py ...`, `bark_perceptual.feature_sets/sw_quantiles/sw_distance`, used by `rock_gen.fit` loops: 64 random directions, 128 quantiles per layer). First test on the pine plates (`fits/pine_bark_plate_sw.json`, `_sw_vs.png`): loss 2.58 (not comparable with the Gram-only 2.09); the plates are taller and their wavy outlines closer to the photograph, but their tones are far more varied (black and white plates) where the photograph is nearly uniform with soft shadows: so SW sees the shapes better and the tones worse (the tone term needs a weight). Not a clear win; try weight 0.3 and a tone term. Original plan: Add a sliced Wasserstein term to `bark_perceptual.py` next to the Gram term (VGG19 features at 3-4 layers, 64-128
  random projections, sort and compare); refit the pine plates, the palm and a rock; compare pictures AND loss.
- [~] B (likeness tried in Python, `tools/bark/stochastic_tile.py`: a 256 px crop of the pine photograph, per-channel Gaussianisation, three randomly shifted copies on a skewed triangle grid, variance-preserving blend, histogram restored): the repeat that a plain tiling shows (the same dark blobs every 256 px) is gone and the colour, scale and grain are kept; the barycentric bug is fixed (the weights of the two vertices of the upper triangle were swapped); the remaining straight seams come from the 256 px CROP not being seamless (its own border is wrapped): the Poly Haven maps are, so use the whole map in the shader. Cost in the shader: 3 reads instead of 1 per sample, x3 inside the parallax march (which samples the height many times), so measure with `gpu_breakdown.sh` before adopting; the Gaussianised tile and LUT are small, so the atlas could shrink 4x to 16x. Original plan: Try the histogram-preserving tiling (item 3) on the bark atlas as a fallback: a 256 px Gaussianised tile plus a
  colour LUT replaces each 1024 px slot; measure the memory (the atlases are 15.7 MB and 15.4 MB now) and the look.
- [ ] C. Only if A shows the same trouble: a small node-graph generator (noise, domain warp, Voronoi, blend, levels)
  fitted by gradient descent in PyTorch, as MATch does.

Licence note: papers are for learning; write the code from scratch (same rule as the Unreal source study in 083).

## Result of the in-game test of B (2026-10-23)
- `stoch_tiling` uniform in `flora_wind.gdshader` (`photo_tap`: three taps, skewed triangle grid, variance-keeping
  weights), switched by `PLANET_STOCH_BARK=1` (game) or `--stoch` (`bark_view.tscn`). Default off.
- **Performance** (forest walk 30 s, photographs for every bark, `planet_lab.tscn -- --plants --grounded --forest-walk=30
  --fixed-fps 60`): GPU 13.6 ms avg without, 14.7 ms with (+1.1 ms, about 8 %); frame rate 54.6 against 50.7.
  Affordable for a few species, not for everything at once.
- **Likeness**: the plain version (no Gaussian pre-transform, an assumed mean of 0.4) is WRONG in the game: the bark
  turns black and red, contrast blown. Heitz and Neyret's method needs the atlas Gaussianised first and an inverse LUT
  after the blend; without it the variance correction pulls everything towards the assumed mean. The Python prototype
  (`stochastic_tile.py`) does it right (rank transform per channel) and looks right. Next step: write the
  Gaussianised atlas (store the rank-Gaussian values, 8 bit is enough at 256 px) plus a 1D LUT per channel and the
  pine's histogram, then the shader blends the Gaussian values and maps back through the LUT.
- Not adopted. Interaction to check: the parallax march reads the height many times, so tap the 3-blend only for the
  colour and keep one tap for the height march (the height can be blended once at the hit point).

## Decision (2026-10-23)
Stochastic tiling is NOT being adopted now. The Python prototype shows it removes the visible repeat and keeps the look, but
doing it right in the game needs a Gaussianised copy of the atlas as a new array texture, a LUT texture per channel and
layer, and 3 taps + 1 LUT fetch per sample: about +1.1 ms GPU (measured with the naive version; the LUT adds a little)
and more memory, while the aim is LESS image data. It also does not move us towards "replace the photographs by code".
It is worth revisiting only if visible tiling of the photographed bark becomes a complaint (a tree's trunk repeats once
per 1-2 m around, so it is hidden in most views). Step A (sliced Wasserstein loss in the fitter) is the useful part and
stays on the list. The test switches (`PLANET_STOCH_BARK`, `--stoch`) stay in as documented experiments, off by default.

## Guide map experiment (2026-10-23): deterministic layout from a tiny picture, procedural detail on top
`tools/bark/plate_guided.py` = the pine plate generator that reads a small picture of the photograph's height (percentile-
stretched) and gives each plate the guide's value at the plate's centre (`guide_mix` 1 = all from the guide). Measured as the
correlation of the low-passed render with the low-passed photograph (the LAYOUT, not the fine detail; `fits/pine_guided_vs.png`:
photo, then no guide, guide 16 x 16, 32 x 32, 64 x 64):
- no guide: 0.07 (the plates' tones are unrelated to the photograph)
- 16 x 16 guide: 0.56 (about 0.3 KB at 8 bit: the big dark and light areas now sit where the photograph's do)
- 32 x 32: 0.52, 64 x 64: 0.32 (finer guides get WORSE: a plate's centre samples single pixels of the photograph, and plate
  tones then follow noise, not the layout; low-pass the guide to the plate size first)
So a 16 x 16 guide (256 bytes per channel) is enough to bring back the layout. Dropping the guide = `guide_mix 0` = fully procedural.
The plate outlines and cracks are still the generator's own, so this is not a copy of the photograph (the pictures differ in the
details). Not in the shader yet (a 16 x 16 `uniform sampler2D` or float array would do).

## Plain-square comparison sheets (2026-10-23, at the user's suggestion)
`tools/bark/compare_sheet.py <folder> <name> <plate|lump|chip|ring|ledge|bark> <fit json> <tile m> <out png> [baked colour png]`
writes `fits/sheets/<name>.png`: photograph colour, the baked colour (if given), BOTH heights lit from the upper left at the
same strength, 1:1 crops of the same place, and the measured feature sizes with their ratio. No object, no projection.
First sheets, honest reading (the object views had been kinder):
- **pine plates**: the procedural is tiled blocks of the same size with a fine pebbly grain; the photograph is long fibrous
  ridges with deep dark grooves between them (ratio 1.29 across, 0.83 along). The "close to the photograph" of the earlier
  object view came from the colour; in height the two differ. The grain (`fine`) should go and the grooves be much deeper.
- **rock_face_04** (lump + straight cracks): cracks are wider and more regular than the photograph's hairline cracks, and the
  lit height shows almost no relief in the photograph itself (it is a flat, stained slab): a colour-driven look.
- ratios (procedural / photograph feature size, across and along): rock_face 1.29 / 0.96, boulder_dry 1.16 / 1.03, rock_08 0.89 / 0.87,
  gravel 0.69 / 0.64, pine 1.29 / 0.83, palm 5.07 / 0.59 (the palm sheet crops a 2:1 photograph: the ratio is not valid there).
Use the sheet BEFORE the object view for every new fit.

## Outcome of the research plan (2026-10-24)
- A (sliced Wasserstein term, `SW_WEIGHT`): kept; it made the long-flake pine and ash fits and the plate pine possible; it did
  nothing for rocks (the generator was the limit there).
- B (stochastic tiling): prototyped in Python and as a shader switch (`PLANET_STOCH_BARK`); not adopted (needs a Gaussianised
  atlas + LUT, +1.1 ms GPU).
- Guide maps (16 x 16 picture steering plate and lump tones, `guide_mix` 0 = fully procedural): done for the pine plates and the
  lump rocks; the way to "match the photograph first, then remove the matching part".
- C (differentiable node graph, MATch-style): not started; the hand-built families (flakes, plates, rings, lumps, chips, ledges,
  soil) covered what could be covered. Revisit only if a new surface needs a family we do not have.
