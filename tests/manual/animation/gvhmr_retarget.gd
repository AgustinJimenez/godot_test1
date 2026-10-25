extends Node
## Retargets a GVHMR clip (a tools/gvhmr/smplx_motion_to_json.py json) onto a catalog character and saves it (GvhmrPack.retarget).
## tools/retarget_cli.gd cannot run under --script (the PlayerProfile autoload), so this runs as a scene:
##   godot --headless --path . res://tests/manual/animation/gvhmr_retarget.tscn -- \
##       source_json=res://x.json target_manifest=res://y.character.json output=res://z.res \
##       [speed=1.4] [inplace=true] [hands=relaxed|fist] [contacts=res://x_contacts.json] [force_loop=true]


func _ready() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(options["target_manifest"]))
	var target_root: Node = (load(manifest["model_path"]) as PackedScene).instantiate()
	var target_skeleton := target_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var result := GvhmrPack.retarget(options["source_json"], target_skeleton, manifest["humanoid_map"], {
		"speed": float(options.get("speed", "0")), "inplace": options.get("inplace", "false") == "true",
		"hands": options.get("hands", ""), "contacts": options.get("contacts", ""),
		"force_loop": options.get("force_loop", "false") == "true",
	})
	DirAccess.make_dir_recursive_absolute(String(options["output"]).get_base_dir())
	var saved := ResourceSaver.save(result, options["output"])
	print("RETARGET_OK ", options["output"], " length=%.2f tracks=%d save=%d" % [
			result.length, result.get_track_count(), saved])
	get_tree().quit()
