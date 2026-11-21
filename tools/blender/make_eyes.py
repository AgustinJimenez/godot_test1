"""Make the eyeballs for the two base bodies, following every body blend shape.

Run after make_bodies.py (it needs the {female,male}_landmarks.json files it writes), headless:
  blender -b --factory-startup --python tools/blender/make_eyes.py -- <folder with the landmarks>
Writes {female,male}_eyes.glb: one mesh with two plain spheres (no iris texture; the Godot shader draws the iris from the
direction on the sphere, so the colour is a parameter), and the same blend shape names as the body. Each shape just moves
the two spheres to where that body variant has its eye centres, so the eyes stay inside the sockets at every slider value.
"""
import json
import math
import sys

import bmesh
import bpy
from mathutils import Vector

EYE_RADIUS_SCALE = 0.9  # the MPFB helper eye is a bit large for a real eyeball; shrink it a little
SEGMENTS = 40
RINGS = 28


def build(folder: str, name: str) -> None:
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	with open(f"{folder}/{name}_landmarks.json") as handle:
		landmarks = json.load(handle)
	radius = landmarks["eye_radius"] * EYE_RADIUS_SCALE
	basis = landmarks["basis"]
	bm = bmesh.new()
	for side in ("eye_l", "eye_r"):
		new = bmesh.ops.create_uvsphere(bm, u_segments=SEGMENTS, v_segments=RINGS, radius=radius)["verts"]
		# the sphere was made at the origin: move this eye's own vertices to its centre in the base shape
		bmesh.ops.translate(bm, vec=basis[side], verts=new)
	for face in bm.faces:
		face.smooth = True
	# a simple spherical UV layer: the shader does not use it, but Godot's importer wants UVs to build tangents
	uv_layer = bm.loops.layers.uv.new("UVMap")
	for face in bm.faces:
		for loop in face.loops:
			co = loop.vert.co
			loop[uv_layer].uv = (0.5 + math.atan2(co.x, co.y) / (2.0 * math.pi), 0.5 + 0.5 * (co.z % 1.0))
	mesh = bpy.data.meshes.new(f"{name}_eyes")
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(f"{name}_eyes", mesh)
	bpy.context.scene.collection.objects.link(obj)
	obj.shape_key_add(name="Basis", from_mix=False)
	half = len(mesh.vertices) // 2
	for key, centres in landmarks.items():
		if key in ("basis", "eye_radius") or key.startswith("lash_"):
			continue
		shape = obj.shape_key_add(name=key, from_mix=False)
		for i, vertex in enumerate(mesh.vertices):
			side = "eye_l" if i < half else "eye_r"
			offset = [centres[side][a] - basis[side][a] for a in range(3)]
			shape.data[i].co = vertex.co + Vector(offset)
		shape.value = 0.0
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(filepath=f"{folder}/{name}_eyes.glb", use_selection=True, export_format="GLB",
			export_morph=True, export_apply=False, export_yup=True)
	print(name, "eyes: radius", round(radius, 4), "vertices", len(mesh.vertices),
			"shapes", [k.name for k in mesh.shape_keys.key_blocks])


folder_arg = sys.argv[sys.argv.index("--") + 1]
build(folder_arg, "male")
build(folder_arg, "female")
print("DONE")
