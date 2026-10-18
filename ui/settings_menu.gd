class_name SettingsMenu
extends PanelContainer
## Pause-menu settings page. Graphics behavior and persistence live in the
## GraphicsSettings autoload; this scene only presents and synchronizes UI.

signal back_requested

const AA_NAMES: PackedStringArray = ["Off", "FXAA", "SMAA", "TAA", "MSAA 2x", "MSAA 4x"]
const SHADOW_NAMES: PackedStringArray = ["Off", "Low", "Medium", "High"]

var _preset_buttons: Array[Button] = []
var _syncing := false
var _tone_mapper: OptionButton
var _hdr: CheckButton
var _cloud_quality: OptionButton
var _look_options := {} # key -> its OptionButton (the look settings)
var _look_toggles := {} # key -> its CheckButton
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
	_add_look_controls()
	max_fps.value_changed.connect(_on_max_fps_changed)
	back_button.pressed.connect(back_requested.emit)
	_settings.settings_changed.connect(_on_settings_changed)
	_sync_controls()


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
	_hdr = CheckButton.new()
	_hdr.text = "HDR output (needs an HDR display)"
	_hdr.toggled.connect(_on_toggle_changed.bind(&"hdr"))
	parent.add_child(_hdr)
	parent.move_child(_hdr, at + 2)
	var cloud_label := Label.new()
	cloud_label.text = "Cloud quality (the planet)"
	parent.add_child(cloud_label)
	parent.move_child(cloud_label, at + 3)
	_cloud_quality = OptionButton.new()
	for name_of: String in ["Low", "Medium", "High"]:
		_cloud_quality.add_item(name_of)
	_cloud_quality.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			_settings.set_graphics_value(&"cloud_quality", index))
	parent.add_child(_cloud_quality)
	parent.move_child(_cloud_quality, at + 4)
	var next := at + 5
	next = _look_option(parent, next, &"upscaler", "Upscaler (below 100% scale)",
			GraphicsLook.UPSCALER_NAMES)
	next = _look_option(parent, next, &"ground_detail", "Ground detail",
			PackedStringArray(["Plain", "Normal", "Fine", "Finest"]))
	next = _look_option(parent, next, &"colour_grade", "Colour grade", GraphicsLook.GRADE_NAMES)
	next = _look_option(parent, next, &"reflections", "Reflections (SSR)",
			GraphicsLook.REFLECTION_NAMES)
	next = _look_toggle(parent, next, &"auto_exposure", "Auto exposure")
	next = _look_toggle(parent, next, &"debanding", "Debanding (smooth sky gradients)")
	next = _look_toggle(parent, next, &"volumetric_fog", "Light shafts (near the ground)")


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
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.toggled.connect(_on_toggle_changed.bind(key))
	parent.add_child(toggle)
	parent.move_child(toggle, at)
	_look_toggles[key] = toggle
	return at + 1


func refresh() -> void:
	_sync_controls()


func _on_preset_pressed(preset: int) -> void:
	_settings.set_preset(preset)


func _on_render_scale_changed(value: float) -> void:
	render_scale_value.text = "%d%%" % roundi(value)
	if not _syncing:
		_settings.set_graphics_value(&"render_scale", value / 100.0)


func _on_anti_aliasing_selected(index: int) -> void:
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
	vsync.button_pressed = bool(_settings.get_graphics_value(&"vsync"))
	max_fps.value = float(_settings.get_graphics_value(&"max_fps"))
	render_scale_value.text = "%d%%" % roundi(render_scale.value)
	max_fps_value.text = "%d FPS" % roundi(max_fps.value)
	_syncing = false
