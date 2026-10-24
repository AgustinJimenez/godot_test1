# 087: handover: how the photo-to-procedural work is done, so anyone can continue it

Written 2026-10-24 at the user's request. Read this first, then `AGENTS.md` ("Procedural surfaces fitted to photographs") and the
rounds in `085` (bark), `084` (everywhere) and `086` (research).

## The goal
Replace the photographs (Poly Haven, CC0) used for bark, rocks, ground scans and wood with procedural code that looks like them
at game distance, so the image files can go. Not a copy: "close at game distance, sharp when zoomed".

## State (2026-10-24)
- In the game by default: oak, maple, cedar bark are procedural (baked at load by `BarkBaker`). Everything else is still a photograph.
- Procedural but OFF by default (environment switch, or ONE switch for all: `PLANET_PROCEDURAL_ALL=1` or an empty file
  `procedural_all` in the project folder, git-excluded): PINE, ASH, PALM, LITTER, GRAVEL, RED (ground scans), WOOD (cabin
  boards), LUMPS (rock slots 0-3), CELLS (rock slot 4), BARK_GROOVES (grooved oak, maple, cedar). All of them together cost
  nothing measurable (forest walk, GPU 14.6 ms vs 14.8 ms).
- Still photographs for good with the current generators: birch (no Poly Haven photo; 5 families failed on sakura bark) and
  rock slot 5 (layered rock, 5 families failed).
- Decision still open for the user: which opt-in sets become the default.

## See it: the square scene (the most useful tool)
`tests/manual/world/square_compare.tscn` (open in the editor, F6). Left: the photograph. Right: the procedural bake, same size,
no object, no lighting. Keys: Left/Right surface (15), H colour <-> height lit from the upper left, Z zoom 1/2/4x on the same
spot, G grooved barks. Options after `--`: `--surface=N --height --zoom=4 --shot=PATH` (saves a picture and quits).
Judge colour AND lit height AND zoomed (4x shows blur the 1x view hides). The tree/object view (`tests/manual/world/bark_view.tscn
-- --compare --kind=N --dist=1.2 --height=1.2`) is a second check, never the first: it adds lighting, projection, lichen paint.
Rock check: `rock_view.tscn -- --baked`. Cabin: `cabin_view.tscn [-- --procedural]`.

Godot 4.7.2: `E:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe` (the `_console` build prints to the terminal; scripts use it).

## The loop that worked (per surface)
1. Download the maps: `tools/bark/fit_bark.py` has `download(name, folder)` (Poly Haven API, 1k diffuse + displacement) into
   `tools/bark/bark_downloads/` (git-untracked). Size of the photographed patch = the API's `dimensions` (metres).
2. Look at the photograph and its lit height by eye. Pick the generator FAMILY first (see below). Measure the feature size
   (`tools/bark/measure_scale.py <folder> <name> <tile m>`: correlation length across/along, strongest repeat).
3. Fit: `tools/bark/<family>_gen.py` has numba generators and a CMA-ES fit through `rock_gen.fit` / `bark_perceptual.fit`
   (Gram style loss on the hillshaded height + size + detail profile). Add `SW_WEIGHT=0.5` for the sliced Wasserstein loss.
   Cap the SCALE parameters from the measurement (`RANGES.update(...)` in a small `fit_*.py`); free fits cheat the statistics.
   `BARK_CORES=6` (default 3). Fits take 3-9 minutes at 200 generations.
4. Compare on a plain square: `python tools/bark/compare_sheet.py <folder> <name> <family> <fit json> <tile m> <out png>`
   (photograph vs procedural, same lit height, 1:1 crops, feature-size ratios) AND the Godot square scene. READ THE PICTURE.
   A perfect feature-size ratio hid a pine with 8 x 30 cm flakes; a lower loss was often a worse picture (see pitfalls).
5. Export the fit to GDScript: `export_fit.py` (bark kinds, `bark_fits.gd`), `export_plate.py`, `export_ring.py`, `export_lump.py`,
   `export_chip.py`, `export_soil.py`, `export_wood.py` (each writes `systems/world_gen/*_fits.gd`: generated, never edit).
   Example: `python tools/bark/export_fit.py tools/bark/bark_downloads systems/world_gen/bark_fits.gd bark_willow_02:2.15:0 pine_bark:2.0:2 tree_bark_03:1.0:3 trident_maple_bark:1.8:4 japanese_cedar_bark:1.0:6`
   (name:tile_m:godot_kind). Python: `E:\anaconda3\python.exe` (numpy, scipy, cv2, numba, torch+CUDA, cma).
6. Bake in Godot: the baker nodes draw ONE 1024 px tile in a SubViewport once at load (`BarkBaker`, `PlateBaker`, `RingBaker`,
   `LumpBaker`, `ChipBaker`, `SoilBaker`, `WoodBaker`, `GroundBaker` for the ground scan maps); the GLSL ports are in
   `shaders/world/*_bake.gdshader` and tile (whole-number repeats, wrapped hashes). Per-surface knobs are the constant tables
   at the top of `bark_baker.gd` (BRIGHTNESS, FLATTEN, DESATURATE, FINE_MOTTLE, EDGE_DARK, GROOVED_*, PALETTE_MIX, CRISP,
   HEIGHT_SPREAD) and the `lump_baker.gd` / `plate_baker.gd` constants.
7. Tune the COLOUR in the shader on the squares (colour is judged against the photograph's mean and contrast: the means were
   measured with a small PIL/numpy script and compared; match mean first, then contrast). Then the lit height.
8. Checks, then commit and push (below).

## Generator families (which one for what)
`procedural_bark.py`/`bark_fast.py` flakes (oak/willow, maple, cedar; forced long and thin = pine, ash), `plate_gen.py` Voronoi
plates (pitted rock; pine plates unused), `ring_gen.py` rings (palm), `lump_gen.py` lumps + creases + rubble + straight-crack
network + mid octave (boulders, rock face, webbed rock), `chip_gen.py` angular chips (gravel), `soil_gen.py` fine soil (forest
soil, red soil), `ledge_gen.py` ledges (layered rock: too regular), `ridge_gen.py`, `smooth_gen.py` (failed), `wood_gen.py` boards.
Rule: each surface needs the right family; where there is none, fitting only cheats the loss. The long-narrow-flake recipe (flake
generator, `cell_aspect` 2-4, size cap taken from the object view, `SW_WEIGHT` 0.5) fixed pine and ash.

## Pitfalls learned (do not repeat)
- A lower loss often made a worse picture: fits make features bigger or simpler. Cap scale parameters from a measurement.
- Fit at the scale of the object, not on crops (the rock face's cracks live across 1-2 m).
- Non-square photographs: pass the tile size of the long side; check `cm_per_px`. The palm and cedar are 1024 x 2048; in the bark
  atlas they were squeezed (`tall_slot`, `tall_palm`).
- Colour must not come from a height that is a fit artefact (the wood ripples): paint the colour as the material.
- Height clipped to a constant shows as flat grey: widen the stored height range (`PlateBaker`).
- Noise cells under about 3 px (0.5 cm at 0.2 cm/px) make a pixel MOSAIC at zoom and in the parallax march; thresholded bilinear
  noise gives axis-aligned L-shaped marks. For fine detail use a warped noise (the warp breaks the grid) plus a per-pixel hash
  grain; keep the HEIGHT fine octaves at 1 cm and up.
- The object view hides errors the squares show (ash was black-and-cream at twice the photograph's contrast on the squares).
- Edits that did not apply: ALWAYS grep the result; a `&&` chain does not stop on a failing lint (run gdlint on its own first).
- Do not judge from one screenshot; do not tune a default (oak, maple, cedar) without showing the user.

## Checks, commit, push
- Lint: `E:/Temp/claude/lintenv/Scripts/gdlint.exe systems tests shaders` (gdlint 4.5.0; line <= 100, file <= 1000 lines).
  `scripts/planet_check.sh` needs gdlint on PATH: `PATH="/e/Temp/claude/lintenv/Scripts:$PATH" bash scripts/planet_check.sh`
  (22 checks, ~10 min) then `bash scripts/visual_check.sh` (6 pictures). Both pass at the time of writing. They run HEADLESS,
  where the baking is skipped: they only prove nothing broke.
- Performance: `planet_lab.tscn -- --plants --grounded --forest-walk=30 --fixed-fps 60` (grep FOREST_WALK), with and without
  `PLANET_PROCEDURAL_ALL=1`. One Godot instance at a time (stray instances corrupt GPU timings).
- Commit after every step, `GIT_TERMINAL_PROMPT=0 timeout 120 git push`, never commit `project.godot` or
  `assets/models/kaykit_fantasy_weapons/weapons_bits_texture.png.import`. Update `AGENTS.md` and these task files with each round.
- Fit results go in `tools/bark/fits/*.json` (keep the good ones, delete the failed ones), sheets in `tools/bark/fits/sheets/`.

## Progress log (2026-10-24, after the handover was first written)
Each item was judged on `square_compare.tscn` only (colour and/or 2x lit height); none was checked in the object view.
- Red soil: warmer tan sand, brick-red lumps (less orange), finer dark grit (`soil_bake.gdshader`); lit-height relief weights lowered
  (was twice as contrasty as the photograph).
- Leaf litter: `BarkBaker.BRIGHTNESS` 0.85 to 0.72 (mean matches the photograph). Still too few green leaves, leaves blocky.
- Gravel: crumbly relief between the stones (`chip_bake.gdshader`, warped noise at 1 and 2.2 cm).
- Boulder: `LumpBaker.CALM` (fine and mid relief x0.5) and smooth rimmed lobes (`rim_lobes` uniform, `LumpBaker.RIM_LOBES`).
- Rock rubble: fragments tilted and bevelled instead of flat tiles (`lump_bake.gdshader`, affects every lump rock).
- Mottled rock: a few long wiggly cracks (`wiggle_cracks`, `LumpBaker.WIGGLE_CRACKS`). A straight-crack network was tried and dropped
  (polygon net).
- Pitted rock: thinner cracks, smaller steps between plates (`plate_bake.gdshader`); fat shadow wedges at some crack ends remain.
- NOT verified: `planet_check` / `visual_check` were not re-run for these changes (a run was started and then stopped, so there is no
  result). Run both before treating the state as checked.

## What to do next (ordered)
1. The user looks at the squares and `procedural_all` and says which sets become the default.
2. Differences left: leaf shapes (blocky, too few green), boulder plates (photograph's are larger and chain together), mottled rock (softer than the photograph), pitted rock (shadow wedges), ash (warm and shiny), a few cracks with a fat shadow (pitted rock), rock swirls and
   lichen, wood (grain not bent round knots; ripple height), gravel (too few stones, terrazzo look), red soil (larger angular red
   chips), palm height detail.
3. Birch and rock slot 5 need a new family: thin overlapping horizontal strips plus splits (birch); a slab with slab joints
   (horizontal lines with stepped ledges) (rock slot 5).
4. When everything is accepted: delete the photographs (`assets/textures/bark/bark_atlas.png`, `rock/rock_atlas.png`,
   `ground/scans/*`) and the opt-in switches; keep `tools/bark` as the source of the fits.

## Boulder round (2026-10-24, later): measure the data, trace the layout
Found while working on `rock_boulder_dry` (lump rock, `lump_bake.gdshader`, `rim_lobes` branch only; other rocks unchanged):
- **Look at numbers, not only pictures.** `tools/bark/measure_boulder.py <photo disp> <bake png> 180` (and `check_boulder.sh`, which bakes with
  `square_compare ... --save-bake=PATH` first) prints relief by wavelength, slope quantiles, how steep and how many the small features are, the
  mean edge profile and how evenly the roughness is spread. It showed the relief per size already matched and the real gap was **very steep
  small features** (the photograph has 11x more pixels with slope > 0.2 per cm): fixed with `speck_cover` / `speck_depth`.
- **The lobes were upside down.** The step measured inside a lobe against a ring round it is NEGATIVE in the photograph's displacement (the
  plates are lower than their surroundings); ours were raised, so every lit outline had its bright and dark sides swapped. `plateau` is now
  negative (-1.4). Check the sign of a feature from the data before tuning its size.
- **The boulder's numbers are `BoulderParams.LIST`** (29 hand-set values, `systems/world_gen/boulder_params.gd`, shader array `bp`); the square
  scene shows a slider for each on the boulder (R reset, C copy the values; the bake redoes itself when a slider is let go).
- **Traced features** (`tools/bark/extract_features.py` -> `systems/world_gen/boulder_features.gd`, generated): 7 lobes traced BY HAND on
  `fits/trace_grid.png` (outlines in `HAND_LOBES`, smoothed, 48 vertices; the step of each measured from the height) and the 87 strongest
  small pits/bumps found automatically. The bake shader draws them at the photograph's own places (`traced_features` 1 = on,
  `traced_gain`, `traced_soft_cm`; the procedural lobes, ridge and pits are then off). With them on: edge step 0.214 vs 0.210, ramp width
  2.29 vs 2.29 cm, strong-edge points 4.0 vs 4.0 per 10k px, relief per size within about 10 %.
- **Not done:** only 7 of the photograph's lobes are traced (the big arch lobes round the pill, the left scallops, the crumbly bands);
  trace more in `HAND_LOBES`, or use the traced shapes as a library of stamps placed at random positions for a non-repeating version;
  the procedural crumbly patches sit in other places than the photograph's; the pits draw as small rings; automatic lobe segmentation
  (edge cells, thresholding the smoothed height) failed because the outlines are open. `tools/bark/diff_boulder.py` (a differentiable
  fit by gradient descent) did not beat hand tuning: the layout is discrete.
- Nothing from this round is committed and `planet_check` / `visual_check` were not re-run.
- **Hybrid copy of the boulder (later the same day):** `extract_features.py` also writes a 64 x 64 `swell` (the photograph minus the traced lobes,
  averaged to cells, ~4 K numbers) into `boulder_features.gd`; with `traced_features` on, the bake reads it (Catmull-Rom, `swell_at`) as the
  height, draws the traced lobes (steps x `traced_gain`) and the pits on top, and keeps the procedural fine relief. Measured against the
  photograph (`measure_boulder.py`, last line `copy:`): height correlation 0.966, lit-height correlation 0.55 to 0.58 (the fine grain is
  procedural, so it does not line up pixel by pixel), edge step 0.234 vs 0.210. Where the photograph's own detail lives (lit correlation of
  a simplified photograph): a 32 x 32 grid 0.69, 64 x 64 0.79, 128 x 128 0.87, 256 x 256 0.94, so a faithful copy of the fine detail is just a
  small image (`tools/bark/fit_copy.py` tried 400 fitted pits and bumps on top of the coarse swell: no gain). Not done: trace more lobes,
  decide the grid size (64 now), the library-of-stamps version for the planet. The percentile clip in the old loader flattened the brightest
  spots (grey patches): `load` now normalises by min and max.
- **Neural cellular automaton test (same day, `tools/bark/nca_texture.py`, weights `fits/nca_boulder.pt`, 7.8 K numbers, 3000 steps ~ 12 min on the 4090):**
  trained on the boulder's lit height with the VGG Gram style loss (192 px crops). It makes a non-repeating, tiling texture of lumps and pits
  but NOT the photograph: relief at 1.4 to 11 cm is about 5x too strong against its own range, and nothing above about 20 cm exists (relief at
  22/45/90 cm: 0.026/0.014/0.007 against 0.050/0.060/0.049), because each step only sees the neighbours and the style crops are small. It
  reproduces statistics, not the layout. Not adopted. If revisited: a multi-scale loss on whole 1024 tiles, more steps, and the coarse
  swell and traced lobes fed in as fixed input channels (so it only adds detail), trained with a pixel loss on the detail.
- **Automatic lobes (2026-10-24, evening): `tools/bark/sam_lobes.py` + `extract_features.py <disp> 180 <out gd> <overlay> fits/sam_boulder_kept.json`.** Segment Anything (ViT-B, the checkpoint
  in `E:/repo/ComfyUI_windows_portable/ComfyUI/models/sams/`, `segment_anything` already installed) run on a two-light hillshade of the height finds the plates
  (228 raw masks, 77 plausible, 8 kept with a consistent step along the whole border: the pill, the snake lobe, the left plates, the small round ones). The old hand tracing
  (`HAND_LOBES`, 7 lobes) is still in `extract_features.py` as the fallback. Steps that worked: (1) the step is measured LOCALLY (a thin strip inside against one outside,
  median along the border, sign must agree on 70 % of it): a wide ring is spoiled by the soft swells and rejected real lobes; (2) each outline is SNAPPED to the strongest height
  gradient along its normal (+-10 px, then smoothed): outline gradient doubled (0.008 to 0.017), the measured steps went from -0.03 to -0.09; (3) `traced_gain` 1.0
  (higher is worse: 2.0 gave lit correlation 0.47, 3.0 gave 0.40, because a stronger edge a few pixels off hurts more than a faint one that is right) and `traced_soft_cm` 0.6.
  Result on the same measures as the hand-traced version: height correlation 0.966 (same), lit-height correlation 0.563 against 0.553. So the automatic version is as good as the
  hand tracing, with 8 lobes instead of 7 and no manual step: the lobes are in the right places but their edges are still softer than the photograph's.
  Not done: a SAM pass on the colour map (rocks differ in tone as well as height), merging plates SAM joined (the large right-hand region), the crumbly patches and cracks, and running
  it on the other rocks (rock_face_04, rock_08, rock_06) where the same hand-tracing problem would appear.
- **Edge layer (2026-10-24, later): `tools/bark/extract_edges.py` -> `systems/world_gen/boulder_edges.bin` (70 KB, 6 bytes a point), drawn by `LumpBaker._edge_texture`.**
  The lobes alone covered only 21 % of the photograph's strongest edge pixels (top 3 % of the gradient); the rest are open arcs, ridges and plate borders (the arch round the pill,
  the curve under the left plate, the long diagonal at the top), so the bake looked far fainter than the photograph in the height view. The layer: the SHARP detail only (height minus its
  own 7 px blur: the soft swells are the coarse grid's job, taking them again doubled them), non-maximum suppression across the gradient, hysteresis (94th/86th percentile), chains joined
  across 3 px gaps and kept if 40+ edge pixels, points thinned to one per 3 px cell, leaving out the 8 lobe outlines (13 px band). Each point stores x, y, the height step across the edge
  (smoothed +-4 px along the uphill normal) and the normal's angle; the bake draws each as a step profile across its edge (tanh, 1.6 px rise, windowed to +-7 px, a Gaussian along the edge)
  into a 1024 float image added to the height (`edge_layer` slider, 0.85). Done in GDScript at bake time (about 1 s): per the project rule it belongs in C++ if it ships.
  Measured (same measures as before): lit-height correlation 0.563 -> 0.714, the bake's gradient on the photograph's strongest edge pixels 76 % -> 103 %, edge-map correlation
  there 0.41 -> about 0.5. The 99th-percentile gradient of the whole tile is now a bit high (0.0203 against 0.0175: some roughness edges in the top-left are speckly).
  Not done: separating crisp rims from rough texture (the crumbly top-left now gets edges too), a library-of-stamps version (this is a sparse copy of the photograph's lines, so it repeats),
  the same pipeline for the other rocks. `lobe_edge_check.py` prints the edge strength along each lobe outline.
- **Other Poly Haven layers (found 2026-10-24): every material has more maps than the diffuse and displacement the fitting used.** For `rock_boulder_dry`: Rough, AO, nor_gl, nor_dx, arm
  (AO/rough/metal packed), plus .blend/.gltf/.mtlx and EXR/PNG versions (`https://api.polyhaven.com/files/<name>`, 1k jpg at
  `https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/<name>/<name>_<map>_1k.jpg`; rough, ao and nor_gl are downloaded into `tools/bark/bark_downloads/`).
  Looking at them (`E:/Temp/boulder_maps.png` when this was made): the AO map shows every lobe as a crisp grey outline (pill, left plate, snake lobe, the arch), the normal map shows
  the rims sharply, the roughness map shows the lobes and the lichen patches too. The DISPLACEMENT map is the soft one (it comes from the same scan but is smoothed), which is why
  the lobes were faint and the extraction needed so much help. Next: take the edge layer and the lobe outlines from the NORMAL map (the gradient is -n.xy / n.z) and the AO map (cavity
  outlines, a better input for SAM than a hillshade of the height), and use AO and roughness to fit the colour's cavity darkening and the roughness.
- The colour side (state when this was written): `extract_features.py` also writes `systems/world_gen/boulder_colour.bin` (64 x 64 RGB, the photograph's colour divided by the lobe tints)
  and 3 tint numbers per lobe (LOBE_STRIDE 107); the baker and the shader do NOT use either yet, so the colour view is unchanged (a uniform mottle).
- **Correction and the colour side (same day):** the displacement map is NOT soft. `tools/bark/fuse_height.py` rebuilt a height from the normal map (Frankot-Chellappa, scaled to the displacement's gradients,
  the two agree with correlation 0.95 in the 3..10 px band) and combined it with the displacement: the lit pictures are the same and the steepest slopes are, if anything, a little lower. So the
  earlier "the lobes are faint because the displacement is smooth" was wrong; they were faint because only 8 closed lobes were drawn (the edge layer fixed that). What the other layers (AO,
  roughness, normal) are good for is the COLOUR: AO shows the cavity outlines, roughness the patches.
- **Colour (bake: `lump_bake.gdshader`, the end of `fragment()`; data `systems/world_gen/boulder_colour.bin`, 128 x 128 RGB, 49 KB; per-lobe tint in the lobe texture column 50):**
  the photograph's own colour at a coarse scale (divided by the lobe tints so they are not counted twice), the procedural grain and specks on top at 30 % of their contrast, each lobe's tone
  (colour inside against just outside its border, ratio per channel, 0.9 to 1.04: the photograph's lobes differ only slightly in tone), and a darkening or lightening from the edge layer's signed
  profile (cavity). Sliders `colour_swell`, `lobe_tint`, `edge_dark`. Measured against the photograph's diffuse map: mean RGB within 0.003, std 0.076 against 0.088, brightness correlation per block
  0.96 at 64, 32 and 16 px and 0.94 at 8 px. It is soft: the lichen speckle and the thin crisp outlines of the photograph are not there (a 128 grid is 1.4 cm a cell).
  Not done: AO as the source of the cavity darkening and as SAM's input, the roughness map (fit `roughness` the same way, the bake has no roughness channel for the boulder), a finer colour
  grid (256 is 196 KB), a per-pixel colour residual, the same for the other rocks. Important when judging the scene: the editor's already-running game window keeps the OLD bake; close it and
  press F6 again after any change here.
- **Definition of the colour (same day): stored detail is the only real kind.** Measured with the detail energy and the correlation of the band-passed brightness (sigma 1, 2, 4 px) against the photograph:
  procedural grain at full strength gave 124 % of the photograph's detail but correlation 0.02 (noise: more of it looked worse, `colour_detail` 2.0 was a mess); stored colour grids gave
  128: 38 % / corr 0.02 to 0.28; 256 (192 KB): 17 to 56 % / corr 0.19 to 0.59; 512 (768 KB): 34 to 76 % / corr 0.53 to 0.79 with the procedural detail off (`colour_detail` 0, set as the default,
  `COLOUR_GRID=512` env var for `extract_features.py`). The 512 version is clearly closest by eye (lichen patches, plate tones, the pale band). BUT 768 KB raw is BIGGER than the photograph's own
  diffuse jpg (see sizes in the last report): a 512 colour grid is a half-resolution copy of the image, not a procedural recipe. It answers "does the bake look like the photograph" and not
  "can the image file go". For a genuinely procedural colour the options are a generated lichen/stain layer fitted by statistics (the earlier route: matched mean and std, no definition), or a much
  smaller stored colour that is only the large-scale tone plus a generated lichen layer placed from the AO map. Decide before shipping.
- **Procedural colour (decision 2026-10-24: stay procedural, no stored colour image).** The bake's colour is now: a 64 x 64 tone map (12 KB, `COLOUR_GRID=64`, the photograph's colour at about 3 cm) + the generated fine grain + a SECOND PASS
  (`shaders/world/lump_colour_pass.gdshader`, run by `LumpBaker._colour_pass`) that reads the bake's own height and darkens cavities / lightens convex tops at 2.5, 6 and 12 px (`cavity_colour` 1.0,
  `cavity_chroma` 0.3). Measured ceiling: even the PHOTOGRAPH's own height predicts its colour detail with correlation only 0.35 to 0.37 (fine and mid band, `cav6` best; slope 0.0, curvature -0.33),
  and our bake's height only 0.17 to 0.26 (its fine relief is noise that does not line up pixel by pixel), so a height-derived colour adds definition (detail energy 9 % -> 44 to 89 % of the photograph's
  at cavity_colour 0 -> 1) but not correlation (0.19 -> 0.16 at sigma 4). Most of the photograph's colour definition (lichen patches, stains, orange crusts) is independent of its height.
  What is left to try, procedurally: crisp-edged lichen/stain patches (thresholded warped noise, pale and orange, density from a stored low-resolution map), because the photograph's patches have sharp
  borders and ours are soft; a roughness channel from the same logic; the same for the other rocks. The edge layer's points look pixelly in the colour (dots along the cavities): lower `edge_dark`
  or smooth the points. Still stored from the photograph (not procedural): the 64 x 64 height swell, 8 lobe outlines, 52 pits, 12 K edge points, the 12 KB tone map.
- **All the photograph's maps, derived procedurally (2026-10-24, requested: use every layer and judge on the compare scene).** Poly Haven's material has colour, height, roughness, AO, normal (GL/DX) and the ARM repack.
  Measured relations on the photograph's own maps (`tools/bark`, analysis in the session): NORMAL.xy/z = -/+ 20.2 x the height gradient (correlation 0.89 / 0.91); ROUGHNESS is a function of the colour
  (correlation with the red channel -1.00; `rough = -0.266 R^2 - 0.438 R + 1.039`, correlation 0.997, rms 0.006); AO from the multi-scale cavity of the height (radii 1.5, 3, 6, 12, 24 px, positive and negative
  parts, 11 weights in `lump_maps_pass.gdshader`, correlation 0.72). `shaders/world/lump_maps_pass.gdshader` + `LumpBaker.derive_map(image, mode)` make our versions from the bake; in `square_compare` the left
  square shows the photograph's map and the right ours when you press M (`--extra=N --save-maps=PREFIX` for pictures). Our bake's height has the photograph's scale (std 0.1531 vs 0.1538), so the constants carry over.
  Measured against the photograph's maps: roughness mean 0.633 vs 0.634, std 0.072 vs 0.069, correlation 0.64 (limited by the colour's own correlation, since roughness = f(colour)); AO mean 0.929 vs 0.929,
  std 0.023 vs 0.035, correlation 0.38; normal.x/y std 0.089/0.091 vs 0.094/0.100, correlation 0.63/0.64, the two normals differ by 5.5 degrees on average (p90 9.6). Fine detail (sigma 2) carries 67 to 77 % of the
  photograph's energy in each map but correlates only 0.06 to 0.22. Next: AO needs its own source (crevices of the actual layout, e.g. from the lobe outlines and the edge layer); the colour's definition
  limits roughness; the game material should read these maps (the planet's rock atlas uses colour and height only today).
- **AO, second model (2026-10-24):** `tools/bark/ao_fit.py` fits the photograph's AO map on (a) the multi-scale cavity of the height and (b) the stored layout (edge layer value and its signed parts, distance profiles inside
  and outside the 8 lobe outlines at 2, 5, 12 px, the pits). On the PHOTOGRAPH's height: cavities alone 0.718, layout alone 0.476, both 0.743 (the layout adds little where the height is already the real one). On OUR
  bake's height the weights have to be refitted: cavities alone 0.443, + layout 0.535 (+ luminance 0.536; 10 radii 0.540, so the radii are not the limit). `lump_maps_pass.gdshader` now uses the refit weights, the
  edge layer and the lobe outlines (kept by `LumpBaker` for `derive_map`), and puts the contrast back (the fit shrinks the spread to 0.019: gain 1.87 gives 0.036 against the photograph's 0.035).
  Result in the compare scene: AO correlation 0.38 -> 0.54, mean 0.929 both, std 0.036 vs 0.035, but the fine detail (sigma 2) still correlates only 0.06 (66 % of the energy): the lobe borders are now crisp lines
  like the photograph's, the arcs and curved edges outside the 8 lobes and the photograph's fine pits and mottling are not. The ceiling is the height: the photograph's AO was baked from the scan's real geometry.
- **"Low resolution" diagnosed (2026-10-24): the finest scales were empty.** `tools/bark/band_energy_check.py` prints our bake's energy as a percent of the photograph's per feature size (radially averaged power spectrum).
  Before: colour 95 to 101 % from 90 cm down to 5.6 cm, 113 % at 2.8-5.6, 147 % at 1.4-2.8 (blobby), then 24 % at 0.7-1.4 cm and 8 % at 0.35-0.7 cm; height 40 % and 48 % there; normal 42 % and 16 %.
  The colour lost its procedural grain when the stored colour image was removed (`colour_detail` 0). Fix: `micro_texture()` in `lump_bake.gdshader`, warped value noise at `fine_cm` x (1.1, 0.55) plus a per-pixel hash
  (the warp avoids axis-aligned marks), added to the colour (`fine_colour` 0.085) and the height (`fine_height` 0.003, so the derived normal and roughness get it too); `fine_cm` 0.6. After: colour 96 / 122 / 184 / 87 / 69 %
  at 5.6 / 2.8 / 1.4 / 0.7 / 0.35 cm, height 95 / 82 / 127 / 70 / 122 %, normal 74 / 74 / 125 / 80 / 46 %. Remaining: the 1.4 to 2.8 cm band is too strong (184 % in colour: the blobby pits and edge points, and the
  cavity pass), the normal map is still weak at the finest size, and the noise is uncorrelated with the photograph (only the statistics match): crisp cracks, the pink tint patches and exact lichen are still missing.
- **More ways to extract information (2026-10-24): two measurements, one dead end.** (1) Peakiness of the band-passed detail (kurtosis; Gaussian noise is 0): the photograph's COLOUR detail is calm
  (1.5 / 1.0 / 0.7 at 1 / 2 / 4 px) and ours was spiky (3.2 / 5.7 / 3.1: the blobby pits and edge dots); its HEIGHT is very spiky at the finest scale (38.9 / 8.6 / 1.6, a few extreme crisp features on a calm ground)
  and ours is less so (16.1 / 5.9 / 0.9). (2) Layer decomposition: k-means on the smoothed Lab colour (k 4, 5, 6) just slices the tone field by brightness (class areas 9 to 34 %, blobs median 1.5 to 2.4 cm2,
  boundary about 500 px per 1000 px of area): the photograph's colour is a continuous mottled tone field, not discrete kinds of surface, so there are no crisp lichen classes to extract and regenerate for this rock.
  Tuned the colour against the kurtosis: soft limit on the cavity effect (`cavity_clip` 0.03: tanh), the smallest cavity scale weakened (`cavity_small` 0.4), `edge_dark` 0.5, `cavity_colour` 1.4; colour kurtosis 3.2 / 5.7 / 3.1 -> 1.6 / 2.9 / 1.3,
  band energy 103 / 114 / 162 / 84 / 67 % at 5.6 / 2.8 / 1.4 / 0.7 / 0.35 cm. The 1.4 to 2.8 cm excess stays (about 160 to 185 % even with the smallest cavity scale at 0): its source is not the cavity pass (suspects: the
  tone map's cells, the edge layer's dots, the lobe tints). Still to do: sparse sharp features in the height (pit lips, crisp edges: kurtosis 16 -> 39 at 1 px) and the band's source.
- **Source of the 1.4 to 2.8 cm colour excess found (ablation, same day):** the edge layer. Colour band energy at 1.4-2.8 cm: all on 162 %; `edge_dark` 0 131 %; edge layer and its darkening both 0 75 %; `fine_colour` 0 130 %;
  `lobe_tint` 0 no change; `cavity_colour` 0 collapses every band (39 / 20 / 35 %). The layer was drawn as dots 3 px apart with a 2 px spread along the line, so it made bumps. `EDGE_TANGENT_SIGMA` 2 -> 3.5 (smoother along the line):
  colour 1.4-2.8 cm 162 -> 152 % (131 % at `edge_layer` 1.0), colour kurtosis 1.1 / 2.4 / 1.4 (photograph 1.5 / 1.0 / 0.7), strong-edge gradient still 85 % of the photograph's (edge-map correlation 0.48); 5.0 would be smoother but loses edge strength (77 %).
  Height peakiness: rare crisp pits with a sharp lip (new `lip_cover` 0.005, `lip_depth` 0.11, `lip_cm` 0.6, in `lump_bake.gdshader`, drawn in traced mode, which the old pit code is not) lifted the height kurtosis at 1 px from 10.5 to 33.0
  (photograph 38.9; 2 px 5.1 vs 8.6) with `fine_height` 0.0028. Tuning notes: cover 0.004 / depth 0.14 gave 64.8, 0.003 / 0.2 gave 171.7 (the tail is very sensitive), 0.006 / 0.1 gave 29.6.
  Band energy now (colour / height / normal at 5.6, 2.8, 1.4, 0.7, 0.35 cm): 103 119 152 76 66 / 96 87 122 63 146 / 75 80 116 67 48 %. Remaining: the normal map at the finest size, the 0.7 to 1.4 cm height (63 %), the stored pits show as
  clean dark discs in the colour (one sits in the middle of the pill), and `#define` names in `lump_bake.gdshader` must be unique (a duplicate breaks the whole preprocessor and the bake is blank).
- **Pits softened (2026-10-24).** `tools/bark/pit_contrast_check.py <bake>` prints the colour contrast (2 px disc minus 6 to 10 px ring, luminance) at the 52 stored pit positions: photograph mean -0.034 (p10 -0.155, p90 +0.122);
  ours was -0.041 (p10 -0.240, p90 +0.195): the average was right and the spread 1.5x too wide, with bright halos at the lips. With the cavity pass off the pits almost vanish from the colour (spread +-0.08), so the cavity pass is the mechanism. Changes:
  `cavity_up` 0.5 (convex parts brighten half as much as cavities darken), `cavity_clip` 0.015 and `cavity_colour` 2.0 (a harder soft limit with more gain, which keeps the mid bands: colour 94 / 101 / 133 / 73 / 64 %), and the real fix for the
  look: the pit outlines were perfect discs (a radial profile), so the stored pits and the new lip pits now get an irregular outline (`pit_irregular` 0.6, a warp of the distance by value noise). Pit colour contrast now mean -0.021 (p10 -0.174, p90 +0.217):
  the bright end did not come down with these controls (its source at some pit positions is not the cavity term: the ring sits in neighbouring halos), so the spread is still wider than the photograph's, but the pits no longer read as round black dots.
- **Thin cracks (2026-10-24): `tools/bark/extract_cracks.py` -> `systems/world_gen/boulder_cracks.bin` (1.9 KB per 330 pixels, 6 bytes a pixel; 6,576 crack pixels, 38 KB).** A multi-scale Hessian valley detector (sigma 0.9 / 1.4 / 2.0 px) on the colour's luminance and on
  the photograph's AO map, hysteresis (99th / 94th percentile of the combined z-score), thinning by non-maximum suppression, chains kept only if long and thin (extent >= 38 px, area <= 13 x extent) and with the lobe outlines cut out. Tuning notes:
  the first loose pass drew the lobe outlines and the lichen clutter (13,448 pixels), a strict pass found almost nothing (1,805); the middle setting finds the long diagonals at the top and middle and the one at lower left, plus short fragments.
  Measured on the photograph (crack core minus the 7 to 15 px ring): luminance -0.027 (-4.6 %), AO -0.048, roughness +0.022, HEIGHT only -0.003: the cracks are colour and occlusion features. In the bake they are drawn into the colour
  (`crack_colour`, x strength), a hair of height (`crack_depth` 0.004), the AO (`w_crack` in `lump_maps_pass.gdshader`), and roughness follows from the colour. They were removed from the edge layer (`extract_edges.py ... boulder_cracks.bin`, 13 px band: 12,000 -> 10,126 points)
  because as edges they made a fuzzy 8 to 10 px band where the photograph has a crisp 2 px line. `crack_colour`: the data says 0.07 to match the average (the contrast averages over a 3 px core with off-line pixels), the picture says 0.25 to read as the
  photograph's thin lines at 3x zoom; 0.25 is the default. Checks with `crack_contrast_check.py`. Not done: the photograph's cracks continue further than the detector follows them (the long diagonal at the top is found for about half its length), the
  stored cracks repeat with the tile, and a generator of cracks (branching, length and spacing from statistics) would make them non-repeating.
- **The boulder at game distance (2026-10-24, `rock_view.tscn -- --baked --dist=D --shot=PATH`).** Two things to know about the object view: `--baked` only bakes our lumps when `PLANET_PROCEDURAL_LUMPS=1` is set (otherwise it shows the
  photographed atlas again: my first comparison was photograph against photograph, 0.13 to 0.73 mean difference), and that switch bakes all four lump slots (0 boulder, 1 rock face, 2 mottled, 3 webbed), three of which are older work and look speckly.
  New test switch `PLANET_LUMP_SLOTS=0` (RockBaker `_lump_wanted`) limits it to the boulder. Results with the boulder alone at 6 m and 2.5 m (the rock meshes, real shader, shadows): mean difference from the photographed atlas 0.99 and 1.14
  of 255, only 0.6 % and 1.6 % of the pixels change by more than 12/255, and the rocks that use slot 0 look like the photographed ones (same tone, same cracks, a little less smooth on the grey rock). With all four lump slots on, the
  difference is 7.9 to 10.2 (the other three read as darker and speckled at 2.5 m). So at the distances the game shows rocks from, the finished boulder is hard to tell from the photograph; the remaining visible differences are in the
  other three lump rocks and in how many rocks use which slot, not in the boulder's finest detail.
