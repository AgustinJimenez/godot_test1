extends SceneTree
## Compact source-asset inventory for the independent procedural gait lab.

const CLIP_DIR := "res://assets/models/pistol_starter/Animation/In-Place/"
const FILES := [
	"W1_Stand_Relaxed_Idle_IPC.fbx",
	"W1_Walk_Aim_F_Loop_IPC.fbx",
	"W1_Jog_Aim_F_Loop_IPC.fbx",
	"W1_CrouchWalk_Aim_F_Loop_IPC.fbx",
	"res://assets/models/universal_animation_library/UAL1_Standard.glb",
]


func _initialize() -> void:
	for file: String in FILES:
		var path := file if file.begins_with("res://") else CLIP_DIR + file
		var root := (load(path) as PackedScene).instantiate()
		var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if skel == null or player == null:
			print("SOURCE_FAIL %s skeleton=%s player=%s" % [path, skel, player])
			root.free()
			continue
		if path.contains("UAL1"):
			print("UAL_BONES pelvis=%d head=%d Head=%d" % [
				skel.find_bone(&"pelvis"), skel.find_bone(&"head"), skel.find_bone(&"Head")])
		var names := PackedStringArray()
		for name: StringName in player.get_animation_list():
			if path.contains("UAL1") and name not in [&"Sprint", &"Walk"]:
				continue
			names.append(String(name))
		for name: String in names:
			var animation := player.get_animation(name)
			var track := (
					str(animation.track_get_path(0)) if animation.get_track_count() > 0 else "none")
			print("SOURCE %s clip=%s len=%.3f bones=%d tracks=%d first=%s root=%s" % [
					path.get_file(), name, animation.length, skel.get_bone_count(),
					animation.get_track_count(), track, str(player.root_node)])
		root.free()
	for path: String in ["res://assets/models/stair_clips/stair_walk_up.res",
			"res://assets/models/stair_clips/stair_walk_down.res"]:
		var animation := load(path) as Animation
		print("SOURCE %s len=%.3f tracks=%d first=%s" % [
				path.get_file(), animation.length, animation.get_track_count(),
				str(animation.track_get_path(0))])
	quit()
