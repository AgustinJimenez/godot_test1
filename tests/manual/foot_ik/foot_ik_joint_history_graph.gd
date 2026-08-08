class_name FootIkJointHistoryGraph
extends Control
## Optional rolling graphs for post-IK joint angles and body-relative positions.

const PREFERRED_GRAPH_SIZE := Vector2(940.0, 760.0)
const MIN_GRAPH_SIZE := Vector2(520.0, 520.0)
const HEADER_HEIGHT := 86.0
const PLOT_LEFT := 62.0
const PLOT_RIGHT := 18.0
const PLOT_BOTTOM := 26.0
const PLOT_GAP := 10.0
const HISTORY_SAMPLES := 360 # Six seconds at the 60Hz physics sampling rate.
const METRICS: Array[Dictionary] = [
	{"key": "angle", "label": "Angle", "unit": "°", "min": 0.0, "max": 180.0},
	{"key": "x", "label": "Body-relative X", "unit": "m", "min": -1.0, "max": 1.0},
	{"key": "y", "label": "Body-relative Y", "unit": "m", "min": 0.0, "max": 2.0},
	{"key": "z", "label": "Body-relative Z", "unit": "m", "min": -1.0, "max": 1.0},
]
const TRACE_CONFIG: Array[Dictionary] = [
	{"key": "left_thigh", "label": "L Hip/Thigh", "color": Color("ff595e")},
	{"key": "left_shin", "label": "L Knee/Shin", "color": Color("ffca3a")},
	{"key": "left_foot", "label": "L Ankle/Foot", "color": Color("8ac926")},
	{"key": "left_leaf", "label": "L Toe/Leaf", "color": Color("1982c4")},
	{"key": "right_thigh", "label": "R Hip/Thigh", "color": Color("ff8fa3")},
	{"key": "right_shin", "label": "R Knee/Shin", "color": Color("ffe66d")},
	{"key": "right_foot", "label": "R Ankle/Foot", "color": Color("52b788")},
	{"key": "right_leaf", "label": "R Toe/Leaf", "color": Color("9d4edd")},
]

var _history: Dictionary = {} # trace key -> metric key -> PackedFloat32Array
var _enabled: Dictionary = {} # trace key -> bool
var _joint_toggles: Array[CheckButton] = []
var _debug_panel_width := 0.0
var _outer_margin := 0.0


func _init() -> void:
	custom_minimum_size = MIN_GRAPH_SIZE
	size = PREFERRED_GRAPH_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	for trace: Dictionary in TRACE_CONFIG:
		var key: String = trace["key"]
		_history[key] = _empty_trace_history()
		_enabled[key] = true


func attach(layer: CanvasLayer, debug_panel_width: float, outer_margin: float) -> void:
	_debug_panel_width = debug_panel_width
	_outer_margin = outer_margin
	layer.add_child(self)
	add_to_group(&"foot_ik_joint_history_graph")
	_build_joint_toggles()
	_position_for_viewport()
	get_viewport().size_changed.connect(_position_for_viewport)


func sample_side(side: String, angles: Dictionary, probes: Dictionary,
		foot_probe: Node3D, body_root: Node3D) -> void:
	if not visible:
		return
	var joint_probes := {
		"thigh": probes.get("hip"),
		"shin": probes.get("knee"),
		"foot": foot_probe,
		"leaf": probes.get("leaf"),
	}
	for segment: String in ["thigh", "shin", "foot", "leaf"]:
		if not angles.has(segment):
			continue
		var probe := joint_probes[segment] as Node3D
		if probe == null:
			continue
		var trace_key := side + "_" + segment
		var relative_position := body_root.to_local(probe.global_position)
		var trace_history := _history[trace_key] as Dictionary
		_append_sample(trace_history, "angle", clampf(float(angles[segment]), 0.0, 180.0))
		_append_sample(trace_history, "x", relative_position.x)
		_append_sample(trace_history, "y", relative_position.y)
		_append_sample(trace_history, "z", relative_position.z)
		_history[trace_key] = trace_history
	queue_redraw()


func set_graph_visible(enabled: bool) -> void:
	visible = enabled
	if enabled:
		for key: String in _history:
			_history[key] = _empty_trace_history()
		queue_redraw()


func is_graph_visible() -> bool:
	return visible


func _empty_trace_history() -> Dictionary:
	return {
		"angle": PackedFloat32Array(),
		"x": PackedFloat32Array(),
		"y": PackedFloat32Array(),
		"z": PackedFloat32Array(),
	}


func _append_sample(history: Dictionary, metric: String, value: float) -> void:
	var samples := history[metric] as PackedFloat32Array
	samples.append(value)
	if samples.size() > HISTORY_SAMPLES:
		samples.remove_at(0)
	history[metric] = samples


func _build_joint_toggles() -> void:
	for trace: Dictionary in TRACE_CONFIG:
		var toggle := CheckButton.new()
		var key: String = trace["key"]
		var color := trace["color"] as Color
		toggle.text = str(trace["label"])
		toggle.button_pressed = true
		toggle.add_theme_font_size_override("font_size", 15)
		for theme_color: StringName in [
				&"font_color", &"font_hover_color", &"font_pressed_color"]:
			toggle.add_theme_color_override(theme_color, color)
		toggle.toggled.connect(_set_joint_enabled.bind(key))
		add_child(toggle)
		_joint_toggles.append(toggle)


func _set_joint_enabled(enabled: bool, key: String) -> void:
	_enabled[key] = enabled
	queue_redraw()


func _position_for_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var available_width := viewport_size.x - _debug_panel_width - _outer_margin * 3.0
	size = Vector2(
			clampf(available_width, MIN_GRAPH_SIZE.x, PREFERRED_GRAPH_SIZE.x),
			clampf(viewport_size.y - _outer_margin * 2.0,
					MIN_GRAPH_SIZE.y, PREFERRED_GRAPH_SIZE.y))
	position = Vector2(maxf(
			_outer_margin,
			viewport_size.x - _debug_panel_width - size.x - _outer_margin * 2.0),
			_outer_margin)
	_layout_joint_toggles()
	queue_redraw()


func _layout_joint_toggles() -> void:
	var column_width := (size.x - 24.0) / 4.0
	for index in _joint_toggles.size():
		var toggle := _joint_toggles[index]
		toggle.position = Vector2(12.0 + (index % 4) * column_width,
				8.0 + (index / 4) * 32.0)
		toggle.size = Vector2(column_width - 4.0, 30.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.035, 0.1, 0.96), true)
	for metric_index in METRICS.size():
		var metric: Dictionary = METRICS[metric_index]
		var plot := _plot_rect(metric_index)
		draw_rect(plot, Color(0.015, 0.02, 0.055, 1.0), true)
		_draw_grid(plot, metric)
		for trace: Dictionary in TRACE_CONFIG:
			var trace_key: String = trace["key"]
			if not bool(_enabled[trace_key]):
				continue
			var history := _history[trace_key] as Dictionary
			_draw_trace(plot, history[metric["key"]] as PackedFloat32Array,
					trace["color"] as Color, float(metric["min"]), float(metric["max"]))


func _plot_rect(index: int) -> Rect2:
	var available_height := size.y - HEADER_HEIGHT - PLOT_BOTTOM
	var plot_height := (available_height - PLOT_GAP * (METRICS.size() - 1)) / METRICS.size()
	return Rect2(PLOT_LEFT, HEADER_HEIGHT + index * (plot_height + PLOT_GAP),
			size.x - PLOT_LEFT - PLOT_RIGHT, plot_height)


func _draw_grid(plot: Rect2, metric: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var minimum := float(metric["min"])
	var maximum := float(metric["max"])
	for line_index in 3:
		var ratio := line_index / 2.0
		var value := lerpf(maximum, minimum, ratio)
		var y := plot.position.y + ratio * plot.size.y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
				Color(0.35, 0.4, 0.55, 0.35), 1.0)
		var value_text := "%.0f" % value if metric["key"] == "angle" else "%.2f" % value
		draw_string(font, Vector2(5.0, y + 5.0),
				value_text + str(metric["unit"]),
				HORIZONTAL_ALIGNMENT_LEFT, 54.0, 13, Color(0.8, 0.84, 0.95))
	draw_string(font, plot.position + Vector2(7.0, 17.0), str(metric["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.9, 0.93, 1.0))


func _draw_trace(plot: Rect2, samples: PackedFloat32Array, color: Color,
		minimum: float, maximum: float) -> void:
	if samples.size() < 2:
		return
	var points := PackedVector2Array()
	var first_sample := maxi(0, samples.size() - HISTORY_SAMPLES)
	for index in range(first_sample, samples.size()):
		var history_index := HISTORY_SAMPLES - (samples.size() - index)
		var x_ratio := float(history_index) / float(HISTORY_SAMPLES - 1)
		var y_ratio := inverse_lerp(minimum, maximum, samples[index])
		points.append(Vector2(
				plot.position.x + x_ratio * plot.size.x,
				plot.end.y - y_ratio * plot.size.y))
	draw_polyline(points, color, 2.0, true)
