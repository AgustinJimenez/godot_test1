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
var model_path := ""
var humanoid_map: Dictionary = {}
var has_skin := false
var humanoid_ready := true

var global_position: Vector3:
	get: return node.global_position


func get_animation_groups() -> Dictionary:
	return {}


func play_debug_anim(_anim_name: StringName, _blend_time: float = 0.2) -> void:
	pass


func set_held_flashlight_visible(_enabled: bool) -> void:
	pass


func get_global_visual_bounds() -> AABB:
	var combined := AABB()
	var has_bounds := false
	for mesh_instance in meshes:
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
			continue
		var bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		combined = combined.merge(bounds) if has_bounds else bounds
		has_bounds = true
	if has_bounds:
		return combined
	return AABB(global_position + Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 2.0, 1.0))


## Frees the wrapped character node. Called when switching to a different
## character; the adapter itself becomes unusable afterward.
func free_node() -> void:
	if is_instance_valid(node):
		node.queue_free()
