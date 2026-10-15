class_name WorldWind
extends RefCounted
## The wind every plant shader reads: a strength (0 calm .. 1 storm) and a direction on the ground.
## The two shader globals (`wind_strength`, `wind_direction`) are declared in project.godot.

static func set_wind(strength: float, direction: Vector2) -> void:
	RenderingServer.global_shader_parameter_set(&"wind_strength", clampf(strength, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"wind_direction", direction.normalized())


## How wet (0..1) and how snowed under (0..1) the ground and the plants look.
static func set_surface(wetness: float, snow: float) -> void:
	RenderingServer.global_shader_parameter_set(&"ground_wetness", clampf(wetness, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"snow_cover", clampf(snow, 0.0, 1.0))


## The season's colour: 0 summer green .. 1 full autumn (leaves and meadows turn).
static func set_autumn(amount: float) -> void:
	RenderingServer.global_shader_parameter_set(&"autumn", clampf(amount, 0.0, 1.0))


## 0 low-poly .. 1 realistic: every world shader blends its two looks with this.
static func set_realism(amount: float) -> void:
	RenderingServer.global_shader_parameter_set(&"realism", clampf(amount, 0.0, 1.0))
