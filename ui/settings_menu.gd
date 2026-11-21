class_name SettingsMenu
extends PanelContainer
## Pause-menu settings page. Graphics behavior and persistence live in the
## GraphicsSettings autoload; this scene only presents and synchronizes UI.

signal back_requested

const AA_NAMES: PackedStringArray = ["Off", "FXAA", "SMAA", "TAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"]
## What each anti-aliasing mode does, for its tooltip and the line under the setting (same order as AA_NAMES).
const AA_HELP: PackedStringArray = [
	"No smoothing: the sharpest and the fastest, but edges look jagged.",
	"The cheapest smoothing. It softens edges and slightly blurs the whole image.",
	"Sharper than FXAA and cheap. Grass and leaves shimmer more while you move.",
	"The steadiest grass, leaves and thin detail. Can smear fast movement; the costliest of the screen modes.",
	"Smooths the edges of shapes only, not shimmering grass or leaves. Uses more memory and GPU.",
	"Cleaner shape edges than 2x. Heavy on the GPU; does not stop foliage shimmer.",
	"The cleanest shape edges and very heavy. Does not stop foliage shimmer.",
]
const SHADOW_NAMES: PackedStringArray = ["Off", "Low", "Medium", "High"]
## What an option costs, as a tooltip on its control (task 101): measured on an RTX 4090 in a dense-forest walk, so a rough guide, not a promise.
## An empty entry is filled in by `_cost_hint`.
const COST_HINTS := {
	&"shadow_quality": "The sun's shadows: the biggest single cost of the effects, about 9 ms of GPU a frame on High (RTX 4090).",
	&"ground_detail": "Fine and Finest add bump, ripples and finer plant meshes: Fine costs about 7 ms of GPU and 11 million triangles more than Normal on High.",
	&"tree_range": "How far the trees are drawn. Short saves about 5-8 ms of GPU against Medium on High; Far costs the most.",
	&"mesh_detail": "How long trees, plants and rocks keep their full detail before a cheaper version takes over. Normal is the engine's own; Sharp costs about 10 ms of GPU more on High (26.8 vs 16.9 ms in the forest walk) and 14 M more triangles.",
	&"plant_range": "How far the shrubs and ground cover are drawn: nearer saves GPU and CPU time.",
	&"plant_bend": "Plants that bend under the walker cost CPU: with none, a dense forest's physics time fell from about 35 ms to 6 ms.",
	&"voxel_ground": "Caves and digging are part of the game and need this. It costs about 5 ms of CPU a frame, three busy worker threads and some hitches: turn it off on a weak machine. It is not changed by the quality presets.",
	&"plant_shadows": "Foliage in the sun's shadows: trees and plants together cost about 3 ms of GPU more than trees alone.",
	&"vegetation_fade": "Fading plants and trees in and out avoids pop-in but draws them twice while they fade: off is a little cheaper (too small to measure in a forest walk).",
	&"grass_density": "Sparse draws about 55% fewer ground-grass tufts than Normal, Dense about 55% more. The frame-time effect was within the measurement noise (about 4 fps) in a forest walk.",
	&"grass_range": "How far the ground grass and meadows are drawn: Short is half the distance, Medium three quarters. Takes effect on ground made after the change.",
	&"far_tree_density": "Beyond the middle distance, Half draws every second tree and A quarter every fourth (a third of the far trees' instances), made bigger so the forest still looks full.",
	&"terrain_range": "How far the voxel ground is built: Short 1 km, Normal 2 km, Far 4 km. A longer view makes the ground take longer to load and keeps more distant ground detail.",
	&"fov": "The player's field of view. A wider view shows more but stretches the edges.",
	&"film_grain": "A light moving noise over the picture. Costs almost nothing.",
	&"agx_tuned": "Turns on the AgX tone mapper with a little more exposure (1.12) and contrast (1.32): softer highlights, less saturated, closer to a photograph than Filmic. Costs nothing. Turning it off keeps AgX with the engine's own values; pick another curve under Tone mapping.",
	&"depth_of_field": "Blurs what is far away (from 200 m on Light, 80 m on Strong), which includes the horizon. Costs GPU time.",
	&"motion_blur": "Smears the picture along the motion of the camera and the objects. Costs a little GPU time.",
}

var _preset_buttons: Array[Button] = []
var _syncing := false
var _aa_hint: Label ## what the chosen anti-aliasing mode does
var _tone_mapper: OptionButton
var _hdr: CheckButton
var _cloud_quality: OptionButton
var _look_options := {} # key -> its OptionButton (the look settings)
var _look_toggles := {} # key -> its CheckButton
var _look_sliders := {} # key -> [slider, value label, scale, offset] (the setting is offset + shown * scale)
var _display_options := {} # key -> [OptionButton, first] (the setting is the chosen index + first)
var _window_sizes: Array[Vector2i] = []
var _window_size_option: OptionButton
var _settings: Node

@onready var low_button: Button = %LowButton
@onready var medium_button: Button = %MediumButton
@onready var high_button: Button = %HighButton
@onready var ultra_button: Button = %UltraButton
@onready var custom_button: Button = %CustomButton
@onready var render_scale: HSlider = %RenderScale
@onready var render_scale_value: Label = %RenderScaleValue
@onready var anti_aliasing: OptionButton = %AntiAliasing
@onready var shadow_quality: OptionButton = %ShadowQuality
@onready var ssao: CheckButton = %SSAO
@onready var ssil: CheckButton = %SSIL
@onready var glow: CheckButton = %Glow
@onready var vsync: CheckButton = %VSync
@onready var max_fps: HSlider = %MaxFPS
@onready var max_fps_value: Label = %MaxFPSValue
@onready var back_button: Button = %BackButton


func _ready() -> void:
	_settings = get_node(^"/root/GraphicsSettings")
	_preset_buttons = [
		low_button, medium_button, high_button, ultra_button, custom_button,
	]
	for index in _preset_buttons.size():
		_preset_buttons[index].pressed.connect(_on_preset_pressed.bind(index))
	for label: String in AA_NAMES:
		anti_aliasing.add_item(label)
	for label: String in SHADOW_NAMES:
		shadow_quality.add_item(label)
	render_scale.value_changed.connect(_on_render_scale_changed)
	anti_aliasing.item_selected.connect(_on_anti_aliasing_selected)
	shadow_quality.item_selected.connect(_on_shadow_quality_selected)
	ssao.toggled.connect(_on_toggle_changed.bind(&"ssao"))
	ssil.toggled.connect(_on_toggle_changed.bind(&"ssil"))
	glow.toggled.connect(_on_toggle_changed.bind(&"glow"))
	vsync.toggled.connect(_on_toggle_changed.bind(&"vsync"))
	_add_anti_aliasing_help()
	_add_look_controls()
	max_fps.value_changed.connect(_on_max_fps_changed)
	back_button.pressed.connect(back_requested.emit)
	_settings.settings_changed.connect(_on_settings_changed)
	_sync_controls()


## A tooltip on every anti-aliasing entry and a line under the setting that says what the chosen one does.
func _add_anti_aliasing_help() -> void:
	for index in AA_HELP.size():
		anti_aliasing.set_item_tooltip(index, AA_HELP[index])
	var parent := anti_aliasing.get_parent()
	var at := anti_aliasing.get_index() + 1
	var spacer := Control.new() # (the empty cell under the setting's name)
	parent.add_child(spacer)
	parent.move_child(spacer, at)
	_aa_hint = Label.new()
	_aa_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aa_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aa_hint.add_theme_font_size_override(&"font_size", 12)
	_aa_hint.modulate = Color(1.0, 1.0, 1.0, 0.7)
	parent.add_child(_aa_hint)
	parent.move_child(_aa_hint, at + 1)


func _show_anti_aliasing_help(index: int) -> void:
	if _aa_hint != null and index >= 0 and index < AA_HELP.size():
		_aa_hint.text = AA_HELP[index]
		anti_aliasing.tooltip_text = AA_HELP[index]


## The tone mapper and the HDR output (Godot 4.7), added under the glow switch.
func _add_look_controls() -> void:
	var parent := glow.get_parent()
	var at := glow.get_index() + 1
	var label := Label.new()
	label.text = "Tone mapping"
	parent.add_child(label)
	parent.move_child(label, at)
	_tone_mapper = OptionButton.new()
	for name_of: String in ["Linear", "Reinhard", "Filmic", "ACES", "AgX"]:
		_tone_mapper.add_item(name_of)
	_tone_mapper.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			_settings.set_graphics_value(&"tone_mapper", index))
	parent.add_child(_tone_mapper)
	parent.move_child(_tone_mapper, at + 1)
	var hdr_label := Label.new()
	hdr_label.text = "HDR output (needs an HDR display)"
	parent.add_child(hdr_label)
	parent.move_child(hdr_label, at + 2)
	_hdr = CheckButton.new()
	_hdr.text = "Enabled"
	_hdr.toggled.connect(_on_toggle_changed.bind(&"hdr"))
	parent.add_child(_hdr)
	parent.move_child(_hdr, at + 3)
	var cloud_label := Label.new()
	cloud_label.text = "Cloud quality (the planet)"
	parent.add_child(cloud_label)
	parent.move_child(cloud_label, at + 4)
	_cloud_quality = OptionButton.new()
	for name_of: String in ["Low", "Medium", "High"]:
		_cloud_quality.add_item(name_of)
	_cloud_quality.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			_settings.set_graphics_value(&"cloud_quality", index))
	parent.add_child(_cloud_quality)
	parent.move_child(_cloud_quality, at + 5)
	var next := at + 6
	next = _look_option(parent, next, &"upscaler", "Upscaler (below 100% scale)",
			GraphicsLook.UPSCALER_NAMES)
	next = _look_option(parent, next, &"ground_detail", "Ground and plant detail",
			PackedStringArray(["Plain", "Normal", "Fine", "Finest"]))
	next = _look_option(parent, next, &"mesh_detail", "Mesh detail distance",
			PackedStringArray(["Normal", "Sharp", "Sharpest"]))
	next = _look_option(parent, next, &"plant_range", "Plant distance (shrubs, ground cover; new ground)",
			PackedStringArray(["Near", "Medium", "Far"]))
	next = _look_option(parent, next, &"tree_range", "Tree distance (new ground)",
			PackedStringArray(["Short (1.5 km)", "Medium (3 km)", "Far (horizon)"]))
	next = _look_option(parent, next, &"plant_bend", "Plants bend when touched",
			PackedStringArray(["Off", "A few", "All"]))
	next = _look_toggle(parent, next, &"voxel_ground", "Caves and digging (needs more CPU; restart to apply)")
	next = _look_option(parent, next, &"plant_shadows", "Foliage shadows (new ground)",
			PackedStringArray(["None", "Trees only", "Trees and plants"]))
	next = _look_option(parent, next, &"grass_density", "Grass density (new ground)",
			PackedStringArray(["Sparse", "Normal", "Dense"]))
	next = _look_option(parent, next, &"grass_range", "Grass distance (new ground)",
			PackedStringArray(["Short", "Medium", "Far"]))
	next = _look_option(parent, next, &"far_tree_density", "Distant tree density (new ground)",
			PackedStringArray(["All", "Half", "A quarter"]))
	next = _look_toggle(parent, next, &"vegetation_fade", "Fade plants and trees in and out (new ground)")
	next = _look_option(parent, next, &"terrain_range", "Terrain distance (restart to apply)",
			PackedStringArray(["Short (1 km)", "Normal (2 km)", "Far (4 km)"]))
	next = _look_option(parent, next, &"colour_grade", "Colour grade", GraphicsLook.GRADE_NAMES)
	next = _look_option(parent, next, &"reflections", "Reflections (SSR)",
			GraphicsLook.REFLECTION_NAMES)
	next = _look_toggle(parent, next, &"auto_exposure", "Auto exposure")
	next = _look_toggle(parent, next, &"debanding", "Debanding (smooth sky gradients)")
	next = _look_option(parent, next, &"film_grain", "Film grain", PackedStringArray(["Off", "Light", "Strong"]))
	next = _look_option(parent, next, &"depth_of_field", "Depth of field (blurs the distance)", PackedStringArray(["Off", "Light", "Strong"]))
	next = _look_option(parent, next, &"motion_blur", "Motion blur", PackedStringArray(["Off", "Light", "Strong"]))
	next = _look_slider(parent, next, &"brightness", "Brightness", 70.0, 130.0, 5.0, 0.01, 0.0)
	next = _look_slider(parent, next, &"fov", "Field of view", 60.0, 110.0, 1.0, 1.0, 0.0)
	next = _look_slider(parent, next, &"fsr_sharpness", "Upscaler sharpness", 0.0, 100.0, 5.0, -0.02, 2.0)
	next = _add_display_controls(parent, next)
	_apply_cost_hints()
	next = _look_toggle(parent, next, &"particles", "Dust and pollen in the air")
	next = _look_toggle(parent, next, &"occlusion_culling", "Occlusion culling (skip what is hidden)")
	next = _look_toggle(parent, next, &"decals", "Footprints in snow, sand and mud")
	next = _look_toggle(parent, next, &"sdfgi",
			"Bounced light (SDFGI, experimental: can reset some GPUs)")
	next = _look_toggle(parent, next, &"cloud_shadows", "Cloud shadows on the ground")
	next = _look_toggle(parent, next, &"volumetric_fog", "Light shafts (near the ground)")
	next = _look_toggle(parent, next, &"agx_tuned", "AgX photographic look (switches the tone mapper to AgX)")
	(_look_toggles[&"agx_tuned"] as CheckButton).toggled.connect(func(on: bool) -> void:
		if on and not _syncing:
			_settings.set_graphics_value(&"tone_mapper", Environment.TONE_MAPPER_AGX))
	_apply_cost_hints() # (again: the rows made since the first call need their tooltips)


func _look_slider(parent: Node, at: int, key: StringName, title: String, low: float, high: float, step: float,
		scale: float, offset: float) -> int:
	## A slider for a number setting: the setting is `offset + shown * scale` (the brightness shows percent, the sharpness shows 100 - ...).
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	parent.move_child(label, at)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 56.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(shown: float) -> void:
		value_label.text = ("%d" % roundi(shown)) + ("\u00b0" if key == &"fov" else "%")
		if not _syncing:
			_settings.set_graphics_value(key, offset + shown * scale))
	row.add_child(slider)
	row.add_child(value_label)
	parent.add_child(row)
	parent.move_child(row, at + 1)
	_look_sliders[key] = [slider, value_label, scale, offset]
	return at + 2


## The Display rows: which monitor, the window mode and (windowed) the size. "As launched" leaves the window alone, as it was before.
func _add_display_controls(parent: Node, at: int) -> int:
	var next := at
	var monitors := PackedStringArray(["As launched"])
	for screen in DisplayServer.get_screen_count():
		var extent := DisplayServer.screen_get_size(screen)
		monitors.append("Monitor %d (%dx%d)" % [screen + 1, extent.x, extent.y])
	next = _display_option(parent, next, &"monitor", "Monitor", monitors, -1)
	next = _display_option(parent, next, &"window_mode", "Window mode",
			PackedStringArray(["As launched", "Windowed", "Borderless fullscreen", "Exclusive fullscreen"]), -1)
	var sizes := PackedStringArray(["As launched"])
	_window_sizes = [Vector2i.ZERO]
	var screen_size := DisplayServer.screen_get_size()
	for candidate: Vector2i in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
			Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]:
		if candidate.x <= screen_size.x and candidate.y <= screen_size.y:
			sizes.append("%dx%d" % [candidate.x, candidate.y])
			_window_sizes.append(candidate)
	var label := Label.new()
	label.text = "Window size (windowed)"
	parent.add_child(label)
	parent.move_child(label, next)
	_window_size_option = OptionButton.new()
	for name_of: String in sizes:
		_window_size_option.add_item(name_of)
	_window_size_option.item_selected.connect(func(index: int) -> void:
		if _syncing:
			return
		var chosen: Vector2i = _window_sizes[index]
		_settings.set_graphics_value(&"window_width", chosen.x)
		_settings.set_graphics_value(&"window_height", chosen.y)
		if chosen.x > 0 and int(_settings.get_graphics_value(&"window_mode")) != 0:
			_settings.set_graphics_value(&"window_mode", 0))
	parent.add_child(_window_size_option)
	parent.move_child(_window_size_option, next + 1)
	return next + 2


## An option whose setting is the chosen index plus `first` (-1: the first entry is "as launched").
func _display_option(parent: Node, at: int, key: StringName, title: String, names: PackedStringArray, first: int) -> int:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	parent.move_child(label, at)
	var options := OptionButton.new()
	for name_of: String in names:
		options.add_item(name_of)
	options.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			_settings.set_graphics_value(key, index + first))
	parent.add_child(options)
	parent.move_child(options, at + 1)
	_display_options[key] = [options, first]
	return at + 2


## The tooltips with the cost of each option (COST_HINTS), on the control and its name.
func _apply_cost_hints() -> void:
	for key: StringName in COST_HINTS:
		var control: Control = null
		if _look_options.has(key):
			control = _look_options[key]
		elif _look_toggles.has(key):
			control = _look_toggles[key]
		elif _look_sliders.has(key):
			control = (_look_sliders[key] as Array)[0]
		elif key == &"shadow_quality":
			control = shadow_quality
		if control != null:
			control.tooltip_text = COST_HINTS[key]


func _look_option(parent: Node, at: int, key: StringName, title: String,
		names: PackedStringArray) -> int:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	parent.move_child(label, at)
	var options := OptionButton.new()
	for name_of: String in names:
		options.add_item(name_of)
	options.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			_settings.set_graphics_value(key, index))
	parent.add_child(options)
	parent.move_child(options, at + 1)
	_look_options[key] = options
	return at + 2


func _look_toggle(parent: Node, at: int, key: StringName, title: String) -> int:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	parent.move_child(label, at)
	var toggle := CheckButton.new()
	toggle.text = "Enabled"
	toggle.toggled.connect(_on_toggle_changed.bind(key))
	parent.add_child(toggle)
	parent.move_child(toggle, at + 1)
	_look_toggles[key] = toggle
	return at + 2


func refresh() -> void:
	_sync_controls()


func _on_preset_pressed(preset: int) -> void:
	_settings.set_preset(preset)


func _on_render_scale_changed(value: float) -> void:
	render_scale_value.text = "%d%%" % roundi(value)
	if not _syncing:
		_settings.set_graphics_value(&"render_scale", value / 100.0)


func _on_anti_aliasing_selected(index: int) -> void:
	_show_anti_aliasing_help(index)
	if not _syncing:
		_settings.set_graphics_value(&"anti_aliasing", index)


func _on_shadow_quality_selected(index: int) -> void:
	if not _syncing:
		_settings.set_graphics_value(&"shadow_quality", index)


func _on_toggle_changed(enabled: bool, key: StringName) -> void:
	if not _syncing:
		_settings.set_graphics_value(key, enabled)


func _on_max_fps_changed(value: float) -> void:
	max_fps_value.text = "%d FPS" % roundi(value)
	if not _syncing:
		_settings.set_graphics_value(&"max_fps", roundi(value))


func _on_settings_changed(_preset: int) -> void:
	_sync_controls()


func _sync_controls() -> void:
	if _settings == null:
		return
	_syncing = true
	var preset: int = _settings.current_preset
	for index in _preset_buttons.size():
		_preset_buttons[index].button_pressed = index == preset
	render_scale.value = float(_settings.get_graphics_value(&"render_scale")) * 100.0
	anti_aliasing.select(int(_settings.get_graphics_value(&"anti_aliasing")))
	_show_anti_aliasing_help(anti_aliasing.selected)
	shadow_quality.select(int(_settings.get_graphics_value(&"shadow_quality")))
	ssao.button_pressed = bool(_settings.get_graphics_value(&"ssao"))
	ssil.button_pressed = bool(_settings.get_graphics_value(&"ssil"))
	glow.button_pressed = bool(_settings.get_graphics_value(&"glow"))
	_tone_mapper.select(int(_settings.get_graphics_value(&"tone_mapper")))
	_hdr.button_pressed = bool(_settings.get_graphics_value(&"hdr"))
	_cloud_quality.select(int(_settings.get_graphics_value(&"cloud_quality")))
	for key: StringName in _look_options:
		(_look_options[key] as OptionButton).select(int(_settings.get_graphics_value(key)))
	for key: StringName in _look_toggles:
		(_look_toggles[key] as CheckButton).button_pressed = bool(_settings.get_graphics_value(key))
	for key: StringName in _look_sliders:
		var entry: Array = _look_sliders[key]
		(entry[0] as HSlider).value = (float(_settings.get_graphics_value(key)) - float(entry[3])) / float(entry[2])
	for key: StringName in _display_options:
		var entry: Array = _display_options[key]
		(entry[0] as OptionButton).select(clampi(int(_settings.get_graphics_value(key)) - int(entry[1]), 0, (entry[0] as OptionButton).item_count - 1))
	if _window_size_option != null:
		var wanted := Vector2i(int(_settings.get_graphics_value(&"window_width")), int(_settings.get_graphics_value(&"window_height")))
		_window_size_option.select(maxi(_window_sizes.find(wanted), 0))
	vsync.button_pressed = bool(_settings.get_graphics_value(&"vsync"))
	max_fps.value = float(_settings.get_graphics_value(&"max_fps"))
	render_scale_value.text = "%d%%" % roundi(render_scale.value)
	max_fps_value.text = "%d FPS" % roundi(max_fps.value)
	_syncing = false
