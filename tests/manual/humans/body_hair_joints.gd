class_name BodyHairJoints
extends RefCounted
## The joints HumanBodyHair cuts its areas from (shoulders, elbows, wrists, hips, knees, ankles, the neck, the hips), read from <gender>_rig.json at the
## body's rest shape (the hair carries the height / weight / muscle shapes itself, so it is built on the base body).

const RIG_PATH := "res://assets/models/humans/%s_rig.json"
const JOINTS := {
	"shoulder_l": "LeftArm", "shoulder_r": "RightArm",
	"elbow_l": "LeftForeArm", "elbow_r": "RightForeArm",
	"wrist_l": "LeftHand", "wrist_r": "RightHand",
	"hip_l": "LeftUpLeg", "hip_r": "RightUpLeg",
	"knee_l": "LeftLeg", "knee_r": "RightLeg",
	"ankle_l": "LeftFoot", "ankle_r": "RightFoot",
	"neck": "Neck", "hips": "Hips",
}


## gender: "Male" or "Female" (any case). Empty when the rig file is missing.
static func for_gender(gender: String) -> Dictionary:
	var path: String = RIG_PATH % gender.to_lower()
	if not FileAccess.file_exists(path):
		return {}
	var rig: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (rig is Dictionary):
		return {}
	var bones: Array = rig["bones"]
	var heads: Array = rig["head"]
	var out: Dictionary = {}
	for key: String in JOINTS:
		var i: int = bones.find("mixamorig:" + String(JOINTS[key]))
		if i >= 0:
			var h: Array = heads[i]
			out[key] = Vector3(float(h[0]), float(h[1]), float(h[2]))
	return out
