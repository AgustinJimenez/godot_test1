class_name PlayerBalance
extends RefCounted
## Walking carefully on a narrow platform (a beam, a pipe, a ledge): when the ground under the
## feet falls away on both sides the player slows down (no sprinting) and stretches the arms out
## sideways to balance (the hand IK of the climb module, so it works with any walk clip).
## Driven by PlayerClimb while it is FREE; `balancing` tells the others.

const SIDE_PROBE := 0.45 # m to each side of the feet where ground is looked for
const VOID_DEPTH := 0.6 # m under the feet that counts as "no ground" at the side
const SLOW_SPEED := 1.1 # m/s walk speed on a narrow platform
const ARM_SPREAD := 0.75 # m each hand goes out from the body
const ARM_HEIGHT := 1.35 # m above the feet
const ARM_RATE := 6.0 # 1/s the arms go out and come back
const HOLD_TIME := 0.25 # s the narrow reading must last (a seam in the floor is not a beam)

var balancing := false
var arm_weight := 0.0

var _player: Player
var _hands: PlayerHandHoldIKModifier
var _walk_speed := 0.0
var _sprint_speed := 0.0
var _narrow_time := 0.0
var _wide_time := 0.0


func setup(player: Player, hands: PlayerHandHoldIKModifier) -> PlayerBalance:
	_player = player
	_hands = hands
	_walk_speed = player.walk_speed
	_sprint_speed = player.sprint_speed
	return self


func update(delta: float) -> void:
	var narrow := _player.is_on_floor() and _is_narrow()
	_narrow_time = _narrow_time + delta if narrow else 0.0
	_wide_time = 0.0 if narrow else _wide_time + delta
	if not balancing and _narrow_time >= HOLD_TIME:
		balancing = true
	elif balancing and _wide_time >= HOLD_TIME:
		balancing = false
	_player.walk_speed = minf(_walk_speed, SLOW_SPEED) if balancing else _walk_speed
	_player.sprint_speed = _player.walk_speed if balancing else _sprint_speed
	arm_weight = move_toward(arm_weight, 1.0 if balancing else 0.0, ARM_RATE * delta)
	_place_arms()


## Ground under the feet but none a little to either side (the void is deeper than VOID_DEPTH).
func _is_narrow() -> bool:
	var feet := _player.global_position
	var right := _player.global_basis.x
	var mask := _player.collision_mask
	var exclude: Array[RID] = [_player.get_rid()]
	var space := _player.get_world_3d().direct_space_state
	for side: float in [-1.0, 1.0]:
		var from := feet + right * side * SIDE_PROBE + Vector3.UP * 0.3
		var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * (0.3 + VOID_DEPTH),
				mask, exclude)
		if not space.intersect_ray(query).is_empty():
			return false
	return true


func _place_arms() -> void:
	if _hands == null:
		return
	if arm_weight <= 0.0:
		if _hands.weight > 0.0 and _hands.targets.has(&"_balance"):
			_hands.weight = 0.0
			_hands.targets.clear()
		return
	var feet := _player.global_position
	var right := _player.global_basis.x
	var ahead := -_player.global_basis.z * 0.1
	var height := Vector3.UP * ARM_HEIGHT
	_hands.targets = {&"left": feet - right * ARM_SPREAD + height + ahead,
			&"right": feet + right * ARM_SPREAD + height + ahead, &"_balance": feet}
	_hands.weight = arm_weight
