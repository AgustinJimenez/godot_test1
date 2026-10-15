extends Node
## Walk from the shore into the sea in the real level and see how far the player gets. Run headless:
##   godot --headless --path . res://tests/manual/world/world_water_walk_check.tscn -- --seed=N
## Prints the progress every second and WORLD_WATER_WALK_CHECK PASS / FAIL (the player must keep
## moving through wading and swimming: more than MIN_SPEED m/s on average over the last seconds).

const LEVEL := preload("res://levels/procedural_world.tscn")
const MIN_SPEED := 0.4
const SECONDS := 14

var _seed := 4242


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
	_run.call_deferred()


func _run() -> void:
	var level := LEVEL.instantiate()
	add_child(level)
	level.world.settings.world_seed = _seed
	level.world.rebuild()
	var player: Player = level.player
	var world: ProceduralWorld = level.world
	var shore := _find_shore(world)
	if shore.is_empty():
		print("WORLD_WATER_WALK_CHECK FAIL no shore found")
		get_tree().quit(1)
		return
	var at: Vector2 = shore["at"]
	var down: Vector2 = shore["down"]
	var spot := Vector3(at.x, world.ground_height(at.x, at.y) + 0.5, at.y)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-down.x, -down.y)
	world.build_around(spot)
	for frame in 60:
		await get_tree().physics_frame
	Input.action_press(&"move_forward", 1.0)
	var last := player.global_position
	var slow_seconds := 0
	for second in SECONDS:
		for frame in 60:
			await get_tree().physics_frame
		var now := player.global_position
		var speed := Vector2(now.x - last.x, now.z - last.z).length()
		last = now
		print("  t=%2ds  speed %.2f m/s  y %.2f  swimming %s  floor %s" % [
				second + 1, speed, now.y, str(world.swim.swimming), str(player.is_on_floor())])
		if second >= 6 and speed < MIN_SPEED:
			slow_seconds += 1
	# deep water: let go of the keys (the swimmer must stop), then swim off again from standing
	var failed := slow_seconds > 0
	if world.swim.swimming:
		Input.action_release(&"move_forward")
		var stop_from := player.global_position
		for frame in 180:
			await get_tree().physics_frame
		var drift := Vector2(player.global_position.x - stop_from.x,
				player.global_position.z - stop_from.z).length()
		print("  keys released for 3 s: drifted %.2f m, speed now %.2f" % [drift,
				Vector2(player.velocity.x, player.velocity.z).length()])
		var restart_from := player.global_position
		Input.action_press(&"move_forward", 1.0)
		for frame in 180:
			await get_tree().physics_frame
		var restarted := Vector2(player.global_position.x - restart_from.x,
				player.global_position.z - restart_from.z).length()
		print("  forward again for 3 s: moved %.2f m" % restarted)
		if restarted < 1.0:
			failed = true
	# from a standstill in deep water (a jump in, a teleport): can the player start swimming?
	Input.action_release(&"move_forward")
	var deep_at := at + down * 120.0
	player.global_position = Vector3(deep_at.x, world.settings.sea_level + 0.5, deep_at.y)
	player.velocity = Vector3.ZERO
	world.build_around(player.global_position)
	for frame in 120:
		await get_tree().physics_frame
	var from_rest := player.global_position
	Input.action_press(&"move_forward", 1.0)
	for frame in 180:
		await get_tree().physics_frame
	var start_moved := Vector2(player.global_position.x - from_rest.x,
			player.global_position.z - from_rest.z).length()
	print("  standing still in deep water, forward for 3 s: moved %.2f m (swimming %s)" % [
			start_moved, str(world.swim.swimming)])
	if start_moved < 1.0:
		failed = true
	Input.action_release(&"move_forward")
	print("WORLD_WATER_WALK_CHECK %s (%d slow seconds in the last %d)" % [
			"FAIL" if failed else "PASS", slow_seconds, SECONDS - 6])
	get_tree().quit(1 if failed else 0)


func _find_shore(world: ProceduralWorld) -> Dictionary:
	var noise := world.generator.noise
	var sea := world.settings.sea_level
	for ring in range(80, 2500, 40):
		for index in 24:
			var at := Vector2.from_angle(TAU * float(index) / 24.0 + float(ring) * 0.31) * float(ring)
			var h := noise.height(at.x, at.y)
			if h < sea + 1.0 or h > sea + 3.0:
				continue
			var dx := noise.height(at.x + 2.0, at.y) - noise.height(at.x - 2.0, at.y)
			var dz := noise.height(at.x, at.y + 2.0) - noise.height(at.x, at.y - 2.0)
			var down := Vector2(-dx, -dz).normalized()
			var ahead := at + down * 40.0
			if noise.height(ahead.x, ahead.y) < sea - 3.0:
				return {"at": at, "down": down}
	return {}
