class_name PlanetMapLabels
extends RefCounted
## The names of the seas and the lands of a planet for the map, in widely spaced capitals as a
## weather map writes them (ATLANTIC OCEAN). The biggest bodies of sea and land are found on a
## coarse grid of the planet's own heights and each gets a made-up name from the seed, at the
## middle of its biggest part.

const WIDTH := 192
const HEIGHT := 96
const SYLLABLES: Array[String] = ["ar", "al", "an", "ba", "bor", "cal", "dan", "el", "fen", "gar",
		"hal", "is", "ka", "lor", "mar", "nor", "or", "pan", "quel", "ros", "sa", "tar", "ul", "ver",
		"wen", "xan", "yor", "zel"]

var items: Array[Dictionary] = [] ## {uv, text, sea, area} of each name


## Finds the bodies of sea and land and names them.
func build(noise: PlanetNoise) -> void:
	items.clear()
	var dirs := PackedVector3Array()
	dirs.resize(WIDTH * HEIGHT)
	for row in HEIGHT:
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		for column in WIDTH:
			var lon := (float(column) + 0.5) / float(WIDTH) * TAU - PI
			dirs[row * WIDTH + column] = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	var heights := noise.macro_heights_of(dirs)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.settings.world_seed + 77
	var seen := PackedByteArray()
	seen.resize(WIDTH * HEIGHT)
	var found: Array[Dictionary] = []
	for start in WIDTH * HEIGHT:
		if seen[start] == 1:
			continue
		var sea := heights[start] < 0.0
		var members := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var at := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			members.append(at)
			var row := at / WIDTH
			var column := at % WIDTH
			for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var r: int = row + step[1]
				if r < 0 or r >= HEIGHT:
					continue
				var next: int = r * WIDTH + posmod(column + step[0], WIDTH)
				if seen[next] == 0 and (heights[next] < 0.0) == sea:
					seen[next] = 1
					stack.append(next)
		# (a cell is a smaller share of the sphere toward the poles: weight by the cosine of its latitude)
		var area := 0.0
		for member in members:
			area += cos((0.5 - (float(member / WIDTH) + 0.5) / float(HEIGHT)) * PI)
		found.append({"members": members, "sea": sea, "area": area})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["area"] > b["area"])
	var seas := 0
	var lands := 0
	for body in found:
		var area: float = body["area"]
		var sea: bool = body["sea"]
		if area < 150.0 or (sea and seas >= 6) or (not sea and lands >= 6):
			continue
		var uv := _middle(body["members"])
		var name_text := _name(rng)
		if sea:
			seas += 1
			name_text += " OCEAN" if area > 2500.0 else " SEA"
		else:
			lands += 1
		items.append({"uv": uv, "text": name_text.to_upper(), "sea": sea, "area": area})


## The point of the body nearest its middle (the middle itself may be outside it).
func _middle(members: PackedInt32Array) -> Vector2:
	var sum := Vector3.ZERO
	for member in members:
		var lat := (0.5 - (float(member / WIDTH) + 0.5) / float(HEIGHT)) * PI
		var lon := (float(member % WIDTH) + 0.5) / float(WIDTH) * TAU - PI
		sum += Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	var centre := sum.normalized() if sum.length() > 0.001 else Vector3.RIGHT
	var best := members[0]
	var best_dot := -2.0
	for member in members:
		var lat := (0.5 - (float(member / WIDTH) + 0.5) / float(HEIGHT)) * PI
		var lon := (float(member % WIDTH) + 0.5) / float(WIDTH) * TAU - PI
		var here := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
		if here.dot(centre) > best_dot:
			best_dot = here.dot(centre)
			best = member
	return Vector2((float(best % WIDTH) + 0.5) / float(WIDTH),
			(float(best / WIDTH) + 0.5) / float(HEIGHT))


func _name(rng: RandomNumberGenerator) -> String:
	var text := ""
	for part in rng.randi_range(2, 3):
		text += SYLLABLES[rng.randi() % SYLLABLES.size()]
	return text.capitalize()


## `text` with a space between the letters (as the map writes a name).
static func spaced(text: String) -> String:
	var out := ""
	for index in text.length():
		out += text[index] + (" " if text[index] != " " else "")
	return out
