class_name PlayerLedgeNudge
extends RefCounted
## Foot IK v2 only plants feet on small steps; when a resting foot has no ground within reach the
## character may not hover over the drop: it walks, slowly, away from the void until both feet
## have ground (Uncharted 4's safe zone). The legs play the walk clip for that direction, so the
## feet STEP instead of the body sliding on planted feet. Returns false when v2 is not installed,
## so the player falls back to the v1-driven nudge.

const SPEED := 1.6 # m/s of the walk back to the safe zone


## True when v2 owns the ledge decision this frame.
static func nudge(player: Player, delta: float) -> bool:
	var v2 := player.body.skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	if v2 == null or not v2.enabled:
		return false
	var push := v2.ledge_push()
	if (push.is_zero_approx() or not player.is_on_floor()
			or not player._smoothed_input_dir.is_zero_approx()
			or player._stair_controller.is_climbing()):
		v2.ledge.set_step(Vector3.ZERO, player.global_basis)
		return true
	var taken := Vector3.ZERO
	# The way along the floor (uphill on a ramp is blocked for a flat push), the straight way first,
	# then each horizontal axis alone if a riser or a wall is in the way.
	var floor_normal := player.get_floor_normal()
	for way: Vector3 in [push, Vector3(push.x, 0.0, 0.0), Vector3(0.0, 0.0, push.z)]:
		if way.is_zero_approx():
			continue
		var along := (way - floor_normal * way.dot(floor_normal)).normalized() * SPEED * delta
		if player.move_and_collide(along) == null:
			taken = way
			break
	v2.ledge.set_step(taken, player.global_basis)
	return true


## The speed / move direction the walk clip is chosen from: the safe-zone walk while it lasts.
static func speed(player: Player, ground_speed: float) -> float:
	var v2 := player.body.skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	return SPEED if v2 != null and v2.ledge.stepping else ground_speed


static func input(player: Player, move_input: Vector2) -> Vector2:
	var v2 := player.body.skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	return v2.ledge.step_input if v2 != null and v2.ledge.stepping else move_input
