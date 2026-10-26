class_name ClimbHandShuffle
extends RefCounted
## Hand over hand along a ledge: the hands stay on the ledge while the body shimmies, and the hand
## that falls too far behind hops ahead of the body (one hand at a time). Standing still, the hands
## settle back to either side of the body. Positions are one number each: how far along the ledge
## (the body's "right") the hand is.

const HOME := 0.22 # m each hand sits from the body when it is still
const LIMIT := 0.38 # m a hand may trail the body before it hops
const AHEAD := 0.3 # m in front of the body a hop lands
const HOP_TIME := 0.2 # s
const LIFT := 0.08 # m a hopping hand rises off the ledge
const IDLE_RETURN := 0.3 # s of standing still before the hands settle back

var home := HOME # m each hand sits from the body when still (a clip with a wider grip sets it)
var hops := 0 # counted for the lab checks
var _u := {&"left": 0.0, &"right": 0.0}
var _hop := {} # side -> {from, to, t}
var _idle := 0.0


func reset(body_u: float) -> void:
	_u = {&"left": body_u - home, &"right": body_u + home}
	_hop.clear()
	_idle = 0.0


## `body_u` the body's place along the ledge, `moving` -1 / 0 / 1 the way it shimmies.
func update(body_u: float, moving: float, delta: float) -> void:
	for side: StringName in _hop.keys():
		var hop: Dictionary = _hop[side]
		hop["t"] = float(hop["t"]) + delta / HOP_TIME
		_u[side] = lerpf(hop["from"], hop["to"], smoothstep(0.0, 1.0, minf(float(hop["t"]), 1.0)))
		if float(hop["t"]) >= 1.0:
			_hop.erase(side)
	if not _hop.is_empty():
		return
	if moving != 0.0:
		_idle = 0.0
		var behind := LIMIT
		var worst := &""
		for side: StringName in _u:
			var gap := (body_u - float(_u[side])) * signf(moving)
			if gap > behind:
				behind = gap
				worst = side
		if worst != &"":
			_start(worst, body_u + signf(moving) * AHEAD)
		return
	_idle += delta
	if _idle < IDLE_RETURN:
		return
	for side: StringName in _u:
		var rest := body_u + (-home if side == &"left" else home)
		if absf(float(_u[side]) - rest) > 0.03:
			_start(side, rest)
			return


## Where the hand is along the ledge.
func along(side: StringName) -> float:
	return float(_u[side])


## How far the hand is lifted off the ledge (m).
func lift(side: StringName) -> float:
	if not _hop.has(side):
		return 0.0
	return LIFT * sin(PI * minf(float((_hop[side] as Dictionary)["t"]), 1.0))


func _start(side: StringName, to: float) -> void:
	_hop[side] = {"from": float(_u[side]), "to": to, "t": 0.0}
	hops += 1
