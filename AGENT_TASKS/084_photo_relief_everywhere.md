# 084 Photographed relief (parallax occlusion) on everything, not only trees

Status 2026-10-22: done for tree bark (six Poly Haven barks, 35ca1d6). Rules and the recipe are in
AGENTS.md ("Surface relief from photographs"). This file lists where to apply it next, in the order
I would take them. For each one: download the 1k diffuse + displacement, measure the real size in
metres, add a slot to an atlas (a new atlas per material family, not one huge one), sample it in
the shader with a mip from the distance, gate the march by distance, compare with the photograph,
check `--fps` and the visual baselines, write findings.

1. Rocks and cliffs (`flora_wind.gdshader` stone branch, `planet_cliff.gdshaderinc`): rock_wall_*,
   rock_boulder_*, mossy_rock, dark_rock, rocks_ground_*; triplanar sampling because rocks have no
   clean UV; the current stone is noise strata and looks the same everywhere.
2. Terrain scans (`planet_ground.gdshader`): the scans (`scan_gravel_*`, `scan_red_*`, `scan_leaf_*`)
   are already photographic; check they carry a height and that the parallax uses it. Candidates:
   forest_ground_*, forest_leaves_*, rocks_ground_*, sand and mud sets. User's sand look is theirs.
3. Birch and the remaining bark kinds: a birch photo; a second photo per kind so a huge trunk does
   not repeat; lichen and moss as an own layer over the photo.
4. Buildings and props (planks, plaster, concrete, metal): the `planks` branch of the plant shader
   and the prop materials.
5. Characters (skin pores, cloth weave, leather): needs the UV layout checked (stretch, seams,
   mirrored halves); a parallax of a few tenths of a millimetre is enough; normal maps may be the
   better tool here. Ask before touching the character shaders.
6. Tooling: a script that downloads a named Poly Haven material, reports its real size and builds
   the atlas slot (today the downloads and the slot list are by hand); WebP for the atlas to cut
   the repo size; a viewer scene for rocks like `bark_view`.

Measured costs to keep in mind: bark photos made the forest lab view GPU 15.5 -> 14.5 ms; the
procedural height it replaced cost more than a texture read. Do not add a per-pixel loop without a
distance gate.

## Done 2026-10-22: rocks (item 1)
`assets/textures/rock/rock_atlas.png` (+ .import), six Poly Haven rocks (rock_boulder_dry, rock_face_04,
rock_08, rock_06, rock_pitted_mossy, dark_rock_02; masonry walls were not used), built with
`tools/build_bark_atlas.gd --out=... --slots=...` (now generic). In `flora_wind.gdshader` the stone
branch uses `rock_sample`: the photo projected along the rock's three axes (no UV), weighted by the
surface normal, at its real size (`obj_scale`), a slot chosen from the mesh colour (dark, warm,
pale...) and a hash, the height as the screen-space bump. `rock_photo_on` = 0 returns the old noise
stone. Viewer: `tests/manual/world/rock_view.tscn -- --dist=9 [--procedural]`. The procedural
stone had cartoon crack loops and an even speckle; the photographed one has weathering, veins and
real stone colours. GPU in the forest lab view unchanged (14.6 to 15.2 ms). Full planet_check and
visual check pass. Not verified: rocks in the desert and snow biomes, the large cliffs of the
terrain (planet_cliff.gdshaderinc is separate), the stone of buildings.
Lesson: a tool script that errors in `_init` does not quit by itself (it hung 8 minutes): make
tools `quit()` on every path. Next in 084: the terrain scans / cliffs, birch, buildings.

## Procedural rocks (2026-10-23, autonomous run)
`tools/bark/rock_gen.py` (numba, 24 params) + `export_rock.py` -> `systems/world_gen/rock_fits.gd`;
`shaders/world/rock_bake.gdshader` (tiling GLSL), `RockBaker` (bake + make_array, same as the bark),
`PlanetWorld._bake_the_bark` now also bakes rocks. One rock fitted so far: rock_face_04 (slot 1: the brown
cracked rock); the other five slots keep the photographs. Baked tile vs photo: blocks of a similar size
cut by dark cracks with rubble along them; the tile reads as a more regular, sandier cousin of the photo
(whole-number block counts make the Voronoi grid-like; lighting halos on the crack rims were clamped).
In the rock viewer (`rock_view.tscn -- --dist=9 --baked`) the boulders look like the photographed ones.
Next: fit the other five rocks (rock_boulder_dry, rock_08, rock_06, rock_pitted_mossy, dark_rock_02)
with `rock_gen.py fit` (needs the photos' real sizes), export all, compare, then remove the atlas.

## Rocks, all six fitted (2026-10-23) - baked result NOT good enough, the game keeps the photographs
Fits (lit loss, 250 generations each): rock_boulder_dry 0.92, rock_face_04 0.99, rock_08 0.57, rock_06 1.22,
rock_pitted_mossy 0.84, dark_rock_02 0.71; exported with `export_rock.py` into `rock_fits.gd`. In the rock
viewer (`rock_view.tscn --dist=9 --baked` against the photographed rocks) the baked rocks show a visible
pixel mosaic (the 2.5 cm rubble layer and the grain at the tile's 0.2 cm/px) and a regular network of thin
cracks like a turtle shell; the photographs look far better. So `PlanetWorld` bakes the rocks only with
env `PLANET_PROCEDURAL_ROCKS=1`. To fix: remove the rubble layer from rocks that have none, bake at 2048
or filter the high frequencies, make crack networks irregular (vary `cell_cm` by zone), fit the rubble
layer only where the photo has it, and drive the crack width by distance. Same loop: change, refit, look.
