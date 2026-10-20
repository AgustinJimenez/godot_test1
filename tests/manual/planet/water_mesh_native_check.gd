extends Node3D
## Small geometry contract for the native tile-water builder. No scene or renderer is needed.


func _ready() -> void:
	if not ClassDB.class_exists(&"PlanetWaterNative"):
		print("WATER_MESH_CHECK FAIL native class missing")
		get_tree().quit(1)
		return
	var water: Object = ClassDB.instantiate(&"PlanetWaterNative")
	var cells := 4
	var side := cells + 3
	var dirs := PackedVector3Array()
	var heights := PackedFloat32Array()
	var samples := PackedVector3Array()
	for row in side:
		for column in side:
			dirs.append(Vector3(float(column), 1.0, float(row)))
			heights.append(1.0)
			samples.append(Vector3(-1.0e9, 0.0, 0.0))
	var origin := PackedFloat64Array([0.0, 0.0, 0.0])
	var sea: Dictionary = water.call(&"sea_mesh", dirs, cells, 20.0, 10.0, 0.0,
			origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var sea_vertices: PackedVector3Array = sea["vertices"]
	var good := sea_vertices.size() == 12 * 12 * 6
	good = good and (sea["normals"] as PackedVector3Array).size() == sea_vertices.size()
	good = good and (sea["colours"] as PackedColorArray).size() == sea_vertices.size()
	good = good and sea_vertices[0].is_equal_approx(Vector3(10.0, 10.0, 10.0))
	var dry: Dictionary = water.call(&"river_mesh", dirs, heights, samples, cells, 10.0, 0.0,
			origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	good = good and (dry["vertices"] as PackedVector3Array).is_empty()
	samples[3 * side + 3] = Vector3(2.0, 0.5, 0.25)
	var river: Dictionary = water.call(&"river_mesh", dirs, heights, samples, cells, 10.0, 0.0,
			origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var river_vertices: PackedVector3Array = river["vertices"]
	var river_uvs: PackedVector2Array = river["uvs"]
	good = good and river_vertices.size() == 24
	good = good and river_uvs.size() == river_vertices.size()
	good = good and river_uvs.has(Vector2(0.25, 0.5))
	print("WATER_MESH_CHECK %s sea=%d river=%d" % ["PASS" if good else "FAIL",
			sea_vertices.size(), river_vertices.size()])
	get_tree().quit(0 if good else 1)
