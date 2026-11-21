#pragma once

// (task 101) PLANET_TIMING=1: how long each planet node's per-frame function takes, printed as one line every 180 calls of the busiest one.
// `FRAME_TIMER("name")` at the top of a _process / _physics_process adds its time (ms) to that name.
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <map>
#include <string>

namespace frame_timer {

struct Totals {
	std::map<std::string, std::pair<double, int>> by_name;
	int frames = 0;
};

inline Totals &totals() {
	static Totals instance;
	return instance;
}

inline bool enabled() {
	static const bool on = godot::OS::get_singleton()->has_environment("PLANET_TIMING");
	return on;
}

struct Scope {
	const char *name;
	uint64_t began;
	explicit Scope(const char *p_name) :
			name(p_name), began(enabled() ? godot::Time::get_singleton()->get_ticks_usec() : 0) {}
	~Scope() {
		if (!enabled()) {
			return;
		}
		Totals &all = totals();
		auto &entry = all.by_name[name];
		entry.first += (godot::Time::get_singleton()->get_ticks_usec() - began) / 1000.0;
		entry.second += 1;
		if (entry.second >= 300) {
			std::string line;
			for (auto &item : all.by_name) {
				char text[96];
				snprintf(text, sizeof(text), " %s=%.2f", item.first.c_str(), item.second.first / std::max(item.second.second, 1));
				line += text;
				item.second = { 0.0, 0 };
			}
			godot::UtilityFunctions::print(godot::String("PLANET_FRAME ms per call:") + godot::String(line.c_str()));
		}
	}
};

} // namespace frame_timer

#define FRAME_TIMER(name) frame_timer::Scope frame_timer_scope(name)
