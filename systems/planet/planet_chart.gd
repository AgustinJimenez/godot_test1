class_name PlanetChart
extends RefCounted
## One picture of (a part of) a planet, drawn from PlanetNoise on background threads: the sea darker
## where it is deep, the land in its biome colours with the relief shaded, lakes in blue, then the
## rivers as thin blue lines. `rect` is the part of the map it covers in fractions (u east, v south,
## the whole planet is (0, 0, 1, 1)); `size` is its size in pixels. Poll `finished()`, then take
## `texture()`.

const WORKERS := 3

var rect := Rect2(0.0, 0.0, 1.0, 1.0)
var size := Vector2i(320, 160)

var _noise: PlanetNoise
var _threads: Array[Thread] = []
var _bands: Array[PackedByteArray] = []
var _rows_done := 0
var _mutex := Mutex.new()


func start(noise: PlanetNoise) -> void:
	_noise = noise
	_bands.resize(WORKERS)
	for worker in WORKERS:
		var thread := Thread.new()
		thread.start(_chart.bind(worker))
		_threads.append(thread)


## 0..1
func progress() -> float:
	_mutex.lock()
	var done := _rows_done
	_mutex.unlock()
	return float(done) / float(size.y)


func finished() -> bool:
	return progress() >= 1.0


## The finished picture (joins the threads). Null while it is not done.
func texture() -> ImageTexture:
	if not finished():
		return null
	for thread in _threads:
		thread.wait_to_finish()
	_threads.clear()
	var all := PackedByteArray()
	for band in _bands:
		all.append_array(band)
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, all)
	_draw_rivers(image)
	return ImageTexture.create_from_image(image)


## Waits for the threads (the map is closed or the game ends).
func stop() -> void:
	for thread in _threads:
		thread.wait_to_finish()
	_threads.clear()


## One worker's share: a band of rows, as RGB bytes.
func _chart(worker: int) -> void:
	var from_row := worker * size.y / WORKERS
	var to_row := (worker + 1) * size.y / WORKERS
	var bytes := PackedByteArray()
	var relief := _noise.relief
	var step_lon := rect.size.x * TAU / float(size.x)
	var step_lat := rect.size.y * PI / float(size.y)
	var run := step_lon * _noise.settings.radius
	var shading := 6.0 * 0.0098 / step_lon / relief # the same light on a close map as a far one
	for row in range(from_row, to_row):
		var v := rect.position.y + (float(row) + 0.5) / float(size.y) * rect.size.y
		var lat := (0.5 - v) * PI
		for column in size.x:
			var u := rect.position.x + (float(column) + 0.5) / float(size.x) * rect.size.x
			var lon := u * TAU - PI
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var ground := _noise.height(dir.x, dir.y, dir.z)
			var east := Vector3(cos(lat) * cos(lon + step_lon), sin(lat),
					cos(lat) * sin(lon + step_lon))
			var up_lat := lat + step_lat
			var north := Vector3(cos(up_lat) * cos(lon), sin(up_lat), cos(up_lat) * sin(lon))
			var h_east := _noise.height(east.x, east.y, east.z)
			var h_north := _noise.height(north.x, north.y, north.z)
			var color: Color
			if ground < 0.0:
				var depth := clampf(-ground / (relief * 0.35), 0.0, 1.0)
				color = Color(0.32, 0.62, 0.78).lerp(Color(0.03, 0.12, 0.33), sqrt(depth))
			elif _noise.hydrology != null and _noise.hydrology.lake_level_at(dir, ground) > -INF:
				color = Color(0.25, 0.5, 0.85)
			else:
				var slope := Vector2(h_east - ground, h_north - ground).length() / run
				color = _noise.facet_color(dir.x, dir.y, dir.z, ground, clampf(slope, 0.0, 1.0))
				# hill shading: the light from the north west
				var shade := clampf(1.0 + ((ground - h_east) + (h_north - ground)) * shading, 0.55, 1.35)
				color = Color(color.r * shade, color.g * shade, color.b * shade)
			bytes.append(clampi(int(color.r * 255.0), 0, 255))
			bytes.append(clampi(int(color.g * 255.0), 0, 255))
			bytes.append(clampi(int(color.b * 255.0), 0, 255))
		_mutex.lock()
		_rows_done += 1
		_mutex.unlock()
	_bands[worker] = bytes


## The rivers of this part of the map as thin blue lines.
func _draw_rivers(image: Image) -> void:
	if _noise.hydrology == null:
		return
	var pixels := Vector2(size)
	for line: Array in _noise.hydrology.river_lines():
		var a := _pixel(line[0] as Vector3, pixels)
		var b := _pixel(line[1] as Vector3, pixels)
		if absf(a.x - b.x) > pixels.x * 0.5 or (a.x < -pixels.x and b.x < -pixels.x):
			continue
		var count := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
		if count > size.x * 2:
			continue
		for index in count + 1:
			var at := a.lerp(b, float(index) / float(maxi(count, 1)))
			var pixel := Vector2i(int(at.x), int(at.y))
			if pixel.x >= 0 and pixel.x < size.x and pixel.y >= 0 and pixel.y < size.y:
				image.set_pixelv(pixel, Color(0.2, 0.45, 0.95))


func _pixel(dir: Vector3, pixels: Vector2) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var u := (lon + PI) / TAU
	var v := 0.5 - lat / PI
	return Vector2((u - rect.position.x) / rect.size.x * pixels.x,
			(v - rect.position.y) / rect.size.y * pixels.y)
