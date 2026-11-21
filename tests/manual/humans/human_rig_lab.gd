extends Node3D
## Human rig lab: a rigged base body (assets/models/humans/*_rigged.glb) whose skeleton follows the Height / Weight / Muscle sliders (native HumanRig).
## Left drag turns the body, wheel zooms. Keys: 1 rest pose, 2 arms up, 3 squat, 4 Mixamo walk (retargeted onto this skeleton), B bones on/off, G gender, Up/Down height.
## Capture mode: `-- --capture=<png> --gender=Male|Female --height= --weight= --muscle= --pose=rest|armsup|squat|walk --time=<seconds into the walk> --bones --yaw=<deg> --face (the camera on the head and shoulders) --sweep=<deg> (the body turns back and forth that far while the lab runs: for a video) --distance=<m>` saves one frame and quits.

const WALK_CLIP: String = "res://assets/models/action_adventure_pack/walking.fbx" # (a Mixamo clip: the same "mixamorig_" names as this skeleton)
const BODIES: Dictionary = {
	"Male": ["res://assets/models/humans/male_rigged.glb", "res://assets/models/humans/male_rig.json"],
	"Female": ["res://assets/models/humans/female_rigged.glb", "res://assets/models/humans/female_rig.json"],
}

var _gender: String = "Male"
var _height: float = 0.0
var _weight: float = 0.0
var _muscle: float = 0.0
var _pose: String = "rest"
var _bones_shown: bool = false
var _yaw: float = 0.0
var _distance: float = 4.0
var _capture_path: String = ""
var _frames: int = 0
var _body: Node3D
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _accessories: Array[MeshInstance3D] = []
var _rig: HumanRig
var _camera: Camera3D
var _lines: MeshInstance3D
var _label: Label
var _player: AnimationPlayer
var _walk_time: float = 0.4
var _face: bool = false
var _sweep: float = 0.0
var _base_yaw: float = 0.0
var _top: float = 1.7
var _clock: float = 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--gender="):
			_gender = arg.trim_prefix("--gender=")
		elif arg.begins_with("--height="):
			_height = float(arg.trim_prefix("--height="))
		elif arg.begins_with("--weight="):
			_weight = float(arg.trim_prefix("--weight="))
		elif arg.begins_with("--muscle="):
			_muscle = float(arg.trim_prefix("--muscle="))
		elif arg.begins_with("--pose="):
			_pose = arg.trim_prefix("--pose=")
		elif arg.begins_with("--time="):
			_walk_time = float(arg.trim_prefix("--time="))
		elif arg.begins_with("--yaw="):
			_yaw = deg_to_rad(float(arg.trim_prefix("--yaw=")))
		elif arg.begins_with("--distance="):
			_distance = float(arg.trim_prefix("--distance="))
		elif arg == "--bones":
			_bones_shown = true
		elif arg == "--face":
			_face = true
		elif arg.begins_with("--sweep="):
			_sweep = deg_to_rad(float(arg.trim_prefix("--sweep=")))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.62, 0.65, 0.74)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	add_child(sun)
	_camera = Camera3D.new()
	add_child(_camera)
	_lines = MeshInstance3D.new()
	add_child(_lines)
	var canvas := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12, 8)
	canvas.add_child(_label)
	add_child(canvas)
	_base_yaw = _yaw
	_build()


func _build() -> void:
	if _body != null:
		_body.queue_free()
	var entry: Array = BODIES[_gender]
	_body = (load(entry[0]) as PackedScene).instantiate() as Node3D
	add_child(_body)
	_skeleton = _body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_mesh = _body.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skin_material := StandardMaterial3D.new()
	skin_material.albedo_color = Color(0.86, 0.62, 0.5)
	skin_material.roughness = 0.6
	_mesh.material_override = skin_material
	# underwear, eyes, brows, lashes and hair: skinned to the same skeleton (the underwear with the body's weights, the rest rigidly on the head)
	_accessories.clear()
	var base: String = "res://assets/models/humans/%s_" % _gender.to_lower()
	var underwear: MeshInstance3D = _take_mesh(base + "underwear.glb", _material_of("res://shaders/human_underwear_fabric.gdshader"))
	_accessories.append(underwear)
	HumanRig.attach_skinned(underwear, _mesh, _skeleton)
	var face_hair: Shader = load("res://shaders/human_face_hair.gdshader")
	var lash_material := ShaderMaterial.new()
	lash_material.shader = face_hair
	lash_material.set_shader_parameter(&"is_lash", true)
	var brow_material := ShaderMaterial.new()
	brow_material.shader = face_hair
	for part: Array in [["eyes.glb", _material_of("res://shaders/human_eye.gdshader")], ["brows.glb", brow_material], ["lashes.glb", lash_material]]:
		var piece: MeshInstance3D = _take_mesh(base + String(part[0]), part[1])
		_accessories.append(piece)
		HumanRig.attach_rigid(piece, _skeleton, &"mixamorig_Head")
	var style: Dictionary = HumanHair.default_params_for(_gender)
	style.merge({"side_trim": 0.55, "length": 0.07, "fringe": 0.35, "gravity": 0.7, "parting": 0.2}, true)
	var hair := MeshInstance3D.new()
	hair.mesh = HumanHair.build(_mesh.mesh as ArrayMesh, style)
	hair.material_override = _material_of("res://shaders/human_hair.gdshader")
	_skeleton.add_child(hair)
	_accessories.append(hair)
	HumanRig.attach_rigid(hair, _skeleton, &"mixamorig_Head")
	var skinned: Array = [_mesh]
	skinned.append_array(_accessories)
	_rig = HumanRig.new()
	if not _rig.setup(_skeleton, skinned, HumanRig.load_data(entry[1])):
		push_error("HumanRig.setup failed")
	_apply()


func _material_of(shader_path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(shader_path)
	return material


# The mesh instance of a glb, taken out of its scene (the glb of an accessory carries a copy of the skeleton we do not want).
func _take_mesh(path: String, material: Material) -> MeshInstance3D:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var found: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	found.get_parent().remove_child(found)
	scene.free()
	found.material_override = material
	return found


func _apply() -> void:
	var weights: Dictionary = HumanRig.shape_weights(_height, _weight, _muscle)
	for shape: StringName in weights:
		_mesh.set("blend_shapes/" + String(shape), float(weights[shape]))
		for piece: MeshInstance3D in _accessories:
			piece.set("blend_shapes/" + String(shape), float(weights[shape]))
	_rig.apply(weights)
	_pose_body()
	var top: float = _rig.bone_origin(&"mixamorig_Head").y
	_label.text = "%s  height %+.1f weight %+.1f muscle %+.1f  head bone at %.2f m  pose %s   (1 rest, 2 arms up, 3 squat, 4 walk, B bones, G gender, Up/Down height)" % [_gender, _height, _weight, _muscle, top, _pose]
	_update_camera(top)


# The walk is retargeted onto the skeleton as it is NOW (the proportions follow Height), so it is made again whenever a slider moves.
func _play_walk() -> void:
	if _player != null:
		_player.queue_free()
		_player = null
	var source: Node = (load(WALK_CLIP) as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = source.find_child("Skeleton3D", true, false) as Skeleton3D
	var source_animation: Animation = (source.get_node("AnimationPlayer") as AnimationPlayer).get_animation(&"mixamo_com")
	var config: HumanoidRetargeter.BoneMapConfig = HumanoidRetargeter.build_bone_map_config(
			HumanoidRetargeter.prefix_role_map(source_skeleton, "mixamorig_"), CharacterEditorRigHandler.full_map_from_prefix(_skeleton, "mixamorig_"))
	var clip: Animation = HumanoidRetargeter.retarget_clip(source_skeleton, source_animation, _skeleton, config, false)
	HumanoidRetargeter.make_clip_in_place(clip)
	clip.loop_mode = Animation.LOOP_LINEAR
	source.free()
	var library := AnimationLibrary.new()
	library.add_animation(&"walk", clip)
	_player = AnimationPlayer.new()
	_player.add_animation_library(&"", library)
	_skeleton.get_parent().add_child(_player) # (its paths are "<skeleton name>:<bone>", read from the skeleton's parent)
	_player.root_node = NodePath("..")
	_player.play(&"walk")
	if _capture_path != "":
		_player.pause()
		_player.seek(_walk_time, true)


func _pose_body() -> void:
	if _pose == "walk":
		_play_walk()
		return
	if _player != null:
		_player.queue_free()
		_player = null
	_skeleton.reset_bone_poses()
	var turns: Dictionary = {}
	match _pose:
		"armsup":
			turns = {"mixamorig_LeftArm": Quaternion(Vector3(0, 0, 1), 1.35), "mixamorig_RightArm": Quaternion(Vector3(0, 0, 1), -1.35)}
		"squat":
			turns = {"mixamorig_LeftUpLeg": Quaternion(Vector3(1, 0, 0), -1.4), "mixamorig_RightUpLeg": Quaternion(Vector3(1, 0, 0), -1.4),
					"mixamorig_LeftLeg": Quaternion(Vector3(1, 0, 0), 2.2), "mixamorig_RightLeg": Quaternion(Vector3(1, 0, 0), 2.2)}
	for bone_name: String in turns:
		var bone: int = _skeleton.find_bone(bone_name)
		if bone >= 0:
			_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * (turns[bone_name] as Quaternion))


func _update_camera(top: float) -> void:
	_top = top
	var centre := Vector3(0.0, top * 0.5, 0.0)
	var lift: float = 0.2
	if _face: # the head and the top of the shoulders (the head bone is at the base of the head)
		centre = Vector3(0.0, top + 0.11, 0.0)
		lift = 0.0
		_camera.fov = 32.0
	_camera.position = centre + Vector3(sin(_yaw), 0.0, cos(_yaw)) * _distance + Vector3(0.0, lift, 0.0)
	_camera.look_at(centre)


func _draw_bones() -> void:
	if not _bones_shown:
		_lines.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for bone: int in _skeleton.get_bone_count():
		var parent: int = _skeleton.get_bone_parent(bone)
		if parent >= 0:
			mesh.surface_add_vertex(_skeleton.get_bone_global_pose(parent).origin)
			mesh.surface_add_vertex(_skeleton.get_bone_global_pose(bone).origin)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.1, 0.1)
	material.no_depth_test = true
	_lines.mesh = mesh
	_lines.material_override = material


func _process(delta: float) -> void:
	_draw_bones()
	if _sweep > 0.0:
		_clock += delta
		_yaw = _base_yaw + _sweep * sin(_clock * 0.9)
		_update_camera(_top)
	if _capture_path != "":
		_frames += 1
		if _frames == 12:
			get_viewport().get_texture().get_image().save_png(_capture_path)
			print("HUMAN_RIG_LAB ", _label.text)
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= (event as InputEventMouseMotion).relative.x * 0.01
		_apply()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(1.0, _distance * 0.9)
				_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(10.0, _distance / 0.9)
				_apply()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_pose = "rest"
			KEY_2:
				_pose = "armsup"
			KEY_3:
				_pose = "squat"
			KEY_4:
				_pose = "walk"
			KEY_B:
				_bones_shown = not _bones_shown
			KEY_G:
				_gender = "Female" if _gender == "Male" else "Male"
				_build()
				return
			KEY_UP:
				_height = minf(_height + 0.25, 1.0)
			KEY_DOWN:
				_height = maxf(_height - 0.25, -1.0)
		_apply()
