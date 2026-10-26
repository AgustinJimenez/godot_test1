#include "planet_prints_native.h"

#include "planet_imprint_native.h"
#include "planet_nodes_native.h"
#include "planet_noise_native.h"
#include "planet_tile_native.h"

#include <godot_cpp/classes/directional_light3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/classes/world3d.hpp>

#include <algorithm>
#include <cmath>
#include <map>

using namespace godot;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

static double positive_mod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

// ---- PlanetDents ----

static std::map<int, PackedByteArray> &soles() {
	static std::map<int, PackedByteArray> *map = new std::map<int, PackedByteArray>();
	return *map;
}

void PlanetDents::_bind_methods() {
	BIND_CONSTANT(SHOWN);
	BIND_CONSTANT(KEPT);
	BIND_CONSTANT(TILE);
	BIND_CONSTANT(COLUMNS);
	NP_BIND(PlanetDents, Variant::FLOAT, life)
	NP_BIND(PlanetDents, Variant::FLOAT, clock)
	ClassDB::bind_static_method("PlanetDents", D_METHOD("create", "material"), &PlanetDents::create);
	ClassDB::bind_method(D_METHOD("add", "at", "forward", "up", "side", "age", "profile"), &PlanetDents::add, DEFVAL(0.0), DEFVAL(PackedByteArray()));
	ClassDB::bind_method(D_METHOD("clear"), &PlanetDents::clear);
	ClassDB::bind_method(D_METHOD("update", "delta", "near"), &PlanetDents::update);
	ClassDB::bind_static_method("PlanetDents", D_METHOD("sole_profile", "side"), &PlanetDents::sole_profile);
}

Ref<PlanetDents> PlanetDents::create(const Ref<ShaderMaterial> &p_material) {
	Ref<PlanetDents> made;
	made.instantiate();
	made->material = p_material;
	made->image = Image::create(SHOWN, 3, false, Image::FORMAT_RGBAF);
	made->texture = ImageTexture::create_from_image(made->image);
	made->atlas = Image::create(TILE * COLUMNS, TILE * (SHOWN / COLUMNS), false, Image::FORMAT_R8);
	made->atlas_texture = ImageTexture::create_from_image(made->atlas);
	p_material->set_shader_parameter("dent_stamps", made->texture);
	p_material->set_shader_parameter("dent_atlas", made->atlas_texture);
	p_material->set_shader_parameter("dent_life", made->life);
	p_material->set_shader_parameter("dent_count", 0);
	return made;
}

// One print at the planet position `at`, its toe along `forward`, the ground's up `up` (both in planet axes); `profile` is what touched the sand
// (TILE x TILE bytes, 255 the deepest), or empty for a bare foot (`side` +1 right, -1 left). `age` makes it older (the lab).
void PlanetDents::add(const PackedFloat64Array &p_at, const Vector3 &p_forward, const Vector3 &p_up, double p_side, double p_age, const PackedByteArray &p_profile) {
	if ((int)stamps.size() >= KEPT) {
		stamps.erase(stamps.begin());
	}
	Stamp stamp;
	stamp.at = p_at;
	stamp.forward = p_forward.normalized();
	stamp.up = p_up.normalized();
	stamp.born = clock - p_age;
	stamp.profile = p_profile.is_empty() ? sole_profile(p_side) : p_profile;
	stamp.id = next_id;
	stamps.push_back(stamp);
	next_id += 1;
	since = REFRESH; // (choose again at once)
}

void PlanetDents::clear() {
	stamps.clear();
	shown.clear();
	material->set_shader_parameter("dent_count", 0);
}

// Every frame: the clock, the old ones dropped, and now and then the nearest stamps to `near` (a planet position) written to the texture.
void PlanetDents::update(double p_delta, const Vector3 &p_near) {
	clock += p_delta;
	material->set_shader_parameter("dent_now", clock);
	since += p_delta;
	if (since < REFRESH) {
		return;
	}
	since = 0.0;
	for (int index = (int)stamps.size() - 1; index >= 0; index--) {
		if (clock - stamps[index].born > life * 1.4) {
			stamps.erase(stamps.begin() + index);
		}
	}
	std::vector<Stamp> ranked = stamps;
	auto distance = [&](const Stamp &s) {
		double dx = s.at[0] - p_near.x;
		double dy = s.at[1] - p_near.y;
		double dz = s.at[2] - p_near.z;
		return dx * dx + dy * dy + dz * dz;
	};
	std::sort(ranked.begin(), ranked.end(), [&](const Stamp &a, const Stamp &b) { return distance(a) < distance(b); });
	int count = std::min((int)ranked.size(), (int)SHOWN);
	std::vector<int> ids;
	for (int index = 0; index < count; index++) {
		const Stamp &stamp = ranked[index];
		ids.push_back(stamp.id);
		image->set_pixel(index, 0, Color(positive_mod_d(stamp.at[0], 1024.0), positive_mod_d(stamp.at[1], 1024.0), positive_mod_d(stamp.at[2], 1024.0), stamp.born));
		image->set_pixel(index, 1, Color(stamp.forward.x, stamp.forward.y, stamp.forward.z, 0.0));
		image->set_pixel(index, 2, Color(stamp.up.x, stamp.up.y, stamp.up.z, 0.0));
	}
	texture->update(image);
	if (ids != shown) { // (the pictures are copied only when the nearest set changed)
		shown = ids;
		for (int index = 0; index < count; index++) {
			Ref<Image> tile = Image::create_from_data(TILE, TILE, false, Image::FORMAT_R8, ranked[index].profile);
			atlas->blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i((index % COLUMNS) * TILE, (index / COLUMNS) * TILE));
		}
		Ref<Image> mapped = atlas->duplicate();
		mapped->generate_mipmaps(); // (an old print is a blurred one: the shader picks the level)
		atlas_texture = ImageTexture::create_from_image(mapped);
		material->set_shader_parameter("dent_atlas", atlas_texture);
	}
	material->set_shader_parameter("dent_count", count);
}

// A bare foot as a profile (a heel, a narrow arch, the ball and five toes; PlanetImprintNative draws it). `side` +1 right, -1 left.
PackedByteArray PlanetDents::sole_profile(double p_side) {
	int key = p_side > 0.0 ? 1 : (p_side < 0.0 ? -1 : 0);
	auto &cache = soles();
	if (cache.find(key) == cache.end()) {
		Ref<PlanetImprintNative> maker;
		maker.instantiate();
		cache[key] = maker->call("sole_profile", (double)key, TILE, SPAN);
	}
	return cache[key];
}

// ---- PlanetImprinter ----

void PlanetImprinter::_bind_methods() {
	BIND_CONSTANT(LAYER);
	ClassDB::bind_method(D_METHOD("take", "at", "forward", "up", "done"), &PlanetImprinter::take);
	ClassDB::bind_method(D_METHOD("taken"), &PlanetImprinter::taken);
	ClassDB::bind_static_method("PlanetImprinter", D_METHOD("profile_of", "levels"), &PlanetImprinter::profile_of);
}

void PlanetImprinter::_ready() {
	viewport = memnew(SubViewport);
	viewport->set_size(Vector2i(PlanetDents::TILE, PlanetDents::TILE));
	viewport->set_update_mode(SubViewport::UPDATE_DISABLED);
	viewport->set_msaa_3d(Viewport::MSAA_DISABLED);
	viewport->set_positional_shadow_atlas_size(0);
	add_child(viewport);
	Ref<Environment> environment;
	environment.instantiate();
	environment->set_background(Environment::BG_COLOR);
	environment->set_bg_color(Color(1, 1, 1, 1));
	environment->set_ambient_source(Environment::AMBIENT_SOURCE_DISABLED);
	environment->set_tonemapper(Environment::TONE_MAPPER_LINEAR);
	camera = memnew(Camera3D);
	camera->set_projection(Camera3D::PROJECTION_ORTHOGONAL);
	camera->set_size(PlanetDents::SPAN);
	camera->set_near(0.001);
	camera->set_far(SLAB);
	camera->set_environment(environment);
	viewport->add_child(camera);
	MeshInstance3D *quad = memnew(MeshInstance3D);
	Ref<QuadMesh> mesh;
	mesh.instantiate();
	quad->set_mesh(mesh);
	quad->set_layer_mask(1 << (LAYER - 1));
	quad->set_extra_cull_margin(16384.0);
	quad->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	Ref<ShaderMaterial> material;
	material.instantiate();
	material->set_shader(ResourceLoader::get_singleton()->load("res://shaders/world/planet_imprint_depth.gdshader"));
	material->set_shader_parameter("slab", SLAB);
	quad->set_material_override(material);
	quad->set_position(Vector3(0.0, 0.0, -SLAB * 0.5));
	camera->add_child(quad);
}

void PlanetImprinter::take(const Vector3 &p_at, const Vector3 &p_forward, const Vector3 &p_up, const Callable &p_done) {
	if (busy) {
		p_done.call(PackedByteArray());
		return;
	}
	busy = true;
	pending = p_done;
	Camera3D *main_camera = get_viewport()->get_camera_3d();
	if (main_camera != nullptr) {
		main_camera->set_cull_mask_value(LAYER, false); // (the depth quad is for the small camera only)
	}
	camera->set_global_transform(Transform3D(Basis::looking_at(p_up, p_forward), p_at - p_up * 0.004));
	viewport->set_update_mode(SubViewport::UPDATE_ONCE);
	RenderingServer::get_singleton()->connect("frame_post_draw", Callable(this, "taken"), CONNECT_ONE_SHOT);
}

void PlanetImprinter::taken() {
	Ref<Image> picture = viewport->get_texture()->get_image();
	busy = false;
	Callable done = pending;
	pending = Callable();
	if (picture.is_null() || picture->is_empty()) {
		done.call(PackedByteArray());
		return;
	}
	picture->convert(Image::FORMAT_RGBA8);
	done.call(profile_of(picture->get_data()));
}

// natively (PlanetImprintNative): the lowest point is the level the lowest few percent of pixels reach (a speck of a stray pixel does not count),
// and anything lower than that is left out.
PackedByteArray PlanetImprinter::profile_of(const PackedByteArray &p_levels) {
	Ref<PlanetImprintNative> maker;
	maker.instantiate();
	return maker->call("profile_of", p_levels, PlanetDents::TILE, NOTHING, REACH, SINK / SLAB * 255.0);
}

// ---- PlanetFootprints ----

void PlanetFootprints::_bind_methods() {
	NP_BIND_OBJECT(PlanetFootprints, planet)
	NP_BIND_OBJECT(PlanetFootprints, target)
	ClassDB::bind_method(D_METHOD("sand_taken", "profile", "where", "forward", "up", "rebased", "at", "up_world"), &PlanetFootprints::sand_taken);
}

void PlanetFootprints::_physics_process(double p_delta) {
	Object *planet_object = get_planet();
	follow(p_delta);
	if (dents.is_null() && planet_object != nullptr) {
		dents = PlanetDents::create(PlanetTile::ground_material());
	}
	if (dents.is_valid()) {
		dents->update(p_delta, planet_object->call("planet_position"));
	}
	Object *player = get_target();
	if (player == nullptr) {
		clear_prints();
		return;
	}
	SceneTree *tree = get_tree();
	Node *graphics = tree->get_root()->get_node_or_null("GraphicsSettings");
	decals_on = graphics != nullptr && (bool)graphics->call("get_graphics_value", StringName("decals"));
	if (!decals_on && !prints.empty()) {
		clear_prints(false); // (the dents in sand are not decals: they stay on)
	}
	Vector3 here = Object::cast_to<Node3D>(player)->get_global_position();
	if (!(bool)player->call("is_on_floor")) {
		have_last = false;
		Vector3 velocity = player->get("velocity");
		fall = std::min(fall, (double)velocity.y);
		return;
	}
	if (fall < -3.5) { // (a landing: a puff of dust on sand, the harder the more)
		land(here, -fall);
	}
	fall = 0.0;
	if (!have_last) {
		last = here;
		have_last = true;
	}
	double moved = Vector2(here.x - last.x, here.z - last.z).length();
	if (moved >= STEP) {
		last = here;
		retry = RETRIES;
	} else if (retry > 0) {
		retry -= 1; // (the foot was in the air: look again next frame)
	} else {
		return;
	}
	press(here);
}

// One footprint under the player's foot (not in the sea or on hard ground).
void PlanetFootprints::press(const Vector3 &p_feet) {
	Object *planet_object = get_planet();
	Dictionary ground = planet_object->call("ground_at", p_feet.x, p_feet.z, p_feet.y);
	if ((bool)ground["wet"]) {
		return;
	}
	// the ground the player really stands on (the tile's collider), not the analytic height
	Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(p_feet + Vector3(0, 1, 0) * 1.2, p_feet - Vector3(0, 1, 0) * 3.0, 1);
	Dictionary hit = get_world_3d()->get_direct_space_state()->intersect_ray(query);
	if (hit.is_empty()) {
		return;
	}
	Vector3 up_world = hit["normal"];
	Node3D *player = Object::cast_to<Node3D>(get_target());
	Vector3 forward = -player->get_global_transform().basis.get_column(2);
	forward = (forward - up_world * forward.dot(up_world)).normalized();
	left = !left;
	Vector3 side = up_world.cross(forward) * (left ? 0.11 : -0.11);
	Vector3 spot = (Vector3)hit["position"] + side;
	spot -= up_world * up_world.dot(side); // (on the slope, not above or below it)
	Ref<PlanetFrame> frame = planet_object->get("frame");
	Basis back = frame->get_rot().inverse();
	if (is_sand((int)ground["biome"])) {
		dent_sand(hit["position"], forward, up_world);
		return;
	}
	if (!decals_on) {
		return;
	}
	Color paint_here = paint(p_feet);
	Color tint = tint_of((int)ground["biome"], paint_here);
	if (tint.a <= 0.0f) {
		return;
	}
	Decal *decal = next_decal();
	decal->set_modulate(tint);
	Print print;
	print.decal = decal->get_instance_id();
	print.at = frame->to_planet(spot);
	print.up = back.xform(up_world);
	print.forward = back.xform(forward);
	print.age = 0.0;
	print.tint = tint;
	prints.push_back(print);
}

// What touches the sand at `at` leaves its own shape: the real mesh is looked at from under the ground (PlanetImprinter), and the print keeps that.
// A foot in the air leaves nothing and the next frames try again.
void PlanetFootprints::dent_sand(const Vector3 &p_at, const Vector3 &p_forward, const Vector3 &p_up_world) {
	if (imprinter == nullptr) {
		imprinter = memnew(PlanetImprinter);
		add_child(imprinter);
	}
	Object *planet_object = get_planet();
	int64_t rebased = planet_object->get("rebases");
	Ref<PlanetFrame> frame = planet_object->get("frame");
	Basis back = frame->get_rot().inverse();
	PackedFloat64Array where = frame->to_planet(p_at);
	Callable done = Callable(this, "sand_taken").bind(where, back.xform(p_forward), back.xform(p_up_world), rebased, p_at, p_up_world);
	// (`sand_taken` takes the profile first: the bound values follow it)
	imprinter->take(p_at, p_forward, p_up_world, done);
}

void PlanetFootprints::sand_taken(const PackedByteArray &p_profile, const PackedFloat64Array &p_where, const Vector3 &p_forward, const Vector3 &p_up, int64_t p_rebased,
		const Vector3 &p_at, const Vector3 &p_up_world) {
	Object *planet_object = get_planet();
	if (p_profile.is_empty() || planet_object == nullptr || (int64_t)planet_object->get("rebases") != p_rebased || dents.is_null()) {
		return;
	}
	retry = 0;
	dents->add(p_where, p_forward, p_up, 1.0, 0.0, p_profile);
	Vector3 velocity = get_target()->get("velocity");
	dust_node()->call("puff", p_at, p_up_world, paint(p_at), 0.5 + 0.1 * velocity.length());
}

Node3D *PlanetFootprints::dust_node() {
	if (dust == nullptr) {
		dust = memnew(PlanetDust);
		add_child(dust);
	}
	return dust;
}

// A landing at `feet` from a fall of `speed` m/s: dust on sand and dry ground.
void PlanetFootprints::land(const Vector3 &p_feet, double p_speed) {
	Dictionary ground = get_planet()->call("ground_at", p_feet.x, p_feet.z, p_feet.y);
	if ((bool)ground["wet"] || !is_sand((int)ground["biome"])) {
		return;
	}
	dust_node()->call("puff", p_feet, Vector3(0, 1, 0), paint(p_feet), CLAMP(p_speed * 0.15, 0.6, 1.5));
}

// The colour of the ground under a world position (what the ground shader starts from).
Color PlanetFootprints::paint(const Vector3 &p_world_position) const {
	Object *planet_object = get_planet();
	Ref<PlanetFrame> frame = planet_object->get("frame");
	Ref<PlanetNoise> noise = planet_object->get("noise");
	PackedFloat64Array at = frame->to_planet(p_world_position);
	Vector3 dir = Vector3(at[0], at[1], at[2]).normalized();
	PackedVector3Array dirs;
	dirs.append(dir);
	PackedFloat32Array heights;
	heights.append(noise->height(dir.x, dir.y, dir.z));
	PackedFloat32Array steeps;
	steeps.append(0.1f);
	return noise->colours_of(dirs, heights, steeps)[0];
}

// Sand and desert take a real dent; the rest a flat decal. (the Biome enum of terrain_noise.gd: BEACH 0, SNOW 4, MARSH 5, DESERT 6)
bool PlanetFootprints::is_sand(int p_biome) {
	return p_biome == 6 || p_biome == 0;
}

// The colour and strength of a footprint on this biome and ground colour (alpha 0: none).
Color PlanetFootprints::tint_of(int p_biome, const Color &p_paint) {
	if (std::min(p_paint.r, std::min(p_paint.g, p_paint.b)) > 0.68f) { // snow and ice are white
		return Color(0.45f, 0.55f, 0.7f, 0.85f);
	}
	switch (p_biome) {
		case 4: // SNOW
			return Color(0.45f, 0.55f, 0.7f, 0.85f);
		case 6: // DESERT
		case 0: // BEACH
			return Color(0.45f, 0.36f, 0.25f, 0.7f);
		case 5: // MARSH
			return Color(0.14f, 0.1f, 0.06f, 0.8f);
	}
	return Color(0.0f, 0.0f, 0.0f, 0.0f);
}

Decal *PlanetFootprints::next_decal() {
	if ((int)prints.size() >= MAX) {
		Decal *oldest = Object::cast_to<Decal>(ObjectDB::get_instance(prints.front().decal));
		prints.erase(prints.begin());
		if (oldest != nullptr) {
			return oldest;
		}
	}
	Decal *decal = memnew(Decal);
	decal->set_size(Vector3(0.26, 2.0, 0.44)); // m: foot width, depth of the box that projects, foot length
	decal->set_texture(Decal::TEXTURE_ALBEDO, footprint_texture());
	decal->set_upper_fade(0.3);
	decal->set_lower_fade(0.3);
	decal->set_enable_distance_fade(true);
	decal->set_distance_fade_begin(25.0);
	decal->set_distance_fade_length(12.0);
	add_child(decal);
	return decal;
}

// Puts every decal where its planet-space spot is now and fades it with its age.
void PlanetFootprints::follow(double p_delta) {
	Object *planet_object = get_planet();
	if (planet_object == nullptr) {
		return;
	}
	Ref<PlanetFrame> frame = planet_object->get("frame");
	if (frame.is_null()) {
		return;
	}
	PackedFloat64Array anchor = frame->get_anchor();
	for (int index = (int)prints.size() - 1; index >= 0; index--) {
		Print &print = prints[index];
		print.age += p_delta;
		Decal *decal = Object::cast_to<Decal>(ObjectDB::get_instance(print.decal));
		if (print.age >= LIFE) {
			if (decal != nullptr) {
				decal->queue_free();
			}
			prints.erase(prints.begin() + index);
			continue;
		}
		if (decal == nullptr) {
			continue;
		}
		Vector3 offset(print.at[0] - anchor[0], print.at[1] - anchor[1], print.at[2] - anchor[2]);
		Vector3 up = frame->get_rot().xform(print.up).normalized();
		Vector3 forward = frame->get_rot().xform(print.forward).normalized();
		Vector3 right = forward.cross(up).normalized();
		Vector3 world_at = frame->get_rot().xform(offset) + frame->get_origin_w() + up * 0.02;
		decal->set_global_transform(Transform3D(Basis(right, up, -forward), world_at));
		decal->set_modulate(Color(print.tint.r, print.tint.g, print.tint.b, print.tint.a * (1.0 - smooth_step(LIFE * 0.6, LIFE, print.age))));
	}
}

void PlanetFootprints::clear_prints(bool p_with_dents) {
	if (dents.is_valid() && p_with_dents) {
		dents->clear();
	}
	for (const Print &print : prints) {
		Decal *decal = Object::cast_to<Decal>(ObjectDB::get_instance(print.decal));
		if (decal != nullptr) {
			decal->queue_free();
		}
	}
	prints.clear();
	have_last = false;
}

// A sole and a heel, soft at the edges: white on clear, the decal's colour tints it.
Ref<ImageTexture> PlanetFootprints::footprint_texture() {
	static Ref<ImageTexture> texture;
	if (texture.is_valid()) {
		return texture;
	}
	const int size = 64;
	Ref<Image> image = Image::create(size, size, false, Image::FORMAT_RGBA8);
	for (int y = 0; y < size; y++) {
		for (int x = 0; x < size; x++) {
			double u = ((double)x + 0.5) / (double)size * 2.0 - 1.0; // across the foot
			double v = ((double)y + 0.5) / (double)size * 2.0 - 1.0; // toe at -1, heel at +1
			double sole = blob(u, v + 0.28, 0.62, 0.62);
			double heel = blob(u, v - 0.62, 0.42, 0.28);
			double toes = blob(u, v + 0.88, 0.45, 0.14);
			double alpha = CLAMP(std::max(std::max(sole, heel), toes), 0.0, 1.0);
			image->set_pixel(x, y, Color(1.0f, 1.0f, 1.0f, (float)alpha));
		}
	}
	texture = ImageTexture::create_from_image(image);
	return texture;
}

// 1 in the middle of an ellipse of half-sizes (a, b) and 0 outside, with a soft edge.
double PlanetFootprints::blob(double p_u, double p_v, double p_a, double p_b) {
	double d = std::sqrt((p_u / p_a) * (p_u / p_a) + (p_v / p_b) * (p_v / p_b));
	return 1.0 - smooth_step(0.7, 1.0, d);
}
