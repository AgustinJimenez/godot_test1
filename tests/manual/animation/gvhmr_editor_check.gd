extends Node
## Selects a GVHMR clip in the character editor and checks that the skeleton moves (godot --path . res://tests/manual/animation/gvhmr_editor_check.tscn).

func _ready() -> void:
	var editor: CharacterEditor = load("res://tools/character_editor/character_editor.tscn").instantiate()
	add_child(editor)
	for i in 10:
		await get_tree().process_frame
	var picker: OptionButton = editor.animation_group_picker
	for index in picker.item_count:
		print("group ", index, ": ", picker.get_item_metadata(index))
	for index in picker.item_count:
		if String(picker.get_item_metadata(index)) == "GVHMR pack (generated)":
			picker.select(index)
			editor._ui_setup_handler._on_animation_group_selected(index)
	print("clips in picker: ", editor.animation_picker.item_count)
	editor.animation_picker.select(2)
	editor._ui_setup_handler._on_animation_selected(2)
	var player: AnimationPlayer = editor.body.anim_player
	print("current: ", editor._current_animation, " playing=", player.is_playing(), " anim=", player.current_animation)
	var anim := player.get_animation(player.current_animation) if player.current_animation != "" else null
	if anim:
		print("tracks=", anim.get_track_count(), " len=", anim.length, " first path=", anim.track_get_path(0))
	var skeleton: Skeleton3D = editor.body.skeleton
	print("skeleton path from player root: ", player.get_node(player.root_node).get_path_to(skeleton))
	var before := skeleton.get_bone_pose_rotation(skeleton.find_bone("mixamorig_LeftArm") if skeleton.find_bone("mixamorig_LeftArm") >= 0 else 5)
	for i in 30:
		await get_tree().process_frame
	var after := skeleton.get_bone_pose_rotation(skeleton.find_bone("mixamorig_LeftArm") if skeleton.find_bone("mixamorig_LeftArm") >= 0 else 5)
	print("moved: ", before.angle_to(after), " position=", player.current_animation_position)
	get_tree().quit()
