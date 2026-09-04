class_name FootIKLandingPlanner
extends RefCounted
## Chooses one supported stance footprint while airborne and retains it to touchdown.

const HEIGHT_TOLERANCE := 0.03
const SEARCH_STEP := 0.05
const SEARCH_RINGS := 12
const SEARCH_DIRECTIONS := 8
const ROOT_CLEARANCE_SAMPLES := 16

var safe_root_target := Vector3(INF, INF, INF)
var committed_surface_y := -INF
var decision := "none"

var _sampler
var _owner
var _settings: FootIKRuntimeSettings


func _init(sampler, owner, settings: FootIKRuntimeSettings) -> void:
	_sampler = sampler
	_owner = owner
	_settings = settings


func reset() -> void:
	safe_root_target = Vector3(INF, INF, INF)
	committed_surface_y = -INF
	decision = "none"


func reject_grounded_mismatch(root: Vector3, height_tolerance: float,
		reject_idle_root: bool = false, root_tolerance: float = 0.05) -> bool:
	if not safe_root_target.is_finite() or not is_finite(committed_surface_y):
		return false
	var height_error := absf(root.y - committed_surface_y)
	var root_error := _horizontal_distance(root, safe_root_target)
	if height_error <= height_tolerance and (not reject_idle_root or root_error <= root_tolerance):
		return false
	safe_root_target = Vector3(INF, INF, INF)
	committed_surface_y = -INF
	decision = ("reject_idle_root error=%.3f" % root_error if reject_idle_root \
			and height_error <= height_tolerance else "reject_grounded_height error=%.3f" % height_error)
	return true


func predict(space: PhysicsDirectSpaceState3D, max_landing_drop: float) -> Vector3:
	if not _settings.airborne_safe_zone_enabled:
		reset()
		decision = "disabled"
		return Vector3(INF, INF, INF)
	if safe_root_target.is_finite():
		decision = "hold_commit"
		return safe_root_target
	var character := _owner.player_body.get_parent() as Player
	var skel: Skeleton3D = _owner.get_skeleton()
	if character == null or skel == null:
		return Vector3(INF, INF, INF)
	var root := character.global_position
	var feet := _predicted_feet(character, skel)
	if feet.size() < 2:
		return Vector3(INF, INF, INF)
	var footprint := _stance_footprint(
			feet[&"left"], feet[&"right"], -character.global_basis.z)
	var coverage_footprint := _coverage_footprint(
			feet[&"left"], feet[&"right"], -character.global_basis.z)
	var probe_y := root.y + 0.8
	var surfaces := _surface_coverage(
			space, coverage_footprint, probe_y, max_landing_drop)
	if surfaces.is_empty():
		decision = "no_flat_support"
		return Vector3(INF, INF, INF)
	var best_root := Vector3(INF, INF, INF)
	var best_surface_y := -INF
	var best_coverage := -1
	var best_distance := INF
	for surface: Dictionary in surfaces:
		var surface_y := float(surface["y"])
		if root.y - surface_y > max_landing_drop:
			continue
		var candidate := _nearest_full_stance_root(
				space, root, footprint, surface_y, probe_y)
		if not candidate.is_finite():
			continue
		var coverage := int(surface["count"])
		var distance := _horizontal_distance(root, candidate)
		if distance > _settings.max_airborne_correction:
			continue
		if coverage > best_coverage or (coverage == best_coverage and distance < best_distance):
			best_root = candidate
			best_surface_y = surface_y
			best_coverage = coverage
			best_distance = distance
	if not best_root.is_finite():
		decision = "no_full_stance"
	elif best_distance <= 0.015 and surfaces.size() == 1:
		safe_root_target = best_root
		committed_surface_y = best_surface_y
		decision = "commit_already_safe coverage=%d/%d" % [
				best_coverage, coverage_footprint.size()]
	else:
		safe_root_target = best_root
		committed_surface_y = best_surface_y
		decision = "commit coverage=%d/%d" % [best_coverage, coverage_footprint.size()]
	return safe_root_target


func _predicted_feet(character: Player, skel: Skeleton3D) -> Dictionary:
	var result := {}
	for side: StringName in [&"left", &"right"]:
		if _sampler.airborne_landing_probe_local.has(side):
			result[side] = character.global_position + character.global_basis \
					* (_sampler.airborne_landing_probe_local[side] as Vector3)
			continue
		var foot_index: int = _owner._bone_indices.get(side, {}).get(&"foot", -1)
		if foot_index >= 0:
			result[side] = skel.global_transform * skel.get_bone_global_pose(foot_index).origin
	return result


func _stance_footprint(left: Vector3, right: Vector3, forward: Vector3) -> Array[Vector3]:
	return _footprint(left, right, forward, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0])


func _coverage_footprint(left: Vector3, right: Vector3,
		forward: Vector3) -> Array[Vector3]:
	return _footprint(left, right, forward, [-0.15, 0.1, 0.35, 0.65, 0.9, 1.15])


func _footprint(left: Vector3, right: Vector3, forward: Vector3,
		lateral_ratios: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	forward.y = 0.0
	forward = forward.normalized()
	for lateral_ratio: float in lateral_ratios:
		var center := left.lerp(right, lateral_ratio)
		for depth_ratio: float in [-1.0, 0.0, 1.0]:
			result.append(center + forward * _settings.landing_footprint_depth * depth_ratio)
	return result


func _surface_coverage(space: PhysicsDirectSpaceState3D, footprint: Array[Vector3],
		probe_y: float, max_landing_drop: float) -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = []
	for point: Vector3 in footprint:
		var hit: Dictionary = _sampler.raycast_ground(
				space, Vector3(point.x, probe_y, point.z), max_landing_drop + 1.0)
		if not hit["hit"] or (hit["normal"] as Vector3).dot(Vector3.UP) \
				< _sampler.STAIR_TREAD_UP_DOT:
			continue
		var y := (hit["position"] as Vector3).y
		var matched := false
		for surface: Dictionary in surfaces:
			if absf(float(surface["y"]) - y) <= HEIGHT_TOLERANCE:
				surface["count"] = int(surface["count"]) + 1
				matched = true
				break
		if not matched:
			surfaces.append({"y": y, "count": 1})
	return surfaces


func _nearest_full_stance_root(space: PhysicsDirectSpaceState3D, root: Vector3,
		footprint: Array[Vector3], surface_y: float, probe_y: float) -> Vector3:
	if _full_stance_supported(space, root, footprint, Vector3.ZERO, surface_y, probe_y):
		return root
	for ring in range(1, SEARCH_RINGS + 1):
		var radius := float(ring) * SEARCH_STEP
		for sample_index in SEARCH_DIRECTIONS:
			var angle := TAU * float(sample_index) / float(SEARCH_DIRECTIONS)
			var motion := Vector3(cos(angle), 0.0, sin(angle)) * radius
			if _full_stance_supported(space, root, footprint, motion, surface_y, probe_y):
				return root + motion
	return Vector3(INF, INF, INF)


func _full_stance_supported(space: PhysicsDirectSpaceState3D, root: Vector3,
		footprint: Array[Vector3], motion: Vector3, surface_y: float, probe_y: float) -> bool:
	if not _sampler._has_surface_at_height(space, root + motion, surface_y, probe_y):
		return false
	if not _capsule_clears_landing(space, root + motion, surface_y):
		return false
	if not _root_clears_higher_surface(space, root + motion, surface_y, probe_y):
		return false
	for point: Vector3 in footprint:
		if not _sampler._has_surface_at_height(space, point + motion, surface_y, probe_y):
			return false
	return true


func _capsule_clears_landing(space: PhysicsDirectSpaceState3D,
		root: Vector3, surface_y: float) -> bool:
	var character := _owner.player_body.get_parent() as Player
	if character == null:
		return false
	var collision := character.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.shape == null:
		return false
	var landing_transform := character.global_transform
	landing_transform.origin = Vector3(root.x, surface_y + 0.03, root.z)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = landing_transform * collision.transform
	query.collision_mask = _sampler.WORLD_COLLISION_MASK
	query.exclude = [character.get_rid()]
	return space.intersect_shape(query, 1).is_empty()


func _root_clears_higher_surface(space: PhysicsDirectSpaceState3D, root: Vector3,
		surface_y: float, probe_y: float) -> bool:
	for sample_index in ROOT_CLEARANCE_SAMPLES:
		var angle := TAU * float(sample_index) / float(ROOT_CLEARANCE_SAMPLES)
		var point := root + Vector3(cos(angle), 0.0, sin(angle)) \
				* _settings.landing_root_clearance_radius
		var hit: Dictionary = _sampler.raycast_ground(
				space, Vector3(point.x, probe_y, point.z), probe_y - surface_y + 1.0)
		if hit["hit"] and (hit["position"] as Vector3).y > surface_y + HEIGHT_TOLERANCE:
			return false
	return true


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()
