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

// an object property (a Ref to a native class of ours): typed for GDScript by its resource-type hint
#define NP_BIND_OBJ(CLS, N, TYPE) \
	ClassDB::bind_method(D_METHOD("get_" #N), &CLS::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &CLS::set_##N); \
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, #N, PROPERTY_HINT_RESOURCE_TYPE, TYPE, PROPERTY_USAGE_NO_EDITOR), "set_" #N, "get_" #N);

// a GDScript object held by id (a node of the scene that may be freed): the property is typed Object for scripts
#include <godot_cpp/core/object.hpp>
#define NP_OBJECT(N) \
	ObjectID N##_id; \
	Object *get_##N() const { return ObjectDB::get_instance(N##_id); } \
	void set_##N(Object *p_v) { N##_id = p_v != nullptr ? p_v->get_instance_id() : ObjectID(); }

#define NP_BIND_OBJECT(CLS, N) \
	ClassDB::bind_method(D_METHOD("get_" #N), &CLS::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &CLS::set_##N); \
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, #N, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "set_" #N, "get_" #N);
