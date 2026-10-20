class_name PlanetGroundBake
extends Node
## The heights of the packed ground plates, drawn into a picture round the camera, so that the
## ground shader's parallax march reads one texel a step instead of working the procedural pattern
## out at every step (task 077: 14.0 to 5.4 ms in the lab view with the same look). The picture is
## made at run time from the same functions and sliders (planet_mosaic_bake.gdshader): a cache of
## the pattern, not an asset.
##
## The picture wraps round (a torus): the texel of the ground at world texel w is w mod `pixels`,
## so when the camera walks only the strip of ground it has just reached is drawn, not the whole
## picture. The ground shader reads it through `mosaic_height_window` (the window's corner, its
## size, 1) and falls back to working the heights out outside the window or while there is none.
## Everything is in the march's own coordinates ("flat": the ground's metres along the anchor's
## right and forward axes, see `flat_of`), which change whenever the planet's anchor does: `follow`
## takes a key for that frame and draws the whole picture again when the key changes.

const SHADER := preload("res://shaders/world/planet_mosaic_bake.gdshader")
const STEP := 64 ## texels the window moves at a time: a strip this wide is drawn when it does
const RECTS := 8 ## a strip is at most four pieces (it wraps in x and in y), and two strips

var pixels := 2048 ## the picture is this many texels on a side
var metres := 12.0 ## and covers this much ground
var _view: SubViewport
var _rects: Array[ColorRect] = []
var _materials: Array[ShaderMaterial] = []
var _ground: ShaderMaterial
var _origin := Vector2i.ZERO ## the world texel at the window's corner
var _key := 0
var _valid := false
var _used := 0 ## the rects drawn this frame


## Makes the picture and gives it to `ground` (the ground material).
func setup(ground: ShaderMaterial, texels := 2048, size_metres := 12.0) -> void:
	_ground = ground
	pixels = texels
	metres = size_metres
	_view = SubViewport.new()
	_view.size = Vector2i(pixels, pixels)
	_view.use_hdr_2d = true
	_view.transparent_bg = false
	_view.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	for index in RECTS:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"bake_texel", metres / float(pixels))
		var rect := ColorRect.new()
		rect.material = material
		rect.visible = false
		_view.add_child(rect)
		_rects.append(rect)
		_materials.append(material)
	ground.set_shader_parameter(&"mosaic_height_map", _view.get_texture())


## Changes a number of the plates (a `mosaic_*` uniform) for the picture; it is drawn again.
func set_parameter(key: StringName, value: Variant) -> void:
	for material in _materials:
		material.set_shader_parameter(key, value)
	_valid = false


## The ground's own metres at the world position `at`, as the ground shader finds them: the
## position from the anchor plus the wrapped anchor, along the anchor's right and forward axes.
static func flat_of(frame: PlanetFrame, at: Vector3) -> Vector2:
	var on_planet := frame.anchor_from_world() * at + frame.anchor_wrap()
	var up := frame.anchor_up().normalized()
	var reference := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var right := reference.cross(up).normalized()
	var forward := up.cross(right)
	return Vector2(on_planet.dot(right), on_planet.dot(forward))


## Keeps the picture round `centre` (the camera in the march's coordinates). `key` names the
## frame those coordinates belong to: a new key draws everything again.
func follow(centre: Vector2, key: int) -> void:
	for rect in _rects:
		rect.visible = false
	_used = 0
	var texel := metres / float(pixels)
	var middle := Vector2i(floori(centre.x / texel), floori(centre.y / texel))
	if not _valid or key != _key:
		_key = key
		_valid = true
		_origin = _corner_for(middle)
		_draw(_origin, Vector2i(pixels, pixels))
		_publish()
		return
	var drift := middle - (_origin + Vector2i(pixels, pixels) / 2)
	if absi(drift.x) < STEP * 3 / 2 and absi(drift.y) < STEP * 3 / 2:
		return
	var want := _corner_for(middle)
	if want == _origin:
		return
	var delta := want - _origin
	if absi(delta.x) >= pixels or absi(delta.y) >= pixels:
		_draw(want, Vector2i(pixels, pixels))
	else:
		# the ground the window has just reached: a strip across the new window (the columns it gained)
		# and a strip across the part the two windows share (the rows it gained)
		var gained_x := _gained(_origin.x, want.x)
		_draw(Vector2i(gained_x.x, want.y), Vector2i(gained_x.y, pixels))
		var shared_from := maxi(_origin.x, want.x)
		var shared_width := mini(_origin.x, want.x) + pixels - shared_from
		var gained_y := _gained(_origin.y, want.y)
		_draw(Vector2i(shared_from, gained_y.x), Vector2i(shared_width, gained_y.y))
	_origin = want
	_publish()


## The window's corner (a multiple of STEP) that puts `middle` in the middle.
func _corner_for(middle: Vector2i) -> Vector2i:
	var half := pixels / 2
	return Vector2i(floori(float(middle.x - half) / STEP) * STEP,
			floori(float(middle.y - half) / STEP) * STEP)


## The texels a window gained along one axis when its corner moved from `old` to `now`:
## (the first one, how many).
func _gained(old: int, now: int) -> Vector2i:
	if now > old:
		return Vector2i(old + pixels, now - old)
	return Vector2i(now, old - now)


## Draws the world texels from `corner`, `size` of them, into the picture; the picture wraps, so a
## rectangle that crosses its edge is drawn in pieces.
func _draw(corner: Vector2i, size: Vector2i) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	for across in _cut(corner.x, size.x):
		for down in _cut(corner.y, size.y):
			_place(Vector2i(across.x, down.x), Vector2i(across.y, down.y))
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## Splits `length` texels from world texel `start` where the picture wraps: (start, length) pieces.
func _cut(start: int, length: int) -> Array[Vector2i]:
	var first := mini(length, pixels - posmod(start, pixels))
	if first >= length:
		return [Vector2i(start, length)]
	return [Vector2i(start, first), Vector2i(start + first, length - first)]


func _place(world: Vector2i, size: Vector2i) -> void:
	var rect := _rects[_used]
	rect.position = Vector2(posmod(world.x, pixels), posmod(world.y, pixels))
	rect.size = Vector2(size)
	rect.visible = true
	_materials[_used].set_shader_parameter(&"bake_rect",
			Vector4(world.x, world.y, size.x, size.y))
	_used += 1


func _publish() -> void:
	var texel := metres / float(pixels)
	_ground.set_shader_parameter(&"mosaic_height_window",
			Vector4(_origin.x * texel, _origin.y * texel, metres, 1.0))
