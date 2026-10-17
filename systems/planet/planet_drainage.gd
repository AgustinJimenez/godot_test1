class_name PlanetDrainage
extends RefCounted
## Where the water of the planet runs, on a coarse grid of the cube sphere, from the crust and the
## rain (the climate's): the hollows are filled to where they would spill, and the rain of every
## cell runs down to the sea split between the lower neighbours (a multiple flow direction), so the
## rivers branch and wind instead of following a grid's eight directions. The heavy part is native
## (PlanetDrainageNative); this keeps the arrays and answers questions about them. It needs the
## native library: without it `build` returns false and nothing is made.
##
## This is the first step: the map of the flow. Cutting the valleys from it and drawing the water
## come after, from the same arrays.

var cells := 0 ## cells along an edge of a cube face
var dirs := PackedVector3Array() ## the middle of every cell
var heights := PackedFloat32Array() ## the crust there without the smallest hills (m above the sea)
var rain := PackedFloat32Array() ## the climate's rain there
var filled := PackedFloat32Array() ## the ground with its hollows filled up to where they spill (m)
var flow := PackedFloat32Array() ## the water that passes through the cell (rain x area)
var receiver := PackedInt32Array() ## the main cell it runs on to (-1: the sea)
var lake := PackedByteArray() ## 1 where the hollow is a lake
var land_cells := 0
var _native: Object


## Solves the drainage of the planet on `cells_per_edge` cells an edge. `exponent`: how much the
## steepest way is favoured (1 spreads the water over every way down, 4 and up gathers it).
func build(noise: PlanetNoise, cells_per_edge: int, exponent := 4.0) -> bool:
	if noise.native == null or not ClassDB.class_exists(&"PlanetDrainageNative"):
		return false
	cells = cells_per_edge
	_native = ClassDB.instantiate(&"PlanetDrainageNative")
	_native.call(&"setup", cells, noise.settings.radius, noise._cube_faces())
	dirs = _native.call(&"cell_dirs")
	heights = noise.native.call(&"macro_heights", dirs)
	rain.resize(dirs.size())
	for index in dirs.size():
		rain[index] = noise.climate.sample(dirs[index]).y
	var lake_depth := maxf(noise.relief * 0.015, 6.0) # a hollow this deep is a lake
	var solved: Dictionary = _native.call(&"solve", heights, rain, 0.0, exponent, lake_depth,
			maxi(cells / 16, 4))
	filled = solved["filled"]
	flow = solved["flow"]
	receiver = solved["receiver"]
	lake = solved["lake"]
	land_cells = 0
	for height in heights:
		land_cells += 1 if height >= 0.0 else 0
	return true


## The flow above which a land cell counts as a river: the `share` of land cells with the most.
func river_threshold(share: float) -> float:
	var land_flows := PackedFloat32Array()
	for index in flow.size():
		if heights[index] >= 0.0:
			land_flows.append(flow[index])
	land_flows.sort()
	if land_flows.is_empty():
		return INF
	var at := clampi(int(float(land_flows.size()) * (1.0 - share)), 0, land_flows.size() - 1)
	return land_flows[at]


## How deep each cell's river valley is cut (m): the bed of a river cell is no higher than the bed
## below it plus the slope its water allows (steep for a trickle, gentle for a big river), and the
## ground above is cut away, the valley a cell wider than the river. The cuts are what the crust
## subtracts (PlanetCrustNative.set_cut_field), after the flow was solved on the uncut ground.
func carve(relief: float) -> PackedFloat32Array:
	var river := river_threshold(0.06)
	return _native.call(&"carve", heights, filled, flow, receiver, river, 0.006, relief * 0.1)


## The cell that holds the unit direction `dir`.
func cell_of(dir: Vector3) -> int:
	return _native.call(&"cell_of", dir)


## The cells that hold many directions at once.
func cells_of(many: PackedVector3Array) -> PackedInt32Array:
	return _native.call(&"cells_of", many)


## Each cell's share of the sphere (1 on average).
func areas() -> PackedFloat32Array:
	return _native.call(&"cell_areas")
