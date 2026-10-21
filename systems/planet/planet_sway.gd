class_name PlanetSway
extends Node
## The trees and shrubs round the walker bend for real. The plants of a tile are drawn in batches
## (one MultiMesh for a kind),
## which cannot hold a pose for each tree; so every tree within ENTER metres of the walker is taken
## out of its batch (its
## instance is shrunk to nothing) and drawn by a PlanetSwayTree of its own, whose branches the
## native springs turn when the walker's
## body touches them and let go again after. Beyond LEAVE metres, and once it has come to rest, it
## goes back into the batch.
## The tiles keep what is needed: `sway_sets` on a tile's plant holder, [MultiMeshInstance3D,
## buffer] for each kind that can bend.

const ENTER := 8.0 ## m: closer than this a tree is taken out of its batch
const LEAVE := 11.0 ## m: farther than this (and at rest) it goes back
const TOUCH := 6.0 ## m: the body is given to the trees within this (the others only settle)
## the same for grass, ferns, flowers and low shrubs: there are very many, and they are touched only
## close
const ENTER_SMALL := 2.4
const LEAVE_SMALL := 3.4
const TOUCH_SMALL := 1.8
const LOOK_EVERY := 0.25 ## s between looks for trees to take or give back
const MAX_LIVE := 24
const MAX_SMALL := 120
## and the tufts of the turf of the ground: hundreds a few metres round, only the ones at the feet
## are pushed
const ENTER_TURF := 1.7
const LEAVE_TURF := 2.6
const TOUCH_TURF := 1.4
const MAX_TURF := 90
const BIG := 0 ## the class of a batch: trees and tall shrubs,
const SMALL := 1 ## grass, ferns, flowers and low shrubs,
const TURF := 2 ## the tufts of the turf
const BODY_HEIGHT := 1.8 ## m, the walker's body: an upright capsule from the feet
const BODY_RADIUS := 0.4

var planet: PlanetWorld
var player: Player

var _native := PlantSwayNative.new()
var _live: Array[Dictionary] = [] # {tree, instance, index, original, holder}
var _since := 0.0
var _keys := {} # the live ones by batch and index, to ask quickly
var _turf: PlanetTurf
var _counts := [0, 0, 0] # how many of the live ones are of each class


func _ready() -> void:
	process_physics_priority = 101


func _physics_process(delta: float) -> void:
	if player == null or planet == null:
		return
	var here := player.global_position
	_since += delta
	if _since >= LOOK_EVERY:
		_since = 0.0
		_give_back(here)
		_take(here)
		if OS.has_environment("PLANET_TIMING"):
			var sets := 0
			for tile: PlanetTile in planet.surface.tiles.values():
				if tile.plant_holder != null and tile.plant_holder.has_meta(&"sway_sets"):
					sets += (tile.plant_holder.get_meta(&"sway_sets") as Array).size()
			print("PLANET_TIMING sway live=%d kinds=%d" % [_live.size(), sets])
	for entry in _live:
		var tree_value: Variant = entry["tree"] # (a tree of a tile that has gone is a freed object)
		if not is_instance_valid(tree_value) or not (tree_value as Node3D).is_inside_tree():
			continue # (_give_back lets it go)
		var tree: PlanetSwayTree = tree_value
		var body := PackedFloat32Array()
		if tree.global_position.distance_to(here) < [TOUCH, TOUCH_SMALL, TOUCH_TURF][entry["klass"]]:
			body = _body_in(tree, here)
		tree.step(body, delta)


## The walker's body as a capsule in `tree`'s own space: from the feet up, its radius made smaller
## or larger by the tree's scale.
func _body_in(tree: PlanetSwayTree, feet: Vector3) -> PackedFloat32Array:
	var inverse := tree.global_transform.affine_inverse()
	var a := inverse * feet
	var b := inverse * (feet + player.global_basis.y * BODY_HEIGHT)
	var scale := maxf(tree.global_basis.get_scale().x, 0.01)
	return PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, BODY_RADIUS / scale])


## Trees of the tiles round the walker that are within ENTER metres go live.
func _take(here: Vector3) -> void:
	for tile: PlanetTile in planet.surface.tiles.values():
		var holder := tile.plant_holder
		if holder == null or not holder.has_meta(&"sway_sets"):
			continue
		var local := holder.to_local(here)
		var half := tile.size * 0.5 + ENTER
		if absf(local.x) > half or absf(local.z) > half:
			continue # (the tile's own space is centred on it)
		for kind: Array in holder.get_meta(&"sway_sets"):
			_take_kind(holder, kind, local)
	# the tufts of turf round the walker too (PlanetTurf keeps its chunks)
	if _turf == null:
		for node in planet.get_children():
			if node is PlanetTurf:
				_turf = node
	if _turf != null:
		for entry: Array in _turf.chunk_sets():
			_take_kind(entry[0], entry[1], (entry[0] as Node3D).to_local(here))


## The instances of one batch `kind` ([MultiMeshInstance3D, buffer, class]) of `holder` near `local`
## go live.
func _take_kind(holder: Node3D, kind: Array, local: Vector3) -> void:
	var instance_value: Variant = kind[0]
	if not is_instance_valid(instance_value):
		return
	var instance: MultiMeshInstance3D = instance_value
	if instance.multimesh == null:
		return
	var klass := int(kind[2]) # (the plants' batches say only true for the small ones)
	for index in _native.within(kind[1], local.x, local.z, [ENTER, ENTER_SMALL, ENTER_TURF][klass]):
		if _counts[klass] >= [MAX_LIVE, MAX_SMALL, MAX_TURF][klass]:
			break
		if not _is_live(instance, index):
			_go_live(holder, instance, kind[1], index, klass)


func _is_live(instance: MultiMeshInstance3D, index: int) -> bool:
	return _keys.has(_key_of(instance, index))


static func _key_of(instance: MultiMeshInstance3D, index: int) -> int:
	return instance.get_instance_id() * 65536 + index


func _go_live(holder: Node3D, instance: MultiMeshInstance3D, buffer: PackedFloat32Array, index: int,
		klass: int) -> void:
	var multi := instance.multimesh
	var at := index * 16 # (the tile's own buffer: the renderer need not keep the instances)
	var original := Transform3D(Basis(
			Vector3(buffer[at], buffer[at + 4], buffer[at + 8]),
			Vector3(buffer[at + 1], buffer[at + 5], buffer[at + 9]),
			Vector3(buffer[at + 2], buffer[at + 6], buffer[at + 10])),
			Vector3(buffer[at + 3], buffer[at + 7], buffer[at + 11]))
	var tree := PlanetSwayTree.new()
	if not tree.setup(multi.mesh as ArrayMesh, instance.material_override as ShaderMaterial,
			Color(buffer[at + 12], buffer[at + 13], buffer[at + 14], buffer[at + 15])):
		tree.free()
		return
	tree.transform = original
	tree.cast_shadow = instance.cast_shadow
	holder.add_child(tree)
	multi.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), original.origin))
	_live.append({"tree": tree, "instance": instance, "index": index, "original": original,
			"klass": klass,
			"key": _key_of(instance, index)})
	_counts[klass] += 1
	_keys[_key_of(instance, index)] = true # (see _is_live)


## Trees the walker has left, once their branches have settled, go back into their batch.
func _give_back(here: Vector3) -> void:
	var at := _live.size() - 1
	while at >= 0:
		var entry := _live[at]
		var tree_value: Variant = entry["tree"]
		var instance_value: Variant = entry["instance"]
		var gone := (not is_instance_valid(instance_value) or not is_instance_valid(tree_value)
				or not (tree_value as Node3D).is_inside_tree())
		var tree: PlanetSwayTree = null if gone else tree_value
		var instance: MultiMeshInstance3D = null if gone else instance_value
		var leave: float = [LEAVE, LEAVE_SMALL, LEAVE_TURF][entry["klass"]]
		if gone or (tree.global_position.distance_to(here) > leave and tree.is_at_rest()):
			if not gone:
				instance.multimesh.set_instance_transform(entry["index"], entry["original"])
			if is_instance_valid(tree_value):
				(tree_value as Node).queue_free()
			_counts[entry["klass"]] -= 1
			_keys.erase(entry["key"])
			_live.remove_at(at)
		at -= 1


## How many trees are drawn live now, and the most any branch of them is turned (radians): for the
## checks.
func live_count() -> int:
	return _live.size()


func most_turned() -> float:
	var worst := 0.0
	for entry in _live:
		if is_instance_valid(entry["tree"]):
			worst = maxf(worst, (entry["tree"] as PlanetSwayTree).most_turned())
	return worst


## The most any live branch turned in the last step (radians).
func jitter() -> float:
	var worst := 0.0
	for entry in _live:
		if is_instance_valid(entry["tree"]):
			worst = maxf(worst, (entry["tree"] as PlanetSwayTree).jitter())
	return worst


## The turns of all the live branches added up (radians): it stops changing when everything is at
## rest.
func pose_sum() -> float:
	var total := 0.0
	for entry in _live:
		if is_instance_valid(entry["tree"]):
			total += (entry["tree"] as PlanetSwayTree).turn_sum()
	return total


func _exit_tree() -> void:
	for entry in _live:
		if is_instance_valid(entry["instance"]) and is_instance_valid(entry["tree"]):
			(entry["instance"] as MultiMeshInstance3D).multimesh.set_instance_transform(entry["index"],
					entry["original"])
	_live.clear()
