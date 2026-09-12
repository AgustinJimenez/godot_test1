class_name FootIKLegPoseResult
extends RefCounted
## Candidate output, immutable by convention: world-space bones plus tentative history and
## diagnostics. Evaluating it has no external effects; commit_candidate accepts it once.
## Diagnostics are existing measurements/guards, not a complete clearance/feasibility report.

var next_state: FootIKLegSolveState
var source_revision := -1
var source_solver_id := 0
var physics_frame := -1
var skeleton_id := 0
var to_world := Transform3D.IDENTITY
var has_pose := false

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
