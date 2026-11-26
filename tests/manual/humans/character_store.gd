class_name CharacterStore
extends RefCounted
## Saved characters for the human body lab: everything the editor sets (body, face and body shapes, skin, eyes, brows, hair, beard), one JSON
## file a character (<dir>/<name>.json: {"version": 1, "state": {...}}). The state is the lab's own Dictionary: values may be numbers, bools,
## strings, Colors, Dictionaries and Arrays. Colors are stored as {"color": [r, g, b, a]}; Dictionary keys are stored as strings and come back
## as StringNames inside the dictionaries named in NAMED_KEYS (the lab keeps those keyed by StringName), as Strings elsewhere.

const VERSION: int = 1
const NAMED_KEYS: Array[String] = ["face_values", "skin_values", "hair_style"]   # their keys are StringNames in the lab
const NAMED_INNER_KEYS: Array[String] = ["hair_zones"]                            # a zone name (String) -> {StringName: value}


static func save_character(dir: String, character_name: String, state: Dictionary) -> Error:
	var file_name: String = HairStyleStore.clean_name(character_name)
	if file_name.is_empty():
		return ERR_INVALID_PARAMETER
	var made: Error = DirAccess.make_dir_recursive_absolute(dir)
	if made != OK and not DirAccess.dir_exists_absolute(dir):
		return made
	var file := FileAccess.open(dir.path_join(file_name + ".json"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "state": _plain(state)}, "\t"))
	file.close()
	return OK


## The saved state (keys as the lab keeps them), or {} when there is no such character (or it is not readable).
static func load_character(dir: String, character_name: String) -> Dictionary:
	var path: String = dir.path_join(HairStyleStore.clean_name(character_name) + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("state") is Dictionary):
		return {}
	var raw: Dictionary = (parsed as Dictionary)["state"]
	var state: Dictionary = {}
	for key: Variant in raw:
		var value: Variant = _rich(raw[key])
		if str(key) in NAMED_KEYS and value is Dictionary:
			value = _named(value)
		elif str(key) in NAMED_INNER_KEYS and value is Dictionary:
			var zones: Dictionary = {}
			for zone: Variant in value:
				if (value as Dictionary)[zone] is Dictionary:
					zones[str(zone)] = _named((value as Dictionary)[zone])
			value = zones
		state[str(key)] = value
	return state


static func list_characters(dir: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return names
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "json":
			names.append(file_name.get_basename())
	names.sort()
	return names


static func delete_character(dir: String, character_name: String) -> Error:
	return DirAccess.remove_absolute(dir.path_join(HairStyleStore.clean_name(character_name) + ".json"))


# Variant -> JSON-safe (Colors as {"color": [...]}, Vector2/3 as {"vec": [...]}, keys as strings)
static func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_COLOR:
			var c: Color = value
			return {"color": [c.r, c.g, c.b, c.a]}
		TYPE_VECTOR2, TYPE_VECTOR3:
			var v: Variant = value
			return {"vec": [v.x, v.y] if typeof(value) == TYPE_VECTOR2 else [v.x, v.y, v.z]}
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value:
				out[str(key)] = _plain((value as Dictionary)[key])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for item: Variant in value:
				arr.append(_plain(item))
			return arr
		TYPE_STRING_NAME:
			return str(value)
	return value


static func _rich(value: Variant) -> Variant:
	if value is Dictionary:
		var d: Dictionary = value
		if d.size() == 1 and d.has("color") and d["color"] is Array and (d["color"] as Array).size() == 4:
			var c: Array = d["color"]
			return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
		if d.size() == 1 and d.has("vec") and d["vec"] is Array:
			var v: Array = d["vec"]
			return Vector2(float(v[0]), float(v[1])) if v.size() == 2 else Vector3(float(v[0]), float(v[1]), float(v[2]))
		var out: Dictionary = {}
		for key: Variant in d:
			out[key] = _rich(d[key])
		return out
	if value is Array:
		var arr: Array = []
		for item: Variant in value:
			arr.append(_rich(item))
		return arr
	return value


static func _named(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in values:
		out[StringName(str(key))] = values[key]
	return out
