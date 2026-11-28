class_name ClothSetup
extends RefCounted
## The GPU cloth solver set up from a garment's recipe (docs/superpowers/specs/2026-11-26-garment-recipes-design.md), the same in both labs:
## the material's stiffness, the collision from what the garment covers, every garment a peer of every other. The rules are the ones the
## villager shirt and trousers were tuned with (task 103), written for any garment.

const GARMENTS_DIR := "res://assets/models/humans/garments/"
const OUTFITS_DIR := "res://assets/models/humans/outfits/"


static func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ClothSetup: cannot read " + path)
		return null
	return JSON.parse_string(text)


static func materials() -> Dictionary:
	return _read_json(GARMENTS_DIR + "materials.json")


static func load_recipe(garment_name: String) -> Dictionary:
	var recipe: Variant = _read_json(GARMENTS_DIR + garment_name + ".json")
	return recipe if recipe is Dictionary else {}


## An outfit: {"name", "garments": [recipe dictionaries, inside out], "colours": {garment: {gender: [r, g, b]}}}.
static func load_outfit(outfit_name: String) -> Dictionary:
	var data: Variant = _read_json(OUTFITS_DIR + outfit_name + ".json")
	if not data is Dictionary:
		return {}
	var garments: Array = []
	var order := 0
	for garment_name: String in data.get("garments", []):
		var recipe := load_recipe(garment_name)
		recipe["_order"] = order
		order += 1
		garments.append(recipe)
	garments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["layer"]) < int(b["layer"]) or (int(a["layer"]) == int(b["layer"]) and int(a["_order"]) < int(b["_order"])))
	return {"name": data.get("name", outfit_name), "garments": garments, "colours": data.get("colours", {})}


## Whether a garment is simulated as cloth (its material: shoes and armour plates follow the skeleton instead).
static func is_simulated(garment: Dictionary) -> bool:
	return bool(materials().get(String(garment.get("material", "linen")), {}).get("simulated", true))


## The shader a garment draws with (its material's "shader", else the woven clothes).
static func shader_path(garment: Dictionary) -> String:
	return String(materials().get(String(garment.get("material", "linen")), {}).get("shader", "res://shaders/human_clothes.gdshader"))


## How far in a garment is drawn where a higher layer covers it (the layers are built 12 mm apart: in a quick turn the shirt still came
## through the mail and the jerkin at a few points; drawn 1 cm in it cannot show). Covers nothing at the higher garment's edges (its hem mask).
const COVERED_INSET := 0.01
const COVERED_REACH := 0.05
const COVERED_TEX_WIDTH := 1024


## For every garment under a higher layer: which of its vertices that layer covers (1 under the middle of it, down to 0 toward its edges,
## 0 where nothing covers it), as a texture by vertex index, and the inset, onto its material (`covered_tex`, `covered_inset`). Footwear
## neither covers nor is covered. meshes[i] and materials[i] belong to garments[i] (rest shape, all in the same space).
static func apply_covered(garments: Array, meshes: Array, materials: Array) -> void:
	for i in garments.size():
		var material := materials[i] as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter(&"covered_inset", 0.0)
		if _is_footwear(garments[i]):
			continue
		var layer := int(garments[i].get("layer", 1))
		var grid: Dictionary = {}   # cell -> [position, weight, ...] of the higher layers' vertices
		for k in garments.size():
			if int(garments[k].get("layer", 1)) <= layer or _is_footwear(garments[k]):
				continue
			var arrays: Array = (meshes[k] as MeshInstance3D).mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			for v in points.size():
				var weight := 1.0 - (colours[v].g if v < colours.size() else 0.0)   # (G: 1 at the edge)
				var cell := Vector3i((points[v] / COVERED_REACH).floor())
				if not grid.has(cell):
					grid[cell] = []
				(grid[cell] as Array).append_array([points[v], weight])
		if grid.is_empty():
			continue
		var own: PackedVector3Array = (meshes[i] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var rows := int(ceil(float(own.size()) / COVERED_TEX_WIDTH))
		var bytes := PackedByteArray()
		bytes.resize(COVERED_TEX_WIDTH * maxi(rows, 1))
		var covered := 0
		var found := 0
		for v in own.size():
			var p: Vector3 = own[v]
			var base := Vector3i((p / COVERED_REACH).floor())
			var best := COVERED_REACH * COVERED_REACH * 1.01
			var weight := 0.0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var bucket: Array = grid.get(base + Vector3i(dx, dy, dz), [])
						for b in range(0, bucket.size(), 2):
							var d: float = p.distance_squared_to(bucket[b])
							if d < COVERED_REACH * COVERED_REACH:
								best = minf(best, d)
								weight = maxf(weight, bucket[b + 1] * clampf(2.0 - 2.0 * sqrt(d) / COVERED_REACH, 0.0, 1.0))   # (the most covered point in reach, full to half the reach: the nearest was often the higher
								# garment's rolled lip, turned in toward this one, and at its edge)
			bytes[v] = int(clampf(weight, 0.0, 1.0) * 255.0)
			found += int(best < COVERED_REACH * COVERED_REACH)
			covered += int(weight > 0.5)
		var image := Image.create_from_data(COVERED_TEX_WIDTH, maxi(rows, 1), false, Image.FORMAT_R8, bytes)
		material.set_shader_parameter(&"covered_tex", ImageTexture.create_from_image(image))
		material.set_shader_parameter(&"covered_tex_width", COVERED_TEX_WIDTH)
		material.set_shader_parameter(&"covered_inset", COVERED_INSET)
		print("CLOTH_COVERED %s: %d of %d vertices under a higher layer (%d near one)" % [garments[i]["name"], covered, own.size(), found])


## Debug (the body lab's bump heatmap): each vertex's signed distance (m) along its normal from a heavily smoothed copy of the mesh (Taubin
## smoothing: no shrinking, so only local bumps and dents remain), as a float texture by vertex index (`bump_debug_tex`). The glTF's vertices
## split at UV seams are welded for the smoothing by position.
const BUMP_THIN_PIECE := 0.02   # the bump heatmap leaves out a separate piece thinner than this in some direction (a sole slab, a lace)


static func bump_texture(mesh: Mesh, passes: int = 60) -> ImageTexture:
	var arrays: Array = mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var weld: Dictionary = {}
	var welded := PackedInt32Array()
	welded.resize(points.size())
	var spots := PackedVector3Array()
	var spot_normals := PackedVector3Array()
	for v in points.size():
		var key := Vector3i((points[v] * 100000.0).round())
		if not weld.has(key):
			weld[key] = spots.size()
			spots.append(points[v])
			spot_normals.append(Vector3.ZERO)
		welded[v] = weld[key]
		if v < normals.size():
			spot_normals[welded[v]] += normals[v]
	var near: Array = []
	near.resize(spots.size())
	for i in spots.size():
		near[i] = {}
	for t in range(0, indices.size(), 3):
		var corners := [welded[indices[t]], welded[indices[t + 1]], welded[indices[t + 2]]]
		for a in corners:
			for b in corners:
				if a != b:
					near[a][b] = true
	var ring: Array = []
	for i in spots.size():
		ring.append(PackedInt32Array((near[i] as Dictionary).keys()))
	var smooth := spots.duplicate()
	for step in passes:
		var weight := 0.5 if step % 2 == 0 else -0.53
		var next := smooth.duplicate()
		for i in smooth.size():
			var r: PackedInt32Array = ring[i]
			if r.is_empty():
				continue
			var sum := Vector3.ZERO
			for o in r:
				sum += smooth[o]
			next[i] = smooth[i].lerp(sum / r.size(), weight)
		smooth = next
	# a piece thin in some direction (a shoe's sole slab, a lace) is not judged: the smoothing collapses a thin, sharp-edged piece and the whole
	# of it read as one big bump
	var piece := PackedInt32Array()
	piece.resize(spots.size())
	piece.fill(-1)
	var thin: Dictionary = {}
	var pieces := 0
	for start in spots.size():
		if piece[start] >= 0:
			continue
		var stack := [start]
		piece[start] = pieces
		var box := AABB(spots[start], Vector3.ZERO)
		while not stack.is_empty():
			var at: int = stack.pop_back()
			box = box.expand(spots[at])
			for o in ring[at]:
				if piece[o] < 0:
					piece[o] = pieces
					stack.append(o)
		thin[pieces] = minf(box.size.x, minf(box.size.y, box.size.z)) < BUMP_THIN_PIECE
		pieces += 1
	var rows := int(ceil(float(points.size()) / COVERED_TEX_WIDTH))
	var image := Image.create_empty(COVERED_TEX_WIDTH, maxi(rows, 1), false, Image.FORMAT_RF)
	for v in points.size():
		var i: int = welded[v]
		var off := 0.0 if thin[piece[i]] else (spots[i] - smooth[i]).dot(spot_normals[i].normalized())
		image.set_pixel(v % COVERED_TEX_WIDTH, v / COVERED_TEX_WIDTH, Color(off, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


## How far a character wearing these garments stands above the ground: a shoe's floor and sole are under the foot (garments/footwear.py: the
## upper's sole SOLE_DROP under the foot, the outsole under that), and the wearer stands on the outsole. Below the ground, the grass was drawn
## inside the shoe over its floor.
const FOOTWEAR_SOLE_DROP := 0.004   # (garments/footwear.py SOLE_DROP)


static func footwear_lift(garments: Array) -> float:
	var lift := 0.0
	for garment: Dictionary in garments:
		var shoe: Dictionary = garment.get("shoe", {})
		if not shoe.is_empty():
			lift = maxf(lift, FOOTWEAR_SOLE_DROP + float(shoe.get("outsole", 0.005)) + float(shoe.get("heel", 0.0)))
	return lift


static func _is_footwear(garment: Dictionary) -> bool:
	return String((garment.get("top", {}) as Dictionary).get("at", "")) == "ankle"


## The outfits there are (file names without .json).
static func outfit_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file: String in DirAccess.get_files_at(OUTFITS_DIR):
		if file.ends_with(".json"):
			names.append(file.get_basename())
	names.sort()
	return names


## The solver's settings for `garment` (a recipe dictionary). The paths (target, skeleton, body) and the peers are set by the caller.
static func configure(solver: GPUClothSolver, garment: Dictionary) -> void:
	var material: Dictionary = materials().get(String(garment.get("material", "linen")), {})
	var covers: Array = garment.get("covers", [])
	solver.set_meta(&"garment", garment)
	solver.cloth_weight_channel = 2   # (the builder's vertex colour blue: 0 held, 1 free)
	solver.flip_normals = true   # (without it the solver's normals for our garments point into the body: a dark garment with bright specks)
	solver.solver_iterations = 4   # (8 x 4 looked the same and cost 4.5 ms a frame instead of 1.7)
	solver.substeps = 2
	solver.stiffness = float(material.get("stiffness", 0.9))
	solver.bend_stiffness = float(material.get("bend_stiffness", 0.6))
	solver.damping = 0.985
	solver.max_travel_distance = 0.04
	solver.cloth_skin_offset = 0.0
	solver.collider_friction = 0.5
	solver.peer_collider_voxel_resolution = 8
	# layered contact with the other garments: kept outside the lower layers and inside the higher ones (a quick turn carried the shirt through
	# the mail, and the unsigned push held it outside)
	solver.peer_layer = int(garment.get("layer", 1))
	# capsules: small on the torso (a capsule is round, a torso oval: full ones pushed the cloth out like a cape), the lopsided pelvis and
	# upper-spine capsules shrunk to nothing (pelvis to the RIGHT thigh pushed trousers out at one hip; spine to the LEFT collarbone lifted the
	# neck band), full ones on the shins (the shins poked through small ones)
	solver.body_collider_voxel_resolution = 0
	solver.auto_collider_lod = 1
	solver.auto_collider_radius_percentile = 0.5
	solver.auto_collider_radius_scale = 0.8
	solver.auto_collider_bone_overrides = {"mixamorig_Hips": Vector2(0.0, 0.1), "mixamorig_Spine2": Vector2(0.0, 0.1)}
	if covers.has("shin"):
		solver.auto_collider_bone_overrides.merge({"mixamorig_LeftLeg": Vector2(0.85, 1.0), "mixamorig_RightLeg": Vector2(0.85, 1.0)})
	# drawn 4 mm out along the normal (hides the skin where free cloth sinks onto capsules inside the body)
	solver.cloth_render_offset = 0.004
	solver.body_collider_thickness = 0.006
	if covers.has("forearm"):
		# a sleeve hangs loose over the arm: the exact arm surface, weighted like the body, packed in native code (plan 3: near characters only)
		solver.body_collider_voxel_resolution = 1
		solver.body_collider_preparer = func(data: Dictionary) -> Dictionary:
			return HumanRig.prepare_cloth_arms(data)
		solver.body_collider_packer = func(data: Dictionary, poses: Array) -> PackedByteArray:
			return HumanRig.skin_cloth_arms(data, poses)
		solver.cloth_render_offset = 0.001
		solver.body_collider_thickness = 0.004


## A limb's direction through its middle joint and how bent it is (0 straight .. 1 at 135 degrees), from the three joints (the bend wrinkles).
static func limb_bend(root: Vector3, middle: Vector3, end: Vector3) -> Array:
	var upper := (middle - root).normalized()
	var lower := (end - middle).normalized()
	var axis := (upper + lower).normalized()
	return [axis, clampf(upper.angle_to(lower) / (PI * 0.75), 0.0, 1.0)]


## Every solver collides with every other (all garments of an outfit are each other's peers). The solvers must share a parent.
static func connect_peers(solvers: Array) -> void:
	# three layers (mail over a shirt over trousers): the middle one's proxy at 8 cells across sat up to ~7 mm inside it on the back's curve and
	# the shirt showed through the mail in a quick turn; at 16 it holds. Two layers keep 8 (cheaper, and what the waist checks were tuned on).
	var top_layer := 0
	for solver: GPUClothSolver in solvers:
		top_layer = maxi(top_layer, solver.peer_layer)
	for solver: GPUClothSolver in solvers:
		if top_layer >= 2 and OS.get_cmdline_user_args().has("--cloth-layered=off"):
			solver.peer_layer = -1   # (debug: the unsigned contact for every outfit)
		if top_layer >= 2:
			solver.peer_collider_voxel_resolution = maxi(solver.peer_collider_voxel_resolution, 16)
		else:
			solver.peer_layer = -1   # (two layers: the unsigned contact the waist checks were tuned on; one-sided, the shirt sank 13 mm into the
			# trousers at the hip on the most muscular body)
	for solver: GPUClothSolver in solvers:
		var peers: Array[NodePath] = []
		for other: GPUClothSolver in solvers:
			if other != solver:
				peers.append(NodePath("../" + String(other.name)))
		solver.peer_cloth_solvers = peers


## The solver of the garment covering the forearms (the sleeves), or null.
static func sleeve_solver(solvers: Array) -> GPUClothSolver:
	for solver: GPUClothSolver in solvers:
		if solver.has_meta(&"garment") and (solver.get_meta(&"garment") as Dictionary).get("covers", []).has("forearm"):
			return solver
	return null
