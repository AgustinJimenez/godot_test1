class_name MeshPenetrationGeometry
extends RefCounted

## Pure triangle/geometry math extracted from character_editor.gd purely to
## keep that file under a manageable size - every function here only reads
## its parameters, no editor/UI state, moved verbatim from
## _build_penetration_report's supporting functions (see that function, now
## in character_editor_mcp_handler.gd, for how these compose into the actual
## held-object penetration check).


static func triangles_aabb(triangles: Array) -> AABB:
	var result := AABB()
	var has_any := false
	for tri in triangles:
		for point in tri:
			if not has_any:
				result = AABB(point, Vector3.ZERO)
				has_any = true
			else:
				result = result.expand(point)
	return result


## Deduplicates by rounding to the nearest tenth of a millimeter - triangles
## sharing an edge/vertex would otherwise produce many redundant containment
## ray casts for the same physical point.
static func unique_triangle_vertices(triangles: Array) -> Array:
	var seen := {}
	var unique := []
	for tri in triangles:
		for point in tri:
			var key := Vector3i(round(point.x * 10000.0), round(point.y * 10000.0), round(point.z * 10000.0))
			if not seen.has(key):
				seen[key] = true
				unique.append(point)
	return unique


## Even-odd ray casting rule: a point is inside a closed mesh if a ray cast
## from it crosses the mesh's surface an odd number of times. The ray
## direction is an arbitrary non-axis-aligned vector, deliberately not
## X/Y/Z-aligned, to avoid coincidentally grazing triangle edges/vertices
## along a suspiciously "clean" axis.
static func point_inside_triangles(point: Vector3, triangles: Array, ray_length: float) -> bool:
	var ray_dir := Vector3(1.0, 0.31, 0.17).normalized()
	var ray_end := point + ray_dir * ray_length
	var crossing_count := 0
	for tri in triangles:
		if Geometry3D.segment_intersects_triangle(point, ray_end, tri[0], tri[1], tri[2]) != null:
			crossing_count += 1
	return crossing_count % 2 == 1


## Returns the intersection point if the two triangles cross, else null -
## tests every edge of each triangle against the other triangle's face,
## since Godot has no direct triangle-triangle intersection method.
static func triangle_intersection_point(tri_a: Array, tri_b: Array):
	for i in 3:
		var hit = Geometry3D.segment_intersects_triangle(
				tri_a[i], tri_a[(i + 1) % 3], tri_b[0], tri_b[1], tri_b[2])
		if hit != null:
			return hit
	for i in 3:
		var hit = Geometry3D.segment_intersects_triangle(
				tri_b[i], tri_b[(i + 1) % 3], tri_a[0], tri_a[1], tri_a[2])
		if hit != null:
			return hit
	return null


static func collect_mesh_triangles(
		node: Node, out: Array, filter_aabb: AABB, use_filter: bool) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		append_mesh_triangles(
				(node as MeshInstance3D).mesh, (node as MeshInstance3D).global_transform,
				out, filter_aabb, use_filter)
	for child in node.get_children():
		collect_mesh_triangles(child, out, filter_aabb, use_filter)


static func append_mesh_triangles(
		mesh: Mesh, xform: Transform3D, out: Array, filter_aabb: AABB, use_filter: bool) -> void:
	for surface_idx in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var triangle_count: int = (indices.size() / 3) if indices != null else (verts.size() / 3)
		for t in triangle_count:
			var i0: int
			var i1: int
			var i2: int
			if indices != null:
				i0 = indices[t * 3]
				i1 = indices[t * 3 + 1]
				i2 = indices[t * 3 + 2]
			else:
				i0 = t * 3
				i1 = t * 3 + 1
				i2 = t * 3 + 2
			var a: Vector3 = xform * verts[i0]
			var b: Vector3 = xform * verts[i1]
			var c: Vector3 = xform * verts[i2]
			if use_filter:
				var tri_aabb := AABB(a, Vector3.ZERO).expand(b).expand(c)
				if not tri_aabb.intersects(filter_aabb):
					continue
			out.append([a, b, c])
