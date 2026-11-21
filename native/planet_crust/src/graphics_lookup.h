#pragma once

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

// The GraphicsSettings autoload. Looking a node up by its name from a worker thread is refused by the engine (an error per call), so the
// lookup is done on the main thread once and kept as an object id, which any thread may resolve.
inline Node *graphics_settings_node() {
	static int64_t cached = 0;
	if (cached != 0) {
		Object *found = UtilityFunctions::instance_from_id(cached);
		if (found != nullptr) {
			return Object::cast_to<Node>(found);
		}
		cached = 0;
	}
	OS *os = OS::get_singleton();
	if (os->get_thread_caller_id() != os->get_main_thread_id()) {
		return nullptr; // (not seen yet by the main thread: the caller takes its default)
	}
	SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
	if (tree == nullptr || tree->get_root() == nullptr) {
		return nullptr;
	}
	Node *settings = tree->get_root()->get_node_or_null("GraphicsSettings");
	if (settings != nullptr) {
		cached = (int64_t)settings->get_instance_id();
	}
	return settings;
}

// (task 101) one setting of the autoload, as a small integer level (`p_default` when the autoload is not there: a tool or a worker thread that has not seen it)
inline int graphics_level(const char *p_key, int p_default) {
	Node *settings = graphics_settings_node();
	if (settings == nullptr) {
		return p_default;
	}
	Variant value = settings->call("get_graphics_value", StringName(p_key));
	return value.get_type() == Variant::NIL ? p_default : (int)(int64_t)value;
}

} // namespace godot
