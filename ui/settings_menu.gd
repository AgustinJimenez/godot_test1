class_name SettingsMenu
extends PanelContainer
## Pause-menu settings page. Graphics behavior and persistence live in the
## GraphicsSettings autoload; this scene only presents and synchronizes UI.

signal back_requested

const AA_NAMES: PackedStringArray = ["Off", "FXAA", "SMAA", "TAA", "MSAA 2x", "MSAA 4x"]
const SHADOW_NAMES: PackedStringArray = ["Off", "Low", "Medium", "High"]

var _preset_buttons: Array[Button] = []
var _syncing := false
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
	max_fps.value_changed.connect(_on_max_fps_changed)
	back_button.pressed.connect(back_requested.emit)
	_settings.settings_changed.connect(_on_settings_changed)
	_sync_controls()


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
	vsync.button_pressed = bool(_settings.get_graphics_value(&"vsync"))
	max_fps.value = float(_settings.get_graphics_value(&"max_fps"))
	render_scale_value.text = "%d%%" % roundi(render_scale.value)
	max_fps_value.text = "%d FPS" % roundi(max_fps.value)
	_syncing = false
