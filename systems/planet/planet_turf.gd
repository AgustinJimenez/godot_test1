class_name PlanetTurf
extends Node
## The short grass that covers the ground where grass grows: thousands of small tufts round the walker. A tile cannot hold them all
## (a hundred metres of ground at a few tufts a square metre is hundreds of thousands), so the tufts are made in chunks of the
## tile's ground, only the chunks within ENTER metres of the walker, and let go again beyond LEAVE. Where they grow comes from the
## tile's "turf" (how well turf grows at each vertex of its grid: rain, warmth, slope, stones, shade; the native placement makes
## it); each chunk is one MultiMesh (PlanetScatterNative.turf_chunk) of one tuft mesh, drawn by the plant shader.
## Off with `PLANET_NO_TURF`.

const CHUNK := 16.0 ## m: the square of a tile's ground made at a time
const ENTER := 26.0 ## m: chunks whose middle is closer than this are made
const LEAVE := 36.0 ## m: and let go beyond this
const SPACING := 0.36 ## m: one tuft for each spot of a jittered grid of this
const DENSITY := 1.6 ## the odds of a tuft are the field times this (the field is 1 only where grass grows best)
const DRAWN := 32.0 ## m: how far a tuft is drawn (it fades out)
const LOOK_EVERY := 0.3 ## s
const MAKE_EACH_LOOK := 3 ## chunks made at most in each look: the walker is never held up

var planet: PlanetWorld
var player: Player

var _chunks: Dictionary = {} # key -> {node, holder, middle (the chunk's middle in the holder's space)}
var _since := 0.0


func _physics_process(delta: float) -> void:
	if player == null or planet == null or planet.noise.scatter_native == null:
		return
	_since += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	var here := player.global_position
	_let_go(here)
	var made := 0
	for tile: PlanetTile in planet.surface.tiles.values():
		var holder := tile.plant_holder
		if holder == null or not holder.has_meta(&"turf"):
			continue
		var grid: Dictionary = holder.get_meta(&"turf")
		var local := _grid_of(grid, holder.to_local(here)) # (the grid's own space: metres from its corner along its x and z)
		var size: float = grid["size"]
		if local.x < -ENTER or local.z < -ENTER or local.x > size + ENTER or local.z > size + ENTER:
			continue
		var from_x := maxi(int(floorf((local.x - ENTER) / CHUNK)), 0)
		var to_x := mini(int(floorf((local.x + ENTER) / CHUNK)), int(ceilf(size / CHUNK)) - 1)
		var from_z := maxi(int(floorf((local.z - ENTER) / CHUNK)), 0)
		var to_z := mini(int(floorf((local.z + ENTER) / CHUNK)), int(ceilf(size / CHUNK)) - 1)
		for iz in range(from_z, to_z + 1):
			for ix in range(from_x, to_x + 1):
				var key := holder.get_instance_id() * 10000 + ix * 100 + iz
				if _chunks.has(key):
					continue
				var middle := Vector2((ix + 0.5) * CHUNK, (iz + 0.5) * CHUNK)
				if middle.distance_to(Vector2(local.x, local.z)) > ENTER + CHUNK * 0.4:
					continue
				if made >= MAKE_EACH_LOOK:
					return
				made += 1
				_make(key, holder, grid, ix, iz)


## Make the chunk (ix, iz) of the tile whose grid is `grid`, hanging in `holder`.
func _make(key: int, holder: Node3D, grid: Dictionary, ix: int, iz: int) -> void:
	var size: float = grid["size"]
	var buffers: Array = planet.noise.scatter_native.call(&"turf_chunk", grid["positions"], grid["field"],
			grid["cells"], size, ix * CHUNK, iz * CHUNK, minf((ix + 1) * CHUNK, size), minf((iz + 1) * CHUNK, size), SPACING,
			DENSITY, key ^ int(grid["key"]), FloraMeshes.TURF_VARIANTS)
	var entry := {"nodes": [], "holder": holder, "grid": grid, "at": Vector2((ix + 0.5) * CHUNK, (iz + 0.5) * CHUNK), "buffers": []}
	for variant in buffers.size():
		var buffer: PackedFloat32Array = buffers[variant]
		if buffer.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = FloraMeshes.turf_tuft(variant)
		multi.instance_count = buffer.size() / 16
		multi.buffer = buffer
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.material_override = FloraMeshes.material()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = DRAWN
		instance.visibility_range_end_margin = 6.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(instance)
		entry["nodes"].append(instance)
		entry["buffers"].append(buffer)
	_chunks[key] = entry


## Chunks the walker has left (or whose tile has gone) are let go.
func _let_go(here: Vector3) -> void:
	for key: int in _chunks.keys():
		var entry: Dictionary = _chunks[key]
		var holder: Node3D = entry["holder"]
		var gone := not is_instance_valid(holder) or not holder.is_inside_tree()
		if not gone:
			var local := _grid_of(entry["grid"], holder.to_local(here))
			gone = Vector2(local.x, local.z).distance_to(entry["at"]) > LEAVE + CHUNK * 0.4
		if gone:
			for node: Node in entry["nodes"]:
				if is_instance_valid(node):
					node.queue_free()
			_chunks.erase(key)


## A point of the holder's space in the grid's: x and z in metres from the grid's corner along the grid's own axes (y: unchanged).
static func _grid_of(grid: Dictionary, local: Vector3) -> Vector3:
	var corner: Vector3 = grid["corner"]
	var ax: Vector2 = grid["ax"]
	var az: Vector2 = grid["az"]
	var d := Vector2(local.x - corner.x, local.z - corner.z)
	var det := ax.x * az.y - ax.y * az.x
	if absf(det) < 0.0001:
		return Vector3(d.x, local.y, d.y)
	return Vector3((d.x * az.y - d.y * az.x) / det, local.y, (ax.x * d.y - ax.y * d.x) / det)


## The chunks as [holder, [MultiMeshInstance3D, buffer, true]] (the same as the plants' `sway_sets`): PlanetSway takes the tufts
## nearest the walker out of them and bends them.
func chunk_sets() -> Array:
	var sets: Array = []
	for entry: Dictionary in _chunks.values():
		if is_instance_valid(entry["holder"]):
			for at in entry["nodes"].size():
				if is_instance_valid(entry["nodes"][at]):
					sets.append([entry["holder"], [entry["nodes"][at], entry["buffers"][at], PlanetSway.TURF]])
	return sets


## How many tufts are drawn now (for the checks).
func tuft_count() -> int:
	var total := 0
	for entry: Dictionary in _chunks.values():
		for node: MultiMeshInstance3D in entry["nodes"]:
			if is_instance_valid(node):
				total += node.multimesh.instance_count
	return total
