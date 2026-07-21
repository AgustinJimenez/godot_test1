class_name PlayerBodyAdapter
extends CharacterAdapter

## Wraps the player character the same way actors/player/player.tscn's own
## "Body" node does - a generic Node3D with player_body.gd attached, whose
## _ready() instantiates character_scene (MotusMan by default) as a child
## itself - not the full player.tscn (which pulls in gameplay-only pieces
## like weapons and the camera controller that this tool has no use for).
##
## Also merges in UniversalAnimationPools (action_adventure_pack + Human
## Basic Motions FREE) alongside PlayerBody's own native/UAL/UAL2 groups -
## MotusMan's skeleton uses the exact same bone hierarchy/naming as a
## standard Mixamo rig, just with an empty prefix instead of "mixamorig_"
## (confirmed by inspection: player_body.gd's own UAL retarget BONE_MAP
## targets "Hips"/"LeftShoulder"/"RightHandIndex1"/etc. directly - Mixamo's
## naming convention with the prefix stripped). Done here rather than in
## player_body.gd itself so the tested, gameplay-critical retarget system
## stays untouched; this only ever adds extra libraries onto the same
## AnimationPlayer.

const _MODEL_PATH := (
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Aim_Idle_IPC.fbx")
const _SCRIPT_PATH := "res://actors/player/player_body.gd"
const _BONE_PREFIX := ""


static func create(parent: Node3D, at_position: Vector3) -> PlayerBodyAdapter:
	var instance := Node3D.new()
	instance.name = &"Body"
	instance.position = at_position
	instance.set_script(load(_SCRIPT_PATH))
	# Already player_body.gd's own default - set explicitly anyway so this
	# tool's behavior stays pinned to MotusMan specifically even if that
	# script's default is ever repointed at a different character.
	instance.set("character_scene", load(_MODEL_PATH))
	instance.set("autoplay_default_animation", false)
	parent.add_child(instance)
	var adapter := PlayerBodyAdapter.new()
	adapter._bind(instance)
	return adapter


func _bind(player_body: Node) -> void:
	node = player_body
	skeleton = player_body.skeleton
	mesh = player_body.mesh
	meshes = [player_body.mesh]
	anim_player = player_body.anim_player
	supports_held_object = true
	supports_isolated_attachment = true
	supports_comparison = true
	display_name = "Player"
	UniversalAnimationPools.build_action_pack_library(skeleton, anim_player, _BONE_PREFIX)
	UniversalAnimationPools.build_human_basic_motions_library(skeleton, anim_player, _BONE_PREFIX)


func get_animation_groups() -> Dictionary:
	var groups: Dictionary = node.get_animation_groups()
	var pools := UniversalAnimationPools.groups()
	for group_name: StringName in pools:
		groups[group_name] = pools[group_name]
	return groups


func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	if not UniversalAnimationPools.try_play(anim_player, anim_name, blend_time):
		node.play_debug_anim(anim_name, blend_time)


func set_held_flashlight_visible(enabled: bool) -> void:
	node.set_held_flashlight_visible(enabled)
