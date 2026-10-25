# 090 - Image (or material scan) to procedural generator pipeline

Status (2026-10-25): PLAN ONLY, nothing built. Written after the user asked "if I want a pipeline that accepts an image as input and
generates the procedural rules or code as output, how would we do that?", then "maybe all the assets we have", then "yes, write it all
in a task". Related: 085 (bark from photos, rounds 1-30), 086 (fitting alternatives), 087 (handover).

## Goal

One command per surface: a scan (colour + height, optionally the other maps) in, a fitted generator out, in the form the game
already consumes (numbers in `systems/world_gen/*_fits.gd`, baked by the GLSL `*_bake.gdshader`). Today every surface is a hand-run
chain of `tools/bark/fit_*.py`, `export_*.py`, `colour_match.py` plus many rounds of looking at squares. The pitted rock (cells) is
the worst case: the generator has no structure for rounded blocky ridges, so no parameter fit can look right (see round 30 notes in 085).

## What the game actually consumes (checked 2026-10-25)

- Bake outputs: colour in rgb, height in alpha (one tile per surface), made by the `*_bake.gdshader` through `ColourMatch`.
- Ground scans (ambientCG sets Ground110 gravel, Ground111 red soil, Ground106 leaf; `scripts/make_scan_textures.py`): `<name>_c.png`
  = colour + AO in alpha, `<name>_n.png` = normal XY + roughness in B. `planet_ground.gdshader` samples them in `scan_triplanar`
  (colour ratio, AO, normal tilt, roughness). The scans live outside the repo at `E:/Temp/claude/refs/ground_sets/`.
- SPOM (self-shadowed parallax) in the ground shader ray-marches heights the shader generates itself (procedural heights).
- The Poly Haven set in `tools/bark/bark_downloads/` (18 surfaces, untracked on purpose): the `nor_gl`, `rough`, `arm` files were not
  found in any `.gd`/`.gdshader` (only the boulder has the full set). Pitted rock has only `_diff.jpg` and `_disp.png`.
- So the pipeline must OUTPUT colour, height, AO, normal, roughness; it needs colour + height as INPUT (normal and AO can be derived from
  height; roughness is a bonus, else a per-material constant; metal is zero for all our surfaces; `arm` is only AO+rough+metal packed).

## Research (one web search + one repo read, 2026-10-25; a starting list, not a survey)

- DiffProxy (Hu, Guerrero, Hasan, Rushmeier, Deschaintre, SIGGRAPH 2022), https://github.com/yiwei-hu/DiffProxy, cloned to
  `E:/Temp/dp/DiffProxy`: fits the parameters of a node graph to a photo through a trained StyleGAN3 proxy. About 1,200 own lines, last
  commit 2022-12, no top-level licence file (assume research only). Needs the proprietary Adobe Substance Automation Toolkit to make
  training data (about 300,000 images per generator) and a VGG19 file from a Google Drive link. NOT reusable as is. Its loss is worth
  copying: L1 + VGG feature loss (weight 10, layers r22 r32 r42) + VGG style/Gram loss (weight 1, layers r11 r21 r31 r41 r51).
- DiffMat (MIT, https://cdfg.mit.edu/assets/files/match.pdf): procedural node graphs translated into differentiable programs; picks a
  graph from a library, fits parameters, also recovers roughness and metallic. Code availability not confirmed.
- Hu et al. 2022 "An Inverse Procedural Modeling Pipeline for SVBRDF Maps" (https://graphics.cs.yale.edu/sites/default/files/ipmm_preprint.pdf):
  builds NEW procedural models from SVBRDF maps (no artist graph). Input is the full map set.
- VLMaterial (ICLR 2025, https://arxiv.org/html/2501.18623v2): fine-tuned vision-language model writes Blender procedural material code
  from an image; releases a dataset. Model weights not confirmed public. Blender-only.
- Not found in the search (unverified, check separately if wanted): MatFormer, Material Maker, ArmorLab, ControlMat.

## Design (hybrid: trusted generators + measurement + fitting + check loop)

1. MEASURE (no model): per scan, feature scale (autocorrelation / watershed: pixels per cell, plate, flake), anisotropy (FFT),
   3-5 palette colours with shares, std per size band. Cap every scale parameter from this BEFORE fitting (085 lesson: free fits that
   lowered the loss by making features bigger or simpler always looked wrong). Existing: `tools/bark/measure_scale.py`,
   `extract_features.py`, `analyze_flakes.py`.
2. CLASSIFY the generator family: flakes, plates, rings, lumps, chips, soil, smooth. A vision model (Claude) sees the scan + the
   measurements and names the family; a new family is flagged, not forced.
3. FIT parameters with gradients. Reimplement the 2-3 most used generators (plates, flakes, chips) in PyTorch (differentiable: soft
   Voronoi edges, smooth steps). Loss = L1 on colour and height + VGG feature + Gram style (DiffProxy weights) + sliced Wasserstein
   (`bark_perceptual.py`, SW_WEIGHT 0.5) + measured stats. Several starts. Then the closed-form `colour_match.py` pass. Compare with the
   current black-box search (`fit_*.py`) on the same surface.
4. EXPORT the numbers only (a `*_fits.gd` row), baked by the existing GLSL. The PyTorch generator must match the GLSL one (test: same
   params, same seed texture, difference under a threshold); otherwise the fit is for the wrong picture.
5. AGENT LOOP for a missing family (the new part): a model writes a GLSL bake shader, it is rendered by `square_compare --shot`, a vision
   model + the metrics list what differs, the model revises, 5-10 rounds, human check at the end. Needs an automatic render and an
   automatic comparison or it drifts.
6. VALIDATE in two views (flat square AND object view with parallax; they disagreed several times), plus tile edges and seams.
   Outputs also AO / normal (from height) / roughness so the ground scan path and the PBR bakes get all five maps.

## Steps

- [ ] 1. Inventory: for every surface (the 18 Poly Haven + 3 ambientCG sets), which maps exist, which generator family it uses, its current
      fit file, and a judged rating (ok / close / bad) from the squares. Write the table here.
- [ ] 2. One command `tools/bark/pipeline.py <surface>`: measure -> (family from a flag first, vision model later) -> existing fit -> export
      -> colour_match -> square shot. Replaces the hand-run chain; no new maths yet. Check it reproduces today's fits for 3 surfaces.
- [ ] 3. PyTorch plates generator + GLSL parity test (the pitted rock is the target). Gradient fit against colour + height.
- [ ] 4. Fix the pitted rock structure: rounded blocky ridges with few cracks (the user: "still looks bad compared to the og image").
      Round 30 got colour and plate size close; the crack network is still too regular and thin with a dotted parallax edge, no deep pits.
- [ ] 5. Derive AO, normal, roughness from the fitted height in the pipeline output; compare with the scanned ones where they exist
      (boulder; the three ambientCG sets).
- [ ] 6. Vision-model family classifier + the agent loop for a new family; try on one surface with no good generator (birch/sakura smooth
      bark, rock slot 5 layered rock: both "failed for good" in 085).
- [ ] 7. Port flakes and chips to PyTorch if step 3 beats the black-box fit.

## Risks / open questions

- Single photo plus height does not give true 3D for rocks; the height map is the only ground truth, so rocks without one stay hard.
- Differentiable generators must stay in sync with the GLSL (two implementations of each generator). A parity test is mandatory.
- Licences: DiffProxy has no clear licence; ambientCG and Poly Haven are CC0 (scans outside the repo are not committed).
- Compute: gradient fits on the 4090 should take minutes per surface; the black-box fits took much longer.
- Whether to use published code (DiffMat, if released) or only the ideas: decide after reading its repo if it exists.

## Decisions

- 2026-10-25: do not adopt DiffProxy's code (Substance dependency, per-generator proxy training); reuse its loss and the differentiable-fit idea.
- 2026-10-25: inputs = colour + height required; AO/normal derived; roughness optional; metal ignored.
