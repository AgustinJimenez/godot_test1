class_name PlanetHydrology
extends RefCounted
## Where the water of a planet runs. The planet's ground is sampled on a grid (the cube faces, a
## few hundred metres a cell on a small planet), every hollow is filled up to the level it would
## spill over (those are the lakes), and every cell drains to its lowest neighbour on the way to the
## sea. Adding up the rain that falls on all the cells that drain through one gives the river: the
## cells with enough water are rivers, wider where more water flows. The ground is then carved along
## them (a channel with a bed, banks and a valley), and the tiles draw the water as ribbons and
## lakes. Built once per planet from PlanetNoise.base_height, then only read.

const RIVER_SHARE := 0.045 ## the share of land cells that carry a river

var cells := 96 ## cells along a cube face edge
var lake_depth := 8.0 ## m a filled hollow must be deeper than to count as a lake
var _count := 0 ## cells on all faces
var _radius := 1.0
var _dirs := PackedVector3Array() ## the middle of every cell, as a unit direction
var _neighbours := PackedInt32Array() ## 8 per cell
var _filled := PackedFloat32Array() ## the ground, with the hollows filled up (m above the sea)
var _ground := PackedFloat32Array() ## the ground itself
var _down := PackedInt32Array() ## the cell this one drains into (-1: it is sea)
var _order: Array[int] = [] ## the cells in the order the flood from the sea reached them
var _flow := PackedFloat32Array() ## the water that passes through the cell
var _is_river := PackedByteArray()
var _erosion_near := PackedByteArray() ## 1 where a cell or a neighbour is eroded
var _near := PackedByteArray() ## 1 on a river cell and the cells next to one
var _lake_cell := PackedByteArray() ## 1 on a cell whose hollow is filled into a lake
var _width := PackedFloat32Array() ## river width in metres (0: no river)
var _noise: PlanetNoise
var cell_metres := 100.0
var _erosion := PackedFloat32Array() ## m the valley floor of each cell is cut below the ground
var _pieces: Dictionary = {} ## cell -> the smoothed river pieces whose middle lies in it
var river_cells := 0
var lake_cells := 0


func build(noise: PlanetNoise, cells_per_edge: int) -> void:
	_noise = noise
	cells = cells_per_edge
	lake_depth = maxf(noise.relief * noise.settings.lake_depth_share, 6.0)
	_count = 6 * cells * cells
	_radius = noise.settings.radius
	cell_metres = _radius * PI * 0.5 / float(cells)
	_dirs.resize(_count)
	_ground.resize(_count)
	var rain := PackedFloat32Array()
	rain.resize(_count)
	for face in 6:
		for j in cells:
			for i in cells:
				var id := _id(face, i, j)
				var dir := PlanetTile.direction(face, _mid(i), _mid(j))
				_dirs[id] = dir
				_ground[id] = noise.macro_height(dir.x, dir.y, dir.z)
				rain[id] = noise.climate.sample(dir).y
	_link_neighbours()
	_fill(rain)
	_erode(noise.relief)
	_rivers(noise)


## The face coordinate (-1..1) of the middle of cell row/column `index_on_face`.
func _mid(index_on_face: int) -> float:
	return -1.0 + 2.0 * (float(index_on_face) + 0.5) / float(cells)


func _id(face: int, i: int, j: int) -> int:
	return (face * cells + j) * cells + i


## The cell that holds the unit direction `dir`.
func cell_of(dir: Vector3) -> int:
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	var az := absf(dir.z)
	var face := 0
	if ax >= ay and ax >= az:
		face = 0 if dir.x > 0.0 else 1
	elif ay >= az:
		face = 2 if dir.y > 0.0 else 3
	else:
		face = 4 if dir.z > 0.0 else 5
	var axes: Array = PlanetTile.FACES[face]
	var along := dir.dot(axes[0] as Vector3)
	var s := atan(dir.dot(axes[1] as Vector3) / along) * 4.0 / PI
	var t := atan(dir.dot(axes[2] as Vector3) / along) * 4.0 / PI
	var i := clampi(int((s + 1.0) * 0.5 * float(cells)), 0, cells - 1)
	var j := clampi(int((t + 1.0) * 0.5 * float(cells)), 0, cells - 1)
	return _id(face, i, j)


func _link_neighbours() -> void:
	_neighbours.resize(_count * 8)
	var spots: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	for face in 6:
		for j in cells:
			for i in cells:
				var id := _id(face, i, j)
				for n in 8:
					var ni := i + spots[n].x
					var nj := j + spots[n].y
					if ni >= 0 and ni < cells and nj >= 0 and nj < cells:
						_neighbours[id * 8 + n] = _id(face, ni, nj)
					else: # over the edge of the face: where would that cell's middle be?
						var s := -1.0 + 2.0 * (float(ni) + 0.5) / float(cells)
						var t := -1.0 + 2.0 * (float(nj) + 0.5) / float(cells)
						_neighbours[id * 8 + n] = cell_of(PlanetTile.direction(face, s, t))


## Priority flood from the sea: every land cell drains into the cell that reached it first, and its
## filled level is never below that cell's (plus a hair, so flats still run downhill).
func _fill(rain: PackedFloat32Array) -> void:
	_filled.resize(_count)
	_down.resize(_count)
	var done := PackedByteArray()
	done.resize(_count)
	var heap_keys: Array[float] = []
	var heap_ids: Array[int] = []
	for id in _count:
		_down[id] = -1
		if _ground[id] < 0.0:
			_filled[id] = _ground[id]
			done[id] = 1
			_push(heap_keys, heap_ids, _ground[id], id)
	_order.clear()
	var order := _order
	var hair := 0.002
	while not heap_ids.is_empty():
		var id := _pop(heap_keys, heap_ids)
		order.append(id)
		for n in 8:
			var other := _neighbours[id * 8 + n]
			if done[other] == 1:
				continue
			done[other] = 1
			_down[other] = id
			_filled[other] = maxf(_ground[other], _filled[id] + hair)
			_push(heap_keys, heap_ids, _filled[other], other)
	# add up the rain: from the highest cell down to the sea
	_flow.resize(_count)
	for id in _count:
		_flow[id] = rain[id] if _ground[id] >= 0.0 else 0.0
	for index in range(order.size() - 1, -1, -1):
		var id := order[index]
		if _down[id] >= 0:
			_flow[_down[id]] += _flow[id]


## Stream power erosion, the way rivers cut real valleys: a cell can only be as steep as the water
## running through it allows (slope = uplift / (erodibility * water^0.5)), so the more water a cell
## drains, the lower it sits below its upstream neighbours. Walking from the sea inland, the height
## a cell can keep is its downstream neighbour's plus that slope times the distance; the ground
## above that is cut away (smoothly, by at most a share of the relief). Big rivers get wide, deep
## valleys and the small streams only scratch. (After Cordonnier et al. 2016.)
func _erode(relief: float) -> void:
	_erosion.resize(_count)
	var most := 0.0
	for id in _count:
		most = maxf(most, _flow[id])
	var reach := cell_metres
	var cut_limit := relief * 0.12
	var allowed := PackedFloat32Array() # the height each cell may keep
	allowed.resize(_count)
	for id in _count:
		allowed[id] = _ground[id]
	# the sea first, then inland in the order the flood reached the cells (low to high)
	for id in _order:
		var down := _down[id]
		if down < 0 or _ground[id] < 0.0:
			continue
		var water := maxf(_flow[id], 0.0001) / maxf(most, 0.0001)
		# slope allowed: steep for a trickle, shallow for a river (relief per cell distance)
		var slope := 0.02 + 0.5 * pow(1.0 - minf(sqrt(water) * 6.0, 1.0), 2.0)
		allowed[id] = minf(_ground[id], maxf(allowed[down], 0.0) + slope * reach * 0.2)
		_erosion[id] = clampf(_ground[id] - allowed[id], 0.0, cut_limit)
	_erosion_near.resize(_count)
	for id in _count:
		if _erosion[id] > 0.0:
			_erosion_near[id] = 1
			for n in 8:
				_erosion_near[_neighbours[id * 8 + n]] = 1


func _rivers(noise: PlanetNoise) -> void:
	var flows: Array[float] = []
	for id in _count:
		if _ground[id] >= 0.0:
			flows.append(_flow[id])
	flows.sort()
	if flows.is_empty():
		return
	var threshold: float = flows[clampi(int(float(flows.size()) * (1.0 - RIVER_SHARE)), 0,
			flows.size() - 1)]
	_is_river.resize(_count)
	_lake_cell.resize(_count)
	_near.resize(_count)
	_width.resize(_count)
	var biggest: float = flows[flows.size() - 1]
	for id in _count:
		if _ground[id] >= 2.0 and _flow[id] >= threshold and _down[id] >= 0:
			_is_river[id] = 1
			river_cells += 1
			# width grows with the square root of the water (and a long river is wide)
			var share := sqrt(_flow[id] / maxf(threshold, 0.0001))
			var most := sqrt(biggest / maxf(threshold, 0.0001))
			_width[id] = clampf(6.0 + 14.0 * share * minf(cell_metres / 400.0, 3.0), 6.0,
					minf(cell_metres * 0.35, 6.0 + 14.0 * most * minf(cell_metres / 400.0, 3.0)))
		if _filled[id] - _ground[id] > lake_depth and _ground[id] >= 0.0:
			lake_cells += 1
			_lake_cell[id] = 1
	_smooth_rivers(noise)
	for key: int in _pieces:
		_near[key] = 1
		for n in 8:
			_near[_neighbours[key * 8 + n]] = 1


## Follows every river from its source to its mouth and rounds its corners (Chaikin's cutting), so
## the rivers wind instead of stepping from cell to cell. The pieces are filed under the cell their
## middle is in; the last piece of a river that ends in the sea stops at the shore.
func _smooth_rivers(noise: PlanetNoise) -> void:
	var fed := PackedByteArray() # 1 on a river cell some other river cell drains into
	fed.resize(_count)
	for id in _count:
		if _is_river[id] == 1 and _is_river[_down[id]] == 1:
			fed[_down[id]] = 1
	for start in _count:
		if _is_river[start] == 0 or fed[start] == 1:
			continue
		var points: Array[Vector3] = []
		var levels: Array[float] = []
		var widths: Array[float] = []
		var id := start
		while true:
			points.append(_dirs[id])
			levels.append(maxf(_filled[id], 0.0))
			widths.append(_width[id])
			var down := _down[id]
			if _is_river[down] == 0:
				# the mouth: on to the shore (or the lake) and no further
				var reach := 0.5 if _ground[down] < 0.0 else 1.0
				points.append(_dirs[id].lerp(_dirs[down], reach).normalized())
				levels.append(maxf(_filled[down] if reach == 1.0 else 0.0, 0.0))
				widths.append(_width[id] * 1.1)
				break
			id = down
			if points.size() > 4000:
				break
		for round in 2:
			var cut_points: Array[Vector3] = [points[0]]
			var cut_levels: Array[float] = [levels[0]]
			var cut_widths: Array[float] = [widths[0]]
			for k in points.size() - 1:
				cut_points.append(points[k].lerp(points[k + 1], 0.25).normalized())
				cut_points.append(points[k].lerp(points[k + 1], 0.75).normalized())
				cut_levels.append(lerpf(levels[k], levels[k + 1], 0.25))
				cut_levels.append(lerpf(levels[k], levels[k + 1], 0.75))
				cut_widths.append(lerpf(widths[k], widths[k + 1], 0.25))
				cut_widths.append(lerpf(widths[k], widths[k + 1], 0.75))
			cut_points.append(points[points.size() - 1])
			cut_levels.append(levels[levels.size() - 1])
			cut_widths.append(widths[widths.size() - 1])
			points = cut_points
			levels = cut_levels
			widths = cut_widths
		# the water runs downhill on the real ground: each node's level is below the ground there and
		# never above the node upstream; where the ground falls under the sea the river ends
		var lowest := INF
		for k in points.size():
			var ground := noise.base_height(points[k].x, points[k].y, points[k].z)
			if ground < 0.6 and k > 0:
				points.resize(k + 1)
				levels.resize(k + 1)
				widths.resize(k + 1)
				lowest = minf(lowest, 0.0)
				levels[k] = 0.0
				break
			lowest = minf(lowest, ground - 1.0)
			levels[k] = maxf(lowest, 0.0)
		# the direction the river runs at each node (shared by the two pieces that meet there, so
		# the ribbons join without a gap or an overlap)
		var tangents: Array[Vector3] = []
		for k in points.size():
			var before := points[maxi(k - 1, 0)]
			var after := points[mini(k + 1, points.size() - 1)]
			tangents.append((after - before).normalized())
		var travelled := 0.0 # metres along the river from its source (the water's texture flows)
		for k in points.size() - 1:
			var home := cell_of((points[k] + points[k + 1]).normalized())
			if not _pieces.has(home):
				_pieces[home] = []
			var length := (points[k + 1] - points[k]).length() * _radius
			(_pieces[home] as Array).append([points[k], points[k + 1], levels[k], levels[k + 1],
					widths[k], widths[k + 1], tangents[k], tangents[k + 1], travelled,
					travelled + length])
			travelled += length


func _push(keys: Array[float], ids: Array[int], key: float, id: int) -> void:
	keys.append(key)
	ids.append(id)
	var at := keys.size() - 1
	while at > 0:
		var parent := (at - 1) >> 1
		if keys[parent] <= keys[at]:
			break
		var k := keys[parent]
		keys[parent] = keys[at]
		keys[at] = k
		var d := ids[parent]
		ids[parent] = ids[at]
		ids[at] = d
		at = parent


func _pop(keys: Array[float], ids: Array[int]) -> int:
	var top := ids[0]
	var last := keys.size() - 1
	keys[0] = keys[last]
	ids[0] = ids[last]
	keys.resize(last)
	ids.resize(last)
	var at := 0
	while true:
		var left := at * 2 + 1
		var right := left + 1
		var small := at
		if left < last and keys[left] < keys[small]:
			small = left
		if right < last and keys[right] < keys[small]:
			small = right
		if small == at:
			break
		var k := keys[small]
		keys[small] = keys[at]
		keys[at] = k
		var d := ids[small]
		ids[small] = ids[at]
		ids[at] = d
		at = small
	return top


## The ground at `dir` after the rivers are cut into it (`h`: the ground before).
func carve(dir: Vector3, h: float) -> float:
	var here := cell_of(dir)
	if _near[here] == 0:
		return h
	var best := INF
	var best_piece: Array = []
	var best_t := 0.0
	for n in 9:
		var id := here if n == 8 else _neighbours[here * 8 + n]
		if not _pieces.has(id):
			continue
		for piece: Array in _pieces[id]:
			var a: Vector3 = piece[0]
			var ab := (piece[1] as Vector3) - a
			var t := clampf((dir - a).dot(ab) / maxf(ab.length_squared(), 0.0000000001), 0.0, 1.0)
			var distance := (dir - (a + ab * t)).length() * _radius
			if distance < best:
				best = distance
				best_piece = piece
				best_t = t
	if best_piece.is_empty():
		return h
	var width := lerpf(float(best_piece[4]), float(best_piece[5]), best_t)
	var level := lerpf(float(best_piece[2]), float(best_piece[3]), best_t)
	var bed := level - (1.0 + 0.07 * width)
	var inner := width * 0.5
	var outer := minf(inner + width * 2.2 + 8.0, maxf(cell_metres * 0.7, inner + 4.0))
	var blend := 1.0 - smoothstep(inner, outer, best)
	return lerpf(h, minf(h, bed), blend) # a river only cuts down, it never builds a dike


## The cells within `rings` steps of cell `id` (itself included), across cube faces.
func cells_around(id: int, rings: int) -> PackedInt32Array:
	var seen := {id: true}
	var frontier := PackedInt32Array([id])
	for ring in rings:
		var next := PackedInt32Array()
		for cell in frontier:
			for n in 8:
				var other := _neighbours[cell * 8 + n]
				if not seen.has(other):
					seen[other] = true
					next.append(other)
		frontier = next
	return PackedInt32Array(seen.keys())


## The river pieces whose middle lies in these cells: each is [from dir, to dir, level at the start,
## level at the end, width at the start, width at the end, direction at the start, at the end,
## metres from the source at the start, at the end] (levels in metres above the sea).
func river_segments(ids: PackedInt32Array) -> Array[Array]:
	var found: Array[Array] = []
	for id in ids:
		if _pieces.has(id):
			found.append_array(_pieces[id])
	return found


## The level of the lake water at `dir` if the ground there (`ground`) is below the lake that fills
## this cell or a neighbour, else -INF. (A tile uses it at its own vertices, so a lake's shore
## follows the real ground and not the grid.)
func lake_level_at(dir: Vector3, ground: float) -> float:
	if ground < 0.5:
		return -INF # the sea
	var here := cell_of(dir)
	var best := -INF
	for n in 9:
		var id := here if n == 8 else _neighbours[here * 8 + n]
		if _lake_cell[id] == 1 and ground < _filled[id]:
			best = maxf(best, _filled[id])
	return best


## True if any of these cells holds a lake.
func has_lake(ids: PackedInt32Array) -> bool:
	for id in ids:
		if _lake_cell[id] == 1:
			return true
	return false


## The level of the river or lake water at `dir` if there is some there and `ground` is below it
## (metres above the sea), else -INF. Plants keep out of it.
func water_at(dir: Vector3, ground: float) -> float:
	var here := cell_of(dir)
	var level := -INF
	level = lake_level_at(dir, ground)
	if _near[here] == 0:
		return level
	for n in 9:
		var id := here if n == 8 else _neighbours[here * 8 + n]
		if not _pieces.has(id):
			continue
		for piece: Array in _pieces[id]:
			var a: Vector3 = piece[0]
			var ab := (piece[1] as Vector3) - a
			var t := clampf((dir - a).dot(ab) / maxf(ab.length_squared(), 0.0000000001), 0.0, 1.0)
			var distance := (dir - (a + ab * t)).length() * _radius
			if distance < lerpf(float(piece[4]), float(piece[5]), t) * 0.5 + 1.0:
				level = maxf(level, lerpf(float(piece[2]), float(piece[3]), t))
	return level


## How far (m) the valleys have cut the ground at `dir`: the cells' cuts blended smoothly.
func erosion_at(dir: Vector3) -> float:
	var here := cell_of(dir)
	if _erosion[here] <= 0.0 and _erosion_near[here] == 0:
		return 0.0
	var total := _erosion[here] * 0.0
	var weight := 0.0
	for n in 9:
		var id := here if n == 8 else _neighbours[here * 8 + n]
		var d := (dir - _dirs[id]).length() * _radius / cell_metres
		var w := exp(-d * d * 1.6)
		total += _erosion[id] * w
		weight += w
	return total / maxf(weight, 0.0001)


## The current of the river at `dir` (a planet space vector, m/s along the river, longer in a bigger
## river) if the point is in one, else zero.
func flow_at(dir: Vector3) -> Vector3:
	var here := cell_of(dir)
	if _near[here] == 0:
		return Vector3.ZERO
	var best := INF
	var best_piece: Array = []
	var best_t := 0.0
	for n in 9:
		var id := here if n == 8 else _neighbours[here * 8 + n]
		if not _pieces.has(id):
			continue
		for piece: Array in _pieces[id]:
			var a: Vector3 = piece[0]
			var ab := (piece[1] as Vector3) - a
			var t := clampf((dir - a).dot(ab) / maxf(ab.length_squared(), 0.0000000001), 0.0, 1.0)
			var distance := (dir - (a + ab * t)).length() * _radius
			if distance < best:
				best = distance
				best_piece = piece
				best_t = t
	if best_piece.is_empty():
		return Vector3.ZERO
	var width := lerpf(float(best_piece[4]), float(best_piece[5]), best_t)
	if best > width * 0.5:
		return Vector3.ZERO
	var along: Vector3 = (best_piece[6] as Vector3).lerp(best_piece[7] as Vector3, best_t)
	return along.normalized() * clampf(0.7 * sqrt(width / 8.0), 0.5, 3.0)


## Every river piece as [from dir, to dir, width at the start] (for the map).
func river_lines() -> Array[Array]:
	var found: Array[Array] = []
	for id: int in _pieces:
		for piece: Array in _pieces[id]:
			found.append([piece[0], piece[1], piece[4]])
	return found
