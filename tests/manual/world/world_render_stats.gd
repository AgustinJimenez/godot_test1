extends Node3D
## Render cost of the procedural world as the GPU sees it, from a real window (headless has no
## renderer): stands in a forest, turns slowly all the way round, and prints the average and the
## worst of the triangles drawn per frame, the draw calls, the frame time and the FPS.
## Run (needs a window):
##   godot --path . res://tests/manual/world/world_render_stats.tscn -- --seed=N
## Options: --realistic (the realistic look; default low-poly)  --frames=N  --spot=forest|any
## Prints WORLD_RENDER_STATS ... and quits.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const SETTLE_FRAMES := 120

var world: ProceduralWorld
var player: Player
var _seed := 1337
var _frames := 720
var _realistic := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--frames="):
			_frames = arg.get_slice("=", 1).to_int()
		elif arg == "--realistic":
			_realistic = true
	world = ProceduralWorld.new()
	world.settings = WorldSettings.new()
	world.settings.world_seed = _seed
	world.realism = 1.0 if _realistic else 0.0
	add_child(world)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	world.set_target(player)
	world.generator.chunks_per_frame = 8
	_run.call_deferred()


func _run() -> void:
	var spot := _find_forest()
	player.global_position = Vector3(spot.x, world.ground_height(spot.x, spot.y) + 0.5, spot.y)
	world.build_around(player.global_position)
	player.set_physics_process(false) # stand still; only the view turns
	for frame in SETTLE_FRAMES:
		await get_tree().process_frame
	var triangles: Array[float] = []
	var draws: Array[float] = []
	var times: Array[float] = []
	for frame in _frames:
		player.rotation.y = TAU * float(frame) / float(_frames)
		await get_tree().process_frame
		triangles.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	print("WORLD_RENDER_STATS seed=%d look=%s spot=(%.0f,%.0f) triangles avg=%.0f worst=%.0f "
			% [_seed, "realistic" if _realistic else "low-poly", spot.x, spot.y, _mean(triangles),
			_worst(triangles)] + "draws avg=%.0f worst=%.0f  cpu_frame avg=%.2f ms fps=%.0f" % [
			_mean(draws), _worst(draws), _mean(times), Engine.get_frames_per_second()])
	get_tree().quit()


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(float(values.size()), 1.0)


func _worst(values: Array[float]) -> float:
	var worst := 0.0
	for value in values:
		worst = maxf(worst, value)
	return worst


## A land point well above the sea with gentle slope, away from the spawn, on a ring search.
func _find_forest() -> Vector2:
	var noise := world.generator.noise
	for ring in range(60, 1500, 40):
		for index in 16:
			var at := Vector2.from_angle(TAU * float(index) / 16.0 + float(ring) * 0.43) * float(ring)
			var h := noise.height(at.x, at.y)
			if h > world.settings.sea_level + 8.0 and noise.slope(at.x, at.y) < 0.2 \
					and noise.moisture(at.x, at.y) > 0.5:
				return at
	return Vector2(40.0, 40.0)
