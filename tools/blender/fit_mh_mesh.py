"""Fit a CC0 MakeHuman clothes-type item (a hair shell, .mhclo + .obj) to our body as a single mesh and bind it to our shape keys.

Our own code (see fit_mindfront.py, same mhclo fitting). The obj's faces and UVs are kept as they are (the texture is applied in Godot); only the vertex
positions are rebuilt on our bodies: sum(weight x base vertex) + offset x scale, then bound to the nearest body vertex for every shape key.

  blender -b --factory-startup --python tools/blender/fit_mh_mesh.py -- <folder with {male,female}_body.glb> <item folder> <label> <out folder>
Check the licence line of the item's .mhclo first (CC0 only).
"""
import importlib
import os
import sys

import addon_utils
import bpy
from mathutils import Vector, kdtree

args = sys.argv[sys.argv.index("--") + 1:]
body_folder, item_folder, label, out_folder = args[:4]
DM = 0.1
RACE = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}


def mpfb_base_positions(gender_value):
	entry = bpy.context.preferences.addons.new()
	entry.module = "bl_ext.blender_org.mpfb"
	addon_utils.enable("bl_ext.blender_org.mpfb")
	service = importlib.import_module("bl_ext.blender_org.mpfb.services.humanservice").HumanService
	base = service.create_human(macro_detail_dict={"gender": gender_value, "age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 0.5,
			"height": 0.5, "cupsize": 0.5, "firmness": 0.5, "race": RACE})
	for modifier in base.modifiers:
		modifier.show_viewport = False
	bpy.context.view_layer.update()
	mesh = base.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
	points = [v.co.copy() for v in mesh.vertices]
	bpy.data.objects.remove(base, do_unlink=True)
	return points


def read_item(folder):
	name = [f for f in os.listdir(folder) if f.endswith(".mhclo")][0][:-6]
	scales, rows, in_rows = {}, [], False
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
	uvs, faces, face_uvs = [], [], []
	with open(f"{folder}/{obj_file}") as handle:
		for line in handle:
			if line.startswith("vt "):
				uvs.append((float(line.split()[1]), float(line.split()[2])))
			elif line.startswith("f "):
				corners = [x.split("/") for x in line.split()[1:]]
				faces.append(tuple(int(c[0]) - 1 for c in corners))
				face_uvs.append([uvs[int(c[1]) - 1] if len(c) > 1 and c[1] else (0.0, 0.0) for c in corners])
	return scales, rows, faces, face_uvs


def fit(basis, scales, rows):
	def dist(axis, a, b):
		return abs(basis[a].x - basis[b].x) if axis == "x" else abs(basis[a].z - basis[b].z) if axis == "y" else abs(basis[a].y - basis[b].y)
	scale = {axis: dist(axis, a, b) / (factor * DM) for axis, (a, b, factor) in scales.items()}
	out = []
	for indices, weights, offset in rows:
		p = basis[indices[0]] * weights[0] + basis[indices[1]] * weights[1] + basis[indices[2]] * weights[2]
		p += Vector((offset[0] * DM * scale["x"], -offset[2] * DM * scale["z"], offset[1] * DM * scale["y"]))
		out.append(p)
	return out


scales, rows, faces, face_uvs = read_item(item_folder)
print("rows", len(rows), "faces", len(faces))
for gender in ("male", "female"):
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	original = mpfb_base_positions(1.0 if gender == "male" else 0.0)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=f"{body_folder}/{gender}_body.glb")
	body = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))
	basis = [v.co.copy() for v in body.data.vertices]
	blocks = list(body.data.shape_keys.key_blocks)
	tree = kdtree.KDTree(len(basis))
	for i, co in enumerate(basis):
		tree.insert(co, i)
	tree.balance()
	positions = fit(original, scales, rows)
	print(gender, "bbox z", round(min(p.z for p in positions), 3), round(max(p.z for p in positions), 3))
	bound = []
	for co in positions:
		_, index, _ = tree.find(co)
		bound.append((index, co - basis[index]))
	mesh = bpy.data.meshes.new(f"{gender}_{label}")
	mesh.from_pydata([tuple(v) for v in positions], [], faces)
	mesh.update()
	uv_layer = mesh.uv_layers.new(name="UVMap")
	loop = 0
	for polygon, uvs in zip(mesh.polygons, face_uvs):
		for corner in range(polygon.loop_total):
			uv_layer.data[loop].uv = uvs[corner]
			loop += 1
	for polygon in mesh.polygons:
		polygon.use_smooth = True
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
			export_morph=True, export_apply=False, export_yup=True)
	print(gender, label, "vertices", len(positions), "faces", len(faces))
print("DONE")
