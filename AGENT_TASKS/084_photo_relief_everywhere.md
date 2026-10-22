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
