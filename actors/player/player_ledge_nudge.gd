class_name PlayerLedgeNudge
extends RefCounted
## Foot IK v2 only plants feet on small steps; when a resting foot has no ground within reach the
## character may not hover over the drop: it slides, slowly, away from the void until both feet
## have ground (Uncharted 4's safe zone). Returns false when v2 is not installed, so the player
## falls back to the v1-driven nudge.

const SPEED := 3.0 # m/s of the slide back to the safe zone (1.2 looked like a slow float)


## True when v2 owns the ledge decision this frame.
static func nudge(player: Player, delta: float) -> bool:
	var v2 := player.body.skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	if v2 == null or not v2.enabled:
		return false
	if (not player.is_on_floor() or not player._smoothed_input_dir.is_zero_approx()
			or player._stair_controller.is_climbing()):
		return true
	var push := v2.ledge_push()
	if push.is_zero_approx():
		return true
	# The way along the floor (uphill on a ramp is blocked for a flat push), the straight way first,
	# then each horizontal axis alone if a riser or a wall is in the way.
	var floor_normal := player.get_floor_normal()
	for way: Vector3 in [push, Vector3(push.x, 0.0, 0.0), Vector3(0.0, 0.0, push.z)]:
		if way.is_zero_approx():
			continue
		var along := (way - floor_normal * way.dot(floor_normal)).normalized() * SPEED * delta
		if player.move_and_collide(along) == null:
			break
	return true
