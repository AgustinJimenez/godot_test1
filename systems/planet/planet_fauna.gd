class_name PlanetFauna
extends WorldFauna
## The flat world's deer and rabbits (WorldFauna: same animals, same wandering, fleeing and
## sleeping) on a planet: they look the ground up through the planet (PlanetWorld.ground_at)
## instead of a flat height function, so they stand on its meadows and forests and keep out of the
## sea, rivers and lakes.

var planet: PlanetWorld


func update(target: Vector3, daylight: float, delta: float) -> void:
	if planet == null or planet.noise == null:
		return
	for animal in _animals:
		var away := Vector2(animal.global_position.x - target.x, animal.global_position.z - target.z)
		if not animal.visible or away.length() > FAR:
			_place(animal, target)
			continue
		animal.visible = daylight > 0.25
		_think(animal, away, delta)
		_move(animal, delta)


func _place(animal: Animal, target: Vector3) -> void:
	for attempt in 12:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(NEAR, FAR * 0.9)
		var x := target.x + cos(angle) * distance
		var z := target.z + sin(angle) * distance
		var ground := planet.ground_at(x, z, target.y)
		if ground["wet"]:
			continue
		var biome: int = ground["biome"]
		if biome != TerrainNoise.Biome.MEADOW and biome != TerrainNoise.Biome.FOREST:
			continue
		animal.global_position = Vector3(x, float(ground["y"]), z)
		animal.state = &"idle"
		animal.timer = _rng.randf_range(1.0, 6.0)
		animal.visible = true
		return
	animal.visible = false # nowhere suitable this time; try again next frame


func _move(animal: Animal, delta: float) -> void:
	var speed := 0.0
	match animal.state:
		&"walk":
			speed = 1.3 if animal.is_deer else 0.7
		&"flee":
			speed = 7.0 if animal.is_deer else 5.0
	var step := Vector2.from_angle(animal.heading) * speed * delta
	var here := animal.global_position
	var ground := planet.ground_at(here.x + step.x, here.z + step.y, here.y)
	var next := Vector3(here.x + step.x, float(ground["y"]), here.z + step.y)
	# water ahead or a cliff: turn instead of going on
	var jump := absf(next.y - here.y) > 0.9 * maxf(speed * delta, 0.01) + 0.15
	if ground["wet"] or jump:
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
	else:
		var hop := maxf(sin(animal.phase), 0.0) if speed > 0.1 else 0.0
		animal.body.position.y = hop * 0.28
		animal.body.rotation.x = -hop * 0.3
