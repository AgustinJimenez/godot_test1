extends SceneTree
## Headless check of the native head hair (HumanHair): builds hair on both base bodies and checks the result.
##   godot --headless --path . -s res://tests/manual/humans/human_hair_check.gd
## Prints HUMAN_HAIR_CHECK PASS or FAIL lines and exits with a nonzero code on failure.

const BODIES: Dictionary = {
	"male": "res://assets/models/humans/male_body.glb",
	"female": "res://assets/models/humans/female_body.glb",
}

var _failures: int = 0


func _init() -> void:
	if not ClassDB.class_exists(&"HumanHair"):
		_fail("HumanHair is not registered (is the native library built?)")
		quit(1)
		return
	for gender: String in BODIES:
		_check_body(gender)
	if _failures == 0:
		print("HUMAN_HAIR_CHECK PASS")
	else:
		print("HUMAN_HAIR_CHECK FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_body(gender: String) -> void:
	var packed: PackedScene = load(BODIES[gender])
	var root: Node = packed.instantiate()
	var body: ArrayMesh = _find_mesh(root)
	if body == null:
		_fail("%s: no ArrayMesh in the body" % gender)
		return
	var params: Dictionary = HumanHair.default_params_for(gender)
	# the default eye_drop is the real drop of the eye landmarks (tools/blender/landmarks, Blender z is up) below the top of the body
	var landmarks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/blender/landmarks/%s_landmarks.json" % gender))
	var eye_height: float = float((landmarks["basis"]["eye_l"] as Array)[2])
	var body_top: float = -INF
	for v: Vector3 in (body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		body_top = maxf(body_top, v.y)
	_expect(absf(float(params["eye_drop"]) - (body_top - eye_height)) < 0.002, "%s: default eye_drop %.4f but the landmarks say %.4f" % [gender, float(params["eye_drop"]), body_top - eye_height])
	# the body is read once and kept: the second prepare gives the same object
	var data: HumanHairBody = HumanHair.prepare(body)
	_expect(data.is_valid() and data.get_vertex_count() == (body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "%s: prepare did not read the body" % gender)
	_expect(HumanHair.prepare(body) == data, "%s: prepare did not keep the body data" % gender)
	var kept_names: Array[StringName] = _hair_shape_names(body)
	_expect(kept_names.size() == 6 and data.get_shape_count() == kept_names.size(), "%s: prepare read %d shapes, the body has %d height/weight/muscle shapes" % [gender, data.get_shape_count(), kept_names.size()])
	var hair: ArrayMesh = HumanHair.build(body, params)
	if hair == null or hair.get_surface_count() != 1:
		_fail("%s: build returned no surface" % gender)
		return
	var arrays: Array = hair.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_expect(vertices.size() > 2000, "%s: only %d vertices" % [gender, vertices.size()])
	# the hair is on the head: finite, above the neck, not far above the crown
	var top_y: float = -INF
	for v: Vector3 in (body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		top_y = maxf(top_y, v.y)
	var low: float = INF
	var high: float = -INF
	var finite: bool = true
	for v: Vector3 in vertices:
		finite = finite and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
		low = minf(low, v.y)
		high = maxf(high, v.y)
	_expect(finite, "%s: a vertex is not finite" % gender)
	_expect(high < top_y + 0.12, "%s: hair reaches %.2f above the crown" % [gender, high - top_y])
	_expect(low > top_y - 0.55, "%s: hair reaches %.2f below the crown" % [gender, top_y - low])
	# the same blend shapes as the body, so the body's sliders move the hair
	# (the face and age keys of the body are not hair blend shapes: they are baked into the body the hair is built on)
	_expect(hair.get_blend_shape_count() == kept_names.size() and kept_names.size() > 0,
			"%s: %d blend shapes against the body's %d height/weight/muscle shapes" % [gender, hair.get_blend_shape_count(), kept_names.size()])
	for i: int in hair.get_blend_shape_count():
		_expect(hair.get_blend_shape_name(i) == kept_names[i], "%s: blend shape %d is named %s, the body's is %s" % [gender, i, hair.get_blend_shape_name(i), kept_names[i]])
	# blend shapes are NORMALIZED: full positions, and the normals and tangents of the base (a zero normal delta used to pull hair normals backwards)
	var base_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var shape_arrays: Array = hair.surface_get_blend_shape_arrays(0)
	_expect(hair.get_blend_shape_mode() == Mesh.BLEND_SHAPE_MODE_NORMALIZED, "%s: hair blend shapes are not NORMALIZED" % gender)
	for s: int in shape_arrays.size():
		var shape_normals: PackedVector3Array = (shape_arrays[s] as Array)[Mesh.ARRAY_NORMAL]
		var worst: float = 0.0
		for i: int in range(0, shape_normals.size(), 11):
			worst = maxf(worst, (shape_normals[i] - base_normals[i]).length())
		_expect(worst < 0.01, "%s: shape %d normals differ from the base by %.3f" % [gender, s, worst])
	# the mesh bounds must contain the body-moved hair (the engine grows them from the shape arrays)
	var tall_index: int = -1 # (an index into the HAIR's shapes)
	for i: int in hair.get_blend_shape_count():
		if hair.get_blend_shape_name(i) == &"height_tall":
			tall_index = i
	_expect(tall_index >= 0, "%s: the body has no height_tall shape" % gender)
	if tall_index < 0:
		root.free()
		return
	var shape_top: float = -INF
	for p: Vector3 in ((shape_arrays[tall_index] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		shape_top = maxf(shape_top, p.y)
	_expect(hair.get_aabb().end.y >= shape_top - 0.001, "%s: bounds end at %.3f, below the tall-shape hair top %.3f" % [gender, hair.get_aabb().end.y, shape_top])
	# the hair follows the head in every shape: the scalp cap (blue vertex colour = 1) moves with the body's scalp, so at Height +-1 the hair is not left behind
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var body_vertices: PackedVector3Array = body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var body_shapes: Array = body.surface_get_blend_shape_arrays(0)
	for s: int in shape_arrays.size():
		var hair_move: float = 0.0
		var cap_count: int = 0
		for i: int in colors.size():
			if colors[i].b > 0.5:
				hair_move += ((shape_arrays[s] as Array)[Mesh.ARRAY_VERTEX][i] as Vector3).y - vertices[i].y
				cap_count += 1
		hair_move /= maxf(cap_count, 1)
		# the same measure on the body: the average vertical move of the vertices of the head (the top 14 cm)
		var body_move: float = 0.0
		var head_count: int = 0
		var body_index: int = -1 # (the same shape in the body, by name)
		for b: int in body.get_blend_shape_count():
			if body.get_blend_shape_name(b) == hair.get_blend_shape_name(s):
				body_index = b
		_expect(body_index >= 0, "%s: the body has no shape %s" % [gender, hair.get_blend_shape_name(s)])
		if body_index < 0:
			continue
		var body_shape_vertices: PackedVector3Array = (body_shapes[body_index] as Array)[Mesh.ARRAY_VERTEX]
		for i: int in body_vertices.size():
			if body_vertices[i].y > top_y - 0.14:
				body_move += body_shape_vertices[i].y - (body_vertices[i].y if body.get_blend_shape_mode() == Mesh.BLEND_SHAPE_MODE_NORMALIZED else 0.0)
				head_count += 1
		body_move /= maxf(head_count, 1)
		_expect(absf(hair_move - body_move) < 0.02, "%s: shape %d moves the head %.3f m but the hair cap %.3f m" % [gender, s, body_move, hair_move])
	# the three steps give the same hair as build(), and build_arrays touches no engine object (it may run on a worker thread)
	var built: Dictionary = HumanHair.build_arrays(data, params)
	_expect(built.has("arrays") and built.has("blend_arrays") and (built["blend_names"] as PackedStringArray).size() == kept_names.size(), "%s: build_arrays result is incomplete" % gender)
	var stepped: ArrayMesh = HumanHair.make_mesh(built)
	_expect(stepped != null and (stepped.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array) == vertices, "%s: build_arrays + make_mesh differ from build" % gender)
	var worker_ok: bool = false
	var thread := Thread.new()
	thread.start(func() -> Dictionary: return HumanHair.build_arrays(data, params))
	var from_thread: Dictionary = thread.wait_to_finish()
	var from_worker: ArrayMesh = HumanHair.make_mesh(from_thread)
	worker_ok = from_worker != null and (from_worker.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array) == vertices
	_expect(worker_ok, "%s: build_arrays on a worker thread gave other hair" % gender)
	# the same seed gives the same hair; a longer length hangs lower
	var again: ArrayMesh = HumanHair.build(body, params)
	_expect((again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array) == vertices, "%s: not deterministic" % gender)
	var long_params: Dictionary = params.duplicate()
	long_params["length"] = 0.3
	var long_hair: ArrayMesh = HumanHair.build(body, long_params)
	var long_low: float = INF
	for v: Vector3 in (long_hair.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		long_low = minf(long_low, v.y)
	_expect(long_low < low - 0.05, "%s: length 0.3 only reaches %.2f lower than 0.12" % [gender, low - long_low])
	# curly hair keeps each ribbon's side from point to point (a coil used to flip it: crossed quads, flipped normals), and carries the rest place in UV2
	var curly_params: Dictionary = params.duplicate()
	curly_params.merge({"curl": 0.9, "volume": 1.3}, true)
	var curly_arrays: Array = HumanHair.build(body, curly_params).surface_get_arrays(0)
	var curly_normals: PackedVector3Array = curly_arrays[Mesh.ARRAY_NORMAL]
	var curly_uvs: PackedVector2Array = curly_arrays[Mesh.ARRAY_TEX_UV]
	var curly_colors: PackedColorArray = curly_arrays[Mesh.ARRAY_COLOR]
	var flips: int = 0
	var pairs: int = 0
	for i: int in range(0, curly_normals.size() - 2):
		if curly_colors[i].b > 0.5 or curly_colors[i + 2].b > 0.5 or curly_uvs[i + 2].y <= curly_uvs[i].y or (i % 2) != (i + 2) % 2:
			continue
		pairs += 1
		if curly_normals[i].dot(curly_normals[i + 2]) < -0.3:
			flips += 1
	_expect(pairs > 1000 and float(flips) / maxf(pairs, 1) < 0.01, "%s: %d of %d consecutive ribbon points of curly hair face opposite ways" % [gender, flips, pairs])
	_expect((curly_arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() == curly_normals.size(), "%s: the hair has no rest-place UV2" % gender)
	# consecutive seeds do not share a shifted stream: the locks of seed 1 and seed 2 start at other places
	var seed_one: Dictionary = params.duplicate()
	seed_one["seed"] = 1
	var seed_two: Dictionary = params.duplicate()
	seed_two["seed"] = 2
	var first_a: PackedVector3Array = HumanHair.build(body, seed_one).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var first_b: PackedVector3Array = HumanHair.build(body, seed_two).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var same_places: int = 0
	var shared: Dictionary = {}
	for v: Vector3 in first_a:
		shared[v.snapped(Vector3.ONE * 0.0005)] = true
	for v: Vector3 in first_b:
		if shared.has(v.snapped(Vector3.ONE * 0.0005)):
			same_places += 1
	_expect(same_places < first_b.size() / 10, "%s: seeds 1 and 2 share %d of %d vertices" % [gender, same_places, first_b.size()])
	# side_trim 1 leaves the sides bald without writing locks of no length (no zero normals)
	var bald_params: Dictionary = params.duplicate()
	bald_params["side_trim"] = 1.0
	var bald_normals: PackedVector3Array = HumanHair.build(body, bald_params).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var zero_normals: int = 0
	for n: Vector3 in bald_normals:
		if n.length() < 0.5:
			zero_normals += 1
	_expect(zero_normals == 0, "%s: %d zero normals with side_trim 1" % [gender, zero_normals])
	# a bald head can have a beard (length 0: no head hair and no scalp cap, the beard is still made)
	var bald_beard: Dictionary = params.duplicate()
	bald_beard.merge({"length": 0.0, "beard": 1.0, "beard_length": 0.03}, true)
	var bald_hair: ArrayMesh = HumanHair.build(body, bald_beard)
	_expect(bald_hair != null and bald_hair.get_surface_count() == 1, "%s: a bald head with a beard made no mesh" % gender)
	if bald_hair != null and bald_hair.get_surface_count() == 1:
		var bald_arrays: Array = bald_hair.surface_get_arrays(0)
		_expect((bald_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 1000, "%s: a bald head's beard has only %d vertices" % [gender, (bald_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()])
	var no_hair: Dictionary = params.duplicate()
	no_hair.merge({"length": 0.0, "beard": 0.0}, true)
	_expect(HumanHair.build(body, no_hair) == null or HumanHair.build(body, no_hair).get_surface_count() == 0, "%s: a bald head without a beard made a mesh" % gender)
	# a long curly ribbon hair keeps to the 16 points per guide the simulation holds (it asked for 18 and froze in its rest pose)
	var curly_long: Dictionary = params.duplicate()
	curly_long.merge({"length": 0.2, "curl": 0.9, "strands": 0}, true)
	var curly_hair: ArrayMesh = HumanHair.build(body, curly_long)
	_expect(curly_hair != null and curly_hair.has_meta(&"hair_guide_steps"), "%s: the curly hair has no hair_guide_steps meta" % gender)
	if curly_hair != null and curly_hair.has_meta(&"hair_guide_steps"):
		_expect(int(curly_hair.get_meta(&"hair_guide_steps")) <= 16, "%s: %d points per guide, the simulation holds 16" % [gender, int(curly_hair.get_meta(&"hair_guide_steps"))])
	# the vertex budget: an extreme request is built again with fewer hairs instead of coming out bald (the simulation draws 65,535 groups of 64 vertices)
	var huge: Dictionary = params.duplicate()
	huge.merge({"locks": 9000, "strands": 0, "beard": 1.0, "beard_length": 0.1, "curl": 0.5, "length": 0.3}, true)
	var huge_hair: ArrayMesh = HumanHair.build(body, huge)
	var huge_count: int = 0
	if huge_hair != null:
		for si: int in huge_hair.get_surface_count():
			huge_count = maxi(huge_count, huge_hair.surface_get_array_len(si))
	_expect(huge_count > 0 and huge_count <= 4194240, "%s: an extreme request made a surface of %d vertices (limit 4194240 a surface)" % [gender, huge_count])
	# waves: the hair is drawn with more points than its guide (a curve through the guide's points), a big mesh is cut into surfaces under the limit, and every
	# drawn point still names a point of its guide (CUSTOM0.y from 0 to steps - 1, fractional between two)
	var wavy: Dictionary = params.duplicate()
	wavy.merge({"length": 0.3, "wave": 0.8, "strands": 40}, true)
	var wavy_hair: ArrayMesh = HumanHair.build(body, wavy)
	_expect(wavy_hair != null and int(wavy_hair.get_meta(&"hair_render_steps", 0)) > int(wavy_hair.get_meta(&"hair_guide_steps", 0)), "%s: wavy hair is not drawn with more points than its guide" % gender)
	if wavy_hair != null:
		var wavy_steps: int = int(wavy_hair.get_meta(&"hair_guide_steps", 0))
		var fractional: int = 0
		var outside: int = 0
		var wavy_total: int = 0
		for si: int in wavy_hair.get_surface_count():
			_expect(wavy_hair.surface_get_array_len(si) <= 4194240, "%s: a wavy surface has %d vertices (limit 4194240)" % [gender, wavy_hair.surface_get_array_len(si)])
			wavy_total += wavy_hair.surface_get_array_len(si)
			var custom: PackedFloat32Array = wavy_hair.surface_get_arrays(si)[Mesh.ARRAY_CUSTOM0]
			for i: int in range(1, custom.size(), 4):
				if custom[i] < -0.001 or custom[i] > float(wavy_steps - 1) + 0.001:
					outside += 1
				elif absf(custom[i] - roundf(custom[i])) > 0.01:
					fractional += 1
		_expect(outside == 0 and fractional > 0, "%s: wavy hair: %d points outside the guide, %d between guide points" % [gender, outside, fractional])
		print("HUMAN_HAIR_CHECK %s wavy: %d surfaces, %d vertices, %d points a hair (guide %d)" % [gender, wavy_hair.get_surface_count(), wavy_total, int(wavy_hair.get_meta(&"hair_render_steps", 0)), wavy_steps])
	# how long the hair takes (the docs said "a few ms": measured here; the body is already read, so this is the growing alone)
	var timings: String = ""
	for style: Array in [["default", {}], ["buzz", {"length": 0.025, "locks": 2600}], ["curly", {"curl": 0.9, "volume": 1.3}], ["long", {"length": 0.3}]]:
		var timed: Dictionary = params.duplicate()
		timed.merge(style[1], true)
		var start: int = Time.get_ticks_usec()
		var timed_built: Dictionary = HumanHair.build_arrays(data, timed)
		var grow_ms: float = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		HumanHair.make_mesh(timed_built)
		timings += " %s %.0f+%.0f ms" % [style[0], grow_ms, (Time.get_ticks_usec() - start) / 1000.0]
		_expect(grow_ms < 1500.0, "%s: %s hair took %.0f ms to grow" % [gender, style[0], grow_ms])
	print("%s build times (grow + make mesh):%s" % [gender, timings])
	for amount: float in [0.0, 0.85]:
		var beard_params: Dictionary = params.duplicate()
		beard_params.merge({"beard": amount, "beard_length": 0.02}, true)
		if OS.get_environment("HAIR_TIMES") != "":
			beard_params["cover_debug"] = 1.0   # (HAIR_TIMES=1: the builder prints its own laps)
		var beard_start: int = Time.get_ticks_usec()
		var beard_built: Dictionary = HumanHair.build_arrays(data, beard_params)
		var beard_grow: float = (Time.get_ticks_usec() - beard_start) / 1000.0
		beard_start = Time.get_ticks_usec()
		HumanHair.make_mesh(beard_built)
		print("%s beard %.2f: grow %.0f ms + mesh %.0f ms" % [gender, amount, beard_grow, (Time.get_ticks_usec() - beard_start) / 1000.0])
	print("%s: %d vertices, hair y %.3f .. %.3f (crown %.3f), long hair down to %.3f" % [gender, vertices.size(), low, high, top_y, long_low])
	_check_zones(gender, body, params)
	root.free()


# The body's blend shapes the hair keeps: height_, weight_ and muscle_ (the face and age keys are baked into the body the hair is built on).
func _hair_shape_names(body: ArrayMesh) -> Array[StringName]:
	var names: Array[StringName] = []
	for i: int in body.get_blend_shape_count():
		var shape_name: String = String(body.get_blend_shape_name(i))
		if shape_name.begins_with("height_") or shape_name.begins_with("weight_") or shape_name.begins_with("muscle_"):
			names.append(StringName(shape_name))
	return names


func _find_mesh(node: Node) -> ArrayMesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		return (node as MeshInstance3D).mesh as ArrayMesh
	for child: Node in node.get_children():
		var found: ArrayMesh = _find_mesh(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	print("HUMAN_HAIR_CHECK failed: ", message)


# Hair zones (front, top, crown, left_side, right_side, back, nape = 0..6): the builder sorts every guide's root into a zone; the character faces +Z, so its left is +X.
const ZONE_FRONT: int = 0
const ZONE_TOP: int = 1
const ZONE_CROWN: int = 2
const ZONE_LEFT: int = 3
const ZONE_RIGHT: int = 4
const ZONE_BACK: int = 5
const ZONE_NAPE: int = 6


# The roots of a hair mesh's guides, by zone: {zone: [root, ...]}.
func _roots_by_zone(hair: ArrayMesh) -> Dictionary:
	var by_zone: Dictionary = {}
	if hair == null:
		return by_zone
	var guides: PackedVector3Array = hair.get_meta(&"hair_guides", PackedVector3Array())
	var steps: int = int(hair.get_meta(&"hair_guide_steps", 0))
	var zones: PackedByteArray = hair.get_meta(&"hair_guide_zones", PackedByteArray())
	for g: int in zones.size():
		if not by_zone.has(zones[g]):
			by_zone[zones[g]] = []
		(by_zone[zones[g]] as Array).append(guides[g * steps])
	return by_zone


func _mean_root(roots: Array) -> Vector3:
	var sum := Vector3.ZERO
	for r: Vector3 in roots:
		sum += r
	return sum / maxf(1.0, float(roots.size()))


func _check_zones(gender: String, body: ArrayMesh, params: Dictionary) -> void:
	var zoned: Dictionary = params.duplicate()
	zoned.merge({"length": 0.15, "strands": 8}, true)
	var hair: ArrayMesh = HumanHair.build(body, zoned)
	# (f) a near-bald head with one long zone still grows that zone (the bald test must look at the zones' lengths too)
	var near_bald: Dictionary = params.duplicate()
	near_bald.merge({"length": 0.003, "strands": 8, "zones": {"top": {&"length": 0.2}}}, true)
	var top_only: ArrayMesh = HumanHair.build(body, near_bald)
	_expect(top_only != null and int(top_only.get_meta(&"hair_guide_count", 0)) > 50, "%s: zones: a 3 mm head with a 20 cm top grew %d guides" % [gender, int(top_only.get_meta(&"hair_guide_count", 0)) if top_only != null else -1])
	var zones: PackedByteArray = hair.get_meta(&"hair_guide_zones", PackedByteArray()) if hair != null else PackedByteArray()
	_expect(hair != null and zones.size() == int(hair.get_meta(&"hair_guide_count", -1)), "%s: zones: %d guide zones for %d guides" % [gender, zones.size(), int(hair.get_meta(&"hair_guide_count", -1)) if hair != null else -1])
	var by_zone: Dictionary = _roots_by_zone(hair)
	for z: int in 7:
		_expect((by_zone.get(z, []) as Array).size() >= 20, "%s: zones: zone %d has %d guides (want 20+)" % [gender, z, (by_zone.get(z, []) as Array).size()])
	for r: Vector3 in by_zone.get(ZONE_LEFT, []):
		if r.x <= 0.02:
			_fail("%s: zones: a left_side root at x %.3f" % [gender, r.x])
			break
	for r: Vector3 in by_zone.get(ZONE_RIGHT, []):
		if r.x >= -0.02:
			_fail("%s: zones: a right_side root at x %.3f" % [gender, r.x])
			break
	var front: Vector3 = _mean_root(by_zone.get(ZONE_FRONT, []))
	var top: Vector3 = _mean_root(by_zone.get(ZONE_TOP, []))
	var back: Vector3 = _mean_root(by_zone.get(ZONE_BACK, []))
	var nape: Vector3 = _mean_root(by_zone.get(ZONE_NAPE, []))
	_expect(front.z > top.z and top.z > back.z, "%s: zones: mean z front %.3f, top %.3f, back %.3f (want front > top > back)" % [gender, front.z, top.z, back.z])
	_expect(nape.y < back.y, "%s: zones: mean y nape %.3f, back %.3f (want nape lower)" % [gender, nape.y, back.y])
	# --- per-zone settings
	# (a) no zones is the same build as an empty zone list
	var plain: ArrayMesh = HumanHair.build(body, zoned)
	var empty_zones: Dictionary = zoned.duplicate()
	empty_zones["zones"] = {}
	_expect(_vertices(plain) == _vertices(HumanHair.build(body, empty_zones)), "%s: zones: an empty zone list changed the build" % gender)
	# (e) unknown zone names and keys are ignored
	var unknown: Dictionary = zoned.duplicate()
	unknown["zones"] = {"nowhere": {"curl": 1.0}, "top": {"bogus": 3.0}}
	_expect(_vertices(plain) == _vertices(HumanHair.build(body, unknown)), "%s: zones: unknown zone names or keys changed the build" % gender)
	# (b) amount 0 on the left side: no hair grows there, the right side keeps its hair, the scalp layer fades out over the left side
	var bare_left: Dictionary = zoned.duplicate()
	bare_left["zones"] = {"left_side": {"amount": 0.0}}
	var bare_hair: ArrayMesh = HumanHair.build(body, bare_left)
	var bare_by_zone: Dictionary = _roots_by_zone(bare_hair)
	# (only the soft border, ~1.5 cm wide, keeps a little hair: the guides rooted on the left side drop by 90% or more)
	var left_before: int = (by_zone.get(ZONE_LEFT, []) as Array).size()
	var left_after: int = (bare_by_zone.get(ZONE_LEFT, []) as Array).size()
	_expect(left_after <= int(0.10 * left_before), "%s: zones: amount 0 on the left side kept %d of its %d guides (want 10%% at most: the soft border)" % [gender, left_after, left_before])
	var right_before: int = (by_zone.get(ZONE_RIGHT, []) as Array).size()
	var right_after: int = (bare_by_zone.get(ZONE_RIGHT, []) as Array).size()
	_expect(right_after >= int(0.8 * right_before), "%s: zones: the right side went from %d to %d guides when only the left was bare" % [gender, right_before, right_after])
	var cap_alpha: float = 0.0
	var cap_count: int = 0
	if bare_hair != null:
		var arrays: Array = bare_hair.surface_get_arrays(0)
		var cap_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cap_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var cap_custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		for i: int in cap_vertices.size():
			if cap_colors[i].b > 0.9 and int(round(cap_custom[i * 4 + 2])) == ZONE_LEFT + 1 and cap_vertices[i].x > 0.06:
				cap_alpha += cap_colors[i].a
				cap_count += 1
	_expect(cap_count > 0 and cap_alpha / maxf(1.0, float(cap_count)) < 0.1, "%s: zones: the scalp layer over a bare left side has alpha %.2f over %d vertices (want < 0.1)" % [gender, cap_alpha / maxf(1.0, float(cap_count)), cap_count])
	# the skin's dark scalp (hair_scalp_weight, the hair colour under the hair) goes with the hair: over the left side zone it drops by 60% or more
	var body_vertices: PackedVector3Array = body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var plain_weight: PackedFloat32Array = plain.get_meta(&"hair_scalp_weight", PackedFloat32Array())
	var bare_weight: PackedFloat32Array = bare_hair.get_meta(&"hair_scalp_weight", PackedFloat32Array()) if bare_hair != null else PackedFloat32Array()
	var body_zones: PackedByteArray = plain.get_meta(&"hair_body_zones", PackedByteArray())
	var side_plain: float = 0.0
	var side_bare: float = 0.0
	for i: int in mini(body_vertices.size(), mini(plain_weight.size(), bare_weight.size())):
		if i < body_zones.size() and body_zones[i] == ZONE_LEFT and plain_weight[i] > 0.5:
			side_plain += plain_weight[i]
			side_bare += bare_weight[i]
	_expect(side_plain > 0.0 and side_bare <= 0.4 * side_plain, "%s: zones: the dark scalp on a bare left side is %.0f%% of normal (want 40%% at most)" % [gender, 100.0 * side_bare / maxf(side_plain, 0.001)])
	# (c) a long top over short hair
	var long_top: Dictionary = zoned.duplicate()
	long_top.merge({"length": 0.06, "zones": {"top": {"length": 0.2}}}, true)
	var top_hair: ArrayMesh = HumanHair.build(body, long_top)
	var top_len: float = _mean_guide_length(top_hair, ZONE_TOP)
	var back_len: float = _mean_guide_length(top_hair, ZONE_BACK)
	_expect(top_len > 2.0 * back_len, "%s: zones: a long top is %.3f m against the back's %.3f m (want 2x)" % [gender, top_len, back_len])
	# (d) a wave in one zone draws the hair with more points than its guide
	var wavy_back: Dictionary = zoned.duplicate()
	wavy_back.merge({"length": 0.25, "zones": {"back": {"wave": 0.8}}}, true)
	var wavy_hair: ArrayMesh = HumanHair.build(body, wavy_back)
	_expect(wavy_hair != null and int(wavy_hair.get_meta(&"hair_render_steps", 0)) > int(wavy_hair.get_meta(&"hair_guide_steps", 0)), "%s: zones: a wave in one zone is not drawn with extra points" % gender)


# Every surface's vertices, in order (the hair is split into several surfaces under the per-surface vertex limit).
func _vertices(hair: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	if hair == null:
		return out
	for surface: int in hair.get_surface_count():
		out.append_array(hair.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return out


# The mean length of the guides rooted in one zone (along their points).
func _mean_guide_length(hair: ArrayMesh, zone: int) -> float:
	if hair == null:
		return 0.0
	var guides: PackedVector3Array = hair.get_meta(&"hair_guides", PackedVector3Array())
	var steps: int = int(hair.get_meta(&"hair_guide_steps", 0))
	var zones: PackedByteArray = hair.get_meta(&"hair_guide_zones", PackedByteArray())
	var total: float = 0.0
	var count: int = 0
	for g: int in zones.size():
		if zones[g] != zone:
			continue
		for k: int in range(1, steps):
			total += guides[g * steps + k].distance_to(guides[g * steps + k - 1])
		count += 1
	return total / maxf(1.0, float(count))
