class_name HairStyleStore
extends RefCounted
## Saved custom hairstyles for the human body lab: the whole-head hair settings, the zone changes and the wet look, one JSON file a style
## (<dir>/<name>.json: {"version": 1, "style": {...}, "zones": {zone: {...}}, "wet": x}). Never the hair colour: a hairstyle does not change it.
## Settings come back with StringName keys (as the lab keeps them); zone names stay Strings. Unknown settings are kept: the builder ignores them.

const VERSION: int = 1


## Letters, digits, space, - and _ only (no path characters), trimmed.
static func clean_name(style_name: String) -> String:
	var out: String = ""
	for c: String in style_name:
		if c == " " or c == "-" or c == "_" or (c >= "0" and c <= "9") or (c.to_lower() >= "a" and c.to_lower() <= "z"):
			out += c
	return out.strip_edges()


static func save_style(dir: String, style_name: String, style: Dictionary, zones: Dictionary, wet: float) -> Error:
	var file_name: String = clean_name(style_name)
	if file_name.is_empty():
		return ERR_INVALID_PARAMETER
	var made: Error = DirAccess.make_dir_recursive_absolute(dir)
	if made != OK and not DirAccess.dir_exists_absolute(dir):
		return made
	var zone_data: Dictionary = {}
	for zone: Variant in zones:
		zone_data[str(zone)] = _plain(zones[zone])
	var data: Dictionary = {"version": VERSION, "style": _plain(style), "zones": zone_data, "wet": wet}
	var file := FileAccess.open(dir.path_join(file_name + ".json"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK


## {"style": {StringName: value}, "zones": {String: {StringName: value}}, "wet": float}, or {} when there is no such style (or it is not readable).
static func load_style(dir: String, style_name: String) -> Dictionary:
	var path: String = dir.path_join(clean_name(style_name) + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	var zones: Dictionary = {}
	var raw_zones: Variant = data.get("zones", {})
	if raw_zones is Dictionary:
		for zone: Variant in raw_zones:
			if raw_zones[zone] is Dictionary:
				zones[str(zone)] = _named(raw_zones[zone])
	var raw_style: Variant = data.get("style", {})
	return {"style": _named(raw_style) if raw_style is Dictionary else {}, "zones": zones, "wet": float(data.get("wet", 0.0))}


static func list_styles(dir: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return names
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "json":
			names.append(file_name.get_basename())
	names.sort()
	return names


static func delete_style(dir: String, style_name: String) -> Error:
	return DirAccess.remove_absolute(dir.path_join(clean_name(style_name) + ".json"))


# {StringName: number} -> {String: number} (JSON keys are strings)
static func _plain(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in values:
		var value: Variant = values[key]
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT or typeof(value) == TYPE_BOOL:
			out[str(key)] = value
	return out


static func _named(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in values:
		out[StringName(str(key))] = values[key]
	return out
