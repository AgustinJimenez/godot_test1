extends SceneTree

## Standalone CLI: retargets one clip from a source FBX/GLB skeleton onto any
## catalog character's skeleton via HumanoidRetargeter, saving the result as
## a .res Animation resource. No live editor/mcp_bridge round trip needed -
## the source and target files just need to already be imported Godot
## resources under res:// (e.g. via `godot --headless --import`).
##
## For a UE-Mannequin/ALS-style source (pelvis, clavicle_l, hand_r, ...),
## PlayerBody.BONE_MAP already is the source-role-map HumanoidRetargeter
## expects - reused directly rather than re-derived. A source using a
## different convention would need its own role map built via
## HumanoidRetargeter.detect_bone_prefix()/prefix_role_map() instead.
##
## Usage:
##   godot --headless --script res://tools/retarget_cli.gd -- \
##       source=res://path/to/clip.fbx [source_anim=<name, default: first found>] \
##       target_manifest=res://path/to/Character.character.json \
##       output=res://path/to/output.res [force_loop=true]


func _initialize() -> void:
	var options := _parse_args()
	var missing := _missing_required(options, ["source", "target_manifest", "output"])
	if not missing.is_empty():
		push_error("Missing required argument(s): %s" % ", ".join(missing))
		quit(1)
		return

	var source_path: String = options["source"]
	var manifest_path: String = options["target_manifest"]
	var output_path: String = options["output"]
	var force_loop: bool = String(options.get("force_loop", "false")) == "true"

	var manifest := _load_manifest(manifest_path)
	if manifest.is_empty():
		quit(1)
		return
	var humanoid_map: Dictionary = manifest.get("humanoid_map", {})
	var target_model_path: String = manifest.get("model_path", "")
	if humanoid_map.is_empty() or target_model_path.is_empty():
		push_error("Target manifest has no humanoid_map/model_path: %s" % manifest_path)
		quit(1)
		return

	var target_root: Node = _instantiate(target_model_path)
	if target_root == null:
		quit(1)
		return
	var target_skeleton: Skeleton3D = target_root.find_child("Skeleton3D", true, false)
	if target_skeleton == null:
		push_error("Target model has no Skeleton3D: %s" % target_model_path)
		quit(1)
		return

	var source_root: Node = _instantiate(source_path)
	if source_root == null:
		quit(1)
		return
	var source_skeleton: Skeleton3D = source_root.find_child("Skeleton3D", true, false)
	var source_ap: AnimationPlayer = source_root.find_child("AnimationPlayer", true, false)
	if source_skeleton == null or source_ap == null:
		push_error("Source has no Skeleton3D/AnimationPlayer: %s" % source_path)
		quit(1)
		return

	var source_anim_name: String = options.get("source_anim", "")
	var source_animation := _find_animation(source_ap, source_anim_name)
	if source_animation == null:
		push_error("Could not find source animation '%s' in %s" % [source_anim_name, source_path])
		quit(1)
		return

	var config := HumanoidRetargeter.build_bone_map_config(ALS_SOURCE_ROLE_MAP, humanoid_map)
	var retargeted := HumanoidRetargeter.retarget_clip(
			source_skeleton, source_animation, target_skeleton, config, force_loop)

	source_root.free()
	target_root.free()

	var directory := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var save_result := ResourceSaver.save(retargeted, output_path)
	if save_result != OK:
		push_error("Could not save retargeted animation: %s" % error_string(save_result))
		quit(1)
		return

	print("RETARGET_OK: %s -> %s (length=%.3f tracks=%d)" % [
		source_path, output_path, retargeted.length, retargeted.get_track_count(),
	])
	quit()


func _parse_args() -> Dictionary:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if "=" in argument:
			options[argument.get_slice("=", 0)] = argument.get_slice("=", 1)
	return options


func _missing_required(options: Dictionary, required: PackedStringArray) -> PackedStringArray:
	var missing := PackedStringArray()
	for key in required:
		if not options.has(key):
			missing.append(key)
	return missing


func _load_manifest(manifest_path: String) -> Dictionary:
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("Could not open target manifest: %s" % manifest_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Target manifest is not valid JSON: %s" % manifest_path)
		return {}
	return parsed


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Could not load as PackedScene: %s" % path)
		return null
	return packed.instantiate()


## Deliberate duplicate of PlayerBody.BONE_MAP's non-finger-leaf entries,
## not a reference to it - matches HumanoidRetargeter's own stated policy
## ("Duplicated on purpose; do not merge back into player_body.gd") so this
## standalone tool never has to load player_body.gd's class at all (that
## script requires the PlayerProfile autoload, which --script mode does not
## initialize, and referencing it here previously produced a noisy
## "Identifier not found: PlayerProfile" compile error on every run even
## though PlayerBody.BONE_MAP's own data still resolved correctly).
##
## Two differences from PlayerBody.BONE_MAP, confirmed by diffing every key
## against this project's own exported ALS skeleton (assets/models/
## als_mannequin_standalone/AnimMan.fbx):
## - "head" is lowercase here (PlayerBody.BONE_MAP has "Head" capitalized,
##   which resolves to no bone at all on this rig and hard-crashes
##   retarget_clip's required head/facing computation with a -1 bone index -
##   unlike a missing hand/finger entry, which that function's per-bone loop
##   just skips harmlessly).
## - the ten "_04_leaf_" fingertip entries are omitted entirely - this rig
##   has no such bones (its finger chains stop at 3 joints), so leaving them
##   in would just be silently-skipped dead entries; omitted for clarity.
const ALS_SOURCE_ROLE_MAP: Dictionary = {
	&"pelvis": &"Hips",
	&"spine_01": &"Spine",
	&"spine_02": &"Spine1",
	&"spine_03": &"Spine2",
	&"neck_01": &"Neck",
	&"head": &"Head",
	&"clavicle_r": &"RightShoulder",
	&"upperarm_r": &"RightArm",
	&"lowerarm_r": &"RightForeArm",
	&"hand_r": &"RightHand",
	&"index_01_r": &"RightHandIndex1",
	&"index_02_r": &"RightHandIndex2",
	&"index_03_r": &"RightHandIndex3",
	&"middle_01_r": &"RightHandMiddle1",
	&"middle_02_r": &"RightHandMiddle2",
	&"middle_03_r": &"RightHandMiddle3",
	&"pinky_01_r": &"RightHandPinky1",
	&"pinky_02_r": &"RightHandPinky2",
	&"pinky_03_r": &"RightHandPinky3",
	&"ring_01_r": &"RightHandRing1",
	&"ring_02_r": &"RightHandRing2",
	&"ring_03_r": &"RightHandRing3",
	&"thumb_01_r": &"RightHandThumb1",
	&"thumb_02_r": &"RightHandThumb2",
	&"thumb_03_r": &"RightHandThumb3",
	&"clavicle_l": &"LeftShoulder",
	&"upperarm_l": &"LeftArm",
	&"lowerarm_l": &"LeftForeArm",
	&"hand_l": &"LeftHand",
	&"index_01_l": &"LeftHandIndex1",
	&"index_02_l": &"LeftHandIndex2",
	&"index_03_l": &"LeftHandIndex3",
	&"middle_01_l": &"LeftHandMiddle1",
	&"middle_02_l": &"LeftHandMiddle2",
	&"middle_03_l": &"LeftHandMiddle3",
	&"pinky_01_l": &"LeftHandPinky1",
	&"pinky_02_l": &"LeftHandPinky2",
	&"pinky_03_l": &"LeftHandPinky3",
	&"ring_01_l": &"LeftHandRing1",
	&"ring_02_l": &"LeftHandRing2",
	&"ring_03_l": &"LeftHandRing3",
	&"thumb_01_l": &"LeftHandThumb1",
	&"thumb_02_l": &"LeftHandThumb2",
	&"thumb_03_l": &"LeftHandThumb3",
	&"thigh_r": &"RightUpLeg",
	&"calf_r": &"RightLeg",
	&"foot_r": &"RightFoot",
	&"ball_r": &"RightToeBase",
	&"thigh_l": &"LeftUpLeg",
	&"calf_l": &"LeftLeg",
	&"foot_l": &"LeftFoot",
	&"ball_l": &"LeftToeBase",
}


func _find_animation(anim_player: AnimationPlayer, requested_name: String) -> Animation:
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if requested_name.is_empty() or String(anim_name) == requested_name:
				return lib.get_animation(anim_name)
	return null
