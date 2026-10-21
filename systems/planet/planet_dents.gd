class_name PlanetDents
extends RefCounted
## The prints that dent the sand (task 078, planet_dents.gdshaderinc): a list of stamps in planet
## space (so they stay put when the world turns under the player). Each stamp is a PROFILE, a small
## picture of how deep each spot under whatever touched the sand is pressed (PlanetImprinter takes
## it from the real mesh), 0.8 m square, TILE pixels across. The nearest SHOWN are put in one atlas
## texture the ground shader reads, with the clock they were made at (the shader works out the
## age). Nothing is drawn here and the ground does not change.

const SHOWN := 32 ## how many the shader gets (the nearest to the camera)
const KEPT := 240 ## how many are remembered (the oldest go first)
const REFRESH := 0.25 ## s between two choices of the nearest stamps
const TILE := 192 ## pixels across a profile
const SPAN := 0.8 ## m across a profile
const COLUMNS := 8 ## the atlas: COLUMNS x (SHOWN / COLUMNS) profiles

static var _soles: Dictionary = {} # side -> the bare foot's profile (the lab and the fallback)

var life := 240.0 ## s, when a print has gone
var clock := 0.0 ## s since the start; the stamps are made at this time
var _stamps: Array[Dictionary] = [] # {at (planet, doubles), forward, up, born, profile, id}
var _next_id := 1
var _shown: Array[int] = [] # the ids in the atlas, in slot order
var _image := Image.create(SHOWN, 3, false, Image.FORMAT_RGBAF)
var _texture := ImageTexture.create_from_image(_image)
var _atlas := Image.create(TILE * COLUMNS, TILE * (SHOWN / COLUMNS), false, Image.FORMAT_R8)
var _atlas_texture: ImageTexture
var _since := REFRESH
var _material: ShaderMaterial


func _init(material: ShaderMaterial) -> void:
	_material = material
	_atlas_texture = ImageTexture.create_from_image(_atlas)
	_material.set_shader_parameter(&"dent_stamps", _texture)
	_material.set_shader_parameter(&"dent_atlas", _atlas_texture)
	_material.set_shader_parameter(&"dent_life", life)
	_material.set_shader_parameter(&"dent_count", 0)


## One print at the planet position `at`, its toe along `forward`, the ground's up `up` (both in
## planet axes); `profile` is what touched the sand (TILE x TILE bytes, 255 the deepest), or
## empty for a bare foot (`side` +1 right, -1 left). `age` makes it older (the lab).
func add(at: PackedFloat64Array, forward: Vector3, up: Vector3, side: float, age := 0.0,
		profile := PackedByteArray()) -> void:
	if _stamps.size() >= KEPT:
		_stamps.pop_front()
	if profile.is_empty():
		profile = sole_profile(side)
	_stamps.append({"at": at, "forward": forward.normalized(), "up": up.normalized(),
			"born": clock - age, "profile": profile, "id": _next_id})
	_next_id += 1
	_since = REFRESH # (choose again at once)


func clear() -> void:
	_stamps.clear()
	_shown.clear()
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
	var ids: Array[int] = []
	for index in count:
		var stamp: Dictionary = ranked[index]
		var at: PackedFloat64Array = stamp["at"]
		var forward: Vector3 = stamp["forward"]
		var up: Vector3 = stamp["up"]
		ids.append(int(stamp["id"]))
		_image.set_pixel(index, 0, Color(fposmod(at[0], 1024.0), fposmod(at[1], 1024.0),
				fposmod(at[2], 1024.0), float(stamp["born"])))
		_image.set_pixel(index, 1, Color(forward.x, forward.y, forward.z, 0.0))
		_image.set_pixel(index, 2, Color(up.x, up.y, up.z, 0.0))
	_texture.update(_image)
	if ids != _shown: # (the pictures are copied only when the nearest set changed)
		_shown = ids
		for index in count:
			var tile := Image.create_from_data(TILE, TILE, false, Image.FORMAT_R8,
					ranked[index]["profile"])
			_atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE),
					Vector2i((index % COLUMNS) * TILE, (index / COLUMNS) * TILE))
		var mapped := _atlas.duplicate() as Image
		mapped.generate_mipmaps() # (an old print is a blurred one: the shader picks the level)
		_atlas_texture = ImageTexture.create_from_image(mapped)
		_material.set_shader_parameter(&"dent_atlas", _atlas_texture)
	_material.set_shader_parameter(&"dent_count", count)


## A bare foot as a profile (a heel, a narrow arch, the ball and five toes; PlanetImprintNative
## draws it). `side` +1 right, -1 left.
static func sole_profile(side: float) -> PackedByteArray:
	var key := signf(side)
	if not _soles.has(key):
		var maker: Object = ClassDB.instantiate(&"PlanetImprintNative")
		_soles[key] = maker.call(&"sole_profile", key, TILE, SPAN)
	return _soles[key]


static func _distance(at: PackedFloat64Array, near: Vector3) -> float:
	var dx := at[0] - near.x
	var dy := at[1] - near.y
	var dz := at[2] - near.z
	return dx * dx + dy * dy + dz * dz
