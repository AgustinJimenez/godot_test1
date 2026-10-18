class_name PlanetChart
extends RefCounted
## One picture of (a part of) a planet, drawn from PlanetNoise on background threads, in one of the
## map's layers (what the colours show). `rect` is the part of the map it covers in fractions (u
## east, v south, the whole planet is (0, 0, 1, 1)); `size` is its size in pixels. Poll
## `finished()`, then take `texture()`.

enum Layer { TERRAIN, ELEVATION, TEMPERATURE, RAIN, BIOME, PLATES, SLOPE, MEAN_TEMPERATURE,
		CLOUDS, SATELLITE, CLOUD_MASK }
## CLOUD_MASK is the cloud cover alone (for the shell round the planet)

const NAMES: Array[String] = ["Terrain", "Elevation", "Temperature", "Rain", "Biome", "Plates",
		"Slope", "Mean temp", "Clouds", "Satellite"]
const CALM_PIXEL := 2000.0 ## metres a pixel spans above which the Terrain relief is shaded gently
const COARSE_PIXEL := 20.0 ## metres a pixel spans above which the map has no fine grain or beds
const SHADE_EXAGGERATION := 2.0 ## the map's hill shading: how much a slope lights or darkens
const SMOOTHED := [Layer.TEMPERATURE, Layer.MEAN_TEMPERATURE, Layer.RAIN, Layer.CLOUDS]
const NATIVE_LAYERS := [Layer.ELEVATION, Layer.TEMPERATURE, Layer.RAIN, Layer.SLOPE,
		Layer.MEAN_TEMPERATURE] ## the layers whose rows the native crust colours
const SMOOTH_PIXEL := 30.0 ## metres a pixel spans above which the map draws the smooth ground

const BIOME_COLORS := {
	TerrainNoise.Biome.BEACH: Color(0.93, 0.85, 0.55), TerrainNoise.Biome.MEADOW: Color(0.6, 0.8, 0.3),
	TerrainNoise.Biome.FOREST: Color(0.1, 0.45, 0.15), TerrainNoise.Biome.ROCKY: Color(0.5, 0.5, 0.52),
	TerrainNoise.Biome.SNOW: Color(0.97, 0.98, 1.0), TerrainNoise.Biome.MARSH: Color(0.3, 0.55, 0.5),
	TerrainNoise.Biome.DESERT: Color(0.9, 0.6, 0.25),
}

## threads a chart is drawn on: every core but one (the main thread), at most 8
var workers := clampi(OS.get_processor_count() - 1, 2, 8)
var rect := Rect2(0.0, 0.0, 1.0, 1.0)
var size := Vector2i(320, 160)
var layer := Layer.TERRAIN
var clock: PlanetClock ## the moment the temperature layer shows (a copy: the game moves on)

var _noise: PlanetNoise
var _pixel_metres := 0.0 ## metres a pixel spans
var _threads: Array[Thread] = []
var _bands: Array[PackedByteArray] = []
var _blend := PackedFloat32Array() # the seasons' grid at this chart's moment (Temperature)
var _ground_bands: Array[PackedFloat32Array] = [] # each worker's heights (the map's cache)
var _land_bands: Array[PackedByteArray] = [] # 1 where the pixel is land (for the coast lines)
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
			# -30 .. 45 °C: purple, blue, green (5), yellow (20), orange (30), red, dark red (45)
			return _along(t, [Color(0.35, 0.2, 0.75), Color(0.25, 0.6, 1.0), Color(0.45, 0.85, 0.6),
					Color(1.0, 0.9, 0.25), Color(0.98, 0.5, 0.1), Color(0.8, 0.12, 0.08),
					Color(0.4, 0.04, 0.02)], [0.0, 0.2, 0.46, 0.67, 0.8, 0.92, 1.0])
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
			return ["-30 °C", "45 °C"]
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
	_land_bands.resize(workers)
	_ground_bands.resize(workers)
	if layer == Layer.TEMPERATURE and clock != null:
		_blend = noise.climate.seasons.blended(clock.year_share())
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
	var tidy := layer != Layer.PLATES and layer != Layer.CLOUD_MASK
	if tidy and _noise.native != null and _noise.native.has_method(&"despeckle"):
		all = _noise.native.call(&"despeckle", all, size.x, size.y) # (lone dots are grain)
	var full_map := rect == Rect2(0.0, 0.0, 1.0, 1.0) and _pixel_metres > SMOOTH_PIXEL
	if not _cancelled and full_map and not _noise.map_heights.has(size):
		var heights := PackedFloat32Array()
		for band in _ground_bands:
			heights.append_array(band)
		if heights.size() == size.x * size.y:
			_noise.map_heights[size] = heights
	var far := _pixel_metres > CALM_PIXEL * 50.0 # (kilometres a pixel: Elevation is grain too)
	if _noise.native != null and (layer in SMOOTHED or (layer == Layer.ELEVATION and far)):
		# (a data layer is a smooth gradient: the grain of the small pixels is averaged away, and a thin
		# dark line follows the coasts so the sea and the land read through the colours)
		var passes := 8 if layer in [Layer.TEMPERATURE, Layer.MEAN_TEMPERATURE] else 3
		for pass_number in passes:
			all = _noise.native.call(&"smooth_rgb", all, size.x, size.y)
		var land_all := PackedByteArray()
		for band in _land_bands:
			land_all.append_array(band)
		if land_all.size() >= size.x * size.y:
			all = _noise.native.call(&"coast_lines", all, land_all, size.x, size.y)
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
	var land := PackedByteArray()
	# the Terrain layer's rows come ready from the native crust (rows are then added one by one)
	var step_lon := rect.size.x * TAU / float(size.x)
	var native_rows := _noise.native != null and ((layer == Layer.TERRAIN and _noise.hydrology == null)
			or layer in NATIVE_LAYERS)
	if not native_rows:
		bytes.resize((to_row - from_row) * size.x * 3)
	var at := 0
	var step_lat := rect.size.y * PI / float(size.y)
	var needs_slope := layer in [Layer.TERRAIN, Layer.ELEVATION, Layer.BIOME, Layer.SLOPE,
			Layer.SATELLITE]
	# a pixel wider than a few tens of metres would only alias the hills and gullies into grain: the
	# smooth ground is drawn (shaded like an illustration); closer in, the real ground
	var smooth_ground := step_lon * _noise.settings.radius > SMOOTH_PIXEL
	# the relief of a pixel of many kilometres is shaded gently (steeper looks like grain)
	var calm := clampf(sqrt(CALM_PIXEL / (step_lon * _noise.settings.radius)), 0.5, 1.0)
	_pixel_metres = step_lon * _noise.settings.radius
	var above := PackedFloat32Array() # the heights of the row before (the point a pixel north)
	# the whole planet's pictures share their heights: a layer drawn after another reads them
	var whole := rect == Rect2(0.0, 0.0, 1.0, 1.0) and smooth_ground
	var cached := PackedFloat32Array()
	if whole:
		cached = _noise.map_heights.get(size, PackedFloat32Array())
	var use_cache := cached.size() == size.x * size.y
	var recorded := PackedFloat32Array()
	for row in range(from_row, to_row):
		if _cancelled:
			land.resize(land.size() + size.x)
			if native_rows:
				bytes.resize(bytes.size() + size.x * 3)
			at += size.x * 3
			_mutex.lock()
			_rows_done += 1
			_mutex.unlock()
			above = PackedFloat32Array() # the next row is not beside this one
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
		var grounds := PackedFloat32Array()
		if use_cache:
			grounds = cached.slice(row * size.x, (row + 1) * size.x)
		else:
			grounds = _ground_of(dirs, smooth_ground)
		var east_grounds := grounds
		var north_grounds := grounds
		if use_cache:
			east_grounds = grounds.slice(1)
			east_grounds.append(grounds[0]) # (the map wraps east-west)
			north_grounds = cached.slice(maxi(row - 1, 0) * size.x, maxi(row - 1, 0) * size.x + size.x)
		elif needs_slope:
			# the point a pixel east is the next pixel of the row, the one a pixel north is the same
			# pixel of the row before (kept from the last turn): only the row's last pixel and the
			# first row of a thread need points of their own
			var u_end := rect.end.x + 0.5 / float(size.x) * rect.size.x
			var last_east := PackedVector3Array([_direction(lat, u_end * TAU - PI)])
			east_grounds = grounds.slice(1)
			east_grounds.append_array(_ground_of(last_east, smooth_ground))
			if above.is_empty():
				north_dirs.resize(size.x)
				for column in size.x:
					var u := rect.position.x + (float(column) + 0.5) / float(size.x) * rect.size.x
					north_dirs[column] = _direction(lat + step_lat, u * TAU - PI)
				above = _ground_of(north_dirs, smooth_ground)
			north_grounds = above
			above = grounds
		var macros := grounds
		if whole and not use_cache:
			recorded.append_array(grounds)
		if smooth_ground:
			pass # (the broad ground of a far view is the ground itself)
		elif layer in [Layer.TEMPERATURE, Layer.MEAN_TEMPERATURE, Layer.CLOUDS, Layer.SATELLITE,
				Layer.CLOUD_MASK]:
			macros = _ground_of(dirs, true)
		for column in size.x:
			land.append(1 if grounds[column] >= 0.0 else 0)
		if native_rows:
			if layer == Layer.TERRAIN:
				bytes.append_array(_noise.native.call(&"terrain_row", dirs, grounds, east_grounds,
						north_grounds, step_lon, calm))
			else:
				bytes.append_array(_noise.native.call(&"data_row", int(layer), dirs, grounds, macros,
						east_grounds, north_grounds, step_lon, _row_params(lat)))
			_mutex.lock()
			_rows_done += 1
			_mutex.unlock()
			continue
		var bases := PackedColorArray()
		if layer == Layer.CLOUDS and _pixel_metres <= COARSE_PIXEL:
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
	_land_bands[worker] = land
	_ground_bands[worker] = recorded


## What the native row needs besides the heights (the seasons' grid now, the sun's longitude, and
## how clear the sky is on this row's latitude).
func _row_params(lat: float) -> Dictionary:
	if clock == null or _blend.is_empty():
		return {}
	var sun := clock.sun_in_body()
	return {"grid": _blend, "gw": PlanetSeasons.WIDTH, "gh": PlanetSeasons.HEIGHT,
			"sun_lon": atan2(sun.z, sun.x),
			"clear": clampf(clock.day_length(lat) * 2.0 + 0.3, 0.3, 1.0)}


## The ground at many directions: its smooth shape (without the hills and gullies) for a far view.
func _ground_of(dirs: PackedVector3Array, smooth_shape: bool) -> PackedFloat32Array:
	if not smooth_shape:
		return _noise.heights_of(dirs)
	return _noise.broad_heights_of(dirs, _pixel_metres)


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
			# (pixels of kilometres: the colour is the mean of the pixel and its east and north ones)
			var shown := ground
			if _pixel_metres > CALM_PIXEL and ground >= 0.0:
				shown = maxf(ground + (rise_east + rise_north) * 0.25, 0.0)
			var deep := ground
			if _pixel_metres > CALM_PIXEL and ground < 0.0: # (the sea floor's noise only makes grain)
				deep = minf((ground + (ground + rise_east + rise_north)) * 0.5, 0.0)
			if ground < 0.0:
				t = lerpf(0.33, 0.0, clampf(-deep / (relief * 0.35), 0.0, 1.0))
			else:
				t = lerpf(0.36, 1.0, clampf(shown / relief, 0.0, 1.0))
			color = ramp(Layer.ELEVATION, t)
			# contour lines every 5% of the relief on the land
			if ground >= 0.0 and _pixel_metres <= CALM_PIXEL: # (at kilometres a pixel they are only grain)
				var interval := relief * 0.05
				var band := floorf(ground / interval)
				var crosses_east := band != floorf((ground + rise_east) / interval)
				var crosses_north := band != floorf((ground + rise_north) / interval)
				if crosses_east or crosses_north:
					color = color.darkened(0.3)
		Layer.TEMPERATURE:
			# (the broad ground: the small hills would only speckle the map)
			var shape := macro if not is_nan(macro) else ground
			var degrees := noise.temperature_now(dir.x, dir.y, dir.z, maxf(shape, 0.0), clock,
					macro)
			color = ramp(Layer.TEMPERATURE, (degrees + 30.0) / 75.0)
		Layer.MEAN_TEMPERATURE:
			var shape := macro if not is_nan(macro) else ground
			var degrees := noise.temperature(dir.x, dir.y, dir.z, maxf(shape, 0.0))
			color = ramp(Layer.TEMPERATURE, (degrees + 30.0) / 75.0)
		Layer.CLOUDS:
			var own := ground >= 0.0 and noise.hydrology == null and base_colour != Color.BLACK
			var land_colour := base_colour if own else 					_terrain_color(dir, ground, 0.1, 0.0, step_lon)
			var base := land_colour.darkened(0.45)
			var cover := noise.weather.cloud(dir, clock, macro)
			color = base.lerp(Color(0.97, 0.98, 1.0), cover * 0.92)
		Layer.SATELLITE:
			color = _satellite_color(dir, ground, macro, rise_east - rise_north, step_lon)
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


## The land as a map shows it from far: green where it is wet and warm, tan where it is dry, brown
## and grey rock up the mountains and snow where it is cold (the rock types are left to the close
## views).
func _illustrated_color(dir: Vector3, ground: float, slope: float) -> Color:
	var noise := _noise
	var degrees := noise.temperature(dir.x, dir.y, dir.z, ground)
	var wet := clampf(noise.climate.sample(dir).y / 0.9, 0.0, 1.0)
	var warm := clampf((degrees + 6.0) / 16.0, 0.0, 1.0)
	var low := Color(0.78, 0.7, 0.46).lerp(Color(0.46, 0.6, 0.27), wet * warm)
	low = low.lerp(Color(0.62, 0.64, 0.5), 1.0 - warm) # cold ground: tundra
	var tall := clampf(ground / noise.relief, 0.0, 1.0)
	var color := low.lerp(Color(0.58, 0.5, 0.38), smoothstep(0.12, 0.4, tall))
	color = color.lerp(Color(0.5, 0.48, 0.46), smoothstep(0.3, 0.65, tall + slope * 0.4))
	var snow := smoothstep(-1.0, -5.0, degrees) * (1.0 - 0.7 * smoothstep(0.5, 0.95, slope))
	color = color.lerp(Color(0.95, 0.97, 1.0), snow)
	var ice := smoothstep(-8.0, -14.0, degrees) * (1.0 - smoothstep(0.25, 0.6, slope)) * snow
	color = color.lerp(Color(0.72, 0.86, 0.96), ice * 0.7) # glacier ice
	var sand := smoothstep(1.0, 0.0, ground) # a beach by the sea
	return color.lerp(Color(0.9, 0.82, 0.55), sand * 0.8)


## The planet as a weather satellite sees it: a deep blue sea, green and brown land (greener where
## it rains), white snow and ice, and the clouds over it with a little shade of their own.
func _satellite_color(dir: Vector3, ground: float, macro: float, light: float,
		step_lon: float) -> Color:
	var noise := _noise
	var shape := macro if not is_nan(macro) else ground
	var color: Color
	if ground < 0.0:
		var depth := clampf(-ground / (noise.relief * 0.35), 0.0, 1.0)
		color = Color(0.12, 0.27, 0.52).lerp(Color(0.04, 0.1, 0.3), sqrt(depth))
	else:
		var weather := noise.climate.sample(dir)
		var green := clampf(weather.y / 0.9, 0.0, 1.0)
		var warm := clampf((noise.temperature(dir.x, dir.y, dir.z, maxf(shape, 0.0)) + 8.0) / 14.0,
				0.0, 1.0)
		var dry := Color(0.62, 0.56, 0.38)
		var forest := Color(0.17, 0.3, 0.1)
		color = dry.lerp(forest, green * warm).lerp(Color(0.5, 0.5, 0.42), 1.0 - warm)
		var snow := 1.0 - clampf((noise.temperature(dir.x, dir.y, dir.z, maxf(shape, 0.0)) + 6.0)
				/ 5.0, 0.0, 1.0)
		color = color.lerp(Color(0.95, 0.97, 1.0), snow)
		var metres := step_lon * noise.settings.radius * sqrt(maxf(1.0 - dir.y * dir.y, 0.04))
		var shade := clampf(1.0 - 1.2 * SHADE_EXAGGERATION * 0.5 * light / metres, 0.75, 1.2)
		color = Color(color.r * shade, color.g * shade, color.b * shade)
	var cover := noise.weather.cloud(dir, clock, macro)
	var cloud := Color(0.93, 0.95, 0.98).lerp(Color(0.72, 0.75, 0.82), 0.25 * (1.0 - cover))
	return color.lerp(cloud, cover * 0.92)


## Sea (darker where it is deep), lakes and the land's biome colours with the relief shaded.
func _terrain_color(dir: Vector3, ground: float, slope: float, light: float,
		step_lon: float) -> Color:
	var relief := _noise.relief
	if ground < 0.0:
		var depth := clampf(-ground / (relief * 0.35), 0.0, 1.0)
		var water := Color(0.32, 0.62, 0.78).lerp(Color(0.03, 0.12, 0.33), sqrt(depth))
		# sea ice where the sea's mean temperature is below its freezing point
		var lat := asin(clampf(dir.y, -1.0, 1.0))
		var lon := atan2(dir.z, dir.x)
		var warm := 0.0 # (the mean over a band of latitude, wobbled: a ragged edge of ice)
		for step in range(-2, 3):
			var l := clampf(lat + 0.14 * sin(lon * 3.0 + lat * 5.0) + float(step) * 0.06, -1.5, 1.5)
			warm += _noise.climate.sea_temperature(_direction(l, lon)) / 5.0
		var ice := smoothstep(-1.5, -8.0, warm) * 0.92
		return water.lerp(Color(0.90, 0.94, 0.98), ice)
	if _noise.hydrology != null and _noise.hydrology.lake_level_at(dir, ground) > -INF:
		return Color(0.25, 0.5, 0.85)
	var coarse := step_lon * _noise.settings.radius > COARSE_PIXEL
	var color := _noise.facet_color(dir.x, dir.y, dir.z, ground, slope, false)
	if coarse:
		color = _illustrated_color(dir, ground, slope)
	# hill shading: the light from the north west, the same on a close map as on a far one
	# (the height difference over the metres a pixel spans is the slope; the relief is drawn with a
	# fixed vertical exaggeration, so plains stay smooth and only real slopes are lit and shadowed)
	var metres := step_lon * _noise.settings.radius * sqrt(maxf(1.0 - dir.y * dir.y, 0.04))
	var shade := clampf(1.0 - SHADE_EXAGGERATION * light / metres, 0.55, 1.35)
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
