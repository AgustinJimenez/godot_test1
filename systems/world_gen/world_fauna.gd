class_name WorldFauna
extends Node3D
## Deer and rabbits that wander the meadows and forests near the player. A small pool of animals is
## kept around the target: each one idles, walks or flees (deer at 25 m, rabbits at 10 m), follows
## the ground, keeps out of the water, and is moved to a fresh spot when the player has left it far
## behind. They sleep (are hidden) in the deep of the night.

const DEER := 9
const RABBITS := 14
const NEAR := 55.0 ## m: closest an animal is placed to the target
const FAR := 150.0 ## m: farther than this it is moved
const FLEE_DEER := 25.0
const FLEE_RABBIT := 11.0

class Animal:
	extends Node3D
	var is_deer := true
	var state := &"idle"
	var timer := 0.0
	var heading := 0.0
	var phase := 0.0
	var legs: Array[Node3D] = []
	var body: Node3D

var noise: TerrainNoise
var settings: WorldSettings

var _animals: Array[Animal] = []
var _rng := RandomNumberGenerator.new()
var _deer_mesh: ArrayMesh
var _leg_mesh: ArrayMesh
var _rabbit_mesh: ArrayMesh


func _ready() -> void:
	_rng.seed = 5150
	_deer_mesh = _make_deer()
	_leg_mesh = _make_leg()
	_rabbit_mesh = _make_rabbit()
	for index in DEER + RABBITS:
		var animal := _make_animal(index < DEER)
		add_child(animal)
		animal.visible = false
		_animals.append(animal)


func update(target: Vector3, daylight: float, delta: float) -> void:
	if noise == null:
		return
	for animal in _animals:
		var away := Vector2(animal.global_position.x - target.x, animal.global_position.z - target.z)
		if not animal.visible or away.length() > FAR:
			_place(animal, target)
			continue
		animal.visible = daylight > 0.25
		_think(animal, away, delta)
		_move(animal, delta)


func _make_animal(deer: bool) -> Animal:
	var animal := Animal.new()
	animal.is_deer = deer
	var body := Node3D.new()
	animal.body = body
	animal.add_child(body)
	var instance := MeshInstance3D.new()
	instance.mesh = _deer_mesh if deer else _rabbit_mesh
	instance.material_override = FloraMeshes.material()
	body.add_child(instance)
	if deer:
		for corner: Vector2 in [Vector2(0.55, 0.16), Vector2(0.55, -0.16), Vector2(-0.5, 0.16),
				Vector2(-0.5, -0.16)]:
			var pivot := Node3D.new()
			pivot.position = Vector3(corner.x, 0.95, corner.y)
			var leg := MeshInstance3D.new()
			leg.mesh = _leg_mesh
			leg.material_override = FloraMeshes.material()
			pivot.add_child(leg)
			body.add_child(pivot)
			animal.legs.append(pivot)
	animal.heading = _rng.randf() * TAU
	animal.timer = _rng.randf_range(1.0, 5.0)
	return animal


func _place(animal: Animal, target: Vector3) -> void:
	for attempt in 12:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(NEAR, FAR * 0.9)
		var x := target.x + cos(angle) * distance
		var z := target.z + sin(angle) * distance
		var ground := noise.height(x, z)
		if ground < noise.water_level(x, z) + 1.0:
			continue
		var biome := noise.biome(x, z, ground, noise.slope(x, z))
		if biome != TerrainNoise.Biome.MEADOW and biome != TerrainNoise.Biome.FOREST:
			continue
		animal.global_position = Vector3(x, ground, z)
		animal.state = &"idle"
		animal.timer = _rng.randf_range(1.0, 6.0)
		animal.visible = true
		return
	animal.visible = false # nowhere suitable this time; try again next frame


func _think(animal: Animal, away: Vector2, delta: float) -> void:
	var scared := FLEE_DEER if animal.is_deer else FLEE_RABBIT
	if away.length() < scared:
		animal.state = &"flee"
		animal.heading = atan2(away.y, away.x)
		animal.timer = 1.2
		return
	animal.timer -= delta
	if animal.timer > 0.0:
		return
	if animal.state == &"idle":
		animal.state = &"walk"
		animal.heading += _rng.randf_range(-1.5, 1.5)
		animal.timer = _rng.randf_range(2.0, 6.0)
	else:
		animal.state = &"idle"
		animal.timer = _rng.randf_range(2.0, 7.0)


func _move(animal: Animal, delta: float) -> void:
	var speed := 0.0
	match animal.state:
		&"walk":
			speed = 1.3 if animal.is_deer else 0.7
		&"flee":
			speed = 7.0 if animal.is_deer else 5.0
	var step := Vector2.from_angle(animal.heading) * speed * delta
	var here := animal.global_position
	var next := Vector3(here.x + step.x, 0.0, here.z + step.y)
	next.y = noise.height(next.x, next.z)
	# water ahead or a cliff: turn instead of going on
	var jump := absf(next.y - here.y) > 0.9 * maxf(speed * delta, 0.01) + 0.15
	if next.y < noise.water_level(next.x, next.z) + 0.4 or jump:
		animal.heading += PI * 0.6
		next = here
	animal.global_position = next
	animal.rotation.y = -animal.heading + PI * 0.5
	animal.phase += speed * delta * (3.2 if animal.is_deer else 4.0)
	if animal.is_deer:
		var swing := minf(speed, 4.0) * 0.14
		for index in animal.legs.size():
			animal.legs[index].rotation.x = sin(animal.phase + (PI if index % 3 != 0 else 0.0)) * swing
		animal.body.position.y = absf(sin(animal.phase)) * 0.04 * minf(speed, 3.0)
	else: # rabbits hop
		var hop := maxf(sin(animal.phase), 0.0) if speed > 0.1 else 0.0
		animal.body.position.y = hop * 0.28
		animal.body.rotation.x = -hop * 0.3


func _make_deer() -> ArrayMesh:
	var builder := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fur := Color(0.55, 0.38, 0.22, 0.0)
	var belly := Color(0.82, 0.72, 0.55, 0.0)
	builder.add_blob(Vector3(0.0, 1.1, 0.0), Vector3(0.75, 0.38, 0.3), fur.darkened(0.15), fur, rng,
			0.06)
	builder.add_blob(Vector3(0.0, 0.95, 0.0), Vector3(0.6, 0.2, 0.26), belly, belly, rng, 0.04)
	# neck and head lean forward (+X), antlers on top
	builder.xf = Transform3D(Basis(Vector3.BACK, -0.9), Vector3(0.6, 1.2, 0.0))
	builder.add_frustum(Vector3.ZERO, 0.6, 0.17, 0.11, 5, fur.darkened(0.1), fur)
	builder.xf = Transform3D.IDENTITY
	builder.add_blob(Vector3(1.08, 1.68, 0.0), Vector3(0.22, 0.14, 0.12), fur, fur.lightened(0.1),
			rng, 0.05)
	builder.add_blob(Vector3(-0.72, 1.18, 0.0), Vector3(0.1, 0.1, 0.1), belly, belly, rng, 0.05)
	for side in [-1.0, 1.0]:
		builder.xf = Transform3D(Basis(Vector3.RIGHT, side * 0.45) * Basis(Vector3.BACK, 0.2),
				Vector3(1.0, 1.78, side * 0.07))
		builder.add_frustum(Vector3.ZERO, 0.5, 0.025, 0.01, 4, Color(0.8, 0.75, 0.6, 0.0),
				Color(0.9, 0.85, 0.7, 0.0))
	builder.xf = Transform3D.IDENTITY
	return builder.commit()


func _make_leg() -> ArrayMesh:
	var builder := MeshBuilder.new()
	var fur := Color(0.45, 0.31, 0.18, 0.0)
	builder.add_frustum(Vector3(0.0, -0.95, 0.0), 0.95, 0.04, 0.07, 5, Color(0.2, 0.15, 0.1, 0.0), fur)
	return builder.commit()


func _make_rabbit() -> ArrayMesh:
	var builder := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var fur := Color(0.62, 0.55, 0.45, 0.0)
	builder.add_blob(Vector3(0.0, 0.17, 0.0), Vector3(0.2, 0.15, 0.13), fur.darkened(0.1), fur, rng,
			0.05)
	builder.add_blob(Vector3(0.2, 0.26, 0.0), Vector3(0.1, 0.09, 0.08), fur, fur.lightened(0.1), rng,
			0.05)
	for side in [-1.0, 1.0]:
		builder.xf = Transform3D(Basis(Vector3.RIGHT, side * 0.15) * Basis(Vector3.BACK, -0.2),
				Vector3(0.18, 0.31, side * 0.035))
		builder.add_frustum(Vector3.ZERO, 0.2, 0.025, 0.012, 4, fur, fur.lightened(0.2))
	builder.xf = Transform3D.IDENTITY
	builder.add_blob(Vector3(-0.22, 0.2, 0.0), Vector3(0.05, 0.05, 0.05), Color.WHITE, Color.WHITE,
			rng, 0.0)
	return builder.commit()
