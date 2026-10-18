class_name PlanetMap
extends CanvasLayer
## A map of the planet on the M key, over the whole screen. It opens on the player's region (about a
## sixth of the planet round them, their arrow in the middle); the mouse wheel zooms in and out (all
## the way out is the whole planet), dragging moves the view, R comes back to the player. The sea is
## darker where it is deep, the land has its biome colours with the relief shaded, with lakes,
## rivers and a lat/long grid. It is drawn from the planet's own height function (PlanetNoise) on
## background threads once the player is in: a coarse chart of the whole planet first (a couple of
## seconds), a fine one after, and, when you stop on a close view, a chart of just that region (so
## close up it is sharp). A flat (equirectangular) map: east to the right, north up, the poles
## stretched along the edges; it wraps round east-west.
##
## Layers (buttons under the map, or the keys 1 to 7): the terrain as it looks, the elevation (with
## contour lines), the temperature, the rain, the biomes, the tectonic plates and the slope: the
## planet's own numbers made visible, a debug tool as much as a map. Under the cursor the exact
## numbers are listed (height, temperature, rain, biome, plate).

const ACTION := &"planet_map"
const PASSES: Array[Vector2i] = [Vector2i(320, 160), Vector2i(640, 320), Vector2i(1024, 512),
		Vector2i(2048, 1024)]
const DETAIL_MIN := 768 ## pixels across the close chart, at least (more for a big view)
const DETAIL_MAX := 2560
const START_ZOOM := 6.0
const MAX_ZOOM := 60.0
const MARGIN := 14.0

var planet: PlanetWorld

var _layer := PlanetChart.Layer.TERRAIN
var _cache: Dictionary = {} # layer -> {"whole": ImageTexture, "pass": int}: what was charted
var _retired: Array[PlanetChart] = [] # charts of a layer left behind, drawing out their threads
var _buttons: Array[Button] = []
var _hover: Label
var _time_row: HBoxContainer
var _season_slider: HSlider
var _rate_label: Label
var _drawn_at := -1.0 # the clock time the temperature chart on the screen is of
var _refresh_wait := 0.0
var _chart_time := 0.0
var _whole: ImageTexture # the whole planet, as sharp as it has got
var _whole_pass := -1 # the pass `_whole` is from (-1: none yet)
var _chart: PlanetChart # the chart being drawn, if any
var _chart_is_detail := false
var _detail: ImageTexture # a close chart of `_detail_rect` (fractions of the map)
var _detail_rect := Rect2()
var _wanted_rect := Rect2() # the region the next close chart is for
var _still := 0.0 # seconds the view has stayed as it is
var _last_view := Rect2()
var _view: Control
var _caption: Label
var _zoom := START_ZOOM
var _centre := Vector2(0.5, 0.5) # in map fractions (u east, v south)
var _dragging := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _started := false


func _ready() -> void:
	layer = 70
	visible = false
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_M
		InputMap.action_add_event(ACTION, key)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = MARGIN
	panel.offset_top = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_view = Control.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(400.0, 300.0)
	_view.clip_contents = true
	_view.draw.connect(_draw_view)
	column.add_child(_view)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var group := ButtonGroup.new()
	for index in PlanetChart.NAMES.size():
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, PlanetChart.NAMES[index]]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = index == 0
		button.pressed.connect(select_layer.bind(index))
		row.add_child(button)
		_buttons.append(button)
	_build_time_controls(column)
	_hover = Label.new()
	_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hover)
	_caption = Label.new()
	_caption.text = "Charting the planet..."
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_caption)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, 1.25)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, 0.8)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture: # a pinch on a trackpad
		var pinch := event as InputEventMagnifyGesture
		_zoom_at(pinch.position, clampf(pinch.factor, 0.5, 2.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture: # two fingers moving on a trackpad: the wheel
		var pan := event as InputEventPanGesture
		_zoom_at(get_viewport().get_mouse_position(), pow(1.25, -pan.delta.y))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var size := _visible_size()
		_centre -= Vector2(motion.relative.x / _view.size.x * size.x,
				motion.relative.y / _view.size.y * size.y)
		_clamp_centre()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var code := (event as InputEventKey).physical_keycode
		if code == KEY_R:
			_go_home()
			get_viewport().set_input_as_handled()
		elif code == KEY_EQUAL or code == KEY_KP_ADD: # the keyboard zooms too (+ and -)
			_zoom_at(_view.size * 0.5, 1.25)
			get_viewport().set_input_as_handled()
		elif code == KEY_MINUS or code == KEY_KP_SUBTRACT:
			_zoom_at(_view.size * 0.5, 0.8)
			get_viewport().set_input_as_handled()
		elif code >= KEY_1 and code < KEY_1 + PlanetChart.NAMES.size():
			select_layer(code - KEY_1)
			get_viewport().set_input_as_handled()


## Opens or closes the map (on the player's region).
func toggle() -> void:
	visible = not visible
	if planet != null and planet.surface != null:
		planet.surface.paused = visible and _started # (not while the world is still loading)
	if visible:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_go_home()
	else:
		Input.mouse_mode = _mouse_before
		_dragging = false


## The buttons that move time: the speed (backward too), a jump of a day or an eighth of a year, and
## a slider through the year, to watch the temperature (and the sun) change.
func _build_time_controls(column: VBoxContainer) -> void:
	_time_row = HBoxContainer.new()
	_time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_time_row)
	var title := Label.new()
	title.text = "Time:  "
	_time_row.add_child(title)
	for rate in [-1000, -100, -10, -1]:
		_time_button("%d×" % rate, func() -> void: planet.time_rate = float(rate))
	_time_button("pause", func() -> void: planet.time_rate = 0.0)
	for rate in [1, 10, 100, 1000]:
		_time_button("%d×" % rate, func() -> void: planet.time_rate = float(rate))
	_time_button("-day", func() -> void: planet.jump_time(-1.0))
	_time_button("+day", func() -> void: planet.jump_time(1.0))
	_time_button("-1/8 year", func() -> void: planet.jump_time(-planet.clock.year_days / 8.0))
	_time_button("+1/8 year", func() -> void: planet.jump_time(planet.clock.year_days / 8.0))
	var year := Label.new()
	year.text = "  year:"
	_time_row.add_child(year)
	_season_slider = HSlider.new()
	_season_slider.custom_minimum_size = Vector2(200.0, 0.0)
	_season_slider.max_value = 1.0
	_season_slider.step = 0.002
	_season_slider.focus_mode = Control.FOCUS_NONE
	_season_slider.value_changed.connect(func(value: float) -> void:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				planet.set_year_share(value))
	_time_row.add_child(_season_slider)
	_rate_label = Label.new()
	_time_row.add_child(_rate_label)


func _time_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	_time_row.add_child(button)


## Shows another layer (a PlanetChart.Layer): what was charted of it before comes back at once, the
## rest is charted again.
func select_layer(layer: int) -> void:
	if layer == _layer:
		return
	if _whole != null:
		_cache[_layer] = {"whole": _whole, "pass": _whole_pass}
	_layer = layer as PlanetChart.Layer
	_buttons[layer].set_pressed_no_signal(true)
	var kept: Dictionary = _cache.get(layer, {})
	_whole = kept.get("whole")
	_whole_pass = kept.get("pass", -1)
	_detail = null
	if _chart != null:
		_chart.cancel()
		_retired.append(_chart) # its threads finish on their own; the picture is thrown away
		_chart = null
	if _started and _whole_pass < _last_pass():
		_start_chart(_whole_pass + 1)


## Zooms to `zoom` (1: the whole planet) round the player.
func show_zoom(zoom: float) -> void:
	if not visible:
		toggle()
	_zoom = clampf(zoom, 1.0, MAX_ZOOM)
	_centre = _where_is_the_player().get("uv", Vector2(0.5, 0.5))
	_clamp_centre()


## Back to the player's region.
func _go_home() -> void:
	_zoom = START_ZOOM
	_centre = _where_is_the_player().get("uv", Vector2(0.5, 0.5))
	_clamp_centre()


## How many screen pixels one whole map width is at zoom 1: the whole planet just fits the view.
func _pixels_per_map() -> float:
	return minf(_view.size.x, _view.size.y * 2.0)


## The part of the map the view shows, as fractions of the map (more than 1 high or wide when the
## map is smaller than the view: the bars round it).
func _visible_size() -> Vector2:
	var pixels := _pixels_per_map() * _zoom
	return Vector2(_view.size.x / pixels, _view.size.y / (pixels * 0.5))


func _clamp_centre() -> void:
	var size := _visible_size()
	_centre.x = fposmod(_centre.x, 1.0) # the map wraps east-west
	if size.y >= 1.0:
		_centre.y = 0.5
	else:
		_centre.y = clampf(_centre.y, size.y * 0.5, 1.0 - size.y * 0.5)


## Zooms by `factor`, keeping the point of the map under the cursor where it is.
func _zoom_at(mouse: Vector2, factor: float) -> void:
	var local := mouse - _view.global_position
	var inside := Vector2(clampf(local.x / _view.size.x, 0.0, 1.0),
			clampf(local.y / _view.size.y, 0.0, 1.0))
	var before := _visible_size()
	var under := _centre - before * 0.5 + inside * before
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	var after := _visible_size()
	_centre = under - inside * after + after * 0.5
	_clamp_centre()


## Starts charting the map on background threads (a no-op without a window, and the second time).
func begin() -> void:
	if _started or planet == null or DisplayServer.get_name() == "headless":
		return
	_started = true
	_start_chart(0)


## The finest picture of the layer: the layers that follow the clock are charted again as time
## moves and cost more per pixel, so they stop one pass short.
func _last_pass() -> int:
	if _layer == PlanetChart.Layer.TEMPERATURE or _layer == PlanetChart.Layer.CLOUDS:
		return PASSES.size() - 2
	return PASSES.size() - 1


func _start_chart(pass_index: int) -> void:
	_chart = PlanetChart.new()
	_chart.size = PASSES[pass_index]
	_chart.layer = _layer
	_chart.clock = planet.clock.copy()
	_chart_time = planet.clock.time
	_chart_is_detail = false
	_chart.start(planet.noise)


func _exit_tree() -> void:
	if _chart != null:
		_chart.cancel()
		_chart.stop()
	for old in _retired:
		old.cancel()
		old.stop()


func _process(delta: float) -> void:
	for index in range(_retired.size() - 1, -1, -1):
		if _retired[index].finished():
			_retired[index].texture() # joins the threads, the picture is not wanted
			_retired.remove_at(index)
	if visible:
		_view.queue_redraw()
		_hover.text = _numbers_under_the_cursor()
		_season_slider.set_value_no_signal(planet.clock.year_share())
		var rate := "paused" if planet.time_rate == 0.0 else "%d×" % int(planet.time_rate)
		_rate_label.text = "   " + rate
		_refresh_temperature(delta)
	if _chart != null:
		if _chart.finished():
			_adopt_chart()
		elif visible and _whole_pass < 0:
			_caption.text = "Charting the planet...  %d %%" % int(100.0 * _chart.progress())
	# a close view is charted sharply as soon as there is a picture to look at: it does not wait for
	# the whole planet's last passes (those go on afterwards)
	var whole_is_drawing := _chart != null and not _chart_is_detail
	if visible and _whole_pass >= 0 and (_chart == null or whole_is_drawing):
		_maybe_chart_the_view(delta)


## The temperature and cloud layers show a moment: when time has moved on, they are charted again
## (the coarse chart only, a second or so), so they follow the seasons, the day and the winds.
func _refresh_temperature(delta: float) -> void:
	var moving := _layer == PlanetChart.Layer.TEMPERATURE or _layer == PlanetChart.Layer.CLOUDS
	if not moving or _chart != null or _whole_pass < 0:
		return
	_refresh_wait -= delta
	var moved := absf(planet.clock.time - _drawn_at)
	if _refresh_wait > 0.0 or moved < planet.clock.day_seconds * 0.04:
		return
	_refresh_wait = 0.4
	_whole_pass = -1
	_detail = null
	_start_chart(0)


func _adopt_chart() -> void:
	var texture := _chart.texture()
	if _chart_is_detail:
		_detail = texture
		_detail_rect = _chart.rect
		_chart = null
		if _whole_pass < _last_pass():
			_start_chart(_whole_pass + 1) # the passes the close view interrupted go on
		return
	_whole = texture
	_whole_pass += 1
	_drawn_at = _chart_time
	if _layer != PlanetChart.Layer.TEMPERATURE and _layer != PlanetChart.Layer.CLOUDS:
		_cache[_layer] = {"whole": _whole, "pass": _whole_pass}
	_chart = null
	if _whole_pass < _last_pass():
		_start_chart(_whole_pass + 1) # the fine chart replaces the coarse one when it is done


## When the view has stayed still on a close region, draws that region sharply.
func _maybe_chart_the_view(delta: float) -> void:
	var size := _visible_size()
	var view := Rect2(_centre - size * 0.5, size)
	if view.is_equal_approx(_last_view):
		_still += delta
	else:
		_still = 0.0
		_last_view = view
	# (the slow layers, drawn again as time moves, wait for a closer look)
	var close := 2.5 if _last_pass() < PASSES.size() - 1 else 1.4
	if _still < 0.5 or _zoom < close or _covered_by_detail(view):
		return
	var rect := Rect2(view.position - size * 0.25, size * 1.5) # a margin to pan in
	# the margin stops at the poles (east-west the map wraps, so x may run past 0 and 1)
	var top := maxf(rect.position.y, 0.0)
	rect = Rect2(rect.position.x, top, rect.size.x, minf(rect.end.y, 1.0) - top)
	if not rect.encloses(view):
		return # the view reaches over a pole: the whole planet chart will do
	if _chart != null: # a whole planet pass still drawing gives way to the close view
		_chart.cancel()
		_retired.append(_chart)
	_chart = PlanetChart.new()
	_chart.layer = _layer
	_chart.clock = planet.clock.copy()
	_chart.rect = rect
	# about one chart pixel and a quarter for every screen pixel of the 1.5 times wider chart, so a
	# close zoom stays sharp
	var across := clampi(int(_view.size.x * 1.5 * 1.25), DETAIL_MIN, DETAIL_MAX)
	_chart.size = Vector2i(across, int(across * rect.size.y / rect.size.x * 0.5))
	_chart_is_detail = true
	_chart.start(planet.noise)


func _covered_by_detail(view: Rect2) -> bool:
	return _detail != null and _detail_rect.encloses(view)


## The numbers of the planet under the mouse, as one line of text.
func _numbers_under_the_cursor() -> String:
	var local := _view.get_local_mouse_position()
	if local.x < 0.0 or local.y < 0.0 or local.x > _view.size.x or local.y > _view.size.y:
		return ""
	var size := _visible_size()
	var uv := Vector2(fposmod(_centre.x - size.x * 0.5 + local.x / _view.size.x * size.x, 1.0),
			_centre.y - size.y * 0.5 + local.y / _view.size.y * size.y)
	if uv.y < 0.0 or uv.y > 1.0:
		return ""
	var lat := (0.5 - uv.y) * PI
	var lon := uv.x * TAU - PI
	var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	var noise := planet.noise
	var ground := noise.height(dir.x, dir.y, dir.z)
	var plate := noise.tectonics.plate_at(dir)
	return "%.1f° %s %.1f° %s   height %d m   %.0f °C   rain %.2f   %s   plate %d (%s)" % [
			absf(rad_to_deg(lat)), "N" if lat >= 0.0 else "S", absf(rad_to_deg(lon)),
			"E" if lon >= 0.0 else "W", roundi(ground),
			noise.temperature_now(dir.x, dir.y, dir.z, maxf(ground, 0.0)), noise.climate.sample(dir).y,
			"sea" if ground < 0.0 else TerrainNoise.Biome.keys()[noise.biome(dir.x, dir.y, dir.z,
			ground, 0.1)].to_lower(), int(plate.x), "land" if plate.z > 0.5 else "ocean"]


func _uv_of(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return Vector2((lon + PI) / TAU, 0.5 - lat / PI)


## The player's place on the map: {"uv", "lat", "lon", "heading"} (empty without a player).
func _where_is_the_player() -> Dictionary:
	if planet == null or planet.target() == null:
		return {}
	var here := planet.planet_position().normalized()
	var east := Vector3(-here.z, 0.0, here.x).normalized()
	var north := east.cross(here)
	var heading := Vector2(0.0, -1.0)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var forward := planet.frame.rot.inverse() * (-camera.global_basis.z)
		heading = Vector2(forward.dot(east), -forward.dot(north)).normalized()
	return {"uv": _uv_of(here), "lat": rad_to_deg(asin(here.y)),
			"lon": rad_to_deg(atan2(here.z, here.x)), "heading": heading}


## Where a point of the map (fractions) is in the view (off the view when out of it).
func _on_screen(uv: Vector2) -> Vector2:
	var size := _visible_size()
	var left := _centre.x - size.x * 0.5
	var across := fposmod(uv.x - left, 1.0)
	var down := uv.y - (_centre.y - size.y * 0.5)
	if across > size.x or down < 0.0 or down > size.y:
		return Vector2(-1.0, -1.0)
	return Vector2(across / size.x * _view.size.x, down / size.y * _view.size.y)


func _draw_view() -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.02, 0.05, 0.12))
	var size := _visible_size()
	var view := Rect2(_centre - size * 0.5, size)
	if _covered_by_detail(view):
		_draw_part(_detail, _detail_rect, view)
	elif _whole != null:
		# the map wraps east-west: the view may need the end of the picture and then its start
		var first_u := fposmod(view.position.x, 1.0)
		var first_width := minf(size.x, 1.0 - first_u)
		_draw_part(_whole, Rect2(0.0, 0.0, 1.0, 1.0), Rect2(first_u, view.position.y, first_width,
				size.y))
		if first_width < size.x:
			_draw_part(_whole, Rect2(0.0, 0.0, 1.0, 1.0), Rect2(0.0, view.position.y,
					size.x - first_width, size.y), first_width)
	_draw_grid()
	_draw_legend()
	var player := _where_is_the_player()
	if player.is_empty():
		return
	var spot := _on_screen(player["uv"])
	if spot.x >= 0.0:
		_draw_arrow(spot, player["heading"])
	if _whole != null:
		var lat: float = player["lat"]
		var lon: float = player["lon"]
		var north_south := "N" if lat >= 0.0 else "S"
		var east_west := "E" if lon >= 0.0 else "W"
		var here := planet.planet_position().normalized()
		var hour := planet.clock.local_hour(here)
		_caption.text = ("%.1f° %s  %.1f° %s    altitude %d m    %02d:%02d    %s    "
				+ "[wheel, pinch, + -] zoom  [drag] move  [R] my region  [M] close") % [absf(lat),
				north_south, absf(lon), east_west, roundi(planet.altitude()), int(hour),
				int((hour - floorf(hour)) * 60.0), planet.season_text() + "  " + planet.weather_text]


## Draws the part `wanted` (map fractions) of `texture`, which shows `covers` (map fractions), where
## it belongs in the view (`offset_u`: how far into the view this part starts, in map fractions).
func _draw_part(texture: ImageTexture, covers: Rect2, wanted: Rect2, offset_u := 0.0) -> void:
	var size := _visible_size()
	var part := wanted.intersection(covers)
	if part.size.x <= 0.0 or part.size.y <= 0.0:
		return
	var tex := Vector2(texture.get_size())
	var source := Rect2((part.position - covers.position) / covers.size * tex,
			part.size / covers.size * tex)
	var view_top := _centre.y - size.y * 0.5
	var dest := Rect2((offset_u + part.position.x - wanted.position.x) / size.x * _view.size.x,
			(part.position.y - view_top) / size.y * _view.size.y,
			part.size.x / size.x * _view.size.x, part.size.y / size.y * _view.size.y)
	_view.draw_texture_rect_region(texture, dest, source)


## The scale of the layer (a bar and its two ends) in the corner of the map.
func _draw_legend() -> void:
	var labels := PlanetChart.scale_labels(_layer, planet.noise.relief)
	if labels.is_empty():
		return
	var origin := Vector2(18.0, _view.size.y - 34.0)
	var width := 260.0
	for step in int(width):
		_view.draw_rect(Rect2(origin + Vector2(float(step), 0.0), Vector2(1.0, 14.0)),
				PlanetChart.ramp(_layer, float(step) / width))
	_view.draw_rect(Rect2(origin, Vector2(width, 14.0)), Color.WHITE, false, 1.0)
	var font := ThemeDB.fallback_font
	_view.draw_string(font, origin + Vector2(0.0, -4.0), labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	_view.draw_string(font, origin + Vector2(width, -4.0), labels[1], HORIZONTAL_ALIGNMENT_RIGHT,
			-1, 14)
	_view.draw_string(font, origin + Vector2(width + 14.0, 12.0), PlanetChart.NAMES[_layer],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


func _draw_grid() -> void:
	var gap := 30 if _zoom < 3.0 else (10 if _zoom < 12.0 else 5)
	var line := Color(1.0, 1.0, 1.0, 0.18)
	for degrees in range(-90, 91, gap):
		var at := _on_screen(Vector2(_centre.x, 0.5 - float(degrees) / 180.0))
		if at.y >= 0.0:
			_view.draw_line(Vector2(0.0, at.y), Vector2(_view.size.x, at.y),
					line if degrees != 0 else Color(1.0, 1.0, 1.0, 0.4))
	for degrees in range(-180, 181, gap):
		var uv := (float(degrees) + 180.0) / 360.0
		var at := _on_screen(Vector2(fposmod(uv, 1.0), _centre.y))
		if at.x >= 0.0:
			_view.draw_line(Vector2(at.x, 0.0), Vector2(at.x, _view.size.y), line)


func _draw_arrow(spot: Vector2, heading: Vector2) -> void:
	var side := Vector2(-heading.y, heading.x)
	var points := PackedVector2Array([spot + heading * 13.0, spot - heading * 7.0 + side * 7.0,
			spot - heading * 7.0 - side * 7.0])
	_view.draw_colored_polygon(points, Color(1.0, 0.25, 0.2))
	_view.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]),
			Color.WHITE, 1.5)
