"""Checks a built outfit against what made the villager shirt and trousers right (task 103):
- every garment's points over a lower layer of the same outfit stay at least MIN_LAYER_GAP outside it (the shirt showed the trousers through it);
- the lower 12 cm of every torso garment has little cloth facing into the body (a fold showed the shirt's outside from under the hem);
- the open edges are exactly the recipe's openings (welded at the UV seams: no holes, no stray pieces);
- a garment that starts at the neck has its neckline close to the skin (it stood off the skin at the sides of the neck).

blender -b --factory-startup --python tools/blender/garment_check.py -- <folder> <gender> <outfit.json>
Prints the measures and GARMENT_CHECK PASS, or GARMENT_CHECK FAIL with the reasons (exit code 1).
"""
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from garments.recipe import load_outfit   # noqa: E402
from garments.fit import joints_of   # noqa: E402

MIN_LAYER_GAP = 0.006
import json   # noqa: E402
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "humans", "body_shapes.json")) as _handle:
	SHAPE_STRENGTH = {k: float(v) for k, v in json.load(_handle).items() if not k.startswith("_")}   # (the layers must hold in every body shape at
	# the strongest the sliders drive it: a heavy body pushed the shirt into the trousers)
BODY_SHAPES = tuple(SHAPE_STRENGTH)
MAX_INWARD_CM2 = {"male": 12.0, "female": 8.0}
MAX_NECK_EDGE_MM = 6.0
MAX_GROIN_DIP_MM = 8.0

args = sys.argv[sys.argv.index("--") + 1:]
folder, gender, outfit_path = args[0], args[1], args[2]
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
outfit = load_outfit(outfit_path, os.path.join(root, "assets", "models", "humans", "garments"))
failures = []


def glb_path(recipe):
	return os.path.join(folder, "%s_%s_%s.glb" % (gender, outfit.name, recipe.name))


def load(path, shape=None):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
	ob = max(meshes, key=lambda o: len(o.data.vertices))
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	if shape is not None:
		layer = bm.verts.layers.shape.get(shape)
		if layer is None:
			return None
		k = SHAPE_STRENGTH[shape]
		for v in bm.verts:
			v.co = v.co + (v[layer] - v.co) * k   # (the garment in that body shape at the slider's strongest)
	bm.transform(ob.matrix_world)
	bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)   # (glTF splits vertices at UV seams: weld so only real openings are open)
	bm.normal_update()
	return bm


def expected_openings(recipe):
	if recipe.top.get("at") == "ankle":
		return 2   # (footwear: one top per foot; the cords are closed rings)
	count = 1   # (the top: the neckline or the waistband)
	if "torso" in recipe.covers and "thigh" not in recipe.covers:
		count += 1   # (the hem)
	if "forearm" in recipe.covers or "upper_arm" in recipe.covers:
		count += 2   # (two sleeves)
	elif "torso" in recipe.covers and recipe.top.get("at") == "neck":
		count += 2   # (sleeveless: two armholes)
	if "shin" in recipe.covers or "thigh" in recipe.covers:
		count += 2   # (two cuffs)
	return count


def open_loops(bm):
	edges = [e for e in bm.edges if e.is_boundary]
	seen, loops = set(), []
	for e in edges:
		if e in seen:
			continue
		stack, comp = [e], []
		seen.add(e)
		while stack:
			c = stack.pop()
			comp.append(c)
			for v in c.verts:
				for o in v.link_edges:
					if o.is_boundary and o not in seen:
						seen.add(o)
						stack.append(o)
		loops.append(comp)
	return loops


bpy.ops.wm.read_factory_settings(use_empty=True)
body = load(os.path.join(folder, "%s_body.glb" % gender))
body_tree = BVHTree.FromBMesh(body)
joints = joints_of(os.path.join(root, "assets", "models", "humans"), gender)
built = []
for recipe in outfit.garments:
	path = glb_path(recipe)
	if not os.path.exists(path):
		failures.append("%s: no file %s" % (recipe.name, os.path.basename(path)))
		continue
	built.append((recipe, load(path), path))

for index, (recipe, bm, path) in enumerate(built):
	# the openings
	loops = open_loops(bm)
	want = expected_openings(recipe)
	print("GARMENT_CHECK %s %s openings %d (expected %d)" % (gender, recipe.name, len(loops), want))
	if len(loops) != want:
		failures.append("%s has %d openings, expected %d" % (recipe.name, len(loops), want))
	# over every lower layer, in the base shape and in every body shape at full strength
	for lower_recipe, lower, lower_path in built[:index]:
		if lower_recipe.layer >= recipe.layer:
			continue
		for shape in (None,) + BODY_SHAPES:
			upper_bm = bm if shape is None else load(path, shape)
			lower_bm = lower if shape is None else load(lower_path, shape)
			if upper_bm is None or lower_bm is None:
				continue
			tree = BVHTree.FromBMesh(lower_bm)
			top = max(v.co.z for v in lower_bm.verts)
			closest, below, where = 1e9, 0, []
			for v in upper_bm.verts:
				if v.co.z > top + 0.005 or abs(v.co.x) > 0.3:
					continue
				loc, nrm, _, d = tree.find_nearest(v.co)
				if loc is None or d > 0.08:
					continue
				gap = (v.co - loc).dot(nrm)
				if abs(gap) < 0.5 * d:
					# the nearest point is on an edge (a waistband's rim) and the point lies to the side of it, not over the surface: the
					# signed distance along that face's normal read ~0 for points 3-8 cm away. The clearance there is the plain distance.
					gap = d
				closest = min(closest, gap)
				below += gap < MIN_LAYER_GAP
				if gap < MIN_LAYER_GAP and len(where) < 3:
					where.append("(%.2f %.2f %.2f%s)" % (v.co.x, v.co.y, v.co.z, " edge" if v.is_boundary else ""))
			label = shape or "base"
			print("GARMENT_CHECK %s %s over %s (%s): closest %.1f mm, %d points under %.0f mm %s" % (gender, recipe.name, lower_recipe.name, label, closest * 1000, below, MIN_LAYER_GAP * 1000, " ".join(where)))
			if below:
				failures.append("%s (%s): %d points closer than %.0f mm to %s" % (recipe.name, label, below, MIN_LAYER_GAP * 1000, lower_recipe.name))
	# folds under the hem: the lower 12 cm of a garment's torso, faces turned toward the body's middle line
	if "torso" in recipe.covers and "thigh" not in recipe.covers:
		low = min(v.co.z for v in bm.verts if abs(v.co.x) < 0.25)
		area = 0.0
		for f in bm.faces:
			c = f.calc_center_median()
			if c.z > low + 0.12 or abs(c.x) > 0.25:
				continue
			radial = Vector((c.x, c.y, 0.0))
			if radial.length > 1e-6 and f.normal.dot(radial.normalized()) < -0.2:
				area += f.calc_area()
		print("GARMENT_CHECK %s %s inward-facing area under the hem %.1f cm2 (at most %.0f)" % (gender, recipe.name, area * 1e4, MAX_INWARD_CM2[gender]))
		if area * 1e4 > MAX_INWARD_CM2[gender]:
			failures.append("%s: %.1f cm2 of cloth faces in under the hem" % (recipe.name, area * 1e4))
	# the neckline
	if recipe.top.get("at") == "neck" and loops:
		neck = max(loops, key=lambda comp: sum(v.co.z for e in comp for v in e.verts))
		gaps = []
		for e in neck:
			for v in e.verts:
				loc, nrm, _, d = body_tree.find_nearest(v.co)
				gaps.append(d)
		mean = sum(gaps) / len(gaps) * 1000
		# (a bound neckline lies on the skin; an open one, over the layers below, at most its ease further out)
		limit = MAX_NECK_EDGE_MM + (0.0 if recipe.openings.get("neck") == "bound" else recipe.ease["torso"] * 1000)
		print("GARMENT_CHECK %s %s neckline mean %.1f mm off the skin (at most %.0f)" % (gender, recipe.name, mean, limit))
		if mean > limit:
			failures.append("%s: neckline %.1f mm off the skin" % (recipe.name, mean))

	# the sleeve tapers (fit.SLEEVE_TAPER / the recipe's sleeve_taper): less room over the forearm near the sleeve's end than over the upper arm
	if "forearm" in recipe.covers and recipe.sleeve_end and (recipe.sleeve_taper is None or recipe.sleeve_taper < 0.95):   # (1: a straight
		# tube asked for, as mail's flared short sleeve)
		rooms = {"upper": [], "end": []}
		for v in bm.verts:
			for side in ("l", "r"):
				for key, a, b, lo, hi in (("upper", "shoulder_", "elbow_", 0.35, 0.8), ("end", "elbow_", "wrist_", recipe.sleeve_end * 0.5,
						recipe.sleeve_end * 0.85)):
					pa, pb = joints[a + side], joints[b + side]
					t = (v.co - pa).dot(pb - pa) / max((pb - pa).length_squared, 1e-9)
					if lo <= t <= hi and (v.co - (pa + (pb - pa) * t)).length < 0.12:
						loc, _, _, d = body_tree.find_nearest(v.co)
						if loc is not None:
							rooms[key].append(d)
		if rooms["upper"] and rooms["end"]:
			upper = sum(rooms["upper"]) / len(rooms["upper"]) * 1000
			end = sum(rooms["end"]) / len(rooms["end"]) * 1000
			print("GARMENT_CHECK %s %s sleeve room upper arm %.1f mm, forearm by the sleeve's end %.1f mm" % (gender, recipe.name, upper, end))
			if end > upper * 0.95:
				failures.append("%s: the sleeve does not taper (%.1f mm over the upper arm, %.1f mm by its end)" % (recipe.name, upper, end))

	# the groin bridges (fit.CROTCH_DROP / the recipe's crotch_drop): across the front and the seat, from below the crotch up to the hips, each
	# horizontal slice of the garment spans the legs (its outer envelope across x) instead of dipping into the groin between them like leggings
	if "thigh" in recipe.covers:
		hips = joints["hips"]
		middle = [v.co.z for v in body.verts if abs(v.co.x) < 0.008 and abs(v.co.y - hips.y) < 0.08 and hips.z - 0.25 < v.co.z < hips.z]
		if middle:
			crotch_z = min(middle)
			worst = {"front": 0.0, "seat": 0.0}
			where = {"front": "", "seat": ""}
			z = crotch_z + 0.015   # (at the crotch itself the slice is the legs' inner sides)
			while z < hips.z - 0.02:
				for label, facing in (("front", -1.0), ("seat", 1.0)):
					pts = sorted((v.co.x, (v.co.y - hips.y) * facing) for v in bm.verts if abs(v.co.z - z) < 0.006 and abs(v.co.x) < 0.12
							and (v.co.y - hips.y) * facing > 0.0 and v.normal.y * facing > 0.5)   # (facing front / back: the legs' inner sides face
					# each other)
					hull = []   # (the outer envelope: out against x)
					for x, out in pts:
						while len(hull) >= 2 and (hull[-1][0] - hull[-2][0]) * (out - hull[-2][1]) - (hull[-1][1] - hull[-2][1]) * (x - hull[-2][0]) >= 0.0:
							hull.pop()
						hull.append((x, out))
					for x, out in pts:
						for k in range(len(hull) - 1):
							if hull[k][0] <= x <= hull[k + 1][0] and hull[k + 1][0] > hull[k][0]:
								env = hull[k][1] + (hull[k + 1][1] - hull[k][1]) * (x - hull[k][0]) / (hull[k + 1][0] - hull[k][0])
								if env - out > worst[label]:
									worst[label] = env - out
									where[label] = "(x %.3f z %.3f, %.0f mm above the crotch)" % (x, z, (z - crotch_z) * 1000)
								break
				z += 0.01
			print("GARMENT_CHECK %s %s groin: front dips %.1f mm %s, seat %.1f mm %s into the groin (at most %.0f)" % (gender, recipe.name,
					worst["front"] * 1000, where["front"], worst["seat"] * 1000, where["seat"], MAX_GROIN_DIP_MM))
			for label in ("front", "seat"):
				if worst[label] * 1000 > MAX_GROIN_DIP_MM:
					failures.append("%s: the %s dips %.1f mm into the groin" % (recipe.name, label, worst[label] * 1000))

if failures:
	print("GARMENT_CHECK FAIL " + "; ".join(failures))
	sys.exit(1)
print("GARMENT_CHECK PASS")
