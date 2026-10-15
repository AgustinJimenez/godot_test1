class_name WaterCalmMap
extends RefCounted
## How much of the sea's waves the water here should get, as a small map around the player: wide,
## deep sea rolls fully (1), a pond in a basin or a shallow bay stays nearly flat. It is worked out
## from the ground: how much of the area around a spot lies well under the sea, blurred. The map
## is rebuilt on a worker thread when the player has wandered off its middle; its texels stay on a
## fixed world grid, so a rebuilt map agrees with the old one where they overlap and nothing pops.

const CELL := 10.0 ## m, one texel
const CELLS := 96 ## texels each way (960 m, a little more than the fine water plane)
const REFRESH := 120.0 ## m the player may drift from the map's middle before it is rebuilt
const SNAP := 40.0 ## m, the middle snaps to this grid
const DEEP := 5.0 ## m under the sea at which a texel counts as open water
const BLUR := 5 ## texels: how far around a spot the water has to reach to count as open
const CALM_MIN := 0.2 ## the least a basin or shallow bay rolls

var terrain: TerrainNoise ## without it every water rolls fully
var sea_level := 0.0

var _material: ShaderMaterial
var _middle := Vector2(INF, INF)
var _task := -1
var _result := PackedByteArray()
var _result_middle := Vector2.ZERO
var _stale := false
var _has_map := false


func _init(material: ShaderMaterial) -> void:
	_material = material


## Throws the map away (the world was rebuilt, e.g. with a new seed).
func invalidate() -> void:
	_middle = Vector2(INF, INF)
	_stale = _task >= 0 # a build still running is for the old world
	_has_map = false
	_material.set_shader_parameter(&"roll_area", Vector3.ZERO)


## Call every frame with the player's position (x, z).
func update(at: Vector2) -> void:
	if terrain == null:
		return
	if _task >= 0:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			if not _stale:
				_apply(_result, _result_middle)
			_stale = false
		return
	if _middle.distance_to(at) < REFRESH:
		return
	var middle := at.snapped(Vector2.ONE * SNAP)
	_middle = middle
	if _has_map:
		_task = WorkerThreadPool.add_task(_build.bind(middle, terrain))
	else:
		_apply(_cells(middle, terrain), middle) # the first map is ready before the first frame


func _build(middle: Vector2, ground: TerrainNoise) -> void:
	_result = _cells(middle, ground)
	_result_middle = middle


func _apply(cells: PackedByteArray, middle: Vector2) -> void:
	_has_map = true
	var image := Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_R8, cells)
	var half := float(CELLS) * CELL * 0.5
	_material.set_shader_parameter(&"roll_map", ImageTexture.create_from_image(image))
	_material.set_shader_parameter(&"roll_area",
			Vector3(middle.x - half, middle.y - half, float(CELLS) * CELL))


## One byte per texel (row by row): how much the water there rolls, 0..255.
func _cells(middle: Vector2, ground: TerrainNoise) -> PackedByteArray:
	var corner := middle - Vector2.ONE * float(CELLS) * CELL * 0.5
	var open := PackedFloat32Array()
	open.resize(CELLS * CELLS)
	for row in CELLS:
		for column in CELLS:
			var depth := sea_level - ground.base_height(corner.x + (float(column) + 0.5) * CELL,
					corner.y + (float(row) + 0.5) * CELL)
			open[row * CELLS + column] = clampf(depth / DEEP, 0.0, 1.0)
	var across := _blur(open, true)
	var blurred := _blur(across, false)
	var bytes := PackedByteArray()
	bytes.resize(CELLS * CELLS)
	for index in CELLS * CELLS:
		bytes[index] = int(255.0 * lerpf(CALM_MIN, 1.0, smoothstep(0.3, 0.75, blurred[index])))
	return bytes


## A box blur of `BLUR` texels along one axis (edges repeat their last texel).
func _blur(source: PackedFloat32Array, along_row: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(CELLS * CELLS)
	var width := float(BLUR * 2 + 1)
	for line in CELLS:
		var total := 0.0
		for offset in range(-BLUR, BLUR + 1):
			total += source[_at(line, clampi(offset, 0, CELLS - 1), along_row)]
		for index in CELLS:
			out[_at(line, index, along_row)] = total / width
			var leaving := clampi(index - BLUR, 0, CELLS - 1)
			var entering := clampi(index + BLUR + 1, 0, CELLS - 1)
			total += source[_at(line, entering, along_row)] - source[_at(line, leaving, along_row)]
	return out


func _at(line: int, index: int, along_row: bool) -> int:
	return line * CELLS + index if along_row else index * CELLS + line
