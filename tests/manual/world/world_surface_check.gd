extends Node3D
## Is the ground you see the ground you stand on? Compares the VISIBLE terrain mesh with the physics
## heightmap (what the capsule and Foot IK meet) at the centre of thousands of cells. Run:
##   godot --headless --path . res://tests/manual/world/world_surface_check.tscn
## Prints WORLD_SURFACE_CHECK PASS / FAIL. Background: the heightmap splits every cell along one
## diagonal; a mesh that picks its own diagonal per cell (it once did) is 10-40 cm off in half the
## cells, so feet look like they float or sink even when IK is perfect.

const LIMIT := 0.01 ## m the two surfaces may differ

var _failures := 0

var _triangle_meshes: Dictionary = {}

func _ready() -> void:
	var world := ProceduralWorld.new()
	world.settings = WorldSettings.new()
	world.settings.world_seed = 1337
	add_child(world)
	var marker := Node3D.new()
	add_child(marker)
	world.set_target(marker)
	world.generator.chunks_per_frame = 8
	var step := world.settings.cell_size
	var spots: Array[Vector2] = [Vector2(300, 300), Vector2(-420, 260), Vector2(800, -200),
			Vector2(120, -640)]
	for spot in spots:
		marker.global_position = Vector3(spot.x, world.ground_height(spot.x, spot.y) + 1.0, spot.y)
		world.build_around(marker.global_position)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var diffs: Array[float] = []
		var origin := Vector2(snappedf(spot.x, step), snappedf(spot.y, step))
		for row in range(-40, 40):
			for column in range(-40, 40):
				var x := origin.x + (float(column) + 0.5) * step
				var z := origin.y + (float(row) + 0.5) * step
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
						Vector3(x, 200.0, z), Vector3(x, -100.0, z), 1))
				if hit.is_empty():
					continue
				var body := hit["collider"] as CollisionObject3D
				if not body.shape_owner_get_shape(body.shape_find_owner(int(hit["shape"])), 0) \
						is HeightMapShape3D:
					continue
				var seen := _visible_height(world, x, z)
				if is_nan(seen):
					continue
				diffs.append(absf((hit["position"] as Vector3).y - seen))
		if diffs.is_empty():
			_failures += 1
			print("  spot %s: no terrain cells found" % spot)
			continue
		diffs.sort()
		var over := 0
		var sum := 0.0
		for diff in diffs:
			sum += diff
			if diff > 0.02:
				over += 1
		var worst := diffs[diffs.size() - 1]
		if worst > LIMIT:
			_failures += 1
		print("  spot %s cells=%d mean=%.2f cm  p95=%.2f cm  worst=%.2f cm  over 2 cm: %d" % [
				spot, diffs.size(), sum / maxf(diffs.size(), 1) * 100.0,
				diffs[int(diffs.size() * 0.95)] * 100.0, worst * 100.0, over])
	print("WORLD_SURFACE_CHECK ", "PASS" if _failures == 0 else "FAIL (%d spots)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Height of the visible ground mesh at (x, z): a ray at the chunk's own terrain mesh (NAN if none).
func _visible_height(world: ProceduralWorld, x: float, z: float) -> float:
	var size := world.settings.chunk_size
	var coord := Vector2i(floori(x / size), floori(z / size))
	var chunk: TerrainChunk = world.generator.chunks.get(coord)
	if chunk == null:
		return NAN
	if not _triangle_meshes.has(coord):
		_triangle_meshes[coord] = (chunk.get_child(0) as MeshInstance3D).mesh.generate_triangle_mesh()
	var tri: TriangleMesh = _triangle_meshes[coord]
	var local := Vector3(x - chunk.position.x, 0.0, z - chunk.position.z)
	var found := tri.intersect_ray(local + Vector3.UP * 300.0, Vector3.DOWN)
	return NAN if found.is_empty() else (found["position"] as Vector3).y
