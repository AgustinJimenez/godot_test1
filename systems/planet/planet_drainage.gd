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
var uplift := PackedFloat32Array() ## 0..1 how far the plates have raised the ground there
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
	var raised: PackedFloat32Array = noise.native.call(&"tectonic_heights", dirs)
	uplift.resize(dirs.size())
	for index in dirs.size():
		uplift[index] = clampf((raised[index] - noise._sea) / 0.4, 0.0, 1.0)
	rain = _native.call(&"sample_grid", noise.climate.rain_grid(), PlanetClimate.WIDTH,
			PlanetClimate.HEIGHT, dirs)
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


## The rivers as curves for the crust to cut its valleys along: every river cell sends a smooth,
## winding curve to the cell its water runs on to (10 pieces, a meander of 6 % of the way), each
## piece with its bed height (from the sea inland, no higher than the bed below plus the slope its
## water allows: steep for a trickle, gentle for a big river) and its flow. The crust
## (PlanetCrustNative.set_rivers) lets the ground stand no higher than the nearest piece's bed and
## the sides the valley allows, so the valleys are lines that follow the flow.
func network() -> Dictionary:
	var river := river_threshold(0.06)
	return _native.call(&"river_network", heights, filled, flow, receiver, river, 0.006, 10, 0.06,
			uplift)


## The cell that holds the unit direction `dir`.
func cell_of(dir: Vector3) -> int:
	return _native.call(&"cell_of", dir)


## The cells that hold many directions at once.
func cells_of(many: PackedVector3Array) -> PackedInt32Array:
	return _native.call(&"cells_of", many)


## Each cell's share of the sphere (1 on average).
func areas() -> PackedFloat32Array:
	return _native.call(&"cell_areas")


## A flat map of the drainage: the sea blue by depth, the land by height, the lakes cyan and the
## rivers drawn bluer the more water they carry.
func picture(view: PackedFloat64Array, threshold: float) -> Image:
	var width := 1024
	var height := 512
	var directions := PackedVector3Array()
	var span := view[2]
	for row in height:
		var lat := deg_to_rad(view[1] + (0.5 - (float(row) + 0.5) / float(height)) * span * 0.5)
		for column in width:
			var lon := deg_to_rad(view[0] + ((float(column) + 0.5) / float(width) - 0.5) * span)
			directions.append(Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)))
	var found := cells_of(directions)
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	for index in directions.size():
		var cell := found[index]
		var ground := heights[cell]
		var colour: Color
		if ground < 0.0:
			var deep := clampf(1.0 + ground / 5000.0, 0.0, 1.0)
			colour = Color(0.02, 0.1, 0.3).lerp(Color(0.2, 0.45, 0.7), deep)
		else:
			var up := clampf(ground / 5000.0, 0.0, 1.0)
			colour = Color(0.28, 0.45, 0.22).lerp(Color(0.6, 0.5, 0.35), smoothstep(0.0, 0.5, up))
			colour = colour.lerp(Color(0.95, 0.95, 0.95), smoothstep(0.5, 1.0, up))
			if lake[cell] == 1:
				colour = Color(0.2, 0.7, 0.85)
			var carried := flow[cell]
			if carried >= threshold:
				var strength := clampf(log(carried / threshold) / log(400.0), 0.0, 1.0)
				colour = colour.lerp(Color(0.1, 0.3, 1.0), 0.45 + 0.55 * strength)
		image.set_pixel(index % width, index / width, colour)
	return image
