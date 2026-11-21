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
	viewport.fsr_sharpness = float(values.get(&"fsr_sharpness", 0.2))
	viewport.use_debanding = bool(values.get(&"debanding", false))
	# things hidden behind hills and buildings are not drawn (the planet tiles carry occluders, see
	# PlanetTile._add_occluder), and the meshes of plants and rocks keep their detail longer
	var occlusion := bool(values.get(&"occlusion_culling", false))
	viewport.use_occlusion_culling = occlusion
	# (task 101) the mesh detail is its own setting now (it was tied to the occlusion switch): the error in pixels a mesh may show before a cheaper
	# level of detail takes over: Normal 2 (the engine's own), Sharp 1, Sharpest 0.5. PLANET_LOD_THRESHOLD overrides.
	var thresholds := [2.0, 1.0, 0.5]
	viewport.mesh_lod_threshold = float(OS.get_environment("PLANET_LOD_THRESHOLD")) if OS.has_environment("PLANET_LOD_THRESHOLD") \
			else float(thresholds[clampi(int(values.get(&"mesh_detail", 1)), 0, 2)])
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
	var brightness := float(values.get(&"brightness", 1.0)) # (task 101: the "Brightness" setting multiplies the grade's)
	environment.adjustment_enabled = int(values.get(&"colour_grade", 0)) > 0 or absf(brightness - 1.0) > 0.001
	environment.adjustment_contrast = grade[0]
	environment.adjustment_saturation = grade[1]
	environment.adjustment_brightness = float(grade[2]) * brightness
	# the AgX look (task 101): only with the AgX tone mapper; the others keep their own curve
	var agx_tuned := bool(values.get(&"agx_tuned", false)) and int(values.get(&"tone_mapper", Environment.TONE_MAPPER_FILMIC)) == Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.12 if agx_tuned else 1.0
	environment.tonemap_agx_contrast = 1.32 if agx_tuned else 1.25 # (1.25 is the engine's default)
	var reflections := int(values.get(&"reflections", 0))
	environment.ssr_enabled = reflections > 0
	environment.ssr_max_steps = 48 if reflections == 1 else 96
	environment.ssr_fade_in = 0.15
	environment.ssr_fade_out = 2.0
	environment.ssr_depth_tolerance = 0.2
	environment.sdfgi_enabled = bool(values.get(&"sdfgi", false))
	if environment.sdfgi_enabled:
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_min_cell_size = 1.0
		environment.sdfgi_cascades = 4
		environment.sdfgi_energy = 0.8
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
	_apply_depth_of_field(world_environment, int(values.get(&"depth_of_field", 0)))
	_apply_motion_blur(world_environment, int(values.get(&"motion_blur", 0)))


## (task 101) The far blur of the engine's camera attributes: what lies beyond a distance is blurred, the more the farther. The planet's horizon is
## always far, so Light blurs from 200 m and Strong from 80 m, both gently.
static func _apply_depth_of_field(world_environment: WorldEnvironment, level: int) -> void:
	var attributes := world_environment.camera_attributes as CameraAttributesPractical
	if level <= 0:
		if attributes != null:
			attributes.dof_blur_far_enabled = false
		return
	if attributes == null:
		attributes = CameraAttributesPractical.new()
		world_environment.camera_attributes = attributes
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 200.0 if level == 1 else 80.0
	attributes.dof_blur_far_transition = 600.0 if level == 1 else 400.0
	attributes.dof_blur_amount = 0.05 if level == 1 else 0.1


## (task 101) Motion blur: a compositor effect on the WorldEnvironment (components/motion_blur_effect.gd), made when first wanted and switched off, not removed.
static func _apply_motion_blur(world_environment: WorldEnvironment, level: int) -> void:
	var effect: MotionBlurEffect = null
	if world_environment.compositor != null:
		for candidate in world_environment.compositor.compositor_effects:
			if candidate is MotionBlurEffect:
				effect = candidate
	if level <= 0:
		if effect != null:
			effect.enabled = false
		return
	if effect == null:
		var compositor := world_environment.compositor if world_environment.compositor != null else Compositor.new()
		effect = MotionBlurEffect.new()
		var effects: Array[CompositorEffect] = compositor.compositor_effects.duplicate()
		effects.append(effect)
		compositor.compositor_effects = effects
		world_environment.compositor = compositor
	effect.strength = 0.5 if level == 1 else 1.0
	effect.enabled = true
