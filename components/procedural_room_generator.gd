class_name ProceduralRoomGenerator
extends RefCounted
## Phase 1 of docs/procedural_room_generation_plan.md: generates a finite,
## seeded batch of connected rooms as plain data (no 3D nodes) - axis-aligned
## rectangles on the XZ ground plane, each new room attached to an existing
## one through a walkable opening in their shared wall. See the plan doc for
## the full algorithm writeup and open-question resolutions this implements.

const HUMAN_WIDTH := 1.0
const MIN_ROOM_PADDING := 1.0
const MAX_CONNECTION_ATTEMPTS := 20
const MAX_TOTAL_ATTEMPTS := 2000

## Weighted room types. "room" is a square with a randomized side length;
## "corridor" is always elongated along whichever axis points away from its
## connecting wall, with a fixed narrow width across it.
const ROOM_TYPES := [
	{"id": &"room", "weight": 70.0, "square_size_min": 4.0, "square_size_max": 30.0},
	{
		"id": &"corridor", "weight": 30.0,
		"width_min": 2.0, "width_max": 4.0,
		"length_min": 6.0, "length_max": 40.0,
	},
]

enum Side { NORTH, SOUTH, EAST, WEST } ## which wall of the anchor the new room connects through

class RoomRecord:
	extends RefCounted
	var type_id: StringName
	var rect: Rect2 ## position = min corner, size = (width along X, depth along Z)

class ConnectionRecord:
	extends RefCounted
	var room_a: int ## index into the generated rooms array (the anchor)
	var room_b: int ## index into the generated rooms array (the new room)
	var side: Side ## which wall of room_a the connection sits on
	var wall_axis_min: float ## opening's extent along the shared wall, world space
	var wall_axis_max: float


static func generate(target_room_count: int, generation_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if generation_seed == 0:
		rng.randomize()
		generation_seed = rng.seed
	else:
		rng.seed = generation_seed

	var rooms: Array[RoomRecord] = []
	var connections: Array[ConnectionRecord] = []

	var first := RoomRecord.new()
	first.type_id = &"room"
	var first_size := rng.randf_range(
			ROOM_TYPES[0]["square_size_min"], ROOM_TYPES[0]["square_size_max"])
	first.rect = Rect2(Vector2(-first_size * 0.5, -first_size * 0.5), Vector2(first_size, first_size))
	rooms.append(first)

	var anchor_index := 0
	var total_attempts := 0

	while rooms.size() < target_room_count and total_attempts < MAX_TOTAL_ATTEMPTS:
		var placed := false

		for connection_attempt in range(MAX_CONNECTION_ATTEMPTS):
			total_attempts += 1
			if total_attempts >= MAX_TOTAL_ATTEMPTS:
				break

			var type: Dictionary = _pick_weighted_type(rng)
			var side: Side = rng.randi_range(0, 3) as Side
			var anchor: RoomRecord = rooms[anchor_index]

			var result := _try_place_room(rng, anchor, anchor_index, side, type)
			if result.is_empty():
				continue

			var candidate: RoomRecord = result["room"]
			if _collides_with_any(candidate.rect, rooms, anchor_index):
				continue

			rooms.append(candidate)
			var connection: ConnectionRecord = result["connection"]
			connection.room_b = rooms.size() - 1
			connections.append(connection)
			anchor_index = rooms.size() - 1
			placed = true
			break

		if not placed:
			anchor_index = rng.randi_range(0, rooms.size() - 1)

	return {
		"rooms": rooms,
		"connections": connections,
		"seed_used": generation_seed,
	}


static func _pick_weighted_type(rng: RandomNumberGenerator) -> Dictionary:
	var total_weight := 0.0
	for type: Dictionary in ROOM_TYPES:
		total_weight += type["weight"]
	var roll := rng.randf() * total_weight
	var cumulative := 0.0
	for type: Dictionary in ROOM_TYPES:
		cumulative += type["weight"]
		if roll <= cumulative:
			return type
	return ROOM_TYPES[-1]


## Builds a candidate room and its connection against `anchor`'s given wall,
## or returns {} if the opening can't fit (e.g. anchor wall too short for
## even the human-minimum opening). Does not check collisions against other
## rooms - the caller does that with the returned candidate's rect.
static func _try_place_room(
		rng: RandomNumberGenerator, anchor: RoomRecord, anchor_index: int,
		side: Side, type: Dictionary) -> Dictionary:
	var away_is_x := side == Side.EAST or side == Side.WEST
	var anchor_wall_length := anchor.rect.size.y if away_is_x else anchor.rect.size.x

	var new_width: float
	var new_length: float ## along the away axis
	if type["id"] == &"corridor":
		new_width = rng.randf_range(type["width_min"], type["width_max"])
		new_length = rng.randf_range(type["length_min"], type["length_max"])
	else:
		var square_size := rng.randf_range(type["square_size_min"], type["square_size_max"])
		new_width = square_size
		new_length = square_size

	var new_wall_length := new_width
	var opening_size := rng.randf_range(HUMAN_WIDTH, min(anchor_wall_length, new_wall_length))
	if opening_size < HUMAN_WIDTH:
		return {}

	var anchor_wall_start := anchor.rect.position.y if away_is_x else anchor.rect.position.x
	var opening_start := rng.randf_range(
			anchor_wall_start, anchor_wall_start + anchor_wall_length - opening_size)
	var opening_center := opening_start + opening_size * 0.5

	var new_wall_start := opening_center - new_wall_length * 0.5
	# Keep the opening fully inside the new room's own wall segment too.
	new_wall_start = clamp(
			new_wall_start, opening_start + opening_size - new_wall_length, opening_start)

	var candidate := RoomRecord.new()
	candidate.type_id = type["id"]

	var along_axis_position: float
	match side:
		Side.NORTH:
			along_axis_position = anchor.rect.position.y - new_length
		Side.SOUTH:
			along_axis_position = anchor.rect.position.y + anchor.rect.size.y
		Side.EAST:
			along_axis_position = anchor.rect.position.x + anchor.rect.size.x
		Side.WEST:
			along_axis_position = anchor.rect.position.x - new_length

	if away_is_x:
		candidate.rect = Rect2(
				Vector2(along_axis_position, new_wall_start), Vector2(new_length, new_wall_length))
	else:
		candidate.rect = Rect2(
				Vector2(new_wall_start, along_axis_position), Vector2(new_wall_length, new_length))

	var connection := ConnectionRecord.new()
	connection.room_a = anchor_index
	connection.side = side
	connection.wall_axis_min = opening_start
	connection.wall_axis_max = opening_start + opening_size

	return {"room": candidate, "connection": connection}


static func _collides_with_any(rect: Rect2, rooms: Array[RoomRecord], skip_index: int) -> bool:
	var padded := rect.grow(MIN_ROOM_PADDING * 0.5)
	for i in rooms.size():
		if i == skip_index:
			continue
		if padded.intersects(rooms[i].rect.grow(MIN_ROOM_PADDING * 0.5)):
			return true
	return false
