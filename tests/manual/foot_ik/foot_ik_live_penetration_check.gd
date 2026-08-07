class_name FootIkLivePenetrationCheck
extends RefCounted
## Mesh-vs-floor penetration check for the interactive $Player, not the
## automated stair walker (see foot_ik_preview.gd's _sample_body_stair_
## penetration, which uses stair-tread math specific to that walker). This
## one raycasts straight down from each skinned mesh vertex against the
## real physics floor collider instead, so it works on any surface - flat,
## ramp, or stairs - not just discrete treads. Split into its own file to
## keep foot_ik_debug_overlay.gd under the project's max-file-lines cap.
##
## Opt-in via a marker file (see foot_ik_debug_overlay.gd), not always-on:
## a raycast per mesh vertex every physics frame is the right cost for a
## focused diagnostic session, not for ordinary interactive play/testing.
const TOLERANCE := 0.005 # matches FOOT_IK_BODY_PENETRATION_CHECK's tolerance
const GROUND_COLLISION_MASK := 1
const RAY_UP := 0.3
const RAY_DOWN := 0.1

var attempts := 0
var unavailable := 0
var missing_mesh := 0
var samples := 0
var penetrating_samples := 0
var penetrating_vertices := 0
var max_depth := 0.0
var penetrating_bones: Dictionary = {} # bone name -> count


## Returns this call's own vertices/max_depth (not the running totals below) -
## exit_tree() isn't reliably called by the MCP stop_scene_in_editor() path,
## so foot_ik_debug_overlay.gd folds this per-frame result straight into the
## JSONL trace instead of relying on format_result() ever printing.
func sample(player: Player, ik: PlayerFootIKModifier) -> Dictionary:
	attempts += 1
	var mesh_nodes := player.body.character.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		unavailable += 1
		missing_mesh += 1
		return {"available": false}
	var skeleton := player.skeleton
	if skeleton == null or ik == null:
		unavailable += 1
		return {"available": false}
	var space := player.get_world_3d().direct_space_state
	var exclude_rid := player.get_rid()
	# foot_ik_preview.tscn lays out many other platforms/idle characters side
	# by side, all on the same GROUND_COLLISION_MASK - an unscoped per-vertex
	# raycast routinely hit a NEIGHBORING platform instead of the one $Player
	# actually stands on, reading as widespread torso/head "penetration" that
	# was really just nearby, unrelated geometry. Only the one collider
	# directly under the player counts.
	var floor_rid := _find_floor_rid(space, player, exclude_rid)
	if not floor_rid.is_valid():
		unavailable += 1
		return {"available": false}
	samples += 1
	var sample_vertices := 0
	var sample_max_depth := 0.0
	var sample_bones: Dictionary = {} # this call's own breakdown, not the cumulative totals below
	for mesh_node: Node in mesh_nodes:
		var mesh_part := mesh_node as MeshInstance3D
		if mesh_part.mesh == null:
			continue
		var bind_transforms := _mesh_bind_transforms(mesh_part, skeleton, ik)
		var bind_bone_names := _mesh_bind_bone_names(mesh_part, skeleton)
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array
					if arrays[Mesh.ARRAY_BONES] is PackedInt32Array else PackedInt32Array())
			var weights := (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
					if arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array else PackedFloat32Array())
			var influences_per_vertex := (
					bones.size() / vertices.size() if not vertices.is_empty() else 0)
			for vertex_index in vertices.size():
				var world_vertex := mesh_part.global_transform * vertices[vertex_index]
				if influences_per_vertex > 0 and not weights.is_empty():
					world_vertex = _skin_vertex(
							vertex_index, vertices, bones, weights, bind_transforms, world_vertex)
				var depth := _floor_penetration_depth(space, world_vertex, exclude_rid, floor_rid)
				if depth <= TOLERANCE:
					continue
				sample_vertices += 1
				sample_max_depth = maxf(sample_max_depth, depth)
				var dominant_bone := _dominant_skin_bone(
						vertex_index, vertices, bones, weights, bind_bone_names)
				penetrating_bones[dominant_bone] = int(
						penetrating_bones.get(dominant_bone, 0)) + 1
				sample_bones[dominant_bone] = int(sample_bones.get(dominant_bone, 0)) + 1
	if sample_vertices > 0:
		penetrating_samples += 1
		penetrating_vertices += sample_vertices
		max_depth = maxf(max_depth, sample_max_depth)
	return {"available": true, "vertices": sample_vertices, "max_depth": sample_max_depth,
			"bones": sample_bones}


## Positive when world_vertex sits below floor_rid's actual top surface - a
## ray from above it must cross that surface before reaching the vertex. A
## hit on any OTHER collider (a neighboring platform) is ignored outright,
## not just excluded - it says nothing about this vertex's own floor.
func _floor_penetration_depth(space: PhysicsDirectSpaceState3D, world_vertex: Vector3,
		exclude_rid: RID, floor_rid: RID) -> float:
	var query := PhysicsRayQueryParameters3D.create(
			world_vertex + Vector3.UP * RAY_UP, world_vertex + Vector3.DOWN * RAY_DOWN)
	query.collision_mask = GROUND_COLLISION_MASK
	query.collide_with_areas = false
	query.exclude = [exclude_rid]
	var result := space.intersect_ray(query)
	if result.is_empty() or (result["rid"] as RID) != floor_rid:
		return 0.0
	return maxf(0.0, (result["position"] as Vector3).y - world_vertex.y)


## One reference raycast straight down from the player's own position,
## excluding the player's own capsule - whatever it hits is "the floor" for
## this sample; every per-vertex check below only counts hits on that same
## collider, so a torso vertex leaning near a different, nearby platform in
## this crowded preview scene can never register as penetrating that one.
func _find_floor_rid(space: PhysicsDirectSpaceState3D, player: Player, exclude_rid: RID) -> RID:
	var query := PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3.UP * 0.1, player.global_position + Vector3.DOWN * 2.0)
	query.collision_mask = GROUND_COLLISION_MASK
	query.collide_with_areas = false
	query.exclude = [exclude_rid]
	var result := space.intersect_ray(query)
	return result["rid"] as RID if not result.is_empty() else RID()


func _mesh_bind_transforms(mesh_part: MeshInstance3D, skeleton: Skeleton3D,
		ik: PlayerFootIKModifier) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var skin_reference := mesh_part.get_skin_reference()
	if skin_reference == null:
		return result
	var skin := skin_reference.get_skin()
	if skin == null:
		return result
	result.resize(skin.get_bind_count())
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = skeleton.find_bone(skin.get_bind_name(bind_index))
		if bone_index < 0:
			result[bind_index] = Transform3D.IDENTITY
			continue
		var pose: Transform3D = skeleton.get_bone_global_pose(bone_index)
		if ik._final_bone_poses.has(bone_index):
			pose = ik._final_bone_poses[bone_index]
		result[bind_index] = skeleton.global_transform * pose * skin.get_bind_pose(bind_index)
	return result


func _mesh_bind_bone_names(
		mesh_part: MeshInstance3D, skeleton: Skeleton3D) -> Array[StringName]:
	var result: Array[StringName] = []
	var skin_reference := mesh_part.get_skin_reference()
	if skin_reference == null or skin_reference.get_skin() == null:
		return result
	var skin := skin_reference.get_skin()
	result.resize(skin.get_bind_count())
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = skeleton.find_bone(skin.get_bind_name(bind_index))
		result[bind_index] = skeleton.get_bone_name(bone_index) if bone_index >= 0 else &"unknown"
	return result


func _dominant_skin_bone(vertex_index: int, vertices: PackedVector3Array,
		bones: PackedInt32Array, weights: PackedFloat32Array,
		bind_bone_names: Array[StringName]) -> StringName:
	if vertices.is_empty() or bones.is_empty() or weights.is_empty():
		return &"unskinned"
	var influences_per_vertex := bones.size() / vertices.size()
	var best_weight := -1.0
	var best_bind := -1
	for influence in influences_per_vertex:
		var array_index := vertex_index * influences_per_vertex + influence
		if weights[array_index] > best_weight:
			best_weight = weights[array_index]
			best_bind = bones[array_index]
	return (bind_bone_names[best_bind]
			if best_bind >= 0 and best_bind < bind_bone_names.size() else &"unknown")


func _skin_vertex(vertex_index: int, vertices: PackedVector3Array,
		bones: PackedInt32Array, weights: PackedFloat32Array,
		bind_transforms: Array[Transform3D], fallback: Vector3) -> Vector3:
	var influences_per_vertex := bones.size() / vertices.size()
	var result := Vector3.ZERO
	var total_weight := 0.0
	for influence in influences_per_vertex:
		var array_index := vertex_index * influences_per_vertex + influence
		var weight: float = weights[array_index]
		var bind_index: int = bones[array_index]
		if weight <= 0.0 or bind_index < 0 or bind_index >= bind_transforms.size():
			continue
		result += (bind_transforms[bind_index] * vertices[vertex_index]) * weight
		total_weight += weight
	return result / total_weight if total_weight > 0.0 else fallback


func format_result() -> String:
	var result := "FAIL" if penetrating_samples > 0 else "PASS"
	return ("FOOT_IK_LIVE_PENETRATION_CHECK %s samples=%d attempts=%d unavailable=%d " +
			"missing_mesh=%d penetrating_samples=%d penetrating_vertices=%d max_depth_m=%s " +
			"tolerance_m=%s bones=%s") % [result, samples, attempts, unavailable, missing_mesh,
			penetrating_samples, penetrating_vertices, snappedf(max_depth, 0.000001),
			TOLERANCE, penetrating_bones]
