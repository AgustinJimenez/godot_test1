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
      IDENTICAL: bark (pine_bark call, covers all bark entries), ring (palm), soil (red soil), lump (boulder). DIFFERENT: plate (the
      committed `rock_pitted_mossy` cell size is 25 by my hand edit; the json says 18), chip/gravel (5 lines: the committed params are not
      what `fits/gravel_soil_chips.json` gives now), wood (16 lines: the json was refitted after the committed file; also new params
      `drift_amp`, `drift_cm`), litter (8 lines). So four generated files cannot be reproduced from the fit json: before relying on the
      pipeline for them, decide per file whether the json or the committed file is the truth (a hand edit like the plate cell size
      should go into the fit script/json, not only into the generated .gd, or the next export silently undoes it).
      `match` verified on the pitted rock: same colour fit as the hand-run `refit.sh`, no change in `systems/world_gen`.
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
