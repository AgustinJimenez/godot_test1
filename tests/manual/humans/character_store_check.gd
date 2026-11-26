extends SceneTree
## Headless check of CharacterStore (saved characters: the lab's whole editor state).
##   godot --headless --path . -s res://tests/manual/humans/character_store_check.gd
## Works in a scratch folder of its own (never the user's characters). Prints CHARACTER_STORE_CHECK PASS or FAIL lines.

const DIR: String = "user://character_store_check_tmp"

var _failures: int = 0


func _init() -> void:
	_wipe()
	var state: Dictionary = {
		"gender": "Female", "height": 0.4, "different_eyes": true,
		"eye_color": Color(0.1, 0.4, 0.7, 1.0),
		"face_values": {&"nose_long": 0.6, &"jaw_wide": 0.3},
		"skin_values": {&"skin_tone": 0.7},
		"hair_style": {&"length": 0.2, &"curl": 0.5},
		"hair_zones": {"left_side": {&"amount": 0.0}},
		"hair_preset": "Long",
	}
	_expect(CharacterStore.save_character(DIR, "Ana", state) == OK, "save failed")
	_expect(CharacterStore.list_characters(DIR) == PackedStringArray(["Ana"]), "list: %s" % [CharacterStore.list_characters(DIR)])
	var back: Dictionary = CharacterStore.load_character(DIR, "Ana")
	_expect(not back.is_empty(), "load returned nothing")
	if not back.is_empty():
		_expect(back["gender"] == "Female" and is_equal_approx(float(back["height"]), 0.4) and back["different_eyes"] == true, "plain values: %s" % [back])
		_expect(back["eye_color"] is Color and (back["eye_color"] as Color).is_equal_approx(Color(0.1, 0.4, 0.7, 1.0)), "colour: %s" % [back["eye_color"]])
		var face: Dictionary = back["face_values"]
		_expect(face.has(&"nose_long") and typeof(face.keys()[0]) == TYPE_STRING_NAME and is_equal_approx(float(face[&"nose_long"]), 0.6), "face keys: %s" % [face])
		_expect((back["hair_style"] as Dictionary).has(&"curl") and (back["skin_values"] as Dictionary).has(&"skin_tone"), "named dictionaries: %s" % [back])
		var zone: Dictionary = (back["hair_zones"] as Dictionary).get("left_side", {})
		_expect(zone.has(&"amount") and typeof(zone.keys()[0]) == TYPE_STRING_NAME, "zones: %s" % [back["hair_zones"]])
	_expect(CharacterStore.load_character(DIR, "Nobody").is_empty(), "a missing character loaded something")
	_expect(CharacterStore.delete_character(DIR, "Ana") == OK and CharacterStore.list_characters(DIR).is_empty(), "delete left %s" % [CharacterStore.list_characters(DIR)])
	_wipe()
	print("CHARACTER_STORE_CHECK PASS" if _failures == 0 else "CHARACTER_STORE_CHECK FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for name: String in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR + "/" + name)
		DirAccess.remove_absolute(DIR)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("CHARACTER_STORE_CHECK failed: ", message)
