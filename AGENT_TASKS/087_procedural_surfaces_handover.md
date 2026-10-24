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

## What to do next (ordered)
1. The user looks at the squares and `procedural_all` and says which sets become the default.
2. Differences left: leaf shapes (blocky), ash (warm and shiny), a few cracks with a fat shadow (pitted rock), rock swirls and
   lichen, wood (grain not bent round knots; ripple height), gravel (too few stones, terrazzo look), red soil (larger angular red
   chips), palm height detail.
3. Birch and rock slot 5 need a new family: thin overlapping horizontal strips plus splits (birch); a slab with slab joints
   (horizontal lines with stepped ledges) (rock slot 5).
4. When everything is accepted: delete the photographs (`assets/textures/bark/bark_atlas.png`, `rock/rock_atlas.png`,
   `ground/scans/*`) and the opt-in switches; keep `tools/bark` as the source of the fits.
