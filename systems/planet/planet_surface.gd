class_name PlanetSurface
extends Node3D
## The ground of a planet as tiles, finer the closer they are (a quadtree on each cube face). Keeps
## the tiles around a point of the planet built, on a worker thread, and a tile is only dropped once
## the tiles that replace it are in, so the ground never has holes. Tiles are placed in the world
## by the PlanetFrame.

var noise: PlanetNoise
var frame: PlanetFrame
var threaded := true
var tiles: Dictionary = {} # key -> PlanetTile (in the tree)

var _settings: PlanetSettings
var _wanted: Dictionary = {} # key -> [face, level, x, y]
var _pending: Dictionary = {} # key -> true while queued or being built
var _jobs: Array = []
var _done: Array = []
var _thread: Thread
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _stop := false
var _near := Vector3.ZERO # the point the tiles are chosen for (planet space)
var _tiles_per_frame := 2


func setup(planet_noise: PlanetNoise, planet_frame: PlanetFrame) -> void:
	noise = planet_noise
	frame = planet_frame
	_settings = noise.settings
	if threaded and DisplayServer.get_name() != "headless":
		_thread = Thread.new()
		_thread.start(_work)


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_stop = true
		_mutex.unlock()
		_semaphore.post()
		_thread.wait_to_finish()


## Chooses the tiles for a player at `at` (planet space) and queues what is missing.
func update(at: Vector3) -> void:
	_near = at
	_wanted.clear()
	for face in 6:
		_select(face, 0, 0, 0)
	var missing: Array = []
	for key: int in _wanted:
		var entry: Array = _wanted[key]
		if _pending.has(key):
			continue
		if not tiles.has(key) or (_collides(entry) and not (tiles[key] as PlanetTile).has_collider):
			missing.append(entry)
	missing.sort_custom(func(a: Array, b: Array) -> bool: return _distance(a) < _distance(b))
	_mutex.lock()
	for job: Array in _jobs: # the player moved: the old queue may be for places it has left
		_pending.erase(PlanetTile.key_of(job[0], job[1], job[2], job[3]))
	_jobs.clear()
	_mutex.unlock()
	if threaded and _thread != null:
		for entry: Array in missing.slice(0, 12):
			_pending[PlanetTile.key_of(entry[0], entry[1], entry[2], entry[3])] = true
			_mutex.lock()
			_jobs.append(entry)
			_mutex.unlock()
			_semaphore.post()
	_drop_stale()


## Builds everything wanted around `at` right now (labs and tests). `near_only`: just the tiles the
## player can stand on, the rest comes from the worker.
func build_all(at: Vector3, near_only := false) -> void:
	update(at)
	for key: int in _wanted:
		var entry: Array = _wanted[key]
		if near_only and not _collides(entry):
			continue
		if not tiles.has(key) or (_collides(entry) and not (tiles[key] as PlanetTile).has_collider):
			if tiles.has(key):
				(tiles[key] as PlanetTile).queue_free()
			_add(_make(entry))
	_drop_stale()


func _process(_delta: float) -> void:
	var added := 0
	while added < _tiles_per_frame:
		_mutex.lock()
		var tile: PlanetTile = _done.pop_front() if not _done.is_empty() else null
		_mutex.unlock()
		if tile == null:
			break
		var key := PlanetTile.key_of(tile.face, tile.level, tile.tile_x, tile.tile_y)
		_pending.erase(key)
		if not _wanted.has(key) or (tiles.has(key) and (tiles[key] as PlanetTile).has_collider):
			tile.free()
			continue
		if tiles.has(key): # the same tile again, now with a collider
			(tiles[key] as PlanetTile).queue_free()
		_add(tile)
		added += 1
	if added > 0:
		_drop_stale()


## Puts every tile where the frame says it is (after the frame moved).
func place_all() -> void:
	for tile: PlanetTile in tiles.values():
		tile.transform = frame.tile_transform(tile)


func _add(tile: PlanetTile) -> void:
	tile.transform = frame.tile_transform(tile)
	add_child(tile)
	tiles[PlanetTile.key_of(tile.face, tile.level, tile.tile_x, tile.tile_y)] = tile


func _make(entry: Array) -> PlanetTile:
	var level: int = entry[1]
	return PlanetTile.new().build(entry[0], level, entry[2], entry[3], noise, _collides(entry),
			_plants(entry))


## What grows on a tile: everything on the finest tiles near the player, only trees further out
## (and on the next size up), nothing on the far tiles.
func _plants(entry: Array) -> PlanetScatter.Detail:
	var level: int = entry[1]
	if level == _settings.max_level():
		if _distance(entry) < _settings.tile_max * 4.0:
			return PlanetScatter.Detail.ALL
		return PlanetScatter.Detail.TREES
	if level == _settings.max_level() - 1 and _distance(entry) < _settings.tile_max * 10.0:
		return PlanetScatter.Detail.TREES
	return PlanetScatter.Detail.NONE


## Only the finest tiles close to the player get a collider.
func _collides(entry: Array) -> bool:
	if entry[1] != _settings.max_level():
		return false
	return _distance(entry) < _settings.tile_max * _settings.collide_tiles * 2.0 + 60.0


## Splits a tile into four while the player is close compared to its size.
func _select(face: int, level: int, x: int, y: int) -> void:
	var entry: Array = [face, level, x, y]
	var size := _settings.radius * PI * 0.5 / float(1 << level)
	if level < _settings.max_level() and _distance(entry) < size * _settings.split_factor:
		for dy in 2:
			for dx in 2:
				_select(face, level + 1, x * 2 + dx, y * 2 + dy)
	else:
		_wanted[PlanetTile.key_of(face, level, x, y)] = entry


## Metres from the player to the middle of a tile (on the sea level sphere).
func _distance(entry: Array) -> float:
	var count := float(1 << int(entry[1]))
	var s := -1.0 + 2.0 * (float(entry[2]) + 0.5) / count
	var t := -1.0 + 2.0 * (float(entry[3]) + 0.5) / count
	return PlanetTile.direction(entry[0], s, t).distance_to(_near.normalized()) * _settings.radius


## Removes a tile once every wanted tile that overlaps it is built.
func _drop_stale() -> void:
	for key: int in tiles.keys():
		if _wanted.has(key):
			continue
		var tile: PlanetTile = tiles[key]
		if _covered(tile):
			tile.queue_free()
			tiles.erase(key)


func _covered(tile: PlanetTile) -> bool:
	for key: int in _wanted:
		var entry: Array = _wanted[key]
		if entry[0] != tile.face or not _overlap(tile, entry):
			continue
		if not tiles.has(key):
			return false
	return true


## True if the wanted tile `entry` and `tile` are the same patch, or one lies inside the other.
func _overlap(tile: PlanetTile, entry: Array) -> bool:
	var level: int = entry[1]
	if level >= tile.level:
		var shift := level - tile.level
		return (int(entry[2]) >> shift) == tile.tile_x and (int(entry[3]) >> shift) == tile.tile_y
	var up := tile.level - level
	return (tile.tile_x >> up) == int(entry[2]) and (tile.tile_y >> up) == int(entry[3])


func _work() -> void:
	while true:
		_semaphore.wait()
		_mutex.lock()
		var stop := _stop
		var job: Array = _jobs.pop_front() if not _jobs.is_empty() else []
		_mutex.unlock()
		if stop:
			return
		if job.is_empty():
			continue
		var tile := _make(job)
		_mutex.lock()
		_done.append(tile)
		_mutex.unlock()
