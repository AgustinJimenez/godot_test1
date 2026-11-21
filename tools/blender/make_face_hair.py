"""Make eyebrows and eyelashes for the two base bodies, following every body blend shape.

Run after make_bodies.py (needs {female,male}_body.glb and {female,male}_landmarks.json), headless:
  blender -b --factory-startup --python tools/blender/make_face_hair.py -- <folder>
Writes {female,male}_brows.glb and {female,male}_lashes.glb. Both are sets of thin tapered hair strips (no strand texture: the
Godot shader draws the taper, so the colour is a parameter). Every vertex is bound to its nearest body vertex plus an offset,
so each body blend shape moves the hairs with the face.

Vertex colour carries per-hair data for the shader: red = a random brightness, green = a random 0..1 used by the brow density
slider (a hair is drawn when green <= density), blue = 1 only on the faint base layer under the brow hairs.
"""
import json
import math
import random
import sys

import bpy
from mathutils import Vector, bvhtree, kdtree

SKIN_OFFSET = 0.0006      # metres a brow hair sits above the skin at its root
BROW_CURVE_STEPS = 40
# Left-eye brow (the +X side) as offsets from the eye centre: x outward, z up, half-height of the brow there (metres).
BROW_POINTS = [(-0.0165, 0.0215, 0.0058), (-0.0085, 0.0252, 0.0054), (0.0020, 0.0275, 0.0050),
		(0.0140, 0.0270, 0.0042), (0.0255, 0.0235, 0.0028), (0.0325, 0.0190, 0.0014)]
BROW_HAIRS = 320          # per brow
BROW_HAIR_LENGTH = 0.0052
BROW_HAIR_WIDTH = 0.0009
UPPER_ROOTS = 24          # lash roots per upper lid; each root grows UPPER_PER_ROOT lashes
UPPER_PER_ROOT = 3
LOWER_ROOTS = 12
LOWER_PER_ROOT = 2
UPPER_LENGTH = 0.0090
LOWER_LENGTH = 0.0040
LASH_WIDTH = 0.0011
SEGMENTS = 3              # quads along one hair


def catmull(points, steps):
	"""Points of a Catmull-Rom curve through the given tuples, `steps` samples in all."""
	n = len(points)
	out = []
	for s in range(steps):
		t = s / (steps - 1) * (n - 1)
		i = min(int(t), n - 2)
		f = t - i
		p0 = points[max(i - 1, 0)]
		p1 = points[i]
		p2 = points[i + 1]
		p3 = points[min(i + 2, n - 1)]
		out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * f + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * f * f
				+ (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * f ** 3) for k in range(3)))
	return out


class Cards:
	"""A bag of vertices/faces/uvs/colours that is bound to the body afterwards."""

	def __init__(self):
		self.verts = []
		self.colors = []
		self.faces = []
		self.uvs = []  # per face: list of (u, v) per corner

	def add_vert(self, co, color):
		self.verts.append(Vector(co))
		self.colors.append(color)
		return len(self.verts) - 1

	def add_face(self, indices, uvs):
		self.faces.append(tuple(indices))
		self.uvs.append(uvs)

	def add_strip(self, centres, sides, widths, color):
		"""A tapered strip along the points `centres`; `sides` are unit side vectors, `widths` the full widths."""
		previous = None
		count = len(centres)
		for k in range(count):
			half = sides[k] * (widths[k] * 0.5)
			left = self.add_vert(centres[k] - half, color)
			right = self.add_vert(centres[k] + half, color)
			if previous is not None:
				v0 = (k - 1) / (count - 1)
				v1 = k / (count - 1)
				self.add_face((previous[0], previous[1], right, left), [(0.0, v0), (1.0, v0), (1.0, v1), (0.0, v1)])
			previous = (left, right)


def build(folder: str, name: str) -> None:
	rng = random.Random(7 if name == "male" else 11)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=f"{folder}/{name}_body.glb")
	body = [o for o in bpy.data.objects if o.type == "MESH"][0]
	mesh = body.data
	blocks = list(mesh.shape_keys.key_blocks)
	basis = [v.co.copy() for v in mesh.vertices]
	tree = kdtree.KDTree(len(basis))
	for i, co in enumerate(basis):
		tree.insert(co, i)
	tree.balance()
	bvh = bvhtree.BVHTree.FromPolygons(basis, [tuple(p.vertices) for p in mesh.polygons])
	with open(f"{folder}/{name}_landmarks.json") as handle:
		landmarks = json.load(handle)
	centres = {"l": Vector(landmarks["basis"]["eye_l"]), "r": Vector(landmarks["basis"]["eye_r"])}

	def on_skin(x, z, y_start):
		hit = bvh.ray_cast(Vector((x, y_start, z)), Vector((0.0, 1.0, 0.0)))
		if hit[0] is None:
			raise RuntimeError(f"no skin at x={x:.3f} z={z:.3f}")
		return hit[0], hit[1]

	brows = Cards()
	for side, sign in (("l", 1.0), ("r", -1.0)):
		centre = centres[side]
		curve = catmull(BROW_POINTS, BROW_CURVE_STEPS)
		# faint base layer under the hairs, so the brow still reads as a solid shape from far away
		previous = None
		for k, (dx, dz, half) in enumerate(curve):
			x = centre.x + sign * dx
			z = centre.z + dz
			top, top_n = on_skin(x, z + half * 0.9, centre.y - 0.15)
			bottom, bottom_n = on_skin(x, z - half * 0.9, centre.y - 0.15)
			top_i = brows.add_vert(top + top_n * 0.0003, (0.5, 0.0, 1.0))
			bottom_i = brows.add_vert(bottom + bottom_n * 0.0003, (0.5, 0.0, 1.0))
			if previous is not None:
				u0 = (k - 1) / (BROW_CURVE_STEPS - 1)
				u1 = k / (BROW_CURVE_STEPS - 1)
				brows.add_face((previous[1], bottom_i, top_i, previous[0]), [(u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)])
			previous = (top_i, bottom_i)
		# the hairs
		for _ in range(BROW_HAIRS):
			u = rng.random() ** 0.85                       # a bit denser toward the inner end
			index = min(int(u * (BROW_CURVE_STEPS - 1)), BROW_CURVE_STEPS - 2)
			frac = u * (BROW_CURVE_STEPS - 1) - index
			dx = curve[index][0] * (1 - frac) + curve[index + 1][0] * frac
			dz = curve[index][1] * (1 - frac) + curve[index + 1][1] * frac
			half = curve[index][2] * (1 - frac) + curve[index + 1][2] * frac
			tangent = Vector((curve[index + 1][0] - curve[index][0], curve[index + 1][1] - curve[index][1]))
			tangent.normalize()
			across = rng.uniform(-1.0, 1.0)                # -1 lower edge, +1 upper edge
			angle = math.atan2(tangent.y, tangent.x)
			# hairs lean up at the inner end, lie along the brow in the middle and tilt down on the upper edge
			angle += math.radians(48.0 * (1.0 - u) ** 1.6 - 14.0 * across + rng.uniform(-9.0, 9.0))
			direction2 = Vector((math.cos(angle), math.sin(angle)))
			length = BROW_HAIR_LENGTH * (1.15 - 0.6 * u) * rng.uniform(0.8, 1.2)
			start = Vector((centre.x + sign * dx, centre.z + dz + across * half))
			points = []
			normals = []
			for k in range(SEGMENTS + 1):
				s = k / SEGMENTS
				x = start.x + sign * direction2.x * length * s
				z = start.y + direction2.y * length * s
				hit, normal = on_skin(x, z, centre.y - 0.15)
				lift = SKIN_OFFSET + 0.0011 * s ** 1.4 + 0.0002 * rng.random() * s
				points.append(hit + normal * lift)
				normals.append(normal)
			sides = []
			for k in range(SEGMENTS + 1):
				step = points[min(k + 1, SEGMENTS)] - points[max(k - 1, 0)]
				side_vec = normals[k].cross(step)
				if side_vec.length < 1e-9:
					side_vec = Vector((0.0, 0.0, 1.0))
				sides.append(side_vec.normalized())
			width = BROW_HAIR_WIDTH * rng.uniform(0.8, 1.25)
			widths = [width, width * 0.95, width * 0.7, width * 0.25]
			brows.add_strip(points, sides, widths, (rng.random(), rng.random(), 0.0))

	lashes = Cards()
	for side, sign in (("l", 1.0), ("r", -1.0)):
		centre = centres[side]
		for row, roots_count, per_root, length, upward in (("2", UPPER_ROOTS, UPPER_PER_ROOT, UPPER_LENGTH, 1.0),
				("1", LOWER_ROOTS, LOWER_PER_ROOT, LOWER_LENGTH, -1.0)):
			points = [Vector(p) for p in landmarks[f"lash_{side}_{row}"]]

			def angle_of(p):
				a = math.degrees(math.atan2(p.z - centre.z, sign * (p.x - centre.x)))
				return a + 360.0 if a < -100.0 else a
			ranked = sorted(((angle_of(p), p) for p in points), key=lambda item: item[0])
			if row == "2":
				ranked = [item for item in ranked if -15.0 <= item[0] <= 195.0]
			else:
				ranked = [item for item in ranked if item[0] <= 5.0 or item[0] >= 175.0]
			low = ranked[0][0]
			high = ranked[-1][0]
			for index in range(roots_count):
				t = index / max(roots_count - 1, 1)
				target = low + (high - low) * t
				near = sorted(ranked, key=lambda item: abs(item[0] - target))[:3]
				root = sum((item[1] for item in near), Vector()) / len(near)
				outward = Vector((root.x - centre.x, 0.0, root.z - centre.z))
				if outward.length < 1e-6:
					outward = Vector((0.0, 0.0, upward))
				outward.normalize()
				flare = 0.85 if row == "2" else 0.4
				shape = 0.55 + 0.45 * math.sin(math.pi * (0.15 + 0.75 * t))     # longest toward the outer-middle of the lid
				for _ in range(per_root):
					jitter = Vector((rng.uniform(-0.25, 0.25), 0.0, rng.uniform(-0.2, 0.2)))
					direction = Vector((outward.x * flare, -1.0, outward.z * 0.9 + 0.15 * upward)) + jitter
					direction.normalize()
					size = length * shape * rng.uniform(0.75, 1.1)
					along = direction.cross(Vector((0.0, 0.0, 1.0))).normalized()
					base = root + along * rng.uniform(-0.0006, 0.0006) + direction * 0.0004
					curl = Vector((0.0, 0.0, upward)) * size * rng.uniform(0.35, 0.6)
					spine = [base + direction * size * (k / SEGMENTS) + curl * (k / SEGMENTS) ** 2 for k in range(SEGMENTS + 1)]
					sides = []
					for k in range(SEGMENTS + 1):
						step = spine[min(k + 1, SEGMENTS)] - spine[max(k - 1, 0)]
						# the lash is flat: its width runs across the direction of travel, roughly along the lid
						side_vec = step.cross(Vector((0.0, 0.0, 1.0)))
						if side_vec.length < 1e-9:
							side_vec = Vector((1.0, 0.0, 0.0))
						sides.append(side_vec.normalized())
					width = LASH_WIDTH * rng.uniform(0.8, 1.2)
					widths = [width, width * 0.9, width * 0.6, width * 0.2]
					lashes.add_strip(spine, sides, widths, (rng.random(), 0.0, 0.0))

	for label, cards in (("brows", brows), ("lashes", lashes)):
		export(folder, name, label, cards, blocks, basis, tree)
		print(name, label, "vertices", len(cards.verts), "faces", len(cards.faces))


def export(folder, name, label, cards, blocks, basis, tree):
	# bind every vertex to the nearest body vertex plus an offset
	bound = []
	for co in cards.verts:
		_, index, _ = tree.find(co)
		bound.append((index, co - basis[index]))
	mesh = bpy.data.meshes.new(f"{name}_{label}")
	mesh.from_pydata([tuple(v) for v in cards.verts], [], cards.faces)
	mesh.update()
	uv_layer = mesh.uv_layers.new(name="UVMap")
	loop = 0
	for polygon, uvs in zip(mesh.polygons, cards.uvs):
		for corner in range(polygon.loop_total):
			uv_layer.data[loop].uv = uvs[corner]
			loop += 1
	for polygon in mesh.polygons:
		polygon.use_smooth = True
	attribute = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
	for i, color in enumerate(cards.colors):
		attribute.data[i].color = (color[0], color[1], color[2], 1.0)
	mesh.color_attributes.active_color = attribute
	obj = bpy.data.objects.new(f"{name}_{label}", mesh)
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
	bpy.ops.export_scene.gltf(filepath=f"{folder}/{name}_{label}.glb", use_selection=True, export_format="GLB",
			export_morph=True, export_apply=False, export_vertex_color="ACTIVE", export_yup=True)


folder_arg = sys.argv[sys.argv.index("--") + 1]
build(folder_arg, "male")
build(folder_arg, "female")
print("DONE")
