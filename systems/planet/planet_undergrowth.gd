class_name PlanetUndergrowth
extends Node
## Pushing through plants: the shrubs, ferns and grass round the walker bend away from them (the plant shader reads where the
## walker is: `pusher_a`, a position and a reach) and hold them back (the more and the thicker the undergrowth, the slower the
## walk). Trunks and thick low limbs are solid (colliders); this is the soft part. The drag comes from the stems each tile's
## native placement kept (PlanetScatterNative.drag) and is felt as the same kind of slowing as wading (WorldSwim).

const REACH := 1.5 ## m: how far from the walker the plants bend
const MAX_SLOW := 0.55 ## the most a thicket takes off the walking speed
const LOOK_EVERY := 0.1 ## s between looks at the stems round the walker

var planet: PlanetWorld
var player: Player

var _drag := 0.0
var _slow := 1.0
var _since := 0.0


func _ready() -> void:
	process_physics_priority = 100 # after the player has made its velocity for the frame, like WorldSwim


func _physics_process(delta: float) -> void:
	if player == null or planet == null:
		return
	var here := player.global_position
	RenderingServer.global_shader_parameter_set(&"pusher_a", Vector4(here.x, here.y, here.z, REACH))
	_since += delta
	if _since >= LOOK_EVERY:
		_since = 0.0
		_drag = _drag_at(here)
		if OS.has_environment("PLANET_TIMING") and _drag > 0.0:
			print("PLANET_TIMING undergrowth drag %.2f -> speed x%.2f" % [_drag, 1.0 - MAX_SLOW * _drag])
	var wanted := 1.0 - MAX_SLOW * _drag if player.is_on_floor() and not player.free_mode_enabled else 1.0
	_slow = move_toward(_slow, wanted, delta * 3.0) # (it eases in and out: no jerk at the edge of a bush)
	player.velocity.x *= _slow
	player.velocity.z *= _slow


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"pusher_a", Vector4(0.0, -1000.0, 0.0, 0.0))


## The undergrowth round `world_position`: 0 in the open .. 1 in a thicket (the worst of the tiles it is over).
func _drag_at(world_position: Vector3) -> float:
	var native: Object = planet.noise.scatter_native
	if native == null:
		return 0.0
	var worst := 0.0
	for tile: PlanetTile in planet.surface.tiles.values():
		if tile.plant_holder == null or not tile.plant_holder.has_meta(&"stems"):
			continue
		if tile.global_position.distance_to(world_position) > tile.size * 0.75:
			continue
		var local := tile.to_local(world_position)
		var stems: PackedFloat32Array = tile.plant_holder.get_meta(&"stems")
		worst = maxf(worst, float(native.call(&"drag", stems, local.x, local.z)))
	return worst
