class_name FootIKV2StretchHold
extends RefCounted
## The extra pelvis drop a resting, unreachable foot asked for ("stretch hold") only ratchets up
## while idle, so one transient stretch left the body squatted at the cap for good. Once nothing has
## been stretched (or turning) for CALM_SECONDS it lets go, slowly, never below what every leg can
## still reach with MARGIN to spare.

const CALM_SECONDS := 0.5
const MARGIN := 0.15 # m of reach kept in hand
const RELEASE_SPEED := 0.1 # m/s

var calm := 0.0
var landed := false
var _yaw := 0.0
var _last_frame := 0


## `legs` are the solve records (`reach`, `needed`); returns the new hold.
func update(hold: float, drop: float, legs: Array, stretched: bool, yaw: float,
		delta: float) -> float:
	var turning := absf(angle_difference(yaw, _yaw)) > 0.004 # a real turn (0.2 deg/frame)
	_yaw = yaw
	calm = 0.0 if stretched or turning else calm + delta
	if calm <= CALM_SECONDS:
		return hold
	var slack := INF
	for solved: Dictionary in legs:
		slack = minf(slack, float(solved.get("reach", 0.0)) - float(solved.get("needed", 0.0)))
	var floor_hold := maxf(drop - maxf(slack - MARGIN, 0.0), 0.0)
	return maxf(minf(hold, floor_hold), hold - RELEASE_SPEED * delta)


## Landing on a ledge: a foot short of the floor keeps going down. The most a foot short of its
## target (not a swinging one) still needs the pelvis to drop.
static func shortfall(solves: Dictionary, states: Dictionary, normals: Dictionary) -> float:
	var most := 0.0
	for side: StringName in solves:
		var flat: bool = (normals.get(side, Vector3.UP) as Vector3).y > 0.95 # a slope is not a ledge
		if flat and String(states.get(side, "")).begins_with("stretched"):
			most = maxf(most, float((solves[side] as Dictionary).get("residual", 0.0)))
	return most


## True once the capsule is down and still while a flat-floor foot is still short of its floor: the
## land clip is then a resting pose, so the resting reach (pelvis drop) takes over at once. It stays
## true for the rest of that landing (re-deciding every frame flipped the body up and down).
func rests(host: CharacterBody3D, still_speed: float, solves: Dictionary,
		states: Dictionary, normals: Dictionary) -> bool:
	var still := (host.is_on_floor() and absf(host.velocity.y) < 0.5
			and Vector2(host.velocity.x, host.velocity.z).length() <= still_speed)
	var frame := Engine.get_physics_frames()
	landed = landed and frame - _last_frame <= 2 # a new landing starts over
	_last_frame = frame
	landed = still and (landed or shortfall(solves, states, normals) > 0.03)
	return landed
