class_name PlanetMapOverlay
extends RefCounted
## What the map draws over its picture: the legend of the layer's colours, the names of the seas
## and lands, the grid of latitude and longitude, and the arrow where the player stands. All of
## them draw on the map's `view` control; `on_screen` turns a map point (fractions) into a point
## of the view (off the view when it is out of it).


## The scale of the layer (a bar, its two ends and, for the temperature, ticks) in the corner.
static func draw_legend(view: Control, layer: int, relief: float) -> void:
	var labels := PlanetChart.scale_labels(layer as PlanetChart.Layer, relief)
	if labels.is_empty():
		return
	var origin := Vector2(18.0, view.size.y - 34.0)
	var width := 260.0
	for step in int(width):
		view.draw_rect(Rect2(origin + Vector2(float(step), 0.0), Vector2(1.0, 14.0)),
				PlanetChart.ramp(layer as PlanetChart.Layer, float(step) / width))
	view.draw_rect(Rect2(origin, Vector2(width, 14.0)), Color.WHITE, false, 1.0)
	var font := ThemeDB.fallback_font
	if layer == PlanetChart.Layer.TEMPERATURE or layer == PlanetChart.Layer.MEAN_TEMPERATURE:
		# ticks every 10 degrees C (the scale runs -30 to 45), as a weather map's legend has
		for degrees in range(-20, 41, 10):
			var x := (float(degrees) + 30.0) / 75.0 * width
			view.draw_line(origin + Vector2(x, 10.0), origin + Vector2(x, 14.0), Color.WHITE, 1.0)
			view.draw_string(font, origin + Vector2(x - 8.0, 27.0), str(degrees),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	view.draw_string(font, origin + Vector2(0.0, -4.0), labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	view.draw_string(font, origin + Vector2(width, -4.0), labels[1], HORIZONTAL_ALIGNMENT_RIGHT,
			-1, 14)
	view.draw_string(font, origin + Vector2(width + 14.0, 12.0), PlanetChart.NAMES[layer],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


## The names of the seas and the lands, spaced capitals, while the view is far enough to show them.
static func draw_names(view: Control, labels: PlanetMapLabels, zoom: float,
		on_screen: Callable) -> void:
	var font := ThemeDB.fallback_font
	var size := clampi(int(13.0 + 3.0 * log(zoom + 1.0)), 13, 22)
	for item in labels.items:
		var spot: Vector2 = on_screen.call(item["uv"])
		if spot.x < 0.0:
			continue
		var text := PlanetMapLabels.spaced(item["text"])
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		var at := spot - Vector2(width * 0.5, 0.0)
		var colour := Color(0.88, 0.95, 1.0, 0.8) if item["sea"] else Color(1.0, 1.0, 1.0, 0.85)
		view.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, 3,
				Color(0.0, 0.0, 0.0, 0.55))
		view.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, colour)


## The lines every `gap` degrees, finer as the view comes closer (only the ones in view).
static func draw_grid(view: Control, zoom: float, centre: Vector2, size: Vector2,
		on_screen: Callable) -> void:
	var gap := 30.0
	var steps := [[3.0, 10.0], [12.0, 5.0], [70.0, 1.0], [140.0, 0.5], [700.0, 0.1], [1400.0, 0.05]]
	for pair: Array in steps: # (from this zoom on, this gap)
		if zoom >= float(pair[0]):
			gap = float(pair[1])
	var line := Color(1.0, 1.0, 1.0, 0.18)
	var lat_from := (0.5 - (centre.y + size.y * 0.5)) * 180.0
	var lat_to := (0.5 - (centre.y - size.y * 0.5)) * 180.0
	for index in range(floori(lat_from / gap), ceili(lat_to / gap) + 1):
		var degrees := float(index) * gap
		var at: Vector2 = on_screen.call(Vector2(centre.x, 0.5 - degrees / 180.0))
		if at.y >= 0.0 and absf(degrees) <= 90.0:
			view.draw_line(Vector2(0.0, at.y), Vector2(view.size.x, at.y),
					line if index != 0 else Color(1.0, 1.0, 1.0, 0.4))
	var lon_centre := (centre.x - 0.5) * 360.0
	var lon_half := minf(size.x * 180.0, 180.0)
	var first := floori((lon_centre - lon_half) / gap)
	for index in range(first, ceili((lon_centre + lon_half) / gap) + 1):
		var uv := (float(index) * gap + 180.0) / 360.0
		var at: Vector2 = on_screen.call(Vector2(fposmod(uv, 1.0), centre.y))
		if at.x >= 0.0:
			view.draw_line(Vector2(at.x, 0.0), Vector2(at.x, view.size.y), line)


## The player: an arrow at `spot` pointing along `heading`.
static func draw_arrow(view: Control, spot: Vector2, heading: Vector2) -> void:
	var side := Vector2(-heading.y, heading.x)
	var points := PackedVector2Array([spot + heading * 13.0, spot - heading * 7.0 + side * 7.0,
			spot - heading * 7.0 - side * 7.0])
	view.draw_colored_polygon(points, Color(1.0, 0.25, 0.2))
	view.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]),
			Color.WHITE, 1.5)
