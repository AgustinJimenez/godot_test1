class_name TreeGenome
extends RefCounted
## The traits of one tree: everything TreeGrower needs to grow it. Spruce and oak are not different
## kinds of thing, only different numbers: a conifer has one trunk to the top ("leader"), whorls of
## branches and sprays of needles; a leafy tree forks into limbs at the top of a shorter trunk and
## carries single leaves. Between them are all the mixed trees. For now a genome is read off a
## PlantSpecies (`from_species`); later it is drawn from archetypes (see AGENT_TASKS/042).

## How far a branch can reach at each height: a cone (long below, short above) or a dome (the limbs
## reach out and up to an envelope).
enum Profile { CONE, DOME }
## What a branch carries: single leaves along the last twigs, or sprays of needles at the ends.
enum Foliage { BLADE, NEEDLE }

# Trunk
var height := 8.0 ## metres (the grower varies it a little per tree)
var girth := 0.3 ## trunk radius at the foot
var taper := 0.6 ## top radius / foot radius of a trunk that ends in limbs
var lean := 0.0 ## the trunk's lean at the top, as a fraction of the height
var leader := false ## one trunk to the top, narrowing to a point, instead of forking into limbs
var trunk_part := 0.3 ## the bare part of the trunk, as a fraction of the height
var column := -1.0 ## a leader trunk's radius at the top, as a share of the foot's (-1: a cone)
var root_flare := 0.0 ## 0..1: the foot of the trunk widens into buttress roots (sequoia)
var stems := 1 ## trunks from one root (a birch clump, hazel): each a smaller tree leaning outward
var stem_spread := 0.25 ## how far the stems lean apart, as a fraction of the height
var trunk_sides := 14
var trunk_wobble := 0.05
var trunk_dark := 0.25 ## how much darker the foot of the trunk is
var marked_bark := false # dark patches on pale bark (birch)

# Where the branches leave the trunk
var profile := Profile.DOME
var crown := 2.0 ## crown radius
var aspect := 1.0 ## crown height / width (dome)
var droop := 0.0 ## 0..1: conifer branches hang more; leafy branches sag more
var whorled := false ## equal spacing round the trunk, each node turned against the one below
var limbs := 4 ## branches per node
var nodes_spacing := 0.0 ## metres between nodes up the trunk (0: a single node at the trunk top)
var nodes_from := 0.0 ## where the first node is, as a fraction of the height (spaced trees)
var limb_angle := 50.0 ## degrees from vertical the limbs leave at (dome)
var limb_length := 1.0 ## limbs reach this many times as far (a spreading oak, an umbrella crown)
var limb_thickness := 0.7 ## limb radius at its foot, as a share of the trunk's radius at the top

# Branches, by level (0 limb, 1 branch, 2 twig)
var depth := 3 ## levels of branching
var rings: Array[int] = [6, 5, 3] ## rings of the tube at each level (more = a rounder curve)
var sides: Array[int] = [11, 8, 5] ## sides, low-poly
var sides_real: Array[int] = [12, 10, 6] ## sides, realistic
var curve: Array[float] = [0.5, 0.8, 1.2] ## the most a branch bends over its length (radians)
var wander: Array[float] = [0.06, 0.08, 0.1] ## irregularity on top of the curve
var lift: Array[float] = [0.08, 0.05, 0.0] ## how much each ring reaches for the sky
var sag: Array[float] = [0.0, 0.04, 0.1] ## how much each ring sags
var droop_sag: Array[float] = [0.0, 0.14, 0.3] ## more sag per unit of `droop`
var sway: Array[float] = [0.16, 0.2, 0.22] ## wind weight added along a branch
var tip_radius: Array[float] = [0.4, 0.25, 0.05] ## radius at the end, as a share of the start
var children: Array[int] = [4, 4, 0] ## branches carried by a limb, a branch (last level: 0)
var child_radius := 0.6 ## a child's radius, as a share of its parent's where it leaves
var child_length: Array[float] = [0.55, 0.5, 0.0] ## and its length, as a share of the parent's
var child_length_a := 1.25 ## children further out are shorter: length * (a - b * position)
var child_length_b := 0.5
var children_from := 0.3 ## where along the parent the children are (first .. last)
var children_to := 0.85
var children_planar := false ## children leave alternately left and right (a fir), not spiralling
var child_forward := 0.4 ## the direction of a child: along the parent,
var child_side := 0.9 ## away from it,
var child_up := 0.25 ## and up
var carry_on := true ## the last child grows on from the tip (the branch never ends bare)
var bury := 0.4 ## how deep a child starts inside its parent, as a share of the parent's radius

# Foliage
var foliage := Foliage.BLADE
var leaf_shape := PlantSpecies.LeafShape.OVAL
var leaf_aspect := 1.8
var leaf_size := 0.2 ## leaf length as a fraction of the crown radius
var leaf_lobes := 0
var leaf_edge := PlantSpecies.LeafEdge.SMOOTH
var leaf_pattern := PlantSpecies.LeafPattern.ALTERNATE
var needle_size := 0.45 ## needle spray length as a fraction of the crown radius
var tips_only := false ## needle sprays only at the very ends of the branches: a tuft layer on top
var leaf_density := 1.0 ## 1 full; less: some twigs have no leaves, the others fewer (an old oak)

# Colours (sRGB)
var bark := Color(0.33, 0.23, 0.15)
var leaf := Color(0.26, 0.5, 0.18)
var leaf_tip := Color(0.4, 0.6, 0.25)
var frosted := false


## The genome of a leafy or conifer species, as the old builders drew them.
static func from_species(s: PlantSpecies) -> TreeGenome:
	var g := TreeGenome.new()
	g.height = s.height
	g.girth = s.girth
	g.bark = s.bark
	g.leaf = s.leaf
	g.leaf_tip = s.leaf_tip
	g.frosted = s.frosted
	g.crown = s.crown
	g.droop = s.droop
	g.trunk_part = s.bare
	if s.form == PlantSpecies.Form.CONIFER:
		_conifer(g, s)
	else:
		_leafy(g, s)
	return g


static func _leafy(g: TreeGenome, s: PlantSpecies) -> void:
	g.taper = s.taper
	g.lean = s.lean
	g.aspect = s.aspect
	g.marked_bark = s.marked_bark
	g.limbs = s.limb_count
	g.limb_angle = s.limb_angle
	g.leaf_shape = s.leaf_shape
	g.leaf_aspect = s.leaf_aspect
	g.leaf_size = s.leaf_size
	g.leaf_lobes = s.leaf_lobes
	g.leaf_edge = s.leaf_edge
	g.leaf_pattern = s.leaf_pattern


static func _conifer(g: TreeGenome, _s: PlantSpecies) -> void:
	g.leader = true
	g.profile = Profile.CONE
	g.whorled = true
	g.limbs = 5
	g.nodes_spacing = clampf(g.crown * 0.35, 0.5, 0.9)
	g.nodes_from = g.trunk_part * 0.75
	g.trunk_sides = 12
	g.trunk_wobble = 0.03
	g.trunk_dark = 0.3
	g.depth = 2
	g.rings = [3, 2, 0]
	g.sides = [5, 3, 0]
	g.sides_real = [7, 4, 0]
	g.curve = [0.0, 0.0, 0.0]
	g.wander = [0.08, 0.08, 0.0]
	g.lift = [0.275, 0.3, 0.0] # per ring: a branch turns up toward its tip
	g.sag = [0.0, 0.0, 0.0]
	g.droop_sag = [0.0, 0.0, 0.0]
	g.sway = [0.2, 0.25, 0.0]
	g.tip_radius = [0.18, 0.18, 0.0]
	g.children = [2, 0, 0]
	g.child_radius = 0.55
	g.child_length = [0.42, 0.0, 0.0]
	g.child_length_a = 1.15
	g.child_length_b = 0.6
	g.children_from = 0.3
	g.children_to = 0.9
	g.children_planar = true
	g.child_forward = 0.75
	g.child_side = 0.7
	g.child_up = -0.1
	g.carry_on = false
	g.foliage = Foliage.NEEDLE
	g.needle_size = 0.45
