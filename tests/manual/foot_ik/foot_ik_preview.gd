extends Node3D # static scene, idle characters on flat/ramp/stair platforms side by side
const PLATFORM_WIDTH := 3.0
const PLATFORM_LENGTH := 4.0
const PLATFORM_THICKNESS := 0.3
const PLATFORM_SPACING := 2.5
const STAIR_STEP_COUNT := 6
const STAIR_TREAD_DEPTH := 0.6
const STAIR_IDLE_SECONDS := 5.0
const STAIR_START_BACKOFF := 0.8
const STAIR_LEAD_FOOT_REACH := 0.2
const STAIR_LANDING_Y_TOLERANCE := 0.08
const STAIR_SLOW_MOTION_SCALE := 0.6 # interactive walkers; automated check forces 100%
const STAIR_WALK_ANIMATION_SPEED := 3.2
const STAIR_WALK_SPEED := STAIR_WALK_ANIMATION_SPEED * STAIR_SLOW_MOTION_SCALE
const FOOT_TRACE_STAIR_HEIGHT := 0.35
const FOOT_CONTACT_DISTANCE := 0.03
const HIP_SKIN_STRETCH_LIMIT := 0.005
const BODY_STAIR_PENETRATION_TOLERANCE := 0.005
const FOOTSTEP_MARKER_LIFETIME := 10.0
const FOOT_TRACE_FILE := "user://foot_ik_trace.jsonl"
const INSPECTION_YAWS: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
const INSPECTION_ANGLE_HOLD_TIME := 1.25 # 4 angles × 1.25s = 5.0s total idle ( STAIR_IDLE_SECONDS)
const STAIR_WALK_TEST_SPAWN := Vector3(6 * PLATFORM_SPACING, 0.05, -STAIR_START_BACKOFF)
const STAIR_WALK_TEST_ROTATION := Vector3(0.0, PI, 0.0)
const FLAT_FORWARD_TEST_SPAWN := Vector3(-40.0, 0.05, -40.0)
const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const FOOT_BONE_DEBUG_SHADER := preload(
		"res://tests/manual/foot_ik/foot_bone_debug.gdshader")

const PLATFORM_MATERIAL_COLOR := Color(0.32, 0.34, 0.38)
const STAIR_TREAD_DEBUG_COLOR := Color(0.85, 0.08, 0.06)
const STAIR_RISER_DEBUG_COLOR := Color(0.05, 0.18, 0.9)
const STAIR_TREAD_DEBUG_THICKNESS := 0.006

const CASES: Array[Dictionary] = [
	{"label": "Flat", "kind": &"flat"},
	{"label": "Ramp 15°", "kind": &"ramp", "angle_deg": 15.0},
	{"label": "Ramp 30°", "kind": &"ramp", "angle_deg": 30.0},
	{"label": "Ramp 45°", "kind": &"ramp", "angle_deg": 45.0},
	{"label": "Stairs 0.10m", "kind": &"stairs", "step_height": 0.1},
	{"label": "Stairs 0.20m", "kind": &"stairs", "step_height": 0.2},
	{"label": "Stairs 0.35m", "kind": &"stairs", "step_height": 0.35},
	{"label": "Stairs 0.50m", "kind": &"stairs", "step_height": 0.5},
	{"label": "Stairs 0.65m", "kind": &"stairs", "step_height": 0.65},
]

var _platform_material: StandardMaterial3D
var _stair_tread_debug_material: StandardMaterial3D
var _stair_riser_debug_material: StandardMaterial3D
var _stair_walkers: Array[Dictionary] = []
var _prediction_ik: PlayerFootIKModifier
var _prediction_player: Player
var _prediction_markers: Dictionary = {}
var _trace_probes: Dictionary = {}
var _contact_ray_meshes: Dictionary = {}
var _contact_hit_markers: Dictionary = {}
var _contact_materials: Dictionary = {}
var _contact_debug_state: Dictionary = {}
var _stretch_check_samples := 0
var _stretch_check_max_error := 0.0
var _stretch_check_failed := false
var _automated_stretch_check := "--foot-ik-check" in OS.get_cmdline_user_args()
var _use_native_backend := "--native-foot-ik" in OS.get_cmdline_user_args()
var _automated_check_frame := 0
var _airborne_check_samples := 0
var _airborne_check_failed := false
var _airborne_check_started := false
var _airborne_check_complete := false
var _automated_jump_launched := false
var _body_penetration_samples := 0
var _body_penetration_attempts := 0
var _body_penetration_unavailable := 0
var _body_penetration_missing_mesh := 0
var _body_penetrating_samples := 0
var _body_penetrating_vertices := 0
var _body_penetration_max_depth := 0.0
var _pose_continuity_check := preload(
		"res://tests/manual/foot_ik/foot_ik_pose_continuity_check.gd").new()
var _stair_locomotion_check := preload(
		"res://tests/manual/foot_ik/foot_ik_stair_locomotion_check.gd").new()
var _walk_continuity_check := preload(
		"res://tests/manual/foot_ik/foot_ik_walk_continuity_check.gd").new()
var _automated_walk_check := "--foot-ik-walk-check" in OS.get_cmdline_user_args()
## Lets interactive play write STAIR_FOOT_TRACE - bounded, not print/append.
var _stair_trace_marker := FileAccess.file_exists("user://foot_ik_stair_trace_marker")
var _stair_trace_buffer: Array[String] = []
const STAIR_TRACE_LIVE_FILE := "user://foot_ik_stair_trace_live.jsonl"
const STAIR_TRACE_MAX_FRAMES := 1200 # 20s at 60fps

func _ready() -> void:
	FileAccess.open(FOOT_TRACE_FILE, FileAccess.WRITE).close()
	_platform_material = StandardMaterial3D.new()
	_platform_material.albedo_color = PLATFORM_MATERIAL_COLOR
	_stair_tread_debug_material = StandardMaterial3D.new()
	_stair_tread_debug_material.albedo_color = STAIR_TREAD_DEBUG_COLOR
	_stair_riser_debug_material = StandardMaterial3D.new()
	_stair_riser_debug_material.albedo_color = STAIR_RISER_DEBUG_COLOR

	for i in CASES.size():
		var case: Dictionary = CASES[i]
		var origin := Vector3(i * PLATFORM_SPACING, 0.0, 0.0)
		var contact := _build_platform(case, origin)
		if case["kind"] == &"stairs":
			_place_stair_walker(origin, contact, case["step_height"])
		else:
			_place_character(contact, 0.0)
		_build_label(case["label"], origin)

	if _automated_stretch_check:
		for walker: Dictionary in _stair_walkers:
			if walker["trace_enabled"]:
				_start_stair_walker(walker)
				break
	$Player.global_position = Vector3(7.7, 0.95, 0.9) # bottom edge of Ramp 45, confirmed repro spot
	$Player.rotation = Vector3.ZERO
	if FileAccess.file_exists("user://foot_ik_walk_marker"): # sprint loop-reset snap repro spot
		$Player.global_position = Vector3(16.85, 0.0009, -1.69)
		$Player.rotation = Vector3(0.0, deg_to_rad(92.3), 0.0)
	if _diagonal_walk_marker: # flat spot above, moved 40m forward, on the enlarged floor
		var rot := deg_to_rad(92.3)
		$Player.global_position = Vector3(16.85, 0.0009, -1.69) \
				+ Vector3.FORWARD.rotated(Vector3.UP, rot) * 40.0
		$Player.rotation = Vector3(0.0, rot, 0.0)
	if _stair_walk_marker:
		$Player.global_position = STAIR_WALK_TEST_SPAWN
		$Player.rotation = STAIR_WALK_TEST_ROTATION
	if _flat_forward_marker:
		$Player.global_position = FLAT_FORWARD_TEST_SPAWN
		$Player.rotation = Vector3.ZERO
	$Player.debug_cam.current = true # ThirdPersonArm, not the free-fly noclip detached_cam
	$Player._debug_cam_active = true
	for child in $Player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			if _flat_forward_marker:
				child.reset_runtime_state()
			child.foot_landed.connect(_on_foot_landed.bind($Player))
			if FileAccess.file_exists("user://foot_ik_disabled_marker"):
				child.set_debug_enabled(false) # A/B baseline: keep grounded updates from re-enabling IK
			break

## Marker-file toggle - play_scene_in_editor() (MCP) can't be given fresh cmdline args.
var _auto_spin := FileAccess.file_exists("user://foot_ik_spin_marker")
var _auto_walk := FileAccess.file_exists("user://foot_ik_walk_marker") # oscillates forward/back
var _stair_walk_marker := FileAccess.file_exists("user://foot_ik_stair_walk_marker")
var _diagonal_walk_marker := FileAccess.file_exists("user://foot_ik_diagonal_walk_marker")
var _flat_forward_marker := FileAccess.file_exists("user://foot_ik_flat_forward_marker")
var _diagonal_walk_dir := Vector2(1.0, -1.0).normalized() # 45deg forward-right
## A fast swipe is a burst - most rotation lands in one or two frames, then holds.
const BURST_DEGREES := 70.0
const BURST_TIME := 0.1 # seconds to cover BURST_DEGREES
const BURST_PAUSE := 2.0
var _burst_elapsed := 0.0
const WALK_LEG_TIME := 3.0 # seconds per forward/back leg, stays on the platform
var _walk_elapsed := 0.0

func _physics_process(delta: float) -> void:
	if _auto_spin:
		$Player.movement_input_override = Vector2.ZERO
		_burst_elapsed += delta
		var cycle := fmod(_burst_elapsed, BURST_TIME + BURST_PAUSE)
		if cycle < BURST_TIME:
			$Player.rotation.y += deg_to_rad(BURST_DEGREES / BURST_TIME) * delta
	if _auto_walk or _diagonal_walk_marker:
		_walk_elapsed += delta
		var leg_time := 2.4 if _diagonal_walk_marker else WALK_LEG_TIME # bigger floor now
		var leg := fmod(_walk_elapsed, leg_time * 2.0)
		var dir := _diagonal_walk_dir if _diagonal_walk_marker else Vector2(0.0, -1.0)
		$Player.movement_input_override = dir if leg < leg_time else -dir
	if _stair_walk_marker:
		$Player.movement_input_override = Vector2(0.0, -1.0)
		if $Player.global_position.z >= 6 * STAIR_TREAD_DEPTH - 0.25: # matches walker top_z
			$Player.global_position = STAIR_WALK_TEST_SPAWN
			$Player.rotation = STAIR_WALK_TEST_ROTATION
			$Player.velocity = Vector3.ZERO
			$Player._reset_stair_hover()
	if _flat_forward_marker:
		$Player.movement_input_override = Vector2(0.0, -1.0)
	if _automated_stretch_check:
		_automated_check_frame += 1
		if (not _automated_jump_launched and _automated_check_frame >= 10
				and $Player.is_on_floor()):
			$Player.velocity.y = $Player.jump_velocity
			_automated_jump_launched = true
		call_deferred(&"_sample_airborne_ik_release")
		call_deferred(&"_sample_controlled_continuity", $Player, _pose_continuity_check)
		_pose_continuity_check.maybe_rotate($Player, delta, INSPECTION_YAWS)
	if _automated_walk_check:
		_walk_continuity_check.drive($Player, delta)
		call_deferred(&"_sample_controlled_continuity", $Player, _walk_continuity_check)
	for walker: Dictionary in _stair_walkers:
		var player: Player = walker["player"]
		if walker["walking"]:
			if walker["trace_enabled"]: # 0.35m uses Player's real stair solver
				_update_physical_walker_tread(walker)
			else:
				_advance_stair_walker(walker, delta)
			if walker["trace_enabled"] and ((_automated_stretch_check
					and not walker["trace_complete"]) or _stair_trace_marker):
				call_deferred(&"_log_stair_foot_frame", walker)
			if player.global_position.z >= walker["top_z"]:
				_reset_stair_walker(walker)
			continue
		walker["timer"] = float(walker["timer"]) - delta
		if walker["timer"] <= 0.0:
			var next_angle := int(walker["inspection_angle"]) + 1
			if next_angle < INSPECTION_YAWS.size():
				walker["inspection_angle"] = next_angle
				player.rotation = Vector3(0.0, INSPECTION_YAWS[next_angle], 0.0)
				walker["timer"] = INSPECTION_ANGLE_HOLD_TIME
			else:
				_start_stair_walker(walker)
	call_deferred(&"_update_step_prediction_markers")

func _exit_tree() -> void:
	if _automated_walk_check:
		print(_walk_continuity_check.format_result())
	if _stretch_check_samples == 0:
		return
	var result := "FAIL" if _stretch_check_failed else "PASS"
	print("FOOT_IK_STRETCH_CHECK ", result,
			" samples=", _stretch_check_samples,
			" max_error_m=", snappedf(_stretch_check_max_error, 0.000001),
			" limit_m=", HIP_SKIN_STRETCH_LIMIT)
	var airborne_result := (
			"FAIL" if _airborne_check_failed or _airborne_check_samples == 0 else "PASS")
	print("FOOT_IK_AIRBORNE_CHECK ", airborne_result,
			" samples=", _airborne_check_samples)
	var penetration_result := "FAIL" if _body_penetrating_samples > 0 else "PASS"
	print("FOOT_IK_BODY_PENETRATION_CHECK ", penetration_result,
			" samples=", _body_penetration_samples,
			" attempts=", _body_penetration_attempts,
			" unavailable=", _body_penetration_unavailable,
			" missing_mesh=", _body_penetration_missing_mesh,
			" penetrating_samples=", _body_penetrating_samples,
			" penetrating_vertices=", _body_penetrating_vertices,
			" max_depth_m=", snappedf(_body_penetration_max_depth, 0.000001),
			" tolerance_m=", BODY_STAIR_PENETRATION_TOLERANCE)
	print(_pose_continuity_check.format_result())
	print(_stair_locomotion_check.format_result())

func _sample_controlled_continuity(player: Player, check: RefCounted) -> void:
	var ik := _find_foot_ik(player)
	if ik != null:
		check.sample(player, ik)

func _sample_airborne_ik_release() -> void:
	var player := $Player as Player
	if _airborne_check_complete:
		return
	if not _airborne_check_started:
		if player.velocity.y <= 1.0:
			return
		_airborne_check_started = true
	if player.is_on_floor():
		_airborne_check_complete = _airborne_check_samples > 0
		return
	var ik := _find_foot_ik(player)
	if ik == null:
		_airborne_check_failed = true
		return
	_airborne_check_samples += 1
	if ik.active:
		_airborne_check_failed = true

# Bone origins alone can't prove skin is clear - weighted regions can cross.
func _sample_body_stair_penetration(walker: Dictionary) -> Dictionary:
	_body_penetration_attempts += 1
	if not walker["walking"]:
		_body_penetration_unavailable += 1
		return {"available": false}
	var player := walker["player"] as Player
	var mesh_nodes := player.body.character.find_children(
			"*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		_body_penetration_unavailable += 1
		_body_penetration_missing_mesh += 1
		return {"available": false}
	var skeleton := player.skeleton
	if skeleton == null:
		_body_penetration_unavailable += 1
		return {"available": false}
	var ik := _find_foot_ik(player)
	if ik == null:
		_body_penetration_unavailable += 1
		return {"available": false}
	_body_penetration_samples += 1
	var sample_vertices := 0
	var sample_max_depth := 0.0
	var penetrating_bones: Dictionary = {}
	for mesh_node: Node in mesh_nodes:
		var mesh_part := mesh_node as MeshInstance3D
		if mesh_part.mesh == null:
			continue
		var bind_transforms := _mesh_bind_transforms(mesh_part, skeleton, ik)
		var bind_bone_names := _mesh_bind_bone_names(mesh_part, skeleton)
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := (
					arrays[Mesh.ARRAY_BONES] as PackedInt32Array
					if arrays[Mesh.ARRAY_BONES] is PackedInt32Array else PackedInt32Array())
			var weights := (
					arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
					if arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array else PackedFloat32Array())
			var influences_per_vertex := (
					bones.size() / vertices.size() if not vertices.is_empty() else 0)
			for vertex_index in vertices.size():
				var world_vertex := mesh_part.global_transform * vertices[vertex_index]
				if influences_per_vertex > 0 and not weights.is_empty():
					world_vertex = _skin_vertex(
							vertex_index, vertices, bones, weights, bind_transforms, world_vertex)
				var depth := _stair_penetration_depth(world_vertex, walker)
				if depth <= BODY_STAIR_PENETRATION_TOLERANCE:
					continue
				sample_vertices += 1
				sample_max_depth = maxf(sample_max_depth, depth)
				var dominant_bone := _dominant_skin_bone(
						vertex_index, vertices, bones, weights, bind_bone_names)
				penetrating_bones[dominant_bone] = int(
						penetrating_bones.get(dominant_bone, 0)) + 1
	if sample_vertices == 0:
		return {"available": true, "vertices": 0, "max_depth": 0.0, "bones": {}}
	_body_penetrating_samples += 1
	_body_penetrating_vertices += sample_vertices
	_body_penetration_max_depth = maxf(_body_penetration_max_depth, sample_max_depth)
	return {"available": true, "vertices": sample_vertices,
			"max_depth": sample_max_depth, "bones": penetrating_bones}

func _mesh_bind_transforms(mesh_part: MeshInstance3D, skeleton: Skeleton3D,
		ik: PlayerFootIKModifier) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var skin_reference := mesh_part.get_skin_reference()
	if skin_reference == null:
		return result
	var skin := skin_reference.get_skin()
	if skin == null:
		return result
	result.resize(skin.get_bind_count())
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = skeleton.find_bone(skin.get_bind_name(bind_index))
		if bone_index < 0:
			result[bind_index] = Transform3D.IDENTITY
			continue
		var pose: Transform3D = skeleton.get_bone_global_pose(bone_index)
		if ik._final_bone_poses.has(bone_index):
			pose = ik._final_bone_poses[bone_index]
		result[bind_index] = skeleton.global_transform * pose * skin.get_bind_pose(bind_index)
	return result

func _mesh_bind_bone_names(
		mesh_part: MeshInstance3D, skeleton: Skeleton3D) -> Array[StringName]:
	var result: Array[StringName] = []
	var skin_reference := mesh_part.get_skin_reference()
	if skin_reference == null or skin_reference.get_skin() == null:
		return result
	var skin := skin_reference.get_skin()
	result.resize(skin.get_bind_count())
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = skeleton.find_bone(skin.get_bind_name(bind_index))
		result[bind_index] = skeleton.get_bone_name(bone_index) if bone_index >= 0 else &"unknown"
	return result

func _dominant_skin_bone(vertex_index: int, vertices: PackedVector3Array,
		bones: PackedInt32Array, weights: PackedFloat32Array,
		bind_bone_names: Array[StringName]) -> StringName:
	if vertices.is_empty() or bones.is_empty() or weights.is_empty():
		return &"unskinned"
	var influences_per_vertex := bones.size() / vertices.size()
	var best_weight := -1.0
	var best_bind := -1
	for influence in influences_per_vertex:
		var array_index := vertex_index * influences_per_vertex + influence
		if weights[array_index] > best_weight:
			best_weight = weights[array_index]
			best_bind = bones[array_index]
	return (bind_bone_names[best_bind]
			if best_bind >= 0 and best_bind < bind_bone_names.size() else &"unknown")

func _skin_vertex(vertex_index: int, vertices: PackedVector3Array,
		bones: PackedInt32Array, weights: PackedFloat32Array,
		bind_transforms: Array[Transform3D], fallback: Vector3) -> Vector3:
	var influences_per_vertex := bones.size() / vertices.size()
	var result := Vector3.ZERO
	var total_weight := 0.0
	for influence in influences_per_vertex:
		var array_index := vertex_index * influences_per_vertex + influence
		var weight: float = weights[array_index]
		var bind_index: int = bones[array_index]
		if weight <= 0.0 or bind_index < 0 or bind_index >= bind_transforms.size():
			continue
		result += (bind_transforms[bind_index] * vertices[vertex_index]) * weight
		total_weight += weight
	return result / total_weight if total_weight > 0.0 else fallback

func _stair_penetration_depth(point: Vector3, walker: Dictionary) -> float:
	var origin_x: float = (walker["start_position"] as Vector3).x
	if absf(point.x - origin_x) >= PLATFORM_WIDTH * 0.5:
		return 0.0
	var relative_z := point.z - float(walker["origin_z"])
	var step_index := floori(relative_z / STAIR_TREAD_DEPTH)
	if step_index < 0 or step_index >= STAIR_STEP_COUNT:
		return 0.0
	var bottom_y := float(walker["origin_y"])
	var top_y := bottom_y + float(walker["stair_height"]) * (step_index + 1)
	if point.y <= bottom_y or point.y >= top_y:
		return 0.0
	return top_y - point.y

func _place_stair_walker(origin: Vector3, contact: Vector3, stair_height: float) -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	var trace_enabled := is_equal_approx(stair_height, FOOT_TRACE_STAIR_HEIGHT)
	var playback_scale := 1.0 if _automated_stretch_check else STAIR_SLOW_MOTION_SCALE
	var physical_speed := STAIR_WALK_ANIMATION_SPEED * playback_scale
	player.movement_input_override = Vector2.ZERO
	player.gameplay_action_input_enabled = false
	player.walk_speed = physical_speed
	player.step_height = maxf(player.step_height, stair_height + 0.05)
	player.add_to_group(&"foot_ik_stair_walkers")
	player.set_meta(&"stair_height", stair_height)
	add_child(player)
	player.camera.current = false
	player.debug_cam.current = false
	player.detached_cam.current = false
	player.hud.visible = false
	player.hud.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	_apply_stair_foot_debug_material(player)
	for child in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			# Custom is the gameplay default; native TwoBoneIK3D is opt-in.
			if _use_native_backend:
				child.set_solver_backend(PlayerFootIKModifier.SolverBackend.NATIVE_TWO_BONE)
			child.ray_up = maxf(child.ray_up, stair_height + 0.2)
			child.ray_down = maxf(child.ray_down, stair_height + 0.2)
			child.foot_landed.connect(_on_foot_landed.bind(player))
			if trace_enabled:
				_prediction_ik = child
				_prediction_player = player
				_build_step_prediction_markers()
				_build_foot_trace_probes(player, child)
				_build_foot_contact_visuals()
	var walker := {
		"player": player,
		"idle_position": contact,
		"start_position": origin + Vector3(0.0, 0.05, -STAIR_START_BACKOFF),
		"origin_z": origin.z,
		"origin_y": origin.y,
		"stair_height": stair_height,
		"playback_scale": playback_scale,
		"physical_speed": physical_speed,
		"trace_enabled": trace_enabled,
		"trace_complete": false,
		"trace_frame": 0,
		"current_tread": -1,
		"waiting_for_step": false,
		"top_z": origin.z + STAIR_STEP_COUNT * STAIR_TREAD_DEPTH - 0.25,
		"inspection_angle": 0,
		"timer": INSPECTION_ANGLE_HOLD_TIME,
		"walking": false,
	}
	_stair_walkers.append(walker)
	_reset_stair_walker(walker)

func _apply_stair_foot_debug_material(player: Player) -> void:
	var material := ShaderMaterial.new()
	material.shader = FOOT_BONE_DEBUG_SHADER
	for role: StringName in [&"LeftFoot", &"LeftToeBase", &"RightFoot", &"RightToeBase"]:
		var bone_name := player.body.resolve_bone_name(role)
		var bone_index := player.skeleton.find_bone(bone_name)
		material.set_shader_parameter(_foot_debug_uniform(role), bone_index)
	player.body.mesh.material_overlay = material

func _foot_debug_uniform(role: StringName) -> StringName:
	match role:
		&"LeftFoot":
			return &"left_foot_bone"
		&"LeftToeBase":
			return &"left_toe_bone"
		&"RightFoot":
			return &"right_foot_bone"
		_:
			return &"right_toe_bone"

func _reset_stair_walker(walker: Dictionary) -> void:
	var player: Player = walker["player"]
	if int(walker["trace_frame"]) > 0:
		walker["trace_complete"] = true
	player.set_physics_process(false) # freeze so depenetration doesn't shift hips while IK plants
	player.movement_input_override = Vector2.ZERO
	player.global_position = walker["idle_position"]
	walker["inspection_angle"] = 0
	player.rotation = Vector3(0.0, INSPECTION_YAWS[0], 0.0)
	player.velocity = Vector3.ZERO
	player._reset_stair_hover()
	var ik := _find_foot_ik(player)
	if ik != null:
		ik.reset_runtime_state()
		ik.force_plant_mode = true
	player.body.locomotion_playback_scale = 1.0
	player.body.update_motion(false, false, 0.0, false, true, 0.0, 0.0, false)
	walker["current_tread"] = -1
	walker["waiting_for_step"] = false
	walker["timer"] = INSPECTION_ANGLE_HOLD_TIME
	walker["walking"] = false

func _start_stair_walker(walker: Dictionary) -> void:
	var player: Player = walker["player"]
	player.global_position = walker["start_position"]
	player.rotation = Vector3(0.0, PI, 0.0)
	player.velocity = Vector3.ZERO
	player._reset_stair_hover()
	var ik := _find_foot_ik(player)
	if ik != null:
		ik.reset_runtime_state()
		ik.force_plant_mode = false
	player.body.locomotion_playback_scale = float(walker["playback_scale"])
	player.movement_input_override = Vector2(0.0, -1.0)
	player.body.update_motion(false, false, float(walker["physical_speed"]),
			false, true, 0.0, 0.0, false)
	if _automated_stretch_check and walker["trace_enabled"]:
		_stair_locomotion_check.reset(
				player, float(walker["physical_speed"]), STAIR_STEP_COUNT)
	player.set_physics_process(bool(walker["trace_enabled"])) # only 0.35m uses live physics
	walker["walking"] = true
	walker["trace_frame"] = 0
	walker["trace_complete"] = false
	walker["current_tread"] = -1
	walker["waiting_for_step"] = false

func _update_physical_walker_tread(walker: Dictionary) -> void:
	var player := walker["player"] as Player
	var risen := player.global_position.y - float(walker["origin_y"]) - 0.05
	walker["current_tread"] = clampi(
			roundi(risen / float(walker["stair_height"])) - 1,
			-1, STAIR_STEP_COUNT - 1)
	walker["waiting_for_step"] = false

func _advance_stair_walker(walker: Dictionary, delta: float) -> void: # 0.50/0.65m = pose limits
	var player: Player = walker["player"]
	var next_position := player.global_position
	var next_tread := int(walker["current_tread"]) + 1
	if next_tread < STAIR_STEP_COUNT:
		var boundary_z: float = float(walker["origin_z"]) + next_tread * STAIR_TREAD_DEPTH
		var approach_z := boundary_z + STAIR_LEAD_FOOT_REACH
		next_position.z = minf(
				next_position.z + float(walker["physical_speed"]) * delta, approach_z)
		walker["waiting_for_step"] = is_equal_approx(next_position.z, approach_z)
	else:
		next_position.z += float(walker["physical_speed"]) * delta
	player.global_position = next_position
	player._update_stair_hover(delta)

func _log_stair_foot_frame(walker: Dictionary) -> void:
	if not walker["walking"]:
		return
	# Deferred so the ray and trace sample the same final rendered foot pose.
	_update_foot_contact_rays()
	var player: Player = walker["player"]
	var ik := _find_foot_ik(player)
	if ik == null:
		return
	if _automated_stretch_check:
		_stair_locomotion_check.sample(player)
	walker["trace_frame"] = int(walker["trace_frame"]) + 1
	var trace := {
		"frame": walker["trace_frame"],
		"solver_backend": PlayerFootIKModifier.SolverBackend.keys()[ik.solver_backend],
		"physics_frame": Engine.get_physics_frames(),
		"animation": player.body.anim_player.current_animation,
		"animation_time": player.body.anim_player.current_animation_position,
		"horizontal_speed": Vector2(player.velocity.x, player.velocity.z).length(),
		"root": _vector_to_array(player.global_position),
		"body_y": player.body.position.y,
		"body_world_y": player.body.global_position.y,
		"head_world_y": player.head.global_position.y,
		"stair_hover_offset_y": player._stair_hover_offset_y,
		"current_tread": walker["current_tread"],
		"waiting_for_step": walker["waiting_for_step"],
		"forced_support": str(ik._forced_support_side),
		"feet": {},
		"hip_skin_stretch": _sample_hip_skin_stretch(player, ik),
	}
	for side: StringName in [&"left", &"right"]:
		trace["feet"][side] = _foot_trace_sample(walker, ik, side)
	if _automated_stretch_check:
		trace["body_penetration"] = _sample_body_stair_penetration(walker)
	var trace_json := JSON.stringify(trace)
	if _automated_stretch_check:
		print("STAIR_FOOT_TRACE ", trace_json)
		var trace_file := FileAccess.open(FOOT_TRACE_FILE, FileAccess.READ_WRITE)
		trace_file.seek_end()
		trace_file.store_line(trace_json)
		trace_file.close()
	if _stair_trace_marker:
		_stair_trace_buffer.append(trace_json)
		if _stair_trace_buffer.size() > STAIR_TRACE_MAX_FRAMES:
			_stair_trace_buffer.pop_front()
		var live_file := FileAccess.open(STAIR_TRACE_LIVE_FILE, FileAccess.WRITE)
		for line: String in _stair_trace_buffer:
			live_file.store_line(line)
		live_file.close()

func _sample_hip_skin_stretch(player: Player, ik: PlayerFootIKModifier) -> Dictionary:
	var sides := {}
	var sample_max_error := 0.0
	for side: StringName in [&"left", &"right"]:
		var hip_idx: int = ik._bone_indices[side]["hip"]
		var pelvis_idx := player.skeleton.get_bone_parent(hip_idx)
		var current_distance := player.skeleton.get_bone_global_pose(pelvis_idx).origin.distance_to(
				player.skeleton.get_bone_global_pose(hip_idx).origin)
		var authored_distance := player.skeleton.get_bone_global_rest(pelvis_idx).origin.distance_to(
				player.skeleton.get_bone_global_rest(hip_idx).origin)
		var error := absf(current_distance - authored_distance)
		sample_max_error = maxf(sample_max_error, error)
		sides[side] = {
			"distance": current_distance,
			"authored_distance": authored_distance,
			"error": error,
		}
	_stretch_check_samples += 1
	_stretch_check_max_error = maxf(_stretch_check_max_error, sample_max_error)
	if sample_max_error > HIP_SKIN_STRETCH_LIMIT:
		_stretch_check_failed = true
	return {"max_error": sample_max_error, "sides": sides}

func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	for child in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null

func _foot_trace_sample(
		walker: Dictionary, ik: PlayerFootIKModifier, side: StringName) -> Dictionary:
	var indices: Dictionary = ik._bone_indices[side]
	var probes: Dictionary = _trace_probes[side]
	var foot_pose: Transform3D = (probes["foot"] as Node3D).global_transform
	var foot_position: Vector3 = foot_pose.origin
	var sole_down := (foot_pose.basis * (ik._sole_down_local[side] as Vector3)).normalized()
	var sole_position := foot_position + sole_down * ik.ankle_offset
	var toe_position := foot_position
	if int(indices["toe"]) >= 0:
		toe_position = (probes["toe"] as Node3D).global_position
	var foot_forward := toe_position - foot_position
	var toe_tip := toe_position
	if not foot_forward.is_zero_approx():
		toe_tip += foot_forward.normalized() * ik.toe_tip_margin
	var ground_target: Vector3 = ik._smoothed_target.get(side, foot_position)
	var contact: Dictionary = _contact_debug_state.get(side, {})
	var animation_velocity: float = ik.debug_vertical_velocity.get(side, 0.0)
	var animation_lowering := animation_velocity < -ik.velocity_noise_floor
	var contact_within_3cm: bool = contact.get("within_3cm", false)
	var leg_state = ik._stair_predictor._legs.get(side)
	var swinging = leg_state.swing_active if leg_state != null else null
	var raw_weight: float = ik.debug_raw_weight.get(side, -1.0)
	return {
		"step_down": ik.debug_step_down.get(side, false), "swing_active": swinging,
		"contact_lost": ik.debug_contact_lost.get(side, null), "raw_weight": raw_weight,
		"ankle": _vector_to_array(foot_position),
		"sole": _point_stair_trace(walker, sole_position),
		"toe_joint": _vector_to_array(toe_position),
		"toe_tip": _point_stair_trace(walker, toe_tip),
		"ik_ground_target": _vector_to_array(ground_target),
		"ground_weight": ik._smoothed_ground_weight.get(side, 0.0),
		"predicted_step": _vector_to_array(
				ik.predicted_step_targets.get(side, foot_position)),
		"step_lift": ik._smoothed_step_lift.get(side, 0.0),
		"contact_ray_start": contact.get("start", []),
		"contact_hit": contact.get("hit", []),
		"contact_distance": contact.get("distance", -1.0),
		"contact_within_3cm": contact_within_3cm,
		"animation_vertical_velocity": animation_velocity,
		"animation_lowering": animation_lowering,
		"lowering_within_3cm": animation_lowering and contact_within_3cm,
	}

func _point_stair_trace(walker: Dictionary, point: Vector3) -> Dictionary:
	var relative_z: float = point.z - float(walker["origin_z"])
	var under_index := floori(relative_z / STAIR_TREAD_DEPTH)
	under_index = clampi(under_index, -1, STAIR_STEP_COUNT - 1)
	var below_top := float(walker["origin_y"])
	if under_index >= 0:
		below_top += float(walker["stair_height"]) * (under_index + 1)
	var above_index := mini(under_index + 1, STAIR_STEP_COUNT - 1)
	var above_top := float(walker["origin_y"])
	if above_index >= 0:
		above_top += float(walker["stair_height"]) * (above_index + 1)
	return {
		"position": _vector_to_array(point),
		"step_below": under_index,
		"step_below_top_y": below_top,
		"clearance": point.y - below_top,
		"step_above": above_index,
		"step_above_top_y": above_top,
		"next_riser_z": float(walker["origin_z"]) + (under_index + 1) * STAIR_TREAD_DEPTH,
	}

func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _build_step_prediction_markers() -> void:
	if not _prediction_markers.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.05, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.8, 0.05, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side: StringName in [&"left", &"right"]:
		var sphere := SphereMesh.new()
		sphere.radius = 0.065
		sphere.height = 0.13
		sphere.material = material
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.visible = false
		add_child(marker)
		_prediction_markers[side] = marker

func _build_foot_trace_probes(player: Player, ik: PlayerFootIKModifier) -> void:
	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = ik._bone_indices[side]
		var probes := {}
		for kind: StringName in [&"foot", &"toe"]:
			var bone_index: int = indices[kind]
			if bone_index < 0:
				continue
			var attachment := BoneAttachment3D.new()
			attachment.bone_idx = bone_index
			player.skeleton.add_child(attachment)
			var probe := Node3D.new()
			attachment.add_child(probe)
			probes[kind] = probe
		_trace_probes[side] = probes

func _update_step_prediction_markers() -> void:
	if _prediction_ik == null:
		return
	for side: StringName in [&"left", &"right"]:
		var marker: MeshInstance3D = _prediction_markers[side]
		if not _prediction_ik.predicted_step_targets.has(side):
			marker.visible = false
			continue
		marker.global_position = _prediction_ik.predicted_step_targets[side] + Vector3.UP * 0.065
		marker.visible = true
	_update_foot_contact_rays()

func _build_foot_contact_visuals() -> void:
	_contact_materials["far"] = _build_contact_material(Color(1.0, 0.92, 0.05))
	_contact_materials["close"] = _build_contact_material(Color(0.1, 1.0, 0.1))
	for side: StringName in [&"left", &"right"]:
		var ray_mesh := ImmediateMesh.new()
		var ray_instance := MeshInstance3D.new()
		ray_instance.mesh = ray_mesh
		ray_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ray_instance)
		_contact_ray_meshes[side] = ray_mesh

		var sphere := SphereMesh.new()
		sphere.radius = 0.045
		sphere.height = 0.09
		sphere.material = _contact_materials["far"]
		var hit_marker := MeshInstance3D.new()
		hit_marker.mesh = sphere
		hit_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hit_marker.visible = false
		add_child(hit_marker)
		_contact_hit_markers[side] = hit_marker

func _build_contact_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material

func _update_foot_contact_rays() -> void:
	if _prediction_player == null or _prediction_ik == null:
		return
	var space := get_world_3d().direct_space_state
	for side: StringName in [&"left", &"right"]:
		var foot_probe: Node3D = _trace_probes[side]["foot"]
		var ray_from := _foot_surface_ray_start(side, foot_probe)
		var ray_to := ray_from + Vector3.DOWN * (
				_prediction_ik.ray_down + _prediction_ik.ray_up)
		var query := PhysicsRayQueryParameters3D.create(ray_from + Vector3.UP * 0.002, ray_to)
		query.collision_mask = 1
		query.collide_with_areas = false
		query.hit_from_inside = true
		query.exclude = [_prediction_player.get_rid()]
		var hit := space.intersect_ray(query)
		var line_end: Vector3 = hit["position"] if not hit.is_empty() else ray_to
		var distance := ray_from.distance_to(line_end) if not hit.is_empty() else -1.0
		var within_3cm := distance >= 0.0 and distance <= FOOT_CONTACT_DISTANCE
		_update_contact_line(side, ray_from, line_end, within_3cm)
		var marker: MeshInstance3D = _contact_hit_markers[side]
		marker.visible = not hit.is_empty()
		if not hit.is_empty():
			marker.global_position = hit["position"]
			marker.material_override = _contact_materials[
					"close" if within_3cm else "far"]
		_contact_debug_state[side] = {
			"start": _vector_to_array(ray_from),
			"hit": _vector_to_array(line_end) if not hit.is_empty() else [],
			"distance": distance,
			"within_3cm": within_3cm,
		}

func _foot_surface_ray_start(side: StringName, foot_probe: Node3D) -> Vector3:
	var sole_down_local: Vector3 = _prediction_ik._sole_down_local[side]
	var sole_down := (foot_probe.global_basis * sole_down_local).normalized()
	var sole_point := foot_probe.global_position + \
			sole_down * _prediction_ik.ankle_offset
	var probes: Dictionary = _trace_probes[side]
	if not probes.has("toe"):
		return sole_point
	var toe_position: Vector3 = (probes["toe"] as Node3D).global_position
	var foot_to_toe := toe_position - foot_probe.global_position
	var toe_tip := toe_position
	if not foot_to_toe.is_zero_approx():
		toe_tip += foot_to_toe.normalized() * _prediction_ik.toe_tip_margin
	return toe_tip if toe_tip.y < sole_point.y else sole_point

func _update_contact_line(
		side: StringName, from: Vector3, to: Vector3, within_3cm: bool) -> void:
	var mesh: ImmediateMesh = _contact_ray_meshes[side]
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _contact_materials[
			"close" if within_3cm else "far"])
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

func _on_foot_landed(
		side: StringName, ground_position: Vector3, player: Player) -> void:
	if player == $Player:
		call_deferred(&"_spawn_footstep_marker", side, ground_position)
		return
	for walker: Dictionary in _stair_walkers:
		if walker["player"] == player and walker["walking"]:
			if walker["trace_enabled"]: # 0.35m advances from rendered contact, not this
				return
			call_deferred(&"_spawn_footstep_marker", side, ground_position)
			_accept_stair_landing(walker, ground_position)
			return

func _try_accept_physical_stair_contact(walker: Dictionary) -> void:
	if not walker["walking"] or not walker["waiting_for_step"]:
		return
	_update_foot_contact_rays()
	var next_tread := int(walker["current_tread"]) + 1
	if next_tread >= STAIR_STEP_COUNT:
		return
	var expected_y: float = float(walker["origin_y"]) + \
			float(walker["stair_height"]) * (next_tread + 1)
	var ik := _find_foot_ik(walker["player"] as Player)
	if ik == null:
		return
	for side: StringName in [&"left", &"right"]:
		var contact: Dictionary = _contact_debug_state.get(side, {})
		if not bool(contact.get("within_3cm", false)):
			continue
		var hit_values: Array = contact.get("hit", [])
		if hit_values.size() != 3:
			continue
		var hit_position := Vector3(hit_values[0], hit_values[1], hit_values[2])
		if absf(hit_position.y - expected_y) > STAIR_LANDING_Y_TOLERANCE:
			continue
		# Rising contact = brush, not landing - unless a latched support foot.
		var vertical_velocity: float = ik.debug_vertical_velocity.get(side, 0.0)
		if (vertical_velocity > ik.velocity_noise_floor
				and ik._forced_support_side != side):
			continue
		_spawn_footstep_marker(side, hit_position)
		_accept_stair_landing(walker, hit_position)
		return

func _accept_stair_landing(walker: Dictionary, ground_position: Vector3) -> void:
	if not walker["waiting_for_step"]:
		return
	var next_tread := int(walker["current_tread"]) + 1
	if next_tread >= STAIR_STEP_COUNT:
		return
	var expected_y: float = float(walker["stair_height"]) * (next_tread + 1)
	if absf(ground_position.y - expected_y) > STAIR_LANDING_Y_TOLERANCE:
		return
	var player: Player = walker["player"]
	var old_y := player.global_position.y
	var next_position := player.global_position
	next_position.y = expected_y + 0.05
	next_position.z = float(walker["origin_z"]) + next_tread * STAIR_TREAD_DEPTH
	player.global_position = next_position
	player._stair_hover_offset_y += old_y - next_position.y
	player._stair_hover_offset_y = clampf(
			player._stair_hover_offset_y, -player.step_height, player.step_height)
	walker["current_tread"] = next_tread
	walker["waiting_for_step"] = false

func _spawn_footstep_marker(side: StringName, ground_position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.85, 1.0) if side == &"left" else Color(1.0, 0.4, 0.1)
	material.emission_enabled = true
	material.emission = material.albedo_color
	marker.material_override = material
	add_child(marker)
	marker.global_position = ground_position + Vector3.UP * sphere.radius
	get_tree().create_timer(FOOTSTEP_MARKER_LIFETIME).timeout.connect(marker.queue_free)

func _build_platform(case: Dictionary, origin: Vector3) -> Vector3: # returns world-space footing
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

# A single inclined slab rotated about local X — no per-point profile needed.
func _build_ramp(origin: Vector3, angle_deg: float) -> Vector3:
	var angle_rad := deg_to_rad(angle_deg)
	var box := CSGBox3D.new()
	box.size = Vector3(PLATFORM_WIDTH, PLATFORM_THICKNESS, PLATFORM_LENGTH)
	box.material = _platform_material
	box.use_collision = true
	box.rotation = Vector3(-angle_rad, 0.0, 0.0)
	# Anchor the near-bottom edge at origin: offset by half-length/half-thickness along tilted axes.
	var half_length_offset := box.basis * Vector3(0.0, 0.0, PLATFORM_LENGTH * 0.5)
	var half_thickness_offset := box.basis * Vector3(0.0, -PLATFORM_THICKNESS * 0.5, 0.0)
	box.position = origin + half_length_offset + half_thickness_offset
	add_child(box)
	var mid_rise := tan(angle_rad) * PLATFORM_LENGTH * 0.5
	return origin + Vector3(0.0, mid_rise, PLATFORM_LENGTH * 0.5)

func _build_stairs(origin: Vector3, step_height: float) -> Vector3: # fixed tread, variable riser
	for step in STAIR_STEP_COUNT:
		var step_rise := step_height * (step + 1)
		var tread_start_z := step * STAIR_TREAD_DEPTH
		var box := CSGBox3D.new()
		box.size = Vector3(PLATFORM_WIDTH, step_rise, STAIR_TREAD_DEPTH)
		box.material = _stair_riser_debug_material
		box.use_collision = true
		box.position = origin + Vector3(
				0.0, step_rise * 0.5, tread_start_z + STAIR_TREAD_DEPTH * 0.5)
		add_child(box)
		var tread := CSGBox3D.new() # CSGBox3D allows one material - thin red cap over the blue box
		tread.size = Vector3(
				PLATFORM_WIDTH, STAIR_TREAD_DEBUG_THICKNESS, STAIR_TREAD_DEPTH)
		tread.material = _stair_tread_debug_material
		tread.use_collision = false
		tread.position = origin + Vector3(
				0.0,
				step_rise + STAIR_TREAD_DEBUG_THICKNESS * 0.5,
				tread_start_z + STAIR_TREAD_DEPTH * 0.5)
		add_child(tread)
	var mid_step := STAIR_STEP_COUNT / 2 # riser between two middle steps
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
