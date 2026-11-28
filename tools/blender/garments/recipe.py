"""Garment recipes and outfits (docs/superpowers/specs/2026-11-26-garment-recipes-design.md).

A recipe is a small JSON file per garment (assets/models/humans/garments/<name>.json): which body regions it covers, where it starts and ends,
how loose it is, which openings are bound, its material and its layer. An outfit (assets/models/humans/outfits/<name>.json) lists garments; they
are built and worn from the inside out (by layer). Plain Python: no Blender, so it is tested on its own.
"""
import json
import os
from dataclasses import dataclass, field

REGIONS = ("torso", "upper_arm", "forearm", "thigh", "shin", "foot")
SHAPES = ("shell",)   # (plan 3 adds "drape": lofted round the body, across the gap between the legs)
OPENINGS = ("neck", "waist", "hem", "sleeves", "cuffs")
OPENING_KINDS = ("open", "bound")


@dataclass(frozen=True)
class Material:
	name: str
	simulated: bool
	freedom_scale: float    # times the freedom the general rules give (cloth 1; leather is held close)
	stiffness: float        # the solver's stretch stiffness
	bend_stiffness: float
	rim_depth: float        # metres: the rolled lip at every opening (the cloth's thickness where it ends)
	bridge: int = 0         # outward-only smoothing passes: a stiff material spans the body's hollows (leather under the bust) instead of
	# following them in


_MATERIALS_PATH = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "assets", "models", "humans",
		"garments", "materials.json"))   # (shared with the labs' ClothSetup: one table for the builder and the solver)
with open(_MATERIALS_PATH, encoding="utf-8") as _handle:
	MATERIALS = {name: Material(name, **{k: v for k, v in values.items() if k not in ("look", "shader")}) for name, values in json.load(_handle).items()}   # (the
	# look is the shader's, the labs read it)


@dataclass
class Recipe:
	name: str
	layer: int
	shape: str
	covers: list
	top: dict
	ease: dict
	openings: dict
	material: str
	neckline: dict = None
	bottom: dict = None
	sleeve_end: float = None
	leg_end: float = None
	belt: bool = False
	shoe: dict = None
	crotch_drop: float = None    # metres: the crotch seam's lowest line below the body's crotch (garments covering the thighs; None: the builder's
	sleeve_taper: float = None   # share of the upper arm's room left at the wrist (sleeves; None: the builder's default; 1: a straight tube)
	overrides: dict = field(default_factory=dict)


@dataclass
class Outfit:
	name: str
	garments: list
	colours: dict = field(default_factory=dict)


class RecipeError(ValueError):
	pass


_REQUIRED = ("name", "layer", "shape", "covers", "top", "ease", "openings", "material")
_OPTIONAL = ("neckline", "bottom", "sleeve_end", "leg_end", "belt", "overrides", "shoe", "crotch_drop", "sleeve_taper")
_EASE_KEYS = ("torso", "limb", "flare_torso", "flare_limb")


def _fail(path, message):
	raise RecipeError("%s: %s" % (os.path.basename(path), message))


_OPENING_KINDS = {"neck": ("open", "bound"), "sleeves": ("open", "bound"), "cuffs": ("open", "bound"),
		"hem": ("open",), "waist": ("bound",)}   # (only what the builder makes: a hem is open, a waistband held)
_NECKLINE_KEYS = ("round_ease", "v_depth", "v_width")


def _number(value):
	return isinstance(value, (int, float)) and not isinstance(value, bool)


def _keys(path, field, table, allowed, required=()):
	if not isinstance(table, dict):
		_fail(path, "field '%s' must be a table of %s" % (field, ", ".join(allowed)))
	for key in table:
		if key not in allowed:
			_fail(path, "field '%s': unknown key '%s' (keys: %s)" % (field, key, ", ".join(allowed)))
	for key in required:
		if key not in table:
			_fail(path, "field '%s': missing '%s'" % (field, key))


def load_recipe(path):
	with open(path, encoding="utf-8") as handle:
		data = json.load(handle)
	for key in data:
		if key not in _REQUIRED and key not in _OPTIONAL:
			_fail(path, "unknown field '%s'" % key)
	for key in _REQUIRED:
		if key not in data:
			_fail(path, "missing field '%s'" % key)
	if not isinstance(data["layer"], int) or isinstance(data["layer"], bool):
		_fail(path, "field 'layer' must be a whole number")
	if data["shape"] not in SHAPES:
		_fail(path, "field 'shape': '%s' is not one of %s" % (data["shape"], ", ".join(SHAPES)))
	for region in data["covers"]:
		if region not in REGIONS:
			_fail(path, "field 'covers': unknown region '%s' (regions: %s)" % (region, ", ".join(REGIONS)))
	top = data["top"]
	_keys(path, "top", top, ("at", "above_hips", "shin"), ("at",))
	if top["at"] not in ("neck", "waist", "ankle"):
		_fail(path, "field 'top': 'at' must be 'neck', 'waist' or 'ankle'")
	if top["at"] == "ankle":
		if not (_number(top.get("shin")) and 0.0 < top["shin"] < 1.0):
			_fail(path, "field 'top': an ankle top needs 'shin' (where on the shin it starts, a share from the knee)")
		if "foot" not in data["covers"]:
			_fail(path, "field 'top': an ankle top is for footwear: 'covers' needs 'foot'")
	if top["at"] == "waist" and not _number(top.get("above_hips")):
		_fail(path, "field 'top': a waist top needs 'above_hips' (metres)")
	if top["at"] == "neck":
		if "neckline" not in data:
			_fail(path, "missing field 'neckline' (the top is at the neck)")
		if "bottom" not in data:
			_fail(path, "missing field 'bottom' (a garment hung from the neck ends somewhere)")
	if "neckline" in data:
		_keys(path, "neckline", data["neckline"], _NECKLINE_KEYS, _NECKLINE_KEYS)
		for key in _NECKLINE_KEYS:
			if not _number(data["neckline"][key]):
				_fail(path, "field 'neckline': '%s' must be a number (metres)" % key)
	if "bottom" in data:
		_keys(path, "bottom", data["bottom"], ("below_hips",), ("below_hips",))
		if not _number(data["bottom"]["below_hips"]):
			_fail(path, "field 'bottom': 'below_hips' must be a number (metres)")
	_keys(path, "ease", data["ease"], _EASE_KEYS, _EASE_KEYS)
	for key in _EASE_KEYS:
		if not _number(data["ease"][key]):
			_fail(path, "field 'ease': '%s' must be a number (metres)" % key)
	_keys(path, "openings", data["openings"], OPENINGS)
	for opening, kind in data["openings"].items():
		if kind not in _OPENING_KINDS[opening]:
			_fail(path, "field 'openings': '%s' can be %s" % (opening, " or ".join(_OPENING_KINDS[opening])))
	if data["material"] not in MATERIALS:
		_fail(path, "field 'material': unknown material '%s' (materials: %s)" % (data["material"], ", ".join(sorted(MATERIALS))))
	for field_name, region in (("sleeve_end", "forearm"), ("leg_end", "shin")):
		if region in data["covers"] and field_name not in data:
			_fail(path, "missing field '%s' (it covers the %s)" % (field_name, region))
		if field_name in data and not (_number(data[field_name]) and 0.0 < data[field_name] <= 1.0):
			_fail(path, "field '%s' must be a share of the limb, above 0 and at most 1" % field_name)
	if "overrides" in data:
		_keys(path, "overrides", data["overrides"], ("freedom",))
		if "freedom" in data["overrides"]:
			_keys(path, "overrides.freedom", data["overrides"]["freedom"], REGIONS)
	if "shoe" in data:
		_keys(path, "shoe", data["shoe"], ("sole", "toe_point", "toe_shape", "cords", "opening_below_ankle", "throat", "lace", "welt", "outsole",
				"heel", "tongue"), ("sole", "toe_point"))
		if data["shoe"].get("toe_shape", "pointed") not in ("pointed", "almond", "round", "square"):
			_fail(path, "field 'shoe': 'toe_shape' can be pointed, almond, round or square")
		for key in ("sole", "toe_point"):
			if not _number(data["shoe"][key]):
				_fail(path, "field 'shoe': '%s' must be a number (metres)" % key)
		if "cords" in data["shoe"]:
			_keys(path, "shoe.cords", data["shoe"]["cords"], ("rings", "radius", "below_top"), ("rings", "radius", "below_top"))
	if "crotch_drop" in data:
		if "thigh" not in data["covers"]:
			_fail(path, "field 'crotch_drop' needs a garment covering the thighs")
		if not (_number(data["crotch_drop"]) and data["crotch_drop"] >= 0.0):
			_fail(path, "field 'crotch_drop' must be a number of metres, 0 or more")
	if "sleeve_taper" in data:
		if "forearm" not in data["covers"]:
			_fail(path, "field 'sleeve_taper' needs a garment covering the forearms")
		if not (_number(data["sleeve_taper"]) and 0.0 < data["sleeve_taper"] <= 1.0):
			_fail(path, "field 'sleeve_taper' must be a share, above 0 and at most 1")
	if "belt" in data and not isinstance(data["belt"], bool):
		_fail(path, "field 'belt' must be true or false")
	return Recipe(**data)


def load_outfit(path, garments_dir):
	with open(path, encoding="utf-8") as handle:
		data = json.load(handle)
	for key in data:
		if key not in ("name", "garments", "colours"):
			_fail(path, "unknown field '%s'" % key)
	for key in ("name", "garments"):
		if key not in data:
			_fail(path, "missing field '%s'" % key)
	recipes = []
	for name in data["garments"]:
		recipe_path = os.path.join(garments_dir, name + ".json")
		if not os.path.exists(recipe_path):
			_fail(path, "garment '%s' has no recipe (%s)" % (name, recipe_path))
		recipes.append(load_recipe(recipe_path))
	recipes = sorted(enumerate(recipes), key=lambda pair: (pair[1].layer, pair[0]))   # (inside out; ties keep the file's order)
	return Outfit(data["name"], [r for _, r in recipes], data.get("colours", {}))
