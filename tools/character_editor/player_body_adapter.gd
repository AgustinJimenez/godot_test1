class_name PlayerBodyAdapter
extends CharacterAdapter

## Wraps the player character exactly the way character_editor.tscn's
## original baked-in "Body" node did: the raw MotusMan model with
## player_body.gd attached directly, not the full actors/player/player.tscn
## (which pulls in gameplay-only pieces like weapons and the camera
## controller that this tool has no use for).

const _MODEL_PATH := "res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Aim_Idle_IPC.fbx"
const _SCRIPT_PATH := "res://actors/player/player_body.gd"


static func create(parent: Node3D, at_position: Vector3) -> PlayerBodyAdapter:
	var instance: Node3D = (load(_MODEL_PATH) as PackedScene).instantiate()
	instance.name = &"Body"
	instance.position = at_position
	instance.set_script(load(_SCRIPT_PATH))
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
	supports_comparison = true
	display_name = "Player"


func get_animation_groups() -> Dictionary:
	return node.get_animation_groups()


func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	node.play_debug_anim(anim_name, blend_time)


func set_held_flashlight_visible(enabled: bool) -> void:
	node.set_held_flashlight_visible(enabled)
