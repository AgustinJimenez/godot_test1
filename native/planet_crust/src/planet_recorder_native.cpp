#include "planet_recorder_native.h"

#include "planet_clock_native.h"
#include "planet_frame_native.h"
#include "planet_settings_native.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/input_event_key.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const char *RECORD_PATH = "user://planet_live.jsonl";
static const char *MARKS_DIR = "user://planet_marks"; // a copy of the file for every F9 (the live file is overwritten by the next run)

static double snapped(double p_value, double p_step) {
	return std::floor(p_value / p_step + 0.5) * p_step;
}

void PlanetRecorderLogger::_log_error(const String &p_function, const String &p_file, int32_t p_line, const String &p_code, const String &p_rationale,
		bool, int32_t p_error_type, const TypedArray<Ref<ScriptBacktrace>> &) {
	PlanetRecorder *target = Object::cast_to<PlanetRecorder>(ObjectDB::get_instance(recorder));
	if (target == nullptr) {
		return;
	}
	String kind = p_error_type == Logger::ERROR_TYPE_WARNING ? "warning" : "error";
	target->note_message(kind, vformat("%s (%s:%d %s) %s", p_rationale != "" ? p_rationale : p_code, p_file.get_file(), p_line, p_function, p_code));
}

void PlanetRecorder::_bind_methods() {
	NP_BIND_OBJECT(PlanetRecorder, planet)
	ClassDB::bind_method(D_METHOD("note_message", "kind", "text"), &PlanetRecorder::note_message);
	ClassDB::bind_method(D_METHOD("add_deferred", "entry"), &PlanetRecorder::add_deferred);
}

void PlanetRecorder::_ready() {
	set_process_mode(Node::PROCESS_MODE_ALWAYS);
	logger.instantiate();
	logger->recorder = get_instance_id();
	OS::get_singleton()->add_logger(logger);
}

void PlanetRecorder::_exit_tree() {
	OS::get_singleton()->remove_logger(logger);
	write();
}

void PlanetRecorder::_unhandled_key_input(const Ref<InputEvent> &p_event) {
	Ref<InputEventKey> key = p_event;
	if (key.is_valid() && key->is_pressed() && !key->is_echo() && key->get_keycode() == KEY_F9) {
		marks += 1;
		Dictionary entry;
		entry["kind"] = "mark";
		entry["mark"] = marks;
		add(entry);
		write();
		keep_a_copy();
	}
}

// The world this file is about, the first line: without it a position means nothing (the seed and the size make the planet).
String PlanetRecorder::world_line() const {
	Object *world = get_planet();
	if (world == nullptr) {
		return "";
	}
	Ref<PlanetSettings> settings = world->get("settings");
	if (settings.is_null()) {
		return "";
	}
	Object *the_target = world->call("target");
	Vector3 here = the_target != nullptr ? (Vector3)world->call("planet_position") : Vector3();
	Vector3 unit = here.normalized();
	Dictionary line;
	line["kind"] = "world";
	line["seed"] = settings->get_world_seed();
	line["radius"] = settings->get_radius();
	line["drainage_cells"] = settings->get_drainage_cells();
	line["plants"] = settings->get_plants_on();
	Array direction;
	direction.append(snapped(unit.x, 0.0000001));
	direction.append(snapped(unit.y, 0.0000001));
	direction.append(snapped(unit.z, 0.0000001));
	line["direction"] = direction;
	line["scene"] = get_tree()->get_current_scene()->get_scene_file_path();
	return JSON::stringify(line);
}

// F9: the file as it is now, kept under its own name (`planet_marks/mark_<when>.jsonl`), the oldest of 20 dropped.
void PlanetRecorder::keep_a_copy() {
	if (in_a_lab()) {
		return;
	}
	DirAccess::make_dir_recursive_absolute(MARKS_DIR);
	String stamp = Time::get_singleton()->get_datetime_string_from_system().replace(":", "-");
	String path = vformat("%s/mark_%s_%d.jsonl", MARKS_DIR, stamp, marks);
	DirAccess::copy_absolute(RECORD_PATH, path);
	PackedStringArray listed = DirAccess::get_files_at(MARKS_DIR);
	listed.sort();
	for (int index = 0; index < std::max((int)listed.size() - MAX_MARKS, 0); index++) {
		DirAccess::remove_absolute(vformat("%s/%s", MARKS_DIR, listed[index]));
	}
}

// The lab and the checks (tests/...) run the same planet: they must not overwrite the file of a real session.
bool PlanetRecorder::in_a_lab() const {
	Node *scene = get_tree()->get_current_scene();
	return scene != nullptr && scene->get_scene_file_path().begins_with("res://tests/");
}

void PlanetRecorder::_process(double p_delta) {
	since_sample += p_delta;
	since_write += p_delta;
	if (since_sample >= INTERVAL) {
		since_sample = 0.0;
		add(sample());
	}
	if (since_write >= WRITE_EVERY) {
		since_write = 0.0;
		write();
	}
}

Dictionary PlanetRecorder::sample() {
	Dictionary result;
	result["kind"] = "sample";
	result["fps"] = Engine::get_singleton()->get_frames_per_second();
	result["frame"] = (int64_t)Engine::get_singleton()->get_process_frames();
	Object *world = get_planet();
	Object *target = world != nullptr ? (Object *)world->call("target") : nullptr;
	if (target == nullptr) {
		return result;
	}
	Vector3 here = world->call("planet_position");
	Ref<PlanetSettings> settings = world->get("settings");
	Ref<PlanetClock> clock = world->get("clock");
	Object *surface = world->get("surface");
	result["altitude"] = snapped(here.length() - settings->get_radius(), 0.1);
	Array position;
	position.append(snapped(here.x, 0.1));
	position.append(snapped(here.y, 0.1));
	position.append(snapped(here.z, 0.1));
	result["position"] = position;
	result["local_hour"] = snapped(clock->local_hour(here.normalized()), 0.01);
	Dictionary tiles = surface->get("tiles");
	result["tiles"] = tiles.size();
	result["weather"] = world->get("weather_text");
	Object *atmosphere = world->get("atmosphere");
	result["fog_extra"] = snapped((double)atmosphere->get("fog_extra"), 0.0001);
	result["cloud_on"] = snapped((double)atmosphere->get("cloud_on"), 0.01);
	result["overcast"] = snapped((double)atmosphere->get("overcast"), 0.01);
	result["underwater"] = atmosphere->get("underwater");
	Object *environment = atmosphere->get("environment");
	Dictionary fog;
	fog["on"] = environment->get("fog_enabled");
	fog["mode"] = environment->get("fog_mode");
	fog["density"] = snapped((double)environment->get("fog_density"), 0.00001);
	fog["begin"] = environment->get("fog_depth_begin");
	fog["end"] = environment->get("fog_depth_end");
	fog["curve"] = environment->get("fog_depth_curve");
	fog["sky"] = environment->get("fog_sky_affect");
	fog["height"] = environment->get("fog_height_density");
	result["fog"] = fog;
	if (target->has_method("set_free_mode")) { // the player
		Vector3 velocity = target->get("velocity");
		result["speed"] = snapped(velocity.length(), 0.1);
		result["free_mode"] = target->get("free_mode_enabled");
		result["on_floor"] = target->call("is_on_floor");
	}
	return result;
}

// Adds a line (stamped with the time) and drops what is older than the window.
void PlanetRecorder::add(Dictionary p_entry) {
	double now = (double)Time::get_singleton()->get_ticks_msec() / 1000.0;
	p_entry["time"] = snapped(now, 0.001);
	std::lock_guard<std::mutex> guard(lock);
	lines.push_back({ now, JSON::stringify(p_entry) });
	while (!lines.empty() && now - lines.front().time > WINDOW) {
		lines.erase(lines.begin());
	}
}

void PlanetRecorder::write() {
	if (in_a_lab()) {
		return;
	}
	Ref<FileAccess> file = FileAccess::open(RECORD_PATH, FileAccess::WRITE);
	if (file.is_null()) {
		return;
	}
	String world = world_line();
	if (world != "") {
		file->store_line(world);
	}
	std::lock_guard<std::mutex> guard(lock);
	for (const Line &entry : lines) {
		file->store_line(entry.json);
	}
	file->close();
}

// Called by the logger, possibly from another thread.
void PlanetRecorder::note_message(const String &p_kind, const String &p_text) {
	Dictionary entry;
	entry["kind"] = p_kind;
	entry["text"] = p_text.left(300);
	call_deferred("add_deferred", entry);
}
