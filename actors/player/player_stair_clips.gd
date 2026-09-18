class_name PlayerStairClips
extends RefCounted
## Authored stair-walk clips (031), retargeted from Mixamo (tools/retarget_cli.gd). Used in place
## of the flat walk clip while the character is on the staircase, so the base pose matches the
## terrain. Kept out of player_body.gd (at the linter's line cap).

const DIR := "res://assets/models/stair_clips/"
const CLIPS: Dictionary = {
	&"unarmed_stair_up": "stair_walk_up",
	&"unarmed_stair_down": "stair_walk_down",
}
## FootIKStairSurfaces authors every stair tread/riser/traversal/landing collider on this layer.
const STAIR_CONTACT_LAYER := 1 << 5
## Ground distance the authored clip itself covers per second at 1x playback (0.467 m per 1.183 s
## cycle - 2 steps of ~0.23 m). The flat walk reference (1.6 m/s) is ~4x this, so playing the stair
## clip at the walk rate makes its steps cover only a quarter of the travel and the feet skate.
const REF_SPEED := 0.395


static func add_to(library: AnimationLibrary) -> void:
	for gameplay_name: StringName in CLIPS:
		var clip := load(DIR + CLIPS[gameplay_name] + ".res") as Animation
		if clip != null:
			library.add_animation(gameplay_name, clip)


## Continuous "is this character on the staircase" signal: a raycast straight down from the body
## onto the authored stair surfaces (their own collision layer). Unlike the stair predictor's
## ownership or the controller's transition flags - both intermittent - this is true for the whole
## climb, including the traversal ramp and the top landing.
static func on_staircase(body: Node3D) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
			body.global_position + Vector3.UP * 0.3, body.global_position - Vector3.UP * 1.2)
	query.collision_mask = STAIR_CONTACT_LAYER
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	return not space.intersect_ray(query).is_empty()


## Pick the walk clip for the current terrain: the authored stair clip while on the staircase.
## Gating the swap to the clip's loop seam was tested and gave a worse result (the stair clip then
## started late, leaving the lower stairs on the flat clip and keeping the 50deg retry spike) than
## switching as soon as the region is entered.
static func select_walk(body: Node3D, base: StringName, descending: bool) -> StringName:
	if base != &"unarmed_walk" or not on_staircase(body):
		return base
	return &"unarmed_stair_down" if descending else &"unarmed_stair_up"


static func is_stair_target(target: StringName) -> bool:
	return target in CLIPS


## Playback rate for a walk target: stair clips use their own authored ground speed so their stride
## matches the distance actually travelled; everything else keeps the caller's flat-walk rate.
static func walk_rate(target: StringName, ground_speed: float, fallback: float) -> float:
	return ground_speed / REF_SPEED if is_stair_target(target) else fallback
