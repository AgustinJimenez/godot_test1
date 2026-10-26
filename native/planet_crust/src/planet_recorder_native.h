#pragma once

// PlanetRecorder (was systems/planet/planet_recorder.gd): a flight recorder for play: always on in the planet, it keeps the last WINDOW seconds (a
// sample every INTERVAL seconds and every error or warning the engine prints) and rewrites them to user://planet_live.jsonl once a second, on a
// mark and on exit. After something looks wrong, the file already holds the moments before it. F9 marks "this looks wrong now".

#include "native_props.h"

#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/logger.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/script_backtrace.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <mutex>
#include <vector>

namespace godot {

class PlanetRecorder;

// Hears what the engine prints (errors and warnings) and passes it to the recorder.
class PlanetRecorderLogger : public Logger {
	GDCLASS(PlanetRecorderLogger, Logger)

protected:
	static void _bind_methods() {}

public:
	ObjectID recorder;
	void _log_error(const String &p_function, const String &p_file, int32_t p_line, const String &p_code, const String &p_rationale, bool p_editor_notify,
			int32_t p_error_type, const TypedArray<Ref<ScriptBacktrace>> &p_script_backtraces) override;
};

class PlanetRecorder : public Node {
	GDCLASS(PlanetRecorder, Node)

	struct Line {
		double time;
		String json;
	};
	std::vector<Line> lines; // oldest first
	std::mutex lock;
	double since_sample = 0.0;
	double since_write = 0.0;
	int marks = 0;
	Ref<PlanetRecorderLogger> logger;

	String world_line() const;
	void keep_a_copy();
	bool in_a_lab() const;
	Dictionary sample();
	void add(Dictionary p_entry);
	void write();

protected:
	static void _bind_methods();

public:
	static constexpr double WINDOW = 10.0; // seconds kept
	static constexpr double INTERVAL = 0.2; // seconds between samples
	static constexpr double WRITE_EVERY = 1.0; // seconds between file writes
	static constexpr int MAX_MARKS = 20;

	NP_OBJECT(planet)

	void _ready() override;
	void _exit_tree() override;
	void _process(double p_delta) override;
	void _unhandled_key_input(const Ref<InputEvent> &p_event) override;
	void note_message(const String &p_kind, const String &p_text);
	void add_deferred(const Dictionary &p_entry) { add(p_entry); }
};

} // namespace godot
