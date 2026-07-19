class_name MeleeWeapon
extends Node
## Forgiving short-range damage query shared by fists and held melee items.

const DAMAGEABLE_MASK := 1 << 2

@export var hit_radius: float = 0.55


func attack(camera: Camera3D, damage: float, attack_range: float) -> bool:
	if damage <= 0.0 or attack_range <= 0.0:
		return false
	var shape := CapsuleShape3D.new()
	shape.radius = hit_radius
	shape.height = attack_range + hit_radius * 2.0
	var forward := -camera.global_transform.basis.z
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(
			Basis(Quaternion(Vector3.UP, forward)),
			camera.global_position + forward * attack_range * 0.5)
	query.collision_mask = DAMAGEABLE_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hits := camera.get_world_3d().direct_space_state.intersect_shape(query, 8)
	var nearest: Node3D
	var nearest_distance := INF
	for hit in hits:
		var collider := hit.get("collider") as Node3D
		if collider == null:
			continue
		var distance := camera.global_position.distance_squared_to(collider.global_position)
		if distance < nearest_distance:
			nearest = collider
			nearest_distance = distance
	if nearest == null:
		return false
	var health := nearest.get_node_or_null(^"Health") as Health
	if health == null:
		return false
	if health.apply_damage(damage) <= 0.0:
		return false
	_spawn_hit_effect(camera, nearest)
	return true


func _spawn_hit_effect(camera: Camera3D, target: Node3D) -> void:
	var target_point := target.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(
			camera.global_position, target_point, DAMAGEABLE_MASK)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position := target_point
	var hit_normal := (camera.global_position - target_point).normalized()
	if not hit.is_empty() and hit.get("collider") == target:
		hit_position = hit["position"]
		hit_normal = hit["normal"]
	DamageHitEffect.spawn(get_tree().current_scene, hit_position, hit_normal)
