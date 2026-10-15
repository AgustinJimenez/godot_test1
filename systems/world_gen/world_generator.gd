class_name WorldGenerator
extends Node3D
## The procedural world. Keeps terrain tiles built around a target: fine tiles (with plants and
## colliders) close by, coarse scenery tiles out to the horizon. Builds a few per frame, upgrades a
## far tile to a fine one when the target comes near, and lets very far tiles go. Everything comes
## from `settings`, so the same seed always makes the same land.

@export var settings: WorldSettings
@export var follow: NodePath ## the node the world is built around (the player)
@export var chunks_per_frame := 1

var noise: TerrainNoise
var chunks: Dictionary = {} # Vector2i -> TerrainChunk
var threaded := true ## build tiles on a worker thread (no hitches while walking)

var _follow_node: Node3D
var _thread: Thread
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _jobs: Array = [] # [coord, near] waiting for the worker
var _done: Array = [] # finished TerrainChunk nodes waiting for the main thread
var _pending: Dictionary = {} # coord -> true while queued or being built
var _stop := false
var _generation := 0 # bumps when the world is thrown away, so unfinished old tiles are dropped


func _ready() -> void:
	if settings == null:
		settings = WorldSettings.new()
	noise = TerrainNoise.new(settings)
	if not follow.is_empty():
		_follow_node = get_node_or_null(follow) as Node3D
	if threaded and DisplayServer.get_name() != "headless":
		_thread = Thread.new()
		_thread.start(_work)


## Where the world is built around (the follow target, or the origin).
func set_target(target: Node3D) -> void:
	_follow_node = target


func _process(_delta: float) -> void:
	var center := _target_position()
	if _thread != null:
		_queue_jobs(center)
		_collect(center)
	else:
		var built := 0
		for coord in _wanted(center):
			if not _needs_build(coord, center):
				continue
			_add_chunk(coord, center)
			built += 1
			if built >= chunks_per_frame:
				break
	_drop_far(center)


## Builds the fine tiles around `center` (and, with `with_far`, the horizon too) now: labs and
## tests, no waiting for the frames.
func build_around(center: Vector3, with_far := true) -> void:
	if noise == null:
		_ready()
	for coord in _wanted(center):
		if _needs_build(coord, center) and (with_far or _is_near(coord, center)):
			_add_chunk(coord, center)


func ground_height(x: float, z: float) -> float:
	return noise.height(x, z)


func chunk_of(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / settings.chunk_size),
			floori(world_position.z / settings.chunk_size))


func _target_position() -> Vector3:
	return _follow_node.global_position if _follow_node != null else Vector3.ZERO


func _is_near(coord: Vector2i, center: Vector3) -> bool:
	var radius := settings.view_chunks
	return (coord - chunk_of(center)).length_squared() <= radius * radius + 1


## A tile is missing, or is a far tile that has come within the fine radius.
func _needs_build(coord: Vector2i, center: Vector3) -> bool:
	if not chunks.has(coord):
		return true
	return (chunks[coord] as TerrainChunk).far and _is_near(coord, center)


## The chunks that should exist out to the horizon, nearest first.
func _wanted(center: Vector3) -> Array[Vector2i]:
	var middle := chunk_of(center)
	var wanted: Array[Vector2i] = []
	var radius := settings.far_chunks
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz <= radius * radius + 1:
				wanted.append(middle + Vector2i(dx, dz))
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - middle).length_squared() < (b - middle).length_squared())
	return wanted


func _add_chunk(coord: Vector2i, center: Vector3) -> void:
	if chunks.has(coord):
		(chunks[coord] as TerrainChunk).queue_free()
	var chunk := TerrainChunk.new().build(coord, noise, _is_near(coord, center))
	add_child(chunk)
	chunks[coord] = chunk


func _drop_far(center: Vector3) -> void:
	var middle := chunk_of(center)
	var limit := settings.far_chunks + 2
	for coord: Vector2i in chunks.keys():
		if absi(coord.x - middle.x) > limit or absi(coord.y - middle.y) > limit:
			(chunks[coord] as TerrainChunk).queue_free()
			chunks.erase(coord)


## Removes every tile (the world is rebuilt around the target by `_process`).
func clear() -> void:
	for chunk: TerrainChunk in chunks.values():
		chunk.queue_free()
	chunks.clear()
	_generation += 1
	_pending.clear()
	_mutex.lock()
	_jobs.clear()
	_mutex.unlock()


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_stop = true
		_mutex.unlock()
		_semaphore.post()
		_thread.wait_to_finish()


## Hands the nearest missing tiles to the worker (a few ahead, never a long line of stale ones).
func _queue_jobs(center: Vector3) -> void:
	_mutex.lock()
	var queued := _jobs.size()
	_mutex.unlock()
	for coord in _wanted(center):
		if queued >= 6:
			break
		if _pending.has(coord) or not _needs_build(coord, center):
			continue
		_pending[coord] = true
		_mutex.lock()
		_jobs.append([coord, _is_near(coord, center), _generation])
		_mutex.unlock()
		_semaphore.post()
		queued += 1


## Adds the tiles the worker finished (a few a frame), unless they went out of range meanwhile.
func _collect(center: Vector3) -> void:
	var added := 0
	while added < chunks_per_frame:
		_mutex.lock()
		var chunk: TerrainChunk = _done.pop_front() if not _done.is_empty() else null
		_mutex.unlock()
		if chunk == null:
			return
		_pending.erase(chunk.coord)
		var middle := chunk_of(center)
		if (chunk.get_meta(&"generation") != _generation
				or (chunk.coord - middle).length_squared() > settings.far_chunks * settings.far_chunks + 4):
			chunk.free()
			continue
		if chunks.has(chunk.coord):
			(chunks[chunk.coord] as TerrainChunk).queue_free()
		add_child(chunk)
		chunks[chunk.coord] = chunk
		added += 1


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
		var chunk := TerrainChunk.new().build(job[0] as Vector2i, noise, job[1] as bool)
		chunk.set_meta(&"generation", job[2])
		_mutex.lock()
		_done.append(chunk)
		_mutex.unlock()
