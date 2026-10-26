extends Node3D
## Plays the game's ledge / traversal clips (BVH files from the reverse-engineering folder) as a stick figure next to a
## ledge block, to see how the edge grab, hang, shimmy and pull-up actually move. Windowed:
##   godot --path . --screen 1 --windowed res://tests/manual/ledge_anim/ledge_anim_lab.tscn -- [--clip=text] [--shot=PATH]
## Keys: Left / Right clip   Space pause   [ ] speed   Home restart   mouse: left orbit, wheel zoom, right pan
## --clip=text starts on the first clip whose name contains it; --shot=PATH saves a picture and quits;
## --at=SECONDS picks the moment for the picture; --dir=PATH picks the folder; --yaw=DEG the view.

const DEFAULT_DIR := "D:/RE/game_locomotion/anims/bvh_trav_ledge"
const HIDDEN_PARTS := ["twist", "offset", "wrinkle", "holster", "attachment", "pinky", "ring", "middle", "index", "thumb"]

var _dir := DEFAULT_DIR
var _files: PackedStringArray = []
var _index := 0
const BvhClip := preload("res://tests/manual/ledge_anim/bvh_clip.gd")

var _clip: BvhClip
var _time := 0.0
var _speed := 1.0
var _paused := false
var _shot := ""
var _shot_at := -1.0
var _mesh := ImmediateMesh.new()
var _ledge: MeshInstance3D
var _camera: Camera3D
var _label: Label
var _yaw := 70.0
var _pitch := -4.0
var _distance := 5.5
var _target := Vector3(0.0, 1.3, 0.0)
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
	for file in DirAccess.get_files_at(_dir):
		if file.ends_with(".bvh"):
			_files.append(file)
	_files.sort()
	_build_stage()
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
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.16, 0.17, 0.18)
	ground.material_override = ground_material
	add_child(ground)
	_ledge = MeshInstance3D.new()
	var ledge_material := StandardMaterial3D.new()
	ledge_material.albedo_color = Color(0.28, 0.25, 0.22)
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


func _load() -> void:
	if _files.is_empty():
		_label.text = "no BVH in " + _dir
		return
	_clip = BvhClip.load_file(_dir + "/" + _files[_index])
	_time = 0.0
	_place_ledge()


## The ledge is where the hands end up: its top at the wrist height and its face at the wrist depth, taken from the
## frame where the hands are highest above the feet. Clips where the hands never go overhead get no ledge.
func _place_ledge() -> void:
	_ledge.visible = false
	if _clip == null:
		return
	var right := _clip.names.find("r_wrist")
	var left := _clip.names.find("l_wrist")
	var ankle := _clip.names.find("l_ankle")
	var best := -1.0
	var top := 0.0
	var face := 0.0
	for step in maxi(_clip.frames.size(), 2):
		var pose := _clip.pose(float(step) * _clip.frame_time, false)
		var hands := (pose[right].origin + pose[left].origin) * 0.5
		var height := hands.y - pose[ankle].origin.y
		if height > best:
			best = height
			top = hands.y
			face = hands.z
	if best < 1.2:
		return
	_ledge.visible = true
	var box := BoxMesh.new()
	box.size = Vector3(6.0, top, 2.0)
	_ledge.mesh = box
	_ledge.position = Vector3(0.0, top * 0.5, face + 1.0)


func _process(delta: float) -> void:
	if _clip == null:
		return
	if not _paused:
		_time += delta * _speed
	var at := _time if _shot_at < 0.0 else _shot_at
	_draw(_clip.pose(at, true))
	_label.text = "%s\n%d / %d   t=%.2f / %.2f s   %.0f fps   speed %.2f%s\n[Left/Right] clip  [Space] pause  [ [ ] ] speed  [Home] restart" % [
			_clip.title, _index + 1, _files.size(), fposmod(at, _clip.duration()), _clip.duration(),
			1.0 / _clip.frame_time, _speed, "  PAUSED" if _paused else ""]
	_place_camera()
	if _shot != "" and Engine.get_frames_drawn() > 40:
		get_viewport().get_texture().get_image().save_png(_shot)
		print("LEDGE_ANIM_LAB picture ", _shot)
		get_tree().quit()


func _draw(pose: Array[Transform3D]) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for joint in _clip.names.size():
		var parent := _clip.parents[joint]
		if parent < 0 or _hidden(_clip.names[joint]):
			continue
		var name := _clip.names[joint]
		var color := Color(1.0, 0.85, 0.3)
		if name.begins_with("l_"):
			color = Color(0.4, 0.8, 1.0)
		elif name.begins_with("r_"):
			color = Color(1.0, 0.5, 0.45)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(pose[parent].origin)
		_mesh.surface_add_vertex(pose[joint].origin)
	var mover := pose[0].origin # the clip's anchor on the ground, as a cross
	_mesh.surface_set_color(Color(0.5, 1.0, 0.5))
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		_mesh.surface_add_vertex(mover - axis * 0.3)
		_mesh.surface_add_vertex(mover + axis * 0.3)
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
			KEY_BRACKETRIGHT:
				_speed = minf(_speed * 1.25, 4.0)
			KEY_BRACKETLEFT:
				_speed = maxf(_speed * 0.8, 0.05)
			KEY_HOME:
				_time = 0.0
