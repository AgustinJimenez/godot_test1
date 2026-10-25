class_name PlanetTurf
extends Node
## The short grass that covers the ground where grass grows: thousands of small tufts round the
## walker. A tile cannot hold them all
## (a hundred metres of ground at a few tufts a square metre is hundreds of thousands), so the tufts
## are made in chunks of the
## tile's ground, only the chunks within ENTER metres of the walker, and let go again beyond LEAVE.
## Where they grow comes from the
## tile's "turf" (how well turf grows at each vertex of its grid: rain, warmth, slope, stones,
## shade; the native placement makes
## it); each chunk is one MultiMesh (PlanetScatterNative.turf_chunk) of one tuft mesh, drawn by the
## plant shader.
## Off with `PLANET_NO_TURF`.

const CHUNK := 16.0 ## m: the square of a tile's ground made at a time
const ENTER := 26.0 ## m: chunks whose middle is closer than this are made
const LEAVE := 36.0 ## m: and let go beyond this
## m: one tuft for each spot of a jittered grid of this (PLANET_TURF_SPACING: another, to try)
const SPACING := 0.21
## the odds of a tuft are the field times this (the field is 1 only where grass grows best)
const DENSITY := 1.6
const DRAWN := 32.0 ## m: how far a tuft is drawn (it fades out)
## the grass seen from afar follows the camera, not a ring round the walker: inside the cone of the view (FAR_COS) chunks are made out to
## FAR_ENTER and drawn out to FAR_DRAWN, thinner (FAR_THIN times the spacing: a tuft is small there); they are let go beyond FAR_LEAVE, or beyond
## LEAVE once they fall out of the wider cone LEAVE_COS
const FAR_ENTER := 62.0
const FAR_LEAVE := 78.0
const FAR_DRAWN := 68.0
const FAR_THIN := 2.0
const FAR_COS := 0.62 ## about 50 degrees either side of where the camera looks
const LEAVE_COS := 0.1 ## about 84 degrees
## m: one stone for each spot of a jittered grid of this (the odds make them thin where grass grows)
const GRAVEL_SPACING := 0.12
const GRAVEL_DRAWN := 14.0 ## m: how far a stone is drawn (its size is under a pixel beyond)
const LOOK_EVERY := 0.3 ## s
const MAKE_EACH_LOOK := 3 ## chunks made at most in each look: the walker is never held up
const NEAR := 12.0 ## m: chunks this close are made at once, whatever the budget
const VIEW_COS := 0.35 ## a chunk within about 70 degrees of where the camera looks counts as in view
const VIEW_BONUS := 30.0 ## m: how much sooner an in-view chunk is made than one out of view

var planet: PlanetWorld
var player: Player
## true: the small stones of the bare ground instead of grass (see
## PlanetScatterNative.gravel_chunk): a node of its own, nearer, finer, with shadows
var gravel := false

# key -> {node, holder, middle (the chunk's middle in the holder's space)}
var _chunks: Dictionary = {}
var _since := 0.0


func _enter() -> float:
	return GRAVEL_DRAWN + 4.0 if gravel else ENTER


func _leave() -> float:
	return GRAVEL_DRAWN + 12.0 if gravel else LEAVE


## The farthest a chunk of grass is made, in the view (the stones: no farther than ever).
func _far() -> float:
	return _enter() if gravel else FAR_ENTER


func _physics_process(delta: float) -> void:
	if player == null or planet == null or planet.noise.scatter_native == null:
		return
	_since += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	var here := player.global_position
	var camera := get_viewport().get_camera_3d()
	var way := Vector3.ZERO # where the camera looks, flat (the chunks it sees are made first)
	if camera != null:
		way = -camera.global_transform.basis.z
		way.y = 0.0
		way = way.normalized()
	_let_go(here, way)
	# every chunk wanted and not yet made, nearest and most in view first: a walker never waits for the
	# patch in front of them while chunks behind (or off to the side) are made in the order of the grid
	var wanted: Array = []
	for tile: PlanetTile in planet.surface.tiles.values():
		var holder := tile.plant_holder
		if holder == null or not holder.has_meta(&"turf"):
			continue
		var grid: Dictionary = holder.get_meta(&"turf")
		# (the grid's own space: metres from its corner along its x and z)
		var local := _grid_of(grid, holder.to_local(here))
		var size: float = grid["size"]
		var reach := _far() if way != Vector3.ZERO else _enter() # (the farthest a chunk may be made, in the view)
		if local.x < -reach or local.z < -reach or local.x > size + reach or local.z > size + reach:
			continue
		var from_x := maxi(int(floorf((local.x - reach) / CHUNK)), 0)
		var to_x := mini(int(floorf((local.x + reach) / CHUNK)), int(ceilf(size / CHUNK)) - 1)
		var from_z := maxi(int(floorf((local.z - reach) / CHUNK)), 0)
		var to_z := mini(int(floorf((local.z + reach) / CHUNK)), int(ceilf(size / CHUNK)) - 1)
		var ahead := Vector2.ZERO # the camera's way in this grid's axes
		if way != Vector3.ZERO:
			var moved := _grid_of(grid, holder.to_local(here + way))
			ahead = Vector2(moved.x - local.x, moved.z - local.z).normalized()
		for iz in range(from_z, to_z + 1):
			for ix in range(from_x, to_x + 1):
				var key := holder.get_instance_id() * 10000 + ix * 100 + iz
				var middle := Vector2((ix + 0.5) * CHUNK, (iz + 0.5) * CHUNK)
				var offset := middle - Vector2(local.x, local.z)
				var distance := offset.length()
				if _chunks.has(key):
					# (a thin chunk made for the view that the walker has come up to is made again, in full)
					if distance > _enter() or not bool((_chunks[key] as Dictionary).get("far", false)):
						continue
					_drop(key)
				var facing := 1.0 if ahead == Vector2.ZERO else offset.normalized().dot(ahead)
				var far := distance > _enter() + CHUNK * 0.4
				if far and (distance > reach + CHUNK * 0.4 or ahead == Vector2.ZERO or facing < FAR_COS):
					continue
				var seen := distance < CHUNK or (ahead != Vector2.ZERO and facing > VIEW_COS)
				wanted.append([distance - (VIEW_BONUS if seen else 0.0), distance, key, holder, grid, ix, iz,
						distance > _enter() + CHUNK * 0.4])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var made := 0
	for item: Array in wanted:
		# (the chunks round the walker's feet are never held back; the rest are made a few at a look)
		if made >= MAKE_EACH_LOOK and float(item[1]) > NEAR:
			break
		made += 1
		_make(item[2], item[3], item[4], item[5], item[6], item[7])


## Make the chunk (ix, iz) of the tile whose grid is `grid`, hanging in `holder`.
## `far`: a chunk beyond the walker's ring, seen from afar (thinner, drawn farther).
func _make(key: int, holder: Node3D, grid: Dictionary, ix: int, iz: int, far := false) -> void:
	var size: float = grid["size"]
	var buffers: Array
	var native := planet.noise.scatter_native
	if gravel: # (none where the crust says there are no stones: a dune, a clean region)
		buffers = native.call(&"gravel_chunk", grid["positions"], grid["field"], grid["cells"], size,
				ix * CHUNK, iz * CHUNK, minf((ix + 1) * CHUNK, size), minf((iz + 1) * CHUNK, size),
				GRAVEL_SPACING, 1.0, key ^ int(grid["key"]), FloraMeshes.CHIP_VARIANTS,
				grid.get("stones", PackedFloat32Array()))
	else:
		buffers = native.call(&"turf_chunk", grid["positions"], grid["field"], grid["cells"], size,
				ix * CHUNK, iz * CHUNK, minf((ix + 1) * CHUNK, size), minf((iz + 1) * CHUNK, size),
				_spacing() * (FAR_THIN if far else 1.0), DENSITY, key ^ int(grid["key"]), FloraMeshes.TURF_VARIANTS)
	far = far and not gravel
	var entry := {"far": far, "nodes": [], "holder": holder, "grid": grid, "at": Vector2((ix + 0.5) * CHUNK,
			(iz + 0.5) * CHUNK), "buffers": [], "shadows": []}
	for variant in buffers.size():
		var buffer: PackedFloat32Array = buffers[variant]
		if buffer.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = FloraMeshes.chip(variant) if gravel else FloraMeshes.turf_tuft(variant)
		multi.instance_count = buffer.size() / 16
		multi.buffer = buffer
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.material_override = FloraMeshes.chip_material() if gravel else FloraMeshes.material()
		instance.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if gravel
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		instance.visibility_range_end = GRAVEL_DRAWN if gravel else (FAR_DRAWN if far else DRAWN)
		instance.visibility_range_end_margin = 6.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(instance)
		entry["nodes"].append(instance)
		entry["buffers"].append(buffer)
		if gravel:
			var patch := FloraMeshes.chip_shadow(buffer)
			patch.visibility_range_end = GRAVEL_DRAWN
			patch.visibility_range_end_margin = 6.0
			patch.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(patch)
			entry["shadows"].append(patch)
	_chunks[key] = entry


## Chunks the walker has left (or whose tile has gone) are let go.
func _let_go(here: Vector3, way: Vector3) -> void:
	for key: int in _chunks.keys():
		var entry: Dictionary = _chunks[key]
		var holder_value: Variant = entry["holder"] # (a tile that has gone is a freed object)
		var gone := not is_instance_valid(holder_value)
		gone = gone or not (holder_value as Node3D).is_inside_tree()
		if not gone:
			var holder: Node3D = holder_value
			var local := _grid_of(entry["grid"], holder.to_local(here))
			var offset: Vector2 = (entry["at"] as Vector2) - Vector2(local.x, local.z)
			if bool(entry.get("far", false)) and way != Vector3.ZERO:
				# (a chunk made for the view stays while it is in the wide cone of it, or close)
				var moved := _grid_of(entry["grid"], holder.to_local(here + way))
				var ahead := Vector2(moved.x - local.x, moved.z - local.z).normalized()
				var in_view := offset.normalized().dot(ahead) > LEAVE_COS
				gone = offset.length() > FAR_LEAVE + CHUNK * 0.4 or (not in_view and offset.length() > _leave() + CHUNK * 0.4)
			else:
				gone = offset.length() > _leave() + CHUNK * 0.4
		if gone:
			_drop(key)


## Let the chunk go: its nodes are freed.
func _drop(key: int) -> void:
	var entry: Dictionary = _chunks[key]
	for node in entry["nodes"] + entry["shadows"]: # (untyped: a freed node would be an error)
		if is_instance_valid(node):
			node.queue_free()
	_chunks.erase(key)


## A point of the holder's space in the grid's: x and z in metres from the grid's corner along the
## grid's own axes (y: unchanged).
static func _grid_of(grid: Dictionary, local: Vector3) -> Vector3:
	var corner: Vector3 = grid["corner"]
	var ax: Vector2 = grid["ax"]
	var az: Vector2 = grid["az"]
	var d := Vector2(local.x - corner.x, local.z - corner.z)
	var det := ax.x * az.y - ax.y * az.x
	if absf(det) < 0.0001:
		return Vector3(d.x, local.y, d.y)
	return Vector3((d.x * az.y - d.y * az.x) / det, local.y, (ax.x * d.y - ax.y * d.x) / det)


## The chunks as [holder, [MultiMeshInstance3D, buffer, true]] (the same as the plants'
## `sway_sets`): PlanetSway takes the tufts
## nearest the walker out of them and bends them.
func chunk_sets() -> Array:
	var sets: Array = []
	for entry: Dictionary in _chunks.values():
		if is_instance_valid(entry["holder"]):
			for at in entry["nodes"].size():
				if is_instance_valid(entry["nodes"][at]):
					sets.append([entry["holder"], [entry["nodes"][at], entry["buffers"][at], PlanetSway.TURF]])
	return sets


static func _spacing() -> float:
	return (OS.get_environment("PLANET_TURF_SPACING").to_float()
			if OS.has_environment("PLANET_TURF_SPACING") else SPACING)


## How many tufts are drawn now (for the checks).
func tuft_count() -> int:
	var total := 0
	for entry: Dictionary in _chunks.values():
		for node in entry["nodes"]: # (untyped: a freed node is skipped below)
			if is_instance_valid(node):
				total += (node as MultiMeshInstance3D).multimesh.instance_count
	return total


## How many chunks are the thin ones made for the view (for the checks).
func far_count() -> int:
	var total := 0
	for entry: Dictionary in _chunks.values():
		if bool(entry.get("far", false)):
			total += 1
	return total
