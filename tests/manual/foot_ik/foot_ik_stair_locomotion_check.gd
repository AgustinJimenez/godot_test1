extends RefCounted

const EXPECTED_ANIMATION := &"moves/unarmed_walk"
const STEP_RISE_THRESHOLD := 0.05
const MIN_SPEED_RATIO := 0.8
const POST_STEP_SAMPLE_COUNT := 3
const MIN_FRAME_TRAVEL_RATIO := 0.5
const MAX_CONSECUTIVE_STALL_FRAMES := 1
const MAX_RENDERED_VERTICAL_DELTA := 0.05
const MAX_ASCENT_VISUAL_OFFSET := 0.05
const MAX_SETTLE_DROP := 0.005

var _expected_speed := 0.0
var _expected_steps := 0
var _previous_root_y := 0.0
var _previous_root_xz := Vector2.ZERO
var _previous_rendered_y := 0.0
var _post_step_samples_left := 0
var _step_count := 0
var _sample_count := 0
var _animation_failures := 0
var _speed_failures := 0
var _min_step_speed := INF
var _travel_sample_count := 0
var _stalled_frames := 0
var _consecutive_stalls := 0
var _max_consecutive_stalls := 0
var _vertical_failures := 0
var _max_rendered_vertical_delta := 0.0
var _floating_frames := 0
var _max_ascent_visual_offset := 0.0
var _settling := false
var _settle_samples := 0
var _settle_failures := 0
var _max_settle_drop := 0.0


func reset(player: Player, expected_speed: float, expected_steps: int) -> void:
	_expected_speed = expected_speed
	_expected_steps = expected_steps
	_previous_root_y = player.global_position.y
	_previous_root_xz = Vector2(player.global_position.x, player.global_position.z)
	_previous_rendered_y = player.body.global_position.y
	_post_step_samples_left = 0
	_step_count = 0
	_sample_count = 0
	_animation_failures = 0
	_speed_failures = 0
	_min_step_speed = INF
	_travel_sample_count = 0
	_stalled_frames = 0
	_consecutive_stalls = 0
	_max_consecutive_stalls = 0
	_vertical_failures = 0
	_max_rendered_vertical_delta = 0.0
	_floating_frames = 0
	_max_ascent_visual_offset = 0.0
	_settling = false
	_settle_samples = 0
	_settle_failures = 0
	_max_settle_drop = 0.0


func begin_settle(player: Player) -> void:
	_settling = true
	_previous_root_y = player.global_position.y
	_previous_rendered_y = player.body.global_position.y


func sample(player: Player) -> void:
	var root_y := player.global_position.y
	if _settling:
		var settle_drop := maxf(_previous_root_y - root_y, 0.0)
		_settle_samples += 1
		_max_settle_drop = maxf(_max_settle_drop, settle_drop)
		if settle_drop > MAX_SETTLE_DROP:
			_settle_failures += 1
	var root_xz := Vector2(player.global_position.x, player.global_position.z)
	var frame_travel := root_xz.distance_to(_previous_root_xz)
	_previous_root_xz = root_xz
	_sample_travel_continuity(player, frame_travel)
	_sample_vertical_continuity(player)
	_sample_ascent_float(player)
	if root_y - _previous_root_y > STEP_RISE_THRESHOLD:
		_step_count += 1
		_post_step_samples_left = POST_STEP_SAMPLE_COUNT
	_previous_root_y = root_y
	if _post_step_samples_left <= 0:
		return
	_post_step_samples_left -= 1
	_sample_count += 1
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_min_step_speed = minf(_min_step_speed, horizontal_speed)
	if horizontal_speed < _expected_speed * MIN_SPEED_RATIO:
		_speed_failures += 1
	if player.body.anim_player.current_animation != EXPECTED_ANIMATION:
		_animation_failures += 1


func _sample_travel_continuity(player: Player, frame_travel: float) -> void:
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var walking := player.body.anim_player.current_animation == EXPECTED_ANIMATION
	if not walking or horizontal_speed < _expected_speed * MIN_SPEED_RATIO:
		_consecutive_stalls = 0
		return
	_travel_sample_count += 1
	var minimum_travel := _expected_speed / Engine.physics_ticks_per_second \
			* MIN_FRAME_TRAVEL_RATIO
	if frame_travel < minimum_travel:
		_stalled_frames += 1
		_consecutive_stalls += 1
		_max_consecutive_stalls = maxi(_max_consecutive_stalls, _consecutive_stalls)
	else:
		_consecutive_stalls = 0


func _sample_vertical_continuity(player: Player) -> void:
	var rendered_y := player.body.global_position.y
	var vertical_delta := rendered_y - _previous_rendered_y
	_previous_rendered_y = rendered_y
	if player.body.anim_player.current_animation != EXPECTED_ANIMATION:
		return
	_max_rendered_vertical_delta = maxf(_max_rendered_vertical_delta, vertical_delta)
	if vertical_delta > MAX_RENDERED_VERTICAL_DELTA:
		_vertical_failures += 1


func _sample_ascent_float(player: Player) -> void:
	if player.body.anim_player.current_animation != EXPECTED_ANIMATION:
		return
	var visual_offset := player.body.position.y - player._body_rest_y
	_max_ascent_visual_offset = maxf(_max_ascent_visual_offset, visual_offset)
	if visual_offset > MAX_ASCENT_VISUAL_OFFSET:
		_floating_frames += 1


func format_result() -> String:
	var passed := (_step_count >= _expected_steps and _sample_count > 0
			and _animation_failures == 0 and _speed_failures == 0
			and _max_consecutive_stalls <= MAX_CONSECUTIVE_STALL_FRAMES
			and _vertical_failures == 0 and _floating_frames == 0)
	var min_speed := 0.0 if is_inf(_min_step_speed) else _min_step_speed
	var template := ("FOOT_IK_STAIR_LOCOMOTION_CHECK %s steps=%d samples=%d "
			+ "animation_failures=%d speed_failures=%d "
			+ "min_horizontal_speed=%.3f expected_speed=%.3f "
			+ "travel_samples=%d stalled_frames=%d max_stall_frames=%d "
			+ "vertical_failures=%d max_rendered_dy=%.3f "
			+ "floating_frames=%d max_visual_offset=%.3f")
	return template % [
			"PASS" if passed else "FAIL", _step_count, _sample_count,
			_animation_failures, _speed_failures, min_speed, _expected_speed,
			_travel_sample_count, _stalled_frames, _max_consecutive_stalls,
			_vertical_failures, _max_rendered_vertical_delta,
			_floating_frames, _max_ascent_visual_offset]


func format_settle_result() -> String:
	var passed := _settle_samples > 0 and _settle_failures == 0
	var template := ("FOOT_IK_STAIR_SETTLE_CHECK %s samples=%d failures=%d "
			+ "max_drop_m=%.4f limit_m=%.4f")
	return template % ["PASS" if passed else "FAIL", _settle_samples,
			_settle_failures, _max_settle_drop, MAX_SETTLE_DROP]
