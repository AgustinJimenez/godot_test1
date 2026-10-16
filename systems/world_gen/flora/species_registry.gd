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


## `lod` 1 is the lighter version of a tree (see TreeGrower); other plants have only one.
func mesh(id: int, variant: int, detailed: bool, lod := 0) -> ArrayMesh:
	var key := id * 100 + variant + (100000 if detailed else 0) + lod * 1000000
	_lock.lock()
	if not _meshes.has(key):
		_meshes[key] = PlantMeshes.build(by_id(id), variant, detailed, false, lod)
	var result: ArrayMesh = _meshes[key]
	_lock.unlock()
	return result


func far_mesh(id: int, variant: int) -> ArrayMesh:
	var key := -(id * 100 + variant)
	_lock.lock()
	if not _meshes.has(key):
		_meshes[key] = PlantMeshes.build_far(by_id(id), variant)
	var result: ArrayMesh = _meshes[key]
	_lock.unlock()
	return result
