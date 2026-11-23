extends RefCounted
# Shows our head hair with the TressFX for Godot addon (AMD TressFX 4.1 port, MIT licence, res://addons/tressfx) for a side by side look.
# Our HumanHair guide strands (mesh metadata "hair_guides") are written as a .tfx file (16 points per strand, resampled by length), the head and shoulders
# of the body become the collider, and a TressFXHair node follows the body. Nothing here is used by the game: it is a comparison tool for the lab (--tressfx).

const VERTS_PER_STRAND := 16
static var root_density := 2.5   # 1 = evenly spaced points along a strand; higher = more points near the root (--tfx=root_density:2.5)
static var options := {}   # extra TressFXHair properties from the lab (--tfx=name:value,name:value)
const TFX_PATH := "user://lab_hair.tfx"
const SHADER_PATH := "res://addons/tressfx/shaders/tressfx_strand.gdshader"


static func available() -> bool:
	return ClassDB.class_exists(&"TressFXHair") and ClassDB.class_exists(&"TressFXCollisionMesh")


# Writes the guide strands of a HumanHair mesh as a TressFX 4 file. Returns the number of strands.
static func write_tfx(hair: ArrayMesh, path: String) -> int:
	var guides: PackedVector3Array = hair.get_meta(&"hair_guides", PackedVector3Array())
	var count: int = int(hair.get_meta(&"hair_guide_count", 0))
	var steps: int = int(hair.get_meta(&"hair_guide_steps", 0))
	if count <= 0 or steps < 2 or guides.size() != count * steps:
		return 0
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return 0
	file.store_float(4.0)       # version
	file.store_32(count)        # strands
	file.store_32(VERTS_PER_STRAND)
	file.store_32(160)          # offset of the vertices
	file.store_32(0)            # offset of the strand UVs (none)
	for i in 35:
		file.store_32(0)        # reserved, up to the 160-byte header
	for g in count:
		var base: int = g * steps
		var cumulative := PackedFloat32Array()
		cumulative.resize(steps)
		var total := 0.0
		for k in range(1, steps):
			total += guides[base + k].distance_to(guides[base + k - 1])
			cumulative[k] = total
		var segment := 1
		for v in VERTS_PER_STRAND:
			# denser near the root (power spacing): the first two points are pinned straight, so evenly spaced points would leave the first centimetres of a short hair unbent
			var target: float = total * pow(float(v) / float(VERTS_PER_STRAND - 1), root_density)
			while segment < steps - 1 and cumulative[segment] < target:
				segment += 1
			var span: float = cumulative[segment] - cumulative[segment - 1]
			var t: float = (target - cumulative[segment - 1]) / span if span > 1e-9 else 0.0
			var p: Vector3 = guides[base + segment - 1].lerp(guides[base + segment], clampf(t, 0.0, 1.0))
			file.store_float(p.x)
			file.store_float(p.y)
			file.store_float(p.z)
			file.store_float(0.0 if v < 2 else 1.0)   # the first two points are pinned to the scalp
	file.close()
	return count


# The head and shoulders of the body as a collider mesh (the whole body would make the distance field too coarse).
static func head_mesh(body: ArrayMesh, below_top: float, shrink: float = 1.0, centre_z: float = 0.065) -> ArrayMesh:
	var arrays: Array = body.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var top := -INF
	for v in vertices:
		top = maxf(top, v.y)
	var remap := {}
	var out_vertices := PackedVector3Array()
	var out_indices := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var a: int = indices[t]
		var b: int = indices[t + 1]
		var c: int = indices[t + 2]
		if vertices[a].y < top - below_top or vertices[b].y < top - below_top or vertices[c].y < top - below_top:
			continue
		for index in [a, b, c]:
			if not remap.has(index):
				remap[index] = out_vertices.size()
				var v: Vector3 = vertices[index]
				out_vertices.append(Vector3(v.x * shrink, v.y, centre_z + (v.z - centre_z) * shrink))   # (shrunk about the head axis; 1 = as is)
			out_indices.append(remap[index])
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = out_vertices
	out_arrays[Mesh.ARRAY_INDEX] = out_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return mesh


# Adds the TressFX hair (and its collider) under `parent`, in the same space as the hair mesh (the body's). Returns the node holding them.
static func attach(parent: Node3D, hair: ArrayMesh, body: ArrayMesh, colour: Color) -> Node3D:
	if not available():
		push_warning("TressFX addon not loaded (res://addons/tressfx)")
		return null
	root_density = float(options.get("root_density", root_density))
	var strands := write_tfx(hair, TFX_PATH)
	if strands <= 0:
		return null
	var holder := Node3D.new()
	holder.name = "TressFXHolder"
	parent.add_child(holder)
	var collider = ClassDB.instantiate(&"TressFXCollisionMesh")
	collider.set(&"mesh", head_mesh(body, 0.36))
	collider.set(&"num_cells_x", 100)
	holder.add_child(collider)
	var node = ClassDB.instantiate(&"TressFXHair")
	node.set(&"tfx_path", ProjectSettings.globalize_path(TFX_PATH))
	node.set(&"num_follow_hairs", 15)
	node.set(&"follow_radius", 0.004)
	# our guides already carry the style (they drape from the root): hold the whole strand to it, so short hair bends at the root and lies on the head
	node.set(&"global_range", 1.0)
	node.set(&"global_stiffness", 0.9)
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter(&"base_color", colour.lightened(0.15))
	material.set_shader_parameter(&"fiber_radius", 0.0003)
	node.set(&"material", material)
	node.set(&"collision_meshes", [] if float(options.get("nocollider", 0.0)) > 0.5 else [collider])
	for key in options:
		if str(key) == "root_density" or str(key) == "nocollider" or str(key) == "showours" or str(key) == "shrink" or str(key) == "fill" or str(key) == "fill_every" or str(key) == "fill_ymax" or str(key) == "tail_forward" or str(key) == "tail_up":
			continue
		if str(key).begins_with("mat_"):   # --tfx=mat_fiber_radius:0.0004 sets a strand material parameter
			material.set_shader_parameter(StringName(str(key).trim_prefix("mat_")), options[key])
		else:
			node.set(StringName(key), options[key])
	holder.add_child(node)
	return holder


# ---- the library's own hair (no code of ours in the hair): the addon's ponytail demo hair on our head --------------------------------------------
# A temporary setup: the demo files stay where they were cloned (LIB_DIR); the hair is only scaled and moved so its roots cover our head's roots.
const LIB_DIR := "E:/Temp/claude/bb8b0ebc32cdb738/82360aae-586d-447d-b130-891b49e0b503/scratchpad/tressfx/repo/addons/tressfx/demo/ponytail/"


# The first point of every strand of a .tfx file (file units).
static func tfx_roots(path: String, vertex_index: int = 0) -> PackedVector3Array:
	var roots := PackedVector3Array()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 160:
		return roots
	var strands: int = bytes.decode_u32(4)
	var verts: int = bytes.decode_u32(8)
	var offset: int = bytes.decode_u32(12)
	for i in strands:
		var at: int = offset + 16 * (i * verts + clampi(vertex_index, 0, verts - 1))
		roots.append(Vector3(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8)))
	return roots


# Extra strands for the back of the head: some of the library hair's own strands (rooted on the front and top), turned half a turn about the head's vertical
# axis, so the bangs become hair over the nape. Written as a second .tfx (file units; the axis is given in world metres and converted with the fit).
static func write_fill(head_path: String, out_path: String, scale_value: float, position_value: Vector3, axis_x: float, axis_z: float, every: int, y_max: float) -> int:
	var bytes := FileAccess.get_file_as_bytes(head_path)
	if bytes.size() < 160:
		return 0
	var strands: int = bytes.decode_u32(4)
	var verts: int = bytes.decode_u32(8)
	var offset: int = bytes.decode_u32(12)
	var ax: float = (axis_x - position_value.x) / scale_value
	var az: float = (axis_z - position_value.z) / scale_value
	var out := PackedByteArray()
	var picked := 0
	var body_bytes := PackedByteArray()
	for i in strands:
		var at: int = offset + 16 * i * verts
		var root_world := Vector3(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8)) * scale_value + position_value
		# front and top strands that start above the ears (the sides stay as they are)
		if root_world.z < axis_z + 0.02:
			continue
		if root_world.y < 1.60 or root_world.y > y_max:   # (the top strands, turned, would puff the back of the head up past the skull)
			continue
		picked += 1
		if picked % every != 0:
			continue
		var chunk := PackedByteArray()
		chunk.resize(16 * verts)
		for v in verts:
			var from: int = at + 16 * v
			chunk.encode_float(16 * v + 0, 2.0 * ax - bytes.decode_float(from))
			chunk.encode_float(16 * v + 4, bytes.decode_float(from + 4))
			chunk.encode_float(16 * v + 8, 2.0 * az - bytes.decode_float(from + 8))
			chunk.encode_float(16 * v + 12, bytes.decode_float(from + 12))
		body_bytes.append_array(chunk)
	var kept: int = body_bytes.size() / (16 * verts)
	if kept == 0:
		return 0
	out.resize(160)
	for i in 160:
		out[i] = bytes[i]
	out.encode_u32(4, kept)
	out.append_array(body_bytes)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		return 0
	file.store_buffer(out)
	file.close()
	return kept


static func bounds_of(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


static func library_material(base: Color, tip: Color, tip_percentage: float, radius: float, k_diffuse: float, k_spec1: float, spec_exp1: float, k_spec2: float, spec_exp2: float, root_shadow: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter(&"base_color", base)
	material.set_shader_parameter(&"tip_color", tip)
	material.set_shader_parameter(&"tip_percentage", tip_percentage)
	material.set_shader_parameter(&"fiber_radius", radius)
	material.set_shader_parameter(&"fiber_ratio", 0.3)
	material.set_shader_parameter(&"k_diffuse", k_diffuse)
	material.set_shader_parameter(&"k_spec1", k_spec1)
	material.set_shader_parameter(&"spec_exp1", spec_exp1)
	material.set_shader_parameter(&"k_spec2", k_spec2)
	material.set_shader_parameter(&"spec_exp2", spec_exp2)
	material.set_shader_parameter(&"root_shadow", root_shadow)
	material.set_shader_parameter(&"color_variation", 0.3)
	material.set_shader_parameter(&"tip_fade", 0.25)
	return material


static func attach_library(parent: Node3D, our_hair: ArrayMesh, body: ArrayMesh) -> Node3D:
	if not available():
		push_warning("TressFX addon not loaded (res://addons/tressfx)")
		return null
	var head_path := LIB_DIR + "ponytail_hair_head.tfx"
	var tail_path := LIB_DIR + "ponytail_hair_tail.tfx"
	var theirs := tfx_roots(head_path)
	var guides: PackedVector3Array = our_hair.get_meta(&"hair_guides", PackedVector3Array())
	var steps: int = int(our_hair.get_meta(&"hair_guide_steps", 0))
	if theirs.is_empty() or guides.is_empty() or steps < 2:
		return null
	# fit: the roots of their hair onto the roots of ours (same size and place)
	var ours := PackedVector3Array()
	for g in range(0, guides.size(), steps):
		ours.append(guides[g])
	var their_box := bounds_of(theirs)
	var our_box := bounds_of(ours)
	var scale_value: float = 0.5 * (our_box.size.x / maxf(their_box.size.x, 1e-6) + our_box.size.y / maxf(their_box.size.y, 1e-6))
	var position_value: Vector3 = our_box.get_center() - their_box.get_center() * scale_value
	var holder := Node3D.new()
	holder.name = "TressFXLibraryHolder"
	parent.add_child(holder)
	var collider = ClassDB.instantiate(&"TressFXCollisionMesh")
	# the demo head is rounder and bigger than ours: some of its roots start inside our head. A collider a little smaller than our head keeps them outside it.
	collider.set(&"mesh", head_mesh(body, 0.36, float(options.get("shrink", 0.86))))
	collider.set(&"num_cells_x", 100)
	holder.add_child(collider)
	# the demo's own settings (ponytail.tscn); the fibre radius follows the scale of the fit (the demo head is about 3x a real one)
	var head = ClassDB.instantiate(&"TressFXHair")
	head.set(&"tfx_path", head_path)
	head.set(&"import_scale", scale_value)
	head.set(&"position", position_value)
	head.set(&"num_follow_hairs", 12)
	head.set(&"follow_radius", 0.012 * scale_value / 0.01)   # (the demo head is 3x ours: the spread scales with the fit)
	head.set(&"tip_separation", 1.0)
	head.set(&"local_stiffness", 0.4)
	head.set(&"global_stiffness", 0.3)
	head.set(&"global_range", 0.4)
	head.set(&"length_iterations", 3)
	head.set(&"damping", 0.2)
	head.set(&"gravity", 1.0)
	head.set(&"material", library_material(Color(0.36, 0.11, 0.04), Color(0.62, 0.28, 0.1), 0.3, 0.0012 * scale_value / 0.01, 0.35, 0.06, 40.0, 0.25, 14.0, 0.3))
	head.set(&"collision_meshes", [] if float(options.get("nocollider", 0.0)) > 0.5 else [collider])
	holder.add_child(head)
	if float(options.get("fill", 0.0)) > 0.5:
		var fill_path := ProjectSettings.globalize_path("user://lab_hair_fill.tfx")
		var kept := write_fill(head_path, fill_path, scale_value, position_value, 0.0, 0.045, int(options.get("fill_every", 3.0)), float(options.get("fill_ymax", 1.68)))
		if kept > 0:
			var fill = ClassDB.instantiate(&"TressFXHair")
			fill.set(&"tfx_path", fill_path)
			fill.set(&"import_scale", scale_value)
			fill.set(&"position", position_value)
			fill.set(&"num_follow_hairs", 12)
			fill.set(&"follow_radius", 0.012 * scale_value / 0.01)
			fill.set(&"tip_separation", 1.0)
			fill.set(&"local_stiffness", 0.4)
			fill.set(&"global_stiffness", 0.3)
			fill.set(&"global_range", 0.4)
			fill.set(&"length_iterations", 3)
			fill.set(&"damping", 0.2)
			fill.set(&"gravity", 1.0)
			fill.set(&"material", library_material(Color(0.36, 0.11, 0.04), Color(0.62, 0.28, 0.1), 0.3, 0.0012 * scale_value / 0.01, 0.35, 0.06, 40.0, 0.25, 14.0, 0.3))
			fill.set(&"collision_meshes", [] if float(options.get("nocollider", 0.0)) > 0.5 else [collider])
			holder.add_child(fill)
			print("TRESSFX back fill strands: ", kept)
	var tail = ClassDB.instantiate(&"TressFXHair")
	tail.set(&"tfx_path", tail_path)
	tail.set(&"import_scale", scale_value)
	var tail_shift := Vector3(0.0, float(options.get("tail_up", 0.032)), float(options.get("tail_forward", 0.04)))
	tail.set(&"position", position_value + tail_shift)
	tail.set(&"num_follow_hairs", 12)
	tail.set(&"follow_radius", 0.012 * scale_value / 0.01)
	tail.set(&"tip_separation", 1.0)
	tail.set(&"vsp_coeff", 0.25)
	tail.set(&"local_stiffness", 0.35)
	tail.set(&"global_stiffness", 0.06)
	tail.set(&"global_range", 0.2)
	tail.set(&"length_iterations", 3)
	tail.set(&"damping", 0.1)
	tail.set(&"gravity", 1.5)
	tail.set(&"material", library_material(Color(0.36, 0.11, 0.04), Color(0.62, 0.28, 0.1), 0.3, 0.0012 * scale_value / 0.01, 0.35, 0.06, 40.0, 0.25, 14.0, 0.3))
	tail.set(&"collision_meshes", [] if float(options.get("nocollider", 0.0)) > 0.5 else [collider])
	holder.add_child(tail)
	# the demo's own character wears a white hair tie where the ponytail leaves the head: without it the tail starts as a bare flat end
	# the demo character wears a white hair tie where the ponytail leaves the head; the tail is a flat sheet of strands, so the tie is an oval ring a few points down it
	var tie_index := 4
	var tie_points := tfx_roots(tail_path, tie_index)
	var after_points := tfx_roots(tail_path, tie_index + 2)
	if not tie_points.is_empty() and not after_points.is_empty():
		var xs := PackedFloat32Array()
		var zs := PackedFloat32Array()
		for point in tie_points:
			xs.append(point.x)
			zs.append(point.z)
		xs.sort()
		zs.sort()
		var lo_i: int = int(tie_points.size() * 0.1)
		var hi_i: int = int(tie_points.size() * 0.9)
		var width: float = (xs[hi_i] - xs[lo_i]) * scale_value
		var depth: float = (zs[hi_i] - zs[lo_i]) * scale_value
		var centre_here := Vector3.ZERO
		for point in tie_points:
			centre_here += point
		centre_here /= tie_points.size()
		var centre_after := Vector3.ZERO
		for point in after_points:
			centre_after += point
		centre_after /= after_points.size()
		var tie := MeshInstance3D.new()
		var ring := TorusMesh.new()
		var tie_radius: float = maxf(width * 0.5 * 1.1, 0.01)
		ring.inner_radius = tie_radius
		ring.outer_radius = tie_radius + 0.004
		ring.rings = 24
		ring.ring_segments = 8
		tie.mesh = ring
		var tie_material := StandardMaterial3D.new()
		tie_material.albedo_color = Color(0.92, 0.92, 0.9)
		tie_material.roughness = 0.5
		tie.material_override = tie_material
		holder.add_child(tie)
		tie.position = centre_here * scale_value + position_value + tail_shift
		var axis_y: Vector3 = ((centre_after - centre_here) * scale_value).normalized()
		var axis_x: Vector3 = axis_y.cross(Vector3.FORWARD).normalized()
		var axis_z: Vector3 = axis_x.cross(axis_y).normalized()
		tie.basis = Basis(axis_x, axis_y, axis_z * clampf(depth / maxf(width, 1e-4), 1.0, 1.0))
		print("TRESSFX hair tie ", tie.position, " width ", width, " depth ", depth)
	print("TRESSFX library hair: scale ", scale_value, " position ", position_value, " their roots ", their_box, " ours ", our_box)
	return holder
