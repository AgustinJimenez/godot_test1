class_name PlanetFootprints
extends Node3D
## Footprints the player leaves in snow, sand and mud: on sand and desert a dent the ground
## shader works out (PlanetDents, task 078), in snow and mud one Decal a step, alternating left and
## right, kept in planet space (the world turns under the player as they walk, a decal in world
## space would slide off the ground) and faded out over LIFE seconds. At most MAX decals exist; the
## right, kept in planet space (the world turns under the player as they walk, a decal in world
## setting is on, and only close to the camera (the decals fade out by distance).

const MAX := 48
const STEP := 0.85 ## m between two footprints
const RETRIES := 8 ## frames a print is tried again while no foot is on the ground
const LIFE := 120.0 ## s
## m: foot width, depth of the box that projects (deep: it must reach the ground whatever the
## collider and the drawn ground disagree by), foot length
const SIZE := Vector3(0.26, 2.0, 0.44)

var planet: PlanetWorld
var target: Player
var dents: PlanetDents
var imprinter: PlanetImprinter
var dust: PlanetDust

var _prints: Array[Dictionary] = [] # {decal, at (planet, doubles), up, forward, age}
var _since := 0.0
var _left := false
var _last := Vector3.ZERO
var _have_last := false
var _retry := 0
var _fall := 0.0 ## m/s, the fastest the player fell since they left the ground
var _decals_on := false
static var _texture: ImageTexture


func _physics_process(delta: float) -> void:
	_follow(delta)
	if dents == null and planet != null:
		dents = PlanetDents.new(PlanetTile.ground_material())
	if dents != null:
		dents.update(delta, planet.planet_position())
	if target == null:
		_clear()
		return
	_decals_on = bool(GraphicsSettings.get_graphics_value(&"decals"))
	if not _decals_on and not _prints.is_empty():
		_clear(false) # (the dents in sand are not decals: they stay on)
	var here := target.global_position
	if not target.is_on_floor():
		_have_last = false
		_fall = minf(_fall, target.velocity.y)
		return
	if _fall < -3.5: # (a landing: a puff of dust on sand, the harder the more)
		_land(here, -_fall)
	_fall = 0.0
	if not _have_last:
		_last = here
		_have_last = true
	var moved := Vector2(here.x - _last.x, here.z - _last.z).length()
	if moved >= STEP:
		_last = here
		_retry = RETRIES
	elif _retry > 0:
		_retry -= 1 # (the foot was in the air: look again next frame)
	else:
		return
	_press(here)


## One footprint under the player's foot (not in the sea or on hard ground).
func _press(feet: Vector3) -> void:
	var ground := planet.ground_at(feet.x, feet.z, feet.y)
	if ground["wet"]:
		return
	# the ground the player really stands on (the tile's collider), not the analytic height
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 1.2,
			feet - Vector3.UP * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var up_world: Vector3 = hit["normal"]
	var forward := -target.global_transform.basis.z
	forward = (forward - up_world * forward.dot(up_world)).normalized()
	_left = not _left
	var side := up_world.cross(forward) * (0.11 if _left else -0.11)
	var spot: Vector3 = (hit["position"] as Vector3) + side
	spot -= up_world * up_world.dot(side) # (on the slope, not above or below it)
	var frame := planet.frame
	var back := frame.rot.inverse()
	if _is_sand(int(ground["biome"])):
		_dent_sand(hit["position"], forward, up_world)
		return
	if not _decals_on:
		return
	var tint := _tint(int(ground["biome"]), _paint(feet))
	if tint.a <= 0.0:
		return
	var decal := _next_decal()
	decal.modulate = tint
	_prints.append({"decal": decal, "at": frame.to_planet(spot), "up": back * up_world,
			"forward": back * forward, "age": 0.0, "tint": tint})


## What touches the sand at `at` leaves its own shape: the real mesh is looked at from under the
## ground (PlanetImprinter), and the print keeps that. A foot in the air leaves nothing and the
## next frames try again.
func _dent_sand(at: Vector3, forward: Vector3, up_world: Vector3) -> void:
	if imprinter == null:
		imprinter = PlanetImprinter.new()
		add_child(imprinter)
	var rebased := planet.rebases
	var frame := planet.frame
	var back := frame.rot.inverse()
	var where := frame.to_planet(at)
	var profile := await imprinter.take(at, forward, up_world)
	if profile.is_empty() or planet.rebases != rebased or dents == null:
		return
	_retry = 0
	dents.add(where, back * forward, back * up_world, 1.0, 0.0, profile)
	if dust == null:
		dust = PlanetDust.new()
		add_child(dust)
	dust.puff(at, up_world, _paint(at), 0.5 + 0.1 * target.velocity.length())


## A landing at `feet` from a fall of `speed` m/s: dust on sand and dry ground.
func _land(feet: Vector3, speed: float) -> void:
	var ground := planet.ground_at(feet.x, feet.z, feet.y)
	if ground["wet"] or not _is_sand(int(ground["biome"])):
		return
	if dust == null:
		dust = PlanetDust.new()
		add_child(dust)
	dust.puff(feet, Vector3.UP, _paint(feet), clampf(speed * 0.15, 0.6, 1.5))


## The colour of the ground under a world position (what the ground shader starts from).
func _paint(world_position: Vector3) -> Color:
	var at := planet.frame.to_planet(world_position)
	var dir := Vector3(at[0], at[1], at[2]).normalized()
	var colours := planet.noise.colours_of(PackedVector3Array([dir]),
			PackedFloat32Array([planet.noise.height(dir.x, dir.y, dir.z)]), PackedFloat32Array([0.1]))
	return colours[0]


## Sand and desert take a real dent; the rest a flat decal.
func _is_sand(biome: int) -> bool:
	return biome == TerrainNoise.Biome.DESERT or biome == TerrainNoise.Biome.BEACH


## The colour and strength of a footprint on this biome and ground colour (alpha 0: none).
func _tint(biome: int, paint: Color) -> Color:
	if minf(paint.r, minf(paint.g, paint.b)) > 0.68: # snow and ice are white
		return Color(0.45, 0.55, 0.7, 0.85)
	match biome:
		TerrainNoise.Biome.SNOW:
			return Color(0.45, 0.55, 0.7, 0.85)
		TerrainNoise.Biome.DESERT, TerrainNoise.Biome.BEACH:
			return Color(0.45, 0.36, 0.25, 0.7)
		TerrainNoise.Biome.MARSH:
			return Color(0.14, 0.1, 0.06, 0.8)
	return Color(0.0, 0.0, 0.0, 0.0)


func _next_decal() -> Decal:
	if _prints.size() >= MAX:
		var oldest: Dictionary = _prints.pop_front()
		return oldest["decal"]
	var decal := Decal.new()
	decal.size = SIZE
	decal.texture_albedo = _footprint()
	decal.upper_fade = 0.3
	decal.lower_fade = 0.3
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 25.0
	decal.distance_fade_length = 12.0
	add_child(decal)
	return decal


## Puts every decal where its planet-space spot is now and fades it with its age.
func _follow(delta: float) -> void:
	if planet == null or planet.frame == null:
		return
	var frame := planet.frame
	for index in range(_prints.size() - 1, -1, -1):
		var print_info: Dictionary = _prints[index]
		print_info["age"] = float(print_info["age"]) + delta
		var age: float = print_info["age"]
		var decal: Decal = print_info["decal"]
		if age >= LIFE:
			decal.queue_free()
			_prints.remove_at(index)
			continue
		var at: PackedFloat64Array = print_info["at"]
		var offset := Vector3(at[0] - frame.anchor[0], at[1] - frame.anchor[1], at[2] - frame.anchor[2])
		var up: Vector3 = (frame.rot * (print_info["up"] as Vector3)).normalized()
		var forward: Vector3 = (frame.rot * (print_info["forward"] as Vector3)).normalized()
		var right := forward.cross(up).normalized()
		var world_at: Vector3 = frame.rot * offset + frame.origin_w + up * 0.02
		decal.global_transform = Transform3D(Basis(right, up, -forward), world_at)
		var tint: Color = print_info["tint"]
		decal.modulate = Color(tint.r, tint.g, tint.b, tint.a * (1.0 - smoothstep(LIFE * 0.6, LIFE, age)))


func _clear(with_dents := true) -> void:
	if dents != null and with_dents:
		dents.clear()
	for print_info in _prints:
		(print_info["decal"] as Decal).queue_free()
	_prints.clear()
	_have_last = false


## A sole and a heel, soft at the edges: white on clear, the decal's colour tints it.
static func _footprint() -> ImageTexture:
	if _texture != null:
		return _texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0 # across the foot
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0 # toe at -1, heel at +1
			var sole := _blob(u, v + 0.28, 0.62, 0.62)
			var heel := _blob(u, v - 0.62, 0.42, 0.28)
			var toes := _blob(u, v + 0.88, 0.45, 0.14)
			var alpha := clampf(maxf(maxf(sole, heel), toes), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_texture = ImageTexture.create_from_image(image)
	return _texture


## 1 in the middle of an ellipse of half-sizes (a, b) and 0 outside, with a soft edge.
static func _blob(u: float, v: float, a: float, b: float) -> float:
	var d := sqrt((u / a) * (u / a) + (v / b) * (v / b))
	return 1.0 - smoothstep(0.7, 1.0, d)
