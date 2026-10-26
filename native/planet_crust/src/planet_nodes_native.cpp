#include "planet_nodes_native.h"

#include "planet_frame_native.h"
#include "planet_settings_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/curve.hpp>
#include <godot_cpp/classes/gradient.hpp>
#include <godot_cpp/classes/gradient_texture2d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/scene_tree_timer.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/timer.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// ---- PlanetCrustGuard ----

void PlanetCrustGuard::_bind_methods() {
	NP_BIND_OBJECT(PlanetCrustGuard, planet)
	NP_BIND_OBJECT(PlanetCrustGuard, target)
	NP_BIND(PlanetCrustGuard, Variant::INT, rescues)
}

void PlanetCrustGuard::_ready() {
	Ref<PlanetSettings> settings = get_planet()->get("settings");
	Ref<SphereMesh> ball;
	ball.instantiate();
	ball->set_radius(settings->get_radius() * 0.97);
	ball->set_height(ball->get_radius() * 2.0);
	ball->set_radial_segments(48);
	ball->set_rings(24);
	Ref<StandardMaterial3D> black;
	black.instantiate();
	black->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
	black->set_albedo(Color(0, 0, 0, 1));
	black->set_flag(BaseMaterial3D::FLAG_DISABLE_FOG, true);
	core = memnew(MeshInstance3D);
	core->set_mesh(ball);
	core->set_material_override(black);
	core->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	core->set_extra_cull_margin(16384.0);
	add_child(core);
}

void PlanetCrustGuard::_physics_process(double) {
	Object *planet_object = get_planet();
	if (planet_object == nullptr) {
		return;
	}
	Ref<PlanetFrame> frame = planet_object->get("frame");
	core->set_global_position(frame->to_world(Vector3()));
	Node3D *player = Object::cast_to<Node3D>(get_target());
	if (player == nullptr || (bool)planet_object->get("loading")) {
		return;
	}
	Vector3 here = player->get_global_position();
	Dictionary ground = planet_object->call("ground_at", here.x, here.z, here.y);
	double ground_y = ground["y"];
	if (here.y < ground_y - PLAYER_DEPTH) {
		player->set_global_position(Vector3(here.x, ground_y + 1.0, here.z));
		player->set("velocity", Vector3());
		rescues += 1;
	}
}

void PlanetCrustGuard::_process(double) {
	Object *planet_object = get_planet();
	if (get_target() == nullptr || planet_object == nullptr || (bool)planet_object->get("loading")) {
		return;
	}
	Camera3D *camera = get_viewport()->get_camera_3d();
	if (camera == nullptr) {
		return;
	}
	Vector3 at = camera->get_global_position();
	Dictionary ground = planet_object->call("ground_at", at.x, at.z, at.y);
	double ground_y = ground["y"];
	if (at.y < ground_y + CAMERA_CLEARANCE) {
		camera->set_global_position(Vector3(at.x, ground_y + CAMERA_CLEARANCE, at.z));
	}
}

// ---- PlanetUndergrowth ----

void PlanetUndergrowth::_bind_methods() {
	NP_BIND_OBJECT(PlanetUndergrowth, planet)
	NP_BIND_OBJECT(PlanetUndergrowth, player)
}

void PlanetUndergrowth::_ready() {
	// after the player has made its velocity for the frame, like WorldSwim
	set_physics_process_priority(100);
}

void PlanetUndergrowth::_physics_process(double p_delta) {
	Object *player_object = get_player();
	if (player_object == nullptr || get_planet() == nullptr) {
		return;
	}
	Node3D *player_node = Object::cast_to<Node3D>(player_object);
	Vector3 here = player_node->get_global_position();
	since += p_delta;
	if (since >= LOOK_EVERY) {
		since = 0.0;
		drag = drag_at(here);
		if (OS::get_singleton()->has_environment("PLANET_TIMING") && drag > 0.0) {
			UtilityFunctions::print(vformat("PLANET_TIMING undergrowth drag %.2f -> speed x%.2f", drag, 1.0 - MAX_SLOW * drag));
		}
	}
	double wanted = ((bool)player_object->call("is_on_floor") && !(bool)player_object->get("free_mode_enabled")) ? 1.0 - MAX_SLOW * drag : 1.0;
	// (it eases in and out: no jerk at the edge of a bush)
	double step = p_delta * 3.0;
	slow = std::abs(wanted - slow) <= step ? wanted : slow + (wanted > slow ? step : -step);
	Vector3 velocity = player_object->get("velocity");
	velocity.x *= slow;
	velocity.z *= slow;
	player_object->set("velocity", velocity);
}

// The undergrowth round `world_position`: 0 in the open .. 1 in a thicket (the worst of the tiles it is over).
double PlanetUndergrowth::drag_at(const Vector3 &p_world_position) const {
	Object *planet_object = get_planet();
	Object *noise = planet_object->get("noise");
	Object *scatter = noise->get("scatter_native");
	if (scatter == nullptr) {
		return 0.0;
	}
	Object *surface = planet_object->get("surface");
	Dictionary all = surface->get("tiles");
	Array values = all.values();
	double worst = 0.0;
	for (int i = 0; i < values.size(); i++) {
		Node3D *tile = Object::cast_to<Node3D>((Object *)values[i]);
		Node3D *holder = Object::cast_to<Node3D>((Object *)tile->get("plant_holder"));
		if (holder == nullptr || !holder->has_meta("stems")) {
			continue;
		}
		if (tile->get_global_position().distance_to(p_world_position) > (double)tile->get("size") * 0.75) {
			continue;
		}
		Vector3 local = tile->to_local(p_world_position);
		PackedFloat32Array stems = holder->get_meta("stems");
		worst = std::max(worst, (double)scatter->call("drag", stems, local.x, local.z));
	}
	return worst;
}

// ---- PlanetShells ----

void PlanetShells::_bind_methods() {
	NP_BIND_OBJECT(PlanetShells, planet)
	NP_BIND_OBJECT(PlanetShells, player)
}

void PlanetShells::_ready() {
	Ref<Shader> shader = ResourceLoader::get_singleton()->load("res://shaders/world/planet_shells.gdshader");
	for (int layer = 0; layer < LAYERS; layer++) {
		Ref<ShaderMaterial> material;
		material.instantiate();
		material->set_shader(shader);
		material->set_shader_parameter("level", (double)(layer + 1) / (double)LAYERS);
		material->set_shader_parameter("top", TOP);
		material->set_shader_parameter("reach", REACH);
		materials.append(material);
	}
}

void PlanetShells::_physics_process(double p_delta) {
	Node3D *player_node = Object::cast_to<Node3D>(get_player());
	Object *planet_object = get_planet();
	if (player_node == nullptr || planet_object == nullptr) {
		return;
	}
	since += p_delta;
	if (since < LOOK_EVERY) {
		return;
	}
	since = 0.0;
	Vector3 here = player_node->get_global_position();
	Array held = tiles.keys();
	for (int i = 0; i < held.size(); i++) {
		Object *tile_object = held[i];
		Node3D *tile = Object::cast_to<Node3D>(tile_object);
		if (tile == nullptr || !tile->is_inside_tree() || gap(tile, here) > REACH * 1.6) {
			drop(tile_object);
		}
	}
	Object *surface = planet_object->get("surface");
	Dictionary all = surface->get("tiles");
	Array values = all.values();
	for (int i = 0; i < values.size(); i++) {
		Node3D *tile = Object::cast_to<Node3D>((Object *)values[i]);
		if (tiles.has(tile) || !(bool)tile->get("has_collider") || (Object *)tile->get("ground_instance") == nullptr) {
			continue;
		}
		if (gap(tile, here) < REACH * 1.2) {
			raise(tile);
		}
	}
}

// How far `here` is from the tile's ground (0 over it).
double PlanetShells::gap(Node3D *p_tile, const Vector3 &p_here) const {
	Vector3 local = p_tile->to_local(p_here);
	double half = (double)p_tile->get("size") * 0.5;
	return Vector2(std::max(std::abs(local.x) - half, 0.0), std::max(std::abs(local.z) - half, 0.0)).length();
}

void PlanetShells::raise(Node3D *p_tile) {
	Array layers;
	MeshInstance3D *ground = Object::cast_to<MeshInstance3D>((Object *)p_tile->get("ground_instance"));
	for (int i = 0; i < materials.size(); i++) {
		MeshInstance3D *copy = memnew(MeshInstance3D);
		copy->set_mesh(ground->get_mesh());
		copy->set_material_override(materials[i]);
		copy->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		p_tile->add_child(copy);
		layers.append(copy);
	}
	tiles[p_tile] = layers;
}

void PlanetShells::drop(Object *p_tile) {
	if (p_tile != nullptr) {
		Array layers = tiles[p_tile];
		for (int i = 0; i < layers.size(); i++) {
			Object *copy = layers[i];
			if (copy != nullptr) {
				Object::cast_to<Node>(copy)->queue_free();
			}
		}
	}
	tiles.erase(p_tile);
}

// ---- PlanetDust ----

void PlanetDust::_bind_methods() {
	ClassDB::bind_method(D_METHOD("puff", "at", "up", "colour", "strength"), &PlanetDust::puff);
}

void PlanetDust::_ready() {
	Ref<GradientTexture2D> round_flake;
	round_flake.instantiate();
	round_flake->set_fill(GradientTexture2D::FILL_RADIAL);
	round_flake->set_fill_from(Vector2(0.5, 0.5));
	round_flake->set_fill_to(Vector2(0.5, 0.0));
	round_flake->set_width(64);
	round_flake->set_height(64);
	Ref<Gradient> edge;
	edge.instantiate();
	edge->set_color(0, Color(1, 1, 1, 1));
	edge->set_color(1, Color(1, 1, 1, 0));
	round_flake->set_gradient(edge);
	Ref<StandardMaterial3D> material;
	material.instantiate();
	material->set_shading_mode(BaseMaterial3D::SHADING_MODE_PER_VERTEX);
	material->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
	material->set_billboard_mode(BaseMaterial3D::BILLBOARD_PARTICLES);
	material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
	material->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, round_flake);
	material->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
	mesh.instantiate();
	mesh->set_size(Vector2(0.5, 0.5));
	mesh->set_material(material);
	Ref<Gradient> ramp;
	ramp.instantiate();
	ramp->set_color(0, Color(1, 1, 1, 0.0));
	ramp->add_point(0.12, Color(1, 1, 1, 0.7));
	ramp->set_color(ramp->get_point_count() - 1, Color(1, 1, 1, 0.0));
	fade.instantiate();
	fade->set_gradient(ramp);
	Ref<Curve> curve;
	curve.instantiate();
	curve->add_point(Vector2(0.0, 0.35));
	curve->add_point(Vector2(1.0, 1.0));
	growth.instantiate();
	growth->set_curve(curve);
}

// A puff at world position `at` (on the ground, `up` the way up), `colour` the ground's, `strength` 0.3 .. 1.5 (a step is 0.5, a hard landing 1.5).
void PlanetDust::puff(const Vector3 &p_at, const Vector3 &p_up, const Color &p_colour, double p_strength) {
	GPUParticles3D *flakes = memnew(GPUParticles3D);
	flakes->set_amount((int)(5.0 * p_strength) + 3);
	flakes->set_lifetime(LIFE);
	flakes->set_one_shot(true);
	flakes->set_explosiveness_ratio(0.9);
	flakes->set_visibility_aabb(AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6)));
	flakes->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	Ref<ParticleProcessMaterial> process;
	process.instantiate();
	process->set_direction(p_up);
	process->set_spread(55.0);
	process->set_param_min(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 0.25 * p_strength);
	process->set_param_max(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 0.7 * p_strength);
	process->set_gravity(Vector3());
	process->set_param_min(ParticleProcessMaterial::PARAM_DAMPING, 0.6);
	process->set_param_max(ParticleProcessMaterial::PARAM_DAMPING, 1.2);
	process->set_param_min(ParticleProcessMaterial::PARAM_SCALE, 0.5);
	process->set_param_max(ParticleProcessMaterial::PARAM_SCALE, 1.1);
	process->set_param_texture(ParticleProcessMaterial::PARAM_SCALE, growth);
	process->set_color(p_colour.lightened(0.4));
	process->set_color_ramp(fade);
	process->set_emission_shape(ParticleProcessMaterial::EMISSION_SHAPE_SPHERE);
	process->set_emission_sphere_radius(0.12);
	flakes->set_process_material(process);
	flakes->set_draw_pass_mesh(0, mesh);
	flakes->set_position(p_at + p_up * 0.04);
	add_child(flakes);
	flakes->set_emitting(true);
	get_tree()->create_timer(LIFE + 0.8)->connect("timeout", Callable(flakes, "queue_free"));
}

// ---- PlanetMotes ----

void PlanetMotes::_bind_methods() {
	NP_BIND_OBJECT(PlanetMotes, planet)
}

void PlanetMotes::_ready() {
	const Vector3 BOX(26.0, 9.0, 26.0); // m: half sizes of the air they live in
	material.instantiate();
	speck.instantiate();
	set_amount(700);
	set_lifetime(LIFE);
	set_pre_process_time(LIFE);
	set_use_local_coordinates(false);
	set_explosiveness_ratio(0.0);
	set_visibility_aabb(AABB(-BOX * 1.2, BOX * 2.4));
	material->set_emission_shape(ParticleProcessMaterial::EMISSION_SHAPE_BOX);
	material->set_emission_box_extents(BOX);
	material->set_gravity(Vector3(0.0, -0.01, 0.0));
	material->set_param_min(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 0.0);
	material->set_param_max(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 0.05);
	material->set_direction(Vector3(1.0, 0.2, 0.3));
	material->set_spread(180.0);
	material->set_turbulence_enabled(true);
	material->set_turbulence_noise_strength(0.35);
	material->set_turbulence_noise_scale(6.0);
	material->set_param_min(ParticleProcessMaterial::PARAM_TURB_VEL_INFLUENCE, 0.05);
	material->set_param_max(ParticleProcessMaterial::PARAM_TURB_VEL_INFLUENCE, 0.12);
	material->set_param_min(ParticleProcessMaterial::PARAM_SCALE, 0.5);
	material->set_param_max(ParticleProcessMaterial::PARAM_SCALE, 1.6);
	Ref<Gradient> fade_gradient; // appear and vanish softly
	fade_gradient.instantiate();
	fade_gradient->set_color(0, Color(1.0, 1.0, 1.0, 0.0));
	fade_gradient->set_color(1, Color(1.0, 1.0, 1.0, 0.0));
	fade_gradient->add_point(0.15, Color(1.0, 1.0, 1.0, 1.0));
	fade_gradient->add_point(0.85, Color(1.0, 1.0, 1.0, 1.0));
	Ref<GradientTexture1D> ramp;
	ramp.instantiate();
	ramp->set_gradient(fade_gradient);
	material->set_color_ramp(ramp);
	set_process_material(material);
	Ref<QuadMesh> quad;
	quad.instantiate();
	quad->set_size(Vector2(0.025, 0.025));
	speck->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
	speck->set_billboard_mode(BaseMaterial3D::BILLBOARD_ENABLED);
	speck->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
	speck->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
	speck->set_albedo(Color(1.0, 0.95, 0.8, 0.55));
	speck->set_distance_fade(BaseMaterial3D::DISTANCE_FADE_PIXEL_ALPHA);
	speck->set_distance_fade_min_distance(18.0);
	speck->set_distance_fade_max_distance(2.0);
	quad->set_material(speck);
	set_draw_pass_mesh(0, quad);
	set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	set_emitting(false);
}

void PlanetMotes::_process(double) {
	Object *planet_object = get_planet();
	if (planet_object == nullptr) {
		return;
	}
	Object *target_object = planet_object->call("target");
	if (target_object == nullptr) {
		return;
	}
	Camera3D *camera = get_viewport()->get_camera_3d();
	if (camera != nullptr) {
		set_global_position(camera->get_global_position());
	}
	Object *atmosphere = planet_object->get("atmosphere");
	Vector3 sun_direction = atmosphere->get("sun_direction");
	Vector3 centre = atmosphere->get("planet_centre");
	Vector3 atmosphere_position = Object::cast_to<Node3D>(atmosphere)->get_global_position();
	double sun_up = CLAMP(sun_direction.dot((atmosphere_position - centre).normalized()) * 6.0, 0.0, 1.0);
	double calm = 1.0 - std::max((double)atmosphere->get("overcast"), (double)atmosphere->get("fog_extra") * 60.0);
	Node *graphics = get_node_or_null("/root/GraphicsSettings");
	bool particles = graphics != nullptr && (bool)graphics->call("get_graphics_value", StringName("particles"));
	bool wanted = particles && sun_up > 0.05 && calm > 0.3 && !(bool)atmosphere->get("underwater") && (double)planet_object->call("altitude") < 2500.0;
	set_emitting(wanted);
	set_visible(wanted);
	Color colour = speck->get_albedo();
	colour.a = 0.55 * sun_up * calm;
	speck->set_albedo(colour);
}

// ---- PlanetSwayTree ----

PlanetSwayTree::PlanetSwayTree() {
	sway.instantiate();
}

void PlanetSwayTree::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "tree_mesh", "material", "tint"), &PlanetSwayTree::setup);
	ClassDB::bind_method(D_METHOD("is_at_rest"), &PlanetSwayTree::is_at_rest);
	ClassDB::bind_method(D_METHOD("step", "body_local", "delta"), &PlanetSwayTree::step);
	ClassDB::bind_method(D_METHOD("most_turned"), &PlanetSwayTree::most_turned);
	ClassDB::bind_method(D_METHOD("jitter"), &PlanetSwayTree::jitter);
	ClassDB::bind_method(D_METHOD("turn_sum"), &PlanetSwayTree::turn_sum);
}

// Take the branches of `tree_mesh` (its "branches" meta) and draw them with `material` (the plant material, copied) tinted by `tint`.
bool PlanetSwayTree::setup(const Ref<ArrayMesh> &p_tree_mesh, const Ref<ShaderMaterial> &p_material, const Color &p_tint) {
	table = p_tree_mesh->get_meta("branches", PackedFloat32Array());
	if (table.size() < 20) {
		return false;
	}
	set_mesh(p_tree_mesh);
	int count = (int)table.size() / 10;
	feet = sway->feet(table).to_byte_array();
	state = PackedFloat32Array();
	PackedByteArray data = feet;
	data.append_array(sway->turns(zeros(count)).to_byte_array());
	image = Image::create_from_data(count, 2, false, Image::FORMAT_RGBAF, data);
	texture = ImageTexture::create_from_image(image);
	Ref<ShaderMaterial> own = p_material->duplicate();
	own->set_shader_parameter("bendable", true);
	own->set_shader_parameter("bend_data", texture);
	own->set_shader_parameter("live_tint", p_tint);
	set_material_override(own);
	awake = false;
	return true;
}

// A step of `delta` seconds. `body_local`: the walker's capsule in this tree's own space (a, b, radius: 7 floats; empty: nobody near, the
// branches only settle).
void PlanetSwayTree::step(const PackedFloat32Array &p_body_local, double p_delta) {
	if (!awake && p_body_local.is_empty()) {
		return;
	}
	Dictionary made = sway->step(table, state, p_body_local, p_delta);
	PackedFloat32Array before = state;
	state = made["state"];
	jitter_ = 0.0;
	if (before.size() == state.size()) {
		for (int at = 0; at < state.size() / 6; at++) {
			for (int axis = 0; axis < 3; axis++) {
				double change = std::abs((double)state[at * 6 + axis] - (double)before[at * 6 + axis]);
				jitter_ = std::max(jitter_, change);
			}
		}
	}
	awake = made["awake"];
	PackedByteArray data = feet;
	data.append_array(sway->turns(state).to_byte_array());
	image->set_data((int)table.size() / 10, 2, false, Image::FORMAT_RGBAF, data);
	texture->update(image);
}

// The most any branch is turned now (radians): for the checks.
double PlanetSwayTree::most_turned() const {
	double worst = 0.0;
	for (int id = 0; id < state.size() / 6; id++) {
		worst = std::max(worst, (double)Vector3(state[id * 6], state[id * 6 + 1], state[id * 6 + 2]).length());
	}
	return worst;
}

// All the branches' turns added up (radians): for the checks.
double PlanetSwayTree::turn_sum() const {
	double total = 0.0;
	for (int id = 0; id < state.size() / 6; id++) {
		total += Vector3(state[id * 6], state[id * 6 + 1], state[id * 6 + 2]).length();
	}
	return total;
}

PackedFloat32Array PlanetSwayTree::zeros(int p_count) {
	PackedFloat32Array result;
	result.resize((int64_t)p_count * 6);
	result.fill(0.0f);
	return result;
}
