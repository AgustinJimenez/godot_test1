extends CharacterAdapter

## Adapter for imported humanoids whose bone names do not follow one of the
## editor's built-in naming conventions. The Rig stage supplies a map from the
## canonical Mixamo-style role names to the actual Skeleton3D bone names.


func bind(parent: Node3D, at_position: Vector3, source_path: String,
		character_display_name: String, target_map: Dictionary) -> CharacterAdapter:
	var instance: Node3D = (load(source_path) as PackedScene).instantiate()
	instance.position = at_position
	parent.add_child(instance)
	node = instance
	skeleton = instance.find_child("Skeleton3D", true, false)
	if target_map.is_empty():
		for bone_index in skeleton.get_bone_count():
			var bone_name := String(skeleton.get_bone_name(bone_index))
			target_map[bone_name] = bone_name
	meshes = []
	for found: Node in instance.find_children("*", "MeshInstance3D", true, false):
		meshes.append(found as MeshInstance3D)
	mesh = meshes[0] if not meshes.is_empty() else null
	anim_player = instance.find_child("AnimationPlayer", true, false)
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		anim_player.name = &"AnimationPlayer"
		instance.add_child(anim_player)
	# Imported GLBs commonly nest Skeleton3D below an armature object instead
	# of beside AnimationPlayer. Retargeted tracks use "Skeleton3D:Bone", so
	# make the skeleton's parent the mixer's resolution root explicitly.
	anim_player.root_node = anim_player.get_path_to(skeleton.get_parent())
	display_name = character_display_name
	model_path = source_path
	humanoid_map = target_map.duplicate(true)
	has_skin = _detect_skin(meshes)
	humanoid_ready = skeleton != null and has_skin
	supports_held_object = humanoid_ready
	if humanoid_ready:
		UniversalAnimationPools.build_action_pack_library_mapped(
				skeleton, anim_player, humanoid_map)
		UniversalAnimationPools.build_human_basic_motions_library_mapped(
				skeleton, anim_player, humanoid_map)
	return self


func get_animation_groups() -> Dictionary:
	return UniversalAnimationPools.groups() if humanoid_ready else {}


func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	UniversalAnimationPools.try_play(anim_player, anim_name, blend_time)


static func _detect_skin(found_meshes: Array[MeshInstance3D]) -> bool:
	for found_mesh: MeshInstance3D in found_meshes:
		if found_mesh.skin != null or not found_mesh.skeleton.is_empty():
			return true
	return false
