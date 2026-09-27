extends Node3D
## Acceptance scene for the v2 foot IK: flat ground, ramps at 15/30/45 degrees, and three
## staircases of increasing step height, all sharing one run. Disables v1's modifier on the player
## so the two cannot fight over the same bones, then adds FootIKV2Modifier. F6 toggles it;
## `-- --foot-ik-v2-check` walks the character up every surface headlessly and grades ankle height,
## sole tilt, and foot clipping.

const V2_MODIFIER := preload("res://tests/manual/foot_ik_v2/foot_ik_v2_modifier.gd")
## v1's trace writer, unchanged - a bounded rotating JSONL window.
const TRACE_WRITER := preload("res://tests/manual/foot_ik/foot_ik_trace_writer.gd")
## Same schema trace_query.py reads (frame + feet.<side>.{sole_clearance,gap,smoothed_target,...}),
## so v2 is inspected with the exact same tooling as v1.
const TRACE_PATH := "user://foot_ik_v2.jsonl"
const TRACE_MAX_LINES := 2000
const SETTLE_FRAMES := 20
const WALK_FRAMES := 150
const ANKLE_TOLERANCE := 0.03
const TILT_TOLERANCE_DEG := 12.0
const CLIP_TOLERANCE := 0.01

const RAMP_ANGLES := [15.0, 30.0, 45.0]
const STAIR_HEIGHTS := [0.10, 0.20, 0.35]
const RAMP_RUN := 4.2 # same run as the staircases (12 treads x 0.35)
const TREAD := 0.35
const STAIR_STEPS := 12
const LANE_SPACING := 8.0
const START_BACKOFF := 0.9
## One lane per surface: flat, then the three ramps, then the three staircases.
const SPOTS := [
	{"name": "flat", "lane": 0, "kind": &"flat"},
	{"name": "ramp15", "lane": 1, "kind": &"ramp", "index": 0},
	{"name": "ramp30", "lane": 2, "kind": &"ramp", "index": 1},
	{"name": "ramp45", "lane": 3, "kind": &"ramp", "index": 2},
	{"name": "stair010", "lane": 4, "kind": &"stair", "index": 0},
	{"name": "stair020", "lane": 5, "kind": &"stair", "index": 1},
	{"name": "stair035", "lane": 6, "kind": &"stair", "index": 2},
]

@onready var player: Player = $Player

var _v2: FootIKV2Modifier
var _trace: FootIkTraceWriter
var _label: Label
var _checking := false
var _spot := 0
var _settle := 0
var _walk := 0
var _worst_ankle := 0.0
var _worst_ankle_spot := ""
var _worst_tilt := 0.0
var _worst_tilt_spot := ""
var _worst_clip := 0.0
var _worst_clip_spot := ""


func _ready() -> void:
	_build_terrain()
	_checking = "--foot-ik-v2-check" in OS.get_cmdline_user_args()
	for child: Node in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			child.active = false # v1 off: one writer per bone.
	_v2 = V2_MODIFIER.new() as FootIKV2Modifier
	_v2.name = &"FootIKV2"
	_v2.player_body = player.body
	player.skeleton.add_child(_v2)
	_trace = TRACE_WRITER.new(TRACE_PATH, TRACE_MAX_LINES)
	# Default CharacterBody3D limit is 45 deg, which sits exactly on the steepest test ramp.
	player.floor_max_angle = deg_to_rad(60.0)
	if _checking:
		_move_to_spot(0)
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)
	_update_label()


## Sampling happens in _process, NOT _physics_process: a SkeletonModifier3D publishes in the
## skeleton's deferred update, which runs after the node's _physics_process, so reading the pose
## there measures the UNcorrected one (it looked like a 22 cm float that the solver never made).
func _process(_delta: float) -> void:
	_capture()


func _physics_process(_delta: float) -> void:
	if _checking:
		_run_check()
		return
	if Input.is_action_just_pressed(&"debug_camera"):
		_v2.enabled = not _v2.enabled
		_update_label()


func _update_label() -> void:
	_label.text = ("Foot IK v2 (flat / ramps 15-45 / stairs 0.10-0.35): %s   [F6]\n"
			+ "weight=%.2f  ankle_height=%.3f  max_lift=%.3f") % [
			"ON" if _v2.enabled else "OFF", _v2.weight, _v2.ankle_height, _v2.max_lift]


## One trace frame per physics tick, in trace_query.py's schema: the real correction target the
## modifier chose (not a re-derivation), where the foot ended up, and how the sole sits.
func _capture() -> void:
	if _trace == null or _v2 == null or _v2._legs.is_empty():
		return
	var frame := {
		"frame": Engine.get_physics_frames(),
		"kind": "foot_ik_v2",
		"root": _v3(player.global_position),
		"feet": {},
	}
	for side: StringName in FootIKV2Modifier.LEGS:
		var leg: Dictionary = _v2._legs.get(side, {})
		if leg.is_empty():
			continue
		var to_world := player.skeleton.global_transform
		var foot: Transform3D = to_world * player.skeleton.get_bone_global_pose(int(leg["foot"]))
		var toe: Transform3D = to_world * player.skeleton.get_bone_global_pose(int(leg["toe"]))
		var sole := (foot.basis * (leg["sole_local"] as Vector3)).normalized()
		var has_target: bool = _v2.debug_target.has(side)
		var target: Vector3 = (_v2.debug_target.get(side, foot.origin) as Vector3)
		var normal: Vector3 = _v2.debug_ground_normal.get(side, Vector3.UP)
		# The target is the ANKLE position (ground + normal * ankle_height), so the sole's own
		# contact point is that far along the sole direction from the bone, and the gap is simply how
		# far the bone sits above its target - not v1's "ground target minus sole depth" shape.
		var sole_point := foot.origin + sole * _v2.ankle_height
		# v1 reports sole clearance against the GROUND; v2's stored target is the ankle position, so
		# the ground is the target pulled back along the normal. Without this the number is just
		# -ankle_height and every frame looks like a penetration.
		var ground_y := (target - normal * _v2.ankle_height).y
		var joints := {}
		for role: String in ["hip", "knee", "foot", "toe"]:
			var bone := int(leg[role])
			if bone < 0:
				continue
			var pose: Transform3D = to_world * player.skeleton.get_bone_global_pose(bone)
			joints[role] = {
				"position": _v3(pose.origin),
				"rotation_quaternion": _q(pose.basis.get_rotation_quaternion()),
			}
		frame["feet"][String(side)] = {
			"foot_pos": _v3(foot.origin),
			"toe_tip_y": toe.origin.y,
			"smoothed_target": _v3(target),
			"target_corrected": has_target,
			"skip_reason": _v2.debug_skip_reason.get(side, ""),
			"gap": _v2.debug_solve.get(side, {}).get("residual", -1.0),
			"sole_clearance": sole_point.y - ground_y,
			"sole_tilt_deg": _v2.debug_align.get(side, {}).get("after_deg", -1.0),
			"ground_normal": _v3(normal),
			"animated_ankle": _v3(_v2.debug_animated_ankle.get(side, foot.origin)),
			"ground": _v3(_v2.debug_ground.get(side, target - normal * _v2.ankle_height)),
			"reach": _solve_fields(side),
			"state": _v2.debug_state.get(side, ""),
			"align": _v2.debug_align.get(side, {}),
			"joints": joints,
		}
	_trace.capture(JSON.stringify(frame))


## JSON has no Vector3; v1's traces carry explicit [x, y, z] arrays and trace_query.py parses those.
## The solver/reach debug dict, with any Vector3 turned into a JSON array.
func _solve_fields(side: StringName) -> Dictionary:
	var out := {}
	for key: String in _v2.debug_solve.get(side, {}):
		var value: Variant = _v2.debug_solve[side][key]
		out[key] = _v3(value) if value is Vector3 else value
	return out


static func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _q(value: Quaternion) -> Array:
	return [value.x, value.y, value.z, value.w]


func _lane_x(lane: int) -> float:
	return -float(lane) * LANE_SPACING


## Ramps climb toward -Z (the character's default forward), so walking forward ascends them.
func _build_terrain() -> void:
	for index in RAMP_ANGLES.size():
		var angle: float = RAMP_ANGLES[index]
		var body := _add_box(Vector3.ZERO, Vector3(3.0, 0.4, RAMP_RUN))
		body.rotation = Vector3(deg_to_rad(angle), 0.0, 0.0)
		body.position = Vector3(_lane_x(1 + index),
				RAMP_RUN * 0.5 * sin(deg_to_rad(angle)), 0.0)
	for index in STAIR_HEIGHTS.size():
		var step_height: float = STAIR_HEIGHTS[index]
		for step in STAIR_STEPS:
			var top := step_height * float(step + 1)
			_add_box(Vector3(_lane_x(4 + index), top * 0.5 - 0.1,
					RAMP_RUN * 0.5 - TREAD * float(step)),
					Vector3(3.0, top + 0.2, TREAD))


func _add_box(box_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
	body.position = box_position
	return body


## Stand the character just before the surface's low end, facing up it.
func _move_to_spot(index: int) -> void:
	var spot: Dictionary = SPOTS[index]
	player.global_position = Vector3(_lane_x(int(spot["lane"])), 0.35,
			RAMP_RUN * 0.5 + START_BACKOFF)
	player.rotation = Vector3.ZERO # model forward is -Z, the ramps' climb direction
	player.velocity = Vector3.ZERO
	_settle = 0
	_walk = 0


func _run_check() -> void:
	if _settle < SETTLE_FRAMES:
		_settle += 1
		return
	var spot: Dictionary = SPOTS[_spot]
	if _walk < WALK_FRAMES:
		_walk += 1
		player.movement_input_override = Vector2(0.0, -1.0) # walk forward, up the surface
		_measure(str(spot["name"]))
		return
	player.movement_input_override = Vector2.ZERO
	_spot += 1
	if _spot < SPOTS.size():
		_move_to_spot(_spot)
		return
	var passed := (_worst_ankle <= ANKLE_TOLERANCE and _worst_tilt <= TILT_TOLERANCE_DEG
			and _worst_clip <= CLIP_TOLERANCE)
	print(("FOOT_IK_V2_CHECK %s surfaces=%d frames=%d ankle_err=%.4f@%s tilt=%.1f@%s "
			+ "clip=%.4f@%s limits=%.3f/%.1f/%.3f") % [
			"PASS" if passed else "FAIL", SPOTS.size(), WALK_FRAMES, _worst_ankle,
			_worst_ankle_spot, _worst_tilt, _worst_tilt_spot, _worst_clip, _worst_clip_spot,
			ANKLE_TOLERANCE, TILT_TOLERANCE_DEG, CLIP_TOLERANCE])
	get_tree().quit(0 if passed else 1)


## Per-frame grade for both feet: where the ankle is against the ground under it, how the sole
## lies against that ground, and whether the sole's own sample points have gone under it.
func _measure(name: String) -> void:
	for side: StringName in FootIKV2Modifier.LEGS:
		var leg: Dictionary = _v2._legs.get(side, {})
		if leg.is_empty():
			continue
		# Grade against the surface the modifier ACTUALLY sampled (its own decision), not a second
		# ray cast here - a restated probe can disagree with the code it is meant to check.
		if not _v2.debug_target.has(side):
			continue # skipped this frame by design (mid-swing / out of reach): animation keeps it
		var to_world := player.skeleton.global_transform
		var foot: Transform3D = to_world * player.skeleton.get_bone_global_pose(int(leg["foot"]))
		var ground: Vector3 = _v2.debug_ground.get(side, foot.origin)
		var normal: Vector3 = _v2.debug_ground_normal.get(side, Vector3.UP)
		# Grade only a foot that is actually down. A swing foot's gap and tilt mean nothing, but a
		# wrongly-corrected grounded foot must NOT slip through: accept it if EITHER the animation or
		# the result has it down, so a bad correction is still measured.
		var expected_y := ground.y + _v2.ankle_height
		var animated_y: float = _v2.debug_animated_ankle.get(side, Vector2.ZERO).y
		if absf(foot.origin.y - expected_y) > 0.05 and absf(animated_y - expected_y) > 0.05:
			continue
		# Authoritative values from the modifier itself: how far the landing ended from the target it
		# was given, and how far the sole ended from the surface normal it was aligned to. Recomputing
		# these here in world space disagreed with the modifier's own (skeleton-space) result and made
		# a correctly-aligned foot read as 60-127 deg off.
		var ankle_error := absf(float(_v2.debug_solve.get(side, {}).get("residual", 999.0)))
		if ankle_error > _worst_ankle:
			_worst_ankle = ankle_error
			_worst_ankle_spot = name
		var sole := (foot.basis * (leg["sole_local"] as Vector3)).normalized()
		var tilt := absf(float(_v2.debug_align.get(side, {}).get("after_deg", 999.0)))
		if tilt > _worst_tilt:
			_worst_tilt = tilt
			_worst_tilt_spot = name
		# The sole's contact points: the ankle and the toe, projected onto the sole plane.
		var toe: Transform3D = to_world * player.skeleton.get_bone_global_pose(int(leg["toe"]))
		for point: Vector3 in [foot.origin - sole * _v2.ankle_height,
				toe.origin - sole * _v2.ankle_height]:
			var under := _ground_height_under(point)
			if is_nan(under):
				continue
			var clip := under - point.y
			if clip > _worst_clip:
				_worst_clip = clip
				_worst_clip_spot = name


func _ground_hit(ankle: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
			ankle + Vector3.UP * _v2.ray_up, ankle - Vector3.UP * _v2.ray_down, _v2.ground_mask)
	query.exclude = [(player as CollisionObject3D).get_rid()]
	return space.intersect_ray(query)


func _ground_height_under(point: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * 0.5, point - Vector3.UP * 0.3, _v2.ground_mask)
	query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y
