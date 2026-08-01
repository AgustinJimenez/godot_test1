extends Node3D
## Static reference scene for foot IK development: the same idle character
## standing on a row of different platform shapes (flat ground, ramps at
## several angles, staircases with different step heights), all built and
## laid out at once so foot penetration/floating is visible across every
## case side by side instead of testing one shape at a time in a real level.
## No IK is applied yet - this is deliberately "before" footage.

const PLATFORM_WIDTH := 3.0
const PLATFORM_LENGTH := 4.0
const PLATFORM_THICKNESS := 0.3
const PLATFORM_SPACING := 2.5
const STAIR_STEP_COUNT := 6
const STAIR_TREAD_DEPTH := 0.6

const PLATFORM_MATERIAL_COLOR := Color(0.32, 0.34, 0.38)

## Each entry becomes one platform, in this left-to-right order.
## "ramp" uses angle_deg; "stairs" uses step_height.
const CASES: Array[Dictionary] = [
	{"label": "Flat", "kind": &"flat"},
	{"label": "Ramp 15°", "kind": &"ramp", "angle_deg": 15.0},
	{"label": "Ramp 30°", "kind": &"ramp", "angle_deg": 30.0},
	{"label": "Ramp 45°", "kind": &"ramp", "angle_deg": 45.0},
	{"label": "Stairs 0.10m", "kind": &"stairs", "step_height": 0.1},
	{"label": "Stairs 0.20m", "kind": &"stairs", "step_height": 0.2},
	{"label": "Stairs 0.35m", "kind": &"stairs", "step_height": 0.35},
]

var _platform_material: StandardMaterial3D


func _ready() -> void:
	_platform_material = StandardMaterial3D.new()
	_platform_material.albedo_color = PLATFORM_MATERIAL_COLOR

	for i in CASES.size():
		var case: Dictionary = CASES[i]
		var origin := Vector3(i * PLATFORM_SPACING, 0.0, 0.0)
		var contact := _build_platform(case, origin)
		# Stair treads run perpendicular to the walking direction, so a
		# character facing straight down the stairs (the default orientation)
		# hides the tread-to-tread foot placement behind their own body from
		# this row's side-on inspection angle - facing them across the
		# stairs instead puts each foot's contact point in full view.
		var yaw := PI * 0.5 if case["kind"] == &"stairs" else 0.0
		_place_character(contact, yaw)
		_build_label(case["label"], origin)

	_build_walking_dummies()


## Two more flat platforms, past the CASES row, each with a character
## looping the walk animation *in place* (no actual locomotion - these are
## bare PlayerBody instances with nothing driving movement input) so the
## up/down foot lift the walk cycle should produce is visible side by side
## with and without the modifier - the whole point of the stance/swing
## blend added to fix the "feet don't move up and down while walking" bug
## (see docs/task_history/foot_ik_debugging.md, Bug 4).
func _build_walking_dummies() -> void:
	var cases: Array[Dictionary] = [
		{"label": "Walk (IK ON)", "ik_active": true},
		{"label": "Walk (IK OFF)", "ik_active": false},
	]
	for i in cases.size():
		var case: Dictionary = cases[i]
		var origin := Vector3((CASES.size() + i) * PLATFORM_SPACING, 0.0, 0.0)
		var contact := _build_flat(origin)
		_place_walking_character(contact, case["ik_active"])
		_build_label(case["label"], origin)


func _place_walking_character(contact: Vector3, ik_active: bool) -> void:
	var body := PlayerBody.new()
	add_child(body)
	body.global_position = contact
	body.play_debug_anim(&"unarmed_walk")
	for child in body.skeleton.get_children():
		if child is PlayerFootIKModifier:
			child.active = ik_active
			break


## Builds the platform for `case` at `origin` and returns the world-space
## point a character should stand on to sit at roughly the platform's
## mid-length - the actual foot-contact point IK will eventually need to
## solve for exactly.
func _build_platform(case: Dictionary, origin: Vector3) -> Vector3:
	match case["kind"]:
		&"ramp":
			return _build_ramp(origin, case["angle_deg"])
		&"stairs":
			return _build_stairs(origin, case["step_height"])
		_:
			return _build_flat(origin)


func _build_flat(origin: Vector3) -> Vector3:
	var box := CSGBox3D.new()
	box.size = Vector3(PLATFORM_WIDTH, PLATFORM_THICKNESS, PLATFORM_LENGTH)
	box.material = _platform_material
	box.use_collision = true
	box.position = origin + Vector3(0.0, -PLATFORM_THICKNESS * 0.5, PLATFORM_LENGTH * 0.5)
	add_child(box)
	return origin + Vector3(0.0, 0.0, PLATFORM_LENGTH * 0.5)


## A single inclined slab, rotated about local X by `angle_deg` and sized so
## its low edge sits at `origin`'s height - a smooth ramp needs no per-point
## profile the way the procedural stair rooms do, just one rotated box.
func _build_ramp(origin: Vector3, angle_deg: float) -> Vector3:
	var angle_rad := deg_to_rad(angle_deg)
	var box := CSGBox3D.new()
	box.size = Vector3(PLATFORM_WIDTH, PLATFORM_THICKNESS, PLATFORM_LENGTH)
	box.material = _platform_material
	box.use_collision = true
	box.rotation = Vector3(-angle_rad, 0.0, 0.0)
	# Anchor the ramp's near-bottom edge at origin: offset the (rotated)
	# center by half-length forward and half-thickness down along the
	# ramp's own tilted axes.
	var half_length_offset := box.basis * Vector3(0.0, 0.0, PLATFORM_LENGTH * 0.5)
	var half_thickness_offset := box.basis * Vector3(0.0, -PLATFORM_THICKNESS * 0.5, 0.0)
	box.position = origin + half_length_offset + half_thickness_offset
	add_child(box)
	var mid_rise := tan(angle_rad) * PLATFORM_LENGTH * 0.5
	return origin + Vector3(0.0, mid_rise, PLATFORM_LENGTH * 0.5)


## A simple stacked staircase (fixed tread depth, variable riser height) -
## no ceiling/walls/openings needed here, so plain stacked boxes are enough,
## unlike the procedural generator's ribbon-profile stairs.
func _build_stairs(origin: Vector3, step_height: float) -> Vector3:
	for step in STAIR_STEP_COUNT:
		var step_rise := step_height * (step + 1)
		var tread_start_z := step * STAIR_TREAD_DEPTH
		var box := CSGBox3D.new()
		box.size = Vector3(PLATFORM_WIDTH, step_rise, STAIR_TREAD_DEPTH)
		box.material = _platform_material
		box.use_collision = true
		box.position = origin + Vector3(
				0.0, step_rise * 0.5, tread_start_z + STAIR_TREAD_DEPTH * 0.5)
		add_child(box)
	# Stand right on the riser boundary between two middle steps, not a tread
	# center - combined with the 90-degree yaw in _ready() (which turns the
	# character's own left/right foot stance into a world-Z offset, the same
	# axis steps progress along), this is what puts one foot on the lower
	# tread and the other on the higher one instead of both feet on the same
	# step.
	var mid_step := STAIR_STEP_COUNT / 2
	var lower_rise := step_height * mid_step
	var upper_rise := step_height * (mid_step + 1)
	var boundary_z := mid_step * STAIR_TREAD_DEPTH
	return origin + Vector3(0.0, (lower_rise + upper_rise) * 0.5, boundary_z)


func _place_character(contact: Vector3, yaw: float) -> void:
	var body := PlayerBody.new()
	add_child(body)
	body.global_position = contact
	body.rotation.y = yaw


func _build_label(text: String, origin: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.position = origin + Vector3(0.0, 2.4, PLATFORM_LENGTH * 0.5)
	add_child(label)
