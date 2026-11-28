"""The cloth freedom of a point of a garment (vertex colour B: 0 held to its place on the body, 1 free cloth), from general rules.

The rules are the ones the villager shirt and trousers were tuned to (task 103), written for any garment:
- a garment hung from the neck is held at the neck band and over the chest, and freer toward its hem (0.6 x hang^2: fully free, the hem curled
  up over the belt);
- a garment held at the waist (trousers, a skirt's waistband) is held over the torso;
- a sleeve is held at the shoulder seam and free past 35 % of the upper arm (a partial weight along the whole sleeve pulled it back to an inflated
  shell);
- a leg is held at the hip, 0.3 at the knee rising to 0.45 down the shin (freer, a quick turn swung it into the back of the calf);
- a bound opening (a cuff, a neckband) is held over its last few centimetres;
- where the garment lies over a lower layer its freedom is capped at 0.3 (a fast turn swung a free hem through the layer under it);
- then the material scales it (leather is held close), and a recipe may set a region's value outright (overrides.freedom).
"""

OVER_LAYER_CAP = 0.3
HANG_MAX = 0.6
KNEE = 0.3
SHIN = 0.45


def _smoothstep(t):
	t = min(max(t, 0.0), 1.0)
	return t * t * (3.0 - 2.0 * t)


def freedom(region, along, hang, near_neck, opening, edge_distance, over_layer, recipe, material):
	"""region: torso | upper_arm | forearm | thigh | shin. along: share along the limb from its root (for the arms: along the upper arm, past 1 on
	the forearm; for the thigh: how far below the hips, 0..1 over 0.35 m). hang: 0 at the chest line to 1 at the hem (torso). near_neck: within the
	neck band. opening: the kind ("open" / "bound") of the nearest opening, or None. edge_distance: metres along the cloth to it. over_layer:
	0..1, how far the point lies over a lower layer."""
	if region == "torso":
		if near_neck or recipe.top.get("at") == "waist":
			w = 0.0   # (held at the neck band, or the whole torso of a garment held at the waist)
		else:
			w = HANG_MAX * hang * hang
	elif region in ("upper_arm", "forearm"):
		w = _smoothstep((along - 0.05) / 0.3)
	elif region == "thigh":
		w = KNEE * min(max(along, 0.0), 1.0)
	elif region == "shin":
		w = KNEE + (SHIN - KNEE) * min(max(along / 0.6, 0.0), 1.0)
	elif region == "foot":
		w = 0.0   # (footwear is held to the foot)
	else:
		raise ValueError("unknown region '%s'" % region)
	if opening == "bound":
		closed_edge = 1.0 - min(max((edge_distance - 0.01) / 0.04, 0.0), 1.0)
		w *= 1.0 - closed_edge
	w = w + (min(w, OVER_LAYER_CAP) - w) * min(max(over_layer, 0.0), 1.0)
	w *= material.freedom_scale
	set_value = recipe.overrides.get("freedom", {}).get(region)
	if set_value is not None:
		w = float(set_value)
	return min(max(w, 0.0), 1.0)
