class_name WorldFootprints
extends Node3D
## Footprints. Walking over fresh snow, wet sand or mud (rain, the beach, the marsh) leaves a print
## under each foot, left and right in turn, that stays a minute and then fades. They are decals
## (a drawn shoe print projected onto the ground), a pool of them that is reused.

const POOL := 60
const WALK_STRIDE := 0.8 ## m between two prints while walking
const RUN_STRIDE := 1.2
const LIFE := 70.0 ## s a print stays

var noise: TerrainNoise
var settings: WorldSettings

var _decals: Array[Decal] = []
var _ages: Array[float] = []
var _tints: Array[Color] = [] # each print's colour (snow or mud), before the fade
var _next := 0
var _distance := 0.0
var _left := true
var _last := Vector3.ZERO
var _texture: ImageTexture


func _ready() -> void:
	_texture = _make_texture()
	for index in POOL:
		var decal := Decal.new()
		decal.texture_albedo = _texture
		decal.size = Vector3(0.34, 1.2, 0.7)
		decal.upper_fade = 0.4
		decal.lower_fade = 0.4
		decal.cull_mask = 1 # the ground, not the plants
		decal.visible = false
		add_child(decal)
		_decals.append(decal)
		_ages.append(LIFE)
		_tints.append(Color.WHITE)


## Called every frame with the player: leaves a print each stride when the ground is soft.
func update(player: Player, snow: float, wetness: float, delta: float) -> void:
	for index in POOL:
		_ages[index] += delta
		if _decals[index].visible:
			var fade := clampf((LIFE - _ages[index]) / 12.0, 0.0, 1.0)
			var tint := _tints[index]
			_decals[index].modulate = Color(tint.r, tint.g, tint.b, tint.a * fade)
			if _ages[index] >= LIFE:
				_decals[index].visible = false
	if noise == null or not player.is_on_floor():
		_last = player.global_position
		return
	var here := player.global_position
	_distance += Vector2(here.x - _last.x, here.z - _last.z).length()
	_last = here
	var running := Vector2(player.velocity.x, player.velocity.z).length() > 3.0
	if _distance < (RUN_STRIDE if running else WALK_STRIDE):
		return
	_distance = 0.0
	var kind := _soft_ground(here, snow, wetness)
	if kind == &"":
		return
	_place(player, kind)


## "snow", "mud" or "" for what is under the feet.
func _soft_ground(at: Vector3, snow: float, wetness: float) -> StringName:
	if snow > 0.35:
		return &"snow"
	var ground := noise.height(at.x, at.z)
	var biome := noise.biome(at.x, at.z, ground, noise.slope(at.x, at.z))
	if biome == TerrainNoise.Biome.MARSH or biome == TerrainNoise.Biome.BEACH:
		return &"mud"
	if wetness > 0.5 and biome != TerrainNoise.Biome.ROCKY:
		return &"mud"
	return &""


func _place(player: Player, kind: StringName) -> void:
	var decal := _decals[_next]
	_next = (_next + 1) % POOL
	var yaw := player.global_rotation.y
	var side := Basis(Vector3.UP, yaw) * Vector3(0.11 if _left else -0.11, 0.0, 0.0)
	_left = not _left
	decal.global_position = player.global_position + side + Vector3(0.0, 0.5, 0.0)
	decal.global_rotation = Vector3(0.0, yaw, 0.0)
	decal.albedo_mix = 1.0
	var slot := _decals.find(decal)
	_tints[slot] = Color(0.36, 0.4, 0.5, 0.85) if kind == &"snow" else Color(0.08, 0.05, 0.03, 0.9)
	decal.modulate = _tints[slot]
	decal.visible = true
	_ages[slot] = 0.0


## A drawn shoe print: a sole and a heel with a gap between, white on transparent.
func _make_texture() -> ImageTexture:
	var image := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			var u := (float(x) - 15.5) / 15.5
			var v := (float(y) - 31.5) / 31.5
			var sole := (u * u) / (0.85 * 0.85) + pow(v + 0.38, 2.0) / (0.55 * 0.55) < 1.0
			var heel := (u * u) / (0.7 * 0.7) + pow(v - 0.62, 2.0) / (0.25 * 0.25) < 1.0
			var edge := 1.0 if sole or heel else 0.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, edge))
	return ImageTexture.create_from_image(image)
