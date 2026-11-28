extends Node3D
## Human rig lab: a rigged base body (assets/models/humans/*_rigged.glb) whose skeleton follows the Height / Weight / Muscle sliders (native HumanRig).
## Left drag turns the body, wheel zooms. Keys: 1 rest pose, 2 arms up, 3 squat, 4 Mixamo walk (retargeted onto this skeleton), B bones on/off, G gender, Up/Down height.
## Capture mode: `-- --capture=<png> --gender=Male|Female --height= --weight= --muscle= --pose=rest|armsup|squat|walk --time=<seconds into the walk> --bones --yaw=<deg> --face (the camera on the head and shoulders) --sweep=<deg> (the body turns back and forth that far while the lab runs: for a video) --distance=<m> --clothes=<outfit>|underwear --cloth (the clothes simulated by the GPU cloth add-on, task 103; the walk then plays and the frame is taken after --capture-frame=, 150)` saves one frame and quits.

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
var _body_turn: float = 0.0   # the body's own turn (left drag, --sweep): the cloth reacts to it
var _clothes: String = "villager"   # an outfit (assets/models/humans/outfits), or "underwear"
var _cloth: bool = false   # --cloth: simulate the villager clothes (addons/godot_gpu_cloth, task 103)
var _cloth_root: Node3D = null
var _capture_frame: int = 12
var _sun_dir := Vector3(0.35, 0.8, 0.45)
var _garments: Array = []   # the outfit's garments (recipes, inside out)
var _garment_pieces: Array = []   # their meshes, skinned to the skeleton (the cloth solvers draw them)


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
		elif arg == "--cloth":
			_cloth = true
			_capture_frame = 150
		elif arg.begins_with("--capture-frame="):
			_capture_frame = int(arg.trim_prefix("--capture-frame="))
		elif arg.begins_with("--clothes="):
			_clothes = arg.trim_prefix("--clothes=").to_lower()
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
	_sun_dir = sun.transform.basis.z.normalized()   # (toward the sun: the clothes' close-up weave shadows)
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
	_garments = []
	_garment_pieces = []
	var outfit: Dictionary = {} if _clothes == "underwear" else ClothSetup.load_outfit(_clothes)
	for garment: Dictionary in outfit.get("garments", []):
		if not ResourceLoader.exists(base + "%s_%s.glb" % [outfit["name"], garment["name"]]):
			push_warning("Clothes: %s%s_%s.glb is not built (tools/blender/build_outfit.py): the underwear instead" % [base, outfit["name"], garment["name"]])
			outfit = {}
			break
	if not (outfit.get("garments", []) as Array).is_empty():
		# the outfit's garments, skinned with the body's weights like the underwear (which they hide); task 103 simulates them as cloth
		underwear.visible = false
		var materials: Dictionary = ClothSetup.materials()
		for garment: Dictionary in outfit["garments"]:
			var cloth_material: ShaderMaterial = _material_of(ClothSetup.shader_path(garment))
			var look: Dictionary = materials.get(String(garment.get("material", "linen")), {}).get("look", {})
			for key: String in look:
				cloth_material.set_shader_parameter(StringName(key), float(look[key]))
			var colour: Array = (outfit.get("colours", {}) as Dictionary).get(garment["name"], {}).get(_gender.to_lower(), [0.6, 0.55, 0.45])
			cloth_material.set_shader_parameter(&"cloth_color", Color(float(colour[0]), float(colour[1]), float(colour[2])))
			cloth_material.set_shader_parameter(&"imperfection", 0.3)
			cloth_material.set_shader_parameter(&"sun_dir_world", _sun_dir)
			var piece: MeshInstance3D = _take_mesh(base + "%s_%s.glb" % [outfit["name"], garment["name"]], cloth_material)
			_accessories.append(piece)
			HumanRig.attach_skinned(piece, _mesh, _skeleton)
			_garments.append(garment)
			_garment_pieces.append(piece)
		_body.position.y = ClothSetup.footwear_lift(_garments)   # (in shoes, standing on their soles)
		ClothSetup.apply_covered(_garments, _garment_pieces, _garment_pieces.map(func(p: MeshInstance3D) -> Material: return p.material_override))
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
	if _cloth and not _garment_pieces.is_empty():
		_add_cloth()


# The outfit's garments as cloth (task 103): one GPU solver per garment, the cloth weight from the vertex colour's blue (build_outfit.py: 0 held to the
# skinned body, 1 free), the body as a collider, the shirt and the trousers colliding with each other. The solver draws the garment with our clothes
# material (human_clothes.gdshader reads its simulated positions).
func _add_cloth() -> void:
	if _cloth_root != null:
		_cloth_root.queue_free()
	_cloth_root = Node3D.new()
	_cloth_root.name = "Cloth"
	add_child(_cloth_root)
	var solvers: Array = []
	var pieces: Array = []   # (only the garments simulated as cloth: the shoes follow the skeleton)
	var garments: Array = []
	for i in _garments.size():
		if ClothSetup.is_simulated(_garments[i]):
			pieces.append(_garment_pieces[i])
			garments.append(_garments[i])
	for i in pieces.size():
		var piece: MeshInstance3D = pieces[i]
		var solver := GPUClothSolver.new()
		solver.name = String(garments[i]["name"]) + "Cloth"
		solver.target_mesh = piece.get_path()
		solver.skeleton = _skeleton.get_path()
		solver.body_mesh = _mesh.get_path()
		ClothSetup.configure(solver, garments[i])
		solver.cloth_material = piece.material_override
		piece.material_override = null   # (the solver puts its copy of the material on the mesh's surface: an override would draw over it)
		# (tuning switches, the defaults being ClothSetup's)
		if _arg_value("--cloth-iterations", "") != "":
			solver.solver_iterations = int(_arg_value("--cloth-iterations", "4"))
		if _arg_value("--cloth-substeps", "") != "":
			solver.substeps = int(_arg_value("--cloth-substeps", "2"))
		if _arg_value("--cloth-travel", "") != "":
			solver.max_travel_distance = float(_arg_value("--cloth-travel", "0.04"))
		if _arg_value("--cloth-collider", "capsules") == "none":
			solver.auto_collider_lod = 0
			solver.body_collider_voxel_resolution = 0
		solver.peer_collider_voxel_resolution = int(_arg_value("--cloth-peer-res", "8"))
		solvers.append(solver)
	if _arg_value("--cloth-peers", "on") != "off":
		ClothSetup.connect_peers(solvers)
	for solver: GPUClothSolver in solvers:
		_cloth_root.add_child(solver)


# (debug, --cloth-dump) the simulated particles that sit furthest from their rest place, along the rest normal (+ out, - in) and in all
func _dump_cloth() -> void:
	for solver: GPUClothSolver in _cloth_root.get_children():
		var data: PackedFloat32Array = solver._rd.buffer_get_data(solver._positions_buffer).to_float32_array()
		var rest: PackedVector3Array = solver._welded_positions
		var rows: Array = []
		for i in rest.size():
			var p := Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
			rows.append([p.distance_to(rest[i]), rest[i], p - rest[i]])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var mean := 0.0
		for row: Array in rows:
			mean += float(row[0])
		print("CLOTH_DUMP ", solver.name, " particles ", rest.size(), " mean move ", mean / rows.size())
		for k in 12:
			print("CLOTH_DUMP   ", "%.4f" % rows[k][0], " rest ", rows[k][1], " move ", rows[k][2])
		for centre: Vector3 in [Vector3(0.063, 1.273, 0.168), Vector3(-0.063, 1.273, 0.168), Vector3(0.0, 1.05, 0.13)]:
			var near: Array = []
			for i in rest.size():
				if rest[i].distance_to(centre) < 0.03:
					var p := Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
					near.append([rest[i], p - rest[i]])
			near.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector3).length() > (b[1] as Vector3).length())
			print("CLOTH_DUMP near ", centre, " count ", near.size(), " largest ", near.slice(0, 4))


const LIMBS: Array = [["elbow", "l", "LeftArm", "LeftForeArm", "LeftHand"], ["elbow", "r", "RightArm", "RightForeArm", "RightHand"],
		["knee", "l", "LeftUpLeg", "LeftLeg", "LeftFoot"], ["knee", "r", "RightUpLeg", "RightLeg", "RightFoot"]]


# The clothes' joints (the wear at the elbows and the knees, the bend wrinkles): where each joint is and the limb's direction in the rest shape
# (the cloth's pattern lies on its rest shape), and how bent it is now, every frame (a walk bends the knees and the elbows).
func _update_cloth_joints() -> void:
	if _garment_pieces.is_empty() or _skeleton == null:
		return
	var materials: Array = []
	if _cloth_root != null:
		for solver: Node in _cloth_root.get_children():
			if solver is GPUClothSolver and (solver as GPUClothSolver)._surf_mat != null:
				materials.append((solver as GPUClothSolver)._surf_mat)
	for piece: MeshInstance3D in _garment_pieces:
		if piece.material_override is ShaderMaterial:
			materials.append(piece.material_override)
	if materials.is_empty():
		return
	var params: Dictionary = {"has_joints": true}
	for limb: Array in LIMBS:
		var bones: Array = []
		for bone_name: String in [limb[2], limb[3], limb[4]]:
			bones.append(_skeleton.find_bone("mixamorig_" + bone_name))
		if bones.has(-1):
			continue
		var rest: Array = bones.map(func(b: int) -> Vector3: return _skeleton.get_bone_global_rest(b).origin)
		var now: Array = bones.map(func(b: int) -> Vector3: return _skeleton.get_bone_global_pose(b).origin)
		params["%s_%s" % [limb[0], limb[1]]] = rest[1]
		params["%s_axis_%s" % [limb[0], limb[1]]] = ClothSetup.limb_bend(rest[0], rest[1], rest[2])[0]
		params["%s_bend_%s" % [limb[0], limb[1]]] = ClothSetup.limb_bend(now[0], now[1], now[2])[1]
	for material: ShaderMaterial in materials:
		for key: String in params:
			material.set_shader_parameter(StringName(key), params[key])


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
	if _capture_path != "" and not _cloth:
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
	_update_cloth_joints()
	if OS.get_cmdline_user_args().has("--cloth-overlap") and Engine.get_process_frames() % 10 == 0 and Engine.get_process_frames() >= 60 and _cloth_root != null:
		RenderingServer.call_on_render_thread(ClothOverlapProbe.measure_layers.bind(_cloth_root.get_children()))
	if OS.get_cmdline_user_args().has("--cloth-dump") and Engine.get_process_frames() == 80 and _cloth_root != null:
		RenderingServer.call_on_render_thread(_dump_cloth)
	if OS.get_cmdline_user_args().has("--gpu-time"):
		# (task 103: what the cloth costs) the GPU time of the frame, every 60 frames, from the viewport's measured render time
		# (the viewport's measured GPU time leaves the solver's compute passes out: the whole frame, uncapped, is the honest number)
		if Engine.get_process_frames() == 1:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		if Engine.get_process_frames() % 120 == 0:
			print("RIG_LAB_FPS %.0f (%.2f ms a frame, process %.2f ms)" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	if _sweep > 0.0:
		# (--sweep turns the body back and forth, not the camera: the cloth swings with it)
		_clock += delta
		_body_turn = _sweep * sin(_clock * 2.2)
		_body.rotation.y = _body_turn
	if _capture_path != "":
		_frames += 1
		if _frames == _capture_frame:
			get_viewport().get_texture().get_image().save_png(_capture_path)
			print("HUMAN_RIG_LAB ", _label.text)
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		# the drag turns the BODY (the camera stays): the simulated cloth swings with a real turn (turning the camera moved nothing it could feel)
		_body_turn += (event as InputEventMouseMotion).relative.x * 0.01
		_body.rotation.y = _body_turn
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


func _arg_value(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.trim_prefix(key + "=")
	return fallback
