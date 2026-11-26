"""Cut plain villager clothes (a long-sleeved tunic shirt and trousers) out of the exported body meshes.

Run after make_bodies.py and make_rig.py, headless:
  blender -b --factory-startup --python tools/blender/make_clothes.py -- <folder with {male,female}_body.glb> <folder with {male,female}_rig.json>
Writes {male,female}_shirt.glb and {male,female}_pants.glb into the first folder.
Optional third argument: --garment=shirt or --garment=pants to rebuild only that garment.

Like the underwear (make_underwear.py), each garment is a shell taken from the body's own faces, retaining its
blend shapes (height, weight, muscle and every face shape). Sleeve subdivision interpolates those shapes. What makes it read as cloth and not as paint:
- it stands off the skin (the shirt more than the trousers), and the shell is smoothed so it bridges the hollows (the spine, between the pecs, the
  small of the back) instead of following them;
- the shirt is a tunic: it hangs out over the trousers to the top of the thighs and flares a little toward its hem;
- the hems are cut straight across the limb (planes square to the forearm and the shin, level at the waist and the shirt's hem), and every vertex
  carries how close it is to a hem (vertex colour green) and to the trousers' waistband (red), for the fabric shader's stitching and the belt.
The pieces come from the skeleton (the rig JSON's joints): a vertex near an arm's bone line is arm, near a leg's line is leg, the rest is torso.
"""
import json
import math
import sys

import bmesh
import bpy
from mathutils import Vector, kdtree

ARGS = sys.argv[sys.argv.index("--") + 1:]
FOLDER = ARGS[0]
RIG_FOLDER = ARGS[1] if len(ARGS) > 1 else ARGS[0]
GARMENTS = [arg.split("=", 1)[1] for arg in ARGS[2:] if arg.startswith("--garment=")] or ["shirt", "pants"]
if any(garment not in ("shirt", "pants") for garment in GARMENTS):
	raise ValueError("--garment must be shirt or pants")

SHIRT_OFFSET = 0.016     # metres off the skin
SLEEVE_OFFSET = 0.019    # the sleeves hang a little looser
SLEEVE_EDGE_LENGTH = 0.012  # collision samples must also support the faces across a bent elbow
SHIRT_FLARE = 0.012      # extra toward the hem (the shirt hangs away from the hips)
SLEEVE_END = 0.9         # the sleeve ends at this share of the forearm (from the elbow): just above the wrist
SHIRT_HEM_BELOW_HIPS = 0.0    # metres below the hip joints' height: at the hips (a shell taken from the body cannot hang across the gap between the legs:
                              # cut lower, it wrapped each thigh like shorts)
NECK_DROP_BACK = 0.03    # metres below the neck joint at the back and sides
NECK_DROP_FRONT = 0.085  # a V neckline in front: its point this far below the neck joint, rising to the back's height NECK_FRONT_WIDTH out
NECK_FRONT_WIDTH = 0.07
PANTS_OFFSET = 0.012
PANTS_FLARE = 0.01       # extra toward the cuffs (loose trousers)
PANTS_END = 0.9          # the trousers end at this share of the shin (from the knee): above the ankle
PANTS_WAIST_ABOVE_HIPS = 0.035  # metres above the hip joints' height: the waistband (only a little under the shirt: the heavy belly folded the shirt into a larger overlap)
HEM_WIDTH = 0.025        # metres: the hem / cuff band the shader stitches
CUFF_OFFSET = 0.004      # metres: how far a cuff, the neckband and the trouser cuffs stand off the skin at their edge
CUFF_LENGTH = 0.06       # metres along the cloth over which a sleeve or a trouser leg closes in to its cuff
NECK_BAND = 0.03         # the same for the neckline
RIM_DEPTH = 0.003        # metres: the rolled hem's lip, turned in toward the skin at every open edge (the cloth's thickness where it ends)
BELT_WIDTH = 0.04        # metres: the waistband the shader turns into a belt
SMOOTH_PASSES = 40   # (Taubin pairs; plain averaging at 8, 16, 24 passes still showed the nipples)


def blender_point(p):
	"""A Godot point (y up, z toward the viewer) as a Blender one (z up, -y toward the viewer)."""
	return Vector((p[0], -p[2], p[1]))


def joints_of(name):
	with open(f"{RIG_FOLDER}/{name}_rig.json") as handle:
		rig = json.load(handle)
	bones = rig["bones"]
	out = {}
	for key, bone in (("hips", "Hips"), ("neck", "Neck"),
			("shoulder_l", "LeftArm"), ("elbow_l", "LeftForeArm"), ("wrist_l", "LeftHand"),
			("shoulder_r", "RightArm"), ("elbow_r", "RightForeArm"), ("wrist_r", "RightHand"),
			("hip_l", "LeftUpLeg"), ("knee_l", "LeftLeg"), ("ankle_l", "LeftFoot"),
			("hip_r", "RightUpLeg"), ("knee_r", "RightLeg"), ("ankle_r", "RightFoot")):
		out[key] = blender_point(rig["head"][bones.index("mixamorig:" + bone)])
	return out


def segment_t(p, a, b):
	axis = b - a
	return (p - a).dot(axis) / max(axis.length_squared, 1e-9), axis


LABELS = []      # per vertex of the body: the piece the bone that moves it most belongs to (bone_labels)
TREE = None      # a KD tree over the body's vertices (a vertex the hem cuts made takes the label of the nearest original one)


def bone_labels(name):
	"""The piece every body vertex belongs to, from the rigged body's skin weights (same vertex order): ('hand', side), ('forearm', side),
	('upperarm', side), ('thigh', side), ('shin', side), ('foot', side) or ('torso',). (The hands hang beside the hips in the rest pose: a test by
	distance to the bones' lines could not tell a hand from the hip it touches, and cut holes in the shirt and the trousers there.)"""
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=f"{RIG_FOLDER}/{name}_rigged.glb")
	mesh = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))   # (the male file has a 42-vertex mesh too)
	group_names = {g.index: g.name for g in mesh.vertex_groups}
	labels, points = [], []
	for v in mesh.data.vertices:
		bone = group_names[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else ""
		side = "l" if "Left" in bone else "r"
		if "Hand" in bone:
			label = ("hand", side)
		elif "ForeArm" in bone:
			label = ("forearm", side)
		elif "Arm" in bone:
			label = ("upperarm", side)
		elif "UpLeg" in bone:
			label = ("thigh", side)
		elif "Foot" in bone or "Toe" in bone:
			label = ("foot", side)
		elif "Leg" in bone:
			label = ("shin", side)
		else:
			label = ("torso",)
		labels.append(label)
		points.append(mesh.matrix_world @ v.co)
	tree = kdtree.KDTree(len(points))
	for i, point in enumerate(points):
		tree.insert(point, i)
	tree.balance()
	return labels, tree


def part_of(p, j):
	"""('arm', side, t on the forearm, -1 on the upper arm, 1.5 on the hand) / ('leg', side, t on the shin, -1 on the thigh, 1.5 on the foot) /
	('torso',): the piece from the skin weights of the nearest body vertex, t from the joints."""
	_, index, _ = TREE.find(p)
	label = LABELS[index]
	if label[0] == "torso":
		return ("torso",)
	side = label[1]
	if label[0] == "hand":
		return ("arm", side, 1.5)
	if label[0] == "upperarm":
		return ("arm", side, -1.0)
	if label[0] == "forearm":
		t, _ = segment_t(p, j["elbow_" + side], j["wrist_" + side])
		return ("arm", side, t)
	if label[0] == "foot":
		return ("leg", side, 1.5)
	if label[0] == "thigh":
		return ("leg", side, -1.0)
	t, _ = segment_t(p, j["knee_" + side], j["ankle_" + side])
	return ("leg", side, t)


def build(name, garment):
	global LABELS, TREE
	LABELS, TREE = bone_labels(name)
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=f"{FOLDER}/{name}_body.glb")
	body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
	me = body.data
	j = joints_of(name)
	hips_z = 0.5 * (j["hip_l"].z + j["hip_r"].z)
	neck = j["neck"]
	waist_z = hips_z + PANTS_WAIST_ABOVE_HIPS
	hem_z = hips_z - SHIRT_HEM_BELOW_HIPS
	bm = bmesh.new()
	bm.from_mesh(me)
	# weld the UV seams: the glb holds the body with its vertices split along the texture seams (under the arms, down the sides, across the shoulders: 14,517
	# vertices for MakeHuman's 13,380), and every seam was an open edge here: pinned out of the smoothing (a step, a "layer line" across the back) and given a hem
	# lip (slits along the sleeves). The two copies of a seam vertex sit on the same place with the same shapes.
	before = len(bm.verts)
	bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
	print(name, garment, "welded seam vertices", before - len(bm.verts))
	# straight hems: cut the whole body along each hem's plane first (the cut interpolates the shape keys too); the selection below picks the cloth
	cuts = []
	for side in ("l", "r"):
		if garment == "shirt":
			axis = (j["wrist_" + side] - j["elbow_" + side]).normalized()
			cuts.append((j["elbow_" + side] + (j["wrist_" + side] - j["elbow_" + side]) * SLEEVE_END, axis))
		else:
			axis = (j["ankle_" + side] - j["knee_" + side]).normalized()
			cuts.append((j["knee_" + side] + (j["ankle_" + side] - j["knee_" + side]) * PANTS_END, axis))
	if garment == "shirt":
		cuts += [(Vector((0, 0, hem_z)), Vector((0, 0, 1))), (Vector((0, 0, neck.z - NECK_DROP_BACK)), Vector((0, 0, 1)))]
		# the V: two planes through the point in front, rising to the back's height NECK_FRONT_WIDTH to each side
		rise = (NECK_DROP_FRONT - NECK_DROP_BACK) / NECK_FRONT_WIDTH
		cuts += [(Vector((0, 0, neck.z - NECK_DROP_FRONT)), Vector((-rise, 0, 1)).normalized()), (Vector((0, 0, neck.z - NECK_DROP_FRONT)), Vector((rise, 0, 1)).normalized())]
	else:
		cuts.append((Vector((0, 0, waist_z)), Vector((0, 0, 1))))
	for co, no in cuts:
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=1e-6, plane_co=co, plane_no=no)
	bm.verts.ensure_lookup_table()

	def keep_shirt(v):
		p = v.co
		part = part_of(p, j)
		if part[0] == "arm":
			return part[2] <= SLEEVE_END + 1e-4
		if part[0] == "leg" and p.z < hem_z - 1e-4:
			return False
		if p.z < hem_z - 1e-4:
			return False
		# the neckline: level at the back and the sides, a V in front
		front = p.y < neck.y - 0.02
		drop = NECK_DROP_BACK
		if front:
			drop = max(NECK_DROP_BACK, NECK_DROP_FRONT - (NECK_DROP_FRONT - NECK_DROP_BACK) * abs(p.x) / NECK_FRONT_WIDTH)
		return p.z <= neck.z - drop + 1e-4

	def keep_pants(v):
		p = v.co
		part = part_of(p, j)
		if part[0] == "arm":
			return False
		if p.z > waist_z + 1e-4:
			return False
		if part[0] == "leg":
			return part[2] <= PANTS_END + 1e-4
		return True

	keep = keep_shirt if garment == "shirt" else keep_pants
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v)], context="VERTS")
	bm.verts.ensure_lookup_table()
	# stray pieces (a finger tip, a toe caught by a band)
	seen, islands = set(), []
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
	# a shirt and a pair of trousers are each one piece: keep the largest and drop the rest (bits of the hands, which hang beside the hips in the rest
	# pose and are only told from the hips by their distance to the hand's bone line, and finger tips caught by a hem plane)
	largest = max(islands, key=len) if islands else []
	drop = [v for comp in islands if comp is not largest for v in comp]
	if drop:
		bmesh.ops.delete(bm, geom=drop, context="VERTS")
	bm.verts.ensure_lookup_table()
	print(name, garment, "islands", sorted(len(c) for c in islands), "kept verts", len(bm.verts), "faces", len(bm.faces))
	if garment == "shirt":
		# Interpolate the existing shape/deform layers rather than remeshing away
		# their correspondence. Keep the torso's original resolution.
		sleeve_faces = [f for f in bm.faces if all(part_of(v.co, j)[0] == "arm" for v in f.verts)]
		bmesh.ops.triangulate(bm, faces=sleeve_faces)
		for _ in range(8):
			edges = [e for e in bm.edges if e.calc_length() > SLEEVE_EDGE_LENGTH
				and all(part_of(v.co, j)[0] == "arm" for v in e.verts)]
			if not edges:
				break
			bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True, use_single_edge=True)
			# Subdivision can leave polygons whose export diagonals would still
			# span the elbow. Include those diagonals in the next length check.
			bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3
				and any(part_of(v.co, j)[0] == "arm" for v in f.verts)])
		else:
			raise RuntimeError("Sleeve refinement did not converge")
		bm.verts.ensure_lookup_table()
		bm.verts.index_update()
		print(name, "refined sleeves", len(bm.verts), "verts", len(bm.faces), "faces")

	# distance (along the surface) from every vertex to the nearest open edge (a hem) and, for the trousers, to the waistband
	import heapq
	boundary = [v for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
	dist = {v: 1e9 for v in bm.verts}
	heap = []
	for v in boundary:
		dist[v] = 0.0
		heapq.heappush(heap, (0.0, v.index, v))
	while heap:
		d, _, v = heapq.heappop(heap)
		if d > dist[v] or d > 0.2:
			continue
		for e in v.link_edges:
			o = e.other_vert(v)
			nd = d + e.calc_length()
			if nd < dist[o]:
				dist[o] = nd
				heapq.heappush(heap, (nd, o.index, o))

	# off the skin, then smoothed (the same smoothing move is added to every shape key: the cloth bridges the same hollows in every shape)
	bm.normal_update()
	layers = list(bm.verts.layers.shape.values())
	base_offset = SHIRT_OFFSET if garment == "shirt" else PANTS_OFFSET
	skin = {v: v.co.copy() for v in bm.verts}
	normal = {v: v.normal.copy() for v in bm.verts}
	offset = {}
	waist_shirt = hips_z + 0.12
	for v in bm.verts:
		extra = 0.0
		part = part_of(v.co, j)
		if garment == "shirt":
			if part[0] == "arm":
				extra = SLEEVE_OFFSET - SHIRT_OFFSET
			else:
				extra = SHIRT_FLARE * min(max((waist_shirt - v.co.z) / 0.12, 0.0), 1.0)   # (the shirt hangs away from the waist down)
		elif part[0] == "leg" and part[2] >= 0.0:
			extra = PANTS_FLARE * min(max(part[2] / PANTS_END, 0.0), 1.0)   # (looser toward the cuffs)
		offset[v] = base_offset + extra
		# the openings close in on the skin (a gathered cuff, a neckband, bound trouser cuffs): from below, a loose sleeve showed the empty gap to the arm and,
		# past the inside the shader draws, the sky through the sleeve. Not the shirt's hem at the hips: the trousers are under it.
		near_neck = garment == "shirt" and part[0] != "arm" and v.co.z > neck.z - 0.16
		closing = near_neck or (garment == "pants" and part[0] == "leg" and part[2] >= 0.0)   # (the sleeves stay open and loose at the wrist: the user
		# did not want them closed on the hands; their inside is drawn instead, vertex colour alpha below)
		if closing:
			length = NECK_BAND if near_neck else CUFF_LENGTH
			t = min(max(dist[v] / length, 0.0), 1.0)
			offset[v] = CUFF_OFFSET + (offset[v] - CUFF_OFFSET) * t * t * (3.0 - 2.0 * t)
	placed = {v: skin[v] + normal[v] * offset[v] for v in bm.verts}
	smoothed = dict(placed)
	for step in range(SMOOTH_PASSES):
		# Taubin smoothing: a smoothing step, then a slightly larger step back out (lambda 0.5, mu -0.53), so small bumps go but the garment does not
		# shrink (plain averaging shrank the sleeves and the trousers toward the skin over many passes and was slow on the dense nipples)
		weight = 0.5 if step % 2 == 0 else -0.53
		nxt = {}
		for v in bm.verts:
			if dist[v] < 1e-6:
				nxt[v] = smoothed[v]   # (the hem edges stay where they were cut)
				continue
			ring = [e.other_vert(v) for e in v.link_edges]
			mean = sum((smoothed[o] for o in ring), Vector()) / len(ring)
			p = smoothed[v].lerp(mean, weight)
			# never closer to the skin than half the offset (the smoothing pulls a shell over a bump back into it), and the shirt never inside the
			# trousers where it covers them (the smoothing pulled it in over the round of the hip and the belt showed through as a dark slit)
			lift = (p - skin[v]).dot(normal[v])
			floor = offset[v] * 0.15   # (0.5 held the cloth over every vertebra, 0.3 still tented it over the nipples)
			if garment == "shirt" and v.co.z < hips_z + PANTS_WAIST_ABOVE_HIPS + 0.04:
				floor = max(floor, PANTS_OFFSET + 0.014)
			if lift < floor:
				p += normal[v] * (floor - lift)
			nxt[v] = p
		smoothed = nxt
	for v in bm.verts:
		move = smoothed[v] - skin[v]
		v.co = smoothed[v]
		for layer in layers:
			v[layer] = v[layer] + move
	# the rolled hem: every open edge (the cuffs, the neckline, the shirt's hem, the trousers' waist and cuffs) gets a lip RIM_DEPTH deep, turned in toward
	# the skin, so the cloth has a thickness where it ends (a bare shell showed a paper-thin edge and the gap to the arm). The inside of the shell is drawn
	# too (the shader: double-sided, darker inside), so a look into a sleeve sees cloth, not the gap.
	boundary_edges = [e for e in bm.edges if e.is_boundary]
	inner = {}
	for e in boundary_edges:
		for v in e.verts:
			if v in inner:
				continue
			w = bm.verts.new(v.co - normal[v] * RIM_DEPTH)
			for layer in layers:
				w[layer] = v[layer] - normal[v] * RIM_DEPTH
			inner[v] = w
	for e in boundary_edges:
		a, b = e.verts
		try:
			bm.faces.new((a, b, inner[b], inner[a]))
		except ValueError:
			pass   # (a face already there)
	bm.normal_update()
	print(name, garment, "rim edges", len(boundary_edges))
	bm.to_mesh(me)
	bm.free()
	# blue: the CLOTH WEIGHT for the GPU cloth solver (task 103; addons/godot_gpu_cloth reads it as `cloth_weight_channel` 2): 0 = glued to its skinned
	# place on the body, 1 = free cloth. Glued where clothes are held by the body: the shoulders and the upper torso, the neckband, the gathered cuffs, the
	# waistband and the seat; free where they hang: the shirt below the chest, the forearm part of the sleeves, the trouser legs (most below the knee).
	chest_z = hips_z + 0.75 * (neck.z - hips_z)
	def cloth_weight(p, edge_distance):
		part = part_of(p, j)
		closed_edge = 1.0 - min(max((edge_distance - 0.01) / 0.04, 0.0), 1.0)   # (the gathered cuffs and the neckband stay on the skin)
		if garment == "shirt":
			if part[0] == "arm":
				# Hold only the shoulder seam, then let the sleeve rest on the arm's
				# collider. A partial weight all along the sleeve pulls it back to
				# its inflated rest shell every frame, leaving an even air gap.
				side = part[1]
				along, _ = segment_t(p, j["shoulder_" + side], j["elbow_" + side])
				t = min(max((along - 0.05) / 0.3, 0.0), 1.0)
				return t * t * (3.0 - 2.0 * t)
			if p.z > neck.z - 0.16:
				return 0.0 * (1.0 - closed_edge)
			hang = min(max((chest_z - p.z) / (chest_z - hem_z), 0.0), 1.0)   # (0 at the chest, 1 at the hem)
			return 0.6 * hang * hang   # (fully free, the hem curled up over the belt and showed the shirt's dark inside)
		# the trousers: the seat and the waist glued, freer down the leg, the bound cuff glued
		if part[0] == "leg":
			if part[2] < 0.0:
				thigh = min(max((hips_z - p.z) / 0.35, 0.0), 1.0)
				return 0.45 * thigh
			return (0.45 + 0.4 * min(max(part[2] / 0.6, 0.0), 1.0)) * (1.0 - closed_edge)
		return 0.0
	# the masks: green = how close to a hem (1 at the edge, 0 one hem width in); red = the trousers' waistband (the belt)
	attribute = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
	verts_by_index = {}
	bm2 = bmesh.new()
	bm2.from_mesh(me)
	bm2.verts.ensure_lookup_table()
	boundary2 = [v for v in bm2.verts if any(e.is_boundary for e in v.link_edges)]
	dist2 = [1e9] * len(bm2.verts)
	heap = [(0.0, v.index) for v in boundary2]
	for v in boundary2:
		dist2[v.index] = 0.0
	heapq.heapify(heap)
	while heap:
		d, i = heapq.heappop(heap)
		if d > dist2[i] or d > 0.2:
			continue
		for e in bm2.verts[i].link_edges:
			o = e.other_vert(bm2.verts[i])
			nd = d + e.calc_length()
			if nd < dist2[o.index]:
				dist2[o.index] = nd
				heapq.heappush(heap, (nd, o.index))
	for v in bm2.verts:
		near_hem = max(0.0, 1.0 - dist2[v.index] / HEM_WIDTH)
		belt = 0.0
		if garment == "pants":
			belt = 1.0 if v.co.z > waist_z - BELT_WIDTH else 0.0   # (the band under the waist line: the belt)
			if belt > 0.0:
				near_hem = 0.0
		# alpha: 1 on the sleeves (the shader draws their inside: a look up a loose sleeve sees cloth, not the sky through it), 0 elsewhere
		sleeve = 1.0 if garment == "shirt" and part_of(v.co, j)[0] == "arm" else 0.0
		attribute.data[v.index].color = (belt, near_hem, cloth_weight(v.co, dist2[v.index]), sleeve)
	bm2.free()
	me.color_attributes.active_color = attribute
	# the normals from the cloth's own shape: the imported body carries custom (split) normals, and they stayed the SKIN's after the vertices moved, so the
	# shirt was lit like the body under it (the vertebrae and the nipples showed through whatever the smoothing did)
	with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body]):
		bpy.ops.mesh.customdata_custom_splitnormals_clear()
	for polygon in me.polygons:
		polygon.use_smooth = True
	# and no hard edges: the import marks the body's UV seams sharp (it splits the normals there), and on the welded cloth those marks made creases in the
	# light along the old seams (dark rectangles on the trousers, a blotch on the heavy belly)
	for attribute_name in ("sharp_edge", "sharp_face"):
		if attribute_name in me.attributes:
			me.attributes.remove(me.attributes[attribute_name])
	me.name = f"{name}_{garment}"
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=f"{FOLDER}/{name}_{garment}.glb", use_selection=True, export_format="GLB",
			export_morph=True, export_morph_normal=False, export_apply=False, export_vertex_color="ACTIVE")   # (the shapes' own normals: dark blotches and
			# rectangles on the heavy shape; the cloth is lit with its base normals in every shape)


for gender in ("male", "female"):
	for piece in GARMENTS:
		build(gender, piece)
print("DONE")
