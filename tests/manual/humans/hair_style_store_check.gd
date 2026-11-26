extends SceneTree
## Headless check of HairStyleStore (saved custom hairstyles: whole-head settings, zone changes, wet look).
##   godot --headless --path . -s res://tests/manual/humans/hair_style_store_check.gd
## Works in a scratch folder of its own (never the user's saved styles). Prints HAIR_STYLE_STORE_CHECK PASS or FAIL lines.

const DIR: String = "user://hair_style_store_check_tmp"

var _failures: int = 0


func _init() -> void:
	_wipe()
	var style: Dictionary = {&"length": 0.07, &"spike": 0.5}
	var zones: Dictionary = {"left_side": {&"amount": 0.0}}
	_expect(HairStyleStore.save_style(DIR, "My mohawk", style, zones, 0.2) == OK, "save_style failed")
	_expect(HairStyleStore.list_styles(DIR) == PackedStringArray(["My mohawk"]), "list_styles: %s" % [HairStyleStore.list_styles(DIR)])
	var loaded: Dictionary = HairStyleStore.load_style(DIR, "My mohawk")
	_expect(not loaded.is_empty(), "load_style returned nothing")
	if not loaded.is_empty():
		var loaded_style: Dictionary = loaded["style"]
		_expect(loaded_style.has(&"length") and typeof(loaded_style.keys()[0]) == TYPE_STRING_NAME, "style keys are not StringName: %s" % [loaded_style])
		_expect(is_equal_approx(float(loaded_style[&"length"]), 0.07) and is_equal_approx(float(loaded_style[&"spike"]), 0.5), "style values: %s" % [loaded_style])
		var loaded_zone: Dictionary = (loaded["zones"] as Dictionary).get("left_side", {})
		_expect(loaded_zone.has(&"amount") and is_equal_approx(float(loaded_zone[&"amount"]), 0.0), "zones: %s" % [loaded["zones"]])
		_expect(is_equal_approx(float(loaded["wet"]), 0.2), "wet: %s" % [loaded["wet"]])
	_expect(HairStyleStore.delete_style(DIR, "My mohawk") == OK and HairStyleStore.list_styles(DIR).is_empty(), "delete_style left %s" % [HairStyleStore.list_styles(DIR)])
	# a file from a later version with a setting this build does not know: it loads (the builder ignores unknown settings)
	var file := FileAccess.open(DIR + "/Odd.json", FileAccess.WRITE)
	file.store_string('{"version": 1, "style": {"length": 0.1}, "zones": {"top": {"made_up": 2}}, "wet": 0}')
	file.close()
	var odd: Dictionary = HairStyleStore.load_style(DIR, "Odd")
	_expect(not odd.is_empty() and ((odd["zones"] as Dictionary).get("top", {}) as Dictionary).has(&"made_up"), "a style with an unknown setting did not load: %s" % [odd])
	_expect(HairStyleStore.load_style(DIR, "Missing").is_empty(), "a missing style loaded something")
	# names: only letters, digits, space, - and _ reach the file name
	_expect(HairStyleStore.save_style(DIR, "../Bad/name?", style, {}, 0.0) == OK and HairStyleStore.list_styles(DIR).has("Badname"), "a name with path characters: %s" % [HairStyleStore.list_styles(DIR)])
	_wipe()
	print("HAIR_STYLE_STORE_CHECK PASS" if _failures == 0 else "HAIR_STYLE_STORE_CHECK FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for name: String in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR + "/" + name)
		DirAccess.remove_absolute(DIR)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("HAIR_STYLE_STORE_CHECK failed: ", message)
