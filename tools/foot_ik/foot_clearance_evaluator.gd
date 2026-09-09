class_name FootClearanceEvaluator
extends RefCounted
## Measurement only: final world-space foot samples against one finite box collider.
## No state, raycasts, target ownership, or bone writes. Orthogonal scaled boxes only.
## Complete mesh samples are a reference prototype, not a production per-frame budget.

const BOUNDARY_EPSILON_M := 0.000002


class Result extends RefCounted:
	var available := false
	var reason := "unmeasured"
	var sample_count := 0
	var penetrating_points := 0
	var outside_footprint_points := 0
	var boundary_points := 0
	var min_top_clearance_m := INF
	var max_penetration_m := 0.0
	var worst_point_index := -1
	var surface_normal := Vector3.ZERO
	# Exit for the single deepest point, NOT a feasible whole-foot pose correction.
	var deepest_point_exit := Vector3.ZERO
	var point_depths_m := PackedFloat32Array()
	var point_boundary := PackedByteArray()


static func evaluate_box(points_world: PackedVector3Array, box_to_world: Transform3D,
		box_size: Vector3, tolerance_m: float = 0.001) -> Result:
	var result := Result.new()
	if points_world.is_empty():
		result.reason = "no_samples"
		return result
	if (not box_to_world.is_finite() or not box_size.is_finite()
			or not is_finite(tolerance_m) or tolerance_m < 0.0
			or minf(box_size.x, minf(box_size.y, box_size.z)) <= 0.0):
		result.reason = "invalid_geometry"
		return result
	var axes: Array[Vector3] = [box_to_world.basis.x, box_to_world.basis.y, box_to_world.basis.z]
	var half := box_size * 0.5
	for axis in 3:
		var length := axes[axis].length()
		if length <= 0.000001:
			result.reason = "degenerate_box"
			return result
		half[axis] *= length
		axes[axis] /= length
	if (absf(axes[0].dot(axes[1])) > 0.00001
			or absf(axes[0].dot(axes[2])) > 0.00001
			or absf(axes[1].dot(axes[2])) > 0.00001):
		result.reason = "unsupported_sheared_box"
		return result
	for point: Vector3 in points_world:
		if not point.is_finite():
			result.reason = "invalid_sample"
			return result
	result.available = true
	result.reason = "measured_box"
	result.sample_count = points_world.size()
	result.point_depths_m.resize(points_world.size())
	result.point_boundary.resize(points_world.size())
	result.surface_normal = axes[1]
	for index in points_world.size():
		var relative := points_world[index] - box_to_world.origin
		var projected := Vector3(relative.dot(axes[0]), relative.dot(axes[1]), relative.dot(axes[2]))
		var face_clearance := projected.abs() - half
		var in_footprint := face_clearance.x <= 0.0 and face_clearance.z <= 0.0
		if not in_footprint:
			result.outside_footprint_points += 1
		elif projected.y > -half.y:
			result.min_top_clearance_m = minf(result.min_top_clearance_m, projected.y - half.y)
		# Signed distance to the closed solid, rather than its infinite top plane.
		var outside := face_clearance.max(Vector3.ZERO).length()
		var inside := minf(maxf(face_clearance.x, maxf(face_clearance.y, face_clearance.z)), 0.0)
		var signed_distance := outside + inside
		# Surface classification within a few micrometres is numerically ambiguous
		# across equivalent world/local transform arithmetic; report it explicitly.
		if (absf(signed_distance) <= BOUNDARY_EPSILON_M
				or absf(projected.y - half.y + tolerance_m) <= BOUNDARY_EPSILON_M):
			result.boundary_points += 1
			result.point_boundary[index] = 1
		# Match the reference oracle's top-face tolerance; shallow end/side entry
		# still counts, and depth reports distance to the nearest exit, not top height.
		if signed_distance >= 0.0 or projected.y - half.y >= -tolerance_m:
			continue
		result.penetrating_points += 1
		result.point_depths_m[index] = -signed_distance
		if -signed_distance > result.max_penetration_m:
			result.max_penetration_m = -signed_distance
			result.worst_point_index = index
			var exit_axis := face_clearance.max_axis_index()
			var direction := 1.0 if projected[exit_axis] >= 0.0 else -1.0
			result.deepest_point_exit = axes[exit_axis] * direction * -signed_distance
	return result
