class_name SmplxJsonSource
## Builds a Skeleton3D and an Animation from a tools/gvhmr/smplx_motion_to_json.py file: no Blender, no FBX.
## The bones have identity rest rotations (SMPL-X's local rotations are relative to that), so every clip has the same rest
## pose; the pelvis position track is the translation plus the pelvis rest joint, like the Blender export.

## Returns {"skeleton": Skeleton3D, "animation": Animation, "fps": float}; the skeleton is named "Skeleton3D".
static func load_clip(path: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var names: Array = data["names"]
	var parents: Array = data["parents"]
	var rest: Array = data["rest"]
	# SMPL-X's origin is not on the floor: lift everything so the rest pose's feet stand on y = 0 (the translation is
	# relative to the same origin, so the pelvis track gets the same lift)
	var ground := minf(_vec(rest[names.find("left_foot")]).y, _vec(rest[names.find("right_foot")]).y)
	var lift := Vector3(0.0, -ground, 0.0)
	var skeleton := Skeleton3D.new()
	skeleton.name = &"Skeleton3D"
	for index in names.size():
		skeleton.add_bone(String(names[index]))
	for index in names.size():
		var parent: int = int(parents[index])
		skeleton.set_bone_parent(index, parent)
		var here := _vec(rest[index])
		var origin := (here + lift) if parent < 0 else here - _vec(rest[parent])
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, origin))
	skeleton.reset_bone_poses()
	var fps: float = data["fps"]
	var frames: int = int(data["frames"])
	var animation := Animation.new()
	animation.length = float(frames - 1) / fps
	var rotations: Array = data["rotations"]
	var transl: Array = data["transl"]
	var pelvis_rest := _vec(rest[0]) # (the translation already puts the feet on the floor: the lift is only for the rest pose)
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, NodePath("Skeleton3D:" + String(names[0])))
	var rotation_tracks: Array[int] = []
	for bone in 22:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("Skeleton3D:" + String(names[bone])))
		rotation_tracks.append(track)
	for frame in frames:
		var time := float(frame) / fps
		animation.position_track_insert_key(position_track, time, _vec(transl[frame]) + pelvis_rest)
		var row: Array = rotations[frame]
		for bone in 22:
			var axis_angle := Vector3(row[bone * 3], row[bone * 3 + 1], row[bone * 3 + 2])
			var angle := axis_angle.length()
			var quaternion := Quaternion.IDENTITY if angle < 0.000001 else Quaternion(axis_angle / angle, angle)
			animation.rotation_track_insert_key(rotation_tracks[bone], time, quaternion)
	return {"skeleton": skeleton, "animation": animation, "fps": fps}


static func _vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
