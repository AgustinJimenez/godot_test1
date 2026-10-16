class_name PlantSpecies
extends RefCounted
## One species of plant in one world: every number that decides what its plants look like and where
## they grow. SpeciesGenerator makes them from the world seed and nothing edits them afterwards, so
## any thread may read them. `form` picks the mesh builder; the shape numbers below are read by
## that builder (what each means per form is noted next to the field); the niche numbers say where
## it grows.

enum Form {
	CONIFER, BROADLEAF, PALM, BARE_TREE, SHRUB, CACTUS, GRASS, TALL_GRASS, REED, FLOWER, FERN,
	MUSHROOM,
}
## The outline of one leaf of a broadleaf tree (see PlantLeafShapes).
enum LeafShape { OVAL, LOBED, PALMATE, HEART, LANCEOLATE, DIAMOND }
## The edge of a leaf (the realistic look draws it; low-poly leaves keep a clean edge).
enum LeafEdge { SMOOTH, SERRATED, WAVY }
## How leaves sit along a twig: one per node on alternating sides, two opposite, or in a spiral.
enum LeafPattern { ALTERNATE, OPPOSITE, SPIRAL }
## Plants are scattered one layer at a time, each on its own grid spacing.
enum Layer { CANOPY, UNDERSTORY, GRASS, MEADOW, COVER }

const LAYER_OF := {
	Form.CONIFER: Layer.CANOPY, Form.BROADLEAF: Layer.CANOPY, Form.PALM: Layer.CANOPY,
	Form.BARE_TREE: Layer.CANOPY, Form.SHRUB: Layer.UNDERSTORY, Form.CACTUS: Layer.UNDERSTORY,
	Form.GRASS: Layer.GRASS, Form.REED: Layer.GRASS, Form.FLOWER: Layer.MEADOW,
	Form.TALL_GRASS: Layer.COVER, Form.FERN: Layer.COVER, Form.MUSHROOM: Layer.COVER,
}

var id := 0 ## 1.. in generation order; stable for a seed
var common_name := ""
var form := Form.BROADLEAF
var seed := 0 ## the dice of its meshes
var variants := 3 ## how many different meshes it makes
var archetype := "" ## the kind of tree it is (TreeArchetypes.NAMES), picked by its climate; "" none

# Shape. Metres at scale 1.
var height := 8.0 ## whole plant (grass: blade length, mushroom: cap stalk)
var girth := 0.3 ## trunk radius at the base (grass: blade half width)
var crown := 2.0 ## crown radius (palm: frond length, shrub: lump size, flower: petal length)
var aspect := 1.0 ## broadleaf crown height / width (tall narrow .. low spreading)
var bare := 0.3 ## fraction of the height that is bare trunk
var taper := 0.6 ## top trunk radius / base radius
var count := 5 ## tiers, crown lumps, fronds, blades, petals or caps, by form
var extra := 0 ## berries, arms, stems per clump, seed heads: by form
var droop := 0.3 ## weeping crowns, bending blades and fronds
var lean := 0.0 ## trunk lean as a fraction of the height
var wobble := 0.12 ## how irregular the mesh is
var size_spread := 0.25 ## +- size difference between individuals
var marked_bark := false ## dark patches on pale bark
var frosted := false ## white snow on the leaves (cold species)

# Broadleaf crown: branches and single leaves (PlantCrownBuilders).
var leaf_shape := LeafShape.OVAL
var leaf_pattern := LeafPattern.ALTERNATE
var leaf_aspect := 1.8 ## leaf length / leaf width
var leaf_size := 0.2 ## leaf length as a fraction of the crown radius
var leaf_lobes := 0 ## lobes per side (lobed leaves)
var leaf_edge := LeafEdge.SMOOTH
var limb_count := 4 ## main limbs leaving the trunk top
var limb_angle := 50.0 ## degrees from vertical the limbs leave at (small: upright, wide: spreading)

# Colours (sRGB, like the old palette).
var leaf := Color(0.26, 0.5, 0.18)
var leaf_tip := Color(0.4, 0.6, 0.25)
var bark := Color(0.33, 0.23, 0.15)
var accent := Color.WHITE ## flowers, berries, caps, seed heads

# Niche: where it grows. 0..1 moisture and heat (TerrainNoise), metres above the local water level.
var moisture := 0.5
var moisture_tol := 0.3
var heat := 0.5
var heat_tol := 0.3
var above_min := 1.5
var above_max := 60.0
var slope_max := 0.5
var density := 0.5 ## chance a spot is planted where the fit is perfect
var patch_freq := 0.05 ## 1 / metres of the clumps it grows in
var patch_strength := 0.0 ## 0 even .. 1 only inside the clumps
var patch_offset := Vector2.ZERO ## decorrelates one species' clumps from the next


func layer() -> Layer:
	return LAYER_OF[form]


func is_tree() -> bool:
	return layer() == Layer.CANOPY


## 0 where it cannot live .. 1 at its ideal spot.
func fitness(wet: float, warm: float, above: float, steep: float) -> float:
	if above < above_min - 0.5 or above > above_max or steep > slope_max:
		return 0.0
	var dry := (wet - moisture) / moisture_tol
	var cold := (warm - heat) / heat_tol
	var off := dry * dry + cold * cold
	if off > 6.0:
		return 0.0 # exp(-6) is nothing: skip the rest of the maths for plants far out of their climate
	var edge := smoothstep(above_min - 0.5, above_min + 0.5, above) \
			* (1.0 - smoothstep(above_max - 4.0, above_max, above)) \
			* (1.0 - smoothstep(slope_max - 0.12, slope_max, steep))
	return exp(-off) * edge


## Radius and height of the trunk collider; Vector2.ZERO when walking through it is fine.
func footprint() -> Vector2:
	match form:
		Form.CONIFER, Form.BROADLEAF, Form.PALM, Form.BARE_TREE:
			return Vector2(maxf(girth * 0.9, 0.18), clampf(height * 0.6, 1.5, 4.0))
		Form.CACTUS:
			return Vector2(maxf(girth, 0.2), minf(height, 2.5))
		_:
			return Vector2.ZERO


func summary() -> String:
	return "#%02d %-9s %-22s h=%4.1f  wet %.2f+-%.2f  heat %.2f+-%.2f  above %.1f..%.0f  dens %.2f" % [
			id, Form.keys()[form], common_name, height, moisture, moisture_tol, heat, heat_tol,
			above_min, above_max, density]
