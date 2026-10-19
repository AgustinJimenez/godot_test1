class_name PlanetDrainageCache
extends RefCounted
## The planet's rivers kept on disk between runs: the drainage solve and the river network are the longest part of loading a
## big planet (1.9 s of 2.8 s on a full Earth) and are a function of the world's settings alone, so a world opened again
## reads them instead. One file per world: `user://drainage_cache/<key>.bin`, the key a hash of the settings, of VERSION and
## of the modification times of the native library and of the scripts the rivers come from (a rebuilt crust or an edited
## climate makes a new key: an old file is never read for new code). RAISE `VERSION` when the drainage or the climate
## changes in a way those times would not show (an exported game has no times).

const VERSION := 1
const ROOT := "user://drainage_cache"
const MAX_FILES := 8 ## worlds kept (the least recently written go)
const SOURCES := ["res://systems/planet/planet_drainage.gd", "res://systems/planet/planet_climate.gd",
		"res://systems/planet/planet_seasons.gd", "res://systems/planet/planet_noise.gd",
		"res://systems/planet/planet_tectonics.gd"]


static func _path(settings: PlanetSettings) -> String:
	var stored := {}
	for property: Dictionary in settings.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			stored[property["name"]] = settings.get(property["name"])
	var stamp := 0
	for source: String in SOURCES:
		stamp = maxi(stamp, FileAccess.get_modified_time(source))
	for file in DirAccess.get_files_at("res://native/planet_crust/bin"):
		if file.get_extension() in ["dll", "so", "dylib"]:
			stamp = maxi(stamp, FileAccess.get_modified_time("res://native/planet_crust/bin/" + file))
	var key := (var_to_str(stored) + "|drain%d|%d" % [VERSION, stamp]).md5_text().substr(0, 16)
	return "%s/%s.bin" % [ROOT, key]


## The river network (what `PlanetCrustNative.set_rivers` takes) kept for these settings, or an empty dictionary.
static func load_network(settings: PlanetSettings) -> Dictionary:
	var path := _path(settings)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var network: Variant = file.get_var()
	if not network is Dictionary or not (network as Dictionary).has("cell_start"):
		return {}
	return network


static func save_network(settings: PlanetSettings, network: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var path := _path(settings)
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return
	file.store_var(network)
	file.close()
	_trim()


static func _trim() -> void:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(ROOT):
		files.append(file)
	if files.size() <= MAX_FILES:
		return
	files.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time("%s/%s" % [ROOT, a]) < FileAccess.get_modified_time("%s/%s" % [ROOT, b]))
	for index in files.size() - MAX_FILES:
		DirAccess.remove_absolute("%s/%s" % [ROOT, files[index]])
