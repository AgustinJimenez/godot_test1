#pragma once

// PlanetMapLog and PlanetChartProfile (were systems/planet/planet_map_log.gd and planet_chart_profile.gd).
// The log of what the map does, written to user://planet_map.log while it is open (emptied each time the map is opened, stops growing at
// MAX_BYTES); and where the time of a map picture goes (the phases the chart's threads add their microseconds to). Both are safe to call from the
// chart threads.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class PlanetMapLog : public RefCounted {
	GDCLASS(PlanetMapLog, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_BYTES = 120000;

	static String get_path() { return "user://planet_map.log"; }
	static void begin(const String &p_note);
	static void end();
	static void line(const String &p_text);
	static void line_every(const String &p_key, double p_seconds, const String &p_text);
	static String where();
};

class PlanetChartProfile : public RefCounted {
	GDCLASS(PlanetChartProfile, RefCounted)

protected:
	static void _bind_methods();

public:
	// Adds the time since `since` (a Time.get_ticks_usec value) to `phase`; returns now, for the next phase.
	static int64_t lap(const String &p_phase, int64_t p_since);
	// The phases so far ([name, ms] in the order they appeared); they are cleared.
	static Array take();
	static void report(const String &p_title, double p_wall_ms, Object *p_native);
};

} // namespace godot
