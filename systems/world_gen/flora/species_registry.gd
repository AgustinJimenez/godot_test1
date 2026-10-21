class_name SpeciesRegistry
extends RefCounted
## The species of one world and the meshes they have made so far. One registry per seed (found with
## for_settings, so the tile builders never pass it around); it is read from the tile worker thread
## and the main thread, so mesh building sits behind a lock and the species list is never changed.

static var _registries: Dictionary = {} # seed key -> SpeciesRegistry, newest last
static var _registries_lock := Mutex.new()

var world_seed := 0
var species: Array[PlantSpecies] = []
var _by_layer: Dictionary = {} # PlantSpecies.Layer -> Array[PlantSpecies]
var _meshes: Dictionary = {}
var impostors_expected := false ## true once PlanetImpostors is baking
var _impostors: Dictionary = {}
var _waiting: Dictionary = {}
var _lock := Mutex.new()


static func for_settings(settings: WorldSettings) -> SpeciesRegistry:
	var key := hash(Vector2i(settings.world_seed, settings.species_count))
	_registries_lock.lock()
	if not _registries.has(key):
		_registries[key] = SpeciesRegistry.new(settings.world_seed, settings.species_count)
		while _registries.size() > 2: # keep this world and the one before it (a seed roll rebuilds)
			_registries.erase(_registries.keys()[0])
	var registry: SpeciesRegistry = _registries[key]
	_registries_lock.unlock()
	return registry


func _init(seed_value: int, count: int) -> void:
	world_seed = seed_value
	species = SpeciesGenerator.generate(seed_value, count)
	for layer: int in PlantSpecies.Layer.values():
		_by_layer[layer] = [] as Array[PlantSpecies]
	for one in species:
		(_by_layer[one.layer()] as Array[PlantSpecies]).append(one)


func in_layer(layer: PlantSpecies.Layer) -> Array[PlantSpecies]:
	return _by_layer[layer]


func by_id(id: int) -> PlantSpecies:
	return species[id - 1]


## `lod` 1 is the lighter version of a tree (see TreeGrower); other plants have only one. A mesh is
## built outside the lock (several threads build different ones at once; two that want the same
## one both build it and the first to finish is kept).
func mesh(id: int, variant: int, detailed_wanted: bool, lod := 0) -> ArrayMesh:
	# trees and shrubs are few and near, and the finer mesh (leaf cards, strips of leaflets, smoother
	# branches) costs little more
	# than the light one: they use it from the middle ground detail up (`FloraMeshes.fine_trees`); the
	# many small plants wait
	# for the Fine ground detail
	var one := by_id(id)
	var detailed := detailed_wanted or (FloraMeshes.fine_trees
			and (one.is_tree() or one.form == PlantSpecies.Form.SHRUB))
	var key := id * 100 + variant + (100000 if detailed else 0) + lod * 1000000
	var found := _cached(key)
	if found != null:
		return found
	return _keep(key, PlantMeshes.build(by_id(id), variant, detailed, false, lod))


func far_mesh(id: int, variant: int) -> ArrayMesh:
	var key := -(id * 100 + variant)
	var found := _cached(key)
	if found != null:
		return found
	return _keep(key, PlantMeshes.build_far(by_id(id), variant))


func _cached(key: int) -> ArrayMesh:
	_lock.lock()
	var found: ArrayMesh = _meshes.get(key)
	_lock.unlock()
	return found


func _keep(key: int, built: ArrayMesh) -> ArrayMesh:
	_lock.lock()
	if _meshes.has(key):
		built = _meshes[key]
	else:
		_meshes[key] = built
	_lock.unlock()
	return built


## The impostor of a tree variant (PlanetImpostors bakes it): {"mesh": a quad as big as the picture,
## "material": the shader with the atlas}, or an empty dictionary until it is baked.
func impostor(id: int, variant: int) -> Dictionary:
	_lock.lock()
	var found: Dictionary = _impostors.get(id * 100 + variant, {})
	_lock.unlock()
	return found


func set_impostor(id: int, variant: int, baked: Dictionary) -> void:
	_lock.lock()
	_impostors[id * 100 + variant] = baked
	_lock.unlock()


## Tile instances showing the lighter mesh of a tree variant until its impostor is baked
## (PlanetImpostors swaps them): {"instance": id, "buffer": the placements}.
func wait_for_impostor(id: int, variant: int, instance_id: int, buffer: PackedFloat32Array) -> void:
	if not impostors_expected:
		return
	_lock.lock()
	var key := id * 100 + variant
	if not _waiting.has(key):
		_waiting[key] = []
	(_waiting[key] as Array).append({"instance": instance_id, "buffer": buffer})
	_lock.unlock()


func take_waiting(id: int, variant: int) -> Array:
	_lock.lock()
	var found: Array = _waiting.get(id * 100 + variant, [])
	_waiting.erase(id * 100 + variant)
	_lock.unlock()
	return found
