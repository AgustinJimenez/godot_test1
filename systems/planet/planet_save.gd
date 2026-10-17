class_name PlanetSave
extends RefCounted
## Saved planets: a file in user://planets/ with the planet's settings (the seed and the numbers
## the planet is made from: the same settings make the same planet, so the land itself is not
## stored) and the moment: where the player stands and which way they face, the clock (the hour and
## the day of the year), the speed of time and the weather forced, if any. Opening a save makes the
## planet again and puts the player back; the ground is rebuilt from the seed as at any start.

const DIR := "user://planets"
const VERSION := 1


## The path of the save called `save_name` (anything but letters, digits, - and _ becomes _).
static func path_for(save_name: String) -> String:
	var clean := ""
	for character in save_name.strip_edges():
		var code := character.unicode_at(0)
		var plain := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) or character == "-" or character == "_"
		clean += character if plain else "_"
	return "%s/%s.json" % [DIR, clean if clean != "" else "world"]


## Writes `planet`'s settings and moment as the save `save_name`. True if it was written.
static func save(planet: PlanetWorld, save_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": VERSION,
		"name": save_name.strip_edges(),
		"saved_at": int(Time.get_unix_time_from_system()),
		"settings": _settings_to_dictionary(planet.settings),
		"state": planet.snapshot(),
	}
	var file := FileAccess.open(path_for(save_name), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


## The contents of the save `save_name` ({} if there is none or it cannot be read).
static func load_data(save_name: String) -> Dictionary:
	var file := FileAccess.open(path_for(save_name), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## The settings stored in a save (what the planet was made from).
static func settings_from(data: Dictionary) -> PlanetSettings:
	var settings := PlanetSettings.new()
	var stored: Dictionary = data.get("settings", {})
	for property: Dictionary in settings.get_property_list():
		var key: String = property["name"]
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not stored.has(key):
			continue
		var current: Variant = settings.get(key)
		settings.set(key, int(stored[key]) if current is int else float(stored[key]))
	return settings


## The saves there are, newest first: [{name, seed, radius, saved_at}].
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file_name in DirAccess.get_files_at(DIR):
		if not file_name.ends_with(".json"):
			continue
		var data := load_data(file_name.trim_suffix(".json"))
		if data.is_empty():
			continue
		var stored: Dictionary = data.get("settings", {})
		found.append({
			"name": str(data.get("name", file_name.trim_suffix(".json"))),
			"seed": int(stored.get("world_seed", 0)),
			"radius": float(stored.get("radius", 0.0)),
			"saved_at": int(data.get("saved_at", 0)),
		})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["saved_at"]) > int(b["saved_at"]))
	return found


## The name of the newest save ("" if there is none).
static func latest() -> String:
	var saves := list()
	return "" if saves.is_empty() else str(saves[0]["name"])


## Removes the save `save_name`.
static func delete(save_name: String) -> void:
	DirAccess.remove_absolute(path_for(save_name))


static func _settings_to_dictionary(settings: PlanetSettings) -> Dictionary:
	var stored := {}
	for property: Dictionary in settings.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var key: String = property["name"]
			stored[key] = settings.get(key)
	return stored
