class_name PlanetSwayTree
extends MeshInstance3D
## One tree whose branches bend and spring back: a tree close to the walker is taken out of its
## MultiMesh and drawn by one of
## these instead. The mesh is the same (every vertex knows its branch, CUSTOM0), the material is the
## plant shader with
## `bendable` on, and the turn of each branch comes from a small float texture the native springs
## (PlantSwayNative) fill in.

var _sway := PlantSwayNative.new()
var _table := PackedFloat32Array()
var _state := PackedFloat32Array()
var _image: Image
var _texture: ImageTexture
var _feet := PackedByteArray()
var _awake := false
var _jitter := 0.0 ## the most any branch turned in the last step (radians)


## Take the branches of `tree_mesh` (its "branches" meta) and draw them with `material` (the plant
## material, copied) tinted by `tint`.
func setup(tree_mesh: ArrayMesh, material: ShaderMaterial, tint: Color) -> bool:
	_table = tree_mesh.get_meta(&"branches", PackedFloat32Array())
	if _table.size() < 20:
		return false
	mesh = tree_mesh
	var count := _table.size() / 10
	_feet = _sway.feet(_table).to_byte_array()
	_state = PackedFloat32Array()
	_image = Image.create_from_data(count, 2, false, Image.FORMAT_RGBAF,
			_feet + _sway.turns(_zeros(count)).to_byte_array())
	_texture = ImageTexture.create_from_image(_image)
	var own := material.duplicate() as ShaderMaterial
	own.set_shader_parameter(&"bendable", true)
	own.set_shader_parameter(&"bend_data", _texture)
	own.set_shader_parameter(&"live_tint", tint)
	material_override = own
	_awake = false
	return true


## Everything has come to rest (no step needed until the body is near again).
func is_at_rest() -> bool:
	return not _awake


## A step of `delta` seconds. `body_local`: the walker's capsule in this tree's own space (a, b,
## radius: 7 floats; empty: nobody
## near, the branches only settle).
func step(body_local: PackedFloat32Array, delta: float) -> void:
	if not _awake and body_local.is_empty():
		return
	var made := _sway.step(_table, _state, body_local, delta)
	var before := _state
	_state = made["state"]
	_jitter = 0.0
	if before.size() == _state.size():
		for at in _state.size() / 6:
			for axis in 3:
				var change := absf(_state[at * 6 + axis] - before[at * 6 + axis])
				_jitter = maxf(_jitter, change)
	_awake = made["awake"]
	_image.set_data(_table.size() / 10, 2, false, Image.FORMAT_RGBAF,
			_feet + _sway.turns(_state).to_byte_array())
	_texture.update(_image)


## The most any branch is turned now (radians): for the checks.
func most_turned() -> float:
	var worst := 0.0
	for id in _state.size() / 6:
		worst = maxf(worst, Vector3(_state[id * 6], _state[id * 6 + 1], _state[id * 6 + 2]).length())
	return worst


## How much the most moving branch turned in the last step (radians): for the checks.
func jitter() -> float:
	return _jitter


## All the branches' turns added up (radians): for the checks.
func turn_sum() -> float:
	var total := 0.0
	for id in _state.size() / 6:
		total += Vector3(_state[id * 6], _state[id * 6 + 1], _state[id * 6 + 2]).length()
	return total


static func _zeros(count: int) -> PackedFloat32Array:
	var zeros := PackedFloat32Array()
	zeros.resize(count * 6)
	return zeros
