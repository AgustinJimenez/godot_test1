extends Node3D
## Foot IK on the procedural terrain, graded the same way for any IK. Run (after `--`):
##   --seed=N  (default 1337)   --v2  (install Foot IK v2 instead of the game's v1)   --off  (no IK)
##   --walk  (also walk straight uphill / downhill / across at every spot)
## It stands the player still on spots of growing steepness (and optionally walks), and prints per
## spot how far each ankle is from where a planted foot would be: how much it floats (+) or sinks
## into (-) the ground, measured along the ground's own normal in the final pose. Ends with
## WORLD_IK_CHECK PASS / FAIL.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const INSTALL := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const SETTLE_FRAMES := 50
const GRADE_FRAMES := 20
const WALK_FRAMES := 70
## Slope bands (TerrainNoise.slope, 0 flat .. 1 vertical) and how many spots to try in each.
const BANDS := [Vector2(0.0, 0.08), Vector2(0.15, 0.3), Vector2(0.3, 0.5), Vector2(0.5, 0.62)]
const SPOTS_PER_BAND := 3
## An ankle further than this from its planted height (cm) is a float / a sink.
const LIMIT := 0.08

var world: ProceduralWorld
var player: Player
var _seed := 1337
var _use_v2 := false
var _off := false
var _walk := false
var _nominal := 0.0
var _foot_samples: Array[Dictionary] = []
var _worst_over_all := 0.0
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
	var args := OS.get_cmdline_user_args()
	_use_v2 = "--v2" in args
	_off = "--off" in args
	_walk = "--walk" in args
	world = ProceduralWorld.new()
	world.settings = WorldSettings.new()
	world.settings.world_seed = _seed
	world.realism = 1.0
	add_child(world)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	world.set_target(player)
	world.generator.chunks_per_frame = 8
	INSTALL.install(player.body, player.skeleton).enabled = _use_v2 and not _off
	player.skeleton.skeleton_updated.connect(_sample_feet)
	_run.call_deferred()


func _run() -> void:
	var label := "v2" if _use_v2 else ("off" if _off else "v1")
	print("WORLD_IK_CHECK seed %d ik=%s" % [_seed, label])
	await _stand_at(Vector2(2.0, 2.0), 0.0, false)
	_nominal = _median_error(0.0)
	print("  flat spawn: planted ankle %.3f m above the ground" % _nominal)
	for band: Vector2 in BANDS:
		for spot in _find_spots(band, SPOTS_PER_BAND):
			var downhill := _downhill_yaw(spot)
			await _stand_at(spot, downhill, false)
			_report("idle  slope %.2f facing downhill" % world.generator.noise.slope(spot.x, spot.y))
			await _stand_at(spot, downhill + PI * 0.5, false)
			_report("idle  slope %.2f across" % world.generator.noise.slope(spot.x, spot.y))
			if _walk:
				for walk_yaw in [downhill, downhill + PI, downhill + PI * 0.5]:
					await _stand_at(spot, walk_yaw, true)
					_report("walk  slope %.2f yaw %+4.0f" % [
							world.generator.noise.slope(spot.x, spot.y), rad_to_deg(walk_yaw - downhill)])
	print("WORLD_IK_CHECK %s worst %.1f cm, %d of the graded runs over %.0f cm" % [
			"PASS" if _failures == 0 else "FAIL", _worst_over_all * 100.0, _failures, LIMIT * 100.0])
	get_tree().quit(0 if _failures == 0 else 1)


## The slope spots of a band: scattered land points (>5 m above the sea) on a 70 m grid.
func _find_spots(band: Vector2, count: int) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var noise := world.generator.noise
	for ring in range(60, 1400, 70):
		for index in 12:
			var at := Vector2.from_angle(TAU * float(index) / 12.0 + float(ring) * 0.37) * float(ring)
			var ground := noise.height(at.x, at.y)
			if ground < world.settings.sea_level + 5.0:
				continue
			var steep := noise.slope(at.x, at.y)
			if steep >= band.x and steep < band.y:
				spots.append(at)
				if spots.size() >= count:
					return spots
	return spots


func _downhill_yaw(at: Vector2) -> float:
	var noise := world.generator.noise
	var dx := noise.height(at.x + 1.0, at.y) - noise.height(at.x - 1.0, at.y)
	var dz := noise.height(at.x, at.y + 1.0) - noise.height(at.x, at.y - 1.0)
	var downhill := Vector2(-dx, -dz)
	return atan2(-downhill.x, -downhill.y) # Godot's forward is -Z


## Puts the player on the spot facing `yaw`, lets it settle, then records `GRADE_FRAMES` of both
## feet (idle), or walks forward for `WALK_FRAMES` and records those.
func _stand_at(at: Vector2, yaw: float, walking: bool) -> void:
	var ground := world.generator.noise.height(at.x, at.y)
	var spot := Vector3(at.x, ground + 0.4, at.y)
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	world.build_around(spot)
	_foot_samples.clear()
	for frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	_foot_samples.clear()
	if walking:
		Input.action_press(&"move_forward", 1.0)
		for frame in WALK_FRAMES:
			await get_tree().physics_frame
		Input.action_release(&"move_forward")
	else:
		for frame in GRADE_FRAMES:
			await get_tree().physics_frame


## Every skeleton update (after all modifiers): both ankles against the real ground under them (a
## ray at the physics terrain, the surface the feet actually meet, not the smooth height formula).
func _sample_feet() -> void:
	var space := get_world_3d().direct_space_state
	for bone_name: StringName in [&"LeftFoot", &"RightFoot"]:
		var bone := player.skeleton.find_bone(bone_name)
		var pose := player.skeleton.get_bone_global_pose(bone)
		var ankle := (player.skeleton.global_transform * pose).origin
		var query := PhysicsRayQueryParameters3D.create(ankle + Vector3.UP * 1.0,
				ankle + Vector3.DOWN * 3.0, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var along := (ankle - (hit["position"] as Vector3)).dot(hit["normal"] as Vector3)
		_foot_samples.append({"foot": bone_name, "along": along})


func _errors(subtract: float) -> Array[float]:
	var errors: Array[float] = []
	for sample in _foot_samples:
		errors.append(float(sample["along"]) - subtract)
	return errors


func _median_error(subtract: float) -> float:
	var errors := _errors(subtract)
	errors.sort()
	return errors[errors.size() / 2] if not errors.is_empty() else 0.0


## Prints the worst float and sink of the recorded frames (against the flat-ground nominal).
func _report(title: String) -> void:
	var worst_float := 0.0
	var worst_sink := 0.0
	for error in _errors(_nominal):
		worst_float = maxf(worst_float, error)
		worst_sink = minf(worst_sink, error)
	var bad := worst_float > LIMIT or -worst_sink > LIMIT
	_worst_over_all = maxf(_worst_over_all, maxf(worst_float, -worst_sink))
	if bad:
		_failures += 1
	print("  %s  %-34s float %+5.1f cm  sink %+5.1f cm  (%d samples)" % [
			"FAIL" if bad else "ok  ", title, worst_float * 100.0, worst_sink * 100.0,
			_foot_samples.size()])
