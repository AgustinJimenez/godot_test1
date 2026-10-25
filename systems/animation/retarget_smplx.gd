class_name RetargetSmplx
## The role map of an SMPL-X skeleton (a GVHMR clip), as tools/retarget_cli.gd's SMPLX_SOURCE_ROLE_MAP.
const ROLE_MAP: Dictionary = {
	&"pelvis": &"Hips", &"spine1": &"Spine", &"spine2": &"Spine1", &"spine3": &"Spine2",
	&"neck": &"Neck", &"head": &"Head",
	&"left_collar": &"LeftShoulder", &"left_shoulder": &"LeftArm", &"left_elbow": &"LeftForeArm",
	&"left_wrist": &"LeftHand", &"right_collar": &"RightShoulder", &"right_shoulder": &"RightArm",
	&"right_elbow": &"RightForeArm", &"right_wrist": &"RightHand",
	&"left_hip": &"LeftUpLeg", &"left_knee": &"LeftLeg", &"left_ankle": &"LeftFoot", &"left_foot": &"LeftToeBase",
	&"right_hip": &"RightUpLeg", &"right_knee": &"RightLeg", &"right_ankle": &"RightFoot", &"right_foot": &"RightToeBase",
}
