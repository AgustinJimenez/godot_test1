"""Fit a garment recipe to a body (Blender, bmesh): the general rules the villager shirt and trousers were tuned with (task 103), for any recipe.

The garment is a shell taken from the body's own faces, so it keeps the body's blend shapes (height, weight, muscle, every face shape):
1. cut to the recipe's coverage (the regions, the hems square to the limbs, a level hem, a waistband, or a round neckline with a V), with clean edges;
2. placed off the skin by the recipe's ease (looser toward the hems by its flare), closing in at bound openings (a neckband, cuffs);
3. over a lower layer of the outfit: placed and floored out from the body's middle line (at the top of the cleft between the buttocks the skin's
   normals face each other, the points crossed and folded), then pushed at least LAYER_CLEARANCE outside the finished lower layer, the push spread
   over the cloth round it;
4. Taubin-smoothed (bridges the hollows, does not shrink), unfolded (triangles still facing into the body relaxed onto their neighbours), sleeves
   refined (exact arm contact needs small faces across the elbow), and a rolled lip at every opening (the cloth's thickness where it ends);
5. the masks in the vertex colour: R belt, G hem band, B freedom (garments.freedom), A draw the inside.
"""
import heapq
import json
import os

import bmesh
import math
import bpy
from mathutils import Vector, kdtree
from mathutils.bvhtree import BVHTree

from garments.freedom import freedom
from garments.recipe import MATERIALS
from garments.footwear import build_shoe

SLEEVE_EDGE_LENGTH = 0.012   # metres: the sleeves' largest edge (exact arm contact must support the faces across a bent elbow)
NECK_DROP_BACK = 0.03        # the neckline's lowest point at the back, below the neck joint (the round cut stops there: the neck's axis carried
                             # down runs through the upper back)
HEM_WIDTH = 0.025            # the hem / cuff band the shader stitches (vertex colour G)
CUFF_OFFSET = 0.004          # how far a bound opening stands off the skin at its edge
CUFF_LENGTH = 0.06           # along the cloth over which a bound sleeve or leg closes in
NECK_BAND = 0.03             # the same for the neckline
NECK_BAND_HEIGHT = 0.16      # the neck band reaches this far below the neck joint (held still: freedom 0)
BELT_WIDTH = 0.04            # the band under a belted waistband (vertex colour R)
SMOOTH_PASSES = 40           # Taubin pairs (plain averaging at 8, 16, 24 passes still showed the nipples)
SLEEVE_TAPER = 0.7           # a sleeve's room at the wrist, as a share of the upper arm's (the recipe's sleeve_taper overrides it)
SLEEVE_TAPER_FROM = 0.45     # ... narrowing from this share along the arm (0 shoulder, 0.5 elbow, 1 wrist; from 0.3 the bent elbow met
# the sleeve at 40 faces in the 150-degree motion check, from 6-12)
CROTCH_DROP = 0.035          # garments covering the thighs: the groin's bridging fades in from this far below the body's crotch (crotch_drop)
GROIN_HALF_WIDTH = 0.13      # ... over this far either side of the middle
GROIN_FADE_TOP = 0.05        # ... and fades out over this much above the hips joint (toward the waistband)
BRIDGE_STRIP = 0.015         # a stiff material's bridging: the width of each upright strip whose side profile is spanned
LIP_CLEARANCE = 0.007        # a rolled lip stops this far outside a lower layer (the checks want 6 mm)
ARMHOLE_IN = 0.85            # a sleeveless garment's armhole: this share of the shoulder joint's distance from the middle
ARMPIT_DROP = 0.09           # ... cut down to this far below the shoulder joint (below it the side follows the skin's labels to the armpit)
LAYER_CLEARANCE = 0.012      # a garment stays this far outside a lower layer where it covers it (8 mm: the lower one is drawn 3 mm further out
                             # than the upper one, and a turning hem dips a little)
LAYER_FLOOR_EXTRA = 0.014    # the smoothing's floor over a lower layer: that layer's ease plus this
LAYER_ZONE = 0.04            # how far above a lower layer's waistband the over-layer rules reach
HIP_ZONE = 0.075             # below this much above the hip joints a torso garment is placed out from the body's middle line (the cleft between
                             # the buttocks: the skin's normals face each other there, whatever is or is not under the garment)
ARMPIT_NO_INSIDE = 0.09      # the inside is not drawn within this of an armpit (a sleeve and the body's shell overlap there)
CROTCH_NO_INSIDE = 0.10      # nor of the crotch (the two legs' shells overlap there)
FLARE_RAMP = 0.12            # the torso's flare grows over this much above its hem


def blender_point(p):
	"""A Godot point (y up, z toward the viewer) as a Blender one (z up, -y toward the viewer)."""
	return Vector((p[0], -p[2], p[1]))


def joints_of(rig_folder, gender):
	with open(os.path.join(rig_folder, "%s_rig.json" % gender)) as handle:
		rig = json.load(handle)
	bones = rig["bones"]
	out = {}
	for key, bone in (("hips", "Hips"), ("neck", "Neck"), ("head", "Head"),
			("shoulder_l", "LeftArm"), ("elbow_l", "LeftForeArm"), ("wrist_l", "LeftHand"),
			("shoulder_r", "RightArm"), ("elbow_r", "RightForeArm"), ("wrist_r", "RightHand"),
			("hip_l", "LeftUpLeg"), ("knee_l", "LeftLeg"), ("ankle_l", "LeftFoot"),
			("hip_r", "RightUpLeg"), ("knee_r", "RightLeg"), ("ankle_r", "RightFoot"),
			("toe_l", "LeftToeBase"), ("toe_r", "RightToeBase")):
		out[key] = blender_point(rig["head"][bones.index("mixamorig:" + bone)])
	return out


def segment_t(p, a, b):
	axis = b - a
	return (p - a).dot(axis) / max(axis.length_squared, 1e-9), axis


class Body:
	"""A body's pieces from the rigged body's skin weights (the hands hang beside the hips in the rest pose: a test by distance to the bones' lines
	could not tell a hand from the hip it touches), and its joints."""

	def __init__(self, rig_folder, gender):
		self.joints = joints_of(rig_folder, gender)
		for ob in list(bpy.data.objects):
			bpy.data.objects.remove(ob, do_unlink=True)
		bpy.ops.import_scene.gltf(filepath=os.path.join(rig_folder, "%s_rigged.glb" % gender))
		mesh = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))   # (the male file has a 42-vertex mesh too)
		group_names = {g.index: g.name for g in mesh.vertex_groups}
		self.labels, points = [], []
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
			self.labels.append(label)
			points.append(mesh.matrix_world @ v.co)
		self.tree = kdtree.KDTree(len(points))
		for i, point in enumerate(points):
			self.tree.insert(point, i)
		self.tree.balance()
		j = self.joints
		self.hips_z = 0.5 * (j["hip_l"].z + j["hip_r"].z)
		self.hips_axis = Vector((0.0, j["hips"].y, 0.0))

	def part_of(self, p):
		"""('arm', side, t on the forearm, -1 on the upper arm, 1.5 on the hand) / ('leg', side, t on the shin, -1 on the thigh, 1.5 on the foot) /
		('torso',)."""
		j = self.joints
		_, index, _ = self.tree.find(p)
		label = self.labels[index]
		if label[0] == "torso":
			return ("torso",)
		side = label[1]
		if label[0] == "hand":
			return ("arm", side, 1.5)
		if label[0] == "upperarm":
			return ("arm", side, -1.0)
		if label[0] == "forearm":
			return ("arm", side, segment_t(p, j["elbow_" + side], j["wrist_" + side])[0])
		if label[0] == "foot":
			return ("leg", side, 1.5)
		if label[0] == "thigh":
			return ("leg", side, -1.0)
		return ("leg", side, segment_t(p, j["knee_" + side], j["ankle_" + side])[0])


with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "assets", "models", "humans", "body_shapes.json")) as _handle:
	SHAPE_STRENGTH = {k: float(v) for k, v in json.load(_handle).items() if not k.startswith("_")}   # (the strongest the sliders drive each shape:
	# the layers must hold there; a heavy body pushed the shirt up to 8 mm into the trousers, the lab drives muscle to 2x)
BODY_SHAPES = tuple(SHAPE_STRENGTH)


def layer_surface(path):
	"""A finished garment of the same outfit (built earlier in this run) as surfaces to stay outside of: {None: (tree, top)} for its base shape and
	{shape name: (tree, top)} for each body shape at full strength."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	added = [o for o in bpy.data.objects if o not in before]
	ob = max((o for o in added if o.type == "MESH"), key=lambda o: len(o.data.vertices))
	polygons = [list(f.vertices) for f in ob.data.polygons]
	surfaces = {}
	keys = ob.data.shape_keys.key_blocks if ob.data.shape_keys else {}
	for shape in (None,) + BODY_SHAPES:
		if shape is None:
			vertices = [ob.matrix_world @ v.co for v in ob.data.vertices]
		elif shape in keys:
			k = SHAPE_STRENGTH[shape]
			vertices = [ob.matrix_world @ (v.co + (d.co - v.co) * k) for v, d in zip(ob.data.vertices, keys[shape].data)]
		else:
			continue
		surfaces[shape] = (BVHTree.FromPolygons(vertices, polygons), max(v.z for v in vertices))
	for o in added:
		bpy.data.objects.remove(o, do_unlink=True)
	return surfaces


def _push_outside(bm, pos, tree, top, dist):
	"""pos (vertex -> position) moved so no point below the lower layer's top is closer than LAYER_CLEARANCE outside it; each push is spread over
	~6 rings round the point (single points moved up to 2 cm folded their triangles over), a few rounds until nothing is too close."""
	for _rounds in range(12):
		move = {}
		for v in bm.verts:
			p = pos[v]
			if p.z > top + 0.01:
				continue
			loc, nrm, _, d = tree.find_nearest(p)
			if loc is None or d > 0.08:
				continue
			outside = (p - loc).dot(nrm)
			if outside < LAYER_CLEARANCE:
				move[v] = nrm * (LAYER_CLEARANCE - outside)
		if not move:
			break
		spread = dict(move)
		for _ring in range(6):
			nxt = dict(spread)
			for v in list(spread):
				for e in v.link_edges:
					o = e.other_vert(v)
					if dist[o] < 1e-6:
						continue   # (the cut edges stay)
					cand = spread[v] * 0.7
					if o not in nxt or cand.length > nxt[o].length:
						nxt[o] = cand
			spread = nxt
		for v, m in spread.items():
			pos[v] = pos[v] + m
	return pos


def _surface_distance(bm, limit):
	"""Distance along the surface from every vertex to the nearest open edge (up to limit)."""
	dist = {v: 1e9 for v in bm.verts}
	heap = []
	for v in bm.verts:
		if any(e.is_boundary for e in v.link_edges):
			dist[v] = 0.0
			heapq.heappush(heap, (0.0, v.index, v))
	while heap:
		d, _, v = heapq.heappop(heap)
		if d > dist[v] or d > limit:
			continue
		for e in v.link_edges:
			o = e.other_vert(v)
			nd = d + e.calc_length()
			if nd < dist[o]:
				dist[o] = nd
				heapq.heappush(heap, (nd, o.index, o))
	return dist


CORD_AROUND = 256     # a cord's points round the ankle (64 put ~2 points in a strand's turn: the twist smoothed away)
CORD_TUBE = 16        # ... round the rope
CORD_STRANDS = 3      # ... strands twisted together
CORD_LAY = 0.009      # ... a strand's turn round the rope every this long (m)
CORD_GROOVE = 0.45    # ... the grooves between strands this share of the radius deep
SOLE_RAMP = 0.03   # (footwear's R: the height above the ground over this span; the leather shader's sole_height is in metres of it)


def _add_cords(bm, layers, cord_layer, j, recipe):
	"""The cords wound round the ankle: closed rings lying on the shoe's outside, a little below its top, each a twisted rope of three strands
	(real relief: a tube with a painted twist looked painted). The path: the shoe's surface found by rays round the ankle, smoothed, then pushed
	out until the rope clears the shoe everywhere (28 ray points let the shoe bulge between them and the cord dipped inside). Every rope point
	takes the skin weights and the shape-key moves of the shoe's nearest point; the groove between strands goes to the masks (G)."""
	import math
	from mathutils.bvhtree import BVHTree as _Tree
	from mathutils import kdtree as _kd
	cords = recipe.shoe["cords"]
	# (the groove layer first: adding a layer to the mesh drops every vertex reference taken before it)
	groove_layer = bm.verts.layers.float.get("groove") or bm.verts.layers.float.new("groove")
	layers = list(bm.verts.layers.shape.values())
	cord_layer = bm.verts.layers.int.get("cord")
	tree = _Tree.FromBMesh(bm)
	shell = [v for v in bm.verts]
	near = _kd.KDTree(len(shell))
	for i, v in enumerate(shell):
		near.insert(v.co, i)
	near.balance()
	deform = bm.verts.layers.deform.active   # (the rings follow the shoe's skin weights too: without them they stayed at rest)
	r_tube = cords["radius"]
	around, tube = CORD_AROUND, CORD_TUBE
	clear = r_tube * 1.15 + 0.0008   # (the rope's middle this far off the shoe: its strands' outer bulge clears it)
	for side in ("l", "r"):
		knee, ankle = j["knee_" + side], j["ankle_" + side]
		axis = (ankle - knee).normalized()
		top = knee + (ankle - knee) * recipe.top["shin"]
		helper = Vector((1.0, 0.0, 0.0)) if abs(axis.x) < 0.9 else Vector((0.0, 1.0, 0.0))
		e1 = axis.cross(helper).normalized()
		e2 = axis.cross(e1).normalized()
		for ring_i, below in enumerate(cords["below_top"][:cords["rings"]]):
			tilt = 0.25 if ring_i % 2 == 0 else -0.25   # (each ring a little tilted, the other way to the last: wound, not stacked)
			path = []
			for k in range(around):
				a = 6.2831853 * k / around
				d = (e1 * math.cos(a) + e2 * math.sin(a)).normalized()
				c = top + axis * (below + tilt * 0.01 * math.sin(a))
				hit = tree.ray_cast(c + d * 0.2, -d, 0.25)   # (from outside, inward: the shoe's outer surface)
				if hit[0] is not None:
					path.append(hit[0] + d * clear)
			if len(path) < 8:
				continue
			n_pts = len(path)
			for _ in range(3):   # (smoothed, then pushed out of the shoe wherever it came closer than `clear`)
				path = [(path[(k - 1) % n_pts] + path[k] * 2.0 + path[(k + 1) % n_pts]) / 4.0 for k in range(n_pts)]
				for k in range(n_pts):
					loc, nrm, _, dist = tree.find_nearest(path[k])
					if loc is None:
						continue
					gap = (path[k] - loc).dot(nrm)   # (the shoe's faces point out: a point inside it has a negative gap)
					if gap < clear:
						path[k] = path[k] + nrm * (clear - gap)
			length = 0.0
			rings = []
			for k in range(n_pts):
				p = path[k]
				length += (p - path[k - 1]).length if k else 0.0
				tangent = (path[(k + 1) % n_pts] - path[(k - 1) % n_pts]).normalized()
				out_dir = (p - (top + axis * below)).normalized()
				out_dir = (out_dir - tangent * out_dir.dot(tangent)).normalized()
				side_v = tangent.cross(out_dir).normalized()
				_, index, _ = near.find(p)
				anchor = shell[index]
				ring = []
				for m in range(tube):
					b = 6.2831853 * m / tube
					phase = CORD_STRANDS * b - length / CORD_LAY * 6.2831853   # (three strands winding round the rope)
					strand = 0.5 + 0.5 * math.cos(phase)   # (1 on a strand's crown, 0 in the groove between strands)
					radius = r_tube * (1.0 - CORD_GROOVE + CORD_GROOVE * strand)
					w = bm.verts.new(p + (out_dir * math.cos(b) + side_v * math.sin(b)) * radius)
					for layer in layers:
						w[layer] = w.co + (anchor[layer] - anchor.co)
					w[cord_layer] = 1
					w[groove_layer] = 1.0 - strand
					if deform is not None:
						for group, value in anchor[deform].items():
							w[deform][group] = value
					ring.append(w)
				rings.append(ring)
			for k in range(n_pts):
				a_ring, b_ring = rings[k], rings[(k + 1) % n_pts]
				for m in range(tube):
					try:
						bm.faces.new((a_ring[m], a_ring[(m + 1) % tube], b_ring[(m + 1) % tube], b_ring[m]))
					except ValueError:
						pass

def build_garment(body_path, out_path, body, recipe, lower):
	"""Fit `recipe` to the body in `body_path` and write `out_path`. `lower`: [(recipe, tree, top)] for the finished lower layers of the outfit."""
	j = body.joints
	material = MATERIALS[recipe.material]
	name = recipe.name
	covers = set(recipe.covers)
	arms = bool(covers & {"upper_arm", "forearm"})
	legs = bool(covers & {"thigh", "shin"})
	neck = j["neck"]
	hips_z = body.hips_z
	top_at = recipe.top["at"]
	waist_z = hips_z + recipe.top.get("above_hips", 0.0) if top_at == "waist" else None
	hem_z = hips_z - recipe.bottom["below_hips"] if recipe.bottom else None
	neckline = recipe.neckline or {}
	part_of = body.part_of

	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	bpy.ops.import_scene.gltf(filepath=body_path)
	ob = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
	me = ob.data
	bm = bmesh.new()
	bm.from_mesh(me)
	# the UV seams welded (every seam was an open edge: pinned out of the smoothing, a lip along it)
	bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)

	# 1. the cuts: planes square to the limbs at their ends, a level hem, a level waistband, the V of a neckline
	cuts = []
	for side in ("l", "r"):
		if "forearm" in covers:
			cuts.append((j["elbow_" + side] + (j["wrist_" + side] - j["elbow_" + side]) * recipe.sleeve_end,
					(j["wrist_" + side] - j["elbow_" + side]).normalized()))
		if "shin" in covers:
			cuts.append((j["knee_" + side] + (j["ankle_" + side] - j["knee_" + side]) * recipe.leg_end,
					(j["ankle_" + side] - j["knee_" + side]).normalized()))
		if top_at == "ankle":   # (footwear: its top, level, at the share of the shin: square to the shin it dipped at the instep and left the
			# front of the ankle bare under the cords)
			cuts.append((j["knee_" + side] + (j["ankle_" + side] - j["knee_" + side]) * recipe.top["shin"], Vector((0.0, 0.0, -1.0))))
	sleeveless = "torso" in covers and not (covers & {"upper_arm", "forearm"}) and top_at == "neck"
	armhole = {}
	if sleeveless:   # (the armholes: an upright plane on each side, ARMHOLE_IN of the shoulder joint's distance in from it, above the armpit; by the
		# skin's labels alone the edge was ragged and the shoulder straps came out torn)
		for side in ("l", "r"):
			sh = j["shoulder_" + side]
			sign = 1.0 if sh.x > 0.0 else -1.0
			armhole[side] = (Vector((sh.x * ARMHOLE_IN, 0.0, 0.0)), Vector((sign, 0.0, 0.0)), sh.z - ARMPIT_DROP)
			cuts.append((armhole[side][0], armhole[side][1]))
	if hem_z is not None:
		cuts.append((Vector((0, 0, hem_z)), Vector((0, 0, 1))))
	if waist_z is not None:
		cuts.append((Vector((0, 0, waist_z)), Vector((0, 0, 1))))
	v_depth = neckline.get("v_depth", NECK_DROP_BACK)
	v_width = neckline.get("v_width", 0.07)
	if top_at == "neck" and v_depth > NECK_DROP_BACK:
		rise = (v_depth - NECK_DROP_BACK) / v_width
		for sign in (-1.0, 1.0):
			cuts.append((Vector((0, 0, neck.z - v_depth)), Vector((sign * rise, 0, 1)).normalized()))
	for co, no in cuts:
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=1e-6, plane_co=co, plane_no=no)
	bm.verts.ensure_lookup_table()

	collar_edge = set()
	collar_f = None
	if top_at == "neck":
		# the round neckline: a cylinder round the neck's axis, the neck's own radius plus the recipe's ease, stopped NECK_DROP_BACK below the neck
		# joint; crossing edges split exactly on it (triangles first: a crossing quad got more than two split points and the edge came out ragged)
		neck_axis = (j["head"] - neck).normalized()
		neck_length = max((j["head"] - neck).length, 1e-6)

		def axis_distance(p):
			d = p - neck
			return (d - neck_axis * d.dot(neck_axis)).length
		band = sorted(axis_distance(v.co) for v in bm.verts if 0.2 < (v.co - neck).dot(neck_axis) / neck_length < 0.5)
		collar_r = (band[len(band) // 2] if band else 0.06) + neckline.get("round_ease", 0.01)

		def collar_f(p):
			return max(axis_distance(p) - collar_r, (neck.z - NECK_DROP_BACK) - p.z)   # (< 0: cut away)
		bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if any(v.co.z > neck.z - NECK_DROP_BACK - 0.03 for v in f.verts)])
		new_verts = []
		for e in [e for e in bm.edges if (collar_f(e.verts[0].co) < 0.0) != (collar_f(e.verts[1].co) < 0.0)]:
			a, b = e.verts
			fa, fb = collar_f(a.co), collar_f(b.co)
			if abs(fa - fb) < 1e-9:
				continue
			_, v_new = bmesh.utils.edge_split(e, a, min(max(fa / (fa - fb), 0.0), 1.0))
			new_verts.append(v_new)
		collar_edge = set(new_verts)   # (the split points ARE the edge: kept, or some went and it was ragged)
		for f in {f for v in new_verts for f in v.link_faces}:
			on = [v for v in f.verts if v in collar_edge]
			if len(on) == 2:
				try:
					bmesh.ops.connect_verts(bm, verts=on)
				except Exception:
					pass
		bm.verts.ensure_lookup_table()

	def keep(v):
		p = v.co
		part = part_of(p)
		if part[0] == "arm":
			if "forearm" in covers:
				return part[2] <= recipe.sleeve_end + 1e-4
			return "upper_arm" in covers and part[2] < 0.0
		if part[0] == "leg":
			if top_at == "ankle":   # (footwear: everything of the leg on the foot's side of its top's plane; by the share along the shin bone the
				# heel was misjudged and the opening ran down the back of the heel)
				side = part[1]
				top_point = j["knee_" + side] + (j["ankle_" + side] - j["knee_" + side]) * recipe.top["shin"]
				return p.z <= top_point.z + 1e-4
			if "shin" in covers:
				return part[2] <= recipe.leg_end + 1e-4
			if "thigh" in covers:
				return part[2] < 0.0
			if hem_z is not None and p.z < hem_z - 1e-4:
				return False
			return False if not legs and p.z < hips_z else "torso" in covers
		if "torso" not in covers:
			return False
		for point, out, below in armhole.values():
			if p.z > below and (p - point).dot(out) > 1e-4:
				return False   # (outside an armhole)
		if hem_z is not None and p.z < hem_z - 1e-4:
			return False
		if waist_z is not None and p.z > waist_z + 1e-4:
			return False
		if top_at == "neck":
			if collar_f(p) < -1e-4 and v not in collar_edge:
				return False
			if p.z > neck.z + 0.02:
				return False   # (the head)
			if p.y < neck.y - 0.02 and abs(p.x) < v_width:   # (only inside the V: outside it the round neckline is the edge)
				drop = max(NECK_DROP_BACK, v_depth - (v_depth - NECK_DROP_BACK) * abs(p.x) / v_width)
				return p.z <= neck.z - drop + 1e-4
		return True

	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v)], context="VERTS")
	bm.verts.ensure_lookup_table()
	# one piece: the largest island (bits of the hands beside the hips, finger tips caught by a hem plane)
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
	largest = max(islands, key=len) if islands else []
	paired = top_at == "ankle"   # (footwear comes in two: keep both shoes, drop only scraps)
	drop = [v for comp in islands if comp is not largest and not (paired and len(comp) > 0.25 * len(largest)) for v in comp]
	print(name, "pieces", sorted((len(c) for c in islands), reverse=True)[:8])
	if drop:
		bmesh.ops.delete(bm, geom=drop, context="VERTS")
	bm.verts.ensure_lookup_table()
	if arms:
		# the sleeves refined (shape layers interpolated, the torso keeps its resolution)
		bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if all(part_of(v.co)[0] == "arm" for v in f.verts)])
		for _ in range(8):
			edges = [e for e in bm.edges if e.calc_length() > SLEEVE_EDGE_LENGTH and all(part_of(v.co)[0] == "arm" for v in e.verts)]
			if not edges:
				break
			bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True, use_single_edge=True)
			bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3 and any(part_of(v.co)[0] == "arm" for v in f.verts)])
		else:
			raise RuntimeError("Sleeve refinement did not converge")
		bm.verts.ensure_lookup_table()
		bm.verts.index_update()

	dist = _surface_distance(bm, 0.2)

	# 2. off the skin
	bm.normal_update()
	layers = list(bm.verts.layers.shape.values())
	skin = {v: v.co.copy() for v in bm.verts}
	normal = {v: v.normal.copy() for v in bm.verts}
	ease = recipe.ease
	flare_top = (hem_z + FLARE_RAMP) if hem_z is not None else None
	offset = {}
	taper = recipe.sleeve_taper if recipe.sleeve_taper is not None else SLEEVE_TAPER
	for v in bm.verts:
		part = part_of(v.co)
		if part[0] == "arm":
			o = ease["limb"] + (ease["flare_limb"] * min(max(part[2] / recipe.sleeve_end, 0.0), 1.0) if part[2] >= 0.0 and recipe.sleeve_end else 0.0)
			# the sleeve tapers: its room narrows from the upper arm to the wrist (a straight tube stood off the forearm and the elbow)
			side = part[1]
			along = 0.5 * min(max(segment_t(v.co, j["shoulder_" + side], j["elbow_" + side])[0], 0.0), 1.0) if part[2] < 0.0 else 					0.5 + 0.5 * min(max(part[2], 0.0), 1.0)
			k = min(max((along - SLEEVE_TAPER_FROM) / (1.0 - SLEEVE_TAPER_FROM), 0.0), 1.0)
			o *= 1.0 - (1.0 - taper) * k * k * (3.0 - 2.0 * k)
		elif part[0] == "leg":
			o = ease["limb"] + (ease["flare_limb"] * min(max(part[2] / recipe.leg_end, 0.0), 1.0) if part[2] >= 0.0 and recipe.leg_end else 0.0)
			if recipe.shoe and normal[v].z < -0.4:
				o += recipe.shoe["sole"]   # (the sole: thicker under the foot)
		else:
			o = ease["torso"] + (ease["flare_torso"] * min(max((flare_top - v.co.z) / FLARE_RAMP, 0.0), 1.0) if flare_top is not None else 0.0)
		# bound openings close in on the skin (a neckband, cuffs); a bound waist is held by the freedom only (it sits under the layer above)
		near_neck = top_at == "neck" and part[0] == "torso" and v.co.z > neck.z - NECK_BAND_HEIGHT
		length = None
		if near_neck and recipe.openings.get("neck") == "bound":
			length = NECK_BAND
		elif part[0] == "arm" and part[2] >= 0.0 and recipe.openings.get("sleeves") == "bound":
			length = CUFF_LENGTH
		elif part[0] == "leg" and part[2] >= 0.0 and recipe.openings.get("cuffs") == "bound":
			length = CUFF_LENGTH
		if length:
			t = min(max(dist[v] / length, 0.0), 1.0)
			o = CUFF_OFFSET + (o - CUFF_OFFSET) * t * t * (3.0 - 2.0 * t)
		offset[v] = o

	# 3. over the lower layers: the zone (from the lower layer's waistband in its recipe) and the floor (its ease plus LAYER_FLOOR_EXTRA, out from the
	# body's middle line)
	zone_top, zone_floor = None, 0.0
	for lower_recipe, _ in lower:
		if lower_recipe.top["at"] == "ankle":
			continue   # (footwear under a garment: nothing of it is covered at the hips)
		lower_waist = hips_z + lower_recipe.top.get("above_hips", 0.0) if lower_recipe.top["at"] == "waist" else neck.z
		zone_top = max(zone_top if zone_top is not None else -1e9, lower_waist + LAYER_ZONE)
		zone_floor = max(zone_floor, lower_recipe.ease["torso"] + LAYER_FLOOR_EXTRA)
	hip_zone = hips_z + HIP_ZONE

	def radial_of(p):
		r = Vector((p.x - body.hips_axis.x, p.y - body.hips_axis.y, 0.0))
		return r.normalized() if r.length > 1e-6 else None

	def place_dir(v):
		if v.co.z < hip_zone and not legs and part_of(v.co)[0] != "arm":   # (hanging over the hips, the tops of the thighs too; trousers have their own seat)
			r = radial_of(v.co)
			if r is not None:
				blend = min(max((hip_zone - v.co.z) / 0.03, 0.0), 1.0)
				return normal[v].lerp(r, blend).normalized()
		return normal[v]
	smoothed = {v: skin[v] + place_dir(v) * offset[v] for v in bm.verts}

	# 4. smoothing (Taubin: lambda 0.5, mu -0.53), never closer to the skin than 0.15 of the offset, nor inside a lower layer's floor
	for step in range(SMOOTH_PASSES):
		weight = 0.5 if step % 2 == 0 else -0.53
		nxt = {}
		for v in bm.verts:
			if dist[v] < 1e-6:
				# the cut edges smoothed along themselves only (pinned at their first offset, a loose garment's edge stuck out in torn flaps
				# past the smoothed cloth beside it)
				ring = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
				nxt[v] = smoothed[v].lerp(sum((smoothed[o] for o in ring), Vector()) / len(ring), weight) if len(ring) == 2 else smoothed[v]
				continue
			ring = [e.other_vert(v) for e in v.link_edges]
			p = smoothed[v].lerp(sum((smoothed[o] for o in ring), Vector()) / len(ring), weight)
			push_dir = normal[v]
			floor = offset[v] * 0.15
			if v.co.z < hip_zone and "torso" in covers and not legs:   # (a garment hanging over the hips; legs: trousers have their own seat)
				r = radial_of(skin[v])
				if r is not None:
					push_dir = r
			if zone_top is not None and v.co.z < zone_top:
				floor = max(floor, zone_floor)
			lift = (p - skin[v]).dot(push_dir)
			if lift < floor:
				p += push_dir * (floor - lift)
			nxt[v] = p
		smoothed = nxt
	# outside every finished lower layer by LAYER_CLEARANCE (base shape)
	for _, surfaces in lower:
		tree, lower_top = surfaces[None]
		smoothed = _push_outside(bm, smoothed, tree, lower_top, dist)
	# unfold: triangles still facing into the body relaxed onto their neighbours (a fold showed the garment's outside from under its hem)
	for _ in range(60):
		folded = set()
		for f in bm.faces:
			vs = f.verts
			n_face = (smoothed[vs[1]] - smoothed[vs[0]]).cross(smoothed[vs[2]] - smoothed[vs[0]])
			n_skin = sum((normal[v] for v in vs), Vector())
			if n_face.length < 1e-12 or n_face.normalized().dot(n_skin.normalized()) < 0.0:
				folded.update(v for v in vs if dist[v] > 1e-6)
		if not folded:
			break
		relaxed = {}
		for v in folded:
			ring = [e.other_vert(v) for e in v.link_edges]
			relaxed[v] = sum((smoothed[o] for o in ring), Vector()) / len(ring)
		smoothed.update(relaxed)
	# a stiff material spans the body's hollows (leather under the bust, over the hollow of the spine) instead of following them in: in side
	# view, for each upright strip of the front and of the back, the profile's convex envelope (how far out each point lies, against its height);
	# points behind it move out to it, faded in toward the sides. Outward-only smoothing on this coarse mesh moved a few points and left the
	# crease under the bust.
	# (after the unfold: before it, the points it found folded were the bridged ones, relaxed back into the crease)
	if material.bridge > 0 and "torso" in covers:
		for facing in (-1.0, 1.0):   # (-1: the front, -y; 1: the back)
			strips = {}
			for v in bm.verts:
				if part_of(skin[v])[0] != "torso" or dist[v] < 1e-6:
					continue
				# (front or back by the direction from the body's middle line: the skin's normal points down in the fold under the bust and
				# faded the bridging out exactly there)
				r = Vector((skin[v].x - body.hips_axis.x, skin[v].y - body.hips_axis.y, 0.0))
				if r.length < 1e-6:
					continue
				weight = min(max((r.normalized().y * facing - 0.45) / 0.3, 0.0), 1.0)
				if weight <= 0.0:
					continue
				strips.setdefault(int(math.floor(smoothed[v].x / BRIDGE_STRIP)), []).append((v, weight))
			for members in strips.values():
				pts = sorted((smoothed[v].z, smoothed[v].y * facing) for v, _ in members)
				hull = []   # (the upper envelope of out against z)
				for z, out in pts:
					while len(hull) >= 2 and (hull[-1][0] - hull[-2][0]) * (out - hull[-2][1]) - (hull[-1][1] - hull[-2][1]) * (z - hull[-2][0]) >= 0.0:
						hull.pop()
					hull.append((z, out))
				for v, weight in members:
					z = smoothed[v].z
					envelope = None
					for k in range(len(hull) - 1):
						if hull[k][0] <= z <= hull[k + 1][0]:
							span = max(hull[k + 1][0] - hull[k][0], 1e-9)
							envelope = hull[k][1] + (hull[k + 1][1] - hull[k][1]) * (z - hull[k][0]) / span
							break
					out = smoothed[v].y * facing
					if envelope is not None and envelope > out:
						smoothed[v].y += facing * (envelope - out) * weight
		# then smoothed (Taubin: no shrinking) where the strips and the fade toward the sides left steps
		torso_verts = [v for v in bm.verts if part_of(skin[v])[0] == "torso" and dist[v] > 1e-6]
		for step in range(16):
			weight = 0.5 if step % 2 == 0 else -0.53
			nxt = {}
			for v in torso_verts:
				ring = [e.other_vert(v) for e in v.link_edges]
				nxt[v] = smoothed[v].lerp(sum((smoothed[o] for o in ring), Vector()) / len(ring), weight)
			smoothed.update(nxt)
	# the groin bridges (garments covering the thighs): across the front and the seat each horizontal slice of the garment takes its outer
	# envelope across both legs instead of dipping between them like leggings; full from just above the body's crotch, faded in from
	# crotch_drop below it and out toward the hips
	groin_bridged = []
	if "thigh" in covers:
		drop = recipe.crotch_drop if recipe.crotch_drop is not None else CROTCH_DROP
		hips_joint = j["hips"]
		middle = [skin[v].z for v in bm.verts if abs(skin[v].x) < 0.008 and abs(skin[v].y - hips_joint.y) < 0.08 and
				hips_joint.z - 0.25 < skin[v].z < hips_joint.z]
		if middle and drop > 0.0:
			crotch_z = min(middle)
			top_z = hips_joint.z + GROIN_FADE_TOP   # (full up to the hips joint: fading out below it left the top of the seat's cleft dipping)
			def bridge_groin():
				for facing in (-1.0, 1.0):   # (-1: the front, 1: the seat)
					slices = {}
					for v in bm.verts:
						p = smoothed[v]
						if dist[v] < 1e-6 or abs(p.x) > GROIN_HALF_WIDTH or not (crotch_z - drop < p.z < top_z):
							continue
						out = (p.y - hips_joint.y) * facing
						weight = min(max(out / 0.01, 0.0), 1.0)   # (to the front / the back: not the legs' inner sides, near the middle plane;
						# from 2 cm out the cleft between the buttocks was left dipping)
						weight *= min(max((p.z - (crotch_z - drop)) / drop, 0.0), 1.0)   # (in from below the crotch, full at it)
						weight *= min(max((top_z - p.z) / GROIN_FADE_TOP, 0.0), 1.0)   # (out toward the hips)
						if weight > 0.0:
							slices.setdefault(int(math.floor(p.z / BRIDGE_STRIP)), []).append((v, weight))
					for members in slices.values():
						pts = sorted((smoothed[v].x, (smoothed[v].y - hips_joint.y) * facing) for v, _ in members)
						hull = []
						for x, out in pts:
							while len(hull) >= 2 and (hull[-1][0] - hull[-2][0]) * (out - hull[-2][1]) - (hull[-1][1] - hull[-2][1]) * (x - hull[-2][0]) >= 0.0:
								hull.pop()
							hull.append((x, out))
						for v, weight in members:
							x = smoothed[v].x
							out = (smoothed[v].y - hips_joint.y) * facing
							for k in range(len(hull) - 1):
								if hull[k][0] <= x <= hull[k + 1][0] and hull[k + 1][0] > hull[k][0]:
									env = hull[k][1] + (hull[k + 1][1] - hull[k][1]) * (x - hull[k][0]) / (hull[k + 1][0] - hull[k][0])
									if env > out:
										smoothed[v].y += facing * (env - out) * weight
									break

			bridge_groin()
			groin = groin_bridged = [v for v in bm.verts if dist[v] > 1e-6 and abs(smoothed[v].x) < GROIN_HALF_WIDTH and   # (3 cm wider reshaped the hips' sides:
					# the shirt sank 2.3 mm into the trousers there on the most muscular body)
					crotch_z - drop - 0.03 < smoothed[v].z < top_z]
			# smoothed (Taubin: the slices' steps, no shrinking), then bridged again: the smoothing pulled the middle back toward the cleft's
			# points the bridge had not moved; twice (once left the female's seat dipping ~9 mm)
			for _round in range(2):
				for step in range(16):
					weight = 0.5 if step % 2 == 0 else -0.53
					nxt = {}
					for v in groin:
						ring = [e.other_vert(v) for e in v.link_edges]
						nxt[v] = smoothed[v].lerp(sum((smoothed[o] for o in ring), Vector()) / len(ring), weight)
					smoothed.update(nxt)
				bridge_groin()
			# the cleft's two walls pressed onto one plane left triangles facing in (a shirt over them read "outside" on a flipped face and sat
			# 5 mm from the seat): such triangles' corners spread apart within the plane (x and z relaxed, y kept) until they face out again
			groin_faces = [f for f in bm.faces if all(v in set(groin) for v in f.verts)]
			groin_set = set(groin)
			for _ in range(40):
				flipped = set()
				for f in groin_faces:
					a, b, c = (smoothed[v] for v in f.verts[:3])
					n = (b - a).cross(c - a)
					centre_out = ((a.y + b.y + c.y) / 3.0 - hips_joint.y)
					want = 1.0 if centre_out > 0.0 else -1.0
					if n.length > 1e-12 and n.normalized().y * want < -0.2:
						flipped.update(f.verts)
				if not flipped:
					break
				nxt = {}
				for v in flipped:
					if v not in groin_set:
						continue
					ring = [e.other_vert(v) for e in v.link_edges]
					avg = sum((smoothed[o] for o in ring), Vector()) / len(ring)
					nxt[v] = Vector((avg.x, smoothed[v].y, avg.z))
				smoothed.update(nxt)
	for _, surfaces in lower:   # (the bridging moved points: outside the layers below again)
		tree, lower_top = surfaces[None]
		smoothed = _push_outside(bm, smoothed, tree, lower_top, dist)
	for v in bm.verts:
		move = smoothed[v] - skin[v]
		v.co = smoothed[v]
		for layer in layers:
			v[layer] = v[layer] + move
	# where the groin was bridged, each body shape's movement smoothed over the bridge: the body's own per-point movement put back the cleft's
	# walls under a muscle shape and the flat panel crumpled (the shirt read 3-4 mm inside it in the lifecycle check)
	if groin_bridged:
		for layer in layers:
			for _ in range(20):
				delta = {v: v[layer] - v.co for v in groin_bridged}
				for v in groin_bridged:
					ring = [e.other_vert(v) for e in v.link_edges]
					avg = sum(((o[layer] - o.co) if o not in delta else delta[o] for o in ring), Vector()) / len(ring)
					v[layer] = v.co + delta[v].lerp(avg, 0.5)
	# and in every body shape: outside the lower layer in that same shape (the shapes move the two garments differently)
	for _, surfaces in lower:
		for shape in BODY_SHAPES:
			layer = bm.verts.layers.shape.get(shape)
			if layer is None or shape not in surfaces:
				continue
			tree, lower_top = surfaces[shape]
			k = SHAPE_STRENGTH[shape]
			pos = _push_outside(bm, {v: v.co + (v[layer] - v.co) * k for v in bm.verts}, tree, lower_top, dist)   # (at the slider's strongest)
			for v in bm.verts:
				v[layer] = v.co + (pos[v] - v.co) / k
	if recipe.shoe:
		# footwear has its own shape (garments/footwear.py): a lofted last and a collar, with this piece's skin weights and body-shape moves
		bm = build_shoe(bm, skin, part_of, j, recipe, ease["limb"])
		layers = list(bm.verts.layers.shape.values())
	# the rolled lip at every opening, the material's depth, turned in toward the skin (footwear rolls its own top)
	rim = material.rim_depth
	boundary_edges = [] if recipe.shoe else [e for e in bm.edges if e.is_boundary]
	inner = {}
	for e in boundary_edges:
		for v in e.verts:
			if v in inner:
				continue
			# shorter where a layer below is close (the shirt's hem lip over the bridged seat came 5 mm from the trousers): it leaves at least
			# LIP_CLEARANCE to every lower layer, measured from the edge along the lip's way in
			depth = rim

			def lip_clear(depth):
				# in the base shape and in every body shape at the slider's strongest (the muscular body brought the shirt's hem lip 5 mm
				# from the trousers)
				for _, surfaces in lower:
					for shape, (tree, _top) in surfaces.items():
						layer = bm.verts.layers.shape.get(shape) if shape is not None else None
						if shape is not None and layer is None:
							continue
						base = v.co if layer is None else v.co + (v[layer] - v.co) * SHAPE_STRENGTH[shape]
						q = base - normal[v] * depth
						loc, nrm, _, d = tree.find_nearest(q)
						if loc is not None and d < 0.05 and (q - loc).dot(nrm) < LIP_CLEARANCE:
							return False
				return True
			while depth > 0.0005 and not lip_clear(depth):   # (measured at the lip's own point: where the lower layer turns sharply the
				depth *= 0.5   # edge's gap did not tell the lip's)
			w = bm.verts.new(v.co - normal[v] * depth)
			for layer in layers:
				w[layer] = v[layer] - normal[v] * depth
			inner[v] = w
	for e in boundary_edges:
		a, b = e.verts
		# wound like the cloth it continues (its face runs a -> b along this edge, so the lip runs b -> a): an arbitrary winding gave the lips
		# wrong normals, and the layer push and the checks read "inside" at a waistband's top
		f = e.link_faces[0]
		runs_ab = any(loop.vert == a and loop.link_loop_next.vert == b for loop in f.loops)
		quad = (b, a, inner[a], inner[b]) if runs_ab else (a, b, inner[b], inner[a])
		try:
			bm.faces.new(quad)
		except ValueError:
			pass
	bm.normal_update()
	cord_layer = bm.verts.layers.int.get("cord") or bm.verts.layers.int.new("cord")   # (footwear makes its own: its lace)
	if recipe.shoe and recipe.shoe.get("cords"):
		_add_cords(bm, layers, cord_layer, j, recipe)
	bm.normal_update()
	bm.to_mesh(me)
	bm.free()

	# 5. the masks
	chest_z = hips_z + 0.75 * (neck.z - hips_z)
	bm2 = bmesh.new()
	bm2.from_mesh(me)
	bm2.verts.ensure_lookup_table()
	dist2 = _surface_distance(bm2, 0.2)
	armpits = [Vector((j["shoulder_" + s].x * 0.85, j["shoulder_" + s].y, j["shoulder_" + s].z - 0.07)) for s in ("l", "r")]
	crotch = Vector((0.0, j["hips"].y, hips_z - 0.08))
	attribute = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
	cords = bm2.verts.layers.int.get("cord")
	grooves = bm2.verts.layers.float.get("groove")
	seams = bm2.verts.layers.float.get("seam")
	sole_top = None
	if recipe.shoe:
		ground_z = min(v.co.z for v in bm2.verts)
	for v in bm2.verts:
		if recipe.shoe:
			# footwear (not simulated): R the sole, G the top's hem, B a cord, A the inside drawn
			is_cord = cords is not None and v[cords] == 1   # (a rope; 2: a leather lace, B 0.5)
			is_lace = cords is not None and v[cords] == 2
			# R: the height above the ground as a ramp (1 on the ground .. 0 at SOLE_RAMP up): the shader draws the sole's edge and its seam at
			# exact heights from it (a 0/1 mask per point came out jagged between the points)
			sole = 0.0 if is_cord else max(0.0, 1.0 - (v.co.z - ground_z) / SOLE_RAMP)
			# (G: the hem's band; on a cord, how deep in the groove between its strands)
			hem_or_groove = (v[grooves] if grooves is not None else 0.0) if is_cord else max(0.0, 1.0 - dist2[v] / HEM_WIDTH,
					v[seams] if seams is not None else 0.0)   # (the vamp's seam with the hem)
			if is_lace:
				hem_or_groove = 0.0
			attribute.data[v.index].color = (sole, hem_or_groove, 1.0 if is_cord else (0.5 if is_lace else 0.0), 1.0)
			continue
		p = v.co
		part = part_of(p)
		edge_distance = dist2[v]
		near_hem = max(0.0, 1.0 - edge_distance / HEM_WIDTH)
		belt = 0.0
		if recipe.belt and waist_z is not None and p.z > waist_z - BELT_WIDTH:
			belt, near_hem = 1.0, 0.0
		inside = 1.0
		if part[0] == "torso" and arms and any((p - a).length < ARMPIT_NO_INSIDE for a in armpits):
			inside = 0.0
		if legs and (p - crotch).length < CROTCH_NO_INSIDE:
			inside = 0.0
		# freedom
		near_neck = top_at == "neck" and part[0] == "torso" and p.z > neck.z - NECK_BAND_HEIGHT
		if part[0] == "arm":
			side = part[1]
			region = "upper_arm" if part[2] < 0.0 else "forearm"
			along = segment_t(p, j["shoulder_" + side], j["elbow_" + side])[0]
			opening = recipe.openings.get("sleeves") if part[2] >= 0.0 else None
		elif part[0] == "leg":
			region = "thigh" if part[2] < 0.0 else "shin"
			along = min(max((hips_z - p.z) / 0.35, 0.0), 1.0) if region == "thigh" else part[2]
			opening = recipe.openings.get("cuffs") if part[2] >= 0.0 else None
		else:
			region, along = "torso", 0.0
			opening = recipe.openings.get("neck") if near_neck else None
		hang = min(max((chest_z - p.z) / (chest_z - hem_z), 0.0), 1.0) if hem_z is not None else 0.0
		over_layer = 0.0
		if zone_top is not None and region == "torso":   # (the torso only: the sleeves' ends hang beside the hips in the rest pose)
			over_layer = min(max((zone_top - 0.01 - p.z) / 0.03, 0.0), 1.0)
		w = freedom(region, along, hang, near_neck, opening, edge_distance, over_layer, recipe, material)
		attribute.data[v.index].color = (belt, near_hem, w, inside)
	bm2.free()
	me.color_attributes.active_color = attribute
	if "cord" in me.attributes:
		me.attributes.remove(me.attributes["cord"])
	if "groove" in me.attributes:
		me.attributes.remove(me.attributes["groove"])
	if "seam" in me.attributes:
		me.attributes.remove(me.attributes["seam"])
	# the cloth's own normals (the body's custom split normals and sharp seams lit the cloth like the skin under it)
	with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
		bpy.ops.mesh.customdata_custom_splitnormals_clear()
	for polygon in me.polygons:
		polygon.use_smooth = True
	for attribute_name in ("sharp_edge", "sharp_face"):
		if attribute_name in me.attributes:
			me.attributes.remove(me.attributes[attribute_name])
	me.name = os.path.splitext(os.path.basename(out_path))[0]
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB", export_morph=True, export_morph_normal=False,
			export_apply=False, export_vertex_color="ACTIVE")
	print(name, "written", out_path)
