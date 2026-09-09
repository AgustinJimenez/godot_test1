extends Node
## Analytic fixtures keep the mesh comparison from validating shared mistakes alone.

const EVALUATOR := preload("res://tools/foot_ik/foot_clearance_evaluator.gd")
const SKIN_SAMPLES := preload("res://tools/foot_ik/foot_clearance_skin_samples.gd")
var _failures: Array[String] = []


func _ready() -> void:
	_check_skin_samples()
	for slope: float in [0.0, 15.0, 30.0, 45.0]:
		for yaw: float in [0.0, 45.0, 135.0, 270.0]:
			var basis := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(slope))
			var box := Transform3D(basis, Vector3(8.0, 2.0, -4.0))
			_check_point(box, Vector3(0.0, 0.48, 0.0), 0.02, "ball_in_top")
			_check_point(box, Vector3(0.99, 0.2, 0.0), 0.01, "side_entry")
			_check_point(box, Vector3(0.0, 0.2, 0.99), 0.01, "end_entry")
			_check_point(box, Vector3(1.02, 0.48, 0.0), 0.0, "outside_finite_ramp")
			_check_point(box, Vector3(0.0, -0.52, 0.0), 0.0, "under_separate_platform")
			_check_point(box, Vector3(0.0, 0.52, 0.0), 0.0, "above_support")
			var points := PackedVector3Array([box * Vector3(0.0, 0.52, -0.3),
					box * Vector3(0.1, 0.48, 0.0), box * Vector3(0.0, 0.52, 0.3)])
			var result := EVALUATOR.evaluate_box(points, box, Vector3(2.0, 1.0, 2.0))
			_expect(result.worst_point_index == 1, "clear tips must not hide embedded ball/width")
			_expect(absf(result.min_top_clearance_m + 0.02) < 0.00001, "signed normal clearance")
	var scaled := Transform3D(Basis.from_scale(Vector3(2.0, 3.0, 4.0)), Vector3.ZERO)
	_check_point(scaled, Vector3(0.0, 0.48, 0.0), 0.06, "scaled_world_metres")
	_expect(not EVALUATOR.evaluate_box(PackedVector3Array(), scaled, Vector3.ONE).available,
			"empty input is unknown, not clear")
	var shear := Transform3D(Basis(Vector3.RIGHT, Vector3(0.2, 1.0, 0.0), Vector3.BACK), Vector3.ZERO)
	_expect(not EVALUATOR.evaluate_box(PackedVector3Array([Vector3.ZERO]), shear,
			Vector3.ONE).available, "unsupported shear must be explicit")
	print("FOOT_IK_CLEARANCE_GEOMETRY_CHECK %s failures=%s" % [
			"PASS" if _failures.is_empty() else "FAIL", _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_point(box: Transform3D, local: Vector3, depth: float, label: String) -> void:
	var result := EVALUATOR.evaluate_box(PackedVector3Array([box * local]), box, Vector3(2, 1, 2))
	_expect(result.available and absf(result.max_penetration_m - depth) < 0.00001, label)
	_expect(result.penetrating_points == (1 if depth > 0.0 else 0), label + ":count")
	if depth > 0.0:
		var resolved := EVALUATOR.evaluate_box(PackedVector3Array([
				box * local + result.deepest_point_exit * 1.001]), box, Vector3(2, 1, 2))
		_expect(resolved.max_penetration_m < 0.00001, label + ":point_exit")


func _expect(condition: bool, reason: String) -> void:
	if not condition:
		_failures.append(reason)


func _check_skin_samples() -> void:
	var samples := SKIN_SAMPLES.new()
	var vertices := PackedVector3Array([Vector3(1, 2, 3), Vector3(-1, 0, 2)])
	var bones := PackedInt32Array([0, 1, 99, -1, 0, 1, 0, 1])
	var weights := PackedFloat32Array([0.25, 0.5, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0])
	_expect(samples.append_surface(vertices, bones, weights, PackedInt32Array([0, 1])),
			"cache accepts four-influence skin")
	var transforms: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 1.2).scaled(Vector3(2, 1, 0.5)), Vector3(3, 4, 5)),
		Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(-2, 3, 1))]
	var fallback := Transform3D(Basis.IDENTITY, Vector3(5, 6, 7))
	var points := samples.sample(transforms, fallback)
	var expected := ((transforms[0] * vertices[0]) * 0.25
			+ (transforms[1] * vertices[0]) * 0.5) / 0.75
	_expect(points[0].distance_to(expected) < 0.000001, "normalize valid influences only")
	_expect(points[1] == fallback * vertices[1], "zero weights use mesh fallback")
	vertices[0] = Vector3.ZERO
	weights[0] = 100.0
	_expect(samples.sample(transforms, fallback) == points, "baked inputs and refresh are stable")
	transforms[1].origin += Vector3.UP
	var moved := samples.sample(transforms, fallback)
	_expect(absf(moved[0].y - points[0].y - 2.0 / 3.0) < 0.000001,
			"new pose is evaluated without cached output or time advancement")
	_expect(not samples.append_surface(vertices, bones, weights, PackedInt32Array([2])),
			"invalid selection is rejected atomically")
	_expect(samples.sample(transforms, fallback) == moved, "failed append preserves prior data")
	var eight := SKIN_SAMPLES.new()
	_expect(eight.append_surface(PackedVector3Array([Vector3.ONE]),
			PackedInt32Array([0, 1, 0, 1, 0, 1, 0, 1]),
			PackedFloat32Array([0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125]),
			PackedInt32Array([0])), "eight-influence skin")
	var eight_expected := ((transforms[0] * Vector3.ONE) + (transforms[1] * Vector3.ONE)) * 0.5
	_expect(eight.sample(transforms, fallback)[0].distance_to(eight_expected) < 0.000002,
			"eight-influence pose")
