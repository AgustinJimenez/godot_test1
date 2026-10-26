#include "planet_map_globe_native.h"

#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/input_event_mouse_button.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/classes/input_event_magnify_gesture.hpp>
#include <godot_cpp/classes/input_event_pan_gesture.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/world_environment.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const char *GLOBE_SHADER = R"SHADER(
shader_type spatial;
render_mode unshaded;
uniform sampler2D chart : source_color, filter_linear, repeat_disable;
uniform sampler2D detail : source_color, filter_linear, repeat_disable; // sharp chart of a part
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
)SHADER";

void PlanetMapGlobe::_bind_methods() {
	ADD_SIGNAL(MethodInfo("moved", PropertyInfo(Variant::VECTOR3, "dir")));
	ADD_SIGNAL(MethodInfo("zoomed", PropertyInfo(Variant::FLOAT, "factor")));
	ClassDB::bind_method(D_METHOD("set_chart", "texture"), &PlanetMapGlobe::set_chart);
	ClassDB::bind_method(D_METHOD("set_detail", "texture", "rect"), &PlanetMapGlobe::set_detail);
	ClassDB::bind_method(D_METHOD("set_zoom", "zoom"), &PlanetMapGlobe::set_zoom);
	ClassDB::bind_method(D_METHOD("set_sun", "dir"), &PlanetMapGlobe::set_sun);
	ClassDB::bind_method(D_METHOD("set_pin", "dir"), &PlanetMapGlobe::set_pin);
	ClassDB::bind_method(D_METHOD("look_at_direction", "dir"), &PlanetMapGlobe::look_at_direction);
	ClassDB::bind_method(D_METHOD("handle_input", "event"), &PlanetMapGlobe::handle_input);
	ClassDB::bind_method(D_METHOD("release"), &PlanetMapGlobe::release);
	ClassDB::bind_method(D_METHOD("facing"), &PlanetMapGlobe::facing);
}

PlanetMapGlobe::PlanetMapGlobe() {
	set_stretch(true);
	set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
	viewport = memnew(SubViewport);
	viewport->set_use_own_world_3d(true);
	viewport->set_msaa_3d(Viewport::MSAA_4X);
	viewport->set_handle_input_locally(false);
	add_child(viewport);
	Ref<Environment> environment;
	environment.instantiate();
	environment->set_background(Environment::BG_COLOR);
	environment->set_bg_color(Color(0.02f, 0.05f, 0.12f));
	WorldEnvironment *world_environment = memnew(WorldEnvironment);
	world_environment->set_environment(environment);
	viewport->add_child(world_environment);
	Ref<Shader> shader;
	shader.instantiate();
	shader->set_code(GLOBE_SHADER);
	material.instantiate();
	material->set_shader(shader);
	Ref<SphereMesh> sphere;
	sphere.instantiate();
	sphere->set_radius(1.0);
	sphere->set_height(2.0);
	sphere->set_radial_segments(128);
	sphere->set_rings(64);
	ball = memnew(MeshInstance3D);
	ball->set_mesh(sphere);
	ball->set_material_override(material);
	viewport->add_child(ball);
	Ref<StandardMaterial3D> pin_material;
	pin_material.instantiate();
	pin_material->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
	pin_material->set_albedo(Color(1.0f, 0.15f, 0.1f));
	Ref<SphereMesh> pin_mesh;
	pin_mesh.instantiate();
	pin_mesh->set_radius(0.018);
	pin_mesh->set_height(0.036);
	pin = memnew(MeshInstance3D);
	pin->set_mesh(pin_mesh);
	pin->set_material_override(pin_material);
	pin->set_visible(false);
	viewport->add_child(pin);
	camera = memnew(Camera3D);
	camera->set_fov(FOV);
	camera->set_near(0.002);
	camera->set_far(50.0);
	viewport->add_child(camera);
	aim();
}

// The picture on the ball (the map's, any layer).
void PlanetMapGlobe::set_chart(const Ref<Texture2D> &p_texture) {
	if (p_texture == shown) {
		return;
	}
	shown = p_texture;
	material->set_shader_parameter("chart", p_texture);
}

// The sharp chart of the part of the map `rect` (fractions of the map), drawn over the whole one.
void PlanetMapGlobe::set_detail(const Ref<Texture2D> &p_texture, const Rect2 &p_rect) {
	if (p_texture.is_null()) {
		material->set_shader_parameter("detail_rect", Vector4());
		detail_shown.unref();
		return;
	}
	if (p_texture != detail_shown) {
		detail_shown = p_texture;
		material->set_shader_parameter("detail", p_texture);
	}
	material->set_shader_parameter("detail_rect", Vector4(p_rect.position.x, p_rect.position.y, p_rect.size.x, p_rect.size.y));
}

// The map's zoom (1: the whole planet) as the camera's distance: the view takes the same part of the planet as the flat map's.
void PlanetMapGlobe::set_zoom(double p_zoom) {
	double span = Math_PI * ZOOM_SPAN / std::max(p_zoom, 1.0);
	distance = 1.0 + span / (2.0 * std::tan(Math::deg_to_rad(FOV) * 0.5));
	pin->set_scale(Vector3(1, 1, 1) * CLAMP((distance - 1.0) / 2.6, 0.02, 1.0));
	aim();
}

// Where the star is (the planet's unit direction): the night side of the ball is darkened.
void PlanetMapGlobe::set_sun(const Vector3 &p_dir) {
	material->set_shader_parameter("sun", Vector3(p_dir.x, p_dir.y, -p_dir.z));
}

// Puts the pin where the planet's unit direction `dir` is (the ball shows the picture as seen from outside, east to the right, which mirrors the
// planet's own axes along z).
void PlanetMapGlobe::set_pin(const Vector3 &p_dir) {
	pin->set_visible(p_dir != Vector3());
	if (pin->is_visible()) {
		pin->set_position(Vector3(p_dir.x, p_dir.y, -p_dir.z).normalized() * 1.01);
	}
}

// Turns the ball to face `dir` (a unit direction of the planet).
void PlanetMapGlobe::look_at_direction(const Vector3 &p_dir) {
	Vector3 seen = Vector3(p_dir.x, p_dir.y, -p_dir.z).normalized();
	yaw = std::atan2(seen.x, seen.z);
	pitch = CLAMP(std::asin(CLAMP((double)seen.y, -1.0, 1.0)), -1.4, 1.4);
	aim();
}

// Handles the mouse and the trackpad; true when the event was used.
bool PlanetMapGlobe::handle_input(const Ref<InputEvent> &p_event) {
	Ref<InputEventMouseButton> button = p_event;
	if (button.is_valid()) {
		if (button->get_button_index() == MOUSE_BUTTON_WHEEL_UP && button->is_pressed()) {
			emit_signal("zoomed", 1.25);
		} else if (button->get_button_index() == MOUSE_BUTTON_WHEEL_DOWN && button->is_pressed()) {
			emit_signal("zoomed", 0.8);
		} else if (button->get_button_index() == MOUSE_BUTTON_LEFT) {
			dragging = button->is_pressed();
		}
		return true;
	}
	Ref<InputEventMagnifyGesture> magnify = p_event;
	if (magnify.is_valid()) {
		emit_signal("zoomed", CLAMP((double)magnify->get_factor(), 0.5, 2.0));
		return true;
	}
	Ref<InputEventPanGesture> pan = p_event;
	if (pan.is_valid()) {
		emit_signal("zoomed", std::pow(1.25, -(double)pan->get_delta().y));
		return true;
	}
	Ref<InputEventMouseMotion> motion = p_event;
	if (motion.is_valid() && dragging) {
		double speed = 0.001 * (distance - 1.0) + 0.0045 * std::max(distance - 2.0, 0.0);
		yaw -= motion->get_relative().x * speed;
		pitch = CLAMP(pitch + motion->get_relative().y * speed, -1.45, 1.45);
		aim();
		emit_signal("moved", facing());
		return true;
	}
	return false;
}

// The unit direction of the planet the camera looks down on.
Vector3 PlanetMapGlobe::facing() const {
	Vector3 seen = camera->get_position().normalized();
	return Vector3(seen.x, seen.y, -seen.z);
}

void PlanetMapGlobe::aim() {
	Vector3 at = distance * Vector3(std::cos(pitch) * std::sin(yaw), std::sin(pitch), std::cos(pitch) * std::cos(yaw));
	camera->set_transform(Transform3D(Basis::looking_at(-at, Vector3(0, 1, 0)), at));
}
