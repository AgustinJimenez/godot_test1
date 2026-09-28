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
## Headless checks write here so they can never overwrite a live session's trace.
const CHECK_TRACE_PATH := "user://foot_ik_v2_check.jsonl"
const TRACE_MAX_LINES := 2000
const SETTLE_FRAMES := 20
## Long enough to climb every surface (4.2 m at 3.2 m/s plus the 0.9 m run-in is ~96 frames) and no
## longer: past that the character walks off the top and falls, which is not what is being graded.
const WALK_FRAMES := 90
## Toe tip / heel must not float more than this above the real surface on a foot meant to be down.
const FORWARD_FLOAT_LIMIT := 0.08
## How far a corrected foot may end from the target it finally chased. Walking up the 45 degree ramp
## the leg is at full extension and lands up to ~6 cm short (measured 0.058), which is expected;
## a clamped foot is not graded here at all (see _measure).
const ANKLE_TOLERANCE := 0.06
const TILT_TOLERANCE_DEG := 12.0
## The user's scenario: stand on the closest ramp and strafe left/right along the cross-slope.
const LATERAL_LANE := 1        # ramp15
## The user's live session, replayed: standing on ramp15 with the body turned across the slope
## (yaw ~99 deg, the camera looking sideways), strafing DOWNhill (left) and UPhill (right) in
## alternating passes with a brief pause between. Frame counts come from the recorded trace.
const REPLAY_START_X_OFFSET := 1.7
const REPLAY_START_Z := -0.6
const REPLAY_YAW_DEG := 99.0
## Regression for the last frame of a live session: standing still at mid-ramp with the body across
## the slope (final root x -7.158, z -0.095, yaw 97.6). The downhill (left) foot's floor was out of
## the leg's reach, v2 released it (`out_of_reach`) and it hung ~7 cm above the ramp for the whole
## idle. Replays the session's own history from the floor: a run toward the ramp, a JUMP onto its
## side, a short walk across the slope, a stop, a second walk with the body turning, a final stop.
## Only the idle segments are graded (a walking / airborne foot is legitimately off the floor).
const IDLE_START_X_OFFSET := 4.9 # root x -3.1 (on the floor) relative to the ramp lane's x
const IDLE_START_Z := 0.19
const IDLE_YAW_DEG := 89.0
const IDLE_FROM_FLOOR := true
const IDLE_REPLAY := [
	{"name": "approach", "input": Vector2(0.0, -1.0), "frames": 12, "grade": false},
	{"name": "jump", "input": Vector2(0.0, -1.0), "frames": 50, "jump": true, "grade": false},
	{"name": "land_walk", "input": Vector2(0.0, -1.0), "frames": 16, "grade": false},
	{"name": "idle_a", "input": Vector2.ZERO, "frames": 10, "grade": true},
	{"name": "walk_a", "input": Vector2(0.0, -1.0), "frames": 31, "grade": false},
	{"name": "idle_b", "input": Vector2.ZERO, "frames": 85, "grade": true},
	{"name": "walk_b", "input": Vector2(0.0, -1.0), "frames": 34, "yaw": 95.1, "grade": false},
	{"name": "idle_end", "input": Vector2.ZERO, "frames": 450, "grade": true},
]
## Jumping on the 45 degree ramp (live log): the standing-still squat used to fire in the air and
## on landing, pushing the pelvis 0.2-0.4 m down and back up frame to frame. Only the pelvis drop is
## graded: it must stay within `pelvis_limit` for the jump (crouch, take-off, air, landing) after
## PELVIS_GRACE_FRAMES, which lets the squat held going in release (0.6 m/s).
const PELVIS_GRACE_FRAMES := 30
const JUMP_REPLAY := [
	{"name": "idle_settle", "input": Vector2.ZERO, "frames": 30, "grade": false},
	{"name": "jump", "input": Vector2.ZERO, "frames": 90, "jump": true, "grade": false,
			"pelvis_limit": 0.10},
	{"name": "idle_after", "input": Vector2.ZERO, "frames": 60, "grade": false},
]
## Stricter than the walking replay: at rest both tips must be on the floor.
## The tip sphere sits on the toe bone, ~1 cm above the sole, so a planted foot reads ~+1 cm.
const IDLE_FLOAT_LIMIT := 0.04
## An idle segment is graded only after the walk-to-idle transition has settled.
const IDLE_SETTLE_FRAMES := 40
## Standing on the stairs' edge with one foot on the floor 0.38 m below: both feet must touch.
const STAIRS_EDGE_FLOAT_LIMIT := 0.04
const RAMP_REPLAY := [
	{"name": "downhill1", "input": Vector2(-1.0, 0.0), "frames": 75},
	{"name": "pause1", "input": Vector2.ZERO, "frames": 5},
	{"name": "uphill1", "input": Vector2(1.0, 0.0), "frames": 100},
	{"name": "pause2", "input": Vector2.ZERO, "frames": 5},
	{"name": "downhill2", "input": Vector2(-1.0, 0.0), "frames": 112},
	{"name": "pause3", "input": Vector2.ZERO, "frames": 5},
	{"name": "uphill2", "input": Vector2(1.0, 0.0), "frames": 111},
	{"name": "end_idle", "input": Vector2.ZERO, "frames": 60},
]
## Pass limits for the toe-tip sphere against the real ramp on a foot that is meant to be down.
const TIP_CLIP_LIMIT := 0.02
const TIP_FLOAT_LIMIT := 0.08
const FLOAT_TOLERANCE := 0.03  # sole may sit this far above the real ramp surface
## Ignore the drop-onto-the-ramp settle; grade the steady strafe only.
const MEASURE_AFTER := 0
const TOE_CLIP_TOLERANCE := 0.01
const CLIP_TOLERANCE := 0.01
const TOE_TIP_MARGIN := 0.035
## Toe-tip sphere grading (report-only): a grounded foot whose tip sphere is this far under / over
## the real surface is logged as a TIP_CLIP / TIP_FLOAT event with its frame, side and state.
const TIP_CLIP_TOLERANCE := 0.01
const TIP_FLOAT_TOLERANCE := 0.06
const HEEL_CLIP_TOLERANCE := 0.02
## A heel whose surface is this much lower than the foot's own is overhanging an edge.
const HEEL_OVERHANG_DROP := 0.07
## The tip touches the floor within this band around the surface (a resting toe sits ~1 cm up).
const TOUCH_BELOW := 0.015
const TOUCH_ABOVE := 0.04
const TIP_EVENT_LIMIT := 3 # printed per surface; the counts in the summary are complete

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
var _run_id := ""
var _mode := "live"
var _last_tip_event := {}
var _tip_by_spot := {}
var _segment := ""
var _grade_now := true
var _from_floor := false
var _stairs_start := false
var _stairs_x := 0.5
var _pelvis_limit := INF
var _frames_in_segment := 0
var _pelvis_excess := 0.0
var _ramp_index := 0
var _jump_pressed_at := -100
var _toe_spheres := {}
var _heel_spheres := {}
var _tip_clip_max := 0.0
var _tip_float_max := 0.0
var _tip_clip_events := 0
var _tip_float_events := 0
var _tip_events_printed := {}
var _tip_material_touch: StandardMaterial3D
var _tip_material_air: StandardMaterial3D
var _checking := false
var _ramp_checking := false
var _idle_checking := false
var _replay: Array = []
var _start := Vector3.ZERO # x offset from the ramp lane, z, yaw degrees
var _float_limit := TIP_FLOAT_LIMIT
var _spot := 0
var _settle := 0
var _walk := 0
var _worst_ankle := 0.0
var _worst_ankle_spot := ""
var _worst_tilt := 0.0
var _worst_tilt_spot := ""
var _worst_clip := 0.0
var _worst_clip_spot := ""
var _worst_float := 0.0
var _worst_float_spot := ""
var _worst_float_frame := -1


func _ready() -> void:
	_build_terrain()
	_checking = "--foot-ik-v2-check" in OS.get_cmdline_user_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ramp-index="):
			_ramp_index = clampi(arg.trim_prefix("--ramp-index=").to_int(), 0, RAMP_ANGLES.size() - 1)
	_idle_checking = "--foot-ik-v2-idle-check" in OS.get_cmdline_user_args()
	_ramp_checking = _idle_checking or "--foot-ik-v2-ramp-check" in OS.get_cmdline_user_args()
	if _idle_checking:
		_replay = IDLE_REPLAY
		_start = Vector3(IDLE_START_X_OFFSET, IDLE_START_Z, IDLE_YAW_DEG)
		_float_limit = IDLE_FLOAT_LIMIT
		_from_floor = IDLE_FROM_FLOOR
		if "--start-on-ramp" in OS.get_cmdline_user_args():
			# A steep ramp cannot be jumped onto from the floor: start on it (x -5.6, z -0.134).
			_from_floor = false
			_start = Vector3(2.4, IDLE_START_Z, IDLE_YAW_DEG)
		if "--uphill" in OS.get_cmdline_user_args():
			# Facing UP the slope (live log, last frame): one foot ahead and higher, one behind and
			# lower, so the rear foot's floor is far below the animation's flat-ground stance.
			_from_floor = false
			_start = Vector3(2.4, IDLE_START_Z, -7.9)
			_replay = [{"name": "idle_uphill", "input": Vector2.ZERO, "frames": 450, "grade": true}]
		if "--jump45" in OS.get_cmdline_user_args():
			_ramp_index = 2
			_from_floor = false
			_start = Vector3(2.4, IDLE_START_Z, 95.1)
			_replay = JUMP_REPLAY
		if "--stairs" in OS.get_cmdline_user_args():
			# Live log, last frame: idle on the 0.10 m stairs with the shoe tip against the next
			# riser. The clearance pass read that as "lift onto the higher tread" and raised the
			# whole foot 10 cm, leaving the heel floating.
			_stairs_start = true
			_replay = [{"name": "idle_stairs", "input": Vector2.ZERO, "frames": 300, "grade": true}]
		if "--stairs-edge" in OS.get_cmdline_user_args():
			# Same spot as the live log: standing on the stairs' right edge, one foot on step 3 and
			# the other off the side over the floor 0.38 m below. It used to hang 30 cm up (the plan
			# flip-flopped onto the tread's height); it now squats to put that foot on the floor.
			_stairs_start = true
			_stairs_x = 1.42
			_float_limit = STAIRS_EDGE_FLOAT_LIMIT
			_replay = [{"name": "idle_edge", "input": Vector2.ZERO, "frames": 300, "grade": true}]
	else:
		_replay = RAMP_REPLAY
		_start = Vector3(REPLAY_START_X_OFFSET, REPLAY_START_Z, REPLAY_YAW_DEG)
	for child: Node in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			# v1 off: one writer per bone. `active = false` is not enough - v1 turns itself back on
			# every time the player lands (set_character_grounded), so v1 and v2 were both running
			# and v1's pelvis drop pulled the hips down on ramps. The debug switch is the one that
			# sticks.
			(child as PlayerFootIKModifier).set_debug_enabled(false)
	# Bisect switch: `--disable-modifier=<NodeName>` turns one existing skeleton modifier off.
	for child: Node in player.skeleton.get_children():
		if child is SkeletonModifier3D:
			print("[modifier] %s %s active=%s" % [child.name, child.get_class(), child.active])
			if ("--disable-modifier=%s" % child.name) in OS.get_cmdline_user_args():
				child.active = false
	_v2 = V2_MODIFIER.new() as FootIKV2Modifier
	_v2.name = &"FootIKV2"
	_v2.player_body = player.body
	player.skeleton.add_child(_v2)
	# A/B switch for the headless checks: same scenario with the correction off.
	_v2.enabled = not ("--foot-ik-v2-off" in OS.get_cmdline_user_args())
	if "--foot-ik-v2-no-pelvis-drop" in OS.get_cmdline_user_args():
		_v2.max_pelvis_drop = 0.0
	if "--foot-ik-v2-jump-not-moving" in OS.get_cmdline_user_args():
		_v2.jump_counts_as_moving = false
	if "--foot-ik-v2-no-reach-when-still" in OS.get_cmdline_user_args():
		_v2.reach_when_still = false
	if "--foot-ik-v2-no-reach-when-moving" in OS.get_cmdline_user_args():
		_v2.reach_when_moving = false
	_mode = "ramp_check" if _ramp_checking else ("forward_check" if _checking else "live")
	_run_id = "%s_%d" % [Time.get_datetime_string_from_system(false, true).replace(" ", "T"),
			Time.get_ticks_msec()]
	_trace = TRACE_WRITER.new(
			TRACE_PATH if _mode == "live" else CHECK_TRACE_PATH, TRACE_MAX_LINES)
	# Default CharacterBody3D limit is 45 deg, which sits exactly on the steepest test ramp.
	player.floor_max_angle = deg_to_rad(60.0)
	if _ramp_checking:
		_place_on_ramp()
		return
	if _checking:
		_move_to_spot(0)
		return
	_build_toe_spheres()
	_start_third_person.call_deferred()
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
	_update_toe_spheres()


## Orange sphere on each toe tip, v1's definition (foot_ik_toe_tip_clearance.gd): the toe bone
## pushed TOE_TIP_MARGIN further along the ankle-to-toe direction. Interactive runs only.
func _build_toe_spheres() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	_tip_material_touch = _tip_material(Color(0.0, 0.9, 0.2))
	_tip_material_air = _tip_material(Color(1.0, 0.0, 0.0))
	for side: StringName in FootIKV2Modifier.LEGS:
		var sphere := MeshInstance3D.new()
		sphere.mesh = mesh
		sphere.top_level = true
		add_child(sphere)
		_toe_spheres[side] = sphere
		var heel := MeshInstance3D.new()
		heel.mesh = mesh
		heel.top_level = true
		add_child(heel)
		_heel_spheres[side] = heel


## The player starts in first person; this scene is about watching the feet, so start in the
## player's own third-person camera by sending it the same action its V key sends.
func _start_third_person() -> void:
	for pressed: bool in [true, false]:
		var press := InputEventAction.new()
		press.action = &"debug_camera"
		press.pressed = pressed
		Input.parse_input_event(press)


func _tip_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat


func _update_toe_spheres() -> void:
	if _v2 == null:
		return
	for side: StringName in _toe_spheres:
		if not _v2._legs.has(side):
			continue
		var sphere: MeshInstance3D = _toe_spheres[side]
		var tip := _tip_point(side)
		sphere.global_position = tip
		# Green = the tip touches the real surface under it, red = it does not (floating above it,
		# or sunk below it). Every frame, swing or not - what you see is what is graded.
		var surface := _surface_above(tip)
		var touching := (not is_nan(surface) and (_overhangs(side, surface)
				or (tip.y - surface >= -TOUCH_BELOW and tip.y - surface <= TOUCH_ABOVE)))
		var material := _tip_material_touch if touching else _tip_material_air
		sphere.material_override = material
		# Same rule for the heel sphere on the back of the shoe.
		var heel: MeshInstance3D = _heel_spheres[side]
		var heel_point := _heel_point(side)
		heel.global_position = heel_point
		var heel_clearance: Variant = _heel_clearance(side)
		var heel_touching: bool = (heel_clearance == null
				or (float(heel_clearance) >= -TOUCH_BELOW and float(heel_clearance) <= TOUCH_ABOVE))
		heel.material_override = _tip_material_touch if heel_touching else _tip_material_air


## The visible heel in world space: the mesh-measured rearmost sole-level point, riding the
## published foot bone pose.
func _heel_point(side: StringName) -> Vector3:
	var leg: Dictionary = _v2._legs[side]
	return _pub(int(leg["foot"])) * (leg["heel_local"] as Vector3)


## Heel height above the real surface under it (null when there is none).
func _heel_clearance(side: StringName) -> Variant:
	var heel := _heel_point(side)
	var surface := _surface_above(heel)
	if is_nan(surface):
		return null
	if _overhangs(side, surface):
		return null # a heel hanging over an edge is an overhang, not a float
	return heel.y - surface


## The toe tip in world space: v1's definition (foot_ik_toe_tip_clearance.gd).
func _tip_point(side: StringName) -> Vector3:
	var leg: Dictionary = _v2._legs[side]
	var to_world := player.skeleton.global_transform
	var foot: Transform3D = _pub(int(leg["foot"]))
	var toe: Transform3D = _pub(int(leg["toe"]))
	return toe.origin + (toe.origin - foot.origin).normalized() * TOE_TIP_MARGIN


## A foot meant to be down: the animation or the correction puts the ankle near the surface.
## A swing foot is legitimately in the air, so its tip is never graded.
func _foot_is_grounded(side: StringName, surface_under_tip: float) -> bool:
	var leg: Dictionary = _v2._legs[side]
	var foot: Transform3D = _pub(int(leg["foot"]))
	var surface_here := _surface_above(foot.origin)
	if is_nan(surface_here):
		surface_here = surface_under_tip
	var expected_y := surface_here + _v2.ankle_height
	var animated_y: float = _v2.debug_animated_ankle.get(side, Vector2.ZERO).y
	return (absf(foot.origin.y - expected_y) <= 0.05
			or absf(animated_y - expected_y) <= 0.05)


## The tip sphere against the real surface under it: point, surface height, clearance, whether the
## foot is meant to be down (a swing foot is never graded) and the resulting event.
func _tip_state(side: StringName) -> Dictionary:
	var out := {"point": Vector3.ZERO, "surface": null, "clearance": null,
			"grounded": false, "event": ""}
	if not _v2._legs.has(side):
		return out
	var tip := _tip_point(side)
	out["point"] = tip
	var surface := _surface_above(tip)
	if is_nan(surface):
		return out
	out["surface"] = surface
	if _overhangs(side, surface):
		return out # the toe hangs over an edge (ramp end, tread edge): not a float
	out["clearance"] = tip.y - surface
	out["grounded"] = _foot_is_grounded(side, surface)
	if out["grounded"]:
		if tip.y - surface < -TIP_CLIP_TOLERANCE:
			out["event"] = "TIP_CLIP"
		elif tip.y - surface > TIP_FLOAT_TOLERANCE:
			out["event"] = "TIP_FLOAT"
	return out


## True when the surface under a shoe point is much lower than the one the foot stands on: the
## point overhangs an edge (the toe past a ramp's lower end, a heel past a tread). A slope never
## differs that much over a few centimetres.
func _overhangs(side: StringName, point_surface: float) -> bool:
	var leg: Dictionary = _v2._legs[side]
	var foot_surface := _surface_above(_pub(int(leg["foot"])).origin)
	return not is_nan(foot_surface) and point_surface < foot_surface - HEEL_OVERHANG_DROP


## Interactive runs: one line per clip / float episode (when it starts), not one per frame.
func _report_live_tip_event(side: StringName, tip: Dictionary) -> void:
	if _mode != "live":
		return
	var event: String = tip["event"]
	if event != "" and event != _last_tip_event.get(side, ""):
		print("%s frame=%d side=%s clearance=%+.3f surface=%s state=%s skip=%s" % [
				event, Engine.get_physics_frames(), side, float(tip["clearance"]),
				_v2.debug_surface.get(side, ""), _v2.debug_state.get(side, ""),
				_v2.debug_skip_reason.get(side, "")])
	_last_tip_event[side] = event


## Headless checks: grade every walked frame and print the first few events per surface.
func _grade_tip(side: StringName, spot: String) -> void:
	var tip := _tip_state(side)
	# At rest BOTH feet are on the floor by definition, so an idle segment grades every foot: a foot
	# that hangs well above the ramp must not be excused as "mid-swing" (that hid this very bug).
	var at_rest := _idle_checking and spot.begins_with("idle")
	if tip["clearance"] == null or not (tip["grounded"] or at_rest):
		return
	var clearance: float = tip["clearance"]
	_tip_clip_max = maxf(_tip_clip_max, -clearance)
	_tip_float_max = maxf(_tip_float_max, clearance)
	var spot_stats: Array = _tip_by_spot.get(spot, [0.0, 0.0, 0, 0])
	spot_stats[0] = maxf(float(spot_stats[0]), -clearance)
	spot_stats[1] = maxf(float(spot_stats[1]), clearance)
	spot_stats[2] = int(spot_stats[2]) + (1 if clearance < -TIP_CLIP_TOLERANCE else 0)
	spot_stats[3] = int(spot_stats[3]) + (1 if clearance > TIP_FLOAT_TOLERANCE else 0)
	_tip_by_spot[spot] = spot_stats
	var kind: String = tip["event"]
	if kind == "" and at_rest:
		kind = ("TIP_CLIP" if clearance < -TIP_CLIP_TOLERANCE
				else ("TIP_FLOAT" if clearance > TIP_FLOAT_TOLERANCE else ""))
	if kind == "TIP_CLIP":
		_tip_clip_events += 1
	elif kind == "TIP_FLOAT":
		_tip_float_events += 1
	if kind != "" and int(_tip_events_printed.get(spot, 0)) < TIP_EVENT_LIMIT:
		_tip_events_printed[spot] = int(_tip_events_printed.get(spot, 0)) + 1
		print("%s frame=%d spot=%s side=%s clearance=%+.3f surface=%s state=%s skip=%s" % [
				kind, Engine.get_physics_frames(), spot, side, clearance,
				_v2.debug_surface.get(side, ""), _v2.debug_state.get(side, ""),
				_v2.debug_skip_reason.get(side, "")])


## The heel is graded like the toe tip, into the same counters. A planted heel reads about -1 cm
## (the sole plane is not perfectly flat), so it clips only past HEEL_CLIP_TOLERANCE.
func _grade_heel(side: StringName, spot: String) -> void:
	var measured: Variant = _heel_clearance(side)
	if measured == null:
		return
	var at_rest := _idle_checking and spot.begins_with("idle")
	if not (_tip_state(side)["grounded"] or at_rest):
		return
	var clearance: float = measured
	_tip_clip_max = maxf(_tip_clip_max, -clearance)
	_tip_float_max = maxf(_tip_float_max, clearance)
	var stats: Array = _tip_by_spot.get(spot, [0.0, 0.0, 0, 0])
	stats[0] = maxf(float(stats[0]), -clearance)
	stats[1] = maxf(float(stats[1]), clearance)
	var kind := ""
	if clearance < -HEEL_CLIP_TOLERANCE:
		kind = "HEEL_CLIP"
		_tip_clip_events += 1
		stats[2] = int(stats[2]) + 1
	elif clearance > TIP_FLOAT_TOLERANCE:
		kind = "HEEL_FLOAT"
		_tip_float_events += 1
		stats[3] = int(stats[3]) + 1
	_tip_by_spot[spot] = stats
	var key := "heel_" + spot
	if kind != "" and int(_tip_events_printed.get(key, 0)) < TIP_EVENT_LIMIT:
		_tip_events_printed[key] = int(_tip_events_printed.get(key, 0)) + 1
		print("%s frame=%d spot=%s side=%s clearance=%+.3f state=%s skip=%s" % [kind,
				Engine.get_physics_frames(), spot, side, clearance,
				_v2.debug_state.get(side, ""), _v2.debug_skip_reason.get(side, "")])


func _tip_summary() -> String:
	return ("tip_clip_max=%.3f tip_float_max=%.3f tip_clip_frames=%d tip_float_frames=%d "
			+ "pelvis_excess=%.3f") % [_tip_clip_max, _tip_float_max, _tip_clip_events,
			_tip_float_events, _pelvis_excess]


## World transform of a bone as published by the v2 modifier at the end of its last pass (falls
## back to a live read only before the first pass).
func _pub(bone: int) -> Transform3D:
	if _v2.final_pose.has(bone):
		return _v2.final_pose[bone]
	return player.skeleton.global_transform * player.skeleton.get_bone_global_pose(bone)


func _physics_process(_delta: float) -> void:
	if _ramp_checking:
		_run_ramp_check()
		return
	if _checking:
		_run_check()
		return


## F6 toggles v2. It must not use the `debug_camera` action: that is the player's own V key for the
## third-person camera, so looking at the character silently switched the correction off.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F6 and _label != null:
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
		"run_id": _run_id,
		"mode": _mode,
		"time": Time.get_datetime_string_from_system(false, true),
		"run_seconds": Time.get_ticks_msec() / 1000.0,
		"root": _v3(player.global_position),
		"velocity": _v3(player.velocity),
		"v2_enabled": _v2.enabled,
		"v2_last_frame": _v2.debug_last_frame,
		"v2_passes": _v2.debug_passes,
		"pose_frame": _v2.final_frame,
		"feet": {},
	}
	frame.merge(_motion_fields())
	frame["body"] = _body_fields()
	frame["body"]["node_offset"] = _v3(player.body.position)
	frame["body"]["pelvis_drop"] = _v2.debug_pelvis_drop
	frame["body"]["skeleton_origin"] = _v3(player.skeleton.global_transform.origin)
	frame["body"]["skeleton_scale"] = _v3(player.skeleton.global_transform.basis.get_scale())
	frame["body"]["stair_hover_y"] = float(player.get("_stair_hover_offset_y"))
	for side: StringName in FootIKV2Modifier.LEGS:
		var leg: Dictionary = _v2._legs.get(side, {})
		if leg.is_empty():
			continue
		var to_world := player.skeleton.global_transform
		var foot: Transform3D = _pub(int(leg["foot"]))
		var toe: Transform3D = _pub(int(leg["toe"]))
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
			var pose: Transform3D = _pub(bone)
			joints[role] = {
				"position": _v3(pose.origin),
				"rotation_quaternion": _q(pose.basis.get_rotation_quaternion()),
			}
		var tip := _tip_state(side)
		_report_live_tip_event(side, tip)
		frame["feet"][String(side)] = {
			"foot_pos": _v3(foot.origin),
			"toe_pos": _v3(toe.origin),
			"tip": _v3(tip["point"]),
			"tip_surface_y": tip["surface"],
			"tip_clearance": tip["clearance"],
			"tip_event": tip["event"],
			"heel": _v3(_heel_point(side)),
			"heel_clearance": _heel_clearance(side),
			"grounded": tip["grounded"],
			"surface": _v2.debug_surface.get(side, ""),
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
			"reach_check": _v2.debug_reach_check.get(side, {}),
			"stance_shift": _v2.debug_stance_shift.get(side, 0.0),
			"toe_lift": _v2.debug_toe_lift.get(side, 0.0),
			"stance_plan": _v2.debug_stance_plan.get(side, []),
			"state": _v2.debug_state.get(side, ""),
			"align": _v2.debug_align.get(side, {}),
			"joints": joints,
		}
	_trace.capture(JSON.stringify(frame))


## Animation and heading. The body keeps facing where the camera looks while it strafes, so travel
## direction is reported RELATIVE to the facing: local_velocity is (right, up, forward) in m/s and
## move_angle_deg is 0 walking forward, +90 strafing right, -90 left, 180 backwards.
func _motion_fields() -> Dictionary:
	var anim := player.body.anim_player
	var facing := -player.global_basis.z
	var local_velocity := player.global_basis.inverse() * player.velocity
	var horizontal := Vector2(local_velocity.x, -local_velocity.z)
	return {
		"animation": String(anim.current_animation) if anim != null else "",
		"animation_time": anim.current_animation_position if anim != null else 0.0,
		"facing": _v3(facing),
		"facing_yaw_deg": rad_to_deg(atan2(-facing.x, -facing.z)),
		"local_velocity": _v3(local_velocity),
		"move_angle_deg": (rad_to_deg(atan2(horizontal.x, horizontal.y))
				if horizontal.length() > 0.1 else null),
	}


## Pelvis and spine as published: position (world) and rotation, plus the pelvis's height above
## the character root, which is how far the body drops or rises against the animation.
func _body_fields() -> Dictionary:
	var out := {}
	for role: StringName in [&"Hips", &"Spine", &"Spine1", &"Spine2"]:
		var bone := player.skeleton.find_bone(player.body.resolve_bone_name(role))
		if bone < 0:
			continue
		var pose := _pub(bone)
		out[String(role).to_lower()] = {"position": _v3(pose.origin),
				"rotation_quaternion": _q(pose.basis.get_rotation_quaternion())}
	var hips_bone := player.skeleton.find_bone(player.body.resolve_bone_name(&"Hips"))
	if hips_bone >= 0:
		out["hips_local_pose"] = _v3(player.skeleton.get_bone_pose(hips_bone).origin)
		out["hips_rest"] = _v3(player.skeleton.get_bone_rest(hips_bone).origin)
		out["hips_global_pose_now"] = _v3(player.skeleton.get_bone_global_pose(hips_bone).origin)
		out["hips_parent"] = String(player.skeleton.get_bone_name(
				player.skeleton.get_bone_parent(hips_bone)))
	var modifiers := {}
	for child: Node in player.skeleton.get_children():
		if child is SkeletonModifier3D:
			modifiers[String(child.name)] = (child as SkeletonModifier3D).active
	out["modifiers_active"] = modifiers
	if out.has("hips"):
		out["hips_above_root"] = (out["hips"]["position"][1] as float) - player.global_position.y
	return out


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
		# Wide enough that the cross-slope strafe test stays on the ramp.
		var body := _add_box(Vector3.ZERO, Vector3(6.0, 0.4, RAMP_RUN))
		body.name = "Ramp%d" % int(angle)
		body.rotation = Vector3(deg_to_rad(angle), 0.0, 0.0)
		body.position = Vector3(_lane_x(1 + index),
				RAMP_RUN * 0.5 * sin(deg_to_rad(angle)), 0.0)
	for index in STAIR_HEIGHTS.size():
		var step_height: float = STAIR_HEIGHTS[index]
		for step in STAIR_STEPS:
			var top := step_height * float(step + 1)
			var tread := _add_box(Vector3(_lane_x(4 + index), top * 0.5 - 0.1,
					RAMP_RUN * 0.5 - TREAD * float(step)),
					Vector3(3.0, top + 0.2, TREAD))
			tread.name = "Stair%03d_step%d" % [int(step_height * 100.0), step + 1]


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
			and _worst_clip <= CLIP_TOLERANCE and _tip_clip_max <= TIP_CLIP_LIMIT
			and _tip_float_max <= FORWARD_FLOAT_LIMIT)
	print(("FOOT_IK_V2_CHECK %s surfaces=%d frames=%d ankle_err=%.4f@%s tilt=%.1f@%s "
			+ "clip=%.4f@%s limits=%.3f/%.1f/%.3f %s") % [
			"PASS" if passed else "FAIL", SPOTS.size(), WALK_FRAMES, _worst_ankle,
			_worst_ankle_spot, _worst_tilt, _worst_tilt_spot, _worst_clip, _worst_clip_spot,
			ANKLE_TOLERANCE, TILT_TOLERANCE_DEG, CLIP_TOLERANCE, _tip_summary()])
	get_tree().quit(0 if passed else 1)


## Per-frame grade for both feet: where the ankle is against the ground under it, how the sole
## lies against that ground, and whether the sole's own sample points have gone under it.
func _measure(name: String) -> void:
	for side: StringName in FootIKV2Modifier.LEGS:
		var leg: Dictionary = _v2._legs.get(side, {})
		if leg.is_empty():
			continue
		_grade_tip(side, name)
		# Grade against the surface the modifier ACTUALLY sampled (its own decision), not a second
		# ray cast here - a restated probe can disagree with the code it is meant to check.
		if not _v2.debug_target.has(side):
			continue # skipped this frame by design (mid-swing / out of reach): animation keeps it
		var to_world := player.skeleton.global_transform
		var foot: Transform3D = _pub(int(leg["foot"]))
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
		var solved: Dictionary = _v2.debug_solve.get(side, {})
		# A foot clamped at the leg's reach is short of its floor by design (graded by the tip / heel
		# clearance instead), so its residual is not an error.
		var ankle_error := (0.0 if bool(solved.get("clamped", false))
				else absf(float(solved.get("residual", 999.0))))
		if ankle_error > _worst_ankle:
			_worst_ankle = ankle_error
			_worst_ankle_spot = name
		var sole := (foot.basis * (leg["sole_local"] as Vector3)).normalized()
		var tilt := absf(float(_v2.debug_align.get(side, {}).get("after_deg", 999.0)))
		if tilt > _worst_tilt:
			_worst_tilt = tilt
			_worst_tilt_spot = name
		# The sole's contact points: the ankle and the toe, projected onto the sole plane.
		var toe: Transform3D = _pub(int(leg["toe"]))
		for point: Vector3 in [foot.origin - sole * _v2.ankle_height,
				toe.origin + sole * float(leg["toe_depth"])]:
			var under := _ground_height_under(point)
			if is_nan(under):
				continue
			var clip := under - point.y
			if clip > _worst_clip:
				_worst_clip = clip
				_worst_clip_spot = name


## --- user scenario: replay of the live session on the closest ramp ------------------------
func _place_on_ramp() -> void:
	if _stairs_start:
		# Step 3 of the 0.10 m staircase (top 0.30, z 1.225..1.575), 1.36 m in, facing 13 degrees.
		player.global_position = Vector3(_lane_x(4) + _stairs_x, 0.6, 1.36)
		player.rotation = Vector3(0.0, deg_to_rad(13.2), 0.0)
		player.velocity = Vector3.ZERO
		_settle = 0
		_walk = 0
		return
	var angle := deg_to_rad(RAMP_ANGLES[_ramp_index] as float)
	# Top surface of the tilted 0.4 m slab at this z, plus a small drop so it settles onto it.
	var surface_y := RAMP_RUN * 0.5 * sin(angle) - _start.y * tan(angle) + 0.2 / cos(angle)
	if _from_floor:
		surface_y = 0.0 # start on the floor beside the ramp, as the live session did
	player.global_position = Vector3(_lane_x(LATERAL_LANE + _ramp_index) + _start.x,
			surface_y + 0.3, _start.y)
	player.rotation = Vector3(0.0, deg_to_rad(_start.z), 0.0)
	player.velocity = Vector3.ZERO
	_settle = 0
	_walk = 0


func _run_ramp_check() -> void:
	if _settle < SETTLE_FRAMES:
		_settle += 1
		return
	var frames_left := _walk
	var step: Dictionary = {}
	for candidate: Dictionary in _replay:
		if frames_left < int(candidate["frames"]):
			step = candidate
			break
		frames_left -= int(candidate["frames"])
	if step.is_empty():
		_finish_ramp_check()
		return
	if str(step["name"]) != _segment and step.has("yaw"):
		player.rotation.y = deg_to_rad(float(step["yaw"]))
	if str(step["name"]) != _segment and bool(step.get("jump", false)):
		Input.action_press(&"jump")
		_jump_pressed_at = _walk
	elif Input.is_action_pressed(&"jump") and _walk > _jump_pressed_at + 2:
		Input.action_release(&"jump")
	_segment = str(step["name"])
	_frames_in_segment = frames_left
	_pelvis_limit = float(step.get("pelvis_limit", INF))
	_grade_now = bool(step.get("grade", true)) and (
			not _idle_checking or frames_left >= IDLE_SETTLE_FRAMES)
	player.movement_input_override = step["input"]
	_walk += 1
	_measure_ramp()


func _finish_ramp_check() -> void:
	player.movement_input_override = Vector2.ZERO
	var passed := (_tip_clip_max <= TIP_CLIP_LIMIT and _tip_float_max <= _float_limit
			and _pelvis_excess <= 0.0)
	for segment: Dictionary in _replay:
		var stats: Array = _tip_by_spot.get(str(segment["name"]), [0.0, 0.0, 0, 0])
		print(("  segment %-10s frames=%3d tip_clip_max=%.3f tip_float_max=%.3f "
				+ "clip_frames=%d float_frames=%d") % [segment["name"], segment["frames"],
				stats[0], stats[1], stats[2], stats[3]])
	print(("FOOT_IK_V2_%s %s frames=%d %s limits=clip<=%.3f,float<=%.3f "
			+ "(info: ankle_float=%.3f toe_sole_clip=%.3f)") % [
			"IDLE_CHECK" if _idle_checking else "RAMP_CHECK", "PASS" if passed else "FAIL",
			_walk, _tip_summary(), TIP_CLIP_LIMIT, _float_limit, _worst_float, _worst_clip])
	get_tree().quit(0 if passed else 1)


## Independent of the modifier: this harness casts its own ray from high above so it finds the RAMP
## (not the floor beneath it), then compares the foot's sole points against that real surface.
func _measure_ramp() -> void:
	if _frames_in_segment >= PELVIS_GRACE_FRAMES and _v2.debug_pelvis_drop > _pelvis_limit:
		_pelvis_excess = maxf(_pelvis_excess, _v2.debug_pelvis_drop - _pelvis_limit)
	if _walk < MEASURE_AFTER:
		return
	for side: StringName in FootIKV2Modifier.LEGS:
		var leg: Dictionary = _v2._legs.get(side, {})
		if leg.is_empty():
			continue
		if _grade_now:
			_grade_tip(side, _segment)
			_grade_heel(side, _segment)
		var to_world := player.skeleton.global_transform
		var foot: Transform3D = _pub(int(leg["foot"]))
		var toe: Transform3D = _pub(int(leg["toe"]))
		var sole := (foot.basis * (leg["sole_local"] as Vector3)).normalized()
		# The sole is BELOW the bone: the sole direction points down, so the contact point is
		# + (sole * height), not - it. (Subtracting put the "sole" above the ankle and inflated every
		# float by 2 x ankle_height - the ~0.19 m that had been reported as the bug.)
		var ankle_point := foot.origin + sole * _v2.ankle_height
		var toe_point := toe.origin + sole * float(leg["toe_depth"])
		# Grade only a foot that is meant to be down: either the animation or the correction puts it
		# near the surface. A swing foot is in the air, where "float" says nothing - but a wrongly
		# corrected grounded foot still gets measured, so it cannot hide.
		var surface_here := _surface_above(foot.origin)
		if is_nan(surface_here):
			continue
		var expected_y := surface_here + _v2.ankle_height
		var animated_y: float = _v2.debug_animated_ankle.get(side, Vector2.ZERO).y
		if absf(foot.origin.y - expected_y) > 0.05 and absf(animated_y - expected_y) > 0.05:
			continue
		for pair: Array in [["ankle", ankle_point], ["toe", toe_point]]:
			var label: String = pair[0]
			var point: Vector3 = pair[1]
			var surface := _surface_above(point)
			if is_nan(surface):
				continue
			var clearance := point.y - surface
			if label == "ankle" and clearance > _worst_float:
				_worst_float = clearance
				_worst_float_spot = "%s_%s" % [side, label]
				_worst_float_frame = _walk
			if clearance < -_worst_clip:
				_worst_clip = -clearance
				_worst_clip_spot = "%s_%s" % [side, label]


## Real surface height above a point: cast from well above the body so a ramp/step is found even
## when the point itself sits below it.
func _surface_above(point: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var top := Vector3(point.x, player.global_position.y + 1.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(top, point - Vector3.UP * 1.0,
			_v2.ground_mask)
	query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


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
