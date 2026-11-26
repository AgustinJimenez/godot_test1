extends SceneTree
## Checks HumanBodyHair on the male body: no hair at amount 0; every area grows hair at amount 1; an area at 0 grows none while the others keep theirs;
## the same settings give the same hair; the roots are on the skin and never on the head, the hands or the feet; the hair carries the body's hair shapes
## and moves with the body under the weight shape. Prints HUMAN_BODY_HAIR_CHECK PASS or the failures.

const BODY := "res://assets/models/humans/male_body.glb"
const AREAS := ["chest", "belly", "back", "upper_arm", "forearm", "thigh", "shin", "armpit"]

var _failures: PackedStringArray = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _init() -> void:
	var scene: Node = (load(BODY) as PackedScene).instantiate()
	var body_mesh: ArrayMesh = _find_mesh(scene).mesh as ArrayMesh
	var data: HumanHairBody = HumanHair.prepare(body_mesh)
	var joints: Dictionary = BodyHairJoints.for_gender("Male")
	_check(joints.size() == 14, "joints from the rig: %d of 14" % joints.size())
	var params: Dictionary = HumanBodyHair.default_params()
	params["joints"] = joints

	# (a) no hair at amount 0
	params["amount"] = 0.0
	var none: Dictionary = HumanBodyHair.build_arrays(data, params)
	_check(int(none.get("hairs", -1)) == 0, "amount 0 grows %s hairs" % none.get("hairs"))

	# (b) every area at amount 1, and a sane total
	params["amount"] = 1.0
	params["back"] = 1.0
	var t0 := Time.get_ticks_msec()
	var full: Dictionary = HumanBodyHair.build_arrays(data, params)
	var build_ms := Time.get_ticks_msec() - t0
	var counts: Dictionary = full["area_hairs"]
	print("HUMAN_BODY_HAIR_CHECK hairs ", full["hairs"], " ", counts, " vertices ", full["vertex_count"], " build ms ", build_ms)
	for area: String in AREAS:
		_check(int(counts.get(area, 0)) > 50, "area %s has %s hairs at amount 1" % [area, counts.get(area)])
	_check(int(full["hairs"]) > 10000 and int(full["hairs"]) <= 60000, "total hairs %s (10,000 .. 60,000)" % full["hairs"])

	# (c) the chest at 0: no chest hair, the forearms unchanged
	var no_chest_params: Dictionary = params.duplicate()
	no_chest_params["chest"] = 0.0
	var no_chest: Dictionary = HumanBodyHair.build_arrays(data, no_chest_params)
	var nc: Dictionary = no_chest["area_hairs"]
	_check(int(nc["chest"]) < int(counts["chest"]) / 20, "chest at 0 still grows %s chest hairs (of %s)" % [nc["chest"], counts["chest"]])
	_check(int(nc["forearm"]) > int(counts["forearm"]) / 2, "chest at 0 took the forearms from %s to %s" % [counts["forearm"], nc["forearm"]])

	# (d) the same settings, the same hair
	var again: Dictionary = HumanBodyHair.build_arrays(data, params)
	_check((again["arrays"] as Array)[Mesh.ARRAY_VERTEX] == (full["arrays"] as Array)[Mesh.ARRAY_VERTEX], "two builds with the same settings differ")

	# (e) the roots: on the skin (within 4 cm of a body vertex: the size of the largest triangles), below the neck, not on the hands or the feet
	var body_vertices: PackedVector3Array = (body_mesh.surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]
	var neck_y: float = (joints["neck"] as Vector3).y
	var roots: PackedVector3Array = full["roots"]
	var off_skin := 0
	var on_head := 0
	var on_ends := 0
	for i in range(0, roots.size(), 97):
		var r: Vector3 = roots[i]
		var nearest := 1e9
		for j in body_vertices.size():
			nearest = minf(nearest, r.distance_to(body_vertices[j]))
		if nearest > 0.04:   # (the calf's triangles are large: a root there was measured 3.1 cm from the nearest corner)
			off_skin += 1
		if r.y > neck_y:
			on_head += 1
		for end: String in ["wrist_l", "wrist_r", "ankle_l", "ankle_r"]:
			if r.distance_to(joints[end]) < 0.02:
				on_ends += 1
	_check(off_skin == 0, "%d sampled roots are off the skin" % off_skin)
	_check(on_head == 0, "%d sampled roots are above the neck joint" % on_head)
	_check(on_ends == 0, "%d sampled roots sit on a wrist or an ankle" % on_ends)

	# (f) the shapes: the hair has the body's hair shapes, and under weight_heavy its roots stay on the heavy body
	var mesh: ArrayMesh = HumanHair.make_mesh(full)
	var names: Array = []
	for s in mesh.get_blend_shape_count():
		names.append(String(mesh.get_blend_shape_name(s)))
	_check(names.has("weight_heavy") and names.has("height_tall") and names.has("muscle_high"), "hair shapes: %s" % [names])
	var heavy_index: int = names.find("weight_heavy")
	if heavy_index >= 0:
		var hair_heavy: PackedVector3Array = ((full["blend_arrays"] as Array)[heavy_index] as Array)[Mesh.ARRAY_VERTEX]
		var body_index: int = -1
		for s in body_mesh.get_blend_shape_count():
			if body_mesh.get_blend_shape_name(s) == &"weight_heavy":
				body_index = s
		var body_heavy: PackedVector3Array = (body_mesh.surface_get_blend_shape_arrays(0)[body_index] as Array)[Mesh.ARRAY_VERTEX]
		if body_mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE:
			for j in body_heavy.size():
				body_heavy[j] += body_vertices[j]   # (relative shapes hold offsets)
		var hair_vertices: PackedVector3Array = (full["arrays"] as Array)[Mesh.ARRAY_VERTEX]
		var moved := 0.0
		var off_heavy := 0
		for i in range(0, hair_vertices.size(), 4999):
			moved = maxf(moved, hair_vertices[i].distance_to(hair_heavy[i]))
			var nearest := 1e9
			for j in body_heavy.size():
				nearest = minf(nearest, hair_heavy[i].distance_to(body_heavy[j]))
			if nearest > 0.06:   # (a hair vertex: the root's distance plus the hair's own length, up to 2.6 cm in the armpit)
				off_heavy += 1
		_check(moved > 0.01, "the weight shape moves the hair at most %.4f m" % moved)
		_check(off_heavy == 0, "%d sampled hair vertices leave the heavy body" % off_heavy)

	scene.free()
	if _failures.is_empty():
		print("HUMAN_BODY_HAIR_CHECK PASS")
	else:
		for failure in _failures:
			print("HUMAN_BODY_HAIR_CHECK FAIL ", failure)
	quit()
