#include "planet_log_native.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <map>
#include <mutex>
#include <string>
#include <vector>

using namespace godot;

// ---- PlanetMapLog ----

static std::mutex log_mutex;
static Ref<FileAccess> log_file;
static uint64_t log_started_ms = 0;
static int64_t log_bytes = 0;
static bool log_full = false;
static std::map<std::string, uint64_t> log_last; // key -> the time (ms) its last throttled line was written

void PlanetMapLog::_bind_methods() {
	BIND_CONSTANT(MAX_BYTES);
	ClassDB::bind_static_method("PlanetMapLog", D_METHOD("get_path"), &PlanetMapLog::get_path);
	ClassDB::bind_static_method("PlanetMapLog", D_METHOD("begin", "note"), &PlanetMapLog::begin);
	ClassDB::bind_static_method("PlanetMapLog", D_METHOD("end"), &PlanetMapLog::end);
	ClassDB::bind_static_method("PlanetMapLog", D_METHOD("line", "text"), &PlanetMapLog::line);
	ClassDB::bind_static_method("PlanetMapLog", D_METHOD("line_every", "key", "seconds", "text"), &PlanetMapLog::line_every);
	ClassDB::bind_static_method("PlanetMapLog", D_METHOD("where"), &PlanetMapLog::where);
}

// Starts a fresh log (the old one is gone): the map has just been opened.
void PlanetMapLog::begin(const String &p_note) {
	{
		std::lock_guard<std::mutex> lock(log_mutex);
		if (log_file.is_valid()) {
			log_file->close();
		}
		log_file = FileAccess::open(get_path(), FileAccess::WRITE);
		log_started_ms = Time::get_singleton()->get_ticks_msec();
		log_bytes = 0;
		log_full = false;
		log_last.clear();
	}
	line("map opened: " + p_note);
}

// The map was closed: the last line, and the file is let go.
void PlanetMapLog::end() {
	line("map closed");
	std::lock_guard<std::mutex> lock(log_mutex);
	if (log_file.is_valid()) {
		log_file->close();
		log_file.unref();
	}
}

// One line with the time since the map opened (seconds).
void PlanetMapLog::line(const String &p_text) {
	std::lock_guard<std::mutex> lock(log_mutex);
	if (log_file.is_valid() && !log_full) {
		String stamp = vformat("%7.3f  ", (double)(Time::get_singleton()->get_ticks_msec() - log_started_ms) / 1000.0);
		String out = stamp + p_text + "\n";
		log_bytes += out.length();
		if (log_bytes > MAX_BYTES) {
			log_full = true;
			out = stamp + "-- the log is full: the rest is dropped --\n";
		}
		log_file->store_string(out);
		log_file->flush();
	}
}

// Like `line`, but at most one every `seconds` for the same `key` (a drag or a wheel makes many).
void PlanetMapLog::line_every(const String &p_key, double p_seconds, const String &p_text) {
	uint64_t now = Time::get_singleton()->get_ticks_msec();
	bool due;
	{
		std::lock_guard<std::mutex> lock(log_mutex);
		std::string key = p_key.utf8().get_data();
		auto found = log_last.find(key);
		due = found == log_last.end() || (double)(now - found->second) >= p_seconds * 1000.0;
		if (due) {
			log_last[key] = now;
		}
	}
	if (due) {
		line(p_text);
	}
}

// Where the file is on this machine.
String PlanetMapLog::where() {
	return ProjectSettings::get_singleton()->globalize_path(get_path());
}

// ---- PlanetChartProfile ----

static std::mutex profile_mutex;
static std::map<std::string, int64_t> profile_phases; // phase -> microseconds
static std::vector<std::string> profile_order; // the phases in the order they first appeared

void PlanetChartProfile::_bind_methods() {
	ClassDB::bind_static_method("PlanetChartProfile", D_METHOD("lap", "phase", "since"), &PlanetChartProfile::lap);
	ClassDB::bind_static_method("PlanetChartProfile", D_METHOD("take"), &PlanetChartProfile::take);
	ClassDB::bind_static_method("PlanetChartProfile", D_METHOD("report", "title", "wall_ms", "native"), &PlanetChartProfile::report);
}

int64_t PlanetChartProfile::lap(const String &p_phase, int64_t p_since) {
	int64_t now = (int64_t)Time::get_singleton()->get_ticks_usec();
	std::lock_guard<std::mutex> lock(profile_mutex);
	std::string phase = p_phase.utf8().get_data();
	if (profile_phases.find(phase) == profile_phases.end()) {
		profile_phases[phase] = 0;
		profile_order.push_back(phase);
	}
	profile_phases[phase] += now - p_since;
	return now;
}

Array PlanetChartProfile::take() {
	std::lock_guard<std::mutex> lock(profile_mutex);
	Array out;
	for (const std::string &phase : profile_order) {
		Array entry;
		entry.append(String::utf8(phase.c_str()));
		entry.append((double)profile_phases[phase] / 1000.0);
		out.append(entry);
	}
	profile_phases.clear();
	profile_order.clear();
	return out;
}

// The report of a picture: its wall time and every phase's CPU time (and the native parts inside the rows).
void PlanetChartProfile::report(const String &p_title, double p_wall_ms, Object *p_native) {
	Array lines;
	lines.append(vformat("chart %s: %.0f ms wall", p_title, p_wall_ms));
	Array phases = take();
	for (int i = 0; i < phases.size(); i++) {
		Array entry = phases[i];
		lines.append(vformat("    %-22s %8.1f ms cpu", entry[0], entry[1]));
	}
	if (p_native != nullptr && p_native->has_method("profile_take")) {
		Dictionary inside = p_native->call("profile_take");
		Array keys = inside.keys();
		for (int i = 0; i < keys.size(); i++) {
			if ((double)inside[keys[i]] > 0.0) {
				lines.append(vformat("      in the rows: %-14s %8.1f ms cpu", keys[i], inside[keys[i]]));
			}
		}
	}
	for (int i = 0; i < lines.size(); i++) {
		String text = lines[i];
		PlanetMapLog::line(text);
		if (OS::get_singleton()->has_environment("PLANET_CHART_PROFILE")) {
			UtilityFunctions::print("CHART_PROFILE ", text);
		}
	}
}
