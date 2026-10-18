extends Node
## Persistent project-wide graphics configuration. The pause-menu UI edits
## this service; scenes only provide ordinary WorldEnvironment and light nodes.

signal settings_changed(preset: int)

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum AntiAliasing { OFF, FXAA, SMAA, TAA, MSAA_2X, MSAA_4X }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "graphics"
const PRESET_NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra", "Custom"]
const QUALITY_KEYS: Array[StringName] = [
	&"render_scale", &"anti_aliasing", &"shadow_quality",
	&"ssao", &"ssil", &"glow", &"cloud_quality",
	&"upscaler", &"debanding", &"colour_grade", &"auto_exposure", &"reflections", &"volumetric_fog",
	&"ground_detail", &"cloud_shadows", &"sdfgi",
]
const DEFAULT_VALUES: Dictionary = {
	&"render_scale": 1.0,
	&"anti_aliasing": AntiAliasing.TAA,
	&"shadow_quality": ShadowQuality.MEDIUM,
	&"ssao": true,
	&"ssil": false,
	&"glow": false,
	&"cloud_quality": 2,
	&"upscaler": 0, # 0 off, 1 FSR 1, 2 FSR 2 (only below 100% render scale)
	&"debanding": false,
	&"colour_grade": 0, # GraphicsLook.GRADE_NAMES
	&"auto_exposure": false,
	&"reflections": 0, # 0 off, 1 low, 2 high (screen space)
	&"volumetric_fog": false, # light shafts near the ground
	&"sdfgi": false, # bounced light near the camera (costly)
	&"cloud_shadows": false, # the clouds' shadow moving over the ground
	&"ground_detail": 1, # 0 plain, 1 the noise detail, 2 + fine bump, ripples, glints, 3 + finest
	&"vsync": true,
	&"max_fps": 120,
	&"tone_mapper": Environment.TONE_MAPPER_FILMIC,
	&"hdr": false,
}
const PRESETS: Dictionary = {
	Preset.LOW: {
		&"render_scale": 0.65,
		&"anti_aliasing": AntiAliasing.OFF,
		&"shadow_quality": ShadowQuality.OFF,
		&"ssao": false, &"ssil": false, &"glow": false, &"cloud_quality": 0,
		&"upscaler": 0, &"debanding": false, &"colour_grade": 0, &"auto_exposure": false,
		&"reflections": 0, &"volumetric_fog": false, &"ground_detail": 1,
		&"cloud_shadows": false,
	},
	Preset.MEDIUM: {
		&"render_scale": 0.8,
		&"anti_aliasing": AntiAliasing.FXAA,
		&"shadow_quality": ShadowQuality.LOW,
		&"ssao": false, &"ssil": false, &"glow": false, &"cloud_quality": 1,
		&"upscaler": 2, &"debanding": true, &"colour_grade": 1, &"auto_exposure": true,
		&"reflections": 0, &"volumetric_fog": false, &"ground_detail": 1,
		&"cloud_shadows": false,
	},
	Preset.HIGH: {
		&"render_scale": 1.0,
		&"anti_aliasing": AntiAliasing.TAA,
		&"shadow_quality": ShadowQuality.MEDIUM,
		&"ssao": true, &"ssil": false, &"glow": true, &"cloud_quality": 2,
		&"upscaler": 2, &"debanding": true, &"colour_grade": 1, &"auto_exposure": true,
		&"reflections": 0, &"volumetric_fog": true, &"ground_detail": 2,
		&"cloud_shadows": true,
	},
	Preset.ULTRA: {
		&"render_scale": 1.15,
		&"anti_aliasing": AntiAliasing.TAA,
		&"shadow_quality": ShadowQuality.HIGH,
		&"ssao": true, &"ssil": true, &"glow": true, &"cloud_quality": 2,
		&"upscaler": 2, &"debanding": true, &"colour_grade": 1, &"auto_exposure": true,
		&"reflections": 2, &"volumetric_fog": true, &"ground_detail": 3,
		&"cloud_shadows": true, &"sdfgi": true,
	},
}

var current_preset: Preset = Preset.HIGH
var _values := DEFAULT_VALUES.duplicate()
var _save_timer: Timer
var _ephemeral := false # a test preset from the environment: never saved


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.25
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)
	_load()
	_ephemeral_preset()
	get_tree().node_added.connect(_on_node_added)
	apply()


## `PLANET_PRESET=low|medium|high|ultra` (for pictures and tests): that preset is used for this run
## only, and nothing is written to the saved settings.
func _ephemeral_preset() -> void:
	if not OS.has_environment("PLANET_PRESET"):
		return
	var which := PRESET_NAMES.find(OS.get_environment("PLANET_PRESET").capitalize())
	if which < 0 or which >= Preset.CUSTOM:
		return
	_ephemeral = true
	current_preset = which as Preset
	for key: StringName in PRESETS[which]:
		_values[key] = PRESETS[which][key]


func get_preset_name(preset: int) -> String:
	return PRESET_NAMES[preset] if preset >= 0 and preset < PRESET_NAMES.size() else "Custom"


func get_graphics_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULT_VALUES.get(key))


func set_preset(preset: int) -> void:
	if preset < Preset.LOW or preset > Preset.CUSTOM:
		return
	current_preset = preset as Preset
	if preset != Preset.CUSTOM:
		var preset_values: Dictionary = PRESETS[preset]
		for key: StringName in preset_values:
			_values[key] = preset_values[key]
	apply()
	_queue_save()
	settings_changed.emit(current_preset)


func set_graphics_value(key: StringName, value: Variant) -> void:
	if not DEFAULT_VALUES.has(key):
		return
	_values[key] = _sanitize_value(key, value)
	if key in QUALITY_KEYS:
		current_preset = Preset.CUSTOM
	apply()
	_queue_save()
	settings_changed.emit(current_preset)


func apply() -> void:
	var viewport := get_tree().root as Viewport
	viewport.scaling_3d_scale = float(_values[&"render_scale"])
	_apply_anti_aliasing(viewport, int(_values[&"anti_aliasing"]))
	GraphicsLook.apply_viewport(viewport, _values)
	RenderingServer.global_shader_parameter_set(&"ground_detail", float(_values[&"ground_detail"]))
	Engine.max_fps = int(_values[&"max_fps"])
	var supported := DisplayServer.window_is_hdr_output_supported()
	get_tree().root.hdr_output_requested = bool(_values[&"hdr"]) and supported
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if bool(_values[&"vsync"])
			else DisplayServer.VSYNC_DISABLED)
	_apply_shadow_atlas(int(_values[&"shadow_quality"]))
	var scene := get_tree().current_scene
	if scene:
		_apply_scene_node(scene)


func _apply_anti_aliasing(viewport: Viewport, mode: int) -> void:
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	match mode:
		AntiAliasing.FXAA:
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AntiAliasing.SMAA:
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		AntiAliasing.TAA:
			viewport.use_taa = true
		AntiAliasing.MSAA_2X:
			viewport.msaa_3d = Viewport.MSAA_2X
		AntiAliasing.MSAA_4X:
			viewport.msaa_3d = Viewport.MSAA_4X


func _apply_shadow_atlas(quality: int) -> void:
	var atlas_size := 1024
	match quality:
		ShadowQuality.MEDIUM:
			atlas_size = 2048
		ShadowQuality.HIGH:
			atlas_size = 4096
	RenderingServer.directional_shadow_atlas_set_size(atlas_size, false)


func _apply_scene_node(node: Node) -> void:
	_apply_single_node(node)
	for child: Node in node.get_children():
		_apply_scene_node(child)


## Fog is deliberately not touched here - it's owned per-scene by whatever
## the scene's own Environment resource bakes in (tunable live via the debug
## menu's Vision/Atmosphere panel, see ui/vision_debug_panel.gd), not a
## quality-preset toggle. It used to be one and would silently re-enable
## itself on every settings apply() regardless of what a scene had baked in.
func _apply_single_node(node: Node) -> void:
	if node is WorldEnvironment:
		var world_environment := node as WorldEnvironment
		var environment := world_environment.environment
		if environment:
			environment.ssao_enabled = bool(_values[&"ssao"])
			environment.ssil_enabled = bool(_values[&"ssil"])
			environment.glow_enabled = bool(_values[&"glow"])
			environment.tonemap_mode = int(_values[&"tone_mapper"]) as Environment.ToneMapper
			GraphicsLook.apply_environment(world_environment, _values)
	elif node is DirectionalLight3D:
		var light := node as DirectionalLight3D
		var quality := int(_values[&"shadow_quality"])
		light.shadow_enabled = quality != ShadowQuality.OFF
		match quality:
			ShadowQuality.LOW:
				light.directional_shadow_max_distance = 25.0
			ShadowQuality.MEDIUM:
				light.directional_shadow_max_distance = 50.0
			ShadowQuality.HIGH:
				light.directional_shadow_max_distance = 90.0


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node is DirectionalLight3D:
		_apply_single_node.call_deferred(node)


func _sanitize_value(key: StringName, value: Variant) -> Variant:
	var clean: Variant = value
	match key:
		&"render_scale":
			clean = clampf(float(value), 0.5, 1.25)
		&"anti_aliasing":
			clean = clampi(int(value), AntiAliasing.OFF, AntiAliasing.MSAA_4X)
		&"shadow_quality":
			clean = clampi(int(value), ShadowQuality.OFF, ShadowQuality.HIGH)
		&"max_fps":
			clean = clampi(int(value), 30, 240)
		&"cloud_quality":
			clean = clampi(int(value), 0, 2)
		&"upscaler", &"reflections":
			clean = clampi(int(value), 0, 2)
		&"ground_detail":
			clean = clampi(int(value), 0, 3)
		&"colour_grade":
			clean = clampi(int(value), 0, GraphicsLook.GRADE_NAMES.size() - 1)
		&"tone_mapper":
			clean = clampi(int(value), Environment.TONE_MAPPER_LINEAR, Environment.TONE_MAPPER_AGX)
		&"ssao", &"ssil", &"glow", &"vsync", &"hdr", &"debanding":
			clean = bool(value)
		&"auto_exposure", &"volumetric_fog", &"cloud_shadows", &"sdfgi":
			clean = bool(value)
	return clean


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	current_preset = clampi(
			int(config.get_value(SECTION, "preset", Preset.HIGH)),
			Preset.LOW, Preset.CUSTOM) as Preset
	for key: StringName in DEFAULT_VALUES:
		_values[key] = _sanitize_value(
				key, config.get_value(SECTION, String(key), DEFAULT_VALUES[key]))


func _queue_save() -> void:
	_save_timer.start()


func _save() -> void:
	if _ephemeral:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "preset", current_preset)
	for key: StringName in _values:
		config.set_value(SECTION, String(key), _values[key])
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save graphics settings: %s" % error_string(error))
