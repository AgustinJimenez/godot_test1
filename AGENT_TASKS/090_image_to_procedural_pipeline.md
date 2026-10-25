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

- [x] 1. Inventory (done 2026-10-25, table below).
- [x] 2. `tools/bark/pipeline.py` (done 2026-10-25): `list`, `measure`, `fit`, `export [--check]`, `match`, `run <surface> [--fit]`. It only
      chains the scripts that were run by hand (measure_scale, fit_*, export_*, colour_match, square_compare, the class-cache refresh).
      Python: anaconda (`C:/Users/agus_/anaconda3/python.exe`, override with PIPELINE_PYTHON): the default python lacks `cma`. NumPy 2
      prints import warnings from matplotlib: harmless. `fit` is wired for ash, pine, palm, litter, gravel, red soil, the four lump
      rocks, pitted rock and wood, but NOT run (hours); oak/maple/cedar were fitted by hand (`fit_bark.py`).
      `export --check` re-exports a family file to a temp file and diffs it against the committed one. Result today:
      IDENTICAL: bark (pine_bark call, covers all bark entries), ring (palm), soil (red soil), lump (boulder). DIFFERENT: plate (FIXED later the same day: cell size 25 moved into the json), chip/gravel (5 lines: the committed params are not
      what `fits/gravel_soil_chips.json` gives now), wood (16 lines: the json was refitted after the committed file; also new params
      `drift_amp`, `drift_cm`), litter (8 lines). So four generated files cannot be reproduced from the fit json: before relying on the
      pipeline for them, decide per file whether the json or the committed file is the truth (a hand edit like the plate cell size
      should go into the fit script/json, not only into the generated .gd, or the next export silently undoes it).
      `match` verified on the pitted rock: same colour fit as the hand-run `refit.sh`, no change in `systems/world_gen`.
- [x] 3. PyTorch plates generator + GLSL parity test + gradient fit (done 2026-10-25, details below).
- [~] 4. (partly done, see 085 round 30 'round 2') Fix the pitted rock structure: rounded blocky ridges with few cracks (the user: "still looks bad compared to the og image").
      Round 30 got colour and plate size close; the crack network is still too regular and thin with a dotted parallax edge, no deep pits.
- [x] 5. (done, see 'Step 5 result') Derive AO, normal, roughness from the fitted height in the pipeline output; compare with the scanned ones where they exist
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

## Inventory (step 1, 2026-10-25)

Maps = which Poly Haven files exist in `tools/bark/bark_downloads/` (diff = colour, disp = height; the boulder is the only full set).
Sq = the `square_compare` index (1-based, as shown in its title). Game = default in the game or opt-in switch (085 round 28).
Rating = my last judgement on the squares: ok (hard to tell apart), close (right colour and structure, details differ), weak (visibly
different), none (no generator). Ratings for the four lump rocks and ash/litter come from the notes in 085, not a fresh look today.

| Surface | Sq | Maps | Family (baker) | Fit data | Game | Rating |
|---|---|---|---|---|---|---|
| bark_willow_02 (oak) | 1 | diff, disp | bark flakes (BarkBaker) | bark_fits.gd | default | close |
| trident_maple_bark | 2 | diff, disp | bark flakes | bark_fits.gd | default | close |
| japanese_cedar_bark | 3 | diff, disp | bark flakes | bark_fits.gd | default | close |
| tree_bark_03 (ash) | 4 | diff, disp | bark flakes, ridge tries failed | bark_fits.gd | PLANET_PROCEDURAL_ASH | weak (warm, shiny) |
| pine_bark | 5 | diff, disp | bark flakes + palette override | bark_fits.gd | PINE | close (round 30 colour; plates too regular) |
| palm_tree_bark | 6 | diff, disp | rings (RingBaker) | ring_fits.gd | PALM | weak (no weathering bands) |
| forest_leaves_03 (litter) | 7 | diff, disp | bark flakes, palette_flat (leaf litter) + GroundBaker | litter_fits.gd | LITTER | close (leaf shapes blocky) |
| gravel_soil | 8 | diff, disp | chips (ChipBaker) | chip_fits.gd | GRAVEL | close (round 30; chips too big/few) |
| red_soil | 9 | diff, disp | soil (SoilBaker) | soil_fits.gd | RED | close (round 30) |
| rock_boulder_dry | 10 | diff, disp, nor_gl, rough, ao, arm | lumps (LumpBaker) | lump_fits.gd | LUMPS slot 0 | close (swirls/lichen differ) |
| rock_face_04 | 11 | diff, disp | lumps | lump_fits.gd | LUMPS slot 1 | close |
| rock_08 (mottled) | 12 | diff, disp | lumps | lump_fits.gd | LUMPS slot 2 | close |
| rock_06 (webbed) | 13 | diff, disp | lumps | lump_fits.gd | LUMPS slot 3 | close |
| rock_pitted_mossy | 14 | diff, disp | plates (PlateBaker, flat_rock) | plate_fits.gd | CELLS slot 4 | weak (round 30 helped colour and size) |
| oak_wood_planks | 15 | diff, disp | wood (WoodBaker) | wood_fits.gd | WOOD | close (no cathedral grain) |
| rock_boulder_dry_sharp | - | diff, disp (+ disp_vs preview) | none (a variant of the boulder) | none | - | none |
| dark_rock_02 | - | diff, disp | none | rock fit json only (tools/bark/fits) | - | none |
| sakura_bark | - | diff, disp | none (smooth-bark families failed, 085 round 28) | none | - | none |
| Ground110 gravel (ambientCG) | - | colour, AO, normal, roughness (scan, outside repo) | n/a: used as a scan | assets/textures/ground/scans/gravel_[cn].png | default (near ground) | scan |
| Ground111 red soil (ambientCG) | - | same | n/a | .../red_[cn].png | default | scan |
| Ground106 leaf (ambientCG) | - | same | n/a | .../leaf_[cn].png | default | scan |

Observations for the next steps:
- 15 of 18 Poly Haven surfaces have a generator; 3 have none (boulder_sharp is just a variant; dark_rock_02 and sakura_bark are candidates for step 6).
- Only the boulder has normal, roughness, AO: it is the one place to test step 5 (derive the maps from height, compare with the scanned ones).
- The ambientCG scans are inputs the generators are NOT fitted to: we could fit the gravel/red/leaf generators to them too (they carry all five maps).
- Families by count: bark flakes 7 (incl. litter), lumps 4, chips 1, soil 1, rings 1, plates 1, wood 1. Plates is used once, so step 3's PyTorch
  plates generator pays off mainly for the pitted rock (and as a template); flakes covers the most surfaces, so step 7 may deserve a higher priority.

## Step 3 result (2026-10-25): differentiable plates generator

- `tools/bark/torch_plates.py`: the shader's `plates()`, pits and final alpha in PyTorch, line by line. To make it exact the plate shader's
  hash is now an INTEGER hash (`plate_bake.gdshader` `hash2`, uint arithmetic) instead of `fract(sin(..) * 43758.5)`: the sin hash gives
  different low bits on the GPU and the CPU and the fract of a big product turns that into a different random number. Same params, tile and
  seed: `tools/bark/torch_plates_parity.py` (Godot bake alpha vs the torch render, 1024 px): mean abs diff 0.00098, max 0.0022 (an 8-bit
  alpha step is 0.0039), correlation 0.99996. Pitted rock layout changed once because of the new hash (a different random draw, same statistics).
- `tools/bark/fit_plates_torch.py <folder> <name> [steps]`: whole-number structure (cells per tile `NU=3,4` env, stretch, noise scales) searched
  on a grid, the nine continuous numbers (jit, warp_amp, crack_w, crack_depth, lip, z_var, tilt, fine_amp, rag_amp) by Adam on VGG Gram +
  sliced Wasserstein (`bark_perceptual.py`) of the hillshaded, contrast-stretched height, two seeds per step, fully procedural (no guide map).
  A 120-step run takes about 1.5 min per cell count on the 4090 (the black-box fits took hours). Writes `fits/<name>_plate_torch.json` with the
  numbers by name and the shader's own `height_range` (`export_plate.py` now uses it when present; before it used the older numba model's range).
- Result on the pitted rock: loss 10.4 (the hand-set numbers) -> 6.0. Two free runs went wrong in ways the loss could not see, found by looking:
  (1) z_var at its upper bound 0.6 gave hard tone steps between blocks; (2) crack_depth fitted down to its lower bound 0.2, so the cracks all but
  disappeared in colour. The final run caps z_var at 0.3 (`ZVAR_MAX`) and crack_depth at >= 0.5. LESSON (same as 085): the style loss weighs fine
  grain over the few thin cracks that make the photograph read as cracked rock; bound those parameters from what the eye needs, or add a
  crack term (percentile / hillshade-edge statistics) to the loss.
- Adopted: `fits/rock_pitted_mossy_plate.json` is now the torch fit (cell 33.3 cm = 3 per tile, crack_depth 0.5.., see the file), `plate_fits.gd`
  re-exported (`pipeline.py export --check`: IDENTICAL), colour fit redone, `visual_check` PASS. In the object view the rock reads as rounded
  cushion blocks with thin dark cracks and pits, the best so far; on the flat square the cracks are fainter than in the photograph.
- Decision: keep the gradient route for the other plate-like surfaces only after a parity-tested torch port of their shader; the next
  candidates by value are the bark flakes (7 surfaces) and chips (gravel). Step 7.
- Tried (same day): a thin-crack term (`EDGE_WEIGHT`: percentiles 50/90/99 of the local slope) and a block-tone term (`LOW_WEIGHT`: spread of 32 px
  block means) in `fit_plates_torch.py`, both OFF by default (the adopted fit was made without them). With EDGE_WEIGHT=1 alone and the
  bounds off, crack_depth stayed at 0.47 (cracks kept) but z_var went back to its upper bound 0.575 (hard tone steps); adding LOW_WEIGHT=2 the
  loss fell to 5.2 and crack_depth went back to 0.22. So these statistics trade against each other and the loss still prefers what the eye
  rejects: keep the hand bounds (ZVAR_MAX 0.3, CRACK_MIN 0.5) until a better judge exists (e.g. a vision-model comparison of the squares).

## Step 5 result (2026-10-25): maps from the height (`tools/bark/derive_maps.py`)

Checked on the one scan with all maps, `rock_boulder_dry` (its own `_disp` as input, 150 cm tile, relief scanned over 2-32 cm):
- Normal from the height (Sobel, OpenGL, y up): at a relief of 4 cm the mean angle to the scanned normal is 2.7 degrees (median 1.9), xy correlation 0.905.
  So the normal map need not be scanned or fitted: derive it from the (generated) height. 8 cm: 8 deg, 2 cm: 3.7 deg.
- AO: cavity occlusion (how far a point lies below its blurred neighbourhood) at radii 0.5 and 1 cm, strength 1.5: correlation 0.615 with the scanned
  AO (mean 0.946 vs 0.929). Larger radii or one radius gave 0.54 or less. A moderate match: it gets the cavities, not the broad shading.
- Roughness: the scan is nearly constant (mean 0.634, std 0.069); a height-derived "busy" term has correlation 0.05, so use a per-material constant (default 0.75 in the script; 0.63 for this rock).
- `derive_maps.py make <height.png> <prefix> <tile_cm> <relief_cm>` writes `<prefix>_n.png` (normal RG + roughness B) and `<prefix>_ao.png` in the layout of the ambientCG scan textures.
  Not yet wired into `pipeline.py` or the baker; the ground scans still use the scanned maps.

## Step 6 first pass (2026-10-25): the new-family loop on dark_rock_02 (no generator; four earlier families failed, 085 round 28)

Method (the loop, run by hand with me as the vision judge; every round = a fit of a few minutes + one picture):
- Look at the photo and its height (`probe` picture): dark brown-black stone, thin crack network mostly HORIZONTAL, rectangular blocks 5-25 cm, a few
  big cliff steps and orange stains. Family guess: plates, but wide flat cells.
- Round 1, plates generator with `STRETCH=0.5,0.8`, `NU=12,18` (`fit_plates_torch.py` now takes a surface with no entry: `TILE_CM`, `STRETCH` env):
  loss 43; the picture is round blobs of 17 cm with no straight lines and no cliffs. REJECTED: Voronoi cells cannot make rectilinear blocks.
- Round 2, a new generator written for it, `torch_courses.py` (rows of blocks, offset joints, thin cracks that come and go, per-block height
  steps and tilt, broad ledges) fitted by `fit_courses_torch.py` (Gram + SW + crack-slope + block-tone terms, about 3 min for two course sizes).
  Loss 3.1: reads as a regular brick wall. Revised: courses of varying thickness, wandering lines, per-course block width. Loss 2.8: still a
  wall. NOT adopted; kept as a record (`fits/dark_rock_02_courses.json`, `compare_torch.py` makes the judge picture).
- What the photograph has that the generator lacks: block sizes that vary a lot inside one course, joints that do not run straight through,
  shingle-like overlaps, and the large cliff steps (the `ledge` term is a smooth blob, not a cliff). Next revision would need broken joints and
  a real ledge (steep step along a wandering line), then a GLSL port (shader + baker + fits + export + square_compare entry), which is the
  expensive part: do it only if the surface is wanted in the game.
- Findings for the pipeline: (1) the mechanics work: write a generator in torch (an hour), fit it by gradient (minutes), judge by one picture; the
  hand-written `torch_courses.py` reuses `torch_plates.py`'s hash and noise, so a new family is mostly its own 40-60 lines. (2) the judging
  step does not automate: the loss went 43 -> 3 -> 2.8 while the picture went from "wrong" to "a wall", and the loss gave no hint of "wall".
  A vision-model comparison of the two pictures with a short list of differences is the missing automatic judge (not built).
