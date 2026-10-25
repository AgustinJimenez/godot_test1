extends Node3D
## Prints, at one time, the bone directions (parent -> child, in the character's own space) of the GVHMR source and the
## retargeted character side by side, with the angle between them: where a retarget leans or twists.
##   godot --headless --path . res://tests/manual/animation/gvhmr_debug.tscn -- source=res://a.fbx target_model=res://b.fbx clip=res://c.res at=1.0

const PAIRS := [ # [label, source parent, source child, target parent role, target child role]
	["spine", "pelvis", "spine3", "Hips", "Spine2"],
	["neck", "spine3", "head", "Spine2", "Head"],
	["L thigh", "left_hip", "left_knee", "LeftUpLeg", "LeftLeg"],
	["L shin", "left_knee", "left_ankle", "LeftLeg", "LeftFoot"],
	["R thigh", "right_hip", "right_knee", "RightUpLeg", "RightLeg"],
	["R shin", "right_knee", "right_ankle", "RightLeg", "RightFoot"],
	["L arm", "left_shoulder", "left_elbow", "LeftArm", "LeftForeArm"],
	["L forearm", "left_elbow", "left_wrist", "LeftForeArm", "LeftHand"],
	["R arm", "right_shoulder", "right_elbow", "RightArm", "RightForeArm"],
	["R forearm", "right_elbow", "right_wrist", "RightForeArm", "RightHand"],
	["hips L-R", "left_hip", "right_hip", "LeftUpLeg", "RightUpLeg"],
	["shoulders L-R", "left_shoulder", "right_shoulder", "LeftArm", "RightArm"],
]

var _options := {"at": "1.0"}
var _source: Node3D
var _target: Node3D
var _source_player: AnimationPlayer
var _target_player: AnimationPlayer


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			_options[pair[0]] = pair[1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_options["manifest"]))
	_source = (load(_options["source"]) as PackedScene).instantiate()
	add_child(_source)
	_target = (load(manifest["model_path"]) as PackedScene).instantiate()
	add_child(_target)
	_source_player = _source.find_child("AnimationPlayer", true, false)
	_target_player = _target.find_child("AnimationPlayer", true, false)
	_source_player.play(_source_player.get_animation_list()[0])
	var library: AnimationLibrary = _target_player.get_animation_library(&"")
	library.add_animation(&"clip", load(_options["clip"]))
	_target_player.play(&"clip")
	var at := float(_options["at"])
	_source_player.seek(at, true)
	_target_player.seek(at, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var map: Dictionary = manifest["humanoid_map"]
	var source_skeleton := _source.find_child("Skeleton3D", true, false) as Skeleton3D
	var target_skeleton := _target.find_child("Skeleton3D", true, false) as Skeleton3D
	print("--- at ", at, "s   (source turned to the target's facing; angle = between source and target)")
	# the source and the target face different ways: turn the source by the difference of their hip axes first
	var src_axis := _direction(source_skeleton, "left_hip", "right_hip")
	var dst_axis := _direction(target_skeleton, map["LeftUpLeg"], map["RightUpLeg"])
	var turn := Basis(Vector3.UP, Vector3(src_axis.x, 0.0, src_axis.z).signed_angle_to(
			Vector3(dst_axis.x, 0.0, dst_axis.z), Vector3.UP))
	for row: Array in PAIRS:
		var a: Vector3 = turn * _direction(source_skeleton, row[1], row[2])
		var b := _direction(target_skeleton, map[row[3]], map[row[4]])
		print("%-14s src %s  dst %s  angle %5.1f deg" % [row[0], _fmt(a), _fmt(b), rad_to_deg(a.angle_to(b))])
	# travel against facing: the pelvis position between the start and the end of the clip, along each model's facing
	var length := float(_options.get("end", "0"))
	if length > 0.0:
		_source_player.seek(0.0, true)
		_target_player.seek(0.0, true)
		await get_tree().process_frame
		await get_tree().process_frame
		var s0 := _hips(source_skeleton, "pelvis")
		var d0 := _hips(target_skeleton, map["Hips"])
		var sf := _facing(source_skeleton, "left_hip", "right_hip")
		var df := _facing(target_skeleton, map["LeftUpLeg"], map["RightUpLeg"])
		_source_player.seek(length, true)
		_target_player.seek(length, true)
		await get_tree().process_frame
		await get_tree().process_frame
		var s1 := _hips(source_skeleton, "pelvis")
		var d1 := _hips(target_skeleton, map["Hips"])
		var st := Vector3(s1.x - s0.x, 0.0, s1.z - s0.z)
		var dt := Vector3(d1.x - d0.x, 0.0, d1.z - d0.z)
		print("travel src %.2f m, %.2f of it along its facing | dst %.2f m, %.2f along its facing" % [
				st.length(), st.normalized().dot(sf), dt.length(), dt.normalized().dot(df)])
		print("facing (world, xz) src ", _fmt(sf), " dst ", _fmt(df))
	var hips_src := source_skeleton.get_bone_global_pose(source_skeleton.find_bone("pelvis")).origin
	var hips_dst := target_skeleton.get_bone_global_pose(target_skeleton.find_bone(map["Hips"])).origin
	print("pelvis position src ", _fmt(hips_src), " dst ", _fmt(hips_dst))
	print("source facing (L->R hips x) vs target: see 'hips L-R' row")
	get_tree().quit()


func _direction(skeleton: Skeleton3D, from_name: String, to_name: String) -> Vector3:
	var from := skeleton.get_bone_global_pose(skeleton.find_bone(from_name)).origin
	var to := skeleton.get_bone_global_pose(skeleton.find_bone(to_name)).origin
	return (to - from).normalized()


func _fmt(v: Vector3) -> String:
	return "(%5.2f %5.2f %5.2f)" % [v.x, v.y, v.z]


func _hips(skeleton: Skeleton3D, bone: String) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin


## The way a model faces, from its hip axis (left -> right) and up: right x up, flattened.
func _facing(skeleton: Skeleton3D, left_bone: String, right_bone: String) -> Vector3:
	var across := _direction(skeleton, left_bone, right_bone)
	var facing := across.cross(Vector3.UP)
	facing.y = 0.0
	return facing.normalized()
