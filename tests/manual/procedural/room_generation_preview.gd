extends Node3D
## Manual acceptance harness for ProceduralRoomGenerator (Phase 1 - see
## docs/procedural_room_generation_plan.md). Runs the generator and builds a
## quick debug volume per room (floor + walls with door cuts at each
## connection, color-coded by type) so a generated layout can be flown
## through and visually sanity-checked before any real dressed geometry
## exists. Not the final room-building pass - see the plan doc's
## "Data vs. geometry" section for what that will look like. No ceiling on
## purpose, so flying above with Free Mode still shows the room shapes.

const FLOOR_THICKNESS := 0.2
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.3
const DOOR_HEIGHT := 2.2
const ROOM_COLOR := Color(0.72, 0.6, 0.35)
const CORRIDOR_COLOR := Color(0.35, 0.55, 0.72)

## One color per compass direction so a wall's side is identifiable at a
## glance (helped catch the missing-wall bug this was added to debug) -
## north/east/west/south = red/blue/green/yellow, a standard north-up map
## reading (top/right/left/bottom).
const SIDE_COLORS := {
	ProceduralRoomGenerator.Side.NORTH: Color(0.8, 0.15, 0.15),
	ProceduralRoomGenerator.Side.EAST: Color(0.15, 0.3, 0.85),
	ProceduralRoomGenerator.Side.WEST: Color(0.15, 0.7, 0.2),
	ProceduralRoomGenerator.Side.SOUTH: Color(0.85, 0.75, 0.1),
}

const SIDES: Array[ProceduralRoomGenerator.Side] = [
	ProceduralRoomGenerator.Side.NORTH, ProceduralRoomGenerator.Side.SOUTH,
	ProceduralRoomGenerator.Side.EAST, ProceduralRoomGenerator.Side.WEST,
]

@export var target_room_count: int = 60
@export var generation_seed: int = 0 ## 0 = auto-randomize; check printed seed to reproduce a run

@onready var seed_label: Label = $UI/SeedLabel

var _wall_materials: Dictionary = {}


func _ready() -> void:
	for side: ProceduralRoomGenerator.Side in SIDE_COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = SIDE_COLORS[side]
		_wall_materials[side] = material

	var result := ProceduralRoomGenerator.generate(target_room_count, generation_seed)
	var rooms: Array = result["rooms"]
	var connections: Array = result["connections"]
	var seed_used: int = result["seed_used"]
	print("ProceduralRoomGenerator seed used: ", seed_used)
	print("Rooms placed: ", rooms.size(), " / ", target_room_count)
	print("Connections: ", connections.size())
	if seed_label != null:
		seed_label.text = "Seed: %d  (rooms %d/%d)" % [seed_used, rooms.size(), target_room_count]

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
	var openings_by_room: Dictionary = {} # room_index -> {side: Array[Vector2(min, max)]}
	for connection: ProceduralRoomGenerator.ConnectionRecord in connections:
		_add_opening(openings_by_room, connection.room_a, connection.side,
				connection.wall_axis_min, connection.wall_axis_max)
		_add_opening(openings_by_room, connection.room_b, (connection.side as int) ^ 1,
				connection.wall_axis_min, connection.wall_axis_max)

	var room_material := StandardMaterial3D.new()
	room_material.albedo_color = ROOM_COLOR
	var corridor_material := StandardMaterial3D.new()
	corridor_material.albedo_color = CORRIDOR_COLOR

	for room_index in rooms.size():
		var room: ProceduralRoomGenerator.RoomRecord = rooms[room_index]
		_build_floor(room, corridor_material if room.type_id == &"corridor" else room_material)
		_build_room_label(room, room_index)

		var side_openings: Dictionary = openings_by_room.get(room_index, {})
		for side: ProceduralRoomGenerator.Side in SIDES:
			if side_openings.has(side):
				_build_wall_with_doors(room, side, side_openings[side])
			else:
				_build_solid_wall(room, side)


func _add_opening(map: Dictionary, room_index: int, side: int, min_v: float, max_v: float) -> void:
	if not map.has(room_index):
		map[room_index] = {}
	if not map[room_index].has(side):
		map[room_index][side] = []
	map[room_index][side].append(Vector2(min_v, max_v))


func _build_floor(room: ProceduralRoomGenerator.RoomRecord, material: StandardMaterial3D) -> void:
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(room.rect.size.x, FLOOR_THICKNESS, room.rect.size.y)
	floor_box.position = Vector3(
			room.rect.position.x + room.rect.size.x * 0.5,
			-FLOOR_THICKNESS * 0.5,
			room.rect.position.y + room.rect.size.y * 0.5)
	floor_box.use_collision = true
	floor_box.material = material
	add_child(floor_box)


## Room index as a billboarded label at room center - always faces the
## camera (readable while walking at ground level or flying above in Free
## Mode), rather than a flat floor decal that would foreshorten badly at a
## walking-height viewing angle. Report this index plus the printed/on-screen
## seed when flagging a specific room's geometry as wrong.
func _build_room_label(room: ProceduralRoomGenerator.RoomRecord, room_index: int) -> void:
	var label := Label3D.new()
	label.text = str(room_index)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.outline_size = 14
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.position = Vector3(
			room.rect.position.x + room.rect.size.x * 0.5,
			1.2,
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


func _build_solid_wall(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side) -> void:
	var wall := _make_wall_box(room, side)
	add_child(wall)


func _build_wall_with_doors(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side,
		openings: Array) -> void:
	var geometry := _wall_geometry(room, side)
	var wall := _make_wall_box(room, side)
	add_child(wall)
	for opening: Vector2 in openings:
		var door_center := (opening.x + opening.y) * 0.5
		var door_width := opening.y - opening.x
		var axis_center: float = (
				geometry["center"].x if geometry["along_x"] else geometry["center"].y)
		var local_offset: float = door_center - axis_center
		var cut := CSGBox3D.new()
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		if geometry["along_x"]:
			cut.size = Vector3(door_width, DOOR_HEIGHT, WALL_THICKNESS + 0.2)
			cut.position = Vector3(local_offset, DOOR_HEIGHT * 0.5 - WALL_HEIGHT * 0.5, 0.0)
		else:
			cut.size = Vector3(WALL_THICKNESS + 0.2, DOOR_HEIGHT, door_width)
			cut.position = Vector3(0.0, DOOR_HEIGHT * 0.5 - WALL_HEIGHT * 0.5, local_offset)
		wall.add_child(cut)


## Insets the wall entirely inside `room`'s own footprint (instead of
## straddling the boundary line, which is where the wall would coincide
## with a neighboring room's own wall at a connection - see the _ready()
## comment on why every room draws its own wall unconditionally).
func _make_wall_box(
		room: ProceduralRoomGenerator.RoomRecord, side: ProceduralRoomGenerator.Side) -> CSGBox3D:
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
	wall.position = Vector3(center.x, WALL_HEIGHT * 0.5, center.y)
	wall.use_collision = true
	wall.material = _wall_materials[side]
	return wall
