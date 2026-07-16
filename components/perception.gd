class_name Perception
extends Node
## Reusable AI senses: a vision cone (range + angle + raycast line-of-sight)
## and hearing (radius check against a target's noise_radius()). Add as a
## child of any CharacterBody3D that needs to notice the player - same
## discovery-by-name spirit as Health/Interactable, just used directly by
## the owning script instead of get_node_or_null since AI code always knows
## it has one.

@export var vision_range: float = 10.0
@export var vision_angle_deg: float = 60.0
@export var eye_height: float = 1.6
@export var target_height: float = 1.0
@export var line_of_sight_mask: int = 1

@onready var body: Node3D = get_parent()


func can_see(target: Node3D) -> bool:
	var to_target := target.global_position - body.global_position
	var dist := to_target.length()
	if dist > vision_range:
		return false
	var forward := -body.global_transform.basis.z
	var flat_dir := Vector3(to_target.x, 0.0, to_target.z).normalized()
	if rad_to_deg(forward.angle_to(flat_dir)) > vision_angle_deg * 0.5:
		return false
	var eye_pos := body.global_position + Vector3(0, eye_height, 0)
	var target_pos := target.global_position + Vector3(0, target_height, 0)
	var query := PhysicsRayQueryParameters3D.create(eye_pos, target_pos, line_of_sight_mask)
	query.exclude = [body]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func can_hear(target: Node3D) -> bool:
	if not target.has_method(&"noise_radius"):
		return false
	var noise: float = target.noise_radius()
	if noise <= 0.0:
		return false
	return body.global_position.distance_to(target.global_position) <= noise
