"""Footwear with its own shape (garment recipes with a "shoe" field): a lofted last round the foot and a collar up the ankle, not the body's
foot surface pushed into shape (that kept the toes' gaps and creases: in game each point followed its toe bone and the toes came out torn).

Per foot: the body's foot is cut into slices from the heel to the toes; each slice's width and height (plus the ease), smoothed along the foot and
never smaller than the foot there, narrowed into a point past the toes; every slice a rounded rectangle cross-section with a flat sole;
the heel rounded in plan view and both ends closed. Over it a collar: rings round the leg from just below the ankle bone up to the shoe's top (the
leg's own cross-section, plus room), its top rolled in. Every new point takes its skin weights and its body-shape moves from the nearest body
points (an average of several: no single toe bone), so the shoe follows the skeleton and the body sliders as one piece.
"""
import math

import bmesh
from mathutils import Vector, kdtree

SLICES = 52           # the last: cross-sections from the heel to the tip (26 left facets: stripes 0.5 mm deep in the bump heatmap)
AROUND = 48           # ... points round each cross-section (and round the collar)
COLLAR_RINGS = 7      # the collar: rings from below the ankle bone to the top
COLLAR_ROOM = 0.004   # ... room round the leg (on top of the shoe's ease)
COLLAR_FLARE = 0.0    # ... widening this much more at its bottom (1.2 cm made a brim round the last; any flare a ledge on the ankle bone's side)
COLLAR_TUCK = 0.6     # ... its bottom tucked inside the last: a ring 2 cm lower at this share of the bottom ring's size
COLLAR_BELOW = 0.012  # ... starting this far below the ankle joint (inside the last; from 3.5 cm its outline took in the heel)
LAST_ABOVE_ANKLE = 0.02   # the last takes the foot's height up to this far above the ankle joint
SOLE_DROP = 0.004     # the shoe's flat sole this far under the foot's
FUSE_VOXEL = 0.004    # the last and the collar fused by a voxel remesh this fine
FUSE_SMOOTH = 15      # ... then smoothed this many passes (volume kept; 6 left a thin groove where the collar met the last)
FILL_DENTS = 50       # ... then this many outward-only passes (dents filled; 20 left a shallow one at the male's inner ankle)
WIDTH_STATIONS = ((0.13, 0.07), (0.4, 0.06), (0.7, 0.08), (0.88, 0.04), (1.0, 0.03))   # the outline's measurements, each side its own (a pattern-
# maker's: heel, waist, ball, toes): (where along the foot, 0 heel .. 1 toes' tips; how far either side the foot is measured). Behind the heel
# station the heel closes in a half circle; past the toes the toe's shape
HEIGHT_STATIONS = tuple((0.05 + 0.1 * k, 0.05) for k in range(10)) + ((1.0, 0.03),)   # (a station every 10% of the foot: with 5-6 the coverage
# loop raised the mid-foot station to 13 cm over a foot 4-7 cm high - the tall wall at the throat, a ramp from the toes)
AXIS_HEEL = 0.1       # the sole's axis: from the heel's centre (this share of the foot from its back)
HEEL_TO_BALL = 0.68    # the heel at most this share of the ball (the narrower female ball made hers 0.73-0.87)
TOE_BOX_LIFT = 0.004   # the toe box this much higher than the foot + ease + sole over the forefoot (m), faded in from 0.55 to 0.85 of the foot
TONGUE_LENGTH = 0.045  # the tongue: this long behind the throat (m; recipe field "tongue", 0 = none)
TONGUE_ROWS = 14
TONGUE_COLS = 9
BALL_STATION = 2      # (the index of the ball in WIDTH_STATIONS)
TOE_FLOORS = {3: 0.9, 4: 0.68}   # the stations toward the toes at least this share of the ball: a steady taper to a rounded tip (the foot's own
# last 3% is only the big toe: 1.5 cm, a narrow spike past a wide forefoot)
TOE_LEAN = 5.0        # the toes lean toward the inner side by this many degrees off the heel-to-toe line (a real foot, the reference sole)
AXIS_TIP = 0.96       # ... to the toes' tip (the second toe)
TOE_ROUNDNESS = {"pointed": 1.25, "almond": 1.7, "round": 2.2, "square": 5.0}   # the toe's outline: (1 - u^p)^(1/p)
HEEL_REACH = 0.18     # the heel circle takes the outline's widest value within this share of the foot from the back (0.3 took in the start of the waist-to-ball
# widening: the circle came out as wide as the foot at 0.3: measured, heel 66 mm vs 81 mm used)
SOLE_WAIST_MAX = 0.66  # the sole's waist station at most this share of its ball station (the footprint drawing: 0.70)
SOLE_HEEL_MAX = 0.60   # ... its heel station (the drawing: 0.65)
WAIST_PINCH = 0.86    # the sole's waist station this share of the foot-covering outline's: the sole waisted like a footprint (the foot is wide at the arch
# near the ground); the wall then bulges out over it, each height at least as wide as the foot there (NEED_HEIGHTS)
NEED_HEIGHTS = (0.003, 0.009, 0.016, 0.025, 0.036, 0.05)   # the foot's width measured at these heights above the ground (m), +- 6 mm
SOLE_BAND = 0.012     # the sole's outline: the foot's width up to this far above the ground
SOLE_FLARE_TOP = 0.045 # ... the upper flaring from it to the foot's full width (the ankle bones) by this height
SOLE_POINTS = 90      # the sole's outline: points along each side (denser at the round ends)
TOE_LENGTH = {"pointed": 1.0, "almond": 0.95, "round": 0.45, "square": 0.3}   # past the toes, as a share of the recipe's toe_point
OPENING_BELOW_ANKLE = 0.018   # the opening's topline this far below the ankle joint (below the ankle bone, the reference)
TOPLINE = ((-0.09, 0.006), (-0.055, 0.008), (-0.02, 0.002), (0.02, -0.006), (0.055, -0.004), (0.1, 0.0))   # the opening's topline against the
# ankle joint's place along the foot (m behind (-) or ahead (+) of it, rise (m) over the level below the ankle bone): the heel counter higher at
# the back, dipping at the ankle bones, rising a little to the throat (a flat topline made a box). The cut is made on a level plane after
# every point is dropped by this and the points are lifted back after, so the edge is clean and the rest of the shoe is unchanged
THROAT = 0.5          # ... back to the throat at this share of the foot from the heel (the vamp covers the rest)
SEAM_WIDTH = 0.002    # the vamp's seam line's half-width (m)
LACE_RADIUS = 0.0016  # the thong across the throat
WELT = 0.003          # the welt: this far out past the upper all round
OUTSOLE = 0.005       # the outsole's thickness under the foot
HEEL_HEIGHT = 0.0     # the heel's extra height under the back (0: a flat sole; a heel hangs below the outsole and sinks into the ground
# while the forefoot stands on it - the wearer stands on the outsole, ClothSetup.footwear_lift)
HEEL_END = 0.28       # ... from the back to this share of the foot
TOP_ROUND = 0.85      # the cross-section's top corners rounded by this share of the smaller of its half-width and half-height
SOLE_ROUND = 0.006    # ... its corners at the sole by this (m)
NEIGHBOURS = 8        # body points averaged for a new point's skin weights and body-shape moves


def _fuse(solid):
	"""One surface round the overlapping closed solids in `solid` (Blender's voxel remesh), as a new bmesh."""
	import bpy
	me = bpy.data.meshes.new("shoe_fuse")
	solid.to_mesh(me)
	ob = bpy.data.objects.new("shoe_fuse", me)
	bpy.context.scene.collection.objects.link(ob)
	me.remesh_voxel_size = FUSE_VOXEL
	with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
		bpy.ops.object.voxel_remesh()
	fused = bmesh.new()
	fused.from_mesh(ob.data)
	bpy.data.objects.remove(ob, do_unlink=True)
	bpy.data.meshes.remove(me)
	return fused


def _tube(out, path, radius, add, cord_layer, around=8):
	"""A round thong along path (open ends capped by its last rings), every point weighted and shaped by add(), flagged as a lace (cord 2:
	leather with the grain's depth in the shader, not a rope)."""
	rings = []
	for k, p in enumerate(path):
		tangent = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
		helper = Vector((0.0, 0.0, 1.0)) if abs(tangent.z) < 0.9 else Vector((1.0, 0.0, 0.0))
		u = tangent.cross(helper).normalized()
		v = tangent.cross(u).normalized()
		ring = []
		for m in range(around):
			b = 6.2831853 * m / around
			w = add(p + (u * math.cos(b) + v * math.sin(b)) * radius)
			w[cord_layer] = 2
			ring.append(w)
		rings.append(ring)
	for k in range(len(rings) - 1):
		for m in range(around):
			out.faces.new((rings[k][m], rings[k][(m + 1) % around], rings[k + 1][(m + 1) % around], rings[k + 1][m]))
	for ring, flip in ((rings[0], True), (rings[-1], False)):
		centre = add(sum((w.co for w in ring), Vector()) / around)
		centre[cord_layer] = 2
		for m in range(around):
			tri = (ring[(m + 1) % around], ring[m], centre) if flip else (ring[m], ring[(m + 1) % around], centre)
			out.faces.new(tri)


def _pchip(xs, ys, x):
	"""A monotone cubic through (xs, ys) at x (Fritsch-Butland slopes: between two stations the curve stays between their values, so it never
	overshoots into a lump), flat past both ends and flat at the end stations."""
	if x <= xs[0]:
		return ys[0]
	if x >= xs[-1]:
		return ys[-1]
	n = len(xs)
	h = [xs[i + 1] - xs[i] for i in range(n - 1)]
	d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
	m = [0.0] * n
	for i in range(1, n - 1):
		if d[i - 1] * d[i] > 0.0:
			m[i] = 3.0 * (h[i - 1] + h[i]) / ((2.0 * h[i] + h[i - 1]) / d[i - 1] + (h[i] + 2.0 * h[i - 1]) / d[i])
	i = max(k for k in range(n - 1) if xs[k] <= x)
	u = (x - xs[i]) / h[i]
	h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
	return h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1]


def _fit_stations(ts, raw, stations, cover=True):
	"""A designed profile along the foot: the foot's value at each station (its largest within the station's reach), a monotone cubic through
	them, and wherever the foot still stands out the nearest station raised until it holds the foot. Returns the stations (xs, values).
	(Catmull-Rom overshot round a raised station, and smooth swells added on top left steps and pinches along the sole's edge.)"""
	xs = [at for at, _ in stations]
	values = []
	for at, reach in stations:
		near = [raw[k] for k, t in enumerate(ts) if abs(t - at) <= reach]
		if cover:
			values.append(max(near) if near else 0.0)
		else:   # (the sole's outline: the typical width in the reach, not the largest, so the arch stays narrow)
			near = sorted(near)
			values.append(near[int(0.7 * (len(near) - 1))] if near else 0.0)
	values[BALL_STATION] = max(values[BALL_STATION], values[0] / HEEL_TO_BALL)   # (a real sole's heel is at most about two thirds of its ball)
	for i, share in TOE_FLOORS.items():   # (the designed taper: the toes' stations never narrower than this share of the ball's)
		values[i] = max(values[i], share * values[BALL_STATION])
	for _ in range(300 if cover else 0):
		deficit = [raw[k] - _pchip(xs, values, t) for k, t in enumerate(ts)]
		worst = max(range(len(ts)), key=lambda k: deficit[k])
		if deficit[worst] <= 1e-4:
			break
		nearest = min(range(len(xs)), key=lambda i: abs(xs[i] - ts[worst]))
		values[nearest] += deficit[worst] * 1.05 + 5e-5
	return xs, values


def _toe_shape(shape, u):
	"""The toe past the toes' tips, u 0 (the toes) .. 1 (the tip): the width's and the height's share (the user's toe shapes). The width a
	superellipse quarter (1 - u^p)^(1/p): it leaves the sides with no kink and closes round (a pointed toe nearly to a point, a square one with a
	flat front and rounded corners)."""
	p = TOE_ROUNDNESS[shape]
	w = max(1.0 - u ** p, 0.0) ** (1.0 / p)
	# the height closes to nothing together with the width (a flat slot at the tip left a square cap): an ellipse-like profile, sloping
	dome = max(1.0 - u ** 2.7, 0.0) ** (1.0 / 2.7) * (1.0 - 0.08 * u)
	h = {"square": 1.0 - 0.35 * u * u, "round": 1.0 - 0.45 * u * u, "almond": dome}.get(shape, 1.0 - 0.7 * u ** 1.2)
	return w, h


def _rounded_box(x, z, half_w, half_h, r):
	"""The signed distance from (x, z) to a rectangle of half-sizes half_w, half_h with corners rounded by r (negative inside)."""
	qx, qz = abs(x) - (half_w - r), abs(z) - (half_h - r)
	return math.hypot(max(qx, 0.0), max(qz, 0.0)) + min(max(qx, qz), 0.0) - r


def build_shoe(src, skin, part_of, j, recipe, ease):
	"""A new bmesh: both shoes (last + collar + rolled top), with the source mesh's shape layers and skin weights carried over from the body.
	src: the garment's bmesh cut from the body (its points' v.co may already be moved; their body positions are skin[v], their body-shape moves
	v[layer] - v.co); j: the joints; ease: room over the foot (m)."""
	shoe = recipe.shoe
	out = bmesh.new()
	src_deform = src.verts.layers.deform.active
	deform = out.verts.layers.deform.verify()
	src_layers = list(src.verts.layers.shape.values())
	out_layers = [out.verts.layers.shape.new(layer.name) for layer in src_layers]
	cord_layer = out.verts.layers.int.new("cord")      # (the lace: drawn as cord, B)
	seam_layer = out.verts.layers.float.new("seam")    # (the vamp's seam: G with the hem)
	for side in ("l", "r"):
		verts = [v for v in src.verts if part_of(skin[v])[0] == "leg" and part_of(skin[v])[1] == side]
		if not verts:
			continue
		near = kdtree.KDTree(len(verts))
		for i, v in enumerate(verts):
			near.insert(skin[v], i)
		near.balance()

		def carried(p):
			"""Skin weights and body-shape moves for a new point at p, from the nearest body points (inverse distance)."""
			found = near.find_n(p, NEIGHBOURS)
			total = 0.0
			weights = {}
			moves = [Vector() for _ in src_layers]
			for _, index, d in found:
				v = verts[index]
				w = 1.0 / max(d, 0.002)
				total += w
				if src_deform is not None:
					for group, value in v[src_deform].items():
						weights[group] = weights.get(group, 0.0) + value * w
				for k, layer in enumerate(src_layers):
					moves[k] += (v[layer] - v.co) * w
			strongest = sorted(weights.items(), key=lambda item: -item[1])[:4]
			s = sum(value for _, value in strongest) or 1.0
			return {g: value / s for g, value in strongest}, [m / total for m in moves]

		def add(p):
			w = out.verts.new(p)
			weights, moves = carried(p)
			for group, value in weights.items():
				w[deform][group] = value
			for k, layer in enumerate(out_layers):
				w[layer] = p + moves[k]
			return w

		ankle, toe = j["ankle_" + side], j["toe_" + side]
		knee = j["knee_" + side]
		forward = Vector((toe.x - ankle.x, toe.y - ankle.y, 0.0)).normalized()
		lateral = forward.cross(Vector((0.0, 0.0, 1.0))).normalized()
		ground = min(skin[v].z for v in verts)
		foot = [v for v in verts if skin[v].z < ankle.z + LAST_ABOVE_ANKLE]   # (a little above the ankle joint: the instep in front of the ankle
		# fell between the last's top and the collar and showed through, 9 mm out)
		along = {v: (skin[v] - ankle).dot(forward) for v in foot}
		back, front = min(along.values()), max(along.values())
		length = max(front - back, 1e-4)
		lo, hi, height = [1e9] * SLICES, [-1e9] * SLICES, [0.0] * SLICES
		lo_low, hi_low = [1e9] * SLICES, [-1e9] * SLICES   # (the foot's width near the ground only: the sole's outline)
		ext = [[[1e9, -1e9] for _ in range(SLICES)] for _ in NEED_HEIGHTS]   # (the foot's sideways extent per height band and slice)
		for v in foot:
			k = min(int((along[v] - back) / length * SLICES), SLICES - 1)
			sideways = (skin[v] - ankle).dot(lateral)
			lo[k], hi[k] = min(lo[k], sideways), max(hi[k], sideways)
			height[k] = max(height[k], skin[v].z - ground)
			for b, hb in enumerate(NEED_HEIGHTS):
				if abs(skin[v].z - ground - hb) <= 0.005:
					ext[b][k][0], ext[b][k][1] = min(ext[b][k][0], sideways), max(ext[b][k][1], sideways)
			if skin[v].z < ground + SOLE_BAND:
				lo_low[k], hi_low[k] = min(lo_low[k], sideways), max(hi_low[k], sideways)
		for k in range(SLICES):
			if lo[k] > hi[k]:
				lo[k], hi[k] = (lo[k - 1], hi[k - 1]) if k else (0.0, 0.0)
			if lo_low[k] > hi_low[k]:
				lo_low[k], hi_low[k] = lo[k], hi[k]
		# the outline and the height along the foot as a designed shape (the user's sole outlines: one smooth curve, heel - waist - ball - toe),
		# not traced slice by slice (traced and smoothed, it kept the foot's unevenness: wavy sides, a square heel): a few measurements of the
		# foot, one smooth curve through them (Catmull-Rom), and wherever the foot still stands out the nearest measurement raised and the curve
		# drawn again, so the shoe always holds the foot. The middle line: straight (a line through the slices' middles)
		ts = [(k + 0.5) / SLICES for k in range(SLICES)]
		raw_mid = [0.5 * (lo[k] + hi[k]) for k in range(SLICES)]
		height = list(height)
		# the axis (the user's sole diagram): straight from the heel's centre to the toes' tip (the second toe), and the widths each side of it
		# measured and drawn on their own - a sole is wider on the inner side at the ball (a quadratic middle followed the foot's curve and
		# the sole bent like a C; a symmetric outline round a fitted line was neither)
		def mean_near(at, reach):
			near = [raw_mid[k] for k, t in enumerate(ts) if abs(t - at) <= reach]
			return sum(near) / len(near) if near else 0.0
		heel_mid, tip_mid = mean_near(AXIS_HEEL, 0.05), mean_near(AXIS_TIP, 0.04)
		# the inner side is the one the ball is wider on; the toes lean toward it
		ball = [k for k, t in enumerate(ts) if abs(t - 0.7) <= 0.08]
		line0 = lambda t: heel_mid + (tip_mid - heel_mid) * (t - AXIS_HEEL) / (AXIS_TIP - AXIS_HEEL)
		inner = 1.0 if sum(hi[k] - line0(ts[k]) for k in ball) > sum(line0(ts[k]) - lo[k] for k in ball) else -1.0   # (toward the wider side)
		tip_mid += inner * (AXIS_TIP - AXIS_HEEL) * length * math.tan(math.radians(TOE_LEAN))

		def mid_at(t):
			return heel_mid + (tip_mid - heel_mid) * (t - AXIS_HEEL) / (AXIS_TIP - AXIS_HEEL)
		hi_st = _fit_stations(ts, [hi[k] - mid_at(ts[k]) for k in range(SLICES)], WIDTH_STATIONS)
		lo_st = _fit_stations(ts, [mid_at(ts[k]) - lo[k] for k in range(SLICES)], WIDTH_STATIONS)
		height_st = _fit_stations(ts, height, HEIGHT_STATIONS)
		# the sole's outline from the foot's width near the ground (measured up to the ankle, the ankle bones made the heel as wide as the
		# ball); the upper flares out from it above SOLE_BAND to the full width (ring_point)
		hi_low_st = _fit_stations(ts, [hi_low[k] - mid_at(ts[k]) for k in range(SLICES)], WIDTH_STATIONS)
		lo_low_st = _fit_stations(ts, [mid_at(ts[k]) - lo_low[k] for k in range(SLICES)], WIDTH_STATIONS)
		def _pinch(st):
			xs, vs = st
			vs = list(vs)
			ball = vs[BALL_STATION]
			vs[1] = min(vs[1] * WAIST_PINCH, SOLE_WAIST_MAX * ball)   # (the sole's waist and heel as shares of its ball, whatever the foot's own)
			vs[0] = min(vs[0], SOLE_HEEL_MAX * ball)
			return xs, vs
		hi_low_st, lo_low_st = _pinch(hi_low_st), _pinch(lo_low_st)
		# how wide the foot is at each height, along the foot (relative to the axis): holes (no points in a band) filled from the neighbours, then
		# the upper envelope smoothed (running maximum over 2 slices each side, then an average), 1.5 mm extra
		need_hi, need_lo = [], []
		for b in range(len(NEED_HEIGHTS)):
			for side_k, store in ((1, need_hi), (0, need_lo)):
				raw = []
				for k in range(SLICES):
					e = ext[b][k]
					if e[0] > e[1]:
						raw.append(None)
					else:
						raw.append((e[1] - mid_at(ts[k])) if side_k == 1 else (mid_at(ts[k]) - e[0]))
				known = [k for k in range(SLICES) if raw[k] is not None]
				for k in range(SLICES):
					if raw[k] is None:
						raw[k] = raw[min(known, key=lambda q: abs(q - k))] if known else 0.0
				env = [max(raw[max(k - 4, 0):k + 5]) for k in range(SLICES)]
				store.append([sum(env[max(k - 2, 0):k + 3]) / len(env[max(k - 2, 0):k + 3]) + 0.004 for k in range(SLICES)])

		def need_at(t, hz, hi_side):
			"""The foot's half width (beyond the axis) at height hz above the shoe's bottom, along the foot at t; 0 below the foot's sole."""
			table = need_hi if hi_side else need_lo
			kf = min(max(t * SLICES - 0.5, 0.0), SLICES - 1.0)
			k0 = int(kf)
			k1 = min(k0 + 1, SLICES - 1)
			w = kf - k0
			vals = [table[b][k0] * (1.0 - w) + table[b][k1] * w for b in range(len(NEED_HEIGHTS))]
			hs = [hb + SOLE_DROP for hb in NEED_HEIGHTS]
			if hz <= SOLE_DROP:
				return 0.0
			if hz <= hs[0]:
				return vals[0] * (hz - SOLE_DROP) / (hs[0] - SOLE_DROP)
			for b in range(len(hs) - 1):
				if hz <= hs[b + 1]:
					u = (hz - hs[b]) / (hs[b + 1] - hs[b])
					return vals[b] * (1.0 - u) + vals[b + 1] * u
			return vals[-1]
		toe_shape = shoe.get("toe_shape", "pointed")
		toe_len = shoe["toe_point"] * TOE_LENGTH[toe_shape]   # (how far past the toes the shoe goes: the shape's share of toe_point)
		# the heel: a half circle of the heel's own width (each side its radius), its back far enough behind the foot's that the circle holds
		# the foot's heel (a short round over 1 cm ended in a flat wall)
		r_hi = max(_pchip(*hi_st, t) for t in ts if t < HEEL_REACH) + ease
		r_lo = max(_pchip(*lo_st, t) for t in ts if t < HEEL_REACH) + ease
		rs_hi = max(_pchip(*hi_low_st, t) for t in ts if t < HEEL_REACH) + ease
		rs_lo = max(_pchip(*lo_low_st, t) for t in ts if t < HEEL_REACH) + ease
		heel_back = ease + 0.002
		for k in range(SLICES):
			if ts[k] > 0.35:
				continue
			x_foot = k / SLICES * length   # (the slice's back edge, from the foot's back)
			for r, w in ((r_hi, hi[k] - mid_at(ts[k]) + ease), (r_lo, mid_at(ts[k]) - lo[k] + ease)):
				if 0.0 < w < r:
					heel_back = max(heel_back, r - math.sqrt(r * r - w * w) - x_foot)
				elif w >= r:
					heel_back = max(heel_back, r - x_foot)
		t_start = -heel_back / length
		t_end = 1.0 + toe_len / length

		def circle(t, r):
			x = t * length + heel_back   # (from the shoe's back)
			return math.sqrt(max(r * r - (r - x) ** 2, 0.0)) if x < r else 1e9

		def section(t):
			m = mid_at(t)
			a_lo = min(_pchip(*lo_st, t) + ease, circle(t, r_lo))
			a_hi = min(_pchip(*hi_st, t) + ease, circle(t, r_hi))
			h = max(_pchip(*height_st, t), 0.02) + ease + shoe["sole"]
			ramp = min(max((t - 0.65) / 0.25, 0.0), 1.0)
			h += TOE_BOX_LIFT * ramp * ramp * (3.0 - 2.0 * ramp)   # (room over the toes: a real toe box is deeper than the foot)
			r_mean = 0.5 * (r_lo + r_hi)
			h *= 0.55 + 0.45 * min(circle(t, r_mean) / r_mean, 1.0)   # (the heel's back rounded in side view too)
			if t > 1.0:   # (past the toes: the toe's shape, narrowing and lowering to a close)
				u = min((t - 1.0) / max(t_end - 1.0, 1e-4), 1.0)
				wf, hf = _toe_shape(toe_shape, u)
				a_lo *= wf
				a_hi *= wf
				h *= hf
			return m, max(a_lo, 0.0), max(a_hi, 0.0), h

		def sole_section(t):
			"""The sole's outline at t: the middle and each side's width (never wider than the upper's)."""
			m, a_lo, a_hi, _ = section(t)
			s_lo = min(_pchip(*lo_low_st, t) + ease, circle(t, rs_lo))
			s_hi = min(_pchip(*hi_low_st, t) + ease, circle(t, rs_hi))
			if t > 1.0:
				wf, _ = _toe_shape(toe_shape, min((t - 1.0) / max(t_end - 1.0, 1e-4), 1.0))
				s_lo *= wf
				s_hi *= wf
			return m, min(max(s_lo, 0.0), a_lo), min(max(s_hi, 0.0), a_hi)

		def ring_point(t, angle):
			# the cross-section: a rounded rectangle from the sole (SOLE_DROP under the foot's) to the top, its sides each their own width;
			# big rounds where the sides turn into the top (a superellipse left a hard corner along the whole shoe: a box from the front),
			# small ones at the sole (flat right out to its edge: rounder corners there let the foot's sole edge show)
			m, a_lo, a_hi, h = section(t)
			bottom, top = ground - SOLE_DROP, ground + h
			half_w = 0.5 * (a_lo + a_hi)
			half_h = 0.5 * (top - bottom)
			cx = m + 0.5 * (a_hi - a_lo)
			cz = bottom + half_h
			r_top = TOP_ROUND * min(half_w, half_h)
			r_bottom = min(SOLE_ROUND, 0.5 * min(half_w, half_h))
			dx, dz = math.cos(angle), math.sin(angle)
			lo_s, hi_s = 0.0, 2.0 * max(half_w, half_h) + 0.01
			for _ in range(24):   # (along the ray from the middle to the rounded rectangle's edge)
				mid_s = 0.5 * (lo_s + hi_s)
				if _rounded_box(mid_s * dx, mid_s * dz, half_w, half_h, r_top if dz > 0.0 else r_bottom) < 0.0:
					lo_s = mid_s
				else:
					hi_s = mid_s
			sx, sz = cx + lo_s * dx, cz + lo_s * dz
			# near the ground the sides pulled in to the sole's outline, flaring out to the full width above SOLE_BAND .. SOLE_FLARE_TOP
			_, s_lo, s_hi = sole_section(t)
			g = min(max((sz - bottom - SOLE_BAND) / (SOLE_FLARE_TOP - SOLE_BAND), 0.0), 1.0)
			g = g * g * (3.0 - 2.0 * g)
			rel = sx - m
			full = a_hi if rel > 0.0 else a_lo
			narrow = s_hi if rel > 0.0 else s_lo
			narrow = max(narrow, min(full, need_at(t, sz - bottom, rel > 0.0) + ease))   # (the wall at least as wide as the foot at this height)
			share = narrow / full if full > 1e-6 else 1.0
			sx = m + rel * (share + (1.0 - share) * g)
			p = ankle + forward * (back + t * length) + lateral * sx
			p.z = sz
			return p

		# a 16th-century low shoe (the user's reference sheet: vamp, quarter, inside counter, welt, outsole, heel): the last as one closed solid,
		# voxel-remeshed and smoothed (one clean surface), the opening cut below the ankle from the heel to the throat, its edge rolled in; a
		# thong laced across the throat; the welt, the outsole and the heel as their own layers under it; a seam where the vamp meets the quarter
		solid = bmesh.new()
		t_values = [t_start + (t_end - t_start) * 0.5 * (1.0 - math.cos(math.pi * i / (SLICES - 1))) for i in range(SLICES)]   # (denser at
		# the round ends)
		rings = [[solid.verts.new(ring_point(t, 6.2831853 * a / AROUND)) for a in range(AROUND)] for t in t_values]
		for i in range(SLICES - 1):
			for a in range(AROUND):
				solid.faces.new((rings[i][a], rings[i][(a + 1) % AROUND], rings[i + 1][(a + 1) % AROUND], rings[i + 1][a]))
		for ring in (rings[0], rings[-1]):   # (both ends closed)
			centre = solid.verts.new(sum((v.co for v in ring), Vector()) / AROUND)
			for a in range(AROUND):
				solid.faces.new((ring[a], ring[(a + 1) % AROUND], centre))
		bmesh.ops.recalc_face_normals(solid, faces=solid.faces[:])
		fused = _fuse(solid)
		solid.free()
		for _ in range(FUSE_SMOOTH):   # (smoothed, volume kept)
			bmesh.ops.smooth_laplacian_vert(fused, verts=fused.verts[:], lambda_factor=0.5, lambda_border=0.0, use_x=True, use_y=True,
					use_z=True, preserve_volume=True)
		# the opening: everything above the topline (below the ankle bone) from the heel back to the throat, cut on two planes for a clean edge
		opening_z = ankle.z - shoe.get("opening_below_ankle", OPENING_BELOW_ANKLE)
		throat_along = back + shoe.get("throat", THROAT) * length
		throat_point = ankle + forward * throat_along
		top_xs, top_ys = [a for a, _ in TOPLINE], [r for _, r in TOPLINE]

		def topline_rise(point):
			return _pchip(top_xs, top_ys, (point - ankle).dot(forward))
		for v in fused.verts:
			v.co.z -= topline_rise(v.co)
		for co, no in ((Vector((0.0, 0.0, opening_z)), Vector((0.0, 0.0, 1.0))), (throat_point, forward)):
			bmesh.ops.bisect_plane(fused, geom=fused.verts[:] + fused.edges[:] + fused.faces[:], plane_co=co, plane_no=no)
		cut = [f for f in fused.faces if f.calc_center_median().z > opening_z + 1e-5 and (f.calc_center_median() - ankle).dot(forward) < throat_along - 1e-5]
		bmesh.ops.delete(fused, geom=cut, context="FACES")
		loose = [v for v in fused.verts if not v.link_faces]
		bmesh.ops.delete(fused, geom=loose, context="VERTS")
		for v in fused.verts:   # (lifted back: the cut edge follows the topline)
			v.co.z += topline_rise(v.co)
		# into the shoe, with weights and shapes carried over
		made = {v: add(v.co) for v in fused.verts}
		for f in fused.faces:
			out.faces.new([made[v] for v in f.verts])
		# the opening's edge rolled in: a lip the material's depth inward (toward the opening's middle) and a little down
		rim_edges = [e for e in fused.edges if e.is_boundary]
		rim_verts = {v for e in rim_edges for v in e.verts}
		middle = sum((v.co for v in rim_verts), Vector()) / max(len(rim_verts), 1)
		lip = {v: add(v.co + Vector((middle.x - v.co.x, middle.y - v.co.y, 0.0)).normalized() * 0.004 - Vector((0.0, 0.0, 0.003)))
				for v in rim_verts}
		for e in rim_edges:
			a, b = e.verts
			f = e.link_faces[0]
			runs_ab = any(loop.vert == a and loop.link_loop_next.vert == b for loop in f.loops)
			quad = (made[b], made[a], lip[a], lip[b]) if runs_ab else (made[a], made[b], lip[b], lip[a])
			try:
				out.faces.new(quad)
			except ValueError:
				pass
		# the seam where the vamp meets the quarter: the distance from the throat's upright plane, for the masks (G: a stitched line)
		for v, w in made.items():
			w[seam_layer] = max(0.0, 1.0 - abs((v.co - ankle).dot(forward) - throat_along) / SEAM_WIDTH)
		# the lace: a leather thong across the throat, from one side of the opening to the other over the instep, tied in the middle, its two
		# ends hanging over the vamp; laid on the shoe (rays) and lifted off it by its thickness
		from mathutils.bvhtree import BVHTree as _Tree
		tree = _Tree.FromBMesh(fused)
		lace_r = shoe.get("lace", LACE_RADIUS)

		def on_surface(p, lift):
			hit = tree.ray_cast(p + Vector((0.0, 0.0, 0.2)), Vector((0.0, 0.0, -1.0)), 0.4)
			if hit[0] is None:
				return p
			return hit[0] + hit[1] * lift

		edge_pts = [v.co for v in rim_verts if abs((v.co - ankle).dot(forward) - throat_along) < 0.006]
		if len(edge_pts) >= 2:
			side_a = max(edge_pts, key=lambda q: (q - ankle).dot(lateral))
			side_b = min(edge_pts, key=lambda q: (q - ankle).dot(lateral))
			knot = on_surface((side_a + side_b) * 0.5 + forward * 0.008, lace_r * 2.2)
			paths = []
			for start in (side_a, side_b):
				arc = [on_surface(start.lerp(knot, u) + Vector((0.0, 0.0, 0.006 * math.sin(math.pi * u))), lace_r * 1.3) for u in
						[k / 11.0 for k in range(12)]]
				paths.append(arc)
			for sign in (1.0, -1.0):   # (the two ends: from the knot down over the vamp, a little apart)
				tail = [on_surface(knot + forward * (0.012 * u + 0.02 * u * u) + lateral * (sign * 0.012 * u), lace_r * 1.3) for u in
						[k / 9.0 for k in range(10)]]
				paths.append(tail)
			for path in paths:
				_tube(out, path, lace_r, add, cord_layer)
			_tube(out, [knot - lateral * 0.005, knot, knot + lateral * 0.005], lace_r * 2.2, add, cord_layer)   # (the knot: a short, thick twist)
		# the tongue: a flap of leather (2 mm thick) lying on the instep behind the throat, tucked under the vamp's edge, over the foot's top (a real
		# shoe's opening shows a tongue, not bare skin); each point lifted off the foot's top by the skin's own height there
		if len(edge_pts) >= 2 and shoe.get("tongue", TONGUE_LENGTH) > 0.0:
			t_len = shoe.get("tongue", TONGUE_LENGTH)
			l_centre = (((side_a + side_b) * 0.5) - ankle).dot(lateral)
			half = 0.5 * (side_a - side_b).dot(lateral) * 0.86
			foot_pts = [skin[v] for v in verts]

			rows, cols = TONGUE_ROWS, TONGUE_COLS
			# the foot's top along the middle line (the highest skin point within 2 cm of it), smoothed along the foot, and a gentle drop to the sides
			centre_z = []
			for i in range(rows):
				u = i / (rows - 1)
				base = ankle + forward * (throat_along + 0.006 - t_len * u) + lateral * l_centre
				zs = [q.z for q in foot_pts if (q.x - base.x) ** 2 + (q.y - base.y) ** 2 < 0.02 ** 2]
				centre_z.append(max(zs) if zs else (centre_z[-1] if centre_z else ankle.z - 0.05))
			centre_z = [min(z, opening_z - 0.006) for z in centre_z]   # (the tongue lies below the topline, not up the shin)
			for _ in range(6):
				centre_z = [centre_z[max(k - 1, 0)] * 0.25 + centre_z[k] * 0.5 + centre_z[min(k + 1, rows - 1)] * 0.25 for k in range(rows)]
			grid_top, grid_bottom = [], []
			for i in range(rows):
				u = i / (rows - 1)
				a_pos = throat_along + 0.006 - t_len * u   # (from just under the vamp's edge back toward the ankle)
				w = half * (1.0 - 0.22 * u)
				top_row, bottom_row = [], []
				for jc in range(cols):
					across = 2.0 * jc / (cols - 1) - 1.0
					base = ankle + forward * a_pos + lateral * (l_centre + w * across)
					z = centre_z[i] - 0.007 * across * across   # (the instep is rounded across)
					z += 0.0042 + 0.002 * (1.0 - u)             # (lifted off the skin; a little more at the vamp's edge)
					top_row.append(add(Vector((base.x, base.y, z + 0.0022))))
					bottom_row.append(add(Vector((base.x, base.y, z))))
				grid_top.append(top_row)
				grid_bottom.append(bottom_row)
			made_faces = []
			for i in range(rows - 1):
				for jc in range(cols - 1):
					for quad in ((grid_top[i][jc], grid_top[i][jc + 1], grid_top[i + 1][jc + 1], grid_top[i + 1][jc]),
							(grid_bottom[i][jc], grid_bottom[i + 1][jc], grid_bottom[i + 1][jc + 1], grid_bottom[i][jc + 1])):
						try:
							made_faces.append(out.faces.new(quad))
						except ValueError:
							pass
			for i in range(rows - 1):   # (the two long sides)
				for jc in (0, cols - 1):
					quad = (grid_top[i][jc], grid_top[i + 1][jc], grid_bottom[i + 1][jc], grid_bottom[i][jc])
					try:
						made_faces.append(out.faces.new(quad if jc == cols - 1 else quad[::-1]))
					except ValueError:
						pass
			for i in (0, rows - 1):   # (the two ends)
				for jc in range(cols - 1):
					quad = (grid_top[i][jc], grid_top[i][jc + 1], grid_bottom[i][jc + 1], grid_bottom[i][jc])
					try:
						made_faces.append(out.faces.new(quad if i == 0 else quad[::-1]))
					except ValueError:
						pass
			bmesh.ops.recalc_face_normals(out, faces=made_faces)
		# the sole: a welt a little out round the foot's outline, an outsole under it, and a heel under the back
		welt = shoe.get("welt", WELT)
		outsole = shoe.get("outsole", OUTSOLE)
		heel_h = shoe.get("heel", HEEL_HEIGHT)
		# the outline: each side from the heel's back to the toe's tip (both ends width 0: one closed curve), as one ring (x along, y sideways)
		n = SOLE_POINTS
		sole_ts = [t_start + (t_end - t_start) * 0.5 * (1.0 - math.cos(math.pi * i / (n - 1))) for i in range(n)]
		hi_pts, lo_pts = [], []
		for t in sole_ts:
			m, a_lo, a_hi = sole_section(t)
			hi_pts.append((back + t * length, m + a_hi))
			lo_pts.append((back + t * length, m - a_lo))
		ring2d = hi_pts + lo_pts[-2:0:-1]
		ring_t = sole_ts + sole_ts[-2:0:-1]
		count = len(ring2d)
		area = sum(ring2d[k][0] * ring2d[(k + 1) % count][1] - ring2d[(k + 1) % count][0] * ring2d[k][1] for k in range(count))
		normals = []
		for k in range(count):
			tx = ring2d[(k + 1) % count][0] - ring2d[k - 1][0]
			ty = ring2d[(k + 1) % count][1] - ring2d[k - 1][1]
			nx, ny = (-ty, tx) if area < 0.0 else (ty, -tx)
			ln = math.hypot(nx, ny) or 1.0
			normals.append((nx / ln, ny / ln))
		top_z = ground - SOLE_DROP + 0.002   # (a little inside the upper's sole: no gap)
		layers = []
		for out_by, dz in ((0.0, 0.0), (welt, -0.001), (welt, None), (welt - 0.002, None)):   # (top, welt top, welt bottom, the outsole's edge)
			layer = []
			for k in range(count):
				t = ring_t[k]
				bottom = ground - SOLE_DROP - outsole - (heel_h * (1.0 - min(max((t - HEEL_END) / 0.05, 0.0), 1.0)) if t < HEEL_END + 0.05 else 0.0)
				z = top_z + dz if dz is not None else (bottom + 0.001 if out_by == welt else bottom)
				x, y = ring2d[k][0] + normals[k][0] * out_by, ring2d[k][1] + normals[k][1] * out_by
				q = ankle + forward * x + lateral * y
				q.z = z
				layer.append(add(q))
			layers.append(layer)
		sole_faces = []
		for a_l, b_l in zip(layers, layers[1:]):
			for k in range(count):
				sole_faces.append(out.faces.new((a_l[k], a_l[(k + 1) % count], b_l[(k + 1) % count], b_l[k])))
		for layer in (layers[0], layers[-1]):   # (the top and the bottom: strips across, side to side)
			sole_faces.append(out.faces.new((layer[0], layer[1], layer[count - 1])))
			for i in range(1, n - 2):
				sole_faces.append(out.faces.new((layer[i], layer[i + 1], layer[count - i - 1], layer[count - i])))
			sole_faces.append(out.faces.new((layer[n - 2], layer[n - 1], layer[n])))
		bmesh.ops.recalc_face_normals(out, faces=sole_faces)
		fused.free()
	out.normal_update()
	return out
