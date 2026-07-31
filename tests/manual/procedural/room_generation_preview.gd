extends Node3D
## Manual acceptance harness for ProceduralRoomGenerator (Phase 1 - see
## docs/procedural_room_generation_plan.md). Runs the generator and builds a
## quick debug volume per room (floor, ceiling tiles, walls with door cuts at
## each connection, and a chance of a center light fixture and/or a ceiling
## vent) reusing Backrooms Level 0's materials/shaders/components, so a
## generated layout can be flown through and visually sanity-checked before
## any real dressed geometry exists. Not the final room-building pass - see
## the plan doc's "Data vs. geometry" section for what that will look like.
## Fly with Free Mode to inspect from outside; since rooms now have ceilings,
## go through a door or above the wall height rather than straight down from
## above.

const FLOOR_THICKNESS := 0.2
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.3

const SIDES: Array[ProceduralRoomGenerator.Side] = [
	ProceduralRoomGenerator.Side.NORTH, ProceduralRoomGenerator.Side.SOUTH,
	ProceduralRoomGenerator.Side.EAST, ProceduralRoomGenerator.Side.WEST,
]

## One color per compass direction so a wall's side is identifiable at a
## glance - the original debug look this preview used before switching to
## real textures, kept around behind `debug_wall_colors` for the next time a
## wall-coverage bug needs to be tracked down. North/east/west/south =
## red/blue/green/yellow, a standard north-up map reading
## (top/right/left/bottom).
const SIDE_COLORS := {
	ProceduralRoomGenerator.Side.NORTH: Color(0.8, 0.15, 0.15),
	ProceduralRoomGenerator.Side.EAST: Color(0.15, 0.3, 0.85),
	ProceduralRoomGenerator.Side.WEST: Color(0.15, 0.7, 0.2),
	ProceduralRoomGenerator.Side.SOUTH: Color(0.85, 0.75, 0.1),
}

# Reuses the Backrooms Level 0 wallpaper/carpet shaders and textures (see
# levels/backrooms_level0.tscn) instead of flat debug colors, now that the
# wall-coverage bugs those colors were added to diagnose are resolved. Both
# shaders key their pattern off world-space position (use_world_uv = true),
# so tile/texture scale stays consistent across this layout's wildly
# different room and corridor sizes instead of stretching per-face like a
# mesh-UV-driven material would.
const WALLPAPER_SHADER := preload("res://shaders/damask_wallpaper.gdshader")
const WALLPAPER_TEXTURE := preload("res://assets/textures/backrooms_wallpaper.png")
const CARPET_SHADER := preload("res://shaders/ceiling_tile_grid.gdshader")
const CARPET_TEXTURE := preload("res://assets/textures/backrooms_carpet.png")
const CEILING_TILE_TEXTURE := preload("res://assets/textures/backrooms_ceiling_tile.png")
const LIGHT_FIXTURE_TEXTURE := preload("res://assets/textures/backrooms_light_fixture.png")
const CEILING_VENT_SCENE := preload("res://levels/props/ceiling_vent.tscn")

# Light panel + vent placement, offsets measured from the ceiling's flush
# (visible) underside - see the CeilingTileGrid/ceiling_vent.tscn doc
# comments for why both hang from local Y=0 at that surface. Values copied
# from backrooms_level0.tscn's own fixtures (relative to that scene's
# WALL_HEIGHT-equivalent ceiling height) rather than re-derived.
const LIGHT_PANEL_THICKNESS := 0.08
const LIGHT_PANEL_Y_OFFSET := 0.02
const LIGHT_SOURCE_Y_OFFSET := -0.10
const VENT_Y_OFFSET := 0.03

# Target tile module - see the per-axis fitting comment in _build_ceiling()
# for why each room's actual tile size ends up slightly different from this.
const TILE_SIZE := 1.2
const TILE_GAP := 0.04 ## matches CeilingTileGrid.tile_gap's own default

# Per-room odds of each fixture appearing at all, rolled independently per
# room (vent only among rooms that were already geometrically eligible for
# one - see _build_ceiling). Lights stay common so most rooms are lit;
# vents stay rare so they read as an occasional detail rather than
# furniture, matching how backrooms_level0.tscn only has a single vent for
# its whole level rather than one per room.
const LIGHT_OCCURRENCE_RATE := 0.85
const VENT_OCCURRENCE_RATE := 0.25

# With ordinary rooms roofless in debug mode (see the main loop), the
# scene's own low ambient/no-sun atmosphere (tuned for normal play, relying
# on per-room light fixtures) leaves most of the maze unreadable from above
# or through a wall - debug_wall_colors also brightens the whole scene with
# a flat sun so the structure is visible regardless of which rooms happen to
# have a light fixture.
const DEBUG_AMBIENT_ENERGY := 1.2
const DEBUG_SUN_ENERGY := 1.1

# Ramp/staircase geometry. A stair's step count is derived from its total
# rise so risers stay roughly a real-world size regardless of how tall the
# climb is, clamped to a sane range at both ends.
const STEP_RISE := 0.2 ## ~20cm, a typical stair riser height
const STAIRS_MIN_STEPS := 3
const STAIRS_MAX_STEPS := 24

# The floor/ceiling plates hug the profile by offsetting it a constant
# distance (see _ribbon_polygon()) - fine for a smooth ramp (a simple
# 2-point line), but a stepped profile has real vertical riser segments, and
# offsetting those by anything close to the riser's own height makes the
# offset copy of one riser cross back over the original (a self-intersecting
# polygon CSGPolygon3D can't triangulate - confirmed by the exact "Failed to
# triangulate" engine error). With STEP_RISE=0.2 and STAIRS_MIN_STEPS=3
# forcing a floor of at most 3 steps even for a small total rise, the
# smallest possible per-step riser is rise_min/3 (~0.33m) - this stays
# comfortably clear of that in every case, unlike FLOOR_THICKNESS (0.2m,
# too close to a typical riser height) which is what actually broke.
const RAMP_PLATE_THICKNESS := 0.5

# The side walls' outer face sits exactly at the room's true width boundary
# (same convention _make_wall_box() already uses for flat rooms - see its
# own inset comment), and the floor/ceiling caps naturally span out to that
# same boundary too, so the two end up perfectly coincident - real
# z-fighting, not just a look-alike, the same class of bug already fixed
# once this session for wall-vs-wall at room connections. Shrinking the
# floor/ceiling extrusion by this (imperceptible) margin keeps their edge a
# hair inside the wall's outer face instead of touching it exactly - the
# wall's own WALL_THICKNESS comfortably covers the gap from any angle.
const RAMP_CAP_INSET := 0.02

@export var target_room_count: int = 60
@export var generation_seed: int = 0 ## 0 = auto-randomize; check printed seed to reproduce a run
@export var debug_wall_colors: bool = false ## per-side flat colors instead of the wallpaper texture
@export var spawn_room_index: int = -1 ## -1 = spawn at origin; set to spawn in that room instead

@onready var seed_label: Label = $UI/SeedLabel
@onready var player: Player = $Player

var _wall_material: ShaderMaterial
var _wall_debug_materials: Dictionary = {} ## Side -> StandardMaterial3D, built iff debug enabled
var _floor_material: ShaderMaterial
var _ceiling_tile_material: StandardMaterial3D
var _ceiling_grid_material: StandardMaterial3D
var _ramp_ceiling_material: ShaderMaterial
var _ramp_floor_debug_material: StandardMaterial3D ## plain flat color, built iff debug enabled
var _ramp_ceiling_debug_material: StandardMaterial3D ## plain flat color, built iff debug enabled
var _light_panel_material: StandardMaterial3D
var _dressing_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_wall_material = ShaderMaterial.new()
	_wall_material.shader = WALLPAPER_SHADER
	_wall_material.set_shader_parameter("use_world_uv", true)
	_wall_material.set_shader_parameter("use_texture", true)
	_wall_material.set_shader_parameter("pattern_texture", WALLPAPER_TEXTURE)
	# Matches backrooms_level0.tscn's own wallpaper material: seams off, since
	# that scene's painted-seam look is meant to be replaced by real baseboard
	# trim geometry, which this preview doesn't have.
	_wall_material.set_shader_parameter("seam_width", 0.0)

	if debug_wall_colors:
		for side: ProceduralRoomGenerator.Side in SIDE_COLORS:
			var material := StandardMaterial3D.new()
			material.albedo_color = SIDE_COLORS[side]
			_wall_debug_materials[side] = material
		# A single CSGPolygon3D material paints its whole surface, including
		# the flat top/bottom "cap" edges left by the depth extrusion (the
		# floor's underside, the ceiling's topside) - those edges face a
		# different direction than the main sloped surface, so the
		# world-space wall/ceiling shaders stretch oddly on them. Normally
		# invisible (real ceilings and no flying through walls hide them),
		# but exposed by debug mode's roofless rooms + outside flying - swap
		# to a plain flat color there instead, same as the walls already do.
		_ramp_floor_debug_material = StandardMaterial3D.new()
		_ramp_floor_debug_material.albedo_color = Color(0.5, 0.45, 0.35)
		_ramp_ceiling_debug_material = StandardMaterial3D.new()
		_ramp_ceiling_debug_material.albedo_color = Color(0.75, 0.75, 0.7)
		# The cap only has one real face (Godot's default single-sided
		# culling), and its outward normal points away from the room - so
		# it's visible flying around outside, but backface-culled to
		# invisible from anywhere inside the room looking toward it. Double-
		# sided keeps it visible from both, since debug flying can end up on
		# either side of it.
		for material: StandardMaterial3D in [_ramp_floor_debug_material, _ramp_ceiling_debug_material]:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_enable_debug_lighting()

	_floor_material = ShaderMaterial.new()
	_floor_material.shader = CARPET_SHADER
	_floor_material.set_shader_parameter("use_world_uv", true)
	_floor_material.set_shader_parameter("use_texture", true)
	_floor_material.set_shader_parameter("pattern_texture", CARPET_TEXTURE)

	# Real physical ceiling tile geometry (CeilingTileGrid, per-room MultiMesh)
	# instead of a flat textured box - each individual tile panel has its own
	# mesh UV, so (unlike the wall/floor shaders) these materials don't need
	# world-space UVs to stay consistent across room sizes.
	_ceiling_tile_material = StandardMaterial3D.new()
	_ceiling_tile_material.albedo_texture = CEILING_TILE_TEXTURE
	_ceiling_tile_material.roughness = 0.9
	_ceiling_tile_material.uv1_scale = Vector3(6, 6, 1)

	_ceiling_grid_material = StandardMaterial3D.new()
	_ceiling_grid_material.albedo_color = Color(0.68, 0.65, 0.55)
	_ceiling_grid_material.metallic = 0.4
	_ceiling_grid_material.roughness = 0.3

	# Ramp/stairs ceilings can't use the physical CeilingTileGrid (a flat-plane
	# MultiMesh component) since their surface is sloped or stepped - reuses
	# the same world-space tile shader as the floor instead, just pointed at
	# the ceiling texture, so it still reads as ceiling tile on any surface
	# shape without needing per-tile mesh UVs.
	_ramp_ceiling_material = ShaderMaterial.new()
	_ramp_ceiling_material.shader = CARPET_SHADER
	_ramp_ceiling_material.set_shader_parameter("use_world_uv", true)
	_ramp_ceiling_material.set_shader_parameter("use_texture", true)
	_ramp_ceiling_material.set_shader_parameter("pattern_texture", CEILING_TILE_TEXTURE)

	_light_panel_material = StandardMaterial3D.new()
	_light_panel_material.albedo_texture = LIGHT_FIXTURE_TEXTURE
	_light_panel_material.emission_enabled = true
	_light_panel_material.emission = Color(1, 0.95, 0.78)
	_light_panel_material.emission_energy_multiplier = 1.6
	_light_panel_material.emission_texture = LIGHT_FIXTURE_TEXTURE

	var result := ProceduralRoomGenerator.generate(target_room_count, generation_seed)
	var rooms: Array = result["rooms"]
	var connections: Array = result["connections"]
	var seed_used: int = result["seed_used"]
	print("ProceduralRoomGenerator seed used: ", seed_used)
	print("Rooms placed: ", rooms.size(), " / ", target_room_count)
	print("Connections: ", connections.size())
	if seed_label != null:
		seed_label.text = "Seed: %d  (rooms %d/%d)" % [seed_used, rooms.size(), target_room_count]

	if spawn_room_index >= 0 and spawn_room_index < rooms.size() and player != null:
		var spawn_room: ProceduralRoomGenerator.RoomRecord = rooms[spawn_room_index]
		# rise * 0.5 estimates the floor height at a ramp's geometric center
		# (exact for flat rooms, where rise is always 0) - the extra 1.5m
		# clears any local floor variation (a ramp's ends, or any stair
		# tread) comfortably from above, so gravity settles the player onto
		# the actual floor on the first physics frame instead of risking a
		# spawn embedded in sloped/stepped geometry.
		player.global_position = Vector3(
				spawn_room.rect.position.x + spawn_room.rect.size.x * 0.5,
				spawn_room.elevation + spawn_room.rise * 0.5 + 1.5,
				spawn_room.rect.position.y + spawn_room.rect.size.y * 0.5)
		player.velocity = Vector3.ZERO

	# Separate seeded RNG (not the layout generator's own, which is internal
	# and already spent) so fixture occurrence rolls stay reproducible for a
	# given seed without affecting room/corridor placement at all.
	_dressing_rng.seed = seed_used

	# Every room always draws its own full-width wall on every side, with a
	# door cut for every connection touching that side - never skipped,
	# regardless of which neighboring room is bigger.
	#
	# This replaced two earlier, both-wrong approaches. First: only the
	# anchor ever drew a wall, target always skipped - broke when a narrow
	# corridor (anchor) connected to a wide room (target), since the
	# corridor's wall was far too short to cover the wide room's side,
	# leaving a gap straight to the sky (room 13, seed 12345). Second: let
	# whichever room had the *wider* wall "win" and draw alone - fixed that,
	# but two rooms of *equal* width aren't necessarily positionally
	# aligned (their door-centered placement can offset them from each
	# other), so the "wider" one's wall doesn't always fully cover the
	# other's footprint either - left a corner gap at the door frame
	# between rooms 22 and 23 (seed 12345), the same class of bug as before.
	#
	# The actual fix is to stop trying to pick one wall to own a shared
	# boundary at all: every room draws its own complete wall regardless of
	# neighbors, which can never leave a gap since it only depends on that
	# room's own geometry. The previous z-fighting from two rooms' walls
	# occupying the same plane is solved separately in _make_wall_box() by
	# insetting each wall entirely inside its own room's footprint (instead
	# of straddling the boundary line) - two adjacent rooms' walls now sit
	# right next to each other rather than coincident, so there's nothing
	# left to z-fight.
	var openings_by_room: Dictionary = {} # room_index -> {side: Array[Vector3(min, max, height)]}
	for connection: ProceduralRoomGenerator.ConnectionRecord in connections:
		_add_opening(openings_by_room, connection.room_a, connection.side,
				connection.wall_axis_min, connection.wall_axis_max, connection.door_height)
		_add_opening(openings_by_room, connection.room_b, (connection.side as int) ^ 1,
				connection.wall_axis_min, connection.wall_axis_max, connection.door_height)

	for room_index in rooms.size():
		var room: ProceduralRoomGenerator.RoomRecord = rooms[room_index]
		var side_openings: Dictionary = openings_by_room.get(room_index, {})
		if room.type_id == &"ramp":
			_build_ramp_room(room, side_openings)
			_build_room_label(room, room_index, room.elevation + room.rise * 0.5)
		else:
			_build_floor(room)
			# Debug mode is for structural inspection (walls color-coded by
			# side, flying above with Free Mode) - an open roof on ordinary
			# rooms/corridors matters more there than the real ceiling does.
			# Ramp/stairs rooms keep theirs regardless, since their sloped
			# ceiling is part of what's being inspected.
			if not debug_wall_colors:
				_build_ceiling(room)
			_build_room_label(room, room_index, room.elevation)
			for side: ProceduralRoomGenerator.Side in SIDES:
				_build_end_wall(room, side, room.elevation, side_openings)


func _add_opening(
		map: Dictionary, room_index: int, side: int,
		min_v: float, max_v: float, height: float) -> void:
	if not map.has(room_index):
		map[room_index] = {}
	if not map[room_index].has(side):
		map[room_index][side] = []
	map[room_index][side].append(Vector3(min_v, max_v, height))


func _build_floor(room: ProceduralRoomGenerator.RoomRecord) -> void:
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(room.rect.size.x, FLOOR_THICKNESS, room.rect.size.y)
	floor_box.position = Vector3(
			room.rect.position.x + room.rect.size.x * 0.5,
			room.elevation - FLOOR_THICKNESS * 0.5,
			room.rect.position.y + room.rect.size.y * 0.5)
	floor_box.use_collision = true
	floor_box.material = _floor_material
	add_child(floor_box)


## Structural ceiling (collision only, no visible material) plus the real
## physical tile-panel geometry flush against its underside - mirrors
## backrooms_level0.tscn's Ceiling + CeilingTiles pair. The tile grid's own
## thin backing plate fully covers the structural box's default-material
## underside, so that box never needs a material of its own.
func _build_ceiling(room: ProceduralRoomGenerator.RoomRecord) -> void:
	var center_x := room.rect.position.x + room.rect.size.x * 0.5
	var center_z := room.rect.position.y + room.rect.size.y * 0.5
	var ceiling_y := WALL_HEIGHT + room.elevation

	var ceiling_box := CSGBox3D.new()
	ceiling_box.size = Vector3(room.rect.size.x, FLOOR_THICKNESS, room.rect.size.y)
	ceiling_box.position = Vector3(
			center_x, ceiling_y + FLOOR_THICKNESS * 0.5, center_z)
	ceiling_box.use_collision = true
	add_child(ceiling_box)

	# TILE_SIZE is a target, not a hard module: backrooms_level0.tscn's own
	# rooms happen to be exact multiples of it, but these procedural rooms
	# are random floats, so a literal 1.2m grid leaves the border row/column
	# overshooting the room and getting sliced by the wall. Fitting a whole
	# tile count exactly into each axis (independently, since width and
	# depth rarely share a common factor) keeps every tile whole and flush
	# against the walls, at the cost of the tile module varying slightly
	# (and non-uniformly on each axis) room to room instead of always being
	# exactly 1.2m square.
	var cols: int = max(1, int(round(room.rect.size.x / TILE_SIZE)))
	var rows: int = max(1, int(round(room.rect.size.y / TILE_SIZE)))
	var fit_x := room.rect.size.x / cols
	var fit_z := room.rect.size.y / rows

	var tile_grid := CeilingTileGrid.new()
	tile_grid.width = room.rect.size.x
	tile_grid.depth = room.rect.size.y
	tile_grid.tile_size = fit_x
	tile_grid.tile_size_z = fit_z
	tile_grid.tile_material = _ceiling_tile_material
	tile_grid.grid_material = _ceiling_grid_material
	tile_grid.position = Vector3(center_x, ceiling_y, center_z)
	add_child(tile_grid)

	# Snap the light and vent onto the same tile grid instead of a continuous
	# offset, so each sits centered inside one whole tile cell rather than
	# straddling the grout lines between tiles.
	var light_col := (cols - 1) / 2
	var light_row := (rows - 1) / 2
	if _dressing_rng.randf() < LIGHT_OCCURRENCE_RATE:
		_build_light(
				center_x + _tile_offset(light_col, room.rect.size.x, fit_x),
				center_z + _tile_offset(light_row, room.rect.size.y, fit_z),
				fit_x, fit_z, ceiling_y)

	# The vent goes one tile over on each axis from the light's tile - the
	# nearest cell that can't overlap it - falling back toward whichever edge
	# still has a free tile, or skipping entirely on a single-tile-wide grid
	# (narrow corridors) where no second cell exists. Only rooms that clear
	# this geometric eligibility check even get an occurrence roll.
	var vent_col := light_col + 1 if light_col + 1 < cols else light_col - 1
	var vent_row := light_row + 1 if light_row + 1 < rows else light_row - 1
	if vent_col < 0 or vent_row < 0:
		return
	if _dressing_rng.randf() >= VENT_OCCURRENCE_RATE:
		return
	var vent: Node3D = CEILING_VENT_SCENE.instantiate()
	vent.position = Vector3(
			center_x + _tile_offset(vent_col, room.rect.size.x, fit_x),
			ceiling_y + VENT_Y_OFFSET,
			center_z + _tile_offset(vent_row, room.rect.size.y, fit_z))
	# The vent's own geometry is authored at a fixed ~1.16m footprint (see
	# ceiling_vent.tscn); rescale it to the room's actual fitted tile size so
	# it still reads as "one tile" instead of overflowing a smaller cell or
	# looking undersized in a larger one.
	vent.scale = Vector3(fit_x / TILE_SIZE, 1.0, fit_z / TILE_SIZE)
	add_child(vent)


func _build_light(x: float, z: float, fit_x: float, fit_z: float, ceiling_y: float) -> void:
	var panel := CSGBox3D.new()
	panel.size = Vector3(fit_x - TILE_GAP, LIGHT_PANEL_THICKNESS, fit_z - TILE_GAP)
	panel.position = Vector3(x, ceiling_y + LIGHT_PANEL_Y_OFFSET, z)
	panel.material = _light_panel_material
	add_child(panel)

	var light := OmniLight3D.new()
	light.position = Vector3(x, ceiling_y + LIGHT_SOURCE_Y_OFFSET, z)
	light.light_color = Color(1, 0.95, 0.78)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.shadow_enabled = true
	add_child(light)


## World-space offset (from room center) of tile grid cell `index` along an
## axis spanning `dimension` meters of real room size, tiled at `size` per
## cell - mirrors CeilingTileGrid._build_tiles()'s own start_x/start_z +
## col/row * tile_size math exactly (including using the real room
## dimension, not cols/rows * size, for the start offset) so fixtures land
## on the same cell centers as the physical tile geometry.
func _tile_offset(index: int, dimension: float, size: float) -> float:
	var start := -dimension * 0.5 + size * 0.5
	return start + index * size


## Room index as a billboarded label at room center - always faces the
## camera (readable while walking at ground level or flying above in Free
## Mode), rather than a flat floor decal that would foreshorten badly at a
## walking-height viewing angle. Report this index plus the printed/on-screen
## seed when flagging a specific room's geometry as wrong. `label_elevation`
## is the room's own floor elevation for flat rooms, or the midpoint between
## a ramp's two ends for ramp rooms (see the main loop).
func _build_room_label(
		room: ProceduralRoomGenerator.RoomRecord, room_index: int, label_elevation: float) -> void:
	var label := Label3D.new()
	label.text = str(room_index)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.outline_size = 14
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.position = Vector3(
			room.rect.position.x + room.rect.size.x * 0.5,
			label_elevation + 1.2,
			room.rect.position.y + room.rect.size.y * 0.5)
	add_child(label)


## The world-space center and length of the wall on `room`'s given `side`,
## plus whether that wall runs along world X (true) or world Z (false).
func _wall_geometry(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side) -> Dictionary:
	var r := room.rect
	match side:
		ProceduralRoomGenerator.Side.NORTH:
			return {
				"along_x": true,
				"center": Vector2(r.position.x + r.size.x * 0.5, r.position.y),
				"length": r.size.x,
			}
		ProceduralRoomGenerator.Side.SOUTH:
			return {
				"along_x": true,
				"center": Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y),
				"length": r.size.x,
			}
		ProceduralRoomGenerator.Side.EAST:
			return {
				"along_x": false,
				"center": Vector2(r.position.x + r.size.x, r.position.y + r.size.y * 0.5),
				"length": r.size.y,
			}
		_: # WEST
			return {
				"along_x": false,
				"center": Vector2(r.position.x, r.position.y + r.size.y * 0.5),
				"length": r.size.y,
			}


## Builds whichever wall belongs on `room`'s `side` - solid or door-cut,
## whichever `side_openings` calls for - at `elevation` (that side's own
## local floor height: uniform for a flat room, or the near/far end's own
## elevation for a ramp room's two end walls - see _build_ramp_room()).
func _build_end_wall(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side,
		elevation: float, side_openings: Dictionary) -> void:
	if side_openings.has(side):
		_build_wall_with_doors(room, side, side_openings[side], elevation)
	else:
		_build_solid_wall(room, side, elevation)


func _build_solid_wall(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side,
		elevation: float) -> void:
	var wall := _make_wall_box(room, side, elevation)
	add_child(wall)


func _build_wall_with_doors(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side,
		openings: Array, elevation: float) -> void:
	var geometry := _wall_geometry(room, side)
	var wall := _make_wall_box(room, side, elevation)
	add_child(wall)
	for opening: Vector3 in openings:
		var door_center := (opening.x + opening.y) * 0.5
		var door_width := opening.y - opening.x
		var door_height := opening.z
		var axis_center: float = (
				geometry["center"].x if geometry["along_x"] else geometry["center"].y)
		var local_offset: float = door_center - axis_center
		var cut := CSGBox3D.new()
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		# The subtractor's own material paints the newly-exposed door-reveal
		# faces (Godot CSG boolean quirk) - without this they default to
		# blank white instead of matching the wall around them.
		cut.material = _wall_material_for(side)
		if geometry["along_x"]:
			cut.size = Vector3(door_width, door_height, WALL_THICKNESS + 0.2)
			cut.position = Vector3(local_offset, door_height * 0.5 - WALL_HEIGHT * 0.5, 0.0)
		else:
			cut.size = Vector3(WALL_THICKNESS + 0.2, door_height, door_width)
			cut.position = Vector3(0.0, door_height * 0.5 - WALL_HEIGHT * 0.5, local_offset)
		wall.add_child(cut)


## Insets the wall entirely inside `room`'s own footprint (instead of
## straddling the boundary line, which is where the wall would coincide
## with a neighboring room's own wall at a connection - see the _ready()
## comment on why every room draws its own wall unconditionally). `elevation`
## is that side's own local floor height - see _build_end_wall().
func _make_wall_box(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side,
		elevation: float) -> CSGBox3D:
	var geometry := _wall_geometry(room, side)
	var wall := CSGBox3D.new()
	var center: Vector2 = geometry["center"]
	var half_thickness := WALL_THICKNESS * 0.5
	match side:
		ProceduralRoomGenerator.Side.NORTH:
			center.y += half_thickness
		ProceduralRoomGenerator.Side.SOUTH:
			center.y -= half_thickness
		ProceduralRoomGenerator.Side.EAST:
			center.x -= half_thickness
		ProceduralRoomGenerator.Side.WEST:
			center.x += half_thickness
	if geometry["along_x"]:
		wall.size = Vector3(geometry["length"], WALL_HEIGHT, WALL_THICKNESS)
	else:
		wall.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, geometry["length"])
	wall.position = Vector3(center.x, WALL_HEIGHT * 0.5 + elevation, center.y)
	wall.use_collision = true
	wall.material = _wall_material_for(side)
	return wall


func _wall_material_for(side: ProceduralRoomGenerator.Side) -> Material:
	return _wall_debug_materials[side] if debug_wall_colors else _wall_material


## Brightens the scene's ambient light and adds a flat sun so the whole maze
## reads clearly in debug mode, independent of per-room light fixtures.
func _enable_debug_lighting() -> void:
	var world_environment := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.ambient_light_energy = DEBUG_AMBIENT_ENERGY

	var sun := DirectionalLight3D.new()
	sun.light_energy = DEBUG_SUN_ENERGY
	sun.rotation = Vector3(-PI * 0.35, PI * 0.15, 0.0)
	add_child(sun)


## Builds a ramp/staircase room: floor, ceiling, and the two long (sloped or
## stepped) side walls as CSGPolygon3D ribbons that hug the profile exactly,
## plus the two short end walls via the ordinary flat-room wall path (just at
## each end's own local elevation). No light panel or vent here - both are
## positioned via the flat CeilingTileGrid tile-snapping system, which
## doesn't apply to a sloped/stepped ceiling.
func _build_ramp_room(
		room: ProceduralRoomGenerator.RoomRecord, side_openings: Dictionary) -> void:
	var axes := _ramp_axes(room)
	var profile := _ramp_profile(axes["run"], room.rise, room.has_stairs)
	# The ceiling always stays a smooth incline, even over a staircase floor -
	# real stairs don't usually have a stepped/notched ceiling overhead
	# tracking every riser, just a plain sloped one.
	var ceiling_profile := _ramp_profile(axes["run"], room.rise, false)
	var basis: Basis = _ramp_basis(axes)
	var origin := Vector3(axes["near_x"], room.elevation, axes["near_z"])
	var width: float = axes["width"]

	var cap_width := width - RAMP_CAP_INSET * 2.0
	_build_ramp_floor(profile, cap_width, basis, origin)
	_build_ramp_ceiling(ceiling_profile, cap_width, basis, origin)

	# Which compass Side each long wall corresponds to depends on which axis
	# the room runs along - see _ramp_axes()'s doc comment.
	var negative_side: ProceduralRoomGenerator.Side
	var positive_side: ProceduralRoomGenerator.Side
	if axes["elongated_x"]:
		negative_side = ProceduralRoomGenerator.Side.NORTH
		positive_side = ProceduralRoomGenerator.Side.SOUTH
	else:
		negative_side = ProceduralRoomGenerator.Side.WEST
		positive_side = ProceduralRoomGenerator.Side.EAST
	var side_reach := width * 0.5 - WALL_THICKNESS * 0.5
	_build_ramp_side_wall(
			profile, ceiling_profile, -side_reach, basis, origin, _wall_material_for(negative_side))
	_build_ramp_side_wall(
			profile, ceiling_profile, side_reach, basis, origin, _wall_material_for(positive_side))

	_build_end_wall(room, axes["near_side"], room.elevation, side_openings)
	_build_end_wall(room, axes["far_side"], room.elevation + room.rise, side_openings)


## World-space layout info for a ramp room: which axis it runs along, its
## run (length) and width, the world (x,z) of its near/incoming end, and
## which direction (+1/-1) travel moves along that axis from there. The
## room's own `outgoing_side` (see ProceduralRoomGenerator.RoomRecord) is
## both "the direction from this room's anchor toward this room" and "the
## direction from this room's own near wall toward its own far wall" - the
## same compass value serves both, by construction (see
## ProceduralRoomGenerator._try_place_room()).
func _ramp_axes(room: ProceduralRoomGenerator.RoomRecord) -> Dictionary:
	var elongated_x := room.rect.size.x >= room.rect.size.y
	var far_side: int = room.outgoing_side
	var near_side: int = far_side ^ 1
	var near_x: float
	var near_z: float
	var travel_sign: float
	if elongated_x:
		near_z = room.rect.position.y + room.rect.size.y * 0.5
		if near_side == ProceduralRoomGenerator.Side.WEST:
			near_x = room.rect.position.x
			travel_sign = 1.0
		else:
			near_x = room.rect.position.x + room.rect.size.x
			travel_sign = -1.0
	else:
		near_x = room.rect.position.x + room.rect.size.x * 0.5
		if near_side == ProceduralRoomGenerator.Side.NORTH:
			near_z = room.rect.position.y
			travel_sign = 1.0
		else:
			near_z = room.rect.position.y + room.rect.size.y
			travel_sign = -1.0
	return {
		"elongated_x": elongated_x,
		"run": room.rect.size.x if elongated_x else room.rect.size.y,
		"width": room.rect.size.y if elongated_x else room.rect.size.x,
		"near_x": near_x, "near_z": near_z, "travel_sign": travel_sign,
		"near_side": near_side, "far_side": far_side,
	}


## Local X (distance along the ramp, from _ramp_profile) maps to world X or
## Z depending on which axis the room runs along; local Y (height, already
## relative in the profile) passes straight through to world Y; local Z
## (the CSGPolygon3D depth/extrusion axis) maps to whichever world axis is
## the room's width.
func _ramp_basis(axes: Dictionary) -> Basis:
	var travel_sign: float = axes["travel_sign"]
	if axes["elongated_x"]:
		return Basis(Vector3(travel_sign, 0.0, 0.0), Vector3.UP, Vector3.BACK)
	return Basis(Vector3(0.0, 0.0, travel_sign), Vector3.UP, Vector3.RIGHT)


## Ordered (distance, height) points from (0, 0) to (run, rise), relative to
## the room's own elevation - callers add elevation separately (via the
## node's own transform) rather than baking it into the profile, so the same
## profile can be reused for the floor/ceiling/both side walls.
func _ramp_profile(run: float, rise: float, has_stairs: bool) -> PackedVector2Array:
	if not has_stairs or is_zero_approx(rise):
		return PackedVector2Array([Vector2(0.0, 0.0), Vector2(run, rise)])

	var step_count: int = clampi(
			int(round(absf(rise) / STEP_RISE)), STAIRS_MIN_STEPS, STAIRS_MAX_STEPS)
	var step_run := run / step_count
	var step_rise := rise / step_count
	var points := PackedVector2Array([Vector2(0.0, 0.0)])
	var height := 0.0
	for step in step_count:
		var distance := (step + 1) * step_run
		points.append(Vector2(distance, height)) # tread: forward, height unchanged
		height += step_rise
		points.append(Vector2(distance, height)) # riser: same distance, height jumps
	return points


## A thin constant-thickness band that hugs `profile` exactly on both edges
## (one edge is the profile itself, the other is the same profile offset by
## `thickness`) - used for the floor, ceiling, and side walls alike, so
## every one of them is a real plate that follows the slope/steps closely
## instead of a solid wedge filling the whole vertical drop underneath (or
## above) it. That wedge shape was the actual bug behind the ramp "cap" at
## each width edge looking huge from outside - it wasn't a thin sliver, it
## was the full run-length x total-rise cross-section of a solid fill.
func _ribbon_polygon(profile: PackedVector2Array, thickness: float) -> PackedVector2Array:
	var points := PackedVector2Array(profile)
	for i in range(profile.size() - 1, -1, -1):
		points.append(Vector2(profile[i].x, profile[i].y + thickness))
	return points


## Floor plate: top edge is the walkable profile itself, bottom edge is the
## same profile offset down by RAMP_PLATE_THICKNESS - a thin slab, not a
## wedge filling down to a single flat base line.
func _floor_polygon(profile: PackedVector2Array) -> PackedVector2Array:
	return _ribbon_polygon(profile, -RAMP_PLATE_THICKNESS)


## Ceiling plate: bottom edge is the profile offset up by WALL_HEIGHT
## (exactly where the walls end), top edge is that same offset profile
## shifted up by another RAMP_PLATE_THICKNESS - a thin slab hugging the
## walls' top edge, not a wedge filling up to a single flat top line.
func _ceiling_polygon(profile: PackedVector2Array) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point: Vector2 in profile:
		shifted.append(Vector2(point.x, point.y + WALL_HEIGHT))
	return _ribbon_polygon(shifted, RAMP_PLATE_THICKNESS)


## Wall ribbon band: bottom edge is `floor_profile` itself (so it touches
## the floor's top surface at every point along the slope or every stair
## nosing - no gap), top edge is `ceiling_profile` offset up by WALL_HEIGHT
## (matching the ceiling's own underside - see _build_ramp_ceiling()). The
## two profiles differ when the floor is stepped but the ceiling stays a
## smooth incline (see _build_ramp_room()) - both always share the same
## start/end points, so the band still closes into a single simple polygon.
func _wall_ribbon_polygon(
		floor_profile: PackedVector2Array, ceiling_profile: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array(floor_profile)
	for i in range(ceiling_profile.size() - 1, -1, -1):
		points.append(Vector2(ceiling_profile[i].x, ceiling_profile[i].y + WALL_HEIGHT))
	return points


## CSGPolygon3D's depth mode extrudes from local Z=0 toward local -Z only
## (confirmed via CSGShape3D.get_aabb() - NOT symmetric around the node's
## origin), so every builder below has to shift the node forward by half its
## depth to land the extrusion centered on `origin` instead of trailing off
## to one side of it.
func _build_ramp_floor(
		profile: PackedVector2Array, width: float, basis: Basis, origin: Vector3) -> void:
	var poly := CSGPolygon3D.new()
	poly.polygon = _floor_polygon(profile)
	poly.mode = CSGPolygon3D.MODE_DEPTH
	poly.depth = width
	poly.material = _ramp_floor_debug_material if debug_wall_colors else _floor_material
	poly.use_collision = true
	poly.transform = Transform3D(basis, origin + basis.z * (width * 0.5))
	add_child(poly)


func _build_ramp_ceiling(
		profile: PackedVector2Array, width: float, basis: Basis, origin: Vector3) -> void:
	var poly := CSGPolygon3D.new()
	poly.polygon = _ceiling_polygon(profile)
	poly.mode = CSGPolygon3D.MODE_DEPTH
	poly.depth = width
	poly.material = _ramp_ceiling_debug_material if debug_wall_colors else _ramp_ceiling_material
	poly.use_collision = true
	poly.transform = Transform3D(basis, origin + basis.z * (width * 0.5))
	add_child(poly)


## `side_offset` is the ribbon's position across the room's width, measured
## from center (negative/positive - see _build_ramp_room()'s negative_side/
## positive_side).
func _build_ramp_side_wall(
		floor_profile: PackedVector2Array, ceiling_profile: PackedVector2Array,
		side_offset: float, basis: Basis, origin: Vector3, material: Material) -> void:
	var poly := CSGPolygon3D.new()
	poly.polygon = _wall_ribbon_polygon(floor_profile, ceiling_profile)
	poly.mode = CSGPolygon3D.MODE_DEPTH
	poly.depth = WALL_THICKNESS
	poly.material = material
	poly.use_collision = true
	poly.transform = Transform3D(
			basis, origin + basis.z * (side_offset + WALL_THICKNESS * 0.5))
	add_child(poly)
