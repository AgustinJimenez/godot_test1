extends Node
## Acceptance contract for finding F (018): reset_runtime_state() must fully clear the
## residual/phase-locked correctors' own state, not just the common solver/gait/sampler/
## coordinator/stairs state - a mode switch (LEGACY <-> RESIDUAL_STAIR/PHASE_LOCKED) that
## forgets one of these leaves stale pelvis offsets/locks/timers for a future re-entry into
## that mode to silently reuse. `d1104ca` wired both correctors and the native backend into
## the common reset; this is the "dedicated test" finding F's own text asked for.

var _ik: PlayerFootIKModifier
var _phase := 0
var _failures: Array[String] = []


func _ready() -> void:
	_ik = PlayerFootIKModifier.new()
	add_child(_ik)


func _physics_process(_delta: float) -> void:
	_phase += 1
	match _phase:
		2:
			_poke_residual_state()
			_poke_phase_locked_state()
			_ik.reset_runtime_state()
			_expect_residual_clean()
			_expect_phase_locked_clean()
		3:
			print("FOOT_IK_MODE_SWITCH_CHECK %s failures=%s" % [
					"PASS" if _failures.is_empty() else "FAIL", _failures])
			get_tree().quit(0 if _failures.is_empty() else 1)


func _poke_residual_state() -> void:
	var c := _ik._residual_corrector
	c._smoothed_pelvis_offset = 0.4
	c._smoothed_weight[&"left"] = 0.8
	c._pelvis_base_pose = Transform3D(Basis.IDENTITY, Vector3.ONE)
	c._pelvis_base_pose_frame = 5


func _poke_phase_locked_state() -> void:
	var c := _ik._phase_locked_corrector
	c._smoothed_pelvis_offset = 0.4
	c._pelvis_base_pose = Transform3D(Basis.IDENTITY, Vector3.ONE)
	c._pelvis_base_pose_frame = 5
	c._locked_target[&"left"] = Vector3.ONE
	c._locked_normal[&"left"] = Vector3.UP
	c._stance_time_left[&"left"] = 1.0
	c._weight[&"left"] = 0.8


func _expect_residual_clean() -> void:
	var c := _ik._residual_corrector
	_expect(c._smoothed_pelvis_offset == 0.0, "residual pelvis offset not reset")
	_expect(c._smoothed_weight.is_empty(), "residual weight dict not reset")
	_expect(c._pelvis_base_pose == Transform3D(), "residual pelvis base pose not reset")
	_expect(c._pelvis_base_pose_frame == -1, "residual pose frame not reset")


func _expect_phase_locked_clean() -> void:
	var c := _ik._phase_locked_corrector
	_expect(c._smoothed_pelvis_offset == 0.0, "phase-locked pelvis offset not reset")
	_expect(c._pelvis_base_pose == Transform3D(), "phase-locked pelvis base pose not reset")
	_expect(c._pelvis_base_pose_frame == -1, "phase-locked pose frame not reset")
	_expect(c._locked_target.is_empty(), "phase-locked target dict not reset")
	_expect(c._locked_normal.is_empty(), "phase-locked normal dict not reset")
	_expect(c._stance_time_left.is_empty(), "phase-locked stance time not reset")
	_expect(c._weight.is_empty(), "phase-locked weight dict not reset")


func _expect(passed: bool, reason: String) -> void:
	if not passed:
		_failures.append(reason)
