class_name CharacterAdapter
extends RefCounted

## Common interface character_editor.gd needs from any character it can
## edit. The vast majority of the tool only ever touches .skeleton and
## .anim_player, which are generic Godot nodes any character exposes as-is
## - no per-character adaptation needed there. The handful of members below
## exist because PlayerBody (the only character this tool originally
## supported) has a few concepts other characters don't share:
##
## - .mesh (singular) backs the isolated-attachment-view cutaway feature,
##   which is only meaningful for a character that holds objects in the
##   first place (see supports_held_object) - characters that don't support
##   held objects never reach the code paths that touch it.
## - .meshes (plural) is for bulk operations that must apply uniformly
##   across every mesh part - mesh-visibility toggling and the
##   penetration-checker's triangle baking - since not every character is
##   one single skinned mesh the way PlayerBody's MotusMan rig is
##   (Shambler's Mixamo import is 11 separate MeshInstance3D parts).
## - get_animation_groups()/play_debug_anim()/set_held_flashlight_visible()
##   wrap character-specific animation and held-object systems that have no
##   shared base implementation to call through to.

var node: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var meshes: Array[MeshInstance3D] = []
var anim_player: AnimationPlayer
var supports_held_object := false
var supports_isolated_attachment := false
var supports_comparison := false
var display_name := ""

var global_position: Vector3:
	get: return node.global_position


func get_animation_groups() -> Dictionary:
	return {}


func play_debug_anim(_anim_name: StringName, _blend_time: float = 0.2) -> void:
	pass


func set_held_flashlight_visible(_enabled: bool) -> void:
	pass


## Frees the wrapped character node. Called when switching to a different
## character; the adapter itself becomes unusable afterward.
func free_node() -> void:
	if is_instance_valid(node):
		node.queue_free()
