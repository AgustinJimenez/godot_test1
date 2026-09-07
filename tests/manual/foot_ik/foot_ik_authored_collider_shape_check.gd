extends Node
## Regression guard for the ramp/stairs FPS drop (see 012's "Preview-scene FPS
## drop near ramps/stairs" section): every authored tread/riser/platform box
## must get a convex BoxShape3D collider, never CSGShape3D's own baked
## concave ConcavePolygonShape3D trimesh, since Foot IK's ground sampler
## raycasts these boxes every physics frame for every nearby character.

const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_check_finalize_authored_box()
	_check_build_top_landing()
	print("FOOT_IK_AUTHORED_COLLIDER_SHAPE_CHECK %s failures=%s" % [
			"PASS" if _failures.is_empty() else "FAIL", _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_finalize_authored_box() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var box := CSGBox3D.new()
	box.size = Vector3(3.0, 0.3, 4.0)
	box.use_collision = true
	box.position = Vector3(1.0, 2.0, 3.0)
	STAIR_SURFACES.finalize_authored_box(parent, box)
	_expect(not box.use_collision, "CSG node's own concave collision must be disabled")
	_expect(box.get_parent() == parent, "box itself must still be added under parent")
	_check_sibling_box_collider(parent, box, "finalize_authored_box")


func _check_build_top_landing() -> void:
	var parent := Node3D.new()
	add_child(parent)
	STAIR_SURFACES.build_top_landing(parent, Vector3.ZERO, 3.0, 0.6, 6, 0.2)
	var landing_box: CSGBox3D
	for child in parent.get_children():
		if child is CSGBox3D and (child as CSGBox3D).size.y > 0.1: # skip the thin tread cap
			landing_box = child
			break
	if landing_box == null:
		_failures.append("build_top_landing did not create the expected riser CSGBox3D")
		return
	_expect(not landing_box.use_collision,
			"build_top_landing's riser box must not keep CSG concave collision")
	_check_sibling_box_collider(parent, landing_box, "build_top_landing")


func _check_sibling_box_collider(parent: Node3D, box: CSGBox3D, label: String) -> void:
	var body: StaticBody3D
	for child in parent.get_children():
		if child is StaticBody3D:
			body = child
			break
	if body == null:
		_failures.append("%s: no sibling StaticBody3D collider found" % label)
		return
	var shape: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D:
			shape = child
			break
	if shape == null or shape.shape == null:
		_failures.append("%s: sibling StaticBody3D has no CollisionShape3D" % label)
		return
	if not (shape.shape is BoxShape3D):
		_failures.append("%s: collider shape is %s, expected BoxShape3D (convex)" % [
				label, shape.shape.get_class()])
		return
	var box_shape := shape.shape as BoxShape3D
	_expect(box_shape.size.is_equal_approx(box.size),
			"%s: collider size must match the authored box's visual size" % label)
	_expect(body.transform.is_equal_approx(box.transform),
			"%s: collider transform must match the authored box's transform" % label)


func _expect(passed: bool, reason: String) -> void:
	if not passed:
		_failures.append(reason)
