extends Node3D
## Throwaway preview: plays pack animations inside the greybox room.
## Mixamo clips ship without a mesh but share The Boss's skeleton, so we
## copy their Animation resources into his AnimationPlayer at runtime.

const MIXAMO_CLIPS: Dictionary = {
	&"walking": "res://assets/models/action_adventure_pack/walking.fbx",
	&"idle": "res://assets/models/action_adventure_pack/idle.fbx",
	&"sneak": "res://assets/models/action_adventure_pack/crouched sneaking left.fbx",
}

@export var boss_clip: StringName = &"walking"


func _ready() -> void:
	$TestRoom/PlaceholderCamera.current = false
	$PreviewCamera.make_current()
	_setup_boss()
	_setup_motusman()


func _setup_boss() -> void:
	var ap: AnimationPlayer = $TheBoss/AnimationPlayer
	var lib := AnimationLibrary.new()
	for clip: StringName in MIXAMO_CLIPS:
		var inst: Node = (load(MIXAMO_CLIPS[clip]) as PackedScene).instantiate()
		var src: AnimationPlayer = inst.get_node("AnimationPlayer")
		var anim: Animation = src.get_animation(&"mixamo_com").duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip, anim)
		inst.queue_free()
	ap.add_animation_library(&"pack", lib)
	ap.play("pack/" + boss_clip)


func _setup_motusman() -> void:
	# The FBX references textures from the author's machine; reapply the
	# diffuse map that ships with the pack.
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(
		"res://assets/models/pistol_starter/MotusMan/sourceimages/MCG_diff.jpg")
	mat.roughness = 0.8
	for mesh_inst: Node in $MotusMan.find_children("*", "MeshInstance3D", true, false):
		(mesh_inst as MeshInstance3D).material_override = mat

	var ap: AnimationPlayer = $MotusMan/AnimationPlayer
	ap.get_animation(&"W1_Stand_Aim_Idle_IPC").loop_mode = Animation.LOOP_LINEAR
	ap.play(&"W1_Stand_Aim_Idle_IPC")
