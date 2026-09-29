extends RefCounted
## Foot lock: a RESTING foot stays where it was planted in the world while the body sways or turns
## over it, instead of following the animated ankle (which swings with the body across treads, so
## every tread crossing re-seated the foot and a smooth turn kept it stepping). It is only moved -
## a re-plant, which `FootIKV2Stepper` then walks as a step - once the animated ankle has drifted
## more than `release` metres from it horizontally. Walking, jumping and a foot not planted clear
## the lock: there is nothing to hold.

const RELEASE := 0.25 # m the animated ankle may drift from the anchor before it re-plants
const FAR := 0.32 # m the anchor may sit from the hip horizontally (the leg's reach)

var _anchor: Dictionary = {} # side -> world position the foot is held at (horizontal used)


## The world position to aim the foot at. `animated` is the animated ankle in world space, `hip`
## the hip; the foot re-plants when the animated ankle has drifted RELEASE from the anchor, or
## the anchor has got more than FAR from the hip horizontally (out of the leg's reach).
func held(side: StringName, animated: Vector3, hip: Vector3, resting: bool) -> Vector3:
	if not resting:
		_anchor.erase(side)
		return animated
	if _anchor.has(side):
		var anchor: Vector3 = _anchor[side]
		var apart := Vector2(animated.x - anchor.x, animated.z - anchor.z).length()
		var reach := Vector2(hip.x - anchor.x, hip.z - anchor.z).length()
		if apart <= RELEASE and reach <= FAR:
			return Vector3(anchor.x, animated.y, anchor.z)
	_anchor[side] = animated
	return animated
