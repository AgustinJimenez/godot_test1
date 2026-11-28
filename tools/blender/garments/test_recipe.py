"""Tests for the garment recipes and outfits (plain Python, no Blender): python -I tools/blender/garments/test_recipe.py"""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # (tools/blender: the garments package)
from garments.recipe import MATERIALS, RecipeError, load_outfit, load_recipe   # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GARMENTS = os.path.join(ROOT, "assets", "models", "humans", "garments")
OUTFITS = os.path.join(ROOT, "assets", "models", "humans", "outfits")


def write_recipe(folder, name, **changes):
	with open(os.path.join(GARMENTS, "shirt.json"), encoding="utf-8") as handle:
		data = json.load(handle)
	data["name"] = name
	for key, value in changes.items():
		if value is None:
			data.pop(key, None)
		else:
			data[key] = value
	path = os.path.join(folder, name + ".json")
	with open(path, "w", encoding="utf-8") as handle:
		json.dump(data, handle)
	return path


class RecipeTest(unittest.TestCase):
	def test_shirt_values(self):
		r = load_recipe(os.path.join(GARMENTS, "shirt.json"))
		self.assertEqual(r.name, "shirt")
		self.assertEqual(r.layer, 1)
		self.assertEqual(r.shape, "shell")
		self.assertEqual(r.covers, ["torso", "upper_arm", "forearm"])
		self.assertEqual(r.top, {"at": "neck"})
		self.assertEqual(r.neckline, {"round_ease": 0.01, "v_depth": 0.085, "v_width": 0.07})
		self.assertEqual(r.bottom, {"below_hips": 0.0})
		self.assertEqual(r.sleeve_end, 0.9)
		self.assertEqual(r.ease, {"torso": 0.016, "limb": 0.019, "flare_torso": 0.012, "flare_limb": 0.0})
		self.assertEqual(r.openings, {"neck": "bound", "sleeves": "open", "hem": "open"})
		self.assertEqual(r.material, "linen")
		self.assertFalse(r.belt)
		t = load_recipe(os.path.join(GARMENTS, "trousers.json"))
		self.assertEqual((t.layer, t.top, t.leg_end, t.material, t.belt), (0, {"at": "waist", "above_hips": 0.035}, 0.9, "wool", True))
		self.assertEqual(t.ease, {"torso": 0.012, "limb": 0.012, "flare_torso": 0.0, "flare_limb": 0.01})
		self.assertEqual(t.openings, {"waist": "bound", "cuffs": "bound"})
		self.assertEqual(sorted(MATERIALS), ["leather", "linen", "mail", "shoe_leather", "wool"])
		self.assertEqual(MATERIALS["linen"].bridge, 0)   # (cloth follows the body; stiff materials span its hollows)
		self.assertGreater(MATERIALS["leather"].bridge, 0)

	def test_outfit_sorted(self):
		with tempfile.TemporaryDirectory() as folder:
			path = os.path.join(folder, "o.json")
			with open(path, "w", encoding="utf-8") as handle:
				json.dump({"name": "o", "garments": ["shirt", "trousers"]}, handle)
			outfit = load_outfit(path, GARMENTS)
			self.assertEqual([g.name for g in outfit.garments], ["trousers", "shirt"])
		villager = load_outfit(os.path.join(OUTFITS, "villager.json"), GARMENTS)
		self.assertEqual(villager.colours["shirt"]["male"], [0.72, 0.66, 0.55])

	def test_unknown_field(self):
		with tempfile.TemporaryDirectory() as folder:
			path = write_recipe(folder, "odd", colour="red")
			with self.assertRaises(RecipeError) as caught:
				load_recipe(path)
			self.assertIn("colour", str(caught.exception))

	def test_missing_field(self):
		with tempfile.TemporaryDirectory() as folder:
			path = write_recipe(folder, "odd", layer=None)
			with self.assertRaises(RecipeError) as caught:
				load_recipe(path)
			self.assertIn("layer", str(caught.exception))

	def test_bad_region(self):
		with tempfile.TemporaryDirectory() as folder:
			path = write_recipe(folder, "odd", covers=["wings"])
			with self.assertRaises(RecipeError) as caught:
				load_recipe(path)
			self.assertIn("wings", str(caught.exception))


	def test_nested_fields(self):
		bad = [
			("neckline typo", dict(neckline={"round_ease": 0.01, "v_dept": 0.085, "v_width": 0.07}), "v_dept"),
			("overrides typo", dict(overrides={"fredom": {}}), "fredom"),
			("overrides region", dict(overrides={"freedom": {"chest": 0.1}}), "chest"),
			("top key", dict(top={"at": "neck", "hight": 1}), "hight"),
			("top not a table", dict(top="neck"), "top"),
			("bound hem", dict(openings={"neck": "bound", "sleeves": "open", "hem": "bound"}), "hem"),
			("no bottom", dict(bottom=None), "bottom"),
			("sleeve end", dict(sleeve_end=5), "sleeve_end"),
			("layer bool", dict(layer=True), "layer"),
		]
		with tempfile.TemporaryDirectory() as folder:
			for label, change, field in bad:
				path = write_recipe(folder, "odd", **change)
				with self.assertRaises(RecipeError, msg=label) as caught:
					load_recipe(path)
				self.assertIn(field, str(caught.exception), label)

	def test_fit_fields(self):
		# crotch_drop (garments covering the thighs) and sleeve_taper (sleeves): optional, checked
		with tempfile.TemporaryDirectory() as folder:
			shirt = load_recipe(write_recipe(folder, "tapered", sleeve_taper=0.6))
			self.assertAlmostEqual(shirt.sleeve_taper, 0.6)
			self.assertIsNone(shirt.crotch_drop)
			with open(os.path.join(GARMENTS, "trousers.json"), encoding="utf-8") as handle:
				data = json.load(handle)
			data["crotch_drop"] = 0.05
			path = os.path.join(folder, "trousers.json")
			with open(path, "w", encoding="utf-8") as handle:
				json.dump(data, handle)
			self.assertAlmostEqual(load_recipe(path).crotch_drop, 0.05)
			for label, change, field in [
				("crotch on a shirt", dict(crotch_drop=0.03), "crotch_drop"),
				("taper over 1", dict(sleeve_taper=1.5), "sleeve_taper"),
				("taper not a number", dict(sleeve_taper="x"), "sleeve_taper"),
			]:
				with self.assertRaises(RecipeError, msg=label) as caught:
					load_recipe(write_recipe(folder, "odd", **change))
				self.assertIn(field, str(caught.exception), label)
			data["crotch_drop"] = -0.01
			with open(path, "w", encoding="utf-8") as handle:
				json.dump(data, handle)
			with self.assertRaises(RecipeError):
				load_recipe(path)

	def test_missing_garment(self):
		with tempfile.TemporaryDirectory() as folder:
			path = os.path.join(folder, "o.json")
			with open(path, "w", encoding="utf-8") as handle:
				json.dump({"name": "o", "garments": ["cloak"]}, handle)
			with self.assertRaises(RecipeError) as caught:
				load_outfit(path, GARMENTS)
			self.assertIn("cloak", str(caught.exception))


	def test_shoes(self):
		r = load_recipe(os.path.join(GARMENTS, "shoes.json"))
		self.assertEqual(r.covers, ["foot"])
		self.assertEqual(r.top, {"at": "ankle", "shin": 0.92})
		self.assertEqual(r.material, "shoe_leather")
		self.assertFalse(MATERIALS["shoe_leather"].simulated)
		self.assertEqual(set(r.shoe), {"sole", "toe_point", "toe_shape", "opening_below_ankle", "throat", "lace", "welt", "outsole", "heel", "tongue"})
		self.assertEqual(r.shoe["toe_shape"], "almond")
		with tempfile.TemporaryDirectory() as folder:
			path = os.path.join(folder, "odd.json")
			with open(os.path.join(GARMENTS, "shoes.json"), encoding="utf-8") as handle:
				data = json.load(handle)
			data["shoe"]["spurs"] = 0.02   # (an unknown key: "heel" is a real one now)
			with open(path, "w", encoding="utf-8") as handle:
				json.dump(data, handle)
			with self.assertRaises(RecipeError) as caught:
				load_recipe(path)
			self.assertIn("spurs", str(caught.exception))


if __name__ == "__main__":
	unittest.main()
