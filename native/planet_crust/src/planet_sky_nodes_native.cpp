#include "planet_sky_nodes_native.h"

#include "planet_imprint_native.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/directional_light3d.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;

static Ref<Script> flora_script() {
	static Ref<Script> s;
	if (s.is_null()) {
		s = ResourceLoader::get_singleton()->load("res://systems/world_gen/flora_meshes.gd");
	}
	return s;
}

// ---- PlanetImpostors ----

void PlanetImpostors::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "registry"), &PlanetImpostors::start);
	ClassDB::bind_method(D_METHOD("frame_done"), &PlanetImpostors::frame_done);
	ClassDB::bind_method(D_METHOD("begin_next"), &PlanetImpostors::begin_next);
}

// Starts baking every tree of `registry`, one view a frame.
void PlanetImpostors::start(Object *p_registry) {
	OS *os = OS::get_singleton();
	if (DisplayServer::get_singleton()->get_name() == "headless" || os->get_environment("NO_IMPOSTORS") != "") {
		return;
	}
	registry_id = p_registry->get_instance_id();
	p_registry->set("impostors_expected", true);
	bool debug = os->get_environment("IMPOSTOR_DEBUG") != "";
	Array all = p_registry->get("species");
	if (debug) {
		UtilityFunctions::print("IMPOSTORS start ", all.size());
	}
	viewport = memnew(SubViewport);
	viewport->set_size(Vector2i(CELL, CELL));
	viewport->set_use_own_world_3d(true);
	viewport->set_transparent_background(true);
	viewport->set_msaa_3d(Viewport::MSAA_DISABLED);
	viewport->set_update_mode(SubViewport::UPDATE_DISABLED);
	viewport->set_positional_shadow_atlas_size(0);
	add_child(viewport);
	Ref<Environment> environment;
	environment.instantiate();
	environment->set_background(Environment::BG_COLOR);
	environment->set_bg_color(Color(0, 0, 0, 0));
	environment->set_ambient_source(Environment::AMBIENT_SOURCE_COLOR);
	environment->set_ambient_light_color(Color(0.62f, 0.66f, 0.72f));
	environment->set_tonemapper(Environment::TONE_MAPPER_LINEAR);
	camera = memnew(Camera3D);
	camera->set_projection(Camera3D::PROJECTION_ORTHOGONAL);
	camera->set_near(0.05);
	camera->set_far(400.0);
	camera->set_environment(environment);
	viewport->add_child(camera);
	DirectionalLight3D *sun = memnew(DirectionalLight3D);
	sun->set_param(Light3D::PARAM_ENERGY, 0.9);
	sun->set_shadow(false);
	viewport->add_child(sun);
	sun->set_rotation_degrees(Vector3(-50.0, 35.0, 0.0));
	holder = memnew(MeshInstance3D);
	holder->set_material_override(flora_script()->call("material"));
	viewport->add_child(holder);
	for (int i = 0; i < all.size(); i++) {
		Object *one = all[i];
		if (!(bool)one->call("is_tree")) {
			continue;
		}
		for (int variant = 0; variant < VARIANTS; variant++) {
			tasks.push_back({ (int)(int64_t)one->get("id"), variant });
		}
	}
	call_deferred("begin_next");
}

// Starts the next variant in the list, or ends (a variant with no mesh to speak of is skipped).
void PlanetImpostors::begin_next() {
	Object *reg = species();
	if (reg == nullptr) {
		return;
	}
	while (next_task < tasks.size()) {
		current = tasks[next_task++];
		Ref<ArrayMesh> mesh = reg->call("mesh", current.id, current.variant, (bool)flora_script()->get("detailed"), 1);
		AABB box = mesh->get_aabb();
		if (box.size.y <= 0.1) {
			continue;
		}
		double reach = std::max(std::abs((double)box.position.x), std::abs((double)box.get_end().x));
		reach = std::max(reach, std::max(std::abs((double)box.position.z), std::abs((double)box.get_end().z)));
		side = std::max((double)box.size.y, reach * 2.0) * 1.06;
		middle = box.position.y + box.size.y * 0.5;
		box_top = box.get_end().y;
		holder->set_mesh(mesh);
		camera->set_size(side);
		atlas = Image::create(CELL * (VIEWS + 1), CELL, false, Image::FORMAT_RGBA8); // (the last picture: from straight above)
		view = 0;
		aim(view);
		return;
	}
	if (OS::get_singleton()->get_environment("IMPOSTOR_DEBUG") != "") {
		UtilityFunctions::print("IMPOSTORS baked at ", (int64_t)Time::get_singleton()->get_ticks_msec(), " ms");
	}
}

// Points the camera for one view and asks for the picture a frame later.
void PlanetImpostors::aim(int p_view) {
	double angle = TAU_D * (double)p_view / (double)VIEWS;
	if (p_view == VIEWS) {
		camera->look_at_from_position(Vector3(0.0, box_top + 200.0, 0.0), Vector3(0.0, middle, 0.0), Vector3(0.0, 0.0, -1.0));
	} else {
		Vector3 eye = Vector3(std::cos(angle), 0.0, std::sin(angle)) * 200.0 + Vector3(0.0, middle, 0.0);
		camera->look_at_from_position(eye, Vector3(0.0, middle, 0.0));
	}
	viewport->set_update_mode(SubViewport::UPDATE_ONCE);
	RenderingServer::get_singleton()->connect("frame_post_draw", Callable(this, "frame_done"), CONNECT_ONE_SHOT);
}

void PlanetImpostors::frame_done() {
	Ref<Image> picture = viewport->get_texture()->get_image();
	picture->convert(Image::FORMAT_RGBA8);
	atlas->blit_rect(picture, Rect2i(0, 0, CELL, CELL), Vector2i(view * CELL, 0));
	view += 1;
	if (view <= VIEWS) {
		aim(view);
		return;
	}
	finish_bake();
	begin_next();
}

void PlanetImpostors::finish_bake() {
	Ref<PlanetImprintNative> maker;
	maker.instantiate();
	// (the see-through texels take the colour of the solid ones: no dark fringe when filtered)
	PackedByteArray bled = maker->call("bleed", atlas->get_data(), atlas->get_width(), atlas->get_height(), 3);
	atlas = Image::create_from_data(atlas->get_width(), atlas->get_height(), false, Image::FORMAT_RGBA8, bled);
	atlas->generate_mipmaps();
	Ref<QuadMesh> quad;
	quad.instantiate();
	quad->set_size(Vector2(side, side));
	quad->set_center_offset(Vector3(0.0, middle, 0.0));
	Ref<ShaderMaterial> material;
	material.instantiate();
	material->set_shader(ResourceLoader::get_singleton()->load("res://shaders/world/planet_impostor.gdshader"));
	material->set_shader_parameter("atlas", ImageTexture::create_from_image(atlas));
	material->set_shader_parameter("views", (double)VIEWS);
	material->set_shader_parameter("middle", middle);
	Dictionary baked;
	baked["mesh"] = quad;
	baked["material"] = material;
	species()->call("set_impostor", current.id, current.variant, baked);
	swap(current.id, current.variant);
	if (OS::get_singleton()->get_environment("IMPOSTOR_DEBUG") != "") {
		UtilityFunctions::print("IMPOSTOR baked ", current.id, " ", current.variant, " at ", (int64_t)Time::get_singleton()->get_ticks_msec());
	}
}

// Replaces the lighter meshes that tiles hung before this variant was baked with impostor quads.
void PlanetImpostors::swap(int p_id, int p_variant) {
	Dictionary baked = species()->call("impostor", p_id, p_variant);
	if (baked.is_empty()) {
		return;
	}
	Array waiting = species()->call("take_waiting", p_id, p_variant);
	for (int i = 0; i < waiting.size(); i++) {
		Dictionary entry = waiting[i];
		MultiMeshInstance3D *old = Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance((int64_t)entry["instance"]));
		if (old == nullptr || old->get_parent() == nullptr) {
			continue;
		}
		PackedFloat32Array buffer = entry["buffer"];
		Ref<MultiMesh> multi;
		multi.instantiate();
		multi->set_transform_format(MultiMesh::TRANSFORM_3D);
		multi->set_use_colors(true);
		multi->set_mesh(baked["mesh"]);
		multi->set_instance_count((int)(buffer.size() / 16));
		multi->set_buffer(buffer);
		MultiMeshInstance3D *quads = memnew(MultiMeshInstance3D);
		quads->set_multimesh(multi);
		quads->set_material_override(baked["material"]);
		quads->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		quads->set_visibility_range_begin(old->get_visibility_range_begin());
		quads->set_visibility_range_end(old->get_visibility_range_end());
		old->get_parent()->add_child(quads);
		old->queue_free();
	}
}

// ---- PlanetCloudShell ----

void PlanetCloudShell::_bind_methods() {
	NP_BIND_OBJECT(PlanetCloudShell, planet)
}

void PlanetCloudShell::_ready() {
	material.instantiate();
	material->set_shader(ResourceLoader::get_singleton()->load("res://shaders/world/planet_clouds.gdshader"));
	Ref<QuadMesh> screen; // the shader puts it over the whole screen
	screen.instantiate();
	screen->set_size(Vector2(2.0, 2.0));
	screen->set_flip_faces(true);
	set_mesh(screen);
	set_material_override(material);
	set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	set_extra_cull_margin(1.0e7);
	set_visible(false);
}

void PlanetCloudShell::_process(double p_delta) {
	Object *world = get_planet();
	if (world == nullptr) {
		return;
	}
	Object *the_target = world->call("target");
	if (the_target == nullptr) {
		return;
	}
	Object *atmosphere = world->get("atmosphere");
	double fade = 1.0 - (double)atmosphere->get("cloud_on"); // the sky has them from under the layer
	set_visible(fade > 0.0);
	if (is_visible()) {
		atmosphere->call("set_cloud_parameters", material);
		material->set_shader_parameter("fade", fade);
	}
	refresh_the_cover(p_delta);
}

// The picture of the cloud cover: made again every few seconds on a background thread, for the shell and for the volumetric clouds of the sky.
void PlanetCloudShell::refresh_the_cover(double p_delta) {
	Object *world = get_planet();
	wait -= p_delta;
	if (chart.is_valid()) {
		if (chart->finished()) {
			Ref<ImageTexture> picture = chart->texture();
			material->set_shader_parameter("cover_map", picture);
			Object *atmosphere = world->get("atmosphere");
			Ref<ShaderMaterial> sky = atmosphere->get("sky_material");
			sky->set_shader_parameter("cover_map", picture);
			RenderingServer::get_singleton()->global_shader_parameter_set("cloud_cover_map", picture); // (the ground's shadow)
			chart.unref();
		}
	} else {
		Ref<PlanetClock> clock = world->get("clock");
		if (wait <= 0.0 && std::abs(clock->get_time() - drawn_time) > 1.0e-3) {
			wait = is_visible() ? REFRESH : REFRESH * 2.0;
			chart.instantiate();
			chart->set_layer(PlanetChart::CLOUD_MASK);
			chart->set_size(Vector2i(256, 128));
			chart->set_clock(clock->copy());
			drawn_time = clock->get_time();
			Ref<PlanetNoise> noise = world->get("noise");
			chart->start(noise);
		}
	}
}

void PlanetCloudShell::_exit_tree() {
	if (chart.is_valid()) {
		chart->stop();
	}
}
