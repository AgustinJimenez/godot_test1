extends Node
## Persistent project-wide graphics configuration. The pause-menu UI edits
## this service; scenes only provide ordinary WorldEnvironment and light nodes.

signal settings_changed(preset: int)

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum AntiAliasing { OFF, FXAA, SMAA, TAA, MSAA_2X, MSAA_4X, MSAA_8X }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "graphics"
const PRESET_NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra", "Custom"]
const QUALITY_KEYS: Array[StringName] = [
	&"render_scale", &"anti_aliasing", &"shadow_quality",
	&"ssao", &"ssil", &"glow", &"cloud_quality",
	&"upscaler", &"debanding", &"colour_grade", &"auto_exposure", &"reflections", &"volumetric_fog",
	&"ground_detail", &"cloud_shadows", &"sdfgi", &"decals",
	&"occlusion_culling", &"particles", &"plant_range", &"tree_range", &"plant_bend", &"plant_shadows", &"mesh_detail",
	&"grass_density", &"grass_range", &"vegetation_fade", &"far_tree_density", &"terrain_range",
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
	&"particles": false, # dust and pollen in the air
	&"occlusion_culling": false, # skip what is hidden; keep mesh detail longer
	&"decals": false, # footprints in snow, sand and mud
	# bounced light near the camera (experimental: it reset the GPU in a coast view, so no preset
	# turns it on)
	&"sdfgi": false,
	&"cloud_shadows": false, # the clouds' shadow moving over the ground
	&"ground_detail": 1, # 0 plain, 1 the noise detail, 2 + fine bump, ripples, glints, 3 + finest
	&"plant_range": 1, # how far shrubs and ground cover are drawn: 0 near, 1 medium, 2 far (task 101)
	&"tree_range": 1, # how far the trees are drawn: 0 short (1.5 km), 1 medium (3 km), 2 far (to the horizon) (task 101)
	&"plant_bend": 1, # plants that bend under the walker: 0 none, 1 a few, 2 all (task 101: the bending costs CPU)
	&"voxel_ground": true, # caves and digging, a GAME feature (the ground as a voxel terrain; the lab reads it at start: restart to change). Costs ~5 ms of CPU a frame and hitches on a weak machine: on in every preset, a toggle for the player (task 101)
	&"plant_shadows": 2, # what casts a shadow: 0 no foliage, 1 trees only, 2 trees and plants (~3 ms; task 101)
	&"mesh_detail": 1, # how long meshes keep their detail: 0 normal (2 px of error), 1 sharp (1 px), 2 sharpest (0.5 px). Sharp costs about 10 ms of GPU on High against Normal (task 101)
	&"grass_density": 1, # tufts of the ground grass: 0 sparse (1.5x apart), 1 normal, 2 dense (0.8x apart) (task 101)
	&"grass_range": 2, # how far the grass is drawn: 0 half, 1 three quarters, 2 all (task 101)
	&"vegetation_fade": true, # plants and trees dither in and out at their range (off: cut at once, less overdraw) (task 101)
	&"far_tree_density": 0, # the trees beyond the middle distance: 0 all, 1 every second, 2 every fourth (task 101)
	&"terrain_range": 1, # the voxel ground's view: 0 short (1 km), 1 normal (2 km), 2 far (4 km); the lab reads it at start (task 101)
	# not part of a preset (a taste or the machine, not a quality level):
	&"fov": 75.0, # the player's field of view (degrees)
	&"brightness": 1.0, # a multiplier on the picture's brightness
	&"agx_tuned": false, # with the AgX tone mapper: a little more exposure and contrast (1.12 and 1.32, from the CodingQuests village article) instead of the engine's own (1.0, 1.25)
	&"film_grain": 0, # 0 off, 1 light, 2 strong
	&"depth_of_field": 0, # the far blur: 0 off, 1 light, 2 strong
	&"motion_blur": 0, # 0 off, 1 light, 2 strong (a compositor effect: needs the velocity buffer)
	&"fsr_sharpness": 0.2, # the upscaler's sharpening (Godot: 0 sharpest, 2 softest)
	&"window_mode": -1, # -1 as launched, 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen
	&"window_width": 0, # the windowed size (0 as launched)
	&"window_height": 0,
	&"monitor": -1, # -1 as launched
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
		&"tree_range": 0, &"plant_range": 0, &"plant_bend": 0,
		&"plant_shadows": 0,
		&"grass_density": 0, &"grass_range": 0, &"vegetation_fade": false, &"far_tree_density": 0, &"terrain_range": 0,
		&"mesh_detail": 0,
	},
	Preset.MEDIUM: {
		&"render_scale": 0.8,
		&"anti_aliasing": AntiAliasing.SMAA,
		&"shadow_quality": ShadowQuality.LOW,
		&"ssao": false, &"ssil": false, &"glow": false, &"cloud_quality": 1,
		&"upscaler": 0, &"debanding": true, &"colour_grade": 1, &"auto_exposure": true,
		&"reflections": 0, &"volumetric_fog": false, &"ground_detail": 1,
		&"cloud_shadows": false,
		&"tree_range": 0, &"plant_range": 1, &"plant_bend": 1,
		&"plant_shadows": 1,
		&"grass_density": 1, &"grass_range": 1, &"vegetation_fade": true, &"far_tree_density": 0, &"terrain_range": 1,
		&"mesh_detail": 0,
	},
	Preset.HIGH: {
		&"render_scale": 1.0,
		&"anti_aliasing": AntiAliasing.TAA,
		&"shadow_quality": ShadowQuality.MEDIUM,
		&"ssao": true, &"ssil": false, &"glow": true, &"cloud_quality": 2,
		&"upscaler": 2, &"debanding": true, &"colour_grade": 1, &"auto_exposure": true,
		&"reflections": 0, &"volumetric_fog": true, &"ground_detail": 2,
		&"cloud_shadows": true, &"decals": true, &"occlusion_culling": true, &"particles": true,
		&"tree_range": 1, &"plant_range": 1, &"plant_bend": 1,
		&"plant_shadows": 2,
		&"grass_density": 1, &"grass_range": 2, &"vegetation_fade": true, &"far_tree_density": 0, &"terrain_range": 1,
		&"mesh_detail": 1,
	},
	Preset.ULTRA: {
		&"render_scale": 1.15,
		&"anti_aliasing": AntiAliasing.TAA,
		&"shadow_quality": ShadowQuality.HIGH,
		&"ssao": true, &"ssil": true, &"glow": true, &"cloud_quality": 2,
		&"upscaler": 2, &"debanding": true, &"colour_grade": 1, &"auto_exposure": true,
		&"reflections": 2, &"volumetric_fog": true, &"ground_detail": 3,
		&"cloud_shadows": true, &"sdfgi": false, &"decals": true,
		&"occlusion_culling": true, &"particles": true,
		&"tree_range": 2, &"plant_range": 2, &"plant_bend": 2,
		&"plant_shadows": 2,
		&"grass_density": 1, &"grass_range": 2, &"vegetation_fade": true, &"far_tree_density": 0, &"terrain_range": 1,
		&"mesh_detail": 1,
	},
}

var current_preset: Preset = Preset.HIGH
var _values := DEFAULT_VALUES.duplicate()
var _save_timer: Timer
var _ephemeral := false # a test preset from the environment: never saved
var _grain_layer: CanvasLayer
var _grain_material: ShaderMaterial
var _window_signature: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.25
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)
	var first_run := not FileAccess.file_exists(SETTINGS_PATH)
	_load()
	_ephemeral_preset()
	if first_run and not _ephemeral:
		_first_run_preset()
	get_tree().node_added.connect(_on_node_added)
	apply()


## `PLANET_PRESET=low|medium|high|ultra` (for pictures and tests): that preset is used for this run
## only, and nothing is written to the saved settings.
func _ephemeral_preset() -> void:
	if OS.has_environment("PLANET_PRESET"):
		var which := PRESET_NAMES.find(OS.get_environment("PLANET_PRESET").capitalize())
		if which >= 0 and which < Preset.CUSTOM:
			_ephemeral = true
			current_preset = which as Preset
			for key: StringName in PRESETS[which]:
				_values[key] = PRESETS[which][key]
	# `PLANET_GFX=key=value,key=value` (task 101): single settings on top of the preset, for this run only (the cost of one option)
	if OS.has_environment("PLANET_GFX"):
		_ephemeral = true
		for pair in OS.get_environment("PLANET_GFX").split(","):
			var key := StringName(pair.get_slice("=", 0))
			if not DEFAULT_VALUES.has(key):
				continue
			var text := pair.get_slice("=", 1)
			var old: Variant = DEFAULT_VALUES[key]
			_values[key] = _sanitize_value(key, (text == "true") if old is bool else (text.to_float() if old is float else text.to_int()))


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
	_apply_film_grain(int(_values[&"film_grain"]))
	_apply_window()
	if OS.has_environment("PLANET_SOFT_SHADOW"): # (task 101 experiment) the soft shadow filter quality 0..5
		RenderingServer.directional_soft_shadow_filter_set_quality(int(OS.get_environment("PLANET_SOFT_SHADOW")) as RenderingServer.ShadowQuality)
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
		AntiAliasing.MSAA_8X:
			viewport.msaa_3d = Viewport.MSAA_8X


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
	elif node is Camera3D:
		if node.name == &"Camera3D" and node.get_parent() != null and node.get_parent().name == &"HeadPivot": # (the player's eye; other cameras keep their own)
			(node as Camera3D).fov = float(_values[&"fov"])
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


## (task 101) A moving grain over the picture, under the interface: a canvas layer behind the default one, made when first wanted.
func _apply_film_grain(level: int) -> void:
	if level <= 0:
		if _grain_layer != null:
			_grain_layer.visible = false
		return
	if _grain_layer == null:
		_grain_layer = CanvasLayer.new()
		_grain_layer.layer = -1
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grain_material = ShaderMaterial.new()
		_grain_material.shader = load("res://shaders/post/film_grain.gdshader")
		rect.material = _grain_material
		_grain_layer.add_child(rect)
		add_child(_grain_layer)
	_grain_layer.visible = true
	_grain_material.set_shader_parameter(&"strength", 0.035 if level == 1 else 0.075)


## (task 101) The window: only once the player has chosen something (-1 and 0 mean "as launched"), never in a test run (a preset from the
## environment, a headless run, or a launch with its own --resolution / --fullscreen / --screen), and only when the choice changed.
func _apply_window() -> void:
	if _ephemeral or DisplayServer.get_name() == "headless":
		return
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--resolution") or argument in ["--fullscreen", "--windowed", "--screen", "-f", "-w"]:
			return
	var mode := int(_values[&"window_mode"])
	var monitor := int(_values[&"monitor"])
	var width := int(_values[&"window_width"])
	var height := int(_values[&"window_height"])
	if mode < 0 and monitor < 0 and width <= 0:
		return
	var signature := [mode, monitor, width, height]
	if signature == _window_signature:
		return
	_window_signature = signature
	if monitor >= 0 and monitor < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(monitor)
	match mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if width > 0 and height > 0:
				DisplayServer.window_set_size(Vector2i(width, height))
				var screen := DisplayServer.window_get_current_screen()
				var area := DisplayServer.screen_get_usable_rect(screen)
				DisplayServer.window_set_position(area.position + (area.size - Vector2i(width, height)) / 2)


## (task 101) A first run (no saved settings) starts on the preset that suits the machine instead of always High.
func _first_run_preset() -> void:
	var adapter := RenderingServer.get_video_adapter_name()
	if DisplayServer.get_name() == "headless" or adapter == "":
		return
	var preset := preset_for_hardware(adapter, int(RenderingServer.get_video_adapter_type()), OS.get_processor_count())
	print("GRAPHICS first run on %s (%d threads): the %s preset" % [adapter, OS.get_processor_count(), PRESET_NAMES[preset]])
	set_preset(preset)


## The preset for a graphics card by its name and kind (RenderingDevice.DeviceType: 1 integrated, 3 virtual, 4 CPU) and the number
## of processor threads. A guess by the card's generation: Ultra is never chosen for the player.
static func preset_for_hardware(adapter: String, device_type: int, threads: int) -> int:
	var upper := adapter.to_upper()
	var preset: int = Preset.MEDIUM
	if device_type == 1 or device_type == 3 or device_type == 4 \
			or upper.contains("UHD") or upper.contains("IRIS") or upper.contains("INTEL(R) HD") \
			or upper.contains("RADEON GRAPHICS") or upper.contains("RADEON(TM) GRAPHICS") or upper.contains("INTEGRATED"):
		preset = Preset.LOW
	else:
		var pattern := RegEx.new()
		pattern.compile("(RTX|GTX|RX|ARC)(?:\\(TM\\))?\\s*[AB]?\\s*(\\d{3,4})")
		var found := pattern.search(upper)
		if found != null:
			var family := found.get_string(1)
			var number := found.get_string(2).to_int()
			if family == "RTX":
				preset = Preset.HIGH if number >= 3070 else Preset.MEDIUM
			elif family == "GTX":
				preset = Preset.MEDIUM if number >= 1070 or number == 1650 or number == 1660 else Preset.LOW
			elif family == "RX":
				preset = Preset.HIGH if number >= 6800 else (Preset.MEDIUM if number >= 5600 else Preset.LOW)
			else: # Arc
				preset = Preset.HIGH if number >= 770 else Preset.MEDIUM
	if threads < 6 and preset > Preset.LOW:
		preset -= 1
	return preset


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node is DirectionalLight3D or node is Camera3D:
		_apply_single_node.call_deferred(node)


func _sanitize_value(key: StringName, value: Variant) -> Variant:
	var clean: Variant = value
	match key:
		&"render_scale":
			clean = clampf(float(value), 0.5, 1.25)
		&"anti_aliasing":
			clean = clampi(int(value), AntiAliasing.OFF, AntiAliasing.MSAA_8X)
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
		&"plant_range", &"tree_range", &"plant_bend", &"plant_shadows", &"grass_density", &"grass_range", &"far_tree_density", &"terrain_range", &"film_grain", &"depth_of_field", &"motion_blur":
			clean = clampi(int(value), 0, 2)
		&"fov":
			clean = clampf(float(value), 60.0, 110.0)
		&"brightness":
			clean = clampf(float(value), 0.7, 1.3)
		&"fsr_sharpness":
			clean = clampf(float(value), 0.0, 2.0)
		&"window_mode":
			clean = clampi(int(value), -1, 2)
		&"monitor":
			clean = clampi(int(value), -1, 15)
		&"window_width", &"window_height":
			clean = clampi(int(value), 0, 16384)
		&"vegetation_fade":
			clean = bool(value)
		&"colour_grade":
			clean = clampi(int(value), 0, GraphicsLook.GRADE_NAMES.size() - 1)
		&"tone_mapper":
			clean = clampi(int(value), Environment.TONE_MAPPER_LINEAR, Environment.TONE_MAPPER_AGX)
		&"ssao", &"ssil", &"glow", &"vsync", &"hdr", &"debanding", &"voxel_ground", &"agx_tuned":
			clean = bool(value)
		&"auto_exposure", &"volumetric_fog", &"cloud_shadows", &"sdfgi":
			clean = bool(value)
		&"decals", &"occlusion_culling", &"particles":
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
	# (task 101) a settings file saved before an option existed has no value for it: it takes the chosen preset's value (Low, Medium...), not the plain default
	if current_preset != Preset.CUSTOM and PRESETS.has(current_preset):
		var preset_values: Dictionary = PRESETS[current_preset]
		for key: StringName in preset_values:
			if not config.has_section_key(SECTION, String(key)):
				_values[key] = _sanitize_value(key, preset_values[key])


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
