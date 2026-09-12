class_name FootIKLegSolveInput
extends RefCounted
## Fixed, value-only input for one leg. No live nodes, owner callbacks or mutable settings.
## Treat this snapshot and its history as read-only; each evaluation copies the history.

var side: StringName
var physics_frame := -1
var source_revision := -1
var source_solver_id := 0
var skeleton_id := 0
var to_world := Transform3D.IDENTITY
var history: FootIKLegSolveState
var indices: Dictionary = {}
var poses: Dictionary = {}
var release_poses: Dictionary = {}
var fresh_poses: Dictionary = {}
var animation_name := ""
var hold_idle_loop := false
var actor_forward := Vector3.FORWARD
var root_position := Vector3.ZERO
var pelvis_offset := Vector3.ZERO
var normal := Vector3.UP
var own_surface := Vector3.ZERO
var knee_pole_local := Vector3.FORWARD
var has_riser_away := false
var riser_away := Vector3.ZERO
var riser_surface_y := INF
var landing_grace_time := 0.0
var shared_drop := 0.0
var stair_active := false
var lower_acquiring := false
var ground_foot_basis := Basis.IDENTITY
var toe_rest_offset := Vector3.ZERO
var toe_rest_relative_basis := Basis.IDENTITY
var leaf_rest_offset := Vector3.ZERO
var leaf_rest_relative_basis := Basis.IDENTITY
var max_hip_swing_degrees := 0.0
var max_knee_flexion_degrees := 0.0
var minimum_knee_pole_alignment := 0.0
var max_upright_shin_swing_degrees := 0.0
var upright_shin_steer_start_degrees := 0.0
var joint_correction_speed_degrees := 0.0
var crouch_joint_speed_degrees := 0.0
var standing_joint_speed_degrees := 0.0
var idle_lower_acquire_joint_speed_degrees := 0.0


static func capture(owner, leg_side: StringName, skel: Skeleton3D = null,
		release_only: bool = false) -> FootIKLegSolveInput:
	var input := FootIKLegSolveInput.new()
	input.side = leg_side
	input.physics_frame = Engine.get_physics_frames()
	if skel != null:
		input.to_world = skel.global_transform
		input.skeleton_id = skel.get_instance_id()
	var settings: FootIKRuntimeSettings = owner._ground_sampler._settings
	input.joint_correction_speed_degrees = settings.joint_correction_speed_degrees
	input.crouch_joint_speed_degrees = settings.crouch_joint_speed_degrees
	input.standing_joint_speed_degrees = settings.standing_joint_speed_degrees
	input.idle_lower_acquire_joint_speed_degrees = settings.idle_lower_acquire_joint_speed_degrees
	input.normal = owner._smoothed_normal.get(leg_side, Vector3.UP)
	input.shared_drop = owner._smoothed_shared_drop
	input.pelvis_offset = owner._pelvis_lateral_shift - Vector3.UP * input.shared_drop
	input.animation_name = String(owner.player_body.anim_player.current_animation.get_file())
	input.hold_idle_loop = (input.animation_name.contains("idle")
			and not owner._gait_tracker.is_body_translating()
			and (owner._velocity_suppressed
			or owner.player_body.anim_player.current_animation_position <= 0.10)
			and owner._prev_leg_bone_poses.has(leg_side))
	input.fresh_poses = owner._leg_fresh_pose_cache.duplicate(true)
	input.indices = owner._bone_indices[leg_side].duplicate(true)
	input.poses = input.fresh_poses.get(leg_side, {})
	input.release_poses = (owner._prev_leg_bone_poses[leg_side].duplicate(true)
			if input.hold_idle_loop else input.poses)
	# Preserve the old short-circuit: release-only fixtures need no stair predictor at zero drop.
	if input.shared_drop > 0.001 and input.animation_name.contains("idle"):
		input.stair_active = owner._stair_predictor.is_active()
	if not owner._ground_sampler is Dictionary:
		input.lower_acquiring = (
				owner._ground_sampler as FootIKGroundSampler).idle_lower_acquiring.has(leg_side)
	if release_only:
		return input
	if owner._animation_discontinuous and owner._prev_leg_bone_poses.has(leg_side):
		input.poses = owner._prev_leg_bone_poses[leg_side].duplicate(true)
	input.actor_forward = -owner.player_body.global_transform.basis.z.normalized()
	var root := owner.player_body.get_parent() as Node3D
	input.root_position = root.global_position if root != null else input.to_world.origin
	input.knee_pole_local = owner._knee_pole_local[leg_side]
	input.own_surface = owner._smoothed_target.get(leg_side, Vector3.ZERO)
	input.riser_surface_y = owner._ground_sampler.lower_riser_away_surface_y.get(leg_side, INF)
	input.has_riser_away = owner._ground_sampler.lower_riser_away.has(leg_side)
	input.riser_away = owner._ground_sampler.lower_riser_away.get(leg_side, Vector3.ZERO)
	input.landing_grace_time = owner._landing_grace_time
	input.max_hip_swing_degrees = owner.max_hip_swing_degrees
	input.max_knee_flexion_degrees = owner.max_knee_flexion_degrees
	input.minimum_knee_pole_alignment = settings.minimum_knee_pole_alignment
	input.max_upright_shin_swing_degrees = settings.max_upright_shin_swing_degrees
	input.upright_shin_steer_start_degrees = settings.upright_shin_steer_start_degrees
	input.toe_rest_offset = owner._toe_rest_offset.get(leg_side, Vector3.ZERO)
	input.toe_rest_relative_basis = owner._toe_rest_relative_basis.get(leg_side, Basis.IDENTITY)
	input.leaf_rest_offset = owner._leaf_rest_offset.get(leg_side, Vector3.ZERO)
	input.leaf_rest_relative_basis = owner._leaf_rest_relative_basis.get(leg_side, Basis.IDENTITY)
	if skel != null and not input.poses.is_empty():
		var foot_pose: Transform3D = input.poses["foot"]
		input.ground_foot_basis = (
				owner._compute_new_foot_basis_world(skel, leg_side, -input.normal, foot_pose)
				if input.normal.dot(Vector3.UP) < 0.999
				else input.to_world.basis * foot_pose.basis)
	return input
