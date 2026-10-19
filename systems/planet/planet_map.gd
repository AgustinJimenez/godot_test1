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
const MIDDLE_DETAIL := 1280 ## the picture between the quick one and the sharp one
const MAX_ZOOM := 1500.0 ## a pixel of the sharpest chart is then about 15 m on an Earth
const START_ZOOM := MAX_ZOOM # the map opens as close as it goes, on the player
## the layers as the buttons and the keys 1.. list them (the Atlas first, the rest are extra)
const LAYER_ORDER := [PlanetChart.Layer.ATLAS, PlanetChart.Layer.TERRAIN,
		PlanetChart.Layer.ELEVATION, PlanetChart.Layer.TEMPERATURE, PlanetChart.Layer.RAIN,
		PlanetChart.Layer.BIOME, PlanetChart.Layer.PLATES, PlanetChart.Layer.SLOPE,
		PlanetChart.Layer.MEAN_TEMPERATURE, PlanetChart.Layer.CLOUDS, PlanetChart.Layer.SATELLITE]
const MARGIN := 14.0
const TILE_ZOOM := 2.0 ## from this zoom on the flat map is drawn from tiles
const FIRST_BIG_PASS := 3 ## the whole passes before this are short: they finish first

var planet: PlanetWorld

var _layer := PlanetChart.Layer.ATLAS # (the simple map to read: the others are extra modes)
var _cache: Dictionary = {} # layer -> {"whole": ImageTexture, "pass": int}: what was charted
var _retired: Array[PlanetChart] = [] # charts of a layer left behind, drawing out their threads
var _modes: OptionButton # the layers, as a dropdown (the Atlas first)
var _hover: Label
var _time_bar: PlanetMapTimeBar
var _drawn_at := -1.0 # the clock time the temperature chart on the screen is of
var _refresh_wait := 0.0
var _chart_time := 0.0
var _whole: ImageTexture # the whole planet, as sharp as it has got
var _whole_pass := -1 # the pass `_whole` is from (-1: none yet)
var _chart: PlanetChart # the chart being drawn, if any
var _chart_is_detail := false
var _detail: ImageTexture # a close chart of `_detail_rect` (fractions of the map)
var _detail_rect := Rect2()
var _revealed := false # the picture is sharp (until then a loading note is drawn over the map)
var _unsharp_time := 0.0 # seconds the map has been unsharp since it was opened
var _detail_preview := false # the close chart in `_detail` is the quick small one
var _detail_full := 0 # pixels across of the sharp chart that follows a quick preview (0: none)
var _wanted_rect := Rect2() # the region the next close chart is for
var _still := 0.0 # seconds the view has stayed as it is
var _last_view := Rect2()
var _view: Control
var _globe: PlanetMapGlobe # the map as a small planet in 3D (G)
var _globe_button: Button
var _globe_mode := false
var _caption: Label
var _labels: PlanetMapLabels # the names of the seas and lands (built on the first look)
var _globe_tiles := -1 # what the globe's picture was made from, to see when it needs a new one
var _globe_level := -1
var _globe_view := Rect2()
var _disk: PlanetMapCache # what was charted in an earlier run of this world
var _tiles: PlanetMapTiles # the close views as tiles (from TILE_ZOOM on, on the flat map)
var warm_up := false ## the world sets it: the map is all charted (black meanwhile) before it shows
var _warming := false
var _warm_queue: Array[int] = [] # the layers still to get a first picture
var _warm_total := 1
var _warm_layers_done := 0
var _warm_close := 0 # 0 the close view of the start is not charted yet, 1 it has been started
var _chart_layer := PlanetChart.Layer.TERRAIN # the layer of the chart in hand (maybe not shown)
var _chart_ms := 0 # when the chart in hand was started
var _logged_view := Vector3(-1.0, -1.0, -1.0) # (zoom, centre) last logged
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
	_globe = PlanetMapGlobe.new()
	_globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_globe.custom_minimum_size = Vector2(400.0, 300.0)
	_globe.visible = false
	_globe.zoomed.connect(_zoom_by)
	_globe.moved.connect(_look_from_globe)
	column.add_child(_globe)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_modes = OptionButton.new()
	_modes.focus_mode = Control.FOCUS_NONE
	_modes.custom_minimum_size = Vector2(190.0, 0.0)
	for position in LAYER_ORDER.size():
		var key_name := str((position + 1) % 10) if position < 10 else " "
		_modes.add_item("%s  %s" % [key_name, PlanetChart.NAMES[LAYER_ORDER[position]]], position)
	_modes.select(LAYER_ORDER.find(_layer))
	_modes.item_selected.connect(func(position: int) -> void: select_layer(LAYER_ORDER[position]))
	row.add_child(_modes)
	_globe_button = Button.new()
	_globe_button.text = "G  Globe"
	_globe_button.toggle_mode = true
	_globe_button.focus_mode = Control.FOCUS_NONE
	_globe_button.toggled.connect(_set_globe)
	row.add_child(_globe_button)
	_time_bar = PlanetMapTimeBar.new(planet)
	column.add_child(_time_bar)
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
	if visible and event.is_action_pressed(&"pause"): # Esc closes the map (not the menu behind it)
		toggle()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.physical_keycode == KEY_G:
		_globe_button.button_pressed = not _globe_mode
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and not _over_the_pane(click.position):
		if not click.pressed:
			_dragging = false
			_globe.release()
		return # (a click on a button or the bars is theirs)
	if _globe_mode and not (event is InputEventKey) and _globe.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			PlanetMapLog.line_every("input", 0.1, "input: wheel up (zoom in)")
			_zoom_at(button.position, 1.25)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			PlanetMapLog.line_every("input", 0.1, "input: wheel down (zoom out)")
			_zoom_at(button.position, 0.8)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if _dragging != button.pressed:
				PlanetMapLog.line("input: drag " + ("starts" if button.pressed else "ends"))
			_dragging = button.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture: # a pinch on a trackpad
		var pinch := event as InputEventMagnifyGesture
		PlanetMapLog.line_every("input", 0.1, "input: pinch x%.2f" % pinch.factor)
		_zoom_at(pinch.position, clampf(pinch.factor, 0.5, 2.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture: # two fingers moving on a trackpad: the wheel
		var pan := event as InputEventPanGesture
		PlanetMapLog.line_every("input", 0.1, "input: two fingers %.2f" % pan.delta.y)
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
		PlanetMapLog.line("input: key " + OS.get_keycode_string(code))
		if code == KEY_R:
			_go_home()
			if _globe_mode:
				_globe.look_at_direction(planet.planet_position().normalized())
			get_viewport().set_input_as_handled()
		elif code == KEY_EQUAL or code == KEY_KP_ADD: # the keyboard zooms too (+ and -)
			_zoom_at(_view.size * 0.5, 1.25)
			get_viewport().set_input_as_handled()
		elif code == KEY_MINUS or code == KEY_KP_SUBTRACT:
			_zoom_at(_view.size * 0.5, 0.8)
			get_viewport().set_input_as_handled()
		elif code >= KEY_1 and code <= KEY_9 and code - KEY_1 < LAYER_ORDER.size():
			select_layer(LAYER_ORDER[code - KEY_1]) # (1 is the Atlas, then the extra modes)
			get_viewport().set_input_as_handled()
		elif code == KEY_0 and LAYER_ORDER.size() > 9:
			select_layer(LAYER_ORDER[9])
			get_viewport().set_input_as_handled()


## Opens or closes the map (on the player's region).
func toggle() -> void:
	visible = not visible
	if visible:
		PlanetMapLog.begin("layer %s, globe %s" % [PlanetChart.NAMES[_layer], _globe_mode])
	else:
		PlanetMapLog.end()
	if planet != null and planet.surface != null:
		planet.surface.paused = visible and _started # (not while the world is still loading)
	if visible:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_go_home()
		_revealed = false # (the loading note until the sharp picture of this view is ready)
		_unsharp_time = 0.0
		if planet != null:
			_globe.look_at_direction(planet.planet_position().normalized())
	else:
		Input.mouse_mode = _mouse_before
		_dragging = false


## Shows another layer (a PlanetChart.Layer): what was charted of it before comes back at once, the
## rest is charted again.
func select_layer(layer: int) -> void:
	if layer == _layer or _warming:
		return
	PlanetMapLog.line("layer %s -> %s (picture kept: %s)" % [PlanetChart.NAMES[_layer],
			PlanetChart.NAMES[layer], _cache.has(layer)])
	if _whole != null:
		_cache[_layer] = {"whole": _whole, "pass": _whole_pass}
	_layer = layer as PlanetChart.Layer
	_modes.select(LAYER_ORDER.find(layer))
	var kept: Dictionary = _cache.get(layer, {})
	_whole = kept.get("whole")
	_whole_pass = kept.get("pass", -1)
	_detail = null
	_detail_full = 0
	_revealed = false # (a new layer: with the loading note until it is sharp)
	_unsharp_time = 0.0
	if _chart != null:
		PlanetMapLog.line("chart given up (the layer changed)")
		_chart.cancel()
		_retired.append(_chart) # its threads finish on their own; the picture is thrown away
		_chart = null
	if _started and _whole_pass < _last_pass():
		_start_chart(_whole_pass + 1)


## The layers that show a moment (they are charted again as time moves on).
static func _is_moving(layer: int) -> bool:
	return layer in [PlanetChart.Layer.TEMPERATURE, PlanetChart.Layer.CLOUDS,
			PlanetChart.Layer.SATELLITE]


## The unit direction of the planet at the map's point `uv`.
static func _direction_of(uv: Vector2) -> Vector3:
	var lat := (0.5 - uv.y) * PI
	var lon := uv.x * TAU - PI
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))


## The globe turned: the map's centre follows where it looks (so the close chart is drawn there).
func _look_from_globe(dir: Vector3) -> void:
	_centre = Vector2((atan2(dir.z, dir.x) + PI) / TAU, 0.5 - asin(clampf(dir.y, -1.0, 1.0)) / PI)
	_clamp_centre()


## The globe's wheel and pinch zoom the map (the same zoom as the flat one).
func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	_clamp_centre()


## Shows the map as a small planet in 3D (on) or flat (off).
func _set_globe(on: bool) -> void:
	PlanetMapLog.line("globe %s" % ("on" if on else "off"))
	_globe_mode = on
	_view.visible = not on
	_globe.visible = on
	if on:
		_globe.look_at_direction(_direction_of(_centre)) # (where the flat map looks)

## Zooms to `zoom` (1: the whole planet) round the player.
func show_zoom(zoom: float) -> void:
	if not visible:
		toggle()
	PlanetMapLog.line("show zoom %.1f on the player" % zoom)
	_zoom = clampf(zoom, 1.0, MAX_ZOOM)
	_centre = _where_is_the_player().get("uv", Vector2(0.5, 0.5))
	_clamp_centre()


## Back to the player's region.
func _go_home() -> void:
	PlanetMapLog.line("home: the player's region at the closest zoom")
	_zoom = START_ZOOM
	_centre = _where_is_the_player().get("uv", Vector2(0.5, 0.5))
	_clamp_centre()


## True when the screen point is on the map itself (the flat view or the globe), not on the buttons.
func _over_the_pane(point: Vector2) -> bool:
	var pane: Control = _globe if _globe_mode else _view
	return pane.get_global_rect().has_point(point)


## The size of what shows the map (the flat view, or the globe).
func _pane() -> Vector2:
	var pane := _globe.size if _globe_mode else _view.size
	return pane.max(Vector2(64.0, 64.0))


## How many screen pixels one whole map width is at zoom 1: the whole planet just fits the view.
func _pixels_per_map() -> float:
	var pane := _pane()
	return minf(pane.x, pane.y * 2.0)


## The part of the map the view shows, as fractions of the map (more than 1 high or wide when the
## map is smaller than the view: the bars round it).
func _visible_size() -> Vector2:
	var pixels := _pixels_per_map() * _zoom
	var pane := _pane()
	return Vector2(pane.x / pixels, pane.y / (pixels * 0.5))


func _clamp_centre() -> void:
	var size := _visible_size()
	_centre.x = fposmod(_centre.x, 1.0) # the map wraps east-west
	# past a pole is the other side of the planet: the map goes on, upside down, half a turn on
	_centre.y = fposmod(_centre.y + 0.5, 2.0) - 0.5


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
	_tiles = PlanetMapTiles.new(planet.noise)
	_disk = PlanetMapCache.new(planet.settings)
	_tiles.disk = _disk
	if planet.has_signal(&"world_changed"):
		planet.world_changed.connect(world_changed)
	if warm_up:
		_warming = true
		for layer in PlanetChart.NAMES.size():
			if layer != _layer:
				_warm_queue.append(layer)
		_warm_total = maxi(_warm_queue.size(), 1)
		PlanetMapLog.line("warm-up: the whole map is charted before it is shown")
	_start_chart(0)


## The finest picture of the layer: the layers that follow the clock are charted again as time
## moves and cost more per pixel, so they stop one pass short.
func _last_pass() -> int:
	if _is_moving(_layer):
		return PASSES.size() - 2
	return PASSES.size() - 1


func _start_chart(pass_index: int) -> void:
	var kept := _disk.load_whole(int(_layer), PASSES[pass_index].x) if _disk != null else null
	if kept != null: # charted in an earlier run: no charting
		_whole = kept
		_whole_pass = pass_index
		_chart = null
		if not _is_moving(_layer):
			_cache[_layer] = {"whole": _whole, "pass": _whole_pass}
		if _whole_pass < _last_pass():
			_start_chart(_whole_pass + 1)
		return
	_chart = PlanetChart.new()
	_chart.size = PASSES[pass_index]
	_chart.layer = _layer
	_chart.use_gpu = true # (the game is paused while the map is open: the GPU is free)
	_chart.clock = planet.clock.copy()
	_chart_time = planet.clock.time
	_chart_is_detail = false
	_chart_layer = _layer
	_chart_ms = Time.get_ticks_msec()
	PlanetMapLog.line("chart whole pass %d: %d px, %s" % [pass_index, _chart.size.x,
			PlanetChart.NAMES[_layer]])
	_chart.start(planet.noise)


func _exit_tree() -> void:
	if _tiles != null:
		_tiles.stop()
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
		_drop_a_stale_chart()
		_log_the_view()
		_serve_the_tiles()
		if not _warming:
			_update_reveal(delta)
		_view.queue_redraw()
		if _globe_mode:
			_hover.text = "Drag to turn the planet, wheel to come closer, G: the flat map"
			_globe.set_chart(_whole)
			_set_the_globe_detail()
			_globe.set_zoom(_zoom)
			_globe.set_sun(planet.clock.sun_in_body())
			var here := Vector3.ZERO
			if planet != null and planet.target() != null:
				here = planet.planet_position().normalized()
			_globe.set_pin(here)
		else:
			_hover.text = _numbers_under_the_cursor()
		_time_bar.refresh()
		_refresh_temperature(delta)
	if _chart != null:
		if _chart.finished():
			_adopt_chart()
		elif visible and _whole_pass < 0:
			_caption.text = "Charting the planet...  %d %%" % int(100.0 * _chart.progress())
	# a close view is charted sharply as soon as there is a picture to look at: it does not wait for
	# the whole planet's last passes (those go on afterwards)
	if _warming:
		_drive_the_warm_up()
	var whole_is_drawing := _chart != null and not _chart_is_detail
	var by_tiles := _tile_mode()
	if visible and not _warming and not by_tiles and _whole_pass >= 0 \
			and (_chart == null or whole_is_drawing):
		_maybe_chart_the_view(delta)


## The temperature and cloud layers show a moment: when time has moved on, they are charted again
## (the coarse chart only, a second or so), so they follow the seasons, the day and the winds.
## True when the flat map is drawn from tiles (close enough, and not the globe).
func _tile_mode() -> bool:
	return _tiles != null and _zoom >= TILE_ZOOM


func _tile_level() -> int:
	return PlanetMapTiles.level_for(_pixels_per_map() * _zoom)


## The part of the map the tiles are asked for: the view and a margin to pan in.
func _tile_view() -> Rect2:
	var size := _visible_size()
	if _warming: # (the start: just what is seen)
		return Rect2(_centre - size * 0.5, size)
	return Rect2(_centre - size * 0.6, size * 1.2)


## Asks for the tiles of the view and lets the chart in hand go on (a step of the tile cache).
func _serve_the_tiles() -> void:
	if _tiles == null:
		return
	if not _tile_mode():
		_tiles.ask(Rect2(), 0) # nothing wanted (the chart in hand is given up)
		return
	if _warming and _whole_pass < _last_pass():
		return # (the whole planet's passes come first: nothing else uses the CPU)
	_tiles.layer = _layer
	_tiles.clock = planet.clock
	_tiles.ask(_tile_view(), _tile_level(), _tile_view_beyond())
	_tiles.step()


## Gives the globe the sharp picture it can have: the tiles round where it looks, put together
## (the same tiles as the flat map: changing to the globe charts nothing again).
func _set_the_globe_detail() -> void:
	if not _tile_mode():
		_globe.set_detail(null, Rect2())
		return
	var level := _tile_level()
	var view := _tile_view()
	var shown := _tiles.share(view, level).x
	if shown == _globe_tiles and level == _globe_level and view.position.distance_to(
			_globe_view.position) < view.size.x * 0.05:
		return # (nothing new since the last picture)
	var made := _tiles.compose(view, level)
	_globe_tiles = shown
	_globe_level = level
	_globe_view = view
	if made.is_empty():
		_globe.set_detail(null, Rect2())
		return
	PlanetMapLog.line_every("globe", 0.5, "globe detail: %d tiles of level %d put together" % [
			shown, level])
	_globe.set_detail(made["texture"], made["rect"])


## The whole planet's picture under the view (the map wraps east-west).
func _draw_whole(view: Rect2, size: Vector2) -> void:
	var rows := view.size.y # (a view taller than the screen is the part beyond a pole, mirrored)
	var drawn := 0.0 # the map goes round east-west: its copies are drawn until the view is full
	while drawn < size.x - 0.00001:
		var first_u := fposmod(view.position.x + drawn, 1.0)
		var width := minf(size.x - drawn, 1.0 - first_u)
		_draw_part(_whole, Rect2(0.0, 0.0, 1.0, 1.0), Rect2(first_u, view.position.y, width, rows),
				drawn)
		drawn += width


## The tiles over it (each from its own picture, or its finest charted ancestor).
func _draw_tiles(view: Rect2, size: Vector2) -> void:
	_tiles.draw(_view, view, size, _tile_level())


## The warm-up: the whole planet's passes, then the sharp close view where the player stands, then a
## first picture of every other layer, one after the other; then the map is shown.
func _drive_the_warm_up() -> void:
	if _chart != null:
		return
	var size := _visible_size()
	var view := Rect2(_centre - size * 0.5, size)
	if _whole_pass < _last_pass():
		_start_chart(_whole_pass + 1)
	elif _tile_mode() and not _tiles.covers(view, _tile_level()):
		_warm_close = 1 # (the tiles of the start view are being charted)
		return
	elif not _tile_mode() and _warm_close == 0 and not _sharply_covered(view):
		_warm_close = 1
		_chart_close_view(view, size)
	elif not _warm_queue.is_empty():
		_start_warm_layer(_warm_queue.pop_front())
	else:
		_warming = false
		_revealed = true
		PlanetMapLog.line("warm-up done: the map is ready")


## Charts a first (1024 px) picture of `layer` for later, without showing it.
func _start_warm_layer(layer: int) -> void:
	var kept := _disk.load_whole(layer, PASSES[2].x) if _disk != null else null
	if kept != null:
		_cache[layer] = {"whole": kept, "pass": 2}
		_warm_layers_done += 1
		return
	_chart = PlanetChart.new()
	_chart.layer = layer as PlanetChart.Layer
	_chart.size = PASSES[2]
	_chart.use_gpu = true
	_chart.clock = planet.clock.copy()
	_chart_layer = layer as PlanetChart.Layer
	_chart_is_detail = false
	_chart_ms = Time.get_ticks_msec()
	PlanetMapLog.line("warm-up: first picture of the %s layer" % PlanetChart.NAMES[layer])
	_chart.start(planet.noise)


## How far the warm-up is (0..1): the whole passes, the close view, the other layers.
func _warm_progress() -> float:
	var whole := clampf(float(_whole_pass + 1) / float(_last_pass() + 1), 0.0, 1.0) * 0.4
	var close := 0.0
	if _tile_mode():
		var have := _tiles.share(_tile_view(), _tile_level())
		close = 0.3 * float(have.x) / float(maxi(have.y, 1))
	elif _warm_close > 0:
		close = 0.1
		if _detail != null:
			close = 0.2 if _detail_preview else 0.3
	return whole + close + float(_warm_layers_done) / float(_warm_total) * 0.3


func _log_the_view() -> void:
	var now := Vector3(_zoom, _centre.x, _centre.y)
	if not now.is_equal_approx(_logged_view):
		PlanetMapLog.line_every("view", 0.25, "view: zoom %.1f, centre %.4f, %.4f" % [
				_zoom, now.y, now.z])
		_logged_view = now


func _refresh_temperature(delta: float) -> void:
	if not _is_moving(_layer) or _chart != null or _whole_pass < 0:
		return
	_refresh_wait -= delta
	var moved := absf(planet.clock.time - _drawn_at)
	if _refresh_wait > 0.0 or moved < planet.clock.day_seconds * 0.04:
		return
	_refresh_wait = 0.4
	if _tiles != null:
		_tiles.forget(int(_layer))
	PlanetMapLog.line("time moved: charting the %s layer again" % PlanetChart.NAMES[_layer])
	_whole_pass = -1
	_detail = null
	_detail_full = 0
	_start_chart(0)


func _adopt_chart() -> void:
	if not _chart_is_detail and _chart_layer != _layer: # a layer charted ahead (the warm-up)
		var ahead := _chart.texture()
		_cache[_chart_layer] = {"whole": ahead, "pass": 2}
		if _disk != null:
			_disk.save_whole(int(_chart_layer), PASSES[2].x, ahead)
		PlanetMapLog.line("chart done: first picture of the %s layer in %d ms" % [
				PlanetChart.NAMES[_chart_layer], Time.get_ticks_msec() - _chart_ms])
		_chart = null
		_warm_layers_done += 1
		return
	var texture := _chart.texture()
	PlanetMapLog.line("chart done: %s in %d ms" % ["close view" if _chart_is_detail
			else "whole pass %d" % (_whole_pass + 1), Time.get_ticks_msec() - _chart_ms])
	if _chart_is_detail:
		_detail = texture
		_detail_preview = _detail_full > 0
		_detail_rect = _chart.rect
		var rect := _chart.rect
		var done_width := _chart.size.x
		_chart = null
		if _detail_full > 0: # a preview is up: now a better one over the same region
			var across := _detail_full
			if done_width < MIDDLE_DETAIL and across > MIDDLE_DETAIL:
				_start_detail(rect, MIDDLE_DETAIL) # (still a preview: the sharp one follows)
				return
			_detail_full = 0
			_start_detail(rect, across)
			return
		if _whole_pass < _last_pass():
			_start_chart(_whole_pass + 1) # the passes the close view interrupted go on
		return
	_whole = texture
	_whole_pass += 1
	if _disk != null and not _is_moving(_layer):
		_disk.save_whole(int(_layer), PASSES[_whole_pass].x, texture)
	_drawn_at = _chart_time
	if not _is_moving(_layer):
		_cache[_layer] = {"whole": _whole, "pass": _whole_pass}
	_chart = null
	if _whole_pass < _last_pass():
		_start_chart(_whole_pass + 1) # the fine chart replaces the coarse one when it is done


## When the view has stayed still on a close region, draws that region sharply.
## A close chart of a place the view has left is no use: it is given up (the threads are free for
## the next view).
func _drop_a_stale_chart() -> void:
	if _chart == null or not _chart_is_detail:
		return
	var size := _visible_size()
	if _chart.rect.encloses(Rect2(_centre - size * 0.5, size)):
		return
	PlanetMapLog.line("close chart given up: the view moved out of it")
	_chart.cancel()
	_retired.append(_chart)
	_chart = null
	_detail_full = 0


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
	if _still < 0.5 or _zoom < close or _sharply_covered(view):
		return
	if _chart != null and not _chart_is_detail and _whole_pass + 1 < FIRST_BIG_PASS:
		return # the short whole passes (under half a second) finish first: a zoom out shows them
	_chart_close_view(view, size)


## Starts the close chart of `view` (a margin round it to pan in): false when the view reaches
## over a pole (the whole planet's chart will do).
func _chart_close_view(view: Rect2, size: Vector2) -> bool:
	var rect := Rect2(view.position - size * 0.25, size * 1.5)
	# the margin stops at the poles (east-west the map wraps, so x may run past 0 and 1)
	var top := maxf(rect.position.y, 0.0)
	rect = Rect2(rect.position.x, top, rect.size.x, minf(rect.end.y, 1.0) - top)
	if not rect.encloses(view):
		return false
	PlanetMapLog.line("view still at zoom %.1f: charting it (%s)" % [_zoom,
			"a pass gives way" if _chart != null else "free"])
	if _chart != null: # a whole planet pass still drawing gives way to the close view
		_chart.cancel()
		_retired.append(_chart)
	# about one chart pixel and a quarter for every screen pixel of the 1.5 times wider chart, so a
	# close zoom stays sharp; a quarter of that size comes first (a sixteenth of the time) so the
	# view is better than the whole planet's picture within a second
	var across := clampi(int(_pane().x * 1.5 * 1.25), DETAIL_MIN, DETAIL_MAX)
	if _warming: # (nobody looks at a preview behind a black screen: straight to the sharp one)
		_detail_full = 0
		_start_detail(rect, across)
		return true
	_detail_full = across
	_start_detail(rect, maxi(across / 4, 256))
	return true


## Charts `rect` (fractions of the map) `across` pixels wide, the close view.
func _start_detail(rect: Rect2, across: int) -> void:
	_chart = PlanetChart.new()
	_chart.layer = _layer
	_chart.clock = planet.clock.copy()
	_chart.rect = rect
	_chart.size = Vector2i(across, int(across * rect.size.y / rect.size.x * 0.5))
	_chart_is_detail = true
	_chart_ms = Time.get_ticks_msec()
	PlanetMapLog.line("chart close view (%s): %dx%d, rect %s, %s" % [
			"preview" if _detail_full > 0 else "sharp", _chart.size.x, _chart.size.y, rect,
			PlanetChart.NAMES[_layer]])
	_chart.start(planet.noise)


func _covered_by_detail(view: Rect2) -> bool:
	return _detail != null and _detail_rect.encloses(view)


## True when the close chart covers the view AND has about a pixel for every screen pixel (one
## made at a lower zoom contains the view too, but would only be a blur).
func _sharply_covered(view: Rect2) -> bool:
	if not _covered_by_detail(view):
		return false
	var chart_pixels := float(_detail.get_width()) / _detail_rect.size.x
	var screen_pixels := _pane().x / view.size.x
	return chart_pixels >= screen_pixels * 0.7


## The numbers of the planet under the mouse, as one line of text.
func _numbers_under_the_cursor() -> String:
	var local := _view.get_local_mouse_position()
	if local.x < 0.0 or local.y < 0.0 or local.x > _view.size.x or local.y > _view.size.y:
		return ""
	var size := _visible_size()
	var uv := Vector2(fposmod(_centre.x - size.x * 0.5 + local.x / _view.size.x * size.x, 1.0),
			_centre.y - size.y * 0.5 + local.y / _view.size.y * size.y)
	if uv.y < 0.0: # beyond the north pole: the other side of the planet
		uv = Vector2(fposmod(uv.x + 0.5, 1.0), -uv.y)
	elif uv.y > 1.0:
		uv = Vector2(fposmod(uv.x + 0.5, 1.0), 2.0 - uv.y)
	uv.y = clampf(uv.y, 0.0, 1.0)
	return PlanetMapOverlay.describe(planet.noise, uv)


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


## True when the picture is as sharp as it will get for this view: the close chart (not its quick
## preview) covers the view, or every pass of the whole planet is done.
func _sharp_enough(view: Rect2) -> bool:
	if _tile_mode():
		return _tiles.covers(view, _tile_level())
	if _sharply_covered(view) and not _detail_preview:
		return true
	if _whole == null or _zoom >= 2.5:
		return false
	# the whole planet's picture is sharp enough once it has about half a pixel for every screen
	# pixel (a middle pass does at far zooms: no waiting for the last, slowest one)
	var screen_width := _pixels_per_map() * _zoom
	return float(_whole.get_width()) >= screen_width * 0.4 or _whole_pass >= _last_pass()


func _draw_loading() -> void:
	if not _revealed:
		PlanetMapOverlay.draw_loading(_view, _chart.progress() if _chart != null else -1.0)


## Lifts the note when the picture is sharp enough (or, for a view the close chart cannot cover
## such as one over a pole, once the whole planet is charted and a few seconds have passed).
func _update_reveal(delta: float) -> void:
	var size := _visible_size()
	var all_done := _whole != null and _whole_pass >= _last_pass()
	if _sharp_enough(Rect2(_centre - size * 0.5, size)):
		if not _revealed:
			PlanetMapLog.line("the picture is sharp: the loading note is gone")
		_revealed = true
		_unsharp_time = 0.0
		return
	if _revealed:
		PlanetMapLog.line("the view is not sharp: the loading note is back (zoom %.1f)" % _zoom)
	_revealed = false # (zooming in on a place only charted blurrily brings the note back)
	_unsharp_time += delta
	if all_done and _unsharp_time > 6.0:
		PlanetMapLog.line("6 s unsharp with every pass done: the note is dropped")
		_revealed = true


func _draw_view() -> void:
	if _warming: # the map is not shown until it is all charted: black and how far it is
		_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color.BLACK)
		var font := ThemeDB.fallback_font
		var text := "Charting the planet...  %d %%" % int(100.0 * _warm_progress())
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x
		_view.draw_string(font, (_view.size - Vector2(width, -8.0)) * 0.5, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.85, 0.9, 1.0))
		return
	var size := _visible_size()
	var view := Rect2(_centre - size * 0.5, size)
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.02, 0.05, 0.12))
	_draw_beyond_the_poles(view, size)
	if _tile_mode() and _whole != null:
		_draw_whole(view, size)
		_draw_tiles(view, size)
	elif _covered_by_detail(view):
		_draw_part(_detail, _detail_rect, view)
	elif _whole != null:
		_draw_whole(view, size)
	PlanetMapOverlay.draw_grid(_view, _zoom, _centre, _visible_size(), _on_screen)
	_draw_names()
	PlanetMapOverlay.draw_legend(_view, _layer, planet.noise.relief)
	if _layer == PlanetChart.Layer.ATLAS: # the atlas is an old map: a burnt frame round it
		PlanetMapOverlay.draw_parchment_frame(_view)
	_draw_loading()
	var player := _where_is_the_player()
	if player.is_empty():
		return
	var spot := _on_screen(player["uv"])
	if spot.x >= 0.0:
		PlanetMapOverlay.draw_arrow(_view, spot, player["heading"])
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


## Beyond the north and south edges the map goes on: over a pole is the other side of the planet,
## 180 degrees of longitude away, seen upside down. The picture is drawn again half a map to the
## east and mirrored in the edge it goes over.
func _draw_beyond_the_poles(view: Rect2, size: Vector2) -> void:
	for edge: float in [0.0, 1.0]:
		var reach := -view.position.y if edge == 0.0 else view.end.y - 1.0 # how far beyond the edge
		if reach <= 0.0 or _whole == null:
			continue
		# the part of the map that shows there, mirrored: as deep into the map as the view goes beyond
		var top := 0.0 if edge == 0.0 else 1.0 - reach
		var shifted := Rect2(view.position.x + 0.5, minf(top, view.position.y), size.x,
				maxf(size.y, reach + absf(top - minf(top, view.position.y))))
		var at := (edge - view.position.y) / size.y * _view.size.y # (the edge on the screen)
		_view.draw_set_transform(Vector2(0.0, 2.0 * at), 0.0, Vector2(1.0, -1.0))
		_draw_whole(shifted, size)
		if _tile_mode():
			_tiles.draw(_view, Rect2(view.position + Vector2(0.5, 0.0), size), size, _tile_level(), shifted)
		_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The parts beyond the poles that tiles are needed for (as they are in the map).
func _tile_view_beyond() -> Array[Rect2]:
	var size := _visible_size()
	var view := Rect2(_centre - size * 0.5, size)
	var out: Array[Rect2] = []
	if view.position.y < 0.0:
		out.append(Rect2(view.position.x + 0.5 - size.x * 0.1, 0.0, size.x * 1.2,
				minf(-view.position.y * 1.2, 1.0)))
	if view.end.y > 1.0:
		var depth := minf((view.end.y - 1.0) * 1.2, 1.0)
		out.append(Rect2(view.position.x + 0.5 - size.x * 0.1, 1.0 - depth, size.x * 1.2, depth))
	return out


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


## Something in the world changed around `area` (map fractions: x east, y south): the tiles that
## touch it are forgotten and charted again when looked at, and the whole-planet pictures (which
## showed the old state) are charted again behind the current one. Rare events only (a fire, an
## impact, a building): the map is not meant to follow real-time changes.
func world_changed(area: Rect2) -> void:
	if _tiles == null:
		return
	var gone := _tiles.invalidate(area)
	if _disk != null:
		_disk.forget_whole()
	_cache.clear()
	PlanetMapLog.line("the world changed at %s: %d tiles forgotten, the whole pictures again" % [
			area, gone])
	if _started and not _warming:
		if _chart != null:
			_chart.cancel()
			_retired.append(_chart)
		_whole_pass = -1
		_start_chart(0)


## The same, for a place on the planet: the unit direction, the radius of the change in metres.
func world_changed_at(direction: Vector3, radius_metres: float) -> void:
	var uv := _uv_of(direction.normalized())
	var half := Vector2(radius_metres / (planet.settings.radius * TAU),
			radius_metres / (planet.settings.radius * PI))
	world_changed(Rect2(uv - half, half * 2.0))


## The names of the seas and lands: built on the first look, drawn while the view is far.
func _draw_names() -> void:
	if _zoom > 6.0 or planet == null or planet.noise == null:
		return
	if _labels == null:
		_labels = PlanetMapLabels.new()
		_labels.build(planet.noise)
	PlanetMapOverlay.draw_names(_view, _labels, _zoom, _on_screen, _layer == PlanetChart.Layer.ATLAS)


## Opens the map as the 3D globe (or the flat map).
func show_globe(on := true) -> void:
	if not visible:
		toggle()
	_globe_button.button_pressed = on
