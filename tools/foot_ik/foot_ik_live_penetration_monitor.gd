class_name FootIkLivePenetrationMonitor
extends RefCounted
## Live (non-test) foot/geometry penetration check for the debug overlay - same box-penetration
## math as foot_ik_idle_plant_stability_check.gd's turn-sweep sampling, generalized to any set of
## world-space points so it can run every physics frame during ordinary manual play, not only a
## scripted test sweep.

const CLEARANCE_EVALUATOR := preload("res://tools/foot_ik/foot_clearance_evaluator.gd")
const PROBE_RADIUS := 0.05


## Checks each of points against whatever nearby StaticBody3D box collider(s) it actually
## overlaps right now (found generically, not a presumed tread) and returns the single worst
## result across all of them: {"penetrating": bool, "depth_m": float, "point": Vector3,
## "exit": Vector3}. depth_m/point/exit are only meaningful when penetrating is true.
static func check(space: PhysicsDirectSpaceState3D, points: PackedVector3Array,
		collision_mask: int) -> Dictionary:
	var worst := {"penetrating": false, "depth_m": 0.0, "point": Vector3.ZERO, "exit": Vector3.ZERO}
	for point: Vector3 in points:
		var query := PhysicsShapeQueryParameters3D.new()
		var probe := SphereShape3D.new()
		probe.radius = PROBE_RADIUS
		query.shape = probe
		query.transform = Transform3D(Basis.IDENTITY, point)
		query.collision_mask = collision_mask
		query.collide_with_areas = false
		for hit: Dictionary in space.intersect_shape(query, 4):
			var body: Object = hit.get("collider")
			if not (body is StaticBody3D):
				continue
			for child in (body as StaticBody3D).get_children():
				if not (child is CollisionShape3D):
					continue
				var shape: Shape3D = (child as CollisionShape3D).shape
				if not (shape is BoxShape3D):
					continue
				var result := CLEARANCE_EVALUATOR.evaluate_box(PackedVector3Array([point]),
						(child as CollisionShape3D).global_transform, (shape as BoxShape3D).size)
				if result.available and result.max_penetration_m > float(worst["depth_m"]):
					worst = {"penetrating": true, "depth_m": result.max_penetration_m,
							"point": point, "exit": result.deepest_point_exit}
	return worst
