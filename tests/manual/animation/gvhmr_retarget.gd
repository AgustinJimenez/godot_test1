extends Node
## Retargets a GVHMR clip (SMPL-X skeleton, E:/repo/gvhmr/gvhmr_blender_fbx.py) onto a catalog character and saves it.
## tools/retarget_cli.gd cannot run under --script (the PlayerProfile autoload), so this runs as a scene:
##   godot --headless --path . res://tests/manual/animation/gvhmr_retarget.tscn -- \
##       source=res://x.fbx target_manifest=res://y.character.json output=res://z.res [force_loop=true]

const STANDING_PELVIS_HEIGHT := 1.0 # m: the SMPL-X neutral body's pelvis when standing


func _ready() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(options["target_manifest"]))
	var target_root: Node = (load(manifest["model_path"]) as PackedScene).instantiate()
	var source_root: Node = (load(options["source"]) as PackedScene).instantiate()
	var target_skeleton := target_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var source_skeleton := source_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var animation := player.get_animation(player.get_animation_list()[0])
	# gvhmr_blender_fbx.py bakes the clip's first-frame translation into the pelvis rest, so every clip's rest height
	# differs (a crouch clip rests at 0.6 m, a standing one at 1.0 m) and the retargeter's hips delta follows it:
	# put the pelvis rest at the SMPL-X standing height, in the middle of the body, for every clip.
	var pelvis := source_skeleton.find_bone(&"pelvis")
	var rest := source_skeleton.get_bone_rest(pelvis)
	source_skeleton.set_bone_rest(pelvis, Transform3D(rest.basis, Vector3(0.0, STANDING_PELVIS_HEIGHT, 0.0)))
	var config := HumanoidRetargeter.build_bone_map_config(
			RetargetSmplx.ROLE_MAP, manifest["humanoid_map"] as Dictionary)
	var result := HumanoidRetargeter.retarget_clip(source_skeleton, animation, target_skeleton, config,
			options.get("force_loop", "false") == "true")
	DirAccess.make_dir_recursive_absolute(String(options["output"]).get_base_dir())
	var saved := ResourceSaver.save(result, options["output"])
	print("RETARGET_OK ", options["output"], " length=%.2f tracks=%d save=%d" % [
			result.length, result.get_track_count(), saved])
	get_tree().quit()
