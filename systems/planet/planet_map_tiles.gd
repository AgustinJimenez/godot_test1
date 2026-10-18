class_name PlanetMapTiles
extends RefCounted
## The map's close views as tiles, like a web map's: the map is cut into squares of TILE pixels at
## levels of detail (level L is 2^(L+1) tiles across and 2^L down, each covering the same angle
## both ways), each tile is charted once, kept (the last MAX_TILES), and a view is drawn from the
## tiles it needs: the ones missing are charted nearest the centre first, one after another, so
## the first sharp pieces show within a tenth of a second, panning and zooming back reuse what was
## charted, and a tile not there yet shows its finest charted ancestor (blurrier) meanwhile.

const TILE := 256 ## pixels a side
const MAX_TILES := 360
const MAX_LEVEL := 14
const DENSITY := 0.85 ## tile pixels per screen pixel (a little under one is sharp enough)

var layer := PlanetChart.Layer.TERRAIN
var clock: PlanetClock ## the moment the moving layers (temperature, clouds) show

var _noise: PlanetNoise
var _textures := {} ## Vector4i(layer, level, x, y) -> ImageTexture
var _order: Array[Vector4i] = [] ## the keys, the least recently used first
var _wanted: Array[Vector4i] = [] ## what the view needs and is missing, nearest the centre first
var _chart: PlanetChart
var _chart_key := Vector4i()
var _chart_ms := 0
var finished_tiles := 0 ## how many were charted this session (for the log)


func _init(noise: PlanetNoise) -> void:
	_noise = noise


## The level whose tiles are about a screen pixel each, for a map `screen_width` pixels across
## (between two thirds and one and a third chart pixels for a screen pixel).
static func level_for(screen_width: float) -> int:
	var tiles_across := screen_width * DENSITY / float(TILE)
	var steps := log(maxf(tiles_across / 2.0, 1.0)) / log(2.0)
	return clampi(ceili(steps - 0.4), 0, MAX_LEVEL)


## The part of the map (fractions) a tile covers.
static func rect_of(level: int, x: int, y: int) -> Rect2:
	var width := 1.0 / float(2 << level)
	var height := 1.0 / float(1 << level)
	return Rect2(float(x) * width, float(y) * height, width, height)


## The tiles of `level` that the view (fractions, x may run past 0 and 1) touches, as (x, y).
static func tiles_of(view: Rect2, level: int) -> Array[Vector2i]:
	var across := 2 << level
	var down := 1 << level
	var first_x := floori(view.position.x * float(across))
	var last_x := floori(view.end.x * float(across) - 0.0001)
	var first_y := maxi(floori(view.position.y * float(down)), 0)
	var last_y := mini(floori(view.end.y * float(down) - 0.0001), down - 1)
	var out: Array[Vector2i] = []
	for y in range(first_y, last_y + 1):
		for x in range(first_x, last_x + 1):
			out.append(Vector2i(posmod(x, across), y))
	return out


func _key(level: int, x: int, y: int) -> Vector4i:
	return Vector4i(int(layer), level, x, y)


## True when every tile the view needs is charted.
func covers(view: Rect2, level: int) -> bool:
	for tile in tiles_of(view, level):
		if not _textures.has(_key(level, tile.x, tile.y)):
			return false
	return true


## How many of the tiles the view needs are charted, and how many it needs.
func share(view: Rect2, level: int) -> Vector2i:
	var have := 0
	var all := tiles_of(view, level)
	for tile in all:
		if _textures.has(_key(level, tile.x, tile.y)):
			have += 1
	return Vector2i(have, all.size())


## Asks for the tiles of the view (the missing ones, the centre first). Called every frame it
## changes; what was asked before and is not needed any more is dropped.
func ask(view: Rect2, level: int) -> void:
	var centre := view.get_center()
	var missing: Array[Vector4i] = []
	for tile in tiles_of(view, level):
		var key := _key(level, tile.x, tile.y)
		if _textures.has(key):
			_use(key)
		else:
			missing.append(key)
	missing.sort_custom(func(a: Vector4i, b: Vector4i) -> bool:
		return _distance(a, centre) < _distance(b, centre))
	_wanted = missing
	if _chart != null and not _wanted.has(_chart_key):
		PlanetMapLog.line("tile %s given up: the view left it" % _name(_chart_key))
		_chart.cancel()
		_retired.append(_chart)
		_chart = null


var _retired: Array[PlanetChart] = []


func _distance(key: Vector4i, centre: Vector2) -> float:
	var rect := rect_of(key.y, key.z, key.w)
	var d := rect.get_center() - centre
	d.x = absf(d.x)
	d.x = minf(d.x, 1.0 - d.x) # (the map wraps)
	return d.length()


func _name(key: Vector4i) -> String:
	return "L%d (%d, %d)" % [key.y, key.z, key.w]


func _use(key: Vector4i) -> void:
	_order.erase(key)
	_order.append(key)


## One step: finishes the chart in hand and starts the next tile (true when a tile was added).
func step() -> bool:
	for index in range(_retired.size() - 1, -1, -1):
		if _retired[index].finished():
			_retired[index].texture() # (joins the threads: the picture is not wanted)
			_retired.remove_at(index)
	var added := false
	if _chart != null and _chart.finished():
		var texture := _chart.texture()
		if texture != null:
			_textures[_chart_key] = texture
			_use(_chart_key)
			finished_tiles += 1
			added = true
			PlanetMapLog.line_every("tile", 0.5, "tile %s done in %d ms (%d kept, %d asked)" % [
					_name(_chart_key), Time.get_ticks_msec() - _chart_ms, _textures.size(),
					_wanted.size()])
		_chart = null
		_wanted.erase(_chart_key)
		_evict()
	if _chart == null and not _wanted.is_empty():
		_chart_key = _wanted[0]
		_chart = PlanetChart.new()
		_chart.layer = _chart_key.x as PlanetChart.Layer
		_chart.clock = clock.copy() if clock != null else null
		_chart.rect = rect_of(_chart_key.y, _chart_key.z, _chart_key.w)
		_chart.size = Vector2i(TILE, TILE)
		_chart_ms = Time.get_ticks_msec()
		_chart.start(_noise)
	return added


func _evict() -> void:
	while _order.size() > MAX_TILES:
		var old: Vector4i = _order.pop_front()
		_textures.erase(old)


## Forgets the tiles of a layer (the moving ones, when time has moved on).
func forget(which: int) -> void:
	for key in _textures.keys():
		if key.x == which:
			_textures.erase(key)
			_order.erase(key)
	if _chart != null and _chart_key.x == which:
		_chart.cancel()
		_retired.append(_chart)
		_chart = null


## Waits for nothing: stops the chart in hand (the map is closed or freed).
func stop() -> void:
	if _chart != null:
		_chart.cancel()
		_chart.stop()
		_chart = null
	for old in _retired:
		old.cancel()
		old.stop()
	_retired.clear()


## What to draw for the tile (level, x, y): the texture and the part of it (fractions) that is the
## tile, from the tile itself or its finest charted ancestor. Null when none is charted.
func piece(level: int, x: int, y: int) -> Dictionary:
	for up in range(0, level + 1):
		var key := _key(level - up, x >> up, y >> up)
		if _textures.has(key):
			var part := Rect2(0.0, 0.0, 1.0, 1.0)
			if up > 0:
				var side := float(1 << up)
				part = Rect2(float(x & ((1 << up) - 1)) / side, float(y & ((1 << up) - 1)) / side,
						1.0 / side, 1.0 / side)
			return {"texture": _textures[key], "part": part}
	return {}
