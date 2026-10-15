class_name ClimbWall
extends RefCounted
## Free climbing on a wall of holds (bricks, pegs, handles): every Node3D in the group `climb_hold`
## is a hold, its +Z the way out of the wall. The hands sit on two holds; the stick picks the next
## hold for one hand (up, down, sideways or diagonal), alternating hands, and the body follows the
## hands. Reaching the top of the wall hands over to the ledge hang (PlayerClimb).

const GROUP := &"climb_hold"
const HAND_REACH := 0.8 # m: the farthest a hand goes from the body's shoulders
const MAX_SPREAD := 0.9 # m between the two hands
const MIN_STEP := 0.2 # m a hand has to travel to be worth moving
const MOVE_TIME := 0.4 # s one hand takes to the next hold
const REACH_ARC := 0.08 # m the moving hand lifts off the wall on the way
const BODY_RATE := 9.0 # 1/s the body follows the hands
const STICK := 0.3 # stick deflection that starts a move
const GRAB_RADIUS := 1.15 # m around the hands' rest spot a hold may be caught from
const FOOT_REST_HEIGHT := 0.2 # m above the feet where a foot looks for a hold
const FOOT_SPREAD := 0.15 # m each foot sits from the middle
const FOOT_RADIUS := 0.5 # m a foot may reach for a hold
const FOOT_ANKLE := 0.1 # m the ankle rides above the hold it stands on

var holds: Array[Node3D] = []
var normal := Vector3.BACK # out of the wall, from the first hold

var _climb: PlayerClimb
var _player: Player
var _hand_hold := {&"left": null, &"right": null} # side -> Node3D
var _moving := &"" # side of the hand in motion
var _from := Vector3.ZERO
var _to_hold: Node3D
var _t := 0.0
var _next := &"right" # the hand that moves next when both could


func setup(climb: PlayerClimb, player: Player) -> ClimbWall:
	_climb = climb
	_player = player
	return self


## The holds in the tree (called when a grab is tried: they may come and go).
func refresh() -> void:
	holds.clear()
	for node: Node in _player.get_tree().get_nodes_in_group(GROUP):
		if node is Node3D:
			holds.append(node as Node3D)


## Catch two holds near the hands' rest spot; false when none is close enough.
func begin() -> bool:
	refresh()
	var rest := _player.global_position + Vector3.UP * 1.9
	var near := _nearest(rest, null, GRAB_RADIUS)
	if near == null:
		return false
	normal = near.global_basis.z.slide(Vector3.UP).normalized()
	var right := (-normal).cross(Vector3.UP).normalized()
	var other := _nearest(near.global_position + right * 0.4, near, MAX_SPREAD)
	if other == null:
		other = _nearest(near.global_position - right * 0.4, near, MAX_SPREAD)
	if other == null:
		return false
	var near_is_left := (near.global_position - other.global_position).dot(right) < 0.0
	_hand_hold[&"left"] = near if near_is_left else other
	_hand_hold[&"right"] = other if near_is_left else near
	_moving = &""
	return true


## One physics step. `input` is x right, y backward (the move stick). Returns false when the wall
## lets go of the player (the caller then decides: ledge, drop).
func update(delta: float, input: Vector2) -> bool:
	if _moving != &"":
		_t += delta
		if _t >= MOVE_TIME:
			_hand_hold[_moving] = _to_hold
			_moving = &""
	elif input.length() > STICK:
		_start_move(input)
	_follow_body(delta)
	_place_hands()
	return true


## True when the stick asks for UP and no hold is above: the wall is over (a ledge may be near).
func at_top(input: Vector2) -> bool:
	return _moving == &"" and input.y < -STICK and _pick(Vector2(input.x, input.y), &"left") == null \
			and _pick(Vector2(input.x, input.y), &"right") == null


func hand_position(side: StringName) -> Vector3:
	var hold: Node3D = _hand_hold[side]
	var here := hold.global_position
	if side == _moving:
		var arc := Vector3(normal * sin(PI * clampf(_t / MOVE_TIME, 0.0, 1.0)) * REACH_ARC)
		return _from.lerp(_to_hold.global_position, smoothstep(0.0, 1.0, _t / MOVE_TIME)) + arc
	return here


func body_anchor() -> Vector3:
	var mid := (hand_position(&"left") + hand_position(&"right")) * 0.5
	return Vector3(mid.x, mid.y - _climb.hang_drop(), mid.z) + normal * PlayerClimb.SHOULDER_BACK


func _start_move(input: Vector2) -> void:
	var order: Array[StringName] = [_next, &"left" if _next == &"right" else &"right"]
	for side: StringName in order:
		var target := _pick(input, side)
		if target != null:
			_moving = side
			_from = (_hand_hold[side] as Node3D).global_position
			_to_hold = target
			_t = 0.0
			_next = &"left" if side == &"right" else &"right"
			return


## The hold `side`'s hand should go to for the stick direction, null when there is none.
func _pick(input: Vector2, side: StringName) -> Node3D:
	var right := (-normal).cross(Vector3.UP).normalized()
	var dir := (right * input.x + Vector3.UP * -input.y).normalized()
	var here := (_hand_hold[side] as Node3D).global_position
	var other := (_hand_hold[&"left" if side == &"right" else &"right"] as Node3D).global_position
	var shoulders := _player.global_position + Vector3.UP * (_climb.hang_drop() - 0.1)
	var best: Node3D = null
	var best_score := 0.0
	for hold: Node3D in holds:
		var at := hold.global_position
		var delta := at - here
		var along := delta.dot(dir)
		if along < MIN_STEP * 0.5 or delta.length() < MIN_STEP or at.distance_to(other) > MAX_SPREAD:
			continue
		if at.distance_to(shoulders) > HAND_REACH + 0.25 or at.distance_to(other) < 0.12:
			continue
		var score := along - 0.6 * (delta - dir * along).length()
		if score > best_score:
			best_score = score
			best = hold
	return best


func _nearest(point: Vector3, skip: Node3D, radius: float) -> Node3D:
	var best: Node3D = null
	var best_distance := radius
	for hold: Node3D in holds:
		var distance := hold.global_position.distance_to(point)
		if hold != skip and distance < best_distance:
			best_distance = distance
			best = hold
	return best


func _follow_body(delta: float) -> void:
	var goal := body_anchor()
	_player.global_position = _player.global_position.lerp(goal, 1.0 - exp(-BODY_RATE * delta))
	_climb.face(-normal, delta)


func _place_hands() -> void:
	if _climb.hands == null:
		return
	_climb.hands.targets = {&"left": hand_position(&"left"), &"right": hand_position(&"right")}
	_climb.hands.weight = 1.0
	_place_feet()


## True when the stick asks for a way and neither hand has a hold that way.
func pick_blocked(input: Vector2) -> bool:
	return _moving == &"" and _pick(input, &"left") == null and _pick(input, &"right") == null


## Each foot on the nearest hold under the hips (none close enough: the leg just hangs).
func _place_feet() -> void:
	var hands := _climb.hands
	hands.foot_targets.clear()
	var right := (-normal).cross(Vector3.UP).normalized()
	var taken: Node3D = null
	for side: StringName in [&"left", &"right"]:
		var rest := _player.global_position - normal * PlayerClimb.SHOULDER_BACK \
				+ Vector3.UP * FOOT_REST_HEIGHT \
				+ right * (-FOOT_SPREAD if side == &"left" else FOOT_SPREAD)
		var hold := _nearest(rest, taken, FOOT_RADIUS)
		if hold == null:
			continue
		taken = hold
		hands.foot_targets[side] = hold.global_position + normal * 0.1 + Vector3.UP * FOOT_ANKLE
	hands.knee_way = (normal + Vector3.UP * 0.3).normalized()
	hands.foot_weight = 1.0 if not hands.foot_targets.is_empty() else 0.0
