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
	var source_root: Node
	var source_skeleton: Skeleton3D
	var animation: Animation
	if options.has("source_json"): # straight from tools/gvhmr/smplx_motion_to_json.py (no Blender, no FBX)
		var clip := SmplxJsonSource.load_clip(options["source_json"])
		source_skeleton = clip["skeleton"]
		animation = clip["animation"]
		source_root = source_skeleton
	else:
		source_root = (load(options["source"]) as PackedScene).instantiate()
		source_skeleton = source_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		animation = player.get_animation(player.get_animation_list()[0])
		# gvhmr_blender_fbx.py bakes the clip's first-frame translation into the pelvis rest, so every clip's rest height
		# differs (a crouch clip rests at 0.6 m, a standing one at 1.0 m) and the retargeter's hips delta follows it:
		# put the pelvis rest at the SMPL-X standing height, in the middle of the body, for every clip.
		var pelvis := source_skeleton.find_bone(&"pelvis")
		var rest := source_skeleton.get_bone_rest(pelvis)
		source_skeleton.set_bone_rest(pelvis, Transform3D(rest.basis, Vector3(0.0, STANDING_PELVIS_HEIGHT, 0.0)))
	var target_skeleton := target_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var config := HumanoidRetargeter.build_bone_map_config(
			RetargetSmplx.ROLE_MAP, manifest["humanoid_map"] as Dictionary)
	var map: Dictionary = manifest["humanoid_map"]
	# parents before children; the fourth entry is the child bone the direction runs to
	var chains: Array = [
		["pelvis", "spine1", map["Hips"], map["Spine"]], ["spine1", "spine2", map["Spine"], map["Spine1"]],
		["spine2", "spine3", map["Spine1"], map["Spine2"]], ["spine3", "neck", map["Spine2"], map["Neck"]],
		["twist", "left_collar", "right_collar", map["LeftShoulder"], map["RightShoulder"], map["Spine2"], map["Neck"]],
		["neck", "head", map["Neck"], map["Head"]],
	]
	for side: Array in [["left", "Left"], ["right", "Right"]]:
		var lo: String = side[0]
		var hi: String = side[1]
		chains.append([lo + "_hip", lo + "_knee", map[hi + "UpLeg"], map[hi + "Leg"]])
		chains.append([lo + "_knee", lo + "_ankle", map[hi + "Leg"], map[hi + "Foot"]])
		chains.append([lo + "_collar", lo + "_shoulder", map[hi + "Shoulder"], map[hi + "Arm"]])
		chains.append([lo + "_shoulder", lo + "_elbow", map[hi + "Arm"], map[hi + "ForeArm"]])
		chains.append([lo + "_elbow", lo + "_wrist", map[hi + "ForeArm"], map[hi + "Hand"]])
	var foot_lock := {}
	if options.has("contacts"): # tools/gvhmr/foot_report.py's file: the frames each foot is planted on
		var contacts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(options["contacts"]))
		foot_lock = {"planted": contacts["planted"], "fps": contacts["fps"], "blend": 3, "legs": [
			[map["LeftUpLeg"], map["LeftLeg"], map["LeftFoot"]], [map["RightUpLeg"], map["RightLeg"], map["RightFoot"]]]}
	var result := HumanoidRetargeter.retarget_clip(source_skeleton, animation, target_skeleton, config,
			options.get("force_loop", "false") == "true", options.get("arm_ik", "false") == "true",
			[] if options.get("aim", "true") != "true" else chains,
			["left_hip", "right_hip", map["LeftUpLeg"], map["RightUpLeg"]], foot_lock)
	if options.get("inplace", "false") == "true": # idles and turns: GVHMR's translation drifts, keep the clip on the spot
		HumanoidRetargeter.make_clip_in_place(result)
	if options.get("hands", "") != "":
		print("hand tracks written: ", HandPresets.apply(result, target_skeleton, map, options["hands"]))
	DirAccess.make_dir_recursive_absolute(String(options["output"]).get_base_dir())
	var saved := ResourceSaver.save(result, options["output"])
	print("RETARGET_OK ", options["output"], " length=%.2f tracks=%d save=%d" % [
			result.length, result.get_track_count(), saved])
	get_tree().quit()
