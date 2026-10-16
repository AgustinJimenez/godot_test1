class_name TreeArchetypes
extends RefCounted
## Recognisable kinds of tree, each as a TreeGenome, and the random draw that makes new trees out of
## them: pick one or two kinds, blend their traits by a random weight, nudge every trait a little,
## now and then (exoticness) push a trait somewhere unusual. A draw is believable because the traits
## of a kind agree with each other (a baobab is thick AND short AND wide), which independent random
## sliders almost never manage. The world species generator and the lab share this table.

const NAMES: Array[String] = ["leafy", "conifer", "umbrella", "giant", "oak", "ancient", "dragon",
		"willow", "cypress", "bush"]

## Plausible range of each numeric trait: [min, max]. A draw never leaves it.
const RANGES := {
	"height": [0.8, 45.0], "girth": [0.02, 2.6], "taper": [0.25, 0.95], "lean": [0.0, 0.3],
	"trunk_part": [0.05, 0.8], "root_flare": [0.0, 1.0], "crown": [0.4, 14.0],
	"aspect": [0.4, 2.0], "droop": [0.0, 1.0], "limbs": [3, 10], "limb_angle": [15.0, 90.0],
	"limb_length": [0.5, 2.2], "limb_thickness": [0.3, 1.3], "nodes_spacing": [0.3, 2.0],
	"curve": [0.0, 1.4], "lift": [-0.1, 0.4], "sag": [0.0, 0.3], "tip_radius": [0.05, 0.8],
	"children": [1, 7], "child_radius": [0.3, 0.9], "child_length": [0.2, 0.9],
	"child_forward": [0.0, 1.5], "child_side": [0.0, 1.5], "child_up": [-0.5, 1.0],
	"leaf_aspect": [0.8, 5.0], "leaf_size": [0.08, 0.45], "needle_size": [0.2, 1.5],
	"leaf_density": [0.1, 1.0],
}
## Traits that are a choice from a list, not a number (blended by picking one side).
## Sizes that vary by proportion (a bush and a giant both change by a few percent, not by metres).
const PROPORTIONAL := ["height", "girth", "crown"]
const CHOICES := ["leaf_shape", "leaf_edge", "leaf_pattern", "foliage", "profile"]


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
			g.curve = [1.2, 1.2, 1.4]
			g.lift = [0.14, 0.05, 0.0]
			g.sag = [0.0, 0.03, 0.08]
			g.leaf_size = 0.14
		"ancient":
			g = make("oak", leafy, conifer)
			g.height = 14.0
			g.girth = 2.0
			g.taper = 0.78
			g.trunk_part = 0.3
			g.root_flare = 0.55
			g.crown = 4.4
			g.limb_length = 1.45
			g.limb_thickness = 0.9
			g.leaf_density = 0.45
			g.leaf_size = 0.15
			g.bark = Color(0.3, 0.26, 0.21)
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


static func _moved(value: Variant, low: float, high: float, rng: RandomNumberGenerator,
		amount: float, proportional := false) -> Variant:
	if proportional:
		return clampf(float(value) * exp(rng.randf_range(-1.0, 1.0) * amount * 2.5), low, high)
	var moved := clampf(float(value) + rng.randf_range(-1.0, 1.0) * (high - low) * amount, low, high)
	return roundi(moved) if typeof(value) == TYPE_INT else moved


## One trait pushed somewhere unusual; returns what it did (for the label).
static func _exotic(g: TreeGenome, rng: RandomNumberGenerator) -> String:
	match rng.randi() % 6:
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
	if g.leaf_shape == PlantSpecies.LeafShape.LOBED and g.leaf_lobes == 0:
		g.leaf_lobes = 2
	# branches never shorter than a share of the height, or they look stitched to the trunk
	g.crown = maxf(g.crown, g.height * (0.12 if g.leader else 0.1))
	g.limbs = clampi(g.limbs, 3, 10)
	g.depth = 3 if g.depth > 3 else maxi(g.depth, 2)
	g.nodes_from = clampf(g.nodes_from, 0.02, 0.9)
