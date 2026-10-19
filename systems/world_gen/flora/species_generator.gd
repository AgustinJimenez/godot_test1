class_name SpeciesGenerator
extends RefCounted
## Makes the species of a world from its seed: the same seed always gives the same list. Each growth
## form gets a share of the total (QUOTA); within a form the species are spread over the climate
## (stratified, so a world never ends up with five spruces for the same weather) and each draws its
## own shape numbers and colours. Nothing here touches meshes; PlantMeshes turns a species into one.

const F := PlantSpecies.Form ## short, for the tables below

## How many of each form a 36-species world has; other totals scale these shares.
const QUOTA := {
	F.CONIFER: 3, F.BROADLEAF: 4, F.PALM: 1, F.BARE_TREE: 1, F.SHRUB: 6,
	F.CACTUS: 2, F.GRASS: 4, F.TALL_GRASS: 2, F.REED: 2, F.FLOWER: 6, F.FERN: 3,
	F.MUSHROOM: 2,
}
## What a kind of tree is called (the name of a kind that has its own).
const KIND_NOUNS := {
	"umbrella": "Acacia", "dragon": "Dragon Tree", "raintree": "Rain Tree", "buttress": "Fig",
	"willow": "Willow", "cherry": "Cherry", "blossom": "Plum", "ancient": "Live Oak",
	"oak": "Oak", "cypress": "Cypress", "giant": "Redwood",
}
const NOUNS := {
	F.CONIFER: ["Spruce", "Fir", "Pine", "Cedar", "Hemlock", "Larch"],
	F.BROADLEAF: ["Oak", "Maple", "Beech", "Ash", "Elm", "Linden", "Poplar"],
	F.PALM: ["Palm", "Coconut Palm", "Fan Palm"],
	F.BARE_TREE: ["Snag", "Dead Tree", "Bare Tree"],
	F.SHRUB: ["Bush", "Hazel", "Bramble", "Juniper", "Broom", "Elder", "Holly", "Gorse"],
	F.CACTUS: ["Cactus", "Saguaro", "Barrel Cactus", "Prickly Pear"],
	F.GRASS: ["Grass", "Fescue", "Bluegrass", "Ryegrass", "Meadow Grass"],
	F.TALL_GRASS: ["Tallgrass", "Wheatgrass", "Pampas Grass", "Switchgrass"],
	F.REED: ["Reed", "Rush", "Cattail", "Sedge"],
	F.FLOWER: ["Daisy", "Buttercup", "Violet", "Poppy", "Cornflower", "Clover", "Aster", "Lupine",
			"Marigold"],
	F.FERN: ["Fern", "Bracken", "Shield Fern", "Lady Fern"],
	F.MUSHROOM: ["Toadstool", "Cap", "Bolete", "Puffball"],
}
const COLD := ["Northern", "Alpine", "Frost", "Boreal", "Snow"]
const HOT := ["Southern", "Sun", "Desert", "Dry"]
const WET := ["Marsh", "River", "Mist", "Bog", "Water"]
const PLAIN := ["Common", "Golden", "Silver", "Pale", "Dark", "Red", "Old", "Wild", "Little",
		"Great", "Mountain", "Meadow", "Woodland"]


## The species of the world with this seed; `count` is the total (36 by default in WorldSettings).
static func generate(world_seed: int, count: int) -> Array[PlantSpecies]:
	var quotas := _quotas(count)
	var made: Array[PlantSpecies] = []
	var used := {}
	for form: int in QUOTA.keys():
		var share: int = quotas[form]
		for index in share:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(world_seed, form + 11, index + 3))
			var species := PlantSpecies.new()
			species.form = form as PlantSpecies.Form
			species.id = made.size() + 1
			species.seed = rng.randi()
			# the first axis spreads the species of a form over the climate
			var spread := (float(index) + rng.randf()) / float(share)
			_niche(species, rng, spread)
			_shape(species, rng)
			_archetype(species)
			_name(species, rng, index, used)
			_leaves(species)
			_fit_size(species)
			species.patch_offset = Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0))
			made.append(species)
	return made


## Shares of `count` by QUOTA (largest remainder, so the shares always add up to `count`).
static func _quotas(count: int) -> Dictionary:
	var total := 0
	for form: int in QUOTA.keys():
		total += QUOTA[form] as int
	var shares := {}
	var remainders: Array[Vector2] = []
	var given := 0
	for form: int in QUOTA.keys():
		var exact := float(QUOTA[form] as int) * float(count) / float(total)
		shares[form] = int(exact)
		given += int(exact)
		remainders.append(Vector2(exact - floorf(exact), form))
	remainders.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	for index in maxi(count - given, 0):
		shares[int(remainders[index % remainders.size()].y)] += 1
	return shares


## Where it grows. `t` (0..1) spreads the species of one form along the form's main climate axis.
static func _niche(s: PlantSpecies, rng: RandomNumberGenerator, t: float) -> void:
	match s.form:
		F.CONIFER:
			s.heat = lerpf(0.12, 0.55, t)
			s.heat_tol = rng.randf_range(0.14, 0.22)
			s.moisture = rng.randf_range(0.4, 0.85)
			s.moisture_tol = rng.randf_range(0.22, 0.35)
			s.above_min = 2.0
			s.above_max = 70.0
			s.slope_max = 0.58
			s.density = 0.3 + 0.5 * clampf(t * 1.5, 0.0, 1.0)
			s.patch_freq = rng.randf_range(1.4, 2.2)
			s.patch_strength = rng.randf_range(0.0, 0.3)
		F.BROADLEAF:
			s.moisture = lerpf(0.35, 0.92, t)
			s.moisture_tol = rng.randf_range(0.22, 0.32)
			s.heat = rng.randf_range(0.42, 0.8)
			s.heat_tol = rng.randf_range(0.16, 0.26)
			s.above_min = 2.0
			s.above_max = 45.0
			s.slope_max = 0.55
			s.density = lerpf(0.2, 0.85, t)
			s.patch_freq = rng.randf_range(1.4, 2.2)
			s.patch_strength = rng.randf_range(0.0, 0.35)
		F.PALM:
			s.heat = rng.randf_range(0.65, 0.8)
			s.heat_tol = 0.2
			s.moisture = 0.4
			s.moisture_tol = 0.6
			s.above_min = 0.9
			s.above_max = 3.6
			s.slope_max = 0.4
			s.density = 0.2
		F.BARE_TREE:
			s.heat = 0.5
			s.heat_tol = 0.55
			s.moisture = rng.randf_range(0.3, 0.6)
			s.moisture_tol = 0.7
			s.above_min = 1.0
			s.above_max = 70.0
			s.slope_max = 0.58
			s.density = 0.07
			s.patch_freq = 2.0
			s.patch_strength = 0.4
		F.SHRUB:
			s.moisture = lerpf(0.3, 0.9, t)
			s.moisture_tol = rng.randf_range(0.2, 0.32)
			s.heat = rng.randf_range(0.3, 0.8)
			s.heat_tol = rng.randf_range(0.2, 0.35)
			s.above_min = 1.5
			s.above_max = 55.0
			s.slope_max = 0.5
			s.density = lerpf(0.14, 0.4, t)
			s.patch_freq = rng.randf_range(1.6, 2.6)
			s.patch_strength = rng.randf_range(0.0, 0.4)
		F.CACTUS:
			s.heat = rng.randf_range(0.62, 0.95)
			s.heat_tol = 0.25
			s.moisture = lerpf(0.02, 0.3, t)
			s.moisture_tol = 0.2
			s.above_min = 2.0
			s.above_max = 40.0
			s.slope_max = 0.5
			s.density = rng.randf_range(0.14, 0.24)
		F.GRASS:
			s.moisture = lerpf(0.25, 0.9, t)
			s.moisture_tol = rng.randf_range(0.25, 0.36)
			s.heat = rng.randf_range(0.35, 0.75)
			s.heat_tol = rng.randf_range(0.3, 0.45)
			s.above_min = 1.4
			s.above_max = rng.randf_range(28.0, 46.0)
			s.slope_max = 0.55
			s.density = lerpf(0.3, 0.95, smoothstep(0.0, 0.7, t))
			s.patch_freq = rng.randf_range(0.8, 1.6)
			s.patch_strength = rng.randf_range(0.2, 0.5)
		F.TALL_GRASS:
			s.moisture = lerpf(0.32, 0.7, t)
			s.moisture_tol = 0.25
			s.heat = rng.randf_range(0.4, 0.75)
			s.heat_tol = 0.3
			s.above_min = 1.5
			s.above_max = 35.0
			s.slope_max = 0.5
			s.density = rng.randf_range(0.4, 0.55)
			s.patch_freq = rng.randf_range(1.6, 2.2)
			s.patch_strength = 0.9
		F.REED:
			s.moisture = lerpf(0.6, 1.0, t)
			s.moisture_tol = 0.4
			s.heat = rng.randf_range(0.3, 0.8)
			s.heat_tol = 0.4
			s.above_min = 0.9
			s.above_max = 3.4
			s.slope_max = 0.5
			s.density = rng.randf_range(0.5, 0.7)
			s.patch_freq = 1.5
			s.patch_strength = 0.3
		F.FLOWER:
			s.moisture = lerpf(0.3, 0.85, t)
			s.moisture_tol = rng.randf_range(0.2, 0.3)
			s.heat = rng.randf_range(0.35, 0.8)
			s.heat_tol = rng.randf_range(0.2, 0.3)
			s.above_min = 1.5
			s.above_max = 32.0
			s.slope_max = 0.4
			s.density = rng.randf_range(0.5, 0.75)
			s.patch_freq = rng.randf_range(2.0, 3.0)
			s.patch_strength = rng.randf_range(0.75, 0.9)
		F.FERN:
			s.moisture = lerpf(0.55, 1.0, t)
			s.moisture_tol = 0.25
			s.heat = rng.randf_range(0.3, 0.7)
			s.heat_tol = 0.25
			s.above_min = 1.5
			s.above_max = 45.0
			s.slope_max = 0.5
			s.density = rng.randf_range(0.25, 0.42)
			s.patch_freq = rng.randf_range(1.2, 2.0)
			s.patch_strength = 0.3
		F.MUSHROOM:
			s.moisture = lerpf(0.55, 1.0, t)
			s.moisture_tol = 0.25
			s.heat = rng.randf_range(0.3, 0.7)
			s.heat_tol = 0.3
			s.above_min = 1.2
			s.above_max = 40.0
			s.slope_max = 0.5
			s.density = rng.randf_range(0.1, 0.2)
			s.patch_freq = rng.randf_range(2.0, 3.0)
			s.patch_strength = 0.7


## What it looks like: sizes, counts, colours.
static func _shape(s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	match s.form:
		F.CONIFER:
			var slender := rng.randf() # 0 broad, 1 tall and narrow
			s.height = lerpf(6.5, 13.0, slender) * rng.randf_range(0.9, 1.1)
			s.crown = lerpf(2.7, 1.1, slender) * rng.randf_range(0.9, 1.1)
			s.count = int(lerpf(4.0, 8.0, slender)) + rng.randi_range(0, 1)
			s.girth = rng.randf_range(0.2, 0.38)
			s.bare = rng.randf_range(0.14, 0.26)
			s.droop = rng.randf_range(0.2, 0.9)
			s.wobble = rng.randf_range(0.1, 0.22)
			s.bark = _rhsv(rng, 0.05, 0.08, 0.5, 0.65, 0.2, 0.34)
			s.leaf = _hsv(rng.randf_range(0.33, 0.47), rng.randf_range(0.55, 0.75),
					rng.randf_range(0.22, 0.36))
			s.leaf_tip = s.leaf.lightened(rng.randf_range(0.12, 0.22))
			s.frosted = s.heat < 0.3
			s.variants = 3
		F.BROADLEAF:
			s.height = rng.randf_range(6.0, 11.0)
			s.aspect = rng.randf_range(0.65, 1.5)
			s.crown = minf(rng.randf_range(1.5, 3.0) / sqrt(s.aspect), s.height * 0.38)
			s.bare = rng.randf_range(0.28, 0.5)
			s.girth = rng.randf_range(0.2, 0.45)
			s.taper = rng.randf_range(0.5, 0.72)
			s.count = rng.randi_range(3, 6)
			s.extra = rng.randi_range(0, 3) # forked branches under the crown
			s.droop = 0.0 if s.moisture < 0.75 or rng.randf() < 0.6 else rng.randf_range(0.5, 0.9)
			s.lean = rng.randf_range(0.0, 0.1)
			s.wobble = rng.randf_range(0.15, 0.26)
			s.marked_bark = rng.randf() < 0.25
			s.bark = (Color(0.86, 0.85, 0.8) if s.marked_bark
					else _rhsv(rng, 0.06, 0.1, 0.35, 0.6, 0.25, 0.42))
			if s.marked_bark: # a birch: slim, tall, pale, never weeping
				s.girth *= 0.6
				s.height = rng.randf_range(6.0, 9.0)
				s.crown *= 0.75
				s.bare = rng.randf_range(0.45, 0.6)
				s.aspect = rng.randf_range(1.0, 1.4)
				s.droop = 0.0
			if rng.randf() < 0.18: # a species that is gold or red on its own
				s.leaf = _rhsv(rng, 0.02, 0.13, 0.7, 0.9, 0.65, 0.8)
			else:
				s.leaf = _rhsv(rng, 0.17, 0.34, 0.5, 0.72, 0.38, 0.55)
			s.leaf_tip = s.leaf.lightened(rng.randf_range(0.1, 0.2))
			s.variants = 3
		F.PALM:
			s.height = rng.randf_range(4.5, 8.0)
			s.crown = rng.randf_range(2.0, 3.2)
			s.count = rng.randi_range(7, 10)
			s.girth = rng.randf_range(0.17, 0.26)
			s.lean = rng.randf_range(0.1, 0.18)
			s.bark = _rhsv(rng, 0.07, 0.1, 0.4, 0.55, 0.42, 0.55)
			s.leaf = _rhsv(rng, 0.27, 0.36, 0.6, 0.75, 0.4, 0.55)
			s.leaf_tip = s.leaf.lightened(0.15)
			s.variants = 3
		F.BARE_TREE:
			s.height = rng.randf_range(3.2, 6.0)
			s.count = rng.randi_range(3, 6)
			s.girth = rng.randf_range(0.22, 0.34)
			s.bark = _rhsv(rng, 0.07, 0.1, 0.1, 0.22, 0.3, 0.45)
			s.variants = 3
		F.SHRUB:
			s.height = rng.randf_range(0.8, 1.5)
			s.crown = rng.randf_range(0.5, 0.95)
			s.count = rng.randi_range(2, 4)
			s.wobble = rng.randf_range(0.2, 0.3)
			s.leaf = _rhsv(rng, 0.17, 0.36, 0.5, 0.75, 0.3, 0.5)
			s.leaf_tip = s.leaf.lightened(rng.randf_range(0.08, 0.16))
			if rng.randf() < 0.55: # berries or blossom
				s.extra = rng.randi_range(5, 11)
				s.accent = _bright(rng)
			s.variants = 3
		F.CACTUS:
			var barrel := rng.randf() < 0.4
			s.height = rng.randf_range(0.5, 0.9) if barrel else rng.randf_range(1.8, 3.0)
			s.girth = rng.randf_range(0.3, 0.45) if barrel else rng.randf_range(0.2, 0.3)
			s.count = 1 if barrel else 0 # 1: barrel
			s.extra = 0 if barrel else rng.randi_range(0, 3) # arms
			s.leaf = _rhsv(rng, 0.3, 0.42, 0.35, 0.55, 0.38, 0.52)
			s.leaf_tip = s.leaf.lightened(0.06)
			s.accent = _hsv(rng.randf_range(0.9, 1.0), rng.randf_range(0.5, 0.8), 0.95)
			s.variants = 2
		F.GRASS:
			s.height = rng.randf_range(0.3, 0.8)
			s.girth = rng.randf_range(0.022, 0.038) # slim blades: a real blade is a few millimetres wide
			s.count = rng.randi_range(13, 20) # a clump has many
			s.droop = rng.randf_range(0.1, 0.55)
			var golden := rng.randf() < 0.2
			s.leaf = _rhsv(rng, 0.2, 0.3, 0.5, 0.7, 0.5, 0.64)
			s.leaf_tip = (_rhsv(rng, 0.11, 0.16, 0.5, 0.65, 0.75, 0.88)
					if golden else _rhsv(rng, 0.16, 0.25, 0.5, 0.65, 0.65, 0.8))
			s.variants = 2
		F.TALL_GRASS:
			s.height = rng.randf_range(0.9, 1.6)
			s.girth = rng.randf_range(0.035, 0.05)
			s.count = rng.randi_range(8, 11)
			s.droop = rng.randf_range(0.2, 0.4)
			s.extra = rng.randi_range(0, 1) # seed heads
			s.accent = _rhsv(rng, 0.08, 0.14, 0.4, 0.6, 0.65, 0.8)
			s.leaf = _rhsv(rng, 0.2, 0.28, 0.6, 0.75, 0.4, 0.5)
			s.leaf_tip = _rhsv(rng, 0.12, 0.2, 0.45, 0.6, 0.7, 0.85)
			s.variants = 2
		F.REED:
			s.height = rng.randf_range(1.0, 2.0)
			s.girth = rng.randf_range(0.03, 0.045)
			s.count = rng.randi_range(6, 9)
			s.droop = rng.randf_range(0.05, 0.2)
			s.extra = rng.randi_range(0, 1) # cattail heads
			s.accent = _hsv(rng.randf_range(0.06, 0.09), 0.6, rng.randf_range(0.25, 0.35))
			s.leaf = _rhsv(rng, 0.2, 0.26, 0.5, 0.65, 0.38, 0.48)
			s.leaf_tip = _rhsv(rng, 0.14, 0.2, 0.4, 0.55, 0.65, 0.78)
			s.variants = 2
		F.FLOWER:
			s.height = rng.randf_range(0.3, 0.7)
			s.crown = rng.randf_range(0.09, 0.16)
			s.count = rng.randi_range(4, 9)
			s.extra = rng.randi_range(1, 3) # stems in a clump
			s.accent = _bright(rng)
			s.leaf = _rhsv(rng, 0.24, 0.32, 0.6, 0.75, 0.42, 0.55)
			s.leaf_tip = s.leaf.lightened(0.12)
			s.variants = 2
		F.FERN:
			s.height = rng.randf_range(0.3, 0.55)
			s.crown = rng.randf_range(0.6, 1.3)
			s.count = rng.randi_range(5, 9)
			s.droop = rng.randf_range(0.2, 0.6)
			s.leaf = _rhsv(rng, 0.26, 0.36, 0.5, 0.72, 0.24, 0.42)
			s.leaf_tip = s.leaf.lightened(0.15)
			s.variants = 2
		F.MUSHROOM:
			s.height = rng.randf_range(0.1, 0.3)
			s.crown = rng.randf_range(0.9, 1.3) # cap radius per stalk height
			s.count = rng.randi_range(1, 4)
			s.droop = rng.randf_range(0.3, 0.9) # 0 flat cap .. 1 tall dome
			s.accent = [Color(0.82, 0.18, 0.15), Color(0.62, 0.42, 0.25), Color(0.9, 0.78, 0.55),
					Color(0.85, 0.5, 0.2), Color(0.55, 0.35, 0.6)][rng.randi() % 5]
			s.variants = 2
	s.size_spread = 0.2 if s.is_tree() else 0.3


## The kind of tree a species is (TreeArchetypes), from its climate: the dry heat grows flat-topped
## acacias and cacti, the wet heat rain trees and buttressed figs, a wet bank willows, the cold
## spruces. Its own dice, so nothing else of the species (or of the world) changes.
static func _archetype(s: PlantSpecies) -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = s.seed ^ 0xA2C4
	var hot := s.heat > 0.6
	var wet := s.moisture > 0.6
	var weights := {}
	match s.form:
		F.BROADLEAF:
			if s.marked_bark:
				weights = {"leafy": 1.0} # a birch
			elif s.droop > 0.4:
				weights = {"willow": 1.0}
			else:
				weights = {
					"leafy": 3.0, "oak": 2.0 if s.moisture > 0.4 else 0.5,
					"umbrella": 3.0 if hot and not wet else 0.2,
					"dragon": 1.0 if hot and s.moisture < 0.4 else 0.0,
					"raintree": 3.0 if hot and wet else 0.0,
					"buttress": 2.0 if hot and s.moisture > 0.7 else 0.0,
					"cherry": 1.0 if not hot else 0.0, "blossom": 1.0 if not hot else 0.0,
					"ancient": 0.3 if s.moisture > 0.5 else 0.0,
				}
		F.CONIFER:
			weights = {"conifer": 4.0,
					"cypress": 3.0 if s.heat > 0.4 else 0.0,
					"giant": 0.25 if s.moisture > 0.7 else 0.0}
		F.PALM:
			weights = {"palm": 1.0}
		F.BARE_TREE:
			weights = {"dead": 1.0}
		F.SHRUB:
			weights = {"shrub": 3.0, "bush": 1.5}
		F.CACTUS:
			weights = {"cactus": 1.0}
		F.GRASS:
			weights = {"grass": 3.0, "meadow": 1.0, "lawn": 2.0 if s.moisture > 0.65 else 0.0,
					"tussock": 2.0 if s.moisture < 0.45 else 0.0}
		F.TALL_GRASS:
			weights = {"meadow": 3.0, "pampas": 2.0, "tussock": 1.0}
		F.REED:
			weights = {"reed": 1.0}
		F.FLOWER:
			weights = {"wildflower": 1.0}
		F.FERN:
			weights = {"fern": 1.0}
		_:
			return
	var total := 0.0
	for weight: float in weights.values():
		total += weight
	var roll := dice.randf() * total
	for kind: String in weights:
		roll -= weights[kind] as float
		if roll <= 0.0 and weights[kind] as float > 0.0:
			s.archetype = kind
			return
	s.archetype = weights.keys()[0]


## A tree's size is its kind's, so the collider and the scatter read the real numbers.
static func _fit_size(s: PlantSpecies) -> void:
	if s.archetype == "" or not s.is_tree():
		return
	var g := TreeArchetypes.for_species(s)
	s.height = g.height
	s.girth = g.girth
	s.crown = g.crown


## The leaf and the branching of a broadleaf tree, from the kind of tree its name says (a birch has
## small diamond leaves, a willow long narrow ones). Its own dice, so nothing else of the species
## (or of the world) changes when this is tuned.
static func _leaves(s: PlantSpecies) -> void:
	if s.form != F.BROADLEAF:
		return
	var dice := RandomNumberGenerator.new()
	dice.seed = s.seed ^ 0x1EAF
	var noun: String = s.common_name.get_slice(" ", s.common_name.get_slice_count(" ") - 1)
	apply_leaf_traits(s, noun, dice)


## The leaf and branching traits of a broadleaf species for the kind of tree `noun` (Oak, Maple,
## Beech, Elm, Ash, Linden, Poplar, Birch or Willow). Public so a lab can try any kind.
static func apply_leaf_traits(s: PlantSpecies, noun: String, dice: RandomNumberGenerator) -> void:
	s.limb_count = dice.randi_range(4, 5)
	match noun:
		"Oak":
			_leaf(s, PlantSpecies.LeafShape.LOBED, dice, 1.7, 0.2, 3, 62.0)
		"Maple":
			_leaf(s, PlantSpecies.LeafShape.PALMATE, dice, 1.0, 0.17, 2, 50.0)
		"Beech":
			_leaf(s, PlantSpecies.LeafShape.OVAL, dice, 1.8, 0.2, 0, 52.0)
		"Elm":
			_leaf(s, PlantSpecies.LeafShape.OVAL, dice, 1.6, 0.19, 0, 38.0)
		"Ash":
			_leaf(s, PlantSpecies.LeafShape.LANCEOLATE, dice, 3.4, 0.2, 0, 44.0)
		"Linden":
			_leaf(s, PlantSpecies.LeafShape.HEART, dice, 1.1, 0.22, 0, 48.0)
		"Poplar":
			_leaf(s, PlantSpecies.LeafShape.DIAMOND, dice, 1.2, 0.18, 0, 26.0)
		"Birch":
			_leaf(s, PlantSpecies.LeafShape.DIAMOND, dice, 1.3, 0.15, 0, 30.0)
		"Willow":
			_leaf(s, PlantSpecies.LeafShape.LANCEOLATE, dice, 4.5, 0.17, 0, 58.0)
			s.droop = maxf(s.droop, 0.7) # a willow weeps
		_:
			_leaf(s, PlantSpecies.LeafShape.OVAL, dice, 1.8, 0.2, 0, 50.0)
	s.leaf_edge = PlantSpecies.LeafEdge.SMOOTH
	if noun in ["Elm", "Birch", "Poplar", "Linden"]:
		s.leaf_edge = PlantSpecies.LeafEdge.SERRATED
	elif noun in ["Beech", "Willow"]:
		s.leaf_edge = PlantSpecies.LeafEdge.WAVY
	s.leaf_pattern = (PlantSpecies.LeafPattern.OPPOSITE if noun == "Maple" or noun == "Ash"
			else (PlantSpecies.LeafPattern.SPIRAL if noun == "Willow"
			else PlantSpecies.LeafPattern.ALTERNATE))


static func _leaf(s: PlantSpecies, shape: PlantSpecies.LeafShape, dice: RandomNumberGenerator,
		aspect: float, size: float, lobes: int, angle: float) -> void:
	s.leaf_shape = shape
	s.leaf_aspect = aspect * dice.randf_range(0.88, 1.14)
	s.leaf_size = size * dice.randf_range(0.9, 1.12)
	s.leaf_lobes = lobes
	s.limb_angle = angle * dice.randf_range(0.9, 1.1)


static func _name(s: PlantSpecies, rng: RandomNumberGenerator, index: int,
		used: Dictionary) -> void:
	var nouns: Array = NOUNS[s.form]
	var noun: String = nouns[(index * 2 + rng.randi()) % nouns.size()]
	if KIND_NOUNS.has(s.archetype):
		noun = KIND_NOUNS[s.archetype]
	elif s.form == F.BROADLEAF and s.marked_bark: # the shape picks these two names
		noun = "Birch"
	elif s.form == F.BROADLEAF and s.droop > 0.4:
		noun = "Willow"
	var adjectives := PLAIN
	if s.heat < 0.3:
		adjectives = COLD
	elif s.moisture > 0.78 and s.above_max < 5.0:
		adjectives = WET
	elif s.heat > 0.65 and s.moisture < 0.4:
		adjectives = HOT
	var full := ""
	for attempt in 12:
		full = "%s %s" % [adjectives[rng.randi() % adjectives.size()], noun]
		if not used.has(full):
			break
	if used.has(full): # out of fresh names: number it
		var number := 2
		while used.has("%s %d" % [full, number]):
			number += 1
		full = "%s %d" % [full, number]
	used[full] = true
	s.common_name = full


## A colour with hue, saturation and value each drawn from a range.
static func _rhsv(rng: RandomNumberGenerator, hue_from: float, hue_to: float, sat_from: float,
		sat_to: float, val_from: float, val_to: float) -> Color:
	return _hsv(rng.randf_range(hue_from, hue_to), rng.randf_range(sat_from, sat_to),
			rng.randf_range(val_from, val_to))


static func _hsv(hue: float, saturation: float, value: float) -> Color:
	return Color.from_hsv(fposmod(hue, 1.0), clampf(saturation, 0.0, 1.0), clampf(value, 0.0, 1.0))


## A flower or berry colour: anywhere on the wheel except the greens.
static func _bright(rng: RandomNumberGenerator) -> Color:
	var hue := rng.randf()
	while hue > 0.2 and hue < 0.45:
		hue = rng.randf()
	return _hsv(hue, rng.randf_range(0.55, 0.95), rng.randf_range(0.8, 1.0))
