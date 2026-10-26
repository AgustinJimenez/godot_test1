#include "planet_ground_bake_native.h"

#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>

using namespace godot;

static int positive_mod_i(int p_x, int p_y) {
	int value = p_x % p_y;
	if (value < 0) {
		value += p_y;
	}
	return value;
}

static int floor_div_i(double p_x) {
	return (int)std::floor(p_x);
}

void PlanetGroundBake::_bind_methods() {
	BIND_CONSTANT(STEP);
	BIND_CONSTANT(RECTS);
	NP_BIND(PlanetGroundBake, Variant::INT, pixels)
	NP_BIND(PlanetGroundBake, Variant::BOOL, hdr)
	NP_BIND(PlanetGroundBake, Variant::FLOAT, metres)
	ClassDB::bind_method(D_METHOD("setup", "ground", "texels", "size_metres"), &PlanetGroundBake::setup, DEFVAL(2048), DEFVAL(12.0));
	ClassDB::bind_method(D_METHOD("set_parameter", "key", "value"), &PlanetGroundBake::set_parameter);
	ClassDB::bind_method(D_METHOD("pause"), &PlanetGroundBake::pause);
	ClassDB::bind_static_method("PlanetGroundBake", D_METHOD("flat_of", "frame", "at"), &PlanetGroundBake::flat_of);
	ClassDB::bind_method(D_METHOD("follow", "centre", "key"), &PlanetGroundBake::follow);
}

// Makes the picture and gives it to `ground` (the ground material).
void PlanetGroundBake::setup(const Ref<ShaderMaterial> &p_ground, int64_t p_texels, double p_size_metres) {
	ground = p_ground;
	pixels = p_texels;
	metres = p_size_metres;
	view = memnew(SubViewport);
	view->set_size(Vector2i((int)pixels, (int)pixels));
	view->set_use_hdr_2d(hdr);
	view->set_transparent_background(false);
	view->set_clear_mode(SubViewport::CLEAR_MODE_NEVER);
	view->set_update_mode(SubViewport::UPDATE_DISABLED);
	add_child(view);
	Ref<Shader> shader = ResourceLoader::get_singleton()->load("res://shaders/world/planet_mosaic_bake.gdshader");
	for (int index = 0; index < RECTS; index++) {
		Ref<ShaderMaterial> material;
		material.instantiate();
		material->set_shader(shader);
		material->set_shader_parameter("bake_texel", metres / (double)pixels);
		ColorRect *rect = memnew(ColorRect);
		rect->set_material(material);
		rect->set_visible(false);
		view->add_child(rect);
		rects.push_back(rect);
		materials.push_back(material);
	}
	ground->set_shader_parameter("mosaic_height_map", view->get_texture());
}

// Changes a number of the plates (a `mosaic_*` uniform) for the picture; it is drawn again.
void PlanetGroundBake::set_parameter(const StringName &p_key, const Variant &p_value) {
	for (const Ref<ShaderMaterial> &material : materials) {
		material->set_shader_parameter(p_key, p_value);
	}
	valid = false;
}

// Stops using the picture (the camera is high above the ground, where the parallax is off): the shader works the heights out again and nothing
// is drawn until `follow` is called.
void PlanetGroundBake::pause() {
	if (paused) {
		return;
	}
	paused = true;
	valid = false;
	for (ColorRect *rect : rects) {
		rect->set_visible(false);
	}
	ground->set_shader_parameter("mosaic_height_window", Vector4());
}

// The ground's own metres at the world position `at`, as the ground shader finds them: the position from the anchor plus the wrapped anchor,
// along the anchor's right and forward axes.
Vector2 PlanetGroundBake::flat_of(const Ref<PlanetFrame> &p_frame, const Vector3 &p_at) {
	Vector3 on_planet = p_frame->anchor_from_world().xform(p_at) + p_frame->anchor_wrap();
	Vector3 up = p_frame->anchor_up().normalized();
	Vector3 reference = std::abs(up.y) < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
	Vector3 right = reference.cross(up).normalized();
	Vector3 forward = up.cross(right);
	return Vector2(on_planet.dot(right), on_planet.dot(forward));
}

// Keeps the picture round `centre` (the camera in the march's coordinates). `key` names the frame those coordinates belong to: a new key draws
// everything again.
void PlanetGroundBake::follow(const Vector2 &p_centre, int64_t p_key) {
	paused = false;
	for (ColorRect *rect : rects) {
		rect->set_visible(false);
	}
	used = 0;
	double texel = metres / (double)pixels;
	Vector2i middle(floor_div_i(p_centre.x / texel), floor_div_i(p_centre.y / texel));
	Vector2i full((int)pixels, (int)pixels);
	if (!valid || p_key != key_) {
		key_ = p_key;
		valid = true;
		origin = corner_for(middle);
		draw(origin, full);
		publish();
		return;
	}
	Vector2i drift = middle - (origin + full / 2);
	if (std::abs(drift.x) < STEP * 3 / 2 && std::abs(drift.y) < STEP * 3 / 2) {
		return;
	}
	Vector2i want = corner_for(middle);
	if (want == origin) {
		return;
	}
	Vector2i delta = want - origin;
	if (std::abs(delta.x) >= pixels || std::abs(delta.y) >= pixels) {
		draw(want, full);
	} else {
		// the ground the window has just reached: a strip across the new window (the columns it gained) and a strip across the part the two
		// windows share (the rows it gained)
		Vector2i gained_x = gained(origin.x, want.x);
		draw(Vector2i(gained_x.x, want.y), Vector2i(gained_x.y, (int)pixels));
		int shared_from = std::max(origin.x, want.x);
		int shared_width = std::min(origin.x, want.x) + (int)pixels - shared_from;
		Vector2i gained_y = gained(origin.y, want.y);
		draw(Vector2i(shared_from, gained_y.x), Vector2i(shared_width, gained_y.y));
	}
	origin = want;
	publish();
}

// The window's corner (a multiple of STEP) that puts `middle` in the middle.
Vector2i PlanetGroundBake::corner_for(const Vector2i &p_middle) const {
	int half = (int)pixels / 2;
	return Vector2i(floor_div_i((double)(p_middle.x - half) / STEP) * STEP, floor_div_i((double)(p_middle.y - half) / STEP) * STEP);
}

// The texels a window gained along one axis when its corner moved from `old` to `now`: (the first one, how many).
Vector2i PlanetGroundBake::gained(int p_old, int p_now) const {
	if (p_now > p_old) {
		return Vector2i(p_old + (int)pixels, p_now - p_old);
	}
	return Vector2i(p_now, p_old - p_now);
}

// Draws the world texels from `corner`, `size` of them, into the picture; the picture wraps, so a rectangle that crosses its edge is drawn in pieces.
void PlanetGroundBake::draw(const Vector2i &p_corner, const Vector2i &p_size) {
	if (p_size.x <= 0 || p_size.y <= 0) {
		return;
	}
	for (const Vector2i &across : cut(p_corner.x, p_size.x)) {
		for (const Vector2i &down : cut(p_corner.y, p_size.y)) {
			place(Vector2i(across.x, down.x), Vector2i(across.y, down.y));
		}
	}
	view->set_update_mode(SubViewport::UPDATE_ONCE);
}

// Splits `length` texels from world texel `start` where the picture wraps: (start, length) pieces.
std::vector<Vector2i> PlanetGroundBake::cut(int p_start, int p_length) const {
	int first = std::min(p_length, (int)pixels - positive_mod_i(p_start, (int)pixels));
	if (first >= p_length) {
		return { Vector2i(p_start, p_length) };
	}
	return { Vector2i(p_start, first), Vector2i(p_start + first, p_length - first) };
}

void PlanetGroundBake::place(const Vector2i &p_world, const Vector2i &p_size) {
	ColorRect *rect = rects[used];
	rect->set_position(Vector2(positive_mod_i(p_world.x, (int)pixels), positive_mod_i(p_world.y, (int)pixels)));
	rect->set_size(Vector2(p_size));
	rect->set_visible(true);
	materials[used]->set_shader_parameter("bake_rect", Vector4(p_world.x, p_world.y, p_size.x, p_size.y));
	used += 1;
}

void PlanetGroundBake::publish() {
	double texel = metres / (double)pixels;
	ground->set_shader_parameter("mosaic_height_window", Vector4(origin.x * texel, origin.y * texel, metres, 1.0));
}
