extends Node3D
## Walking straight uphill into slopes of growing steepness on the procedural terrain.
## Run (after --): --seed=N (default 1337)
## Per slope it prints how far the player got uphill in WALK_FRAMES, the height gained, the share
## of frames on the floor, the height gained on frames OFF the floor (air climb: the bug, a body
## that is "falling" on a too steep slope must not move up) and the animation at the end.
## Ends with WORLD_STEEP_CHECK PASS / FAIL (air climb over AIR_CLIMB_LIMIT m on any slope).

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const SETTLE_FRAMES := 40
const WALK_FRAMES := 120
const BANDS := [Vector2(10.0, 25.0), Vector2(30.0, 40.0), Vector2(46.0, 55.0),
		Vector2(55.0, 65.0), Vector2(65.0, 80.0)]
const SPOTS_PER_BAND := 6
const AIR_CLIMB_LIMIT := 0.05

var world: ProceduralWorld
var player: Player
var _seed := 1337
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
	world = ProceduralWorld.new()
	world.settings = WorldSettings.new()
	world.settings.world_seed = _seed
	add_child(world)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	world.set_target(player)
	world.generator.chunks_per_frame = 8
	_run.call_deferred()


func _run() -> void:
	print("WORLD_STEEP_CHECK seed %d floor_max_angle %.0f deg" % [
			_seed, rad_to_deg(player.floor_max_angle)])
	for band: Vector2 in BANDS:
		for spot in _find_spots(band, SPOTS_PER_BAND):
			await _walk_uphill(spot)
	print("WORLD_STEEP_CHECK %s" % ("PASS" if _failures == 0 else "FAIL (%d slopes)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _angle_deg(at: Vector2) -> float:
	var noise := world.generator.noise
	var dx := (noise.height(at.x + 0.5, at.y) - noise.height(at.x - 0.5, at.y))
	var dz := (noise.height(at.x, at.y + 0.5) - noise.height(at.x, at.y - 0.5))
	return rad_to_deg(atan(Vector2(dx, dz).length()))


func _find_spots(band: Vector2, count: int) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var noise := world.generator.noise
	for ring in range(40, 1800, 23):
		for index in 16:
			var at := Vector2.from_angle(TAU * float(index) / 16.0 + float(ring) * 0.61) * float(ring)
			if noise.height(at.x, at.y) < world.settings.sea_level + 5.0:
				continue
			var angle := _angle_deg(at)
			if angle >= band.x and angle < band.y:
				spots.append(at)
				if spots.size() >= count:
					return spots
	return spots


func _walk_uphill(at: Vector2) -> void:
	var noise := world.generator.noise
	var dx := noise.height(at.x + 0.5, at.y) - noise.height(at.x - 0.5, at.y)
	var dz := noise.height(at.x, at.y + 0.5) - noise.height(at.x, at.y - 0.5)
	var uphill := Vector2(dx, dz).normalized()
	var start := Vector3(at.x, noise.height(at.x, at.y) + 0.4, at.y)
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-uphill.x, -uphill.y) # Godot's forward is -Z
	world.build_around(start)
	for frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	var begin := player.global_position
	var floor_frames := 0
	var air_climb := 0.0
	var last_y := begin.y
	Input.action_press(&"move_forward", 1.0)
	for frame in WALK_FRAMES:
		await get_tree().physics_frame
		if player.is_on_floor():
			floor_frames += 1
		else:
			air_climb += maxf(player.global_position.y - last_y, 0.0)
		last_y = player.global_position.y
	Input.action_release(&"move_forward")
	var moved := player.global_position - begin
	var along := Vector2(moved.x, moved.z).dot(uphill)
	var anim := player.body.anim_player
	if air_climb > AIR_CLIMB_LIMIT:
		_failures += 1
	print("  slope %4.1f deg  uphill %+5.2f m  height %+5.2f m  on floor %3d%%  air climb %.2f m"
			% [_angle_deg(at), along, moved.y, floor_frames * 100 / WALK_FRAMES, air_climb]
			+ "  anim %s" % (anim.current_animation if anim else "?"))
