extends RefCounted
## One place that says whether the native foot IK classes are used (FootIKV2*Native in native/planet_crust, AGENT_TASKS/091) and makes them:
## `make(&"Limiter", FootIKV2... )` returns the native object, or the GDScript one built by `fallback` (the reference) when the library is not
## loaded or PLANET_NO_NATIVE=1.

static var _state := -1 # -1 unknown, 0 GDScript, 1 native


static func available() -> bool:
	if _state < 0:
		_state = 1 if ClassDB.class_exists(&"FootIKV2Native") and not OS.has_environment("PLANET_NO_NATIVE") else 0
	return _state == 1


static func make(native_name: StringName, fallback: Callable) -> Variant:
	if available() and ClassDB.class_exists(native_name):
		return ClassDB.instantiate(native_name)
	return fallback.call()
