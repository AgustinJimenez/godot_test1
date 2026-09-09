class_name PrototypeSpineTwistModifier
extends SkeletonModifier3D
## Ports real ALS's spine rotation - the thing that keeps the character
## LOOKING toward the camera while its feet stay planted, which is what makes
## idle turn-in-place read as deliberate rather than as a rigid body frozen
## facing the wrong way.
##
## UALSCharacterAnimInstance::UpdateAimingValues sets
## `SpineRotation.Yaw = AimingAngle.X / 4.0`, and ALS_AnimBP applies that value
## as a LOCAL Transform (Modify) Bone on each of spine_01, spine_02 and
## spine_03 - three bones, NOT the pelvis, confirmed by reading the AnimBP's
## own graph live rather than trusting the C++ comment beside it, which says
## "spine+pelvis bones" and would have led to twisting the hips (and with them
## the legs, fighting foot IK).
##
## Three bones each taking a local quarter of the angle compounds down the
## chain to 0.25 / 0.50 / 0.75 of it in SKELETON space - which is the form
## this modifier writes, since absolute global-pose weights are the technique
## already proven in PlayerLookPoseModifier._bend_torso. Note the total is
## deliberately 0.75, not 1.0: real ALS does not fully counter-rotate the
## torso to face the camera, it leaves a residual.
##
## Deliberately a prototype-local class rather than reuse of
## PlayerLookPoseModifier: that one is the shipped player's, and its
## equivalent weights (0.60/0.80/1.00) are this project's own tuning, not
## ALS's. Retuning it to ALS's numbers would change real gameplay.
const SPINE_TWIST_WEIGHTS: Dictionary = {
	&"Spine": 0.25,
	&"Spine1": 0.50,
	&"Spine2": 0.75,
}

var player_body: PlayerBody
## Real ALS's AimingValues.AimingAngle.X - the raw aim-vs-actor yaw delta, in
## radians. Set once per physics frame by the prototype; zero disables.
var twist_yaw := 0.0


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or player_body == null or is_zero_approx(twist_yaw):
		return
	# Snapshot every target's animation pose BEFORE writing any of them: the
	# weights are absolute offsets from one shared pose, so a child must not
	# stack its correction on top of an already-corrected parent (the same
	# trap PlayerLookPoseModifier._bend_torso documents).
	var targets: Array = []
	for role: StringName in SPINE_TWIST_WEIGHTS:
		var idx := skel.find_bone(player_body.resolve_bone_name(role))
		if idx >= 0:
			targets.append([idx, skel.get_bone_global_pose(idx), SPINE_TWIST_WEIGHTS[role]])
	for target: Array in targets:
		var pose: Transform3D = target[1]
		# Pre-multiplying in skeleton space rotates about the character's own
		# vertical regardless of each bone's local axis convention. Origin is
		# left untouched so this can't fight the foot IK modifier's pelvis
		# height work.
		pose.basis = Basis(Vector3.UP, twist_yaw * float(target[2])) * pose.basis
		skel.set_bone_global_pose(target[0], pose)
