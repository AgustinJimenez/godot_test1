class_name PlayerStairController
extends RefCounted
## Stateful stair traversal helper for the real Player CharacterBody3D.
## It probes and applies stair transitions on that body; it is not a second
## physics node and does not own ordinary move_and_slide() movement.

const TREAD_PROBE_FORWARD := 0.04
const TREAD_NORMAL_MIN_DOT := 0.9
const REPEAT_CONTACT_DISTANCE := 1.0

var hover_offset_y := 0.0
var consumed_horizontal_motion := false

var _host: CharacterBody3D
var _body: Node3D
var _third_person_arm: Node3D
var _body_rest_y := 0.0
var _third_person_arm_rest_y := 0.0
var _climb_target_y := -INF
var _climb_active := false
var _last_tread_y := -INF
var _last_contact := Vector3(INF, INF, INF)
var _pending_step_down_y := -INF


func setup(host: CharacterBody3D, body: Node3D, third_person_arm: Node3D) -> void:
	_host = host
	_body = body
	_third_person_arm = third_person_arm
	_body_rest_y = body.position.y
	_third_person_arm_rest_y = third_person_arm.position.y


func begin_frame() -> void:
	consumed_horizontal_motion = false


func is_climbing() -> bool:
	return _climb_active


func get_body_rest_y() -> float:
	return _body_rest_y


func apply_step_up(motion: Vector3, delta: float, step_height: float,
		step_rise_rate: float) -> float:
	if _climb_active:
		return _continue_step_climb(motion, delta, step_rise_rate)
	# Do not gate on is_on_floor(): touching the riser can unset it briefly.
	var tread: Dictionary = {}
	if not motion.is_zero_approx():
		var wall_collision := KinematicCollision3D.new()
		if _host.test_move(_host.global_transform, motion, wall_collision):
			var lifted := _host.global_transform.translated(
					Vector3(0.0, step_height, 0.0))
			if not _host.test_move(lifted, motion):
				tread = _find_step_up_tread(motion, wall_collision, step_height)
				if not tread.is_empty():
					lifted.origin.y = _host.global_position.y + tread["rise"]
					if _host.test_move(lifted, motion):
						tread = {}
	if not tread.is_empty():
		_last_tread_y = tread["y"]
		_last_contact = tread["contact"]
		_climb_target_y = _host.global_position.y + tread["rise"]
		_climb_active = true
		return _continue_step_climb(motion, delta, step_rise_rate)
	return 0.0


func _continue_step_climb(motion: Vector3, delta: float, step_rise_rate: float) -> float:
	var previous_y := _host.global_position.y
	var rise := move_toward(previous_y, _climb_target_y, step_rise_rate * delta) - previous_y
	if _host.test_move(_host.global_transform, Vector3(0.0, rise, 0.0)):
		_climb_active = false
		_climb_target_y = -INF
		return 0.0
	var next_position := _host.global_position
	next_position.y += rise
	_host.global_position = next_position
	consumed_horizontal_motion = true
	_host.velocity = Vector3.ZERO
	# Always applied: gating horizontal travel at each partial height caused
	# one-to-two stationary frames followed by a visible catch-up jump.
	_host.global_position += motion
	if is_equal_approx(_host.global_position.y, _climb_target_y):
		_climb_active = false
		_climb_target_y = -INF
		_host.apply_floor_snap()
	return maxf(_host.global_position.y - previous_y, 0.0)


func _find_step_up_tread(motion: Vector3, wall_collision: KinematicCollision3D,
		step_height: float) -> Dictionary:
	var direction := motion.normalized()
	var contact := wall_collision.get_position()
	var probe_xz := contact + direction * TREAD_PROBE_FORWARD
	var margin := _host.safe_margin
	var probe_from := Vector3(
			probe_xz.x, _host.global_position.y + step_height + margin, probe_xz.z)
	var probe_to := Vector3(
			probe_xz.x, _host.global_position.y + margin, probe_xz.z)
	var query := PhysicsRayQueryParameters3D.create(
			probe_from, probe_to, _host.collision_mask)
	query.exclude = [_host.get_rid()]
	var hit := _host.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	# Compare floor surfaces instead of assigning the tread height directly;
	# the CharacterBody origin is not necessarily at its collider sole.
	var floor_from := _host.global_position + Vector3.UP * (step_height + margin)
	var floor_to := _host.global_position - Vector3.UP * (step_height + margin)
	var floor_query := PhysicsRayQueryParameters3D.create(
			floor_from, floor_to, _host.collision_mask)
	floor_query.exclude = [_host.get_rid()]
	var current_floor := _host.get_world_3d().direct_space_state.intersect_ray(floor_query)
	if current_floor.is_empty():
		return {}
	var tread_normal: Vector3 = hit["normal"]
	var tread_y: float = hit["position"].y
	var current_floor_y: float = current_floor["position"].y
	var rise := tread_y - current_floor_y
	if tread_normal.dot(Vector3.UP) < TREAD_NORMAL_MIN_DOT:
		return {}
	var repeated_contact := Vector2(probe_xz.x, probe_xz.z).distance_to(
			Vector2(_last_contact.x, _last_contact.z))
	if (is_equal_approx(tread_y, _last_tread_y)
			and repeated_contact < REPEAT_CONTACT_DISTANCE):
		return {}
	if rise <= margin or rise > step_height + margin:
		return {}
	return {"y": tread_y, "rise": rise, "contact": probe_xz}


func apply_step_down(motion: Vector3, step_height: float,
		jump_velocity_threshold: float) -> float:
	if motion.is_zero_approx() or _host.velocity.y > jump_velocity_threshold:
		_pending_step_down_y = -INF
		return 0.0
	if not is_finite(_pending_step_down_y):
		var tread := _find_step_down_tread(motion, step_height)
		if tread.is_empty():
			return 0.0
		_pending_step_down_y = tread["y"]
	var remaining_drop := _host.global_position.y - _pending_step_down_y
	if remaining_drop <= _host.safe_margin:
		_pending_step_down_y = -INF
		return 0.0
	# Move horizontally first, then sweep the capsule down while retaining
	# the lower tread until the rounded heel clears the old edge.
	var moved := _host.global_transform
	moved.origin += motion
	var collision := KinematicCollision3D.new()
	if not _host.test_move(
			moved, Vector3.DOWN * (remaining_drop + _host.safe_margin), collision):
		return 0.0
	moved.origin += collision.get_travel()
	var previous_y := _host.global_position.y
	_host.global_transform = moved
	_host.velocity.y = 0.0
	consumed_horizontal_motion = true
	_host.apply_floor_snap()
	if _host.global_position.y <= _pending_step_down_y + 0.06:
		_pending_step_down_y = -INF
	return maxf(previous_y - _host.global_position.y, 0.0)


func _find_step_down_tread(motion: Vector3, step_height: float) -> Dictionary:
	var probe_height := step_height + _host.safe_margin + 0.05
	var current_query := PhysicsRayQueryParameters3D.create(
			_host.global_position + Vector3.UP * probe_height,
			_host.global_position - Vector3.UP * probe_height, _host.collision_mask)
	current_query.exclude = [_host.get_rid()]
	var next_position := _host.global_position + motion
	var next_query := PhysicsRayQueryParameters3D.create(
			next_position + Vector3.UP * probe_height,
			next_position - Vector3.UP * probe_height, _host.collision_mask)
	next_query.exclude = [_host.get_rid()]
	var space := _host.get_world_3d().direct_space_state
	var current_floor := space.intersect_ray(current_query)
	var next_floor := space.intersect_ray(next_query)
	if current_floor.is_empty() or next_floor.is_empty():
		return {}
	var current_normal: Vector3 = current_floor["normal"]
	var next_normal: Vector3 = next_floor["normal"]
	if (current_normal.dot(Vector3.UP) < TREAD_NORMAL_MIN_DOT
			or next_normal.dot(Vector3.UP) < TREAD_NORMAL_MIN_DOT):
		return {}
	var drop: float = current_floor["position"].y - next_floor["position"].y
	if drop <= _host.safe_margin or drop > step_height + _host.safe_margin:
		return {}
	return {"y": next_floor["position"].y}


func is_short_step_down(frame_start_y: float, horizontal_motion: Vector3,
		step_height: float, jump_velocity_threshold: float) -> bool:
	var drop := frame_start_y - _host.global_position.y
	return (
			not horizontal_motion.is_zero_approx()
			and _host.is_on_floor()
			and _host.get_floor_normal().dot(Vector3.UP) > 0.99
			and drop > 0.001
			and drop <= step_height + 0.01
			and _host.velocity.y <= jump_velocity_threshold)


func record_presentation_delta(delta_y: float, step_height: float) -> void:
	hover_offset_y = clampf(hover_offset_y + delta_y, -step_height, step_height)


func update_presentation(delta: float, hover_speed: float) -> void:
	var blend := 1.0 - exp(-hover_speed * delta)
	hover_offset_y = lerpf(hover_offset_y, 0.0, blend)
	if is_instance_valid(_body):
		_body.position.y = _body_rest_y
	if is_instance_valid(_third_person_arm):
		_third_person_arm.position.y = _third_person_arm_rest_y + hover_offset_y


func reset() -> void:
	hover_offset_y = 0.0
	_climb_target_y = -INF
	_climb_active = false
	_last_tread_y = -INF
	_last_contact = Vector3(INF, INF, INF)
	_pending_step_down_y = -INF
	consumed_horizontal_motion = false
	if is_instance_valid(_body):
		_body.position.y = _body_rest_y
	if is_instance_valid(_third_person_arm):
		_third_person_arm.position.y = _third_person_arm_rest_y
