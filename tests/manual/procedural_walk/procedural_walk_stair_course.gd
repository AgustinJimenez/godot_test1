class_name ProceduralWalkStairCourse
extends RefCounted
## A visual up/landing/down route in front of the lab character. All three lanes share the
## same height function, so preview markers, leg targets, and boxes agree on each tread.

const STEP_COUNT := 12
const STEP_DEPTH := 0.35
const STEP_HEIGHT := 0.18
const TOP_LENGTH := 0.70
const APPROACH := 3.0
const TOE_REACH := 0.245
const LONG_TOE_REACH := 0.26
const HEEL_REACH := 0.13
const UP_HEEL_RESERVE := 0.10
const DOWN_TOE_RESERVE := 0.15

var start_z := 0.0


func configure(character_z: float) -> void:
	start_z = character_z - APPROACH


func support_height(world_z: float) -> float:
	var distance := start_z - world_z
	var run := float(STEP_COUNT) * STEP_DEPTH
	if distance < 0.0 or distance >= run * 2.0 + TOP_LENGTH:
		return 0.0
	if distance < run:
		return float(clampi(int(floorf(distance / STEP_DEPTH)) + 1,
				1, STEP_COUNT)) * STEP_HEIGHT
	if distance < run + TOP_LENGTH:
		return float(STEP_COUNT) * STEP_HEIGHT
	return float(maxi(0, STEP_COUNT - int(floorf(
			(distance - run - TOP_LENGTH) / STEP_DEPTH)) - 1)) * STEP_HEIGHT


func root_height(world_z: float) -> float:
	var distance := start_z - world_z
	var run := float(STEP_COUNT) * STEP_DEPTH
	# Start lowering the body during the last quarter-metre of the top landing,
	# before the leading shoe acquires a lower tread. A body that follows the
	# centerline alone leaves that shoe at full leg extension and visibly hovering.
	var descent_start := run + TOP_LENGTH
	var lead := 0.25
	if distance > descent_start - lead:
		var t := clampf((distance - descent_start + lead) / lead, 0.0, 1.0)
		distance += lead * t * t * (3.0 - 2.0 * t)
	if distance <= 0.0 or distance >= run * 2.0 + TOP_LENGTH:
		return 0.0
	if distance < run:
		return distance / run * float(STEP_COUNT) * STEP_HEIGHT
	if distance < run + TOP_LENGTH:
		return float(STEP_COUNT) * STEP_HEIGHT
	return (1.0 - (distance - run - TOP_LENGTH) / run) * float(STEP_COUNT) * STEP_HEIGHT


func safe_ankle(target: Vector3, long_toe: bool = false) -> Vector3:
	var distance := start_z - target.z
	var run := float(STEP_COUNT) * STEP_DEPTH
	var tread_start := -1.0
	var descending := false
	if distance >= 0.0 and distance < run:
		tread_start = floorf(distance / STEP_DEPTH) * STEP_DEPTH
	elif distance >= run + TOP_LENGTH and distance < run * 2.0 + TOP_LENGTH:
		descending = true
		tread_start = run + TOP_LENGTH + floorf(
				(distance - run - TOP_LENGTH) / STEP_DEPTH) * STEP_DEPTH
	if tread_start >= 0.0:
		var rear_edge := start_z - tread_start
		var front_edge := rear_edge - STEP_DEPTH
		var toe_reach := LONG_TOE_REACH if long_toe else TOE_REACH
		var heel_reserve := 0.075 if long_toe else UP_HEEL_RESERVE
		target.z = clampf(target.z,
				front_edge + (DOWN_TOE_RESERVE if descending else toe_reach),
				rear_edge - (HEEL_REACH if descending else heel_reserve))
	return target


func is_climbing(world_z: float) -> bool:
	var distance := start_z - world_z
	return distance >= 0.0 and distance < float(STEP_COUNT) * STEP_DEPTH


func is_finished(world_z: float) -> bool:
	return start_z - world_z > float(STEP_COUNT) * STEP_DEPTH * 2.0 + TOP_LENGTH + 1.0


func build(stage: Node3D) -> void:
	for child: Node in stage.get_children():
		child.free()
	var run := float(STEP_COUNT) * STEP_DEPTH
	for lane_x in [0.0, 1.4, 2.8]:
		for step in STEP_COUNT:
			var up_z := start_z - (float(step) + 0.5) * STEP_DEPTH
			_add_box(stage, lane_x, up_z, STEP_DEPTH,
					float(step + 1) * STEP_HEIGHT)
		var top_z := start_z - run - TOP_LENGTH * 0.5
		_add_box(stage, lane_x, top_z, TOP_LENGTH, float(STEP_COUNT) * STEP_HEIGHT)
		for step in STEP_COUNT:
			var down_z := start_z - run - TOP_LENGTH - (float(step) + 0.5) * STEP_DEPTH
			_add_box(stage, lane_x, down_z, STEP_DEPTH,
					float(STEP_COUNT - step - 1) * STEP_HEIGHT)


func _add_box(stage: Node3D, lane_x: float, center_z: float,
		depth: float, height: float) -> void:
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, maxf(height, 0.01), depth)
	block.mesh = box
	block.position = Vector3(lane_x, height * 0.5, center_z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.38, 0.42)
	block.material_override = material
	stage.add_child(block)
