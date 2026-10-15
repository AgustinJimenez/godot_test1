class_name PlayerSteepSlope
extends RefCounted
## A slope steeper than the player's floor_max_angle is not ground: the body is "falling" on it,
## and move_and_slide() then slides whatever horizontal velocity is left ALONG the slope, which
## carries the body uphill while the falling animation plays. block_uphill() takes the
## into-the-slope part of the horizontal velocity away before the move, so a slope that is too steep
## stops the walk (moving sideways along it still works, and gravity does the rest).

const PROBE := 0.15 ## m ahead of the body that are tested
const MIN_NORMAL_Y := 0.15 ## flatter than this is a wall: walls do not carry the body upward


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
	var away := Vector3(normal.x, 0.0, normal.z).normalized()
	var into := horizontal.dot(away)
	if into < 0.0:
		player.velocity.x -= away.x * into
		player.velocity.z -= away.z * into
