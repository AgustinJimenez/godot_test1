"""Fit a CC0 MakeHuman hair item (Mindfront eyebrows / eyelashes, .mhclo + .obj) to our body and bind it to our shape keys.

Our own code. The CC0 files only supply the LAYOUT of the hairs: where each root is, which way it lies, how long it is. Every hair there is a
thin 3-sided tube of 3-4 rings; we take the centre of each ring as a point of a polyline and build our own tapered strip along it, so the width
is ours (a real hair is far thinner than a pixel). The mhclo gives, for every obj vertex, three base-mesh vertex indices, three weights and an
offset (scaled per axis by the distance between two reference vertices): our bodies keep the MakeHuman base mesh's 13,380 body vertices first,
so the same indices work on them.

Run headless:
  blender -b --factory-startup --python tools/blender/fit_mindfront.py -- <folder with {male,female}_body.glb> <item folder> <label> <out folder> [width_m]
  <item folder> holds <name>.mhclo and <name>.obj (an unzipped MakeHuman pack item); <label> becomes {male,female}_<label>.glb.
Vertex colour as in make_face_hair.py: red = random brightness, green = random 0..1 (brow density), blue = 0 (no base layer).
"""
import os
import random
import sys

import addon_utils
import importlib

import bpy
from mathutils import Vector, kdtree

args = sys.argv[sys.argv.index("--") + 1:]
body_folder, item_folder, label, out_folder = args[:4]
WIDTH = float(args[4]) if len(args) > 4 else 0.0004
TAPER = (1.0, 0.9, 0.6, 0.2)
DM = 0.1   # MakeHuman units are decimetres
RACE = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}


def mpfb_base_positions(gender_value):
	"""The MakeHuman base mesh in ITS OWN vertex order (the mhclo indices refer to it): the body glb is re-ordered and split by the glTF round trip."""
	entry = bpy.context.preferences.addons.new()
	entry.module = "bl_ext.blender_org.mpfb"
	addon_utils.enable("bl_ext.blender_org.mpfb")
	service = importlib.import_module("bl_ext.blender_org.mpfb.services.humanservice").HumanService
	base = service.create_human(macro_detail_dict={"gender": gender_value, "age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 0.5,
			"height": 0.5, "cupsize": 0.5, "firmness": 0.5, "race": RACE})
	for modifier in base.modifiers:
		modifier.show_viewport = False
	bpy.context.view_layer.update()
	evaluated = base.evaluated_get(bpy.context.evaluated_depsgraph_get())
	mesh = evaluated.to_mesh()
	points = [v.co.copy() for v in mesh.vertices]
	bpy.data.objects.remove(base, do_unlink=True)
	return points


def read_item(folder):
	name = [f for f in os.listdir(folder) if f.endswith(".mhclo")][0][:-6]
	scales = {}
	rows = []
	in_rows = False
	with open(f"{folder}/{name}.mhclo") as handle:
		for line in handle:
			parts = line.split()
			if not parts:
				continue
			if in_rows:
				if len(parts) == 9 and parts[0].isdigit():
					rows.append(([int(p) for p in parts[:3]], [float(p) for p in parts[3:6]], [float(p) for p in parts[6:9]]))
			elif parts[0] in ("x_scale", "y_scale", "z_scale"):
				scales[parts[0][0]] = (int(parts[1]), int(parts[2]), float(parts[3]))
			elif parts[0] == "verts":
				in_rows = True
	obj_file = [f for f in os.listdir(folder) if f.endswith(".obj")][0]
	faces = []
	with open(f"{folder}/{obj_file}") as handle:
		for line in handle:
			if line.startswith("f "):
				faces.append([int(x.split("/")[0]) - 1 for x in line.split()[1:]])
	return name, scales, rows, faces


def hair_rings(vertex_count, faces):
	"""Groups the obj vertices into hairs (connected pieces) and each hair into rings of 3 consecutive vertices."""
	parent = list(range(vertex_count))

	def find(a):
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	for face in faces:
		for index in face[1:]:
			parent[find(index)] = find(face[0])
	groups = {}
	for i in range(vertex_count):
		groups.setdefault(find(i), []).append(i)
	hairs = []
	for members in groups.values():
		members.sort()
		hairs.append([members[k:k + 3] for k in range(0, len(members) - 2, 3)])
	hairs.sort(key=lambda rings: rings[0][0])
	return hairs


def fit(basis, scales, rows):

	# MakeHuman axes (x right, y up, z forward) -> ours (x, z, -y)
	def dist(axis, a, b):
		if axis == "x":
			return abs(basis[a].x - basis[b].x)
		if axis == "y":
			return abs(basis[a].z - basis[b].z)
		return abs(basis[a].y - basis[b].y)
	scale = {axis: dist(axis, a, b) / (factor * DM) for axis, (a, b, factor) in scales.items()}
	points = []
	for indices, weights, offset in rows:
		p = basis[indices[0]] * weights[0] + basis[indices[1]] * weights[1] + basis[indices[2]] * weights[2]
		p += Vector((offset[0] * DM * scale["x"], -offset[2] * DM * scale["z"], offset[1] * DM * scale["y"]))
		points.append(p)
	return points, basis


name, scales, rows, obj_faces = read_item(item_folder)
hairs = hair_rings(len(rows), obj_faces)
print("item", name, "rows", len(rows), "hairs", len(hairs), "rings per hair", sorted(set(len(h) for h in hairs)))
for gender in ("male", "female"):
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	original = mpfb_base_positions(1.0 if gender == "male" else 0.0)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=f"{body_folder}/{gender}_body.glb")
	body = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))
	basis = [v.co.copy() for v in body.data.vertices]
	positions, _ = fit(original, scales, rows)
	blocks = list(body.data.shape_keys.key_blocks)
	tree = kdtree.KDTree(len(basis))
	for i, co in enumerate(basis):
		tree.insert(co, i)
	tree.balance()
	box_min = Vector((min(p.x for p in positions), min(p.y for p in positions), min(p.z for p in positions)))
	box_max = Vector((max(p.x for p in positions), max(p.y for p in positions), max(p.z for p in positions)))
	print(gender, "fitted bbox", tuple(round(c, 3) for c in box_min), tuple(round(c, 3) for c in box_max))
	rng = random.Random(5 if gender == "male" else 9)
	verts, faces_out, uvs, colors = [], [], [], []
	for rings in hairs:
		centres = [sum((positions[i] for i in ring), Vector()) / 3.0 for ring in rings]
		# drop the doubled root ring (the first two are almost the same place)
		if len(centres) > 3 and (centres[1] - centres[0]).length < 0.0016:
			centres = centres[1:]
		if len(centres) < 2:
			continue
		color = (rng.random(), rng.random(), 0.0)
		count = len(centres)
		previous = None
		for k, centre in enumerate(centres):
			step = centres[min(k + 1, count - 1)] - centres[max(k - 1, 0)]
			if step.length < 1e-9:
				step = Vector((0.0, 0.0, 1.0))
			side = Vector((0.0, -1.0, 0.0)).cross(step)   # the strip faces the front of the face
			if side.length < 1e-9:
				side = Vector((1.0, 0.0, 0.0))
			side.normalize()
			taper = TAPER[min(k * (len(TAPER) - 1) // max(count - 1, 1), len(TAPER) - 1)]
			half = side * (WIDTH * taper * 0.5)
			left = len(verts)
			verts.append(centre - half)
			colors.append(color)
			right = len(verts)
			verts.append(centre + half)
			colors.append(color)
			if previous is not None:
				v0 = (k - 1) / (count - 1)
				v1 = k / (count - 1)
				faces_out.append((previous[0], previous[1], right, left))
				uvs.append([(0.0, v0), (1.0, v0), (1.0, v1), (0.0, v1)])
			previous = (left, right)
	bound = []
	for co in verts:
		_, index, _ = tree.find(co)
		bound.append((index, co - basis[index]))
	mesh = bpy.data.meshes.new(f"{gender}_{label}")
	mesh.from_pydata([tuple(v) for v in verts], [], faces_out)
	mesh.update()
	uv_layer = mesh.uv_layers.new(name="UVMap")
	loop = 0
	for polygon, face_uvs in zip(mesh.polygons, uvs):
		for corner in range(polygon.loop_total):
			uv_layer.data[loop].uv = face_uvs[corner]
			loop += 1
	for polygon in mesh.polygons:
		polygon.use_smooth = True
	attribute = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
	for i, color in enumerate(colors):
		attribute.data[i].color = (color[0], color[1], color[2], 1.0)
	mesh.color_attributes.active_color = attribute
	obj = bpy.data.objects.new(f"{gender}_{label}", mesh)
	bpy.context.scene.collection.objects.link(obj)
	obj.shape_key_add(name="Basis", from_mix=False)
	for block in blocks[1:]:
		shape = obj.shape_key_add(name=block.name, from_mix=False)
		for i, (index, offset) in enumerate(bound):
			shape.data[i].co = block.data[index].co + offset
		shape.value = 0.0
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	os.makedirs(out_folder, exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=f"{out_folder}/{gender}_{label}.glb", use_selection=True, export_format="GLB",
			export_morph=True, export_apply=False, export_vertex_color="ACTIVE", export_yup=True)
	print(gender, label, "vertices", len(verts), "faces", len(faces_out))
print("DONE")
