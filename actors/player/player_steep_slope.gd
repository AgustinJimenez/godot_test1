class_name PlayerSteepSlope
extends RefCounted
## A slope steeper than the player's floor_max_angle is not ground: the body is "falling" on it,
## and move_and_slide() then slides whatever horizontal velocity is left ALONG the slope, which
## carries the body uphill while the falling animation plays. block_uphill() takes the
## into-the-slope part of the horizontal velocity away before the move, so a slope that is too steep
## stops the walk (moving sideways along it still works, and gravity does the rest).

const PROBE := 0.15 ## m ahead of the body that are tested
const MIN_NORMAL_Y := 0.15 ## flatter than this is a wall: walls do not carry the body upward
const TREAD_NORMAL_Y := 0.7 ## a surface this flat just past the contact, within step_height above the feet, is a tread: the stair step-up climbs it


static func block_uphill(player: Player) -> void:
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if horizontal.length_squared() < 0.0001:
		return
	var hit := KinematicCollision3D.new()
	if not player.test_move(player.global_transform, horizontal.normalized() * PROBE, hit):
		return
	var normal := hit.get_normal()
	if normal.y < MIN_NORMAL_Y or normal.angle_to(Vector3.UP) <= player.floor_max_angle + 0.01:
		return
	if _is_step_edge(player, hit, horizontal.normalized()):
		return
	var away := Vector3(normal.x, 0.0, normal.z).normalized()
	var into := horizontal.dot(away)
	if into < 0.0:
		player.velocity.x -= away.x * into
		player.velocity.z -= away.z * into


## The capsule's rounded bottom touching a step's top edge reads a steep normal (63 degrees on a 0.2 m riser, past the 45 of the default floor angle),
## which took the whole walk velocity away so the stair step-up never saw any motion and the player stood in front of the first riser for good.
## A step edge has a flat tread just beyond the contact, at most step_height above the feet; a slope that really is too steep has none (its own
## surface, steep, is what is found there).
static func _is_step_edge(player: Player, contact: KinematicCollision3D, direction: Vector3) -> bool:
	var beyond := contact.get_position() + direction * PROBE * 0.4
	var feet := player.global_position.y
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(beyond.x, feet + player.step_height + 0.05, beyond.z), Vector3(beyond.x, feet, beyond.z), player.collision_mask)
	query.exclude = [player.get_rid()]
	var tread := player.get_world_3d().direct_space_state.intersect_ray(query)
	if tread.is_empty():
		return false
	var rise: float = (tread["position"] as Vector3).y - feet
	return (tread["normal"] as Vector3).y >= TREAD_NORMAL_Y and rise > 0.01 and rise <= player.step_height + 0.05
