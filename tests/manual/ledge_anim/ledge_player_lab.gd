extends Node3D
## The game's ledge / traversal clips (BVH) played on the player's own model, next to a ledge block. Windowed:
##   godot --path . --screen 1 --windowed res://tests/manual/ledge_anim/ledge_player_lab.tscn -- [--clip=text] [--shot=PATH]
## Left / Right clip   Space pause   [ ] speed   Home restart   S show the source stick figure   mouse: orbit / zoom / pan
## --clip=text starts on the first clip whose name contains it; --at=SECONDS and --shot=PATH save a picture and quit;
## --yaw=DEG --distance=M --height=M set the view; --dir=PATH picks the folder.

const BvhClip := preload("res://tests/manual/ledge_anim/bvh_clip.gd")
const BvhRetarget := preload("res://tests/manual/ledge_anim/bvh_retarget.gd")
const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const DEFAULT_DIR := "D:/RE/game_locomotion/anims/bvh_trav_ledge"
const REFERENCE := "ledge-facing-idle.bvh"
const HIDDEN_PARTS := ["twist", "offset", "wrinkle", "holster", "attachment", "pinky", "ring", "middle", "index", "thumb"]

var _dir := DEFAULT_DIR
var _files: PackedStringArray = []
var _index := 0
var _clip: BvhClip
var _time := 0.0
var _speed := 1.0
var _paused := false
var _stick := false
var _shot := ""
var _shot_at := -1.0
var _player: Player
var _retarget: BvhRetarget
var _ledge: MeshInstance3D
var _ground: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _camera: Camera3D
var _label: Label
var _yaw := 60.0
var _pitch := -4.0
var _distance := 5.0
var _target := Vector3(0.0, 1.2, 0.0)
var _drag := 0


func _ready() -> void:
	var wanted := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="):
			wanted = arg.substr(7)
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)
		elif arg.begins_with("--at="):
			_shot_at = float(arg.substr(5))
		elif arg.begins_with("--dir="):
			_dir = arg.substr(6)
		elif arg.begins_with("--yaw="):
			_yaw = float(arg.substr(6))
		elif arg.begins_with("--distance="):
			_distance = float(arg.substr(11))
		elif arg.begins_with("--height="):
			_target.y = float(arg.substr(9))
		elif arg == "--stick":
			_stick = true
	for file in DirAccess.get_files_at(_dir):
		if file.ends_with(".bvh"):
			_files.append(file)
	_files.sort()
	_build_stage()
	_build_player()
	_camera.make_current()
	for i in _files.size():
		if wanted != "" and _files[i].contains(wanted):
			_index = i
			break
	_load()


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.24, 0.3)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.16, 0.17, 0.18)
	ground.material_override = ground_material
	add_child(ground)
	_ground = ground
	_ledge = MeshInstance3D.new()
	var ledge_material := StandardMaterial3D.new()
	ledge_material.albedo_color = Color(0.28, 0.25, 0.22, 0.45)
	ledge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ledge.material_override = ledge_material
	add_child(_ledge)
	var lines := MeshInstance3D.new()
	lines.mesh = _mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	lines.material_override = line_material
	add_child(lines)
	_camera = Camera3D.new()
	_camera.near = 0.05
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	layer.add_child(_label)


## The player scene, switched off: only its model and skeleton are used, posed by hand every frame.
func _build_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	add_child(_player)
	for extra in _player.find_children("*", "Camera3D", true, false):
		(extra as Camera3D).clear_current(false) # the lab has its own camera
	for extra in _player.find_children("*", "CanvasLayer", true, false):
		(extra as CanvasLayer).visible = false # and no game HUD
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_unhandled_input(false)
	_player.body.set_process(false)
	_player.body.set_physics_process(false)
	_player.body.anim_player.stop()
	_player.body.anim_player.active = false
	var skeleton := _player.body.skeleton
	for child in skeleton.get_children():
		if child is SkeletonModifier3D:
			(child as SkeletonModifier3D).active = false
	for tree in _player.body.find_children("*", "AnimationTree", true, false):
		(tree as AnimationTree).active = false
	_retarget = BvhRetarget.new(skeleton, _player.body.get("_target_humanoid_map"))
	if not _retarget.has_roles():
		push_error("ledge_player_lab: the player's humanoid map misses the hips / spine / legs")
	var reference := BvhClip.load_file(_dir + "/" + REFERENCE)
	if reference != null:
		var pose: Array[Transform3D] = reference.pose(0.0, false)
		var feet := Vector3.ZERO
		for side in ["l", "r"]:
			feet += pose[reference.names.find(side + "_ball")].origin - pose[reference.names.find(side + "_ankle")].origin
		feet.y = 0.0
		var source_forward := feet.normalized()
		var target_forward := _retarget.target_forward()
		_retarget.yaw = Basis(Vector3.UP, source_forward.signed_angle_to(target_forward, Vector3.UP))
		_retarget.scale = _retarget.fit_scale(reference)
		print("LEDGE_LAB source forward ", source_forward, " player forward ", target_forward, " scale ", _retarget.scale)
		print("LEDGE_LAB hips-based turn puts the feet at ", _retarget.facing_yaw(reference, 0.0) * source_forward)


func _load() -> void:
	if _files.is_empty():
		_label.text = "no BVH in " + _dir
		return
	_clip = BvhClip.load_file(_dir + "/" + _files[_index])
	_time = 0.0
	_place_ledge()


## The ledge is where the hands grab: its top at the wrist height, its near face at the wrist depth, taken from the frame
## where the hands are highest above the hips (the hang). The block extends the way the body faces then, and goes far
## below, because the ground under a hang is somewhere else. Clips without a hang get a floor and no block.
func _place_ledge() -> void:
	_ledge.visible = false
	_ground.position.y = 0.0
	if _clip == null:
		return
	var right: int = _clip.names.find("r_wrist")
	var left: int = _clip.names.find("l_wrist")
	var hips: int = _clip.names.find("pelvis")
	var best := 0.45
	var hands := Vector3.ZERO
	var facing := Vector3.ZERO
	for step in maxi(_clip.frames.size(), 2):
		var pose: Array[Transform3D] = _clip.pose(float(step) * _clip.frame_time, false)
		var middle := (pose[right].origin + pose[left].origin) * 0.5
		var over: float = middle.y - pose[hips].origin.y
		if over > best:
			best = over
			hands = middle
			facing = Vector3.ZERO
			for side in ["l", "r"]:
				facing += pose[_clip.names.find(side + "_ball")].origin - pose[_clip.names.find(side + "_ankle")].origin
	if hands == Vector3.ZERO:
		return
	facing.y = 0.0
	var world_hands := (_retarget.yaw * hands) * _retarget.scale
	var world_facing := (_retarget.yaw * facing).normalized()
	var top := world_hands.y
	var depth := 6.0
	_ledge.visible = true
	_ground.position.y = top - depth
	var box := BoxMesh.new()
	box.size = Vector3(6.0, depth, 2.0)
	_ledge.mesh = box
	var edge := Vector3(world_hands.x, 0.0, world_hands.z)
	_ledge.global_transform = Transform3D(Basis.looking_at(world_facing, Vector3.UP),
			edge + world_facing * 1.0 + Vector3.UP * (top - depth * 0.5))


func _process(delta: float) -> void:
	if _clip == null or _retarget == null:
		return
	if not _paused:
		_time += delta * _speed
	var at := _time if _shot_at < 0.0 else _shot_at
	_retarget.apply(_clip, at)
	_draw_stick(_clip.pose(at, true) if _stick else [])
	_label.text = "%s\n%d / %d   t=%.2f / %.2f s   speed %.2f%s\n[Left/Right] clip  [Space] pause  [ [ ] ] speed  [Home] restart  [S] source stick" % [
			_clip.title, _index + 1, _files.size(), fposmod(at, _clip.duration()), _clip.duration(), _speed,
			"  PAUSED" if _paused else ""]
	_place_camera()
	if get_viewport().get_camera_3d() != _camera:
		_camera.make_current() # the player scene's own camera keeps asking for the view
	if _shot != "" and Engine.get_frames_drawn() > 40:
		get_viewport().get_texture().get_image().save_png(_shot)
		var active := get_viewport().get_camera_3d()
		print("LEDGE_LAB camera ", active.get_path(), " at ", active.global_position, " mine ", _camera.global_position, " yaw ", _yaw)
		_report_error(at)
		print("LEDGE_LAB picture ", _shot)
		get_tree().quit()


func _draw_stick(pose: Array) -> void:
	_mesh.clear_surfaces()
	if pose.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(Color(1.0, 0.85, 0.3))
	for joint in _clip.names.size():
		var parent: int = _clip.parents[joint]
		if parent < 0 or _hidden(_clip.names[joint]):
			continue
		_mesh.surface_add_vertex((_retarget.yaw * (pose[parent] as Transform3D).origin) * _retarget.scale)
		_mesh.surface_add_vertex((_retarget.yaw * (pose[joint] as Transform3D).origin) * _retarget.scale)
	_mesh.surface_end()


func _hidden(joint_name: String) -> bool:
	for part: String in HIDDEN_PARTS:
		if joint_name.contains(part):
			return true
	return false


func _place_camera() -> void:
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	_camera.position = _target + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * _distance
	_camera.look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 0.5)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 30.0)
		else:
			_drag = button.button_index if button.pressed else 0
	elif event is InputEventMouseMotion and _drag != 0:
		var motion := event as InputEventMouseMotion
		if _drag == MOUSE_BUTTON_LEFT:
			_yaw -= motion.relative.x * 0.4
			_pitch = clampf(_pitch - motion.relative.y * 0.4, -89.0, 89.0)
		else:
			var basis := _camera.global_transform.basis
			_target += (-basis.x * motion.relative.x + basis.y * motion.relative.y) * _distance * 0.0016
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_RIGHT:
				_index = posmod(_index + 1, maxi(_files.size(), 1))
				_load()
			KEY_LEFT:
				_index = posmod(_index - 1, maxi(_files.size(), 1))
				_load()
			KEY_SPACE:
				_paused = not _paused
			KEY_S:
				_stick = not _stick
			KEY_BRACKETRIGHT:
				_speed = minf(_speed * 1.25, 4.0)
			KEY_BRACKETLEFT:
				_speed = maxf(_speed * 0.8, 0.05)
			KEY_HOME:
				_time = 0.0


## How far the posed model's joints are from where the clip puts them (world space, metres): a faithful retarget keeps
## the hands, feet and head within a few centimetres.
func _report_error(at: float) -> void:
	var skeleton := _player.body.skeleton
	var source: Array[Transform3D] = _clip.pose(at, true)
	var pairs := [["Hips", "pelvis"], ["Head", "heada"], ["LeftHand", "l_wrist"], ["RightHand", "r_wrist"],
			["LeftFoot", "l_ankle"], ["RightFoot", "r_ankle"], ["LeftLeg", "l_knee"], ["LeftForeArm", "l_elbow"]]
	var map: Dictionary = _player.body.get("_target_humanoid_map")
	var line := "LEDGE_LAB error t=%.2f" % at
	for pair in pairs:
		var bone := skeleton.find_bone(String(map.get(pair[0], "")))
		var joint: int = _clip.names.find(pair[1])
		if bone < 0 or joint < 0:
			continue
		var model := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var wanted: Vector3 = (_retarget.yaw * source[joint].origin) * _retarget.scale
		line += "  %s %.3f" % [pair[0], model.distance_to(wanted)]
		if pair[0] == "Hips":
			line += " (model %s clip %s)" % [model.snapped(Vector3.ONE * 0.01), wanted.snapped(Vector3.ONE * 0.01)]
	print(line)
	var up := skeleton.find_bone(String(map.get("LeftUpLeg", "")))
	var knee := skeleton.find_bone(String(map.get("LeftLeg", "")))
	var model_dir := (skeleton.get_bone_global_pose(knee).origin - skeleton.get_bone_global_pose(up).origin).normalized()
	var wanted_dir: Vector3 = _retarget.to_skeleton(source[_clip.names.find("l_knee")].origin) - _retarget.to_skeleton(source[_clip.names.find("l_upper_leg")].origin)
	var w := func(joint: String) -> Vector3: return ((_retarget.yaw * source[_clip.names.find(joint)].origin) * _retarget.scale).snapped(Vector3.ONE * 0.001)
	var m := func(role: String) -> Vector3: return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(String(map.get(role, "")))).origin).snapped(Vector3.ONE * 0.001)
	print("LEDGE_LAB upleg model ", m.call("LeftUpLeg"), " clip ", w.call("l_upper_leg"), " knee model ", m.call("LeftLeg"), " clip ", w.call("l_knee"), " hips model ", m.call("Hips"), " clip pelvis ", w.call("pelvis"), " thigh len model ", (m.call("LeftLeg") - m.call("LeftUpLeg")).length(), " clip ", (w.call("l_knee") - w.call("l_upper_leg")).length())
	print("LEDGE_LAB thigh model dir ", model_dir, " wanted ", wanted_dir.normalized(), " angle ", rad_to_deg(model_dir.angle_to(wanted_dir)),
			" skeleton scale ", skeleton.global_transform.basis.get_scale(), " bone count ", skeleton.get_bone_count(), " up parent ", skeleton.get_bone_parent(up), " hips ", skeleton.find_bone(String(map.get("Hips", ""))))
