class_name PlanetMap
extends CanvasLayer
## A map of the whole planet on the M key: the sea (darker where it is deep), the land in its
## biome colours with the relief shaded, lakes and rivers, a lat/long grid, and where the player is
## and which way they face. It is drawn once from the planet's own height function (PlanetNoise), a
## few seconds on background threads after the player is in, and shows "charting" until then. A flat
## (equirectangular) map: east to the right, north up, the poles stretched along the edges.

const ACTION := &"planet_map"
const WIDTH := 640
const HEIGHT := 320
const WORKERS := 3

var planet: PlanetWorld

var _image_ready := false
var _threads: Array[Thread] = []
var _rows: Array[PackedByteArray] = [] # each worker's rows, RGB
var _rows_done := 0
var _mutex := Mutex.new()
var _panel: PanelContainer
var _picture: TextureRect
var _marker: Control
var _caption: Label
var _started := false


func _ready() -> void:
	layer = 70
	visible = false
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_M
		InputMap.action_add_event(ACTION, key)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(WIDTH * 2, HEIGHT * 2)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	column.add_child(_picture)
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_picture.add_child(_marker)
	_caption = Label.new()
	_caption.text = "Charting the planet..."
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_caption)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		visible = not visible
		get_viewport().set_input_as_handled()


## Starts drawing the map on background threads (a no-op without a window, and the second time).
func begin() -> void:
	if _started or planet == null or DisplayServer.get_name() == "headless":
		return
	_started = true
	_rows.resize(WORKERS)
	for index in WORKERS:
		var worker := Thread.new()
		worker.start(_chart.bind(index))
		_threads.append(worker)


func _exit_tree() -> void:
	for worker in _threads:
		worker.wait_to_finish()
	_threads.clear()


func _process(_delta: float) -> void:
	if visible:
		_marker.queue_redraw()
	if _started and not _image_ready:
		_mutex.lock()
		var done := _rows_done
		_mutex.unlock()
		if done >= HEIGHT:
			_finish()
		elif visible:
			_caption.text = "Charting the planet...  %d %%" % int(100.0 * float(done) / float(HEIGHT))


## One worker's share of the map: a band of rows, as RGB bytes.
func _chart(worker: int) -> void:
	var noise := planet.noise
	var from_row := worker * HEIGHT / WORKERS
	var to_row := (worker + 1) * HEIGHT / WORKERS
	var bytes := PackedByteArray()
	var relief := noise.relief
	var step := TAU / float(WIDTH)
	for row in range(from_row, to_row):
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		for column in WIDTH:
			var lon := (float(column) + 0.5) / float(WIDTH) * TAU - PI
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var ground := noise.height(dir.x, dir.y, dir.z)
			var east := Vector3(cos(lat) * cos(lon + step), sin(lat), cos(lat) * sin(lon + step))
			var up_lat := lat + step
			var north := Vector3(cos(up_lat) * cos(lon), sin(up_lat), cos(up_lat) * sin(lon))
			var h_east := noise.height(east.x, east.y, east.z)
			var h_north := noise.height(north.x, north.y, north.z)
			var color: Color
			if ground < 0.0:
				var depth := clampf(-ground / (relief * 0.35), 0.0, 1.0)
				color = Color(0.32, 0.62, 0.78).lerp(Color(0.03, 0.12, 0.33), sqrt(depth))
			else:
				var lake := noise.hydrology != null and noise.hydrology.lake_level_at(dir, ground) > -INF
				if lake:
					color = Color(0.25, 0.5, 0.85)
				else:
					var run := step * noise.settings.radius
					var slope := Vector2(h_east - ground, h_north - ground).length() / run
					color = noise.facet_color(dir.x, dir.y, dir.z, ground, clampf(slope, 0.0, 1.0))
					# hill shading: the light from the north west
					var shade := clampf(1.0 + ((ground - h_east) + (h_north - ground)) / relief * 6.0,
							0.55, 1.35)
					color = Color(color.r * shade, color.g * shade, color.b * shade)
			bytes.append(clampi(int(color.r * 255.0), 0, 255))
			bytes.append(clampi(int(color.g * 255.0), 0, 255))
			bytes.append(clampi(int(color.b * 255.0), 0, 255))
		_mutex.lock()
		_rows_done += 1
		_mutex.unlock()
	_rows[worker] = bytes


func _finish() -> void:
	for worker in _threads:
		worker.wait_to_finish()
	_threads.clear()
	var all := PackedByteArray()
	for part in _rows:
		all.append_array(part)
	var image := Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, all)
	_draw_rivers(image)
	_picture.texture = ImageTexture.create_from_image(image)
	_image_ready = true
	_caption.text = ""


## The rivers as thin blue lines (the widest a pixel thicker).
func _draw_rivers(image: Image) -> void:
	if planet.noise.hydrology == null:
		return
	for line: Array in planet.noise.hydrology.river_lines():
		var a := _pixel_of(line[0] as Vector3)
		var b := _pixel_of(line[1] as Vector3)
		if absf(a.x - b.x) > WIDTH * 0.5:
			continue # across the edge of the map
		var count := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
		for index in count + 1:
			var at := a.lerp(b, float(index) / float(maxi(count, 1)))
			var pixel := Vector2i(int(at.x), int(at.y))
			if pixel.x >= 0 and pixel.x < WIDTH and pixel.y >= 0 and pixel.y < HEIGHT:
				image.set_pixelv(pixel, Color(0.2, 0.45, 0.95))


func _pixel_of(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return Vector2((lon + PI) / TAU * float(WIDTH), (0.5 - lat / PI) * float(HEIGHT))


## The lat/long grid, the player and which way they look.
func _draw_marker() -> void:
	var size := _marker.size
	var scale := Vector2(size.x / float(WIDTH), size.y / float(HEIGHT))
	var grid := Color(1.0, 1.0, 1.0, 0.18)
	for degrees in range(-60, 61, 30):
		var y := (0.5 - float(degrees) / 180.0) * size.y
		var colour := grid if degrees != 0 else Color(1.0, 1.0, 1.0, 0.35)
		_marker.draw_line(Vector2(0.0, y), Vector2(size.x, y), colour)
	for degrees in range(-150, 151, 30):
		var x := (float(degrees) + 180.0) / 360.0 * size.x
		_marker.draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid)
	if planet == null or planet.target() == null:
		return
	var here := planet.planet_position().normalized()
	var spot := _pixel_of(here) * scale
	# which way the camera looks, on the map: east to the right, north up
	var camera := get_viewport().get_camera_3d()
	var heading := Vector2(0.0, -1.0)
	if camera != null:
		var forward := planet.frame.rot.inverse() * (-camera.global_basis.z)
		var east := Vector3(-here.z, 0.0, here.x).normalized()
		var north := east.cross(here)
		heading = Vector2(forward.dot(east), -forward.dot(north)).normalized()
	var side := Vector2(-heading.y, heading.x)
	var tip := spot + heading * 13.0
	var points := PackedVector2Array([tip, spot - heading * 7.0 + side * 7.0,
			spot - heading * 7.0 - side * 7.0])
	_marker.draw_colored_polygon(points, Color(1.0, 0.25, 0.2))
	_marker.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]),
			Color.WHITE, 1.5)
	if _image_ready:
		var lat := rad_to_deg(asin(here.y))
		var lon := rad_to_deg(atan2(here.z, here.x))
		var north_south := "N" if lat >= 0.0 else "S"
		var east_west := "E" if lon >= 0.0 else "W"
		_caption.text = "%.1f° %s  %.1f° %s     altitude %d m     [M] close" % [absf(lat),
				north_south, absf(lon), east_west, roundi(planet.altitude())]
