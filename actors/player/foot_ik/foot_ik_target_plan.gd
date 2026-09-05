class_name FootIKTargetPlan
extends RefCounted
## Immutable-by-convention result of target arbitration for one leg and frame.

enum Owner {
	ANIMATION,
	LIVE_CONTACT,
	LANDING_COMMITMENT,
	LANDING_UPPER,
	IDLE_LOWER_ACQUIRE,
	IDLE_LOWER_LATCH,
	IDLE_STANCE_REHOME,
	IDLE_FREEZE,
	STAIR_SUPPORT,
	STAIR_SWING,
	LOCOMOTION_LOCK,
	LOCOMOTION_STANCE,
	SPLIT_RECOVERY,
}

var side: StringName
var owner: Owner = Owner.ANIMATION
var generation := 0
var valid := false
var stance_valid := false
var support_valid := false
var reach_valid := false
var surface_target := Vector3.ZERO
var surface_normal := Vector3.UP
var ankle_target := Vector3.ZERO
var raw_surface := Vector3.ZERO
var reason := "animation"


func owner_name() -> String:
	match owner:
		Owner.IDLE_LOWER_ACQUIRE:
			return "idle_lower_acquiring"
		Owner.IDLE_LOWER_LATCH:
			return "idle_lower_latched"
		Owner.IDLE_STANCE_REHOME:
			return "idle_stance_rehome"
		Owner.STAIR_SWING:
			return "stair_swing_prediction"
		Owner.LOCOMOTION_LOCK:
			return "locomotion_lock"
		_:
			return Owner.keys()[owner].to_lower()
