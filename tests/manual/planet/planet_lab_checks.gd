class_name PlanetLabChecks
extends RefCounted
## Checks of the planet lab that need no scene of their own (the lab calls them and quits).


## `--water-check` (headless): water of the crust (rivers and lakes) over a spread of points.
static func water_check(tree: SceneTree) -> bool:
	if not "--water-check" in OS.get_cmdline_user_args():
		return false
	var made := PlanetSettings.new()
	made.hydrology_on = true
	made.drainage_cells = 96 # (the crust cuts the rivers along the drainage)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			made.world_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--radius="):
			made.radius = arg.trim_prefix("--radius=").to_float()
	var noise := PlanetNoise.new(made)
	# the crust's rivers and lakes: over a spread of points of the planet there is some water (a river
	# here and there,
	# not everywhere), and it is rarely over the sea or under the ground (a river's mouth and its
	# banks, a few in a hundred)
	var points := 0
	var wet := 0
	var over_sea := 0
	var under_ground := 0
	var widest := Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = made.world_seed
	for index in 40000:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var ground := noise.height(dir.x, dir.y, dir.z)
		points += 1
		var level := noise.water_at(dir, ground)
		if level > -INF:
			wet += 1
			widest = dir
			if ground < 0.0:
				over_sea += 1
			if level < ground - 0.31:
				under_ground += 1
	var verdict := ("PASS" if wet > 0 and wet < points / 3
			and over_sea + under_ground <= points / 100 else "FAIL")
	print("WATER_CHECK %s points=%d wet=%d over_sea=%d under_ground=%d" % [verdict, points, wet,
			over_sea,
			under_ground])
	print("RIVER_AT %f,%f,%f" % [widest.x, widest.y, widest.z])
	tree.quit()
	return true


## `--spawn-check` (headless): wherever a start is asked for (the sea included), the character is
## put on solid ground.
static func spawn_check(tree: SceneTree) -> bool:
	if not "--spawn-check" in OS.get_cmdline_user_args():
		return false
	var made := PlanetSettings.new()
	made.drainage_cells = 96
	made.world_seed = 7
	var noise := PlanetNoise.new(made)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var failed := 0
	var moved := 0
	for index in 120:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var spot := noise.solid_spawn(dir)
		if not noise.is_solid_ground(spot):
			failed += 1
		if spot.distance_to(dir) > 1.0e-7:
			moved += 1
	print("SPAWN_CHECK %s starts=120 moved=%d not_solid=%d" % ["PASS" if failed == 0 else "FAIL",
			moved, failed])
	tree.quit()
	return true



## The collision shapes of the plants (the bodies named Plants on the tiles): trunks, thick low
## limbs and rocks.
static func plant_shapes(node: Node) -> Dictionary:
	var found := {"cylinders": 0, "capsules": 0, "boxes": 0}
	for child in node.get_children():
		if child is StaticBody3D and child.name == &"Plants":
			for shape_node in child.get_children():
				var shape := (shape_node as CollisionShape3D).shape
				if shape is CylinderShape3D:
					found["cylinders"] += 1
				elif shape is CapsuleShape3D:
					found["capsules"] += 1
				elif shape is BoxShape3D:
					found["boxes"] += 1
		else:
			var inner := plant_shapes(child)
			for key: String in inner:
				found[key] += inner[key]
	return found


## `--sway-check` (with --plants, a window): at frame 200 the walker is put beside the nearest tree
## or shrub that can bend and held
## there; the check passes when that tree has been taken live and a branch of it was turned
## (PlanetSway). Prints SWAY_CHECK and quits.
static var _sway_worst := 0.0
static var _sway_target := Vector3.ZERO
static var _sway_drift := 1.0


static func sway_step(planet: PlanetWorld, player: Player, frame: int) -> void:
	if not "--sway-check" in OS.get_cmdline_user_args():
		return
	if frame == 200:
		var nearest := 1.0e9
		for tile: PlanetTile in planet.surface.tiles.values():
			if tile.plant_holder == null or not tile.plant_holder.has_meta(&"sway_sets"):
				continue
			for kind: Array in tile.plant_holder.get_meta(&"sway_sets"):
				var buffer: PackedFloat32Array = kind[1]
				var instance: MultiMeshInstance3D = kind[0]
				if instance.multimesh.mesh.get_aabb().size.y > 3.5:
					continue # (a shrub: its branches are within reach of the body)
				for index in buffer.size() / 16:
					var foot := tile.plant_holder.to_global(Vector3(buffer[index * 16 + 3], buffer[index * 16 + 7],
							buffer[index * 16 + 11]))
					var gap := foot.distance_to(player.global_position)
					if gap < nearest:
						nearest = gap
						_sway_target = foot
	if frame >= 200 and frame < 330 and _sway_target != Vector3.ZERO:
		player.global_position = _sway_target + Vector3(0.45, 0.3, 0.0) # (the branches are at the body)
		player.velocity = Vector3.ZERO
	var sway: PlanetSway = null
	for node in planet.get_children():
		if node is PlanetSway:
			sway = node
	if sway != null and frame > 210:
		_sway_worst = maxf(_sway_worst, sway.most_turned())
	if sway != null and frame >= 290 and frame < 330:
		_sway_drift = 0.0 if frame == 290 else _sway_drift
		# (the body stands still: no branch may keep moving)
		_sway_drift = maxf(_sway_drift, sway.jitter())
	if frame == 330:
		var live := 0 if sway == null else sway.live_count()
		var ok := sway != null and live > 0 and _sway_worst > 0.05 and _sway_drift < 0.01
		print(("SWAY_CHECK %s live=%d most_turned=%.2f rad still_jitter=%.4f rad/step "
				+ "nearest_tree=%.1f m") % [
				"PASS" if ok else "FAIL", live, _sway_worst, _sway_drift,
				_sway_target.distance_to(player.global_position)])
		planet.get_tree().quit(0 if ok else 1)


## `--turf-check` (with --plants, a window or headless): after the walker has stood still for a
## while the short grass of the ground
## is made round them (PlanetTurf): thousands of tufts, no more than a ring's worth. Prints
## TURF_CHECK and quits.
static func turf_step(planet: PlanetWorld, frame: int) -> void:
	if not "--turf-check" in OS.get_cmdline_user_args() or frame != 600:
		return
	var turf: PlanetTurf = null
	for node in planet.get_children():
		if node is PlanetTurf:
			turf = node
	var count := 0 if turf == null else turf.tuft_count()
	var ok := count > 3000 and count < 120000
	print("TURF_CHECK %s tufts=%d" % ["PASS" if ok else "FAIL", count])
	planet.get_tree().quit(0 if ok else 1)
