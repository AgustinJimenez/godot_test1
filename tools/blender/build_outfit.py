"""Build an outfit's garments from their recipes (docs/superpowers/specs/2026-11-26-garment-recipes-design.md), inside out.

blender -b --factory-startup --python tools/blender/build_outfit.py -- <folder with {male,female}_body.glb> <folder with {gender}_rig.json and
    {gender}_rigged.glb> <outfit.json> [--gender=male|female]
Writes <gender>_<outfit>_<garment>.glb into the first folder. Each garment is kept outside the garments under it that were built in this run.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from garments.fit import Body, build_garment, layer_surface   # noqa: E402
from garments.recipe import load_outfit   # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GARMENTS_DIR = os.path.join(ROOT, "assets", "models", "humans", "garments")


def build_outfit(folder, rig_folder, gender, outfit):
	body = Body(rig_folder, gender)
	written, lower = [], []
	for recipe in outfit.garments:   # (sorted by layer: inside out)
		out_path = os.path.join(folder, "%s_%s_%s.glb" % (gender, outfit.name, recipe.name))
		below = [entry for entry in lower if entry[0].layer < recipe.layer]
		build_garment(os.path.join(folder, "%s_body.glb" % gender), out_path, body, recipe, below)
		lower.append((recipe, layer_surface(out_path)))
		written.append(out_path)
	return written


args = sys.argv[sys.argv.index("--") + 1:]
folder, rig_folder, outfit_path = args[0], args[1], args[2]
genders = [a.split("=", 1)[1] for a in args[3:] if a.startswith("--gender=")] or ["male", "female"]
outfit = load_outfit(outfit_path, GARMENTS_DIR)
for gender in genders:
	build_outfit(folder, rig_folder, gender, outfit)
print("DONE")
