class_name PlanetShells
extends Node
## The loose stones of the near ground as relief: round the walker the ground tiles get LAYERS extra
## copies of their mesh (planet_shells
## shader), each lifted a little further and drawn only where a stone reaches that high. On only
## with `PLANET_SHELLS` (tried: about 1.5 ms and little to see at standing height).

const SHADER := preload("res://shaders/world/planet_shells.gdshader")
const LAYERS := 8
const TOP := 0.06 ## m: the tallest stone
const REACH := 7.0 ## m
const LOOK_EVERY := 0.4 ## s

var planet: PlanetWorld
var player: Player

var _tiles: Dictionary = {} # PlanetTile -> Array of the MeshInstance3D layers
var _materials: Array[ShaderMaterial] = []
var _since := 0.0


func _ready() -> void:
	for layer in LAYERS:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"level", float(layer + 1) / float(LAYERS))
		material.set_shader_parameter(&"top", TOP)
		material.set_shader_parameter(&"reach", REACH)
		_materials.append(material)


func _physics_process(delta: float) -> void:
	if player == null or planet == null:
		return
	_since += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	var here := player.global_position
	for tile: PlanetTile in _tiles.keys():
		if not is_instance_valid(tile) or not tile.is_inside_tree() or _gap(tile, here) > REACH * 1.6:
			_drop(tile)
	for tile: PlanetTile in planet.surface.tiles.values():
		if _tiles.has(tile) or not tile.has_collider or tile.ground_instance == null:
			continue
		if _gap(tile, here) < REACH * 1.2:
			_raise(tile)


## How far `here` is from the tile's ground (0 over it).
func _gap(tile: PlanetTile, here: Vector3) -> float:
	var local := tile.to_local(here)
	var half := tile.size * 0.5
	return Vector2(maxf(absf(local.x) - half, 0.0), maxf(absf(local.z) - half, 0.0)).length()


func _raise(tile: PlanetTile) -> void:
	var layers: Array = []
	for material in _materials:
		var copy := MeshInstance3D.new()
		copy.mesh = tile.ground_instance.mesh
		copy.material_override = material
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.add_child(copy)
		layers.append(copy)
	_tiles[tile] = layers


func _drop(tile: PlanetTile) -> void:
	if is_instance_valid(tile):
		for copy: MeshInstance3D in _tiles[tile]:
			if is_instance_valid(copy):
				copy.queue_free()
	_tiles.erase(tile)
