class_name PlanetMapCache
extends RefCounted
## The map's pictures kept on disk between runs, so a world opened again shows its map at once
## instead of charting it. One folder per world: `user://map_cache/<key>/`, the key being a hash of
## the world's settings and of VERSION. The land is a function of those settings, so the same key
## is the same pictures. RAISE `VERSION` whenever the crust, the climate or the way a layer is drawn
## changes (an old picture would otherwise show the old look). Only the layers that do not follow
## the clock are kept (the temperature, the clouds and the satellite change with the date).
##
## What changes in the world afterwards (a fire, a crater) is not in the base pictures:
## `forget_area` throws away the tiles that touch it and `forget_whole` the whole-planet pictures;
## the map charts them again. See PlanetMap.world_changed.

const VERSION := 2 ## 2: the atlas inks only the broad hills
const ROOT := "user://map_cache"
const MAX_TILES := 900 ## tile files kept per world (the oldest go first)
const MAX_WORLDS := 6 ## worlds kept (the least recently used go)

var _dir := ""
var _tile_files := 0


## Opens the folder of the world with these settings.
func _init(settings: PlanetSettings) -> void:
	var stored := {}
	for property: Dictionary in settings.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			stored[property["name"]] = settings.get(property["name"])
	var key := (var_to_str(stored) + "|map%d" % VERSION).md5_text().substr(0, 16)
	_dir = "%s/%s" % [ROOT, key]
	DirAccess.make_dir_recursive_absolute(_dir)
	DirAccess.make_dir_recursive_absolute(_dir + "/tiles")
	_touch()
	_tile_files = DirAccess.get_files_at(_dir + "/tiles").size()
	_trim_worlds()


func directory() -> String:
	return _dir


## Whether a layer is kept on disk (the ones that follow the clock are not).
static func keeps(layer: int) -> bool:
	return layer != PlanetChart.Layer.TEMPERATURE and layer != PlanetChart.Layer.CLOUDS \
			and layer != PlanetChart.Layer.SATELLITE and layer != PlanetChart.Layer.CLOUD_MASK


func _whole_path(layer: int, across: int) -> String:
	return "%s/whole_%d_%d.png" % [_dir, layer, across]


func save_whole(layer: int, across: int, texture: Texture2D) -> void:
	if keeps(layer) and texture != null:
		texture.get_image().save_png(_whole_path(layer, across))


## The whole-planet picture of a layer at a width, or null.
func load_whole(layer: int, across: int) -> ImageTexture:
	if not keeps(layer) or not FileAccess.file_exists(_whole_path(layer, across)):
		return null
	var image := Image.load_from_file(_whole_path(layer, across))
	return ImageTexture.create_from_image(image) if image != null else null


func _tile_path(key: Vector4i) -> String:
	return "%s/tiles/%d_%d_%d_%d.png" % [_dir, key.x, key.y, key.z, key.w]


func save_tile(key: Vector4i, texture: Texture2D) -> void:
	if not keeps(key.x) or texture == null:
		return
	texture.get_image().save_png(_tile_path(key))
	_tile_files += 1
	if _tile_files > MAX_TILES:
		_trim_tiles()


func load_tile(key: Vector4i) -> ImageTexture:
	if not keeps(key.x) or not FileAccess.file_exists(_tile_path(key)):
		return null
	var image := Image.load_from_file(_tile_path(key))
	return ImageTexture.create_from_image(image) if image != null else null


## Throws away the tile files whose part of the map touches `area` (fractions of the map).
func forget_area(area: Rect2) -> int:
	var gone := 0
	for file in DirAccess.get_files_at(_dir + "/tiles"):
		var parts := file.get_basename().split("_")
		if parts.size() != 4:
			continue
		var rect := PlanetMapTiles.rect_of(int(parts[1]), int(parts[2]), int(parts[3]))
		if rect.intersects(area):
			DirAccess.remove_absolute("%s/tiles/%s" % [_dir, file])
			gone += 1
	_tile_files = maxi(_tile_files - gone, 0)
	return gone


## Throws away the whole-planet pictures (a change somewhere makes them old).
func forget_whole() -> void:
	for file in DirAccess.get_files_at(_dir):
		if file.begins_with("whole_"):
			DirAccess.remove_absolute("%s/%s" % [_dir, file])


func _touch() -> void:
	var stamp := FileAccess.open(_dir + "/used", FileAccess.WRITE)
	if stamp != null:
		stamp.store_string(str(Time.get_unix_time_from_system()))


## Keeps the newest MAX_TILES tile files.
func _trim_tiles() -> void:
	var files := DirAccess.get_files_at(_dir + "/tiles")
	var dated: Array[Dictionary] = []
	for file in files:
		var path := "%s/tiles/%s" % [_dir, file]
		dated.append({"path": path, "time": FileAccess.get_modified_time(path)})
	dated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	var surplus := dated.size() - int(MAX_TILES * 0.8)
	for index in maxi(surplus, 0):
		DirAccess.remove_absolute(dated[index]["path"])
	_tile_files = DirAccess.get_files_at(_dir + "/tiles").size()


## Keeps the MAX_WORLDS most recently used worlds.
func _trim_worlds() -> void:
	var worlds: Array[Dictionary] = []
	for folder in DirAccess.get_directories_at(ROOT):
		var path := "%s/%s" % [ROOT, folder]
		worlds.append({"path": path, "time": FileAccess.get_modified_time(path + "/used")})
	if worlds.size() <= MAX_WORLDS:
		return
	worlds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	for index in worlds.size() - MAX_WORLDS:
		_remove_folder(worlds[index]["path"])


func _remove_folder(path: String) -> void:
	for file in DirAccess.get_files_at(path + "/tiles"):
		DirAccess.remove_absolute("%s/tiles/%s" % [path, file])
	DirAccess.remove_absolute(path + "/tiles")
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file])
	DirAccess.remove_absolute(path)
