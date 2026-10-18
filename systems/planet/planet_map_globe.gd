class_name PlanetMapGlobe
extends SubViewportContainer
## The planet map as a small planet in 3D: a ball wearing the map's picture (whichever layer is
## showing, as sharp as the charting has got), turned with the mouse (drag), zoomed with the wheel
## or a pinch, and a pin where the player stands. The map shows it instead of the flat map (G).

const SHADER := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D chart : source_color, filter_linear, repeat_disable;
uniform sampler2D detail : source_color, filter_linear, repeat_disable; // the sharp chart of a part of the map
uniform vec4 detail_rect = vec4(0.0); // its x, y, width, height as fractions of the map (0: none)
uniform vec3 rim_colour = vec3(0.45, 0.65, 1.0);
uniform vec3 sun = vec3(0.0, 0.0, 1.0); // toward the star, on the ball
uniform float night = 0.55; // how dark the night side gets (0 none)
varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 n = normalize(dir);
	// the map's picture: longitude along u, as seen from outside the ball (east to the right)
	float u = (PI - atan(n.z, n.x)) / TAU;
	float v = 0.5 - asin(clamp(n.y, -1.0, 1.0)) / PI;
	vec3 colour = texture(chart, vec2(u, v)).rgb;
	if (detail_rect.z > 0.0) {
		float dx = fract(u - detail_rect.x);
		float dy = (v - detail_rect.y) / detail_rect.w;
		if (dx < detail_rect.z && dy >= 0.0 && dy <= 1.0) {
			colour = texture(detail, vec2(dx / detail_rect.z, dy)).rgb;
		}
	}
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float day = smoothstep(-0.12, 0.2, dot(n, normalize(sun)));
	colour *= 1.0 - night * (1.0 - day);
	ALBEDO = mix(colour, rim_colour, rim * 0.55);
}
"""

const ZOOM_SPAN := 0.6 ## how much of the way round the sky the view takes at zoom 1 (x PI)
const FOV := 40.0

## the globe was turned (its centre as a unit direction of the planet); the wheel or a pinch asks for a
## zoom by this factor (more than 1: closer), as on the flat map
signal moved(dir: Vector3)
signal zoomed(factor: float)

var _viewport: SubViewport
var _camera: Camera3D
var _ball: MeshInstance3D
var _pin: MeshInstance3D
var _material: ShaderMaterial
var _yaw := 0.0
var _pitch := 0.3
var _distance := 3.2
var _dragging := false
var _shown: Texture2D
var _detail_shown: Texture2D


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.05, 0.12)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	_ball = MeshInstance3D.new()
	_ball.mesh = sphere
	_ball.material_override = _material
	_viewport.add_child(_ball)
	var pin_material := StandardMaterial3D.new()
	pin_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pin_material.albedo_color = Color(1.0, 0.15, 0.1)
	var pin := SphereMesh.new()
	pin.radius = 0.018
	pin.height = 0.036
	_pin = MeshInstance3D.new()
	_pin.mesh = pin
	_pin.material_override = pin_material
	_pin.visible = false
	_viewport.add_child(_pin)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 0.002
	_camera.far = 50.0
	_viewport.add_child(_camera)
	_aim()


## The picture on the ball (the map's, any layer).
func set_chart(texture: Texture2D) -> void:
	if texture == _shown:
		return
	_shown = texture
	_material.set_shader_parameter(&"chart", texture)


## The sharp chart of the part of the map `rect` (fractions of the map), drawn over the whole one.
func set_detail(texture: Texture2D, rect: Rect2) -> void:
	if texture == null:
		_material.set_shader_parameter(&"detail_rect", Vector4())
		_detail_shown = null
		return
	if texture != _detail_shown:
		_detail_shown = texture
		_material.set_shader_parameter(&"detail", texture)
	_material.set_shader_parameter(&"detail_rect",
			Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


## The map's zoom (1: the whole planet) as the camera's distance: the view takes the same part of the
## planet as the flat map's.
func set_zoom(zoom: float) -> void:
	var span := PI * ZOOM_SPAN / maxf(zoom, 1.0)
	_distance = 1.0 + span / (2.0 * tan(deg_to_rad(FOV) * 0.5))
	_pin.scale = Vector3.ONE * clampf((_distance - 1.0) / 2.6, 0.02, 1.0)
	_aim()


## Where the star is (the planet's unit direction): the night side of the ball is darkened.
func set_sun(dir: Vector3) -> void:
	_material.set_shader_parameter(&"sun", Vector3(dir.x, dir.y, -dir.z))


## Puts the pin where the planet's unit direction `dir` is (the ball shows the picture as seen from
## outside, east to the right, which mirrors the planet's own axes along z).
func set_pin(dir: Vector3) -> void:
	_pin.visible = dir != Vector3.ZERO
	if _pin.visible:
		_pin.position = Vector3(dir.x, dir.y, -dir.z).normalized() * 1.01


## Turns the ball to face `dir` (a unit direction of the planet).
func look_at_direction(dir: Vector3) -> void:
	var seen := Vector3(dir.x, dir.y, -dir.z).normalized()
	_yaw = atan2(seen.x, seen.z)
	_pitch = clampf(asin(clampf(seen.y, -1.0, 1.0)), -1.4, 1.4)
	_aim()


## Handles the mouse and the trackpad; true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoomed.emit(1.25)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoomed.emit(0.8)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		return true
	if event is InputEventMagnifyGesture:
		zoomed.emit(clampf((event as InputEventMagnifyGesture).factor, 0.5, 2.0))
		return true
	if event is InputEventPanGesture:
		zoomed.emit(pow(1.25, -(event as InputEventPanGesture).delta.y))
		return true
	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var speed := 0.001 * (_distance - 1.0) + 0.0045 * maxf(_distance - 2.0, 0.0)
		_yaw -= motion.relative.x * speed
		_pitch = clampf(_pitch + motion.relative.y * speed, -1.45, 1.45)
		_aim()
		moved.emit(facing())
		return true
	return false


## The mouse button went up elsewhere: the turning stops.
func release() -> void:
	_dragging = false


## The unit direction of the planet the camera looks down on.
func facing() -> Vector3:
	var seen := _camera.position.normalized()
	return Vector3(seen.x, seen.y, -seen.z)


func _aim() -> void:
	_camera.position = _distance * Vector3(cos(_pitch) * sin(_yaw), sin(_pitch),
			cos(_pitch) * cos(_yaw))
	_camera.look_at(Vector3.ZERO, Vector3.UP)
