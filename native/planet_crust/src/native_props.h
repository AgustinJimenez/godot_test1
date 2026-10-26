#pragma once

// Shorthand for the ported planet scripts (AGENT_TASKS/092): a stored property with its getter and setter, and its binding as an
// editor/script property of the same name the GDScript `var`/`@export var` had.

#include <godot_cpp/core/class_db.hpp>

#define NP_FIELD(T, N, D) \
	T N = D; \
	T get_##N() const { return N; } \
	void set_##N(const T &p_v) { N = p_v; }

#define NP_BIND(CLS, VT, N) \
	ClassDB::bind_method(D_METHOD("get_" #N), &CLS::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &CLS::set_##N); \
	ADD_PROPERTY(PropertyInfo(VT, #N), "set_" #N, "get_" #N);

// a property scripts read and write but the editor and saved resources leave alone
#define NP_BIND_STATE(CLS, VT, N) \
	ClassDB::bind_method(D_METHOD("get_" #N), &CLS::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &CLS::set_##N); \
	ADD_PROPERTY(PropertyInfo(VT, #N, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "set_" #N, "get_" #N);
