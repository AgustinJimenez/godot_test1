class_name PlanetChart
extends RefCounted
## One picture of (a part of) a planet, drawn from PlanetNoise on background threads, in one of the
## map's layers (what the colours show). `rect` is the part of the map it covers in fractions (u
## east, v south, the whole planet is (0, 0, 1, 1)); `size` is its size in pixels. Poll
## `finished()`, then take `texture()`.

enum Layer { TERRAIN, ELEVATION, TEMPERATURE, RAIN, BIOME, PLATES, SLOPE, MEAN_TEMPERATURE,
		CLOUDS, CLOUD_MASK } ## CLOUD_MASK is the cloud cover alone (for the shell round the planet)

const NAMES: Array[String] = ["Terrain", "Elevation", "Temperature", "Rain", "Biome", "Plates",
		"Slope", "Mean temp", "Clouds"]
## threads a chart is drawn on: every core but one (the main thread), at most 8
var workers := clampi(OS.get_processor_count() - 1, 2, 8)
const BIOME_COLORS := {
	TerrainNoise.Biome.BEACH: Color(0.93, 0.85, 0.55), TerrainNoise.Biome.MEADOW: Color(0.6, 0.8, 0.3),
	TerrainNoise.Biome.FOREST: Color(0.1, 0.45, 0.15), TerrainNoise.Biome.ROCKY: Color(0.5, 0.5, 0.52),
	TerrainNoise.Biome.SNOW: Color(0.97, 0.98, 1.0), TerrainNoise.Biome.MARSH: Color(0.3, 0.55, 0.5),
	TerrainNoise.Biome.DESERT: Color(0.9, 0.6, 0.25),
}

var rect := Rect2(0.0, 0.0, 1.0, 1.0)
var size := Vector2i(320, 160)
var layer := Layer.TERRAIN
var clock: PlanetClock ## the moment the temperature layer shows (a copy: the game moves on)

var _noise: PlanetNoise
var _threads: Array[Thread] = []
var _bands: Array[PackedByteArray] = []
var _rows_done := 0
var _mutex := Mutex.new()
var _cancelled := false # a chart nobody wants any more: its workers skip the pixels


## The colour of `t` (0..1) along a layer's scale (the legend and the picture use the same).
static func ramp(which: Layer, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	match which:
		Layer.ELEVATION: # sea floor to peaks
			return _along(t, [Color(0.05, 0.12, 0.4), Color(0.3, 0.6, 0.85), Color(0.25, 0.55, 0.25),
					Color(0.85, 0.8, 0.35), Color(0.6, 0.4, 0.25), Color(1.0, 1.0, 1.0)],
					[0.0, 0.33, 0.36, 0.55, 0.8, 1.0])
		Layer.TEMPERATURE, Layer.MEAN_TEMPERATURE:
			return _along(t, [Color(0.35, 0.2, 0.75), Color(0.25, 0.6, 1.0), Color(0.5, 0.9, 0.6),
					Color(1.0, 0.9, 0.25), Color(0.95, 0.25, 0.1)], [0.0, 0.25, 0.5, 0.75, 1.0])
		Layer.RAIN:
			return _along(t, [Color(0.95, 0.85, 0.6), Color(0.8, 0.9, 0.7), Color(0.4, 0.75, 0.85),
					Color(0.1, 0.3, 0.8)], [0.0, 0.3, 0.65, 1.0])
		Layer.SLOPE:
			return _along(t, [Color(0.95, 0.95, 0.9), Color(0.75, 0.6, 0.35), Color(0.3, 0.15, 0.1)],
					[0.0, 0.4, 1.0])
	return Color.WHITE


## The two ends of a layer's scale as text (and the numbers they stand for).
static func scale_labels(which: Layer, relief: float) -> Array[String]:
	match which:
		Layer.ELEVATION:
			return ["%d m deep" % int(relief * 0.35), "%d m" % int(relief)]
		Layer.TEMPERATURE, Layer.MEAN_TEMPERATURE:
			return ["-30 °C", "35 °C"]
		Layer.RAIN:
			return ["dry", "wet"]
		Layer.SLOPE:
			return ["flat", "steep"]
	return []


static func _along(t: float, colors: Array, stops: Array) -> Color:
	for index in stops.size() - 1:
		if t <= float(stops[index + 1]):
			var span := float(stops[index + 1]) - float(stops[index])
			return (colors[index] as Color).lerp(colors[index + 1] as Color,
					(t - float(stops[index])) / maxf(span, 0.0001))
	return colors[colors.size() - 1]


func start(noise: PlanetNoise) -> void:
	_noise = noise
	_bands.resize(workers)
	for worker in workers:
		var thread := Thread.new()
		thread.start(_chart.bind(worker), Thread.PRIORITY_HIGH) # (over the world's builders)
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
	if layer == Layer.TERRAIN or layer == Layer.ELEVATION:
		_draw_rivers(image)
	return ImageTexture.create_from_image(image)


## Stops drawing (the rows still left come out empty and fast); the picture is thrown away.
func cancel() -> void:
	_cancelled = true


## Waits for the threads (the game ends).
func stop() -> void:
	for thread in _threads:
		thread.wait_to_finish()
	_threads.clear()


## One worker's share: a band of rows, as RGB bytes.
func _chart(worker: int) -> void:
	var from_row := worker * size.y / workers
	var to_row := (worker + 1) * size.y / workers
	var bytes := PackedByteArray()
	bytes.resize((to_row - from_row) * size.x * 3)
	var at := 0
	var step_lon := rect.size.x * TAU / float(size.x)
	var step_lat := rect.size.y * PI / float(size.y)
	var needs_slope := layer in [Layer.TERRAIN, Layer.ELEVATION, Layer.BIOME, Layer.SLOPE]
	for row in range(from_row, to_row):
		if _cancelled:
			at += size.x * 3
			_mutex.lock()
			_rows_done += 1
			_mutex.unlock()
			continue
		var v := rect.position.y + (float(row) + 0.5) / float(size.y) * rect.size.y
		var lat := (0.5 - v) * PI
		# the heights of the whole row (and the points east and north of it) in one go: the
		# native crust answers many at once much faster than one by one
		var dirs := PackedVector3Array()
		var east_dirs := PackedVector3Array()
		var north_dirs := PackedVector3Array()
		dirs.resize(size.x)
		for column in size.x:
			var u := rect.position.x + (float(column) + 0.5) / float(size.x) * rect.size.x
			dirs[column] = _direction(lat, u * TAU - PI)
		if needs_slope:
			east_dirs.resize(size.x)
			north_dirs.resize(size.x)
			for column in size.x:
				var u := rect.position.x + (float(column) + 0.5) / float(size.x) * rect.size.x
				east_dirs[column] = _direction(lat, u * TAU - PI + step_lon)
				north_dirs[column] = _direction(lat + step_lat, u * TAU - PI)
		var grounds := _noise.heights_of(dirs)
		var east_grounds := _noise.heights_of(east_dirs) if needs_slope else grounds
		var north_grounds := _noise.heights_of(north_dirs) if needs_slope else grounds
		var macros := grounds
		if layer in [Layer.TEMPERATURE, Layer.CLOUDS, Layer.CLOUD_MASK]:
			macros = _noise.macro_heights_of(dirs)
		var bases := PackedColorArray()
		if layer == Layer.CLOUDS:
			var flat := PackedFloat32Array()
			flat.resize(size.x)
			flat.fill(0.1)
			bases = _noise.colours_of(dirs, grounds, flat)
		for column in size.x:
			var ground := grounds[column]
			var color := _pixel_color(dirs[column], ground, east_grounds[column] - ground,
					north_grounds[column] - ground, step_lon, needs_slope, macros[column],
					bases[column] if not bases.is_empty() else Color.BLACK)
			bytes[at] = clampi(int(color.r * 255.0), 0, 255)
			bytes[at + 1] = clampi(int(color.g * 255.0), 0, 255)
			bytes[at + 2] = clampi(int(color.b * 255.0), 0, 255)
			at += 3
		_mutex.lock()
		_rows_done += 1
		_mutex.unlock()
	_bands[worker] = bytes


static func _direction(lat: float, lon: float) -> Vector3:
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))


## The colour of the pixel looking along `dir`, from its ground height and how far the ground
## rises one pixel east and north of it.
func _pixel_color(dir: Vector3, ground: float, rise_east: float, rise_north: float,
		step_lon: float, needs_slope: bool, macro := NAN, base_colour := Color.BLACK) -> Color:
	var noise := _noise
	var relief := noise.relief
	var slope := 0.0
	if needs_slope:
		slope = clampf(Vector2(rise_east, rise_north).length() / (step_lon * noise.settings.radius),
				0.0, 1.0)
	var color := Color.WHITE
	match layer:
		Layer.ELEVATION:
			var t := 0.0
			if ground < 0.0:
				t = lerpf(0.33, 0.0, clampf(-ground / (relief * 0.35), 0.0, 1.0))
			else:
				t = lerpf(0.36, 1.0, clampf(ground / relief, 0.0, 1.0))
			color = ramp(Layer.ELEVATION, t)
			# contour lines every 5% of the relief on the land
			if ground >= 0.0:
				var interval := relief * 0.05
				var band := floorf(ground / interval)
				var crosses_east := band != floorf((ground + rise_east) / interval)
				var crosses_north := band != floorf((ground + rise_north) / interval)
				if crosses_east or crosses_north:
					color = color.darkened(0.3)
		Layer.TEMPERATURE:
			var degrees := noise.temperature_now(dir.x, dir.y, dir.z, maxf(ground, 0.0), clock,
					macro)
			color = ramp(Layer.TEMPERATURE, (degrees + 30.0) / 65.0)
		Layer.MEAN_TEMPERATURE:
			var degrees := noise.temperature(dir.x, dir.y, dir.z, maxf(ground, 0.0))
			color = ramp(Layer.TEMPERATURE, (degrees + 30.0) / 65.0)
		Layer.CLOUDS:
			var land_colour := base_colour if ground >= 0.0 and noise.hydrology == null else \
					_terrain_color(dir, ground, 0.1, 0.0, step_lon)
			var base := land_colour.darkened(0.45)
			var cover := noise.weather.cloud(dir, clock, macro)
			color = base.lerp(Color(0.97, 0.98, 1.0), cover * 0.92)
		Layer.CLOUD_MASK:
			var cover := noise.weather.cloud(dir, clock, macro)
			color = Color(cover, cover, cover)
		Layer.RAIN:
			color = ramp(Layer.RAIN, noise.climate.sample(dir).y / 1.2)
			if ground < 0.0:
				color = color.darkened(0.25)
		Layer.BIOME:
			color = _biome_color(dir, ground, slope)
		Layer.PLATES:
			var plate := noise.tectonics.plate_at(dir)
			var land := plate.z > 0.5
			color = Color.from_hsv(fposmod(plate.x * 0.61803, 1.0), 0.55 if land else 0.25,
					0.95 if land else 0.6)
			if ground < 0.0:
				color = color.darkened(0.35)
			if plate.y < 0.012:
				color = Color.BLACK
		Layer.SLOPE:
			color = Color(0.2, 0.4, 0.7) if ground < 0.0 else ramp(Layer.SLOPE, slope / 0.6)
		_:
			color = _terrain_color(dir, ground, slope, rise_east - rise_north, step_lon)
	return color


## Sea (darker where it is deep), lakes and the land's biome colours with the relief shaded.
func _terrain_color(dir: Vector3, ground: float, slope: float, light: float,
		step_lon: float) -> Color:
	var relief := _noise.relief
	if ground < 0.0:
		var depth := clampf(-ground / (relief * 0.35), 0.0, 1.0)
		return Color(0.32, 0.62, 0.78).lerp(Color(0.03, 0.12, 0.33), sqrt(depth))
	if _noise.hydrology != null and _noise.hydrology.lake_level_at(dir, ground) > -INF:
		return Color(0.25, 0.5, 0.85)
	var color := _noise.facet_color(dir.x, dir.y, dir.z, ground, slope)
	# hill shading: the light from the north west, the same on a close map as on a far one
	var shade := clampf(1.0 - light * 6.0 * 0.0098 / step_lon / relief, 0.55, 1.35)
	return Color(color.r * shade, color.g * shade, color.b * shade)


func _biome_color(dir: Vector3, ground: float, slope: float) -> Color:
	if ground < 0.0:
		return Color(0.2, 0.4, 0.7).lerp(Color(0.05, 0.12, 0.35),
				clampf(-ground / (_noise.relief * 0.35), 0.0, 1.0))
	if _noise.hydrology != null and _noise.hydrology.lake_level_at(dir, ground) > -INF:
		return Color(0.25, 0.5, 0.85)
	return BIOME_COLORS[_noise.biome(dir.x, dir.y, dir.z, ground, slope)]


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
