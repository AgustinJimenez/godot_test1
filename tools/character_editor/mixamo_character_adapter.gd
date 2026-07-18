class_name MixamoCharacterAdapter
extends CharacterAdapter

## Generic adapter for any standalone Mixamo character FBX that uses the
## standard "mixamorig_"-prefixed skeleton (the same convention as
## Shambler's "The Boss.fbx") - covers every character under
## assets/models/mixamo_characters/ except the Ch08/10_nonPBR pair, whose
## numbered-prefix convention needs RetargetedMixamoAdapter instead. Pulls
## its animations entirely from UniversalAnimationPools (action_adventure_
## pack + Human Basic Motions FREE) rather than any character-specific
## source, since "mixamorig_" is exactly action_adventure_pack's own prefix
## - a plain copy, no bone-name swap even needed.
##
## Replaces the old character-specific shambler_adapter.gd - "shambler" is
## just another entry in character_editor.gd's MIXAMO_CHARACTERS table now.

const _BONE_PREFIX := "mixamorig_"

var _anim_player: AnimationPlayer


static func create(parent: Node3D, at_position: Vector3, model_path: String,
		character_display_name: String) -> MixamoCharacterAdapter:
	var instance: Node3D = (load(model_path) as PackedScene).instantiate()
	instance.position = at_position
	parent.add_child(instance)
	var adapter := MixamoCharacterAdapter.new()
	adapter._bind(instance, character_display_name)
	return adapter


func _bind(instance: Node3D, character_display_name: String) -> void:
	node = instance
	skeleton = instance.get_node(^"Skeleton3D")
	meshes = []
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	mesh = meshes[0] if not meshes.is_empty() else null
	_anim_player = instance.get_node(^"AnimationPlayer")
	anim_player = _anim_player
	supports_held_object = false
	supports_comparison = false
	display_name = character_display_name
	UniversalAnimationPools.build_action_pack_library(skeleton, _anim_player, _BONE_PREFIX)
	UniversalAnimationPools.build_human_basic_motions_library(skeleton, _anim_player, _BONE_PREFIX)


func get_animation_groups() -> Dictionary:
	return UniversalAnimationPools.groups()


func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	UniversalAnimationPools.try_play(_anim_player, anim_name, blend_time)
