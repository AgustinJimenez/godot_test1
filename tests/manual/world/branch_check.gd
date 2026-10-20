extends Node
## Every vertex of a grown tree knows its branch, and sits on or near it:
##   godot --headless --path . res://tests/manual/world/branch_check.tscn


func _ready() -> void:
	var ok := true
	var trees := 0
	var seen := {}
	for one in SpeciesRegistry.new(8, 36).species:
		if one.is_tree():
			if trees >= 6:
				continue
		elif seen.has(one.form):
			continue # (one of each growth form)
		seen[one.form] = true
		trees += 1
		var mesh := PlantMeshes.build(one, 0, true)
		var table: PackedFloat32Array = mesh.get_meta(&"branches", PackedFloat32Array())
		if table.is_empty():
			print("BRANCH_CHECK (nothing to bend) %s" % one.summary().substr(0, 40))
			ok = ok and not one.is_tree()
			continue
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		var count := table.size() / 10
		var moving := 0
		var near := 0
		var farthest := 0.0
		for index in points.size():
			var id := int(ids[index])
			if id <= 0:
				continue
			if id >= count:
				print("BRANCH_CHECK id %d out of %d" % [id, count])
				ok = false
				break
			moving += 1
			var row := id * 10
			var foot := Vector3(table[row + 2], table[row + 3], table[row + 4])
			var tip := Vector3(table[row + 5], table[row + 6], table[row + 7])
			var closest := Geometry3D.get_closest_point_to_segment(points[index], foot, tip)
			var gap := points[index].distance_to(closest)
			farthest = maxf(farthest, gap)
			# (a leaf mass hangs about a branch tip)
			if gap < 0.6 + table[row + 8] * 2.0 + table[row + 9] * 0.7:
				near += 1
		var share := float(near) / maxf(float(moving), 1.0)
		print("BRANCH_CHECK %-22s branches=%d vertices=%d moving=%.0f%% near=%.0f%% farthest=%.1f m" % [
				one.common_name, count - 1, points.size(), 100.0 * moving / points.size(), 100.0 * share,
				farthest])
		ok = ok and count > 3 and share > 0.8 and moving > points.size() / 4
	print("BRANCH_CHECK ", "PASS" if ok and trees > 0 else "FAIL")
	get_tree().quit(0 if ok else 1)
