class_name VisionDebugPanel
extends PanelContainer
## Live-tunable "vision"/atmosphere debug panel: finds the current scene's
## WorldEnvironment and edits its Environment resource directly, with no
## persistence - values reset on scene reload by design (a dev tool for
## iterating on ambient/fog/volumetric-fog/glow/background without editing
## scene files and reimporting for every value). "Copy values" hands the
## final tuned numbers back as pasteable text once the user has landed on
## something they like.

signal back_requested

var _environment: Environment
var _syncing := false

@onready var status_label: Label = %StatusLabel
@onready var content_scroll: ScrollContainer = %Scroll

@onready var ambient_energy: HSlider = %AmbientEnergy
@onready var ambient_energy_value: Label = %AmbientEnergyValue
@onready var ambient_color: ColorPickerButton = %AmbientColor

@onready var fog_enabled: CheckButton = %FogEnabled
@onready var fog_density: HSlider = %FogDensity
@onready var fog_density_value: Label = %FogDensityValue
@onready var fog_light_color: ColorPickerButton = %FogLightColor
@onready var fog_light_energy: HSlider = %FogLightEnergy
@onready var fog_light_energy_value: Label = %FogLightEnergyValue
@onready var fog_sun_scatter: HSlider = %FogSunScatter
@onready var fog_sun_scatter_value: Label = %FogSunScatterValue

@onready var volumetric_enabled: CheckButton = %VolumetricEnabled
@onready var volumetric_density: HSlider = %VolumetricDensity
@onready var volumetric_density_value: Label = %VolumetricDensityValue
@onready var volumetric_albedo: ColorPickerButton = %VolumetricAlbedo
@onready var volumetric_emission: ColorPickerButton = %VolumetricEmission
@onready var volumetric_emission_energy: HSlider = %VolumetricEmissionEnergy
@onready var volumetric_emission_energy_value: Label = %VolumetricEmissionEnergyValue
@onready var volumetric_anisotropy: HSlider = %VolumetricAnisotropy
@onready var volumetric_anisotropy_value: Label = %VolumetricAnisotropyValue
@onready var volumetric_length: HSlider = %VolumetricLength
@onready var volumetric_length_value: Label = %VolumetricLengthValue

@onready var glow_enabled: CheckButton = %GlowEnabled
@onready var glow_intensity: HSlider = %GlowIntensity
@onready var glow_intensity_value: Label = %GlowIntensityValue
@onready var glow_strength: HSlider = %GlowStrength
@onready var glow_strength_value: Label = %GlowStrengthValue
@onready var glow_bloom: HSlider = %GlowBloom
@onready var glow_bloom_value: Label = %GlowBloomValue
@onready var glow_hdr_threshold: HSlider = %GlowHdrThreshold
@onready var glow_hdr_threshold_value: Label = %GlowHdrThresholdValue

@onready var background_color: ColorPickerButton = %BackgroundColor

@onready var copy_button: Button = %CopyButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	ambient_energy.value_changed.connect(_on_ambient_energy_changed)
	ambient_color.color_changed.connect(_on_ambient_color_changed)
	fog_enabled.toggled.connect(_on_fog_enabled_toggled)
	fog_density.value_changed.connect(_on_fog_density_changed)
	fog_light_color.color_changed.connect(_on_fog_light_color_changed)
	fog_light_energy.value_changed.connect(_on_fog_light_energy_changed)
	fog_sun_scatter.value_changed.connect(_on_fog_sun_scatter_changed)
	volumetric_enabled.toggled.connect(_on_volumetric_enabled_toggled)
	volumetric_density.value_changed.connect(_on_volumetric_density_changed)
	volumetric_albedo.color_changed.connect(_on_volumetric_albedo_changed)
	volumetric_emission.color_changed.connect(_on_volumetric_emission_changed)
	volumetric_emission_energy.value_changed.connect(_on_volumetric_emission_energy_changed)
	volumetric_anisotropy.value_changed.connect(_on_volumetric_anisotropy_changed)
	volumetric_length.value_changed.connect(_on_volumetric_length_changed)
	glow_enabled.toggled.connect(_on_glow_enabled_toggled)
	glow_intensity.value_changed.connect(_on_glow_intensity_changed)
	glow_strength.value_changed.connect(_on_glow_strength_changed)
	glow_bloom.value_changed.connect(_on_glow_bloom_changed)
	glow_hdr_threshold.value_changed.connect(_on_glow_hdr_threshold_changed)
	background_color.color_changed.connect(_on_background_color_changed)
	copy_button.pressed.connect(_on_copy_pressed)
	back_button.pressed.connect(back_requested.emit)


## Re-locates the current scene's WorldEnvironment and refreshes every
## control from its live values - call each time this panel is shown, since
## the current scene (and its Environment) can differ between opens.
func open() -> void:
	_environment = _find_environment(get_tree().current_scene)
	var found := _environment != null
	status_label.visible = not found
	status_label.text = "No WorldEnvironment found in this scene."
	content_scroll.visible = found
	copy_button.disabled = not found
	if found:
		_sync_controls()


func _find_environment(node: Node) -> Environment:
	if node == null:
		return null
	if node is WorldEnvironment:
		return (node as WorldEnvironment).environment
	for child in node.get_children():
		var found := _find_environment(child)
		if found != null:
			return found
	return null


func _sync_controls() -> void:
	_syncing = true
	ambient_energy.value = _environment.ambient_light_energy
	ambient_color.color = _environment.ambient_light_color
	fog_enabled.button_pressed = _environment.fog_enabled
	fog_density.value = _environment.fog_density
	fog_light_color.color = _environment.fog_light_color
	fog_light_energy.value = _environment.fog_light_energy
	fog_sun_scatter.value = _environment.fog_sun_scatter
	volumetric_enabled.button_pressed = _environment.volumetric_fog_enabled
	volumetric_density.value = _environment.volumetric_fog_density
	volumetric_albedo.color = _environment.volumetric_fog_albedo
	volumetric_emission.color = _environment.volumetric_fog_emission
	volumetric_emission_energy.value = _environment.volumetric_fog_emission_energy
	volumetric_anisotropy.value = _environment.volumetric_fog_anisotropy
	volumetric_length.value = _environment.volumetric_fog_length
	glow_enabled.button_pressed = _environment.glow_enabled
	glow_intensity.value = _environment.glow_intensity
	glow_strength.value = _environment.glow_strength
	glow_bloom.value = _environment.glow_bloom
	glow_hdr_threshold.value = _environment.glow_hdr_threshold
	background_color.color = _environment.background_color
	_update_value_labels()
	_syncing = false


func _update_value_labels() -> void:
	ambient_energy_value.text = "%.2f" % ambient_energy.value
	fog_density_value.text = "%.4f" % fog_density.value
	fog_light_energy_value.text = "%.2f" % fog_light_energy.value
	fog_sun_scatter_value.text = "%.2f" % fog_sun_scatter.value
	volumetric_density_value.text = "%.3f" % volumetric_density.value
	volumetric_emission_energy_value.text = "%.2f" % volumetric_emission_energy.value
	volumetric_anisotropy_value.text = "%.2f" % volumetric_anisotropy.value
	volumetric_length_value.text = "%.1f" % volumetric_length.value
	glow_intensity_value.text = "%.2f" % glow_intensity.value
	glow_strength_value.text = "%.2f" % glow_strength.value
	glow_bloom_value.text = "%.2f" % glow_bloom.value
	glow_hdr_threshold_value.text = "%.2f" % glow_hdr_threshold.value


func _on_ambient_energy_changed(value: float) -> void:
	if _syncing:
		return
	_environment.ambient_light_energy = value
	_update_value_labels()


func _on_ambient_color_changed(color: Color) -> void:
	if _syncing:
		return
	_environment.ambient_light_color = color


func _on_fog_enabled_toggled(enabled: bool) -> void:
	if _syncing:
		return
	_environment.fog_enabled = enabled


func _on_fog_density_changed(value: float) -> void:
	if _syncing:
		return
	_environment.fog_density = value
	_update_value_labels()


func _on_fog_light_color_changed(color: Color) -> void:
	if _syncing:
		return
	_environment.fog_light_color = color


func _on_fog_light_energy_changed(value: float) -> void:
	if _syncing:
		return
	_environment.fog_light_energy = value
	_update_value_labels()


func _on_fog_sun_scatter_changed(value: float) -> void:
	if _syncing:
		return
	_environment.fog_sun_scatter = value
	_update_value_labels()


func _on_volumetric_enabled_toggled(enabled: bool) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_enabled = enabled


func _on_volumetric_density_changed(value: float) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_density = value
	_update_value_labels()


func _on_volumetric_albedo_changed(color: Color) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_albedo = color


func _on_volumetric_emission_changed(color: Color) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_emission = color


func _on_volumetric_emission_energy_changed(value: float) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_emission_energy = value
	_update_value_labels()


func _on_volumetric_anisotropy_changed(value: float) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_anisotropy = value
	_update_value_labels()


func _on_volumetric_length_changed(value: float) -> void:
	if _syncing:
		return
	_environment.volumetric_fog_length = value
	_update_value_labels()


func _on_glow_enabled_toggled(enabled: bool) -> void:
	if _syncing:
		return
	_environment.glow_enabled = enabled


func _on_glow_intensity_changed(value: float) -> void:
	if _syncing:
		return
	_environment.glow_intensity = value
	_update_value_labels()


func _on_glow_strength_changed(value: float) -> void:
	if _syncing:
		return
	_environment.glow_strength = value
	_update_value_labels()


func _on_glow_bloom_changed(value: float) -> void:
	if _syncing:
		return
	_environment.glow_bloom = value
	_update_value_labels()


func _on_glow_hdr_threshold_changed(value: float) -> void:
	if _syncing:
		return
	_environment.glow_hdr_threshold = value
	_update_value_labels()


func _on_background_color_changed(color: Color) -> void:
	if _syncing:
		return
	_environment.background_color = color


func _on_copy_pressed() -> void:
	if _environment == null:
		return
	var lines: PackedStringArray = [
		"ambient_light_energy = %s" % _format_float(_environment.ambient_light_energy),
		"ambient_light_color = %s" % _format_color(_environment.ambient_light_color),
		"fog_enabled = %s" % _environment.fog_enabled,
		"fog_density = %s" % _format_float(_environment.fog_density),
		"fog_light_color = %s" % _format_color(_environment.fog_light_color),
		"fog_light_energy = %s" % _format_float(_environment.fog_light_energy),
		"fog_sun_scatter = %s" % _format_float(_environment.fog_sun_scatter),
		"volumetric_fog_enabled = %s" % _environment.volumetric_fog_enabled,
		"volumetric_fog_density = %s" % _format_float(_environment.volumetric_fog_density),
		"volumetric_fog_albedo = %s" % _format_color(_environment.volumetric_fog_albedo),
		"volumetric_fog_emission = %s" % _format_color(_environment.volumetric_fog_emission),
		("volumetric_fog_emission_energy = %s"
				% _format_float(_environment.volumetric_fog_emission_energy)),
		"volumetric_fog_anisotropy = %s" % _format_float(_environment.volumetric_fog_anisotropy),
		"volumetric_fog_length = %s" % _format_float(_environment.volumetric_fog_length),
		"glow_enabled = %s" % _environment.glow_enabled,
		"glow_intensity = %s" % _format_float(_environment.glow_intensity),
		"glow_strength = %s" % _format_float(_environment.glow_strength),
		"glow_bloom = %s" % _format_float(_environment.glow_bloom),
		"glow_hdr_threshold = %s" % _format_float(_environment.glow_hdr_threshold),
		"background_color = %s" % _format_color(_environment.background_color),
	]
	DisplayServer.clipboard_set("\n".join(lines))


func _format_float(value: float) -> String:
	return "%.4f" % value


func _format_color(color: Color) -> String:
	return "Color(%.3f, %.3f, %.3f, %.3f)" % [color.r, color.g, color.b, color.a]
