class_name ShamblerAdapter
extends CharacterAdapter

## Wraps "The Boss.fbx" directly, not the full actors/enemies/shambler/
## shambler.tscn - that scene's CharacterBody3D root brings AI state
## machine, navigation, patrol, and combat logic that would otherwise start
## running the moment it entered the tree (shambler.gd's _ready() kicks off
## patrolling), none of which applies inside a pose-editing tool. The raw
## model has no such baggage: just a Skeleton3D, its mesh parts, and an
## AnimationPlayer with no animations of its own until Shambler.
## build_clip_library() (extracted from shambler.gd, same mechanism the
## real enemy uses) borrows the standalone pack clips into it.
##
## Unlike PlayerBody's single MotusMan mesh, this rig is 11 separate
## MeshInstance3D parts (jacket, pants, head, etc.) under one Skeleton3D -
## see .meshes on the base class for where that matters.

const _MODEL_PATH := "res://assets/models/action_adventure_pack/The Boss.fbx"
const _ANIMATION_GROUP := &"Enemy - Shambler"

var _anim_player: AnimationPlayer


static func create(parent: Node3D, at_position: Vector3) -> ShamblerAdapter:
	var instance: Node3D = (load(_MODEL_PATH) as PackedScene).instantiate()
	instance.name = &"Boss"
	instance.position = at_position
	parent.add_child(instance)
	var adapter := ShamblerAdapter.new()
	adapter._bind(instance)
	return adapter


func _bind(boss: Node3D) -> void:
	node = boss
	skeleton = boss.get_node(^"Skeleton3D")
	meshes = []
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	mesh = meshes[0] if not meshes.is_empty() else null
	_anim_player = boss.get_node(^"AnimationPlayer")
	anim_player = _anim_player
	supports_held_object = false
	supports_comparison = false
	display_name = "Shambler"
	Shambler.build_clip_library(_anim_player)


func get_animation_groups() -> Dictionary:
	var clips: Array[StringName] = []
	for key: StringName in Shambler.CLIPS:
		clips.append(key)
	clips.append(&"death")
	return {_ANIMATION_GROUP: clips}


func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	var path := "pack/" + String(anim_name)
	if _anim_player.has_animation(path):
		_anim_player.play(path, blend_time)
