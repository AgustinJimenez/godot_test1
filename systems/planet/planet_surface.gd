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
var _native: Object ## PlanetSurfaceNative (the tile selection and the order), or null
var _faces := PackedVector3Array()
var _wanted: Dictionary = {} # key -> [face, level, x, y]
var _pending: Dictionary = {} # key -> true while queued or being built
var _jobs: Array = []
var _done: Array = []
var _thread: Thread # the first ground worker (is_threaded)
var paused := false ## true while the map is open: workers keep their jobs (the charts get the CPU)
var _workers: Array[Thread] = [] # the ground is made by several threads, the plants by one
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _stop := false
var _near := Vector3.ZERO # the point the tiles are chosen for (planet space)
var _height := 0.0 # m the player is over the ground there
## m: the horizon trees (sparse, cheap) are planted out to here
const PLANT_RANGE := 6000.0
const BURST_TILES := 24

var _tiles_per_frame := 2
var burst := false ## true while the player waits: many tiles a frame, hitches do not matter
var _inline: Array = [] # without a worker thread (headless): tiles built here, a few a frame
# plants are a second job, after the ground and the water, on a thread of their own
var _plant_jobs: Array = [] # [tile, detail]
var _plant_done: Array = [] # [tile, holder, detail]
var _plant_pending: Dictionary = {} # tile instance id -> true while queued or being grown
var _retired: Array = [] # tiles taken out of the world, freed once no plant job holds them
var _plant_workers: Array[Thread] = []
var _plant_semaphore := Semaphore.new()
var _plant_inline: Array = []


func setup(planet_noise: PlanetNoise, planet_frame: PlanetFrame) -> void:
	noise = planet_noise
	frame = planet_frame
	_settings = noise.settings
	if ClassDB.class_exists(&"PlanetSurfaceNative") and not OS.has_environment("PLANET_NO_NATIVE"):
		_native = ClassDB.instantiate(&"PlanetSurfaceNative")
		for axes: Array in PlanetTile.FACES:
			_faces.append_array(PackedVector3Array(axes))
	if threaded and DisplayServer.get_name() != "headless":
		var count := clampi(OS.get_processor_count() - 2, 2, 4)
		for index in count:
			var worker := Thread.new()
			worker.start(_work)
			_workers.append(worker)
		_thread = _workers[0]
		for index in clampi(OS.get_processor_count() / 3, 2, 3):
			var planter := Thread.new()
			planter.start(_work_plants)
			_plant_workers.append(planter)


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_stop = true
		_mutex.unlock()
		for worker in _workers:
			_semaphore.post()
		for planter in _plant_workers:
			_plant_semaphore.post()
		for worker in _workers:
			worker.wait_to_finish()
		for planter in _plant_workers:
			planter.wait_to_finish()


## Chooses the tiles for a player at `at` (planet space) and queues what is missing.
func update(at: Vector3) -> void:
	_near = at
	# how high the player is over the ground under them: detail follows the distance in space, so
	# up in the air the ground is coarse and nothing grows (the trees below are far away)
	var here := at.normalized()
	_height = maxf(at.length() - _settings.radius - noise.height(here.x, here.y, here.z), 0.0)
	_wanted.clear()
	if _native != null:
		_select_native(at)
	else:
		for face in 6:
			_select(face, 0, 0, 0)
	var missing: Array = []
	var sorts := PackedFloat64Array()
	for key: int in _wanted:
		var entry: Array = _wanted[key]
		if _pending.has(key):
			continue
		if not tiles.has(key) or (_collides(entry) and not (tiles[key] as PlanetTile).has_collider):
			missing.append(entry)
			if _native != null:
				sorts.append(entry[7])
	if _native != null:
		var ordered: Array = []
		for index: int in _native.call(&"order", sorts):
			ordered.append(missing[index])
		missing = ordered
	else:
		missing.sort_custom(_before)
	_mutex.lock()
	for job: Array in _jobs: # the player moved: the old queue may be for places it has left
		_pending.erase(PlanetTile.key_of(job[0], job[1], job[2], job[3]))
	_jobs.clear()
	_mutex.unlock()
	var batch := 600 if burst else 48 # (the player waits: every tile that is missing, nearest first)
	if threaded and _thread != null:
		for entry: Array in missing.slice(0, batch):
			_pending[PlanetTile.key_of(entry[0], entry[1], entry[2], entry[3])] = true
			_mutex.lock()
			_jobs.append(entry)
			_mutex.unlock()
			_semaphore.post()
	else:
		_inline = missing.slice(0, 12)
	_queue_plants()
	_drop_stale()


## The tiles wanted for a player at `at`, chosen natively: each entry is [face, level, x, y,
## distance, collides, plants,
## sort key] (the extra numbers are what `_distance`, `_collides` and `_plants` would work out).
func _select_native(at: Vector3) -> void:
	var picked: Dictionary = _native.call(&"select", {
		"near": at, "height": _height, "radius": _settings.radius, "max_level": _settings.max_level(),
		"split_factor": _settings.split_factor, "tile_max": _settings.tile_max,
		"collide_tiles": _settings.collide_tiles, "plants_on": _settings.plants_on,
		"coarse_level": coarse_level(), "faces": _faces})
	var entries: PackedInt32Array = picked["entries"]
	var distance: PackedFloat64Array = picked["distance"]
	var collides: PackedByteArray = picked["collides"]
	var plants: PackedByteArray = picked["plants"]
	var sort: PackedFloat64Array = picked["sort"]
	for index in distance.size():
		var at4 := index * 4
		_wanted[PlanetTile.key_of(entries[at4], entries[at4 + 1], entries[at4 + 2], entries[at4 + 3])] = [
				entries[at4], entries[at4 + 1], entries[at4 + 2], entries[at4 + 3], distance[index],
				collides[index] == 1, plants[index], sort[index]]


## The order tiles are made in: the ground the player stands on first, then the planet's whole
## coarse shape (so it is there to see from the start, the big shapes of the crust), coarsest first,
## then the rest nearest first.
func _before(a: Array, b: Array) -> bool:
	var class_a := _urgency(a)
	var class_b := _urgency(b)
	if class_a != class_b:
		return class_a < class_b
	if class_a == 1 and a[1] != b[1]:
		return a[1] < b[1]
	return _distance(a) < _distance(b)


func _urgency(entry: Array) -> int:
	if _collides(entry):
		return 0
	return 1 if int(entry[1]) <= coarse_level() else 2


## The tile levels up to this make the planet's coarse shape (seen from far away).
func coarse_level() -> int:
	return clampi(_settings.max_level() - 3, 2, 4)


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
				_retire(tiles[key])
			_add(_make(entry))
	_drop_stale()


func _process(_delta: float) -> void:
	var added := 0
	var limit := BURST_TILES if burst else _tiles_per_frame
	while added < limit and not _inline.is_empty():
		var entry: Array = _inline.pop_front()
		var key := PlanetTile.key_of(entry[0], entry[1], entry[2], entry[3])
		if _wanted.has(key):
			if tiles.has(key):
				_retire(tiles[key])
			_add(_make(entry))
			added += 1
	while added < limit:
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
			_retire(tiles[key])
		_add(tile)
		added += 1
	_adopt_plants()
	_free_retired()
	if added > 0:
		_drop_stale()


## Asks for the plants of the built tiles that should have more than they have (nearest first).
func _queue_plants() -> void:
	var wishes: Array = []
	for key: int in _wanted:
		if not tiles.has(key):
			continue
		var tile: PlanetTile = tiles[key]
		if _plant_pending.has(tile.get_instance_id()):
			continue
		var entry: Array = _wanted[key]
		var wanted := _plants(entry)
		if wanted == PlanetScatter.Detail.NONE or wanted <= tile.plant_detail:
			continue
		if not tile.plant_grid.is_empty():
			wishes.append([tile, wanted, _distance(entry)])
	wishes.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	_mutex.lock()
	for job: Array in _plant_jobs: # the player moved: the old queue may be for places it has left
		_plant_pending.erase((job[0] as PlanetTile).get_instance_id())
	_plant_jobs.clear()
	_mutex.unlock()
	if not _plant_workers.is_empty():
		for wish: Array in wishes.slice(0, 24):
			var tile: PlanetTile = wish[0]
			_plant_pending[tile.get_instance_id()] = true
			_mutex.lock()
			_plant_jobs.append([tile, wish[1]])
			_mutex.unlock()
			_plant_semaphore.post()
	else:
		_plant_inline = wishes.slice(0, 4)


## Puts the grown plants into their tiles (a few a frame).
func _adopt_plants() -> void:
	var adopted := 0
	while adopted < 4:
		var finished: Array = []
		if not _plant_inline.is_empty():
			var wish: Array = _plant_inline.pop_front()
			if not is_instance_valid(wish[0]): # the tile went away since the wish was made
				continue
			var wished: PlanetTile = wish[0]
			if tiles.get(wished.tile_key) == wished:
				finished = [wished, wished.grow_plants(wish[1]), wish[1]]
			else:
				continue
		else:
			_mutex.lock()
			if not _plant_done.is_empty():
				finished = _plant_done.pop_front()
			_mutex.unlock()
		if finished.is_empty():
			return
		var holder: Node3D = finished[1]
		if not is_instance_valid(finished[0]): # the tile went away while its plants were grown
			holder.free()
			continue
		var tile: PlanetTile = finished[0]
		_plant_pending.erase(tile.get_instance_id())
		if tiles.get(tile.tile_key) != tile or not tile.is_inside_tree():
			holder.free()
			continue
		if tile.plant_holder != null:
			tile.plant_holder.queue_free()
		tile.add_child(holder)
		tile.plant_holder = holder
		tile.plant_detail = finished[2]
		adopted += 1


## 0..1: how much of what the player needs close by is there: every tile within `ground_metres`
## built (with its collider where it needs one), and the plants of every tile within `plant_metres`.
func progress(ground_metres: float, plant_metres: float) -> float:
	var need := 0
	var have := 0
	for key: int in _wanted:
		var entry: Array = _wanted[key]
		var distance := _distance(entry)
		var built: PlanetTile = tiles.get(key)
		if distance < ground_metres:
			need += 1
			if built != null and (not _collides(entry) or built.has_collider):
				have += 1
		if distance >= ground_metres and int(entry[1]) <= coarse_level():
			need += 1 # the planet's coarse shape is part of arriving
			if built != null:
				have += 1
		if distance < plant_metres and _plants(entry) != PlanetScatter.Detail.NONE:
			need += 1
			if built != null and (built.plant_grid.is_empty()
					or built.plant_detail >= _plants(entry)):
				have += 1
	return 1.0 if need == 0 else float(have) / float(need)


func is_threaded() -> bool:
	return _thread != null


## Puts every tile where the frame says it is (after the frame moved).
func place_all() -> void:
	for tile: PlanetTile in tiles.values():
		tile.transform = frame.tile_transform(tile)


## Takes a tile out of the world. It is freed later, once no worker is still planting it.
func _retire(tile: PlanetTile) -> void:
	if tiles.get(tile.tile_key) == tile:
		tiles.erase(tile.tile_key)
	if tile.get_parent() != null:
		tile.get_parent().remove_child(tile)
	_retired.append(tile)


func _free_retired() -> void:
	for index in range(_retired.size() - 1, -1, -1):
		var tile: PlanetTile = _retired[index]
		if not _plant_pending.has(tile.get_instance_id()):
			tile.free()
			_retired.remove_at(index)


func _add(tile: PlanetTile) -> void:
	tile.transform = frame.tile_transform(tile)
	add_child(tile)
	tiles[PlanetTile.key_of(tile.face, tile.level, tile.tile_x, tile.tile_y)] = tile


func _make(entry: Array) -> PlanetTile:
	var level: int = entry[1]
	return PlanetTile.new().build(entry[0], level, entry[2], entry[3], noise, _collides(entry))


## What grows on a tile: everything on the finest tiles near the player, only trees further out
## (and on the next size up), nothing on the far tiles.
func _plants(entry: Array) -> PlanetScatter.Detail:
	if entry.size() > 6:
		return entry[6]
	var detail := PlanetScatter.Detail.NONE
	if _settings.plants_on:
		detail = _plants_by_distance(entry)
	return detail


func _plants_by_distance(entry: Array) -> PlanetScatter.Detail:
	var level: int = entry[1]
	if level == _settings.max_level():
		if _distance(entry) < _settings.tile_max * 2.0:
			return PlanetScatter.Detail.ALL
		return PlanetScatter.Detail.TREES
	if level == _settings.max_level() - 1 and _distance(entry) < _settings.tile_max * 10.0:
		return PlanetScatter.Detail.TREES
	# the horizon: cheap sparse trees on the next few sizes of tile, out to a few kilometres
	var far_level := level >= _settings.max_level() - 4 and level < _settings.max_level() - 1
	if far_level and _distance(entry) < PLANT_RANGE:
		return PlanetScatter.Detail.FAR
	return PlanetScatter.Detail.NONE


## Only the finest tiles close to the player get a collider.
func _collides(entry: Array) -> bool:
	if entry.size() > 5:
		return entry[5]
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
	if entry.size() > 4:
		return entry[4]
	var count := float(1 << int(entry[1]))
	var s := -1.0 + 2.0 * (float(entry[2]) + 0.5) / count
	var t := -1.0 + 2.0 * (float(entry[3]) + 0.5) / count
	var centre := PlanetTile.direction(entry[0], s, t)
	var along := centre.distance_to(_near.normalized()) * _settings.radius
	return sqrt(along * along + _height * _height)


## Removes a tile once every wanted tile that overlaps it is built.
func _drop_stale() -> void:
	for key: int in tiles.keys():
		if _wanted.has(key):
			continue
		var tile: PlanetTile = tiles[key]
		if _covered(tile):
			_retire(tile)


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


## A worker that has woken for a job holds it back while the map is open (until it is closed or the
## game ends).
func _wait_while_paused() -> void:
	while paused and not _stop:
		OS.delay_msec(30)


func _work() -> void:
	while true:
		_semaphore.wait()
		_wait_while_paused()
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


func _work_plants() -> void:
	while true:
		_plant_semaphore.wait()
		_wait_while_paused()
		_mutex.lock()
		var stop := _stop
		var job: Array = _plant_jobs.pop_front() if not _plant_jobs.is_empty() else []
		_mutex.unlock()
		if stop:
			return
		if job.is_empty():
			continue
		var tile: PlanetTile = job[0]
		var holder := tile.grow_plants(job[1])
		_mutex.lock()
		_plant_done.append([tile, holder, job[1]])
		_mutex.unlock()
