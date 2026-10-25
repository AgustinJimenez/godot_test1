"""One command per surface for the photo -> procedural generator chain (AGENT_TASKS/090, step 2).

It does not add new maths: it runs the scripts that were run by hand (measure_scale, fit_*, export_*, colour_match, square_compare).

  python tools/bark/pipeline.py list                       the surfaces, their family, fit script and whether they are in the game
  python tools/bark/pipeline.py measure <surface>          measure_scale.py with the surface's tile size
  python tools/bark/pipeline.py fit <surface> [generations]  the surface's fit script (long: minutes to hours)
  python tools/bark/pipeline.py export <surface> [--check]   rewrites the family's systems/world_gen/*_fits.gd from tools/bark/fits/*.json;
                                                             --check writes to a temp file and diffs against the committed one
  python tools/bark/pipeline.py match <surface> ...          raw bake, colour_match.py, class cache refresh, picture in E:/Temp/tx (needs Godot)
  python tools/bark/pipeline.py run <surface> [--fit]        measure, (fit), export, match
  python tools/bark/pipeline.py review <surface> [picture]   the labelled review sheet + checklist for an agent (tools/bark/review.py; then `review.py record`)
  python tools/bark/pipeline.py fit-torch <surface> [steps] [--adopt]   gradient fit (torch generators: plates, flake bark), a compare
                                                             picture, and with --adopt export + match (plates only; bark fits stay candidates)

Run it from anywhere; it works from the repository root. Set GODOT to the editor executable (default E:/Godot/4.7.2/...).
The export scripts rewrite a whole family file, so the entries (names and tile sizes) are read back from the committed file
and passed again: exporting one surface keeps its neighbours.
"""
import difflib
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BARK = os.path.join(ROOT, "tools", "bark")
DOWNLOADS = "tools/bark/bark_downloads"
PYTHON = os.environ.get("PIPELINE_PYTHON", "C:/Users/agus_/anaconda3/python.exe")  # (the scripts need numpy, scipy, opencv, numba, torch, cma: this anaconda has them; the default python does not)
GODOT = os.environ.get("GODOT", "E:/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe")
PICTURES = os.environ.get("PIPELINE_OUT", "E:/Temp/tx")

# family -> the generated file, the export script, and how the export script wants an entry
FAMILIES = {
    "bark": ("systems/world_gen/bark_fits.gd", "export_fit.py", "kind"),
    "litter": ("systems/world_gen/litter_fits.gd", "export_fit.py", "kind"),
    "plate": ("systems/world_gen/plate_fits.gd", "export_plate.py", "plain"),
    "ring": ("systems/world_gen/ring_fits.gd", "export_ring.py", "plain"),
    "lump": ("systems/world_gen/lump_fits.gd", "export_lump.py", "plain"),
    "chip": ("systems/world_gen/chip_fits.gd", "export_chip.py", "plain"),
    "soil": ("systems/world_gen/soil_fits.gd", "export_soil.py", "plain"),
    "wood": ("systems/world_gen/wood_fits.gd", "export_wood.py", "plain"),
}

# surface -> family, the 0-based index in square_compare's SURFACES, the fit command as an argv template ({folder} {name} {tile} metres {gens}) or None, the game switch
SURFACES = {
    "bark_willow_02": ("bark", 0, None, "default"),
    "trident_maple_bark": ("bark", 1, None, "default"),
    "japanese_cedar_bark": ("bark", 2, None, "default"),
    "tree_bark_03": ("bark", 3, ["fit_ash_long.py", "{folder}", "{gens}"], "PLANET_PROCEDURAL_ASH"),
    "pine_bark": ("bark", 4, ["fit_pine_long.py", "{folder}", "{gens}"], "PLANET_PROCEDURAL_PINE"),
    "palm_tree_bark": ("ring", 5, ["fit_palm.py", "{folder}", "{gens}"], "PLANET_PROCEDURAL_PALM"),
    "forest_leaves_03": ("litter", 6, ["fit_litter.py", "{name}", "{tile}", "{gens}", "{folder}"], "PLANET_PROCEDURAL_LITTER"),
    "gravel_soil": ("chip", 7, ["fit_gravel2.py", "{folder}", "{gens}"], "PLANET_PROCEDURAL_GRAVEL"),
    "red_soil": ("soil", 8, ["fit_red_soil.py", "{folder}", "{gens}"], "PLANET_PROCEDURAL_RED"),
    "rock_boulder_dry": ("lump", 9, ["fit_rock_lump.py", "{folder}", "{name}", "{tile}", "{gens}", "plain"], "PLANET_PROCEDURAL_LUMPS slot 0"),
    "rock_face_04": ("lump", 10, ["fit_rock_lump.py", "{folder}", "{name}", "{tile}", "{gens}"], "PLANET_PROCEDURAL_LUMPS slot 1"),
    "rock_08": ("lump", 11, ["fit_rock_lump.py", "{folder}", "{name}", "{tile}", "{gens}", "plain"], "PLANET_PROCEDURAL_LUMPS slot 2"),
    "rock_06": ("lump", 12, ["fit_rock_lump.py", "{folder}", "{name}", "{tile}", "{gens}"], "PLANET_PROCEDURAL_LUMPS slot 3"),
    "rock_pitted_mossy": ("plate", 13, ["fit_rock_cells.py", "{folder}", "{name}", "{tile}", "{gens}"], "PLANET_PROCEDURAL_CELLS slot 4"),
    "oak_wood_planks": ("wood", 14, ["fit_wood2.py", "{folder}", "{gens}"], "PLANET_PROCEDURAL_WOOD"),
}


def run(command, **kwargs):
    print("$", " ".join(str(c) for c in command), flush=True)
    return subprocess.run(command, cwd=ROOT, check=True, **kwargs)


def entries(family):
    """The (name, tile metres, kind or None) entries of a family's generated file, in file order."""
    text = open(os.path.join(ROOT, FAMILIES[family][0]), encoding="utf-8").read()
    result = []
    starts = list(re.finditer(r'\n\t\t"([a-z_0-9]+)": \{\n', text))
    for i, match in enumerate(starts):
        body = text[match.end():starts[i + 1].start() if i + 1 < len(starts) else len(text)]
        tile = re.search(r'"tile_cm": ([0-9.]+)', body)
        kind = re.search(r'"kind": (\d+)', body)
        if tile:
            result.append((match.group(1), float(tile.group(1)) / 100.0, int(kind.group(1)) if kind else None))
    return result


# surfaces whose generated file cannot be reproduced from the fit data right now, and why (export refuses unless --force)
STALE = {
    "oak_wood_planks": "wood_gen.PARAMS gained drift_amp/drift_cm after wood_fits.gd was exported: a re-export changes the number order and "
                       "needs wood_bake.gdshader (and WoodFits.KEYS use) updated first",
}
# generated files whose header the export script writes for the bark family (the litter file is made by export_fit.py too)
HEADERS = {"litter": ("class_name LitterFits", "## The fitted generators of photographed leaf litter (parameters, height range, colour model)")}


def fix_header(family, path):
    if family not in HEADERS:
        return
    text = open(path, encoding="utf-8", newline="").read()
    crlf = chr(13) + chr(10)
    nl = crlf if crlf in text else chr(10)
    lines = text.split(nl)
    lines[1], lines[4] = HEADERS[family]
    open(path, "w", encoding="utf-8", newline="").write(nl.join(lines))


def export(surface, check=False, force=False):
    if surface in STALE and not force:
        print("STALE (not exported): " + STALE[surface])
        return False
    family = SURFACES[surface][0]
    gd, script, style = FAMILIES[family]
    specs = []
    for name, tile, kind in entries(family):
        specs.append("%s:%g:%d" % (name, tile, kind) if style == "kind" else "%s:%g" % (name, tile))
    if not specs:
        sys.exit("no entries found in " + gd)
    target = gd
    if check:
        handle, target = tempfile.mkstemp(suffix=".gd")
        os.close(handle)
    run([PYTHON, os.path.join(BARK, script), DOWNLOADS, target] + specs)
    fix_header(family, target)
    if check:
        old = open(os.path.join(ROOT, gd), encoding="utf-8").read().replace("\r\n", "\n").splitlines()
        new = open(target, encoding="utf-8").read().replace("\r\n", "\n").splitlines()
        os.remove(target)
        diff = list(difflib.unified_diff(old, new, gd, "re-exported", lineterm="", n=0))
        print("IDENTICAL to the committed file" if not diff else "DIFFERENT: %d diff lines" % len(diff))
        for line in diff[:40]:
            print(line)
        return not diff
    return True


def measure(surface):
    family, _, _, _ = SURFACES[surface]
    tile = {name: t for name, t, _ in entries(family)}.get(surface)
    if tile is None:
        sys.exit("%s is not in %s" % (surface, FAMILIES[family][0]))
    run([PYTHON, os.path.join(BARK, "measure_scale.py"), DOWNLOADS, surface, "%g" % tile])


def fit(surface, generations):
    family, _, command, _ = SURFACES[surface]
    if command is None:
        sys.exit("%s has no fit script wired (its fit was made by bark_perceptual.py / fit_bark.py by hand)" % surface)
    tile = {name: t for name, t, _ in entries(family)}.get(surface, 1.0)
    args = [a.format(folder=DOWNLOADS, name=surface, tile="%g" % tile, gens=generations) for a in command[1:]]
    run([PYTHON, os.path.join(BARK, command[0])] + args)


# surface -> the gradient-fit script (torch generators, parity-tested against the bake) and the json it writes
TORCH_FITS = {
    "rock_pitted_mossy": ("fit_plates_torch.py", "{name}_plate_torch.json", "{name}_plate.json"),
    "pine_bark": ("fit_bark_torch.py", "{name}_torch.json", None),
    "tree_bark_03": ("fit_bark_torch.py", "{name}_torch.json", None),
    "japanese_cedar_bark": ("fit_bark_torch.py", "{name}_torch.json", None),
    "bark_willow_02": ("fit_bark_torch.py", "{name}_torch.json", None),
    "trident_maple_bark": ("fit_bark_torch.py", "{name}_torch.json", None),
}


def fit_torch(surface, steps, adopt=False):
    """Gradient fit (minutes). The json goes to tools/bark/fits/<name>_*torch.json; with adopt=True a plate fit also becomes the
    surface's fit json (so `export` writes it), the flake bark fits are only candidates (bark_fits.gd is exported from the black-box json)."""
    if surface not in TORCH_FITS:
        sys.exit("%s has no torch generator yet (ports so far: plates, flake bark)" % surface)
    script, produced, adopted = TORCH_FITS[surface]
    run([PYTHON, os.path.join(BARK, script), DOWNLOADS, surface, str(steps)])
    made = os.path.join(BARK, "fits", produced.format(name=surface))
    print("fit json:", made)
    if adopt and adopted:
        import shutil
        shutil.copyfile(made, os.path.join(BARK, "fits", adopted.format(name=surface)))
        print("adopted as", adopted.format(name=surface))
    elif adopt:
        print("note: a flake bark torch fit is a candidate only; see AGENT_TASKS/090 step 7 for what adopting it needs")
    return made


def compare(surface, fit_json):
    """The judge picture: photo | generated (| current), for a torch fit json."""
    run([PYTHON, os.path.join(BARK, "compare_torch.py"), surface, fit_json, "%s/compare_%s.png" % (PICTURES, surface)])
    print("compare picture:", "%s/compare_%s.png" % (PICTURES, surface))


def review(surface, picture=None):
    """The review sheet for an agent (tools/bark/review.py): no model is called; the agent reads the picture and records a verdict."""
    run([PYTHON, os.path.join(BARK, "review.py"), "sheet", surface] + ([picture] if picture else []))


def match(surfaces):
    """Raw bakes (no colour match), the fit from them, a refreshed class cache, then the final pictures."""
    os.makedirs(PICTURES + "/one", exist_ok=True)
    scene = "res://tests/manual/world/square_compare.tscn"
    for surface in surfaces:
        index = SURFACES[surface][1]
        run([GODOT, "--path", ROOT, scene, "--", "--surface=%d" % index, "--no-match",
             "--save-bake=%s/one/allbake_%d.png" % (PICTURES, index), "--shot=%s/one/raw_%d.png" % (PICTURES, index)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
    run([PYTHON, os.path.join(BARK, "colour_match.py"), PICTURES + "/one"])
    run([GODOT, "--headless", "--editor", "--quit", "--path", ROOT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
    for surface in surfaces:
        index = SURFACES[surface][1]
        run([GODOT, "--path", ROOT, scene, "--", "--surface=%d" % index, "--shot=%s/n%d.png" % (PICTURES, index)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
        print("picture:", "%s/n%d.png" % (PICTURES, index))


def main(argv):
    if len(argv) < 2 or argv[1] not in ("list", "measure", "fit", "fit-torch", "export", "match", "run", "review"):
        print(__doc__)
        return 1
    command = argv[1]
    if command == "list":
        for name, (family, index, fit_command, game) in SURFACES.items():
            print("%-22s sq %2d  %-7s fit: %-18s game: %s" % (name, index + 1, family, fit_command[0] if fit_command else "(by hand)", game))
        return 0
    if len(argv) < 3 or argv[2] not in SURFACES:
        print("surface?", ", ".join(SURFACES))
        return 1
    surface = argv[2]
    if command == "measure":
        measure(surface)
    elif command == "fit":
        fit(surface, int(argv[3]) if len(argv) > 3 and argv[3].isdigit() else 200)
    elif command == "review":
        review(surface, argv[3] if len(argv) > 3 else None)
    elif command == "fit-torch":
        steps = int(argv[3]) if len(argv) > 3 and argv[3].isdigit() else 120
        made = fit_torch(surface, steps, "--adopt" in argv)
        compare(surface, made)
        if "--adopt" in argv and TORCH_FITS[surface][2]:
            export(surface)
            match([surface])
    elif command == "export":
        return 0 if export(surface, "--check" in argv, "--force" in argv) else 2
    elif command == "match":
        match([s for s in argv[2:] if s in SURFACES])
    elif command == "run":
        measure(surface)
        if "--fit" in argv:
            fit(surface, 200)
        export(surface)
        match([surface])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
