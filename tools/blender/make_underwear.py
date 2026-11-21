"""Cut underwear (briefs for both, a bra for the female) out of the exported body meshes.

Run after make_bodies.py, headless:
  blender -b --factory-startup --python tools/blender/make_underwear.py -- <folder with {male,female}_body.glb>

Each garment is a thin shell taken from the body's own faces, so it has the same vertex order and the same
blend shapes (height_short/tall, weight_light/heavy, muscle_low/high) as the body and follows the sliders exactly. The shell is
pushed OFFSET metres out along the body's normal in the base shape and in every morph shape.
"""
import sys

import bmesh
import bpy

OFFSET = 0.004  # metres the cloth sits above the skin
HEM_WIDTH = 0.02  # metres at 1.75 m tall: width of the waistband / hem strip (edge mask ramp)
# (z_min / height, z_max / height, max |x| / height) bands of the body that become cloth
BRIEFS = (0.40, 0.555, 0.15)
BRA = (0.685, 0.775, 0.14)
MIN_ISLAND_VERTS = 150  # drop stray pieces (a finger, a thumb) caught by a band


def build(out: str, name: str, bands: list) -> None:
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=f"{out}/{name}_body.glb")
	body = [o for o in bpy.data.objects if o.type == "MESH"][0]
	me = body.data
	height = max(v.co.z for v in me.vertices)
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	# Slice the whole body along every hem plane first (the cut interpolates the blend shapes too), so the
	# edges of the cloth are straight lines instead of following the body's triangles.
	hem = HEM_WIDTH * height / 1.75  # hem width scaled with the body
	cuts = []
	for z0, z1, hx in bands:
		cuts += [((0, 0, z0 * height), (0, 0, 1)), ((0, 0, z1 * height), (0, 0, 1)),
				((-hx * height, 0, 0), (1, 0, 0)), ((hx * height, 0, 0), (1, 0, 0)),
				((0, 0, z0 * height + hem), (0, 0, 1)), ((0, 0, z1 * height - hem), (0, 0, 1)),
				((-hx * height + hem, 0, 0), (1, 0, 0)), ((hx * height - hem, 0, 0), (1, 0, 0))]
	for co, no in cuts:
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=1e-6,
				plane_co=co, plane_no=no)
		bm.verts.ensure_lookup_table()
	eps = 1e-4
	keep = set()
	for v in bm.verts:
		for z0, z1, hx in bands:
			if (z0 * height - eps <= v.co.z <= z1 * height + eps) and abs(v.co.x) <= hx * height + eps:
				keep.add(v.index)
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
	bm.verts.ensure_lookup_table()
	seen = set()
	islands = []
	for v in bm.verts:
		if v in seen:
			continue
		stack, comp = [v], []
		seen.add(v)
		while stack:
			c = stack.pop()
			comp.append(c)
			for e in c.link_edges:
				o = e.other_vert(c)
				if o not in seen:
					seen.add(o)
					stack.append(o)
		islands.append(comp)
	drop = [v for comp in islands if len(comp) < MIN_ISLAND_VERTS for v in comp]
	if drop:
		bmesh.ops.delete(bm, geom=drop, context="VERTS")
	bm.verts.ensure_lookup_table()
	print(name, "islands", sorted(len(c) for c in islands), "kept verts", len(bm.verts), "faces", len(bm.faces))
	# Per-vertex masks for the fabric shader, from the base shape: red = how close to the elastic waistband
	# (top of the briefs), green = how close to any other hem (leg openings, bra edges, side cuts). 1 on the
	# cut edge, ramping to 0 one hem width inside.
	masks = []
	for v in bm.verts:
		red = green = 0.0
		for i, (z0, z1, hx) in enumerate(bands):
			if z0 * height - 1e-4 <= v.co.z <= z1 * height + 1e-4 and abs(v.co.x) <= hx * height + 1e-4:
				top = max(0.0, 1.0 - (z1 * height - v.co.z) / hem)
				bottom = max(0.0, 1.0 - (v.co.z - z0 * height) / hem)
				side = max(0.0, 1.0 - (hx * height - abs(v.co.x)) / hem)
				if i == 0:
					red = top
					green = max(bottom, side)
				else:
					green = max(top, bottom, side)
		masks.append((red, green))
	bm.normal_update()
	layers = list(bm.verts.layers.shape.values())
	for v in bm.verts:
		n = v.normal.copy()
		v.co += n * OFFSET
		for layer in layers:
			v[layer] = v[layer] + n * OFFSET
	bm.to_mesh(me)
	bm.free()
	attribute = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
	for i, (red, green) in enumerate(masks):
		attribute.data[i].color = (red, green, 0.0, 1.0)
	me.color_attributes.active_color = attribute
	body.name = f"{name}_underwear"
	me.name = f"{name}_underwear"
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=f"{out}/{name}_underwear.glb", use_selection=True, export_format="GLB",
			export_morph=True, export_apply=False, export_vertex_color="ACTIVE")


folder = sys.argv[sys.argv.index("--") + 1]
build(folder, "male", [BRIEFS])
build(folder, "female", [BRIEFS, BRA])
print("DONE")
