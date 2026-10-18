class_name PlanetMapGlobe
extends SubViewportContainer
## The planet map as a small planet in 3D: a ball wearing the map's picture (whichever layer is
## showing, as sharp as the charting has got), turned with the mouse (drag), zoomed with the wheel
## or a pinch, and a pin where the player stands. The map shows it instead of the flat map (G).

const SHADER := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D chart : filter_linear, repeat_disable;
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
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float day = smoothstep(-0.12, 0.2, dot(n, normalize(sun)));
	colour *= 1.0 - night * (1.0 - day);
	ALBEDO = mix(colour, rim_colour, rim * 0.55);
}
"""

const MIN_DISTANCE := 1.35
const MAX_DISTANCE := 7.0

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
	_camera.fov = 40.0
	_camera.near = 0.05
	_camera.far = 50.0
	_viewport.add_child(_camera)
	_aim()


## The picture on the ball (the map's, any layer).
func set_chart(texture: Texture2D) -> void:
	if texture == _shown:
		return
	_shown = texture
	_material.set_shader_parameter(&"chart", texture)


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
	_distance = 3.2
	_aim()


## Handles the mouse and the trackpad; true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_by(0.88)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_by(1.14)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		return true
	if event is InputEventMagnifyGesture:
		_zoom_by(1.0 / clampf((event as InputEventMagnifyGesture).factor, 0.5, 2.0))
		return true
	if event is InputEventPanGesture:
		_zoom_by(pow(1.14, (event as InputEventPanGesture).delta.y))
		return true
	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var speed := 0.0045 * (_distance - 0.8)
		_yaw -= motion.relative.x * speed
		_pitch = clampf(_pitch + motion.relative.y * speed, -1.45, 1.45)
		_aim()
		return true
	return false


func _zoom_by(factor: float) -> void:
	_distance = clampf(_distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_aim()


func _aim() -> void:
	_camera.position = _distance * Vector3(cos(_pitch) * sin(_yaw), sin(_pitch),
			cos(_pitch) * cos(_yaw))
	_camera.look_at(Vector3.ZERO, Vector3.UP)
