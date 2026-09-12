class_name FootIKLegSolveState
extends RefCounted
## Value-only solver history and diagnostics. Candidate evaluation owns a deep copy.

const FIELDS: Array[StringName] = [
	&"_previous_corrections",
	&"_previous_correction_frames",
	&"_previous_bend",
	&"debug_stance_limited",
	&"debug_swing_clamped",
	&"debug_swing_degrees",
	&"debug_target_error",
	&"debug_solve_target",
	&"debug_final_foot_position",
	&"debug_shin_swing_degrees",
	&"debug_shin_clamped",
	&"debug_signed_knee_flexion",
	&"debug_negative_knee_clamped",
	&"debug_knee_pole_alignment",
	&"debug_knee_direction_constrained",
]

var _previous_corrections: Dictionary = {}
var _previous_correction_frames: Dictionary = {}
var _previous_bend: Dictionary = {}
var debug_stance_limited: Dictionary = {}
var debug_swing_clamped: Dictionary = {}
var debug_swing_degrees: Dictionary = {}
var debug_target_error: Dictionary = {}
var debug_solve_target: Dictionary = {}
var debug_final_foot_position: Dictionary = {}
var debug_shin_swing_degrees: Dictionary = {}
var debug_shin_clamped: Dictionary = {}
var debug_signed_knee_flexion: Dictionary = {}
var debug_negative_knee_clamped: Dictionary = {}
var debug_knee_pole_alignment: Dictionary = {}
var debug_knee_direction_constrained: Dictionary = {}


static func capture(source: Object) -> FootIKLegSolveState:
	var snapshot := FootIKLegSolveState.new()
	for field in FIELDS:
		snapshot.set(field, (source.get(field) as Dictionary).duplicate(true))
	return snapshot


func publish_to(destination: Object) -> void:
	for field in FIELDS:
		destination.set(field, (get(field) as Dictionary).duplicate(true))
