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

## Per-constraint outcome (018 finding C): "valid" used to conflate a real check that passed
## with one that was never applicable to this owner, and with a real failure tolerated for a
## short streak - all reported as plain true. Now distinguishable; VIOLATED is the only status
## that blocks plan.valid, so combining logic is unchanged from the old all-true-unless-false
## bools, but each constraint's actual story is now visible on the plan.
enum ConstraintStatus { SATISFIED, VIOLATED, NOT_CHECKED, NOT_APPLICABLE, TEMPORARILY_TOLERATED }

var side: StringName
var owner: Owner = Owner.ANIMATION
var generation := 0
var valid := false
var stance_status := ConstraintStatus.NOT_CHECKED
var support_status := ConstraintStatus.NOT_CHECKED
var reach_status := ConstraintStatus.NOT_CHECKED
var toe_status := ConstraintStatus.NOT_CHECKED
var surface_target := Vector3.ZERO
var surface_normal := Vector3.UP
var ankle_target := Vector3.ZERO
var raw_surface := Vector3.ZERO
var reason := "animation"


static func constraint_ok(status: ConstraintStatus) -> bool:
	return status != ConstraintStatus.VIOLATED


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
