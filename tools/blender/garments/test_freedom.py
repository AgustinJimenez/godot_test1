"""Tests for the cloth freedom rule (plain Python): python -I tools/blender/garments/test_freedom.py"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from garments.freedom import freedom   # noqa: E402
from garments.recipe import MATERIALS, load_recipe   # noqa: E402

GARMENTS = os.path.abspath(os.path.join(HERE, "..", "..", "..", "assets", "models", "humans", "garments"))
SHIRT = load_recipe(os.path.join(GARMENTS, "shirt.json"))
TROUSERS = load_recipe(os.path.join(GARMENTS, "trousers.json"))
FAR = 1.0   # (metres from any opening: no band)


def shirt(region, **kw):
	args = dict(along=0.0, hang=0.0, near_neck=False, opening=None, edge_distance=FAR, over_layer=0.0)
	args.update(kw)
	return freedom(region, recipe=SHIRT, material=MATERIALS["linen"], **args)


def trousers(region, **kw):
	args = dict(along=0.0, hang=0.0, near_neck=False, opening=None, edge_distance=FAR, over_layer=0.0)
	args.update(kw)
	return freedom(region, recipe=TROUSERS, material=MATERIALS["wool"], **args)


class FreedomTest(unittest.TestCase):
	def test_shirt_parity(self):
		self.assertEqual(shirt("torso", near_neck=True, hang=0.0), 0.0)
		self.assertAlmostEqual(shirt("torso", hang=0.5), 0.15)
		self.assertAlmostEqual(shirt("torso", hang=1.0), 0.6)
		self.assertAlmostEqual(shirt("torso", hang=1.0, over_layer=1.0), 0.3)
		self.assertAlmostEqual(shirt("upper_arm", along=0.05), 0.0)
		self.assertAlmostEqual(shirt("upper_arm", along=0.35), 1.0)
		self.assertAlmostEqual(shirt("forearm", along=0.5), 1.0)   # (past the upper arm: free)

	def test_trousers_parity(self):
		self.assertAlmostEqual(trousers("thigh", along=1.0), 0.3)
		self.assertAlmostEqual(trousers("shin", along=0.6), 0.45)
		self.assertAlmostEqual(trousers("shin", along=0.0), 0.3)
		self.assertAlmostEqual(trousers("shin", along=0.6, opening="bound", edge_distance=0.01), 0.0)
		self.assertAlmostEqual(trousers("torso", hang=1.0), 0.0)   # (the seat and the waist: glued)

	def test_leather_scaled(self):
		value = freedom("torso", along=0.0, hang=1.0, near_neck=False, opening=None, edge_distance=FAR, over_layer=0.0,
				recipe=SHIRT, material=MATERIALS["leather"])
		self.assertAlmostEqual(value, 0.6 * MATERIALS["leather"].freedom_scale)   # (the general rule times the material's scale)

	def test_override(self):
		recipe = load_recipe(os.path.join(GARMENTS, "trousers.json"))
		recipe.overrides = {"freedom": {"shin": 0.2}}
		value = freedom("shin", along=0.6, hang=0.0, near_neck=False, opening=None, edge_distance=FAR, over_layer=0.0,
				recipe=recipe, material=MATERIALS["wool"])
		self.assertAlmostEqual(value, 0.2)


if __name__ == "__main__":
	unittest.main()
