class_name GraphicsLook
extends RefCounted
## The "look" settings of the graphics configuration (the colour grade, the exposure, reflections,
## bloom and the upscaler), applied to the viewport and to a scene's WorldEnvironment.
## GraphicsSettings owns the values and the presets and calls this; everything here is a pure
## function of those values, so a preset is always the same picture. See AGENT_TASKS/071.

## The colour grade: [contrast, saturation, brightness] by level (none, natural, vivid, filmic).
const GRADES: Array = [[1.0, 1.0, 1.0], [1.06, 1.1, 1.0], [1.12, 1.28, 1.0], [1.14, 0.94, 0.98]]
const GRADE_NAMES: PackedStringArray = ["None", "Natural", "Vivid", "Filmic"]
const UPSCALER_NAMES: PackedStringArray = ["Off", "FSR 1", "FSR 2"]
const REFLECTION_NAMES: PackedStringArray = ["Off", "Low", "High"]


## The viewport's part: the upscaler (and its sharpness) and the debanding of smooth gradients.
## FSR 2 does its own temporal anti-aliasing, so it replaces the TAA / MSAA / FXAA choice.
static func apply_viewport(viewport: Viewport, values: Dictionary) -> void:
	var upscaler := int(values.get(&"upscaler", 0))
	var scale := float(values.get(&"render_scale", 1.0))
	match upscaler:
		2:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if scale < 0.999 \
					else Viewport.SCALING_3D_MODE_BILINEAR
		1:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.999 \
					else Viewport.SCALING_3D_MODE_BILINEAR
		_:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.fsr_sharpness = 0.2
	viewport.use_debanding = bool(values.get(&"debanding", false))
	viewport.texture_mipmap_bias = -0.5 if upscaler > 0 and scale < 0.999 else 0.0
	if viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2:
		viewport.use_taa = false
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


## The environment's part: the grade, the reflections, the bloom and the auto exposure.
static func apply_environment(world_environment: WorldEnvironment, values: Dictionary) -> void:
	var environment := world_environment.environment
	if environment == null:
		return
	var grade: Array = GRADES[clampi(int(values.get(&"colour_grade", 0)), 0, GRADES.size() - 1)]
	environment.adjustment_enabled = int(values.get(&"colour_grade", 0)) > 0
	environment.adjustment_contrast = grade[0]
	environment.adjustment_saturation = grade[1]
	environment.adjustment_brightness = grade[2]
	var reflections := int(values.get(&"reflections", 0))
	environment.ssr_enabled = reflections > 0
	environment.ssr_max_steps = 48 if reflections == 1 else 96
	environment.ssr_fade_in = 0.15
	environment.ssr_fade_out = 2.0
	environment.ssr_depth_tolerance = 0.2
	if bool(values.get(&"glow", false)):
		# a bloom that catches the sun, the snow and wet ground without washing the picture out
		environment.glow_intensity = 0.7
		environment.glow_strength = 0.9
		environment.glow_bloom = 0.04
		environment.glow_hdr_threshold = 1.1
		environment.glow_hdr_scale = 1.6
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	if bool(values.get(&"auto_exposure", false)):
		var attributes := world_environment.camera_attributes as CameraAttributesPractical
		if attributes == null:
			attributes = CameraAttributesPractical.new()
			world_environment.camera_attributes = attributes
		attributes.auto_exposure_enabled = true
		attributes.auto_exposure_speed = 0.6 # (slow: an eye, not a flash)
		attributes.auto_exposure_scale = 0.4
		attributes.auto_exposure_min_sensitivity = 40.0 # (a dark night is not lit up to day)
		attributes.auto_exposure_max_sensitivity = 400.0
	elif world_environment.camera_attributes is CameraAttributesPractical:
		(world_environment.camera_attributes as CameraAttributesPractical).auto_exposure_enabled = false
