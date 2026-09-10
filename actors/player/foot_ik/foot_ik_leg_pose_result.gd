class_name FootIKLegPoseResult
extends RefCounted
## Immutable-by-convention output of one leg's solve pass (018 finding D): every bone
## transform _solve_impl computes for hip through leaf, applied to the skeleton in a single
## step by FootIKLegSolver._apply_leg_pose() instead of scattered set_bone_global_pose calls.

var side: StringName
var hip_idx := -1
var knee_idx := -1
var foot_idx := -1
var toe_idx := -1
var leaf_idx := -1
var hip_basis := Basis.IDENTITY
var hip_pos := Vector3.ZERO
var knee_basis := Basis.IDENTITY
var knee_pos := Vector3.ZERO
var foot_basis := Basis.IDENTITY
var foot_pos := Vector3.ZERO
var has_toe := false
var toe_basis := Basis.IDENTITY
var toe_pos := Vector3.ZERO
var has_leaf := false
var leaf_basis := Basis.IDENTITY
var leaf_pos := Vector3.ZERO
