class_name UniverseSave
extends RefCounted
## Saved universes: a file in user://universes/ with the planets of the universe (each one's
## settings: the same settings make the same planet, so the land itself is not stored), which of
## them the player is on, and the moment on that planet: where the player stands and which way they
## face, the clock (the hour and the day of the year), the speed of time and the weather forced.
## Today a universe has the one planet; the format already holds a list for the day the player can
## travel to others (each planet keeping its own settings, and the universe the seed they come
## from). Opening a save makes the planet again and puts the player back; the ground is rebuilt from
## the seed as at any start.

const DIR := "user://universes"
const OLD_DIR := "user://planets" ## the first saves (one planet, no universe): still read
const VERSION := 2
const FIRST_PLANET := "planet_1"


## The path of the save called `save_name` (anything but letters, digits, - and _ becomes _).
static func path_for(save_name: String, folder := DIR) -> String:
	var clean := ""
	for character in save_name.strip_edges():
		var code := character.unicode_at(0)
		var plain := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) or character == "-" or character == "_"
		clean += character if plain else "_"
	return "%s/%s.json" % [folder, clean if clean != "" else "universe"]


## Writes the universe `planet` belongs to as the save `save_name` (its planet and the moment on
## it; the other planets an existing save of that name has are kept). True if it was written.
static func save(planet: PlanetWorld, save_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var kept := load_data(save_name)
	var planets: Array = kept.get("planets", [])
	var planet_id: String = kept.get("current", FIRST_PLANET)
	var entry := {"id": planet_id, "settings": _settings_to_dictionary(planet.settings)}
	var replaced := false
	for index in planets.size():
		if (planets[index] as Dictionary).get("id", "") == planet_id:
			planets[index] = entry
			replaced = true
	if not replaced:
		planets.append(entry)
	var data := {
		"version": VERSION,
		"name": save_name.strip_edges(),
		"saved_at": int(Time.get_unix_time_from_system()),
		"planets": planets,
		"current": planet_id,
		"state": planet.snapshot(),
	}
	var file := FileAccess.open(path_for(save_name), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


## The contents of the save `save_name` ({} if there is none or it cannot be read). A first-version
## save (one planet) is brought to the universe layout.
static func load_data(save_name: String) -> Dictionary:
	var file := FileAccess.open(path_for(save_name), FileAccess.READ)
	if file == null:
		file = FileAccess.open(path_for(save_name, OLD_DIR), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	if not data.has("planets") and data.has("settings"):
		data["planets"] = [{"id": FIRST_PLANET, "settings": data["settings"]}]
		data["current"] = FIRST_PLANET
	return data


## The settings of the planet the player is on in a save (what that planet was made from).
static func settings_from(data: Dictionary) -> PlanetSettings:
	var settings := PlanetSettings.new()
	var stored := {}
	for entry: Dictionary in data.get("planets", []):
		if entry.get("id", "") == data.get("current", FIRST_PLANET):
			stored = entry.get("settings", {})
	for property: Dictionary in settings.get_property_list():
		var key: String = property["name"]
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not stored.has(key):
			continue
		var current: Variant = settings.get(key)
		settings.set(key, int(stored[key]) if current is int else float(stored[key]))
	return settings


## The saves there are, newest first: [{name, planets, seed, radius, saved_at}] (seed and radius
## are the ones of the planet the player is on).
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen := {}
	for folder in [DIR, OLD_DIR]:
		for file_name in DirAccess.get_files_at(folder):
			var save_name := file_name.trim_suffix(".json")
			if not file_name.ends_with(".json") or seen.has(save_name):
				continue
			var data := load_data(save_name)
			if data.is_empty():
				continue
			seen[save_name] = true
			var settings := settings_from(data)
			found.append({
				"name": str(data.get("name", save_name)),
				"planets": (data.get("planets", []) as Array).size(),
				"seed": settings.world_seed,
				"radius": settings.radius,
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
	DirAccess.remove_absolute(path_for(save_name, OLD_DIR))


static func _settings_to_dictionary(settings: PlanetSettings) -> Dictionary:
	var stored := {}
	for property: Dictionary in settings.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var key: String = property["name"]
			stored[key] = settings.get(key)
	return stored
