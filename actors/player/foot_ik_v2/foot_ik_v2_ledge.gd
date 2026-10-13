class_name FootIKV2Ledge
extends RefCounted
## Which way the body should walk so both feet have ground (Uncharted 4's safe zone), from the feet
## that stand over a drop. PlayerLedgeNudge moves the capsule along `push()`.
## The way is found by probing the floor around each such foot for the nearest ground the body
## can stand on (not just "away from the foot": at a tread edge the foot sits to the SIDE of the
## body and the void is in FRONT of it, so away-from-the-foot walked the body along the edge).

const DROP := 0.25 # m: ground lower than this below the body is not ground to stand on
const RADII := [0.15, 0.3, 0.45]
const DIRECTIONS := 8

var ray: Callable # (point, hip) -> the floor hit under `point`, {} if none
var stepping := false
var step_input := Vector2.ZERO
var _over: Dictionary = {} # side -> [body, ankle, hip] of a foot over a drop


## A foot over a drop (or past the limit). All three are world positions.
func over_drop(side: StringName, body: Vector3, ankle: Vector3, hip: Vector3) -> void:
	_over[side] = [body, ankle, hip]


func on_ground(side: StringName) -> void:
	_over.erase(side)


func push() -> Vector3:
	var total := Vector3.ZERO
	for args: Array in _over.values():
		total += _safe_way(args[0], args[1], args[2])
	return total.normalized()


## The horizontal direction from `ankle` to the nearest ground at the body's level; the way to the
## body when there is none (or no probe).
func _safe_way(body: Vector3, ankle: Vector3, hip: Vector3) -> Vector3:
	var toward := Vector3(body.x - ankle.x, 0.0, body.z - ankle.z).normalized()
	if not ray.is_valid():
		return toward
	for radius: float in RADII:
		var best := Vector3.ZERO
		var best_dot := -2.0
		for index in DIRECTIONS:
			var way := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / DIRECTIONS)
			var hit: Dictionary = ray.call(ankle + way * radius, hip)
			if (hit.is_empty() or body.y - (hit["position"] as Vector3).y > DROP
					or (hit["normal"] as Vector3).y < 0.7):
				continue
			if way.dot(toward) > best_dot: # of the ones with ground, the one toward the body
				best_dot = way.dot(toward)
				best = way
		if best != Vector3.ZERO:
			return best
	return toward


## `stepping`: the body walks to the safe zone, so the legs STEP there (a walk clip) instead of the
## whole body sliding on planted feet. `step_input` is the move direction in the body's frame
## (x right, y backward) that picks the walk clip.
func set_step(world_way: Vector3, body_basis: Basis) -> void:
	stepping = not world_way.is_zero_approx()
	var local := body_basis.inverse() * world_way
	step_input = Vector2(local.x, local.z) if stepping else Vector2.ZERO
