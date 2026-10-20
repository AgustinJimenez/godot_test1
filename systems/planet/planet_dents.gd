class_name PlanetDents
extends RefCounted
## The footprints that dent the sand (task 078, planet_dents.gdshaderinc): a list of stamps in
## planet space (so they stay put when the world turns under the player), of which the nearest are
## put in a small float texture the ground shader reads, with the clock they were made at (the
## shader works out the age). Nothing is drawn here and the ground does not change.

const SHOWN := 32 ## how many the shader gets (the nearest to the camera)
const KEPT := 240 ## how many are remembered (the oldest go first)
const REFRESH := 0.25 ## s between two choices of the nearest stamps

var life := 240.0 ## s, when a print has gone
var clock := 0.0 ## s since the start; the stamps are made at this time
var _stamps: Array[Dictionary] = [] # {at (planet, doubles), forward, up, side, born}
var _image := Image.create(SHOWN, 3, false, Image.FORMAT_RGBAF)
var _texture := ImageTexture.create_from_image(_image)
var _since := REFRESH
var _material: ShaderMaterial


func _init(material: ShaderMaterial) -> void:
	_material = material
	_material.set_shader_parameter(&"dent_stamps", _texture)
	_material.set_shader_parameter(&"dent_life", life)
	_material.set_shader_parameter(&"dent_count", 0)


## One footprint at the planet position `at`, its toe along `forward`, the ground's up `up` (both
## in planet axes); `side` is +1 for the right foot and -1 for the left. `age` makes it older (the
## lab).
func add(at: PackedFloat64Array, forward: Vector3, up: Vector3, side: float, age := 0.0) -> void:
	if _stamps.size() >= KEPT:
		_stamps.pop_front()
	_stamps.append({"at": at, "forward": forward.normalized(), "up": up.normalized(), "side": side,
			"born": clock - age})
	_since = REFRESH # (choose again at once)


func clear() -> void:
	_stamps.clear()
	_material.set_shader_parameter(&"dent_count", 0)


## Every frame: the clock, the old ones dropped, and now and then the nearest stamps to `near`
## (a planet position) written to the texture.
func update(delta: float, near: Vector3) -> void:
	clock += delta
	_material.set_shader_parameter(&"dent_now", clock)
	_since += delta
	if _since < REFRESH:
		return
	_since = 0.0
	for index in range(_stamps.size() - 1, -1, -1):
		if clock - float(_stamps[index]["born"]) > life * 1.4:
			_stamps.remove_at(index)
	var ranked := _stamps.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _distance(a["at"], near) < _distance(b["at"], near))
	var count := mini(ranked.size(), SHOWN)
	for index in count:
		var stamp: Dictionary = ranked[index]
		var at: PackedFloat64Array = stamp["at"]
		var forward: Vector3 = stamp["forward"]
		var up: Vector3 = stamp["up"]
		_image.set_pixel(index, 0, Color(fposmod(at[0], 1024.0), fposmod(at[1], 1024.0),
				fposmod(at[2], 1024.0), float(stamp["born"])))
		_image.set_pixel(index, 1, Color(forward.x, forward.y, forward.z, float(stamp["side"])))
		_image.set_pixel(index, 2, Color(up.x, up.y, up.z, 0.0))
	_texture.update(_image)
	_material.set_shader_parameter(&"dent_count", count)


static func _distance(at: PackedFloat64Array, near: Vector3) -> float:
	var dx := at[0] - near.x
	var dy := at[1] - near.y
	var dz := at[2] - near.z
	return dx * dx + dy * dy + dz * dz
