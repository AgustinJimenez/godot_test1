class_name TreeArchetypes
extends RefCounted
## Recognisable kinds of tree, each as a TreeGenome, and the random draw that makes new trees out of
## them: pick one or two kinds, blend their traits by a random weight, nudge every trait a little,
## now and then (exoticness) push a trait somewhere unusual. A draw is believable because the traits
## of a kind agree with each other (a baobab is thick AND short AND wide), which independent random
## sliders almost never manage. The world species generator and the lab share this table.

const NAMES: Array[String] = ["leafy", "conifer", "umbrella", "giant", "oak", "ancient", "dragon",
		"willow", "cypress", "bush", "shrub", "groundcover",
		"clump", "palm",
		"dead", "cactus", "fern", "grass", "wildflower",
		"cherry", "blossom"]

## Plausible range of each numeric trait: [min, max]. A draw never leaves it.
const RANGES := {
	"height": [0.1, 45.0], "girth": [0.01, 2.6], "taper": [0.25, 0.95], "lean": [0.0, 0.3],
	"trunk_part": [0.05, 1.0], "root_flare": [0.0, 1.0], "crown": [0.15, 14.0],
	"aspect": [0.4, 2.0], "droop": [0.0, 1.0], "limbs": [3, 10], "twist": [0.0, 1.0], "stems": [1, 6],
	"stem_spread": [0.05, 0.5], "limb_angle": [15.0, 90.0],
	"limb_length": [0.5, 3.0], "limb_thickness": [0.3, 1.3], "nodes_spacing": [0.3, 2.0],
	"curve": [0.0, 1.4], "lift": [-0.1, 0.4], "sag": [0.0, 0.3], "tip_radius": [0.05, 0.8],
	"children": [1, 7], "twig_radius": [0.2, 1.0], "child_radius": [0.3, 0.9],
	"child_length": [0.2, 0.9],
	"child_forward": [0.0, 1.5], "child_side": [0.0, 1.5], "child_up": [-0.5, 1.0],
	"leaf_aspect": [0.8, 5.0], "leaf_size": [0.08, 0.45], "needle_size": [0.2, 1.5],
	"leaf_density": [0.0, 1.0], "rib_width": [0.005, 0.06], "flower_size": [0.02, 0.15],
	"bark_rough": [0.5, 3.0], "petals": [4, 10], "flower_cup": [0.0, 1.0],
	"blossom_size": [0.03, 0.4], "blossom_density": [0.1, 1.0], "fronds": [6, 24],
	"frond_length": [0.2, 8.0],
	"frond_arch": [0.1, 1.0], "frond_droop": [0.1, 1.0], "leaflet": [0.0, 0.4],
}
## Traits that are a choice from a list, not a number (blended by picking one side).
## Sizes that vary by proportion (a bush and a giant both change by a few percent, not by metres).
const PROPORTIONAL := ["height", "girth", "crown", "frond_length", "leaflet", "rib_width"]
const CHOICES := ["blossom_kind", "leaf_shape", "leaf_edge", "leaf_pattern", "foliage", "profile"]


## The genome of the named kind. `leafy` and `conifer` are the species that give the colours and the
## base numbers of the two plain kinds.
static func make(kind: String, leafy: PlantSpecies, conifer: PlantSpecies) -> TreeGenome:
	var g: TreeGenome
	match kind:
		"conifer":
			g = TreeGenome.from_species(conifer)
		"giant":
			g = TreeGenome.from_species(conifer)
			g.height = 42.0
			g.girth = 2.0
			g.root_flare = 0.7
			g.column = 0.22
			g.trunk_part = 0.5
			g.nodes_from = 0.5
			g.crown = 5.0
			g.nodes_spacing = 1.8
			g.limbs = 5
			g.droop = 0.5
		"cypress":
			g = TreeGenome.from_species(conifer)
			g.height = 16.0
			g.girth = 0.5
			g.column = 0.3
			g.trunk_part = 0.05
			g.nodes_from = 0.08
			g.crown = 1.9
			g.nodes_spacing = 0.6
			g.limbs = 4
			g.droop = 0.0
		"umbrella":
			g = _leafy(leafy)
			g.height = 14.0
			g.girth = 1.45
			g.taper = 0.8
			g.trunk_part = 0.5
			g.root_flare = 0.2
			g.crown = 4.0
			g.aspect = 0.45
			g.limbs = 5
			g.limb_angle = 82.0
			g.limb_length = 1.1
			g.limb_thickness = 0.8
			g.curve = [0.5, 0.9, 1.2]
			g.lift = [0.05, 0.04, 0.0]
			g.leaf_size = 0.16
		"oak":
			g = _leafy(leafy)
			g.height = 12.0
			g.girth = 1.5
			g.taper = 0.75
			g.trunk_part = 0.35
			g.root_flare = 0.4
			g.crown = 3.6
			g.aspect = 0.5
			g.limbs = 7
			g.limb_angle = 78.0
			g.limb_length = 1.2
			g.limb_thickness = 0.85
			g.avoid = true
			g.curve = [1.2, 1.2, 1.4]
			g.lift = [0.14, 0.05, 0.0]
			g.sag = [0.0, 0.03, 0.08]
			g.leaf_size = 0.14
		"ancient":
			# an ancient live oak (the Angel Oak): a huge short trunk, limbs as thick as small trees that
			# wind out sideways and almost touch the ground, thick branches off them
			g = make("oak", leafy, conifer)
			g.height = 14.0
			g.girth = 2.0
			g.taper = 0.78
			g.trunk_part = 0.3
			g.root_flare = 0.55
			g.crown = 5.0
			g.limbs = 7
			g.limb_angle = 84.0
			g.limb_length = 1.45
			g.limb_thickness = 1.0
			g.leaf_density = 0.8
			g.leaf_size = 0.6
			g.twist = 0.6
			g.avoid = true
			g.limb_length = 2.3
			g.rings = [6, 5, 3]
			g.sides = [8, 6, 4]
			g.sides_real = [10, 7, 4]
			g.curve = [1.3, 1.3, 1.5]
			g.lift = [0.07, 0.02, 0.0]
			g.child_up = 0.0
			g.aspect = 0.35
			g.sag = [0.0, 0.03, 0.08]
			g.tip_radius = [0.85, 0.75, 0.15]
			g.child_radius = 0.75
			g.twig_radius = 0.4
			g.children = [6, 3, 0]
			g.child_length = [0.7, 0.5, 0.0]
			g.children_from = 0.15
			g.bark = Color(0.3, 0.3, 0.2)
		"willow":
			g = _leafy(leafy)
			g.height = 11.0
			g.girth = 0.5
			g.trunk_part = 0.3
			g.crown = 3.4
			g.limbs = 5
			g.limb_angle = 58.0
			g.droop = 0.9
			g.leaf_shape = PlantSpecies.LeafShape.LANCEOLATE
			g.leaf_aspect = 4.5
			g.leaf_size = 0.17
			g.leaf_pattern = PlantSpecies.LeafPattern.SPIRAL
			g.sag = [0.05, 0.1, 0.2]
		"bush":
			# almost no trunk: many thin stems fanning out from the ground
			g = _leafy(leafy)
			g.height = 1.6
			g.girth = 0.035
			g.taper = 1.0
			g.trunk_part = 0.05
			g.root_flare = 0.0
			g.crown = 0.8
			g.aspect = 1.2
			g.limbs = 10
			g.limb_angle = 38.0
			g.limb_length = 1.0
			g.limb_thickness = 1.0
			g.trunk_sides = 6
			g.leaf_size = 0.2
			g.bark = Color(0.36, 0.28, 0.2)
		"palm":
			# one bare leaning trunk, a crown of long arching fronds
			g = _leafy(leafy)
			g.height = 9.0
			g.girth = 0.22
			g.taper = 0.7
			g.lean = 0.1
			g.trunk_part = 0.97
			g.foliage = TreeGenome.Foliage.FROND
			g.fronds = 14
			g.frond_length = 3.2
			g.frond_arch = 0.5
			g.frond_droop = 0.6
			g.leaflet = 0.2
			g.bark = Color(0.45, 0.36, 0.26)
			g.bark_rings = 0.4
			g.leaf = Color(0.22, 0.45, 0.16)
			g.leaf_tip = Color(0.36, 0.58, 0.22)
		"dead":
			# a dead tree: grey, rough, bare crooked limbs
			g = make("oak", leafy, conifer)
			g.height = 9.0
			g.girth = 0.45
			g.taper = 0.55
			g.trunk_part = 0.3
			g.crown = 3.2
			g.limbs = 5
			g.limb_angle = 55.0
			g.limb_length = 1.0
			g.curve = [1.0, 1.2, 1.4]
			g.leaf_density = 0.0
			g.bark = Color(0.42, 0.38, 0.34)
			g.bark_rough = 1.8
		"cactus":
			# a candelabra cactus: a short thick green trunk, arms that turn up
			g = _leafy(leafy)
			g.height = 5.0
			g.girth = 0.28
			g.taper = 0.9
			g.trunk_part = 0.35
			g.crown = 1.5
			g.aspect = 1.0
			g.limbs = 3
			g.limb_angle = 85.0
			g.limb_length = 1.1
			g.limb_thickness = 0.7
			g.depth = 1
			g.rings = [5, 3, 2]
			g.sides = [8, 5, 4]
			g.sides_real = [10, 6, 4]
			g.curve = [1.3, 0.0, 0.0]
			g.lift = [1.2, 0.0, 0.0]
			g.tip_radius = [0.9, 0.9, 0.9]
			g.trunk_sides = 8
			g.trunk_dark = 0.1
			g.bark_rough = 0.3
			g.leaf_density = 0.0
			g.bark = Color(0.25, 0.45, 0.25)
		"fern", "grass", "wildflower":
			# low plants of fronds or blades straight from the ground
			g = make("palm", leafy, conifer)
			g.height = 0.12
			g.girth = 0.01
			g.taper = 1.0
			g.lean = 0.0
			g.bark_rings = 0.0
			g.bark = Color(0.3, 0.4, 0.2)
			match kind:
				"fern":
					g.fronds = 11
					g.frond_length = 0.7
					g.frond_arch = 0.9
					g.frond_droop = 0.8
					g.leaflet = 0.28
					g.leaf = Color(0.2, 0.5, 0.2)
					g.leaf_tip = Color(0.32, 0.62, 0.26)
				"grass":
					g.fronds = 34
					g.frond_length = 0.5
					g.frond_arch = 0.25
					g.frond_droop = 0.4
					g.leaflet = 0.0
					g.rib_width = 0.035
					g.leaf = Color(0.4, 0.55, 0.18)
					g.leaf_tip = Color(0.58, 0.68, 0.28)
				_:
					g.fronds = 7
					g.frond_length = 0.5
					g.frond_arch = 0.1
					g.frond_droop = 0.0
					g.leaflet = 0.0
					g.rib_width = 0.035
					g.leaf = Color(0.35, 0.52, 0.2)
					g.leaf_tip = Color(0.5, 0.65, 0.28)
					g.flower = Color(0.95, 0.8, 0.2, 1.0)
					g.flower_size = 0.08
		"cherry", "blossom":
			# a tree in flower: a bird cherry's hanging white stems, or a spring tree with pink blossom
			# covering bare twigs
			g = _leafy(leafy)
			g.height = 9.0 if kind == "cherry" else 6.5
			g.girth = 0.3
			g.crown = 3.0 if kind == "cherry" else 3.4
			g.leaf_density = 0.45 if kind == "cherry" else 0.15
			g.leaf_size = 0.14
			g.petals = 5
			g.leaf = Color(0.3, 0.5, 0.2)
			g.leaf_tip = Color(0.42, 0.6, 0.28)
			g.blossom_size = 0.14 if kind == "cherry" else 0.26
			if kind == "cherry":
				g.blossom = Color(0.97, 0.97, 0.95, 1.0)
				g.blossom_kind = TreeGenome.Bloom.RACEME
				g.blossom_density = 1.0
				g.flower_cup = 0.15
			else:
				g.blossom = Color(0.98, 0.7, 0.78, 1.0)
				g.blossom_kind = TreeGenome.Bloom.SINGLE
				g.blossom_density = 0.9
				g.flower_cup = 0.3
		"clump":
			# a birch or hazel clump: several slim stems from one root
			g = _leafy(leafy)
			g.height = 10.0
			g.girth = 0.14
			g.taper = 0.6
			g.stems = 4
			g.stem_spread = 0.22
			g.trunk_part = 0.55
			g.crown = 1.7
			g.limbs = 4
			g.limb_angle = 35.0
			g.leaf_size = 0.15
			g.bark = Color(0.78, 0.74, 0.68)
			g.marked_bark = true
		"shrub", "groundcover":
			# knee-high and below: many fine stems, small leaves
			g = make("bush", leafy, conifer)
			var low := kind == "groundcover"
			g.height = 0.3 if low else 0.7
			g.girth = 0.012 if low else 0.02
			g.crown = 0.3 if low else 0.45
			g.aspect = 0.8 if low else 1.0
			g.limbs = 8 if low else 9
			g.limb_angle = 65.0 if low else 50.0
			g.leaf_size = 0.12 if low else 0.15
		"dragon":
			# thick trunk, limbs that fork again and again into an umbrella of bare branches, the
			# leaves only in a tuft layer at the very ends
			g = TreeGenome.from_species(conifer)
			g.leader = false
			g.whorled = false
			g.profile = TreeGenome.Profile.DOME
			g.foliage = TreeGenome.Foliage.NEEDLE
			g.tips_only = true
			g.carry_on = true
			g.children_planar = false
			g.frosted = false
			g.depth = 3
			g.rings = [5, 4, 3]
			g.sides = [9, 6, 4]
			g.sides_real = [11, 8, 5]
			g.curve = [0.4, 0.5, 0.6]
			g.wander = [0.05, 0.05, 0.05]
			g.lift = [0.1, 0.1, 0.0]
			g.sag = [0.0, 0.0, 0.0]
			g.droop_sag = [0.0, 0.0, 0.0]
			g.sway = [0.16, 0.2, 0.22]
			g.tip_radius = [0.4, 0.3, 0.1]
			g.children = [7, 7, 0]
			g.child_length = [0.5, 0.45, 0.0]
			g.child_forward = 0.8
			g.child_side = 0.55
			g.child_up = 0.25
			g.child_radius = 0.7
			g.height = 9.0
			g.girth = 1.3
			g.taper = 0.75
			g.trunk_part = 0.55
			g.root_flare = 0.1
			g.column = -1.0
			g.trunk_sides = 14
			g.crown = 4.6
			g.aspect = 0.5
			g.limbs = 8
			g.limb_angle = 66.0
			g.limb_length = 1.2
			g.limb_thickness = 0.8
			g.needle_size = 1.0
			g.bark = Color(0.55, 0.45, 0.38)
			g.leaf = Color(0.38, 0.45, 0.16)
			g.leaf_tip = Color(0.55, 0.6, 0.25)
		_:
			g = _leafy(leafy)
	return g


static func _leafy(leafy: PlantSpecies) -> TreeGenome:
	return TreeGenome.from_species(leafy)


## A new random tree from the kinds above. `randomness` 0..1: how far traits stray from their kind
## (and how often two kinds are mixed); `exotic` 0..1: how often one trait is pushed somewhere
## unusual (tufts at the tips, a leader trunk with leaves, bare twigs). Returns the genome and, in
## `info`, what it was made of.
static func draw(rng: RandomNumberGenerator, leafy: PlantSpecies, conifer: PlantSpecies,
		randomness: float, exotic: float, info: Array) -> TreeGenome:
	var first := NAMES[rng.randi() % NAMES.size()]
	var g := make(first, leafy, conifer)
	var recipe := first
	if rng.randf() < 0.25 + 0.6 * randomness:
		var second := NAMES[rng.randi() % NAMES.size()]
		if second != first:
			var weight := rng.randf_range(0.2, 0.8)
			g = blend(g, make(second, leafy, conifer), weight, rng)
			recipe = "%s %.0f%% + %s %.0f%%" % [first, (1.0 - weight) * 100.0, second, weight * 100.0]
	_nudge(g, rng, 0.04 + 0.2 * randomness)
	if rng.randf() < exotic:
		recipe += " + " + _exotic(g, rng)
	_settle(g)
	info.clear()
	info.append(recipe)
	return g


## A new genome between `a` (weight 0) and `b` (weight 1): numbers are mixed, a choice or a flag is
## taken from one side or the other.
static func blend(a: TreeGenome, b: TreeGenome, weight: float, rng: RandomNumberGenerator) \
		-> TreeGenome:
	var out := TreeGenome.new()
	for info: Dictionary in a.get_property_list():
		if not (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key: String = info["name"]
		var from_a: Variant = a.get(key)
		var from_b: Variant = b.get(key)
		var pick_b := rng.randf() < weight
		match typeof(from_a):
			TYPE_FLOAT:
				out.set(key, lerpf(from_a, from_b, weight))
			TYPE_INT:
				out.set(key, (from_b if pick_b else from_a) if key in CHOICES
						else roundi(lerpf(float(from_a), float(from_b), weight)))
			TYPE_BOOL:
				out.set(key, from_b if pick_b else from_a)
			TYPE_COLOR:
				out.set(key, (from_a as Color).lerp(from_b, weight))
			TYPE_ARRAY:
				var mixed: Array = (from_a as Array).duplicate()
				for index in mixed.size():
					var low: Variant = (from_a as Array)[index]
					var high: Variant = (from_b as Array)[index]
					mixed[index] = (roundi(lerpf(float(low), float(high), weight))
							if typeof(low) == TYPE_INT else lerpf(low, high, weight))
				out.set(key, mixed)
	return out


## Every numeric trait moved a little (by `amount` of its range), the colours too.
static func _nudge(g: TreeGenome, rng: RandomNumberGenerator, amount: float) -> void:
	for key: String in RANGES:
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		var value: Variant = g.get(key)
		if value is Array:
			var arr: Array = value
			for index in arr.size():
				arr[index] = _moved(arr[index], low, high, rng, amount)
		else:
			g.set(key, _moved(value, low, high, rng, amount, key in PROPORTIONAL))
	g.leaf = Color.from_hsv(fposmod(g.leaf.h + rng.randf_range(-0.04, 0.04) * amount * 5.0, 1.0),
			clampf(g.leaf.s + rng.randf_range(-0.1, 0.1), 0.3, 0.9),
			clampf(g.leaf.v + rng.randf_range(-0.08, 0.08), 0.2, 0.7))
	g.leaf_tip = g.leaf.lightened(0.15)
	g.bark = g.bark.lightened(rng.randf_range(-0.08, 0.08))
	_vary_flowers(g, rng)


static func _moved(value: Variant, low: float, high: float, rng: RandomNumberGenerator,
		amount: float, proportional := false) -> Variant:
	if proportional:
		return clampf(float(value) * exp(rng.randf_range(-1.0, 1.0) * amount * 2.5), low, high)
	var moved := clampf(float(value) + rng.randf_range(-1.0, 1.0) * (high - low) * amount, low, high)
	return roundi(moved) if typeof(value) == TYPE_INT else moved


## Every flowering plant its own flowers: colour, petal count, flat or cupped, the middle.
static func _vary_flowers(g: TreeGenome, rng: RandomNumberGenerator) -> void:
	if g.flower.a > 0.0:
		g.flower = Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.9), rng.randf_range(0.8, 1.0))
		g.petals = rng.randi_range(4, 10)
		g.flower_cup = rng.randf() * rng.randf() * 1.0 # mostly open, now and then a tulip
		g.flower_size = g.flower_size * rng.randf_range(0.7, 1.5)
	if g.blossom.a > 0.0:
		g.blossom = Color.from_hsv(rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 0.6),
				rng.randf_range(0.85, 1.0))
		g.petals = rng.randi_range(4, 8)
		g.blossom_kind = rng.randi() % 3 as TreeGenome.Bloom
	g.flower_centre = [Color(0.9, 0.68, 0.1), Color(0.55, 0.35, 0.1), Color(0.95, 0.9, 0.7),
			Color(0.7, 0.2, 0.2)][rng.randi() % 4]


## One trait pushed somewhere unusual; returns what it did (for the label).
static func _exotic(g: TreeGenome, rng: RandomNumberGenerator) -> String:
	match rng.randi() % 7:
		6:
			g.blossom = Color.WHITE
			g.blossom_kind = rng.randi() % 3 as TreeGenome.Bloom
			return "in blossom"
		0:
			g.foliage = TreeGenome.Foliage.NEEDLE
			g.tips_only = true
			g.leader = false
			g.whorled = false
			return "tufts at the tips"
		1:
			g.leader = not g.leader
			g.whorled = g.leader
			return "trunk to the top" if g.leader else "forking trunk"
		2:
			g.leaf_shape = rng.randi() % 6 as PlantSpecies.LeafShape
			g.leaf_edge = rng.randi() % 3 as PlantSpecies.LeafEdge
			return "other leaves"
		3:
			g.leaf_density = rng.randf_range(0.2, 0.6)
			return "sparse leaves"
		4:
			g.limb_length = rng.randf_range(1.3, 1.9)
			g.crown = minf(g.crown * 1.3, 10.0)
			return "very wide"
		_:
			g.girth = minf(g.girth * rng.randf_range(1.5, 2.2), 2.6)
			g.root_flare = rng.randf_range(0.4, 0.9)
			return "very thick trunk"


## Makes the traits agree with each other after a blend or a nudge.
static func _settle(g: TreeGenome) -> void:
	if g.leader:
		g.whorled = true
		g.profile = TreeGenome.Profile.CONE
		if g.foliage == TreeGenome.Foliage.BLADE:
			g.nodes_spacing = maxf(g.nodes_spacing, 1.0) # single leaves are costly: few whorls
	if g.foliage == TreeGenome.Foliage.FROND:
		g.leader = false
		g.trunk_part = maxf(g.trunk_part, 0.9)
		g.frond_length = maxf(g.frond_length, g.height * 0.2)
	if g.leaf_shape == PlantSpecies.LeafShape.LOBED and g.leaf_lobes == 0:
		g.leaf_lobes = 2
	# branches never shorter than a share of the height, or they look stitched to the trunk
	g.crown = maxf(g.crown, g.height * (0.12 if g.leader else 0.1))
	g.limbs = clampi(g.limbs, 3, 10)
	g.depth = 3 if g.depth > 3 else maxi(g.depth, 2)
	g.nodes_from = clampf(g.nodes_from, 0.02, 0.9)
