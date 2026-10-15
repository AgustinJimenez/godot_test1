class_name ClimbProbe
extends RefCounted
## Finds a climbable ledge in front of the body with ray casts only (no scene knowledge): a wall
## face ahead of the chest and a flat top above it. A "ledge" is {point, normal, top}: `point` is
## where the wall face meets the top edge, `normal` the wall's horizontal normal (pointing away
## from the wall, toward the player), `top` the height of the top surface.

const WALL_HEIGHTS := [2.5, 2.0, 1.5, 1.0] # m above the feet where the wall is looked for
const WALL_REACH := 0.75 # m ahead of the capsule centre
const MIN_TOP := 1.4 # m above the feet: lower than this is walked or stepped on
const MAX_TOP := 3.2 # m above the feet: higher than a jump plus the arms can reach
const TOP_INSET := 0.12 # m behind the wall face where the top surface is sampled
const FLAT := 0.9 # normal.y of a surface that counts as a top
const SAME_TOP := 0.12 # m a ledge may rise or fall along a shimmy step


## From `feet` looking along `forward` (horizontal). {} when there is no ledge in reach.
static func find(world: World3D, feet: Vector3, forward: Vector3, mask: int,
		exclude: Array[RID]) -> Dictionary:
	var space := world.direct_space_state
	for height: float in WALL_HEIGHTS:
		var from := feet + Vector3.UP * height
		var wall := _ray(space, from, from + forward * WALL_REACH, mask, exclude)
		if wall.is_empty() or absf((wall["normal"] as Vector3).y) > 0.3:
			continue
		var normal := Vector3((wall["normal"] as Vector3).x, 0.0, (wall["normal"] as Vector3).z)
		if normal.length_squared() < 0.25:
			continue
		normal = normal.normalized()
		var at: Vector3 = wall["position"]
		var top := _top(space, at, normal, feet.y, mask, exclude)
		if top.is_empty():
			continue
		return {"point": Vector3(at.x, (top["position"] as Vector3).y, at.z),
				"normal": normal, "top": (top["position"] as Vector3).y}
	return {}


## The ledge one shimmy step further: `point` moved sideways, wall and top looked up again.
## {} at the end of the ledge (no wall, no top, or a top that jumped by more than SAME_TOP).
static func follow(world: World3D, ledge: Dictionary, point: Vector3, mask: int,
		exclude: Array[RID]) -> Dictionary:
	var space := world.direct_space_state
	var normal: Vector3 = ledge["normal"]
	var top_y: float = ledge["top"]
	var from := Vector3(point.x, top_y - 0.25, point.z) + normal * 0.5
	var wall := _ray(space, from, from - normal * 1.0, mask, exclude)
	if wall.is_empty():
		return {}
	var at: Vector3 = wall["position"]
	var top := _top(space, at, normal, top_y - 2.5, mask, exclude)
	if top.is_empty() or absf((top["position"] as Vector3).y - top_y) > SAME_TOP:
		return {}
	return {"point": Vector3(at.x, (top["position"] as Vector3).y, at.z),
			"normal": normal, "top": (top["position"] as Vector3).y}


static func _top(space: PhysicsDirectSpaceState3D, wall_at: Vector3, normal: Vector3,
		feet_y: float, mask: int, exclude: Array[RID]) -> Dictionary:
	var above := wall_at - normal * TOP_INSET
	above.y = feet_y + MAX_TOP + 0.3
	var hit := _ray(space, above, above - Vector3.UP * (MAX_TOP - MIN_TOP + 0.6), mask, exclude)
	if hit.is_empty() or (hit["normal"] as Vector3).y < FLAT:
		return {}
	var rise := (hit["position"] as Vector3).y - feet_y
	return hit if rise >= MIN_TOP and rise <= MAX_TOP else {}


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int,
		exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return space.intersect_ray(query)


## Standing at the top of a wall and facing off it: the ledge under the feet, to hang from. {} when
## the ground goes on ahead (a step, not a drop) or there is no wall face under the edge.
static func find_below(world: World3D, feet: Vector3, forward: Vector3, mask: int,
		exclude: Array[RID]) -> Dictionary:
	var space := world.direct_space_state
	var out := feet + forward * 0.8
	if not _ray(space, out + Vector3.UP * 0.1, out - Vector3.UP * 0.4, mask, exclude).is_empty():
		return {} # ground still ahead
	var from := out - Vector3.UP * 0.25
	var wall := _ray(space, from, from - forward * 1.2, mask, exclude)
	if wall.is_empty() or absf((wall["normal"] as Vector3).y) > 0.3:
		return {}
	var normal := Vector3((wall["normal"] as Vector3).x, 0.0, (wall["normal"] as Vector3).z)
	if normal.length_squared() < 0.25:
		return {}
	var at: Vector3 = wall["position"]
	return {"point": Vector3(at.x, feet.y, at.z), "normal": normal.normalized(), "top": feet.y}


## True when something solid is within `distance` below `at`.
static func ground_within(world: World3D, at: Vector3, distance: float, mask: int,
		exclude: Array[RID]) -> bool:
	return not _ray(world.direct_space_state, at + Vector3.UP * 0.1, at - Vector3.UP * distance,
			mask, exclude).is_empty()
