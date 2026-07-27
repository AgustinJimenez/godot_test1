extends Node
## Isolated acceptance harness for GPU Cloth Sim on the modular male Peasant outfit.
##
## The imported body and outfit normally own separate but compatible skeletons. This harness
## keeps the garments on their authored skeleton and skins a hidden body-collider copy into that
## reference frame. Rebinding the garments directly distorted them because the two skeletons'
## similarly named bones have rest positions that differ by as much as 3.4 cm.

const CREATOR_SCENE := preload("res://ui/character_creator.tscn")
const CAPTURE_SETTLE_FRAMES := 120
const SHIRT_ANCHOR_Y := 1.20
const SHIRT_FREE_Y := 0.98
const PANTS_ANCHOR_Y := 1.00
const PANTS_FREE_Y := 0.86

var _creator: Node3D
var _capture_path := ""
var _capture_settle_frames := CAPTURE_SETTLE_FRAMES
var _frames_after_setup := 0
var _setup_done := false
var _animation_time := 0.0
var _body_skeleton: Skeleton3D
var _outfit_skeleton: Skeleton3D


func _ready() -> void:
	_capture_path = _argument_value("capture")
	var settle_argument := _argument_value("settle_frames")
	if settle_argument.is_valid_int():
		_capture_settle_frames = maxi(settle_argument.to_int(), 1)
	_creator = CREATOR_SCENE.instantiate()
	add_child(_creator)
	await get_tree().process_frame
	_creator._on_body_selected(1)
	_creator._on_outfit_selected(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_cloth()


func _process(delta: float) -> void:
	if _setup_done:
		_animate_skeletons(delta)
	if _capture_path.is_empty() or not _setup_done:
		return
	_frames_after_setup += 1
	if _frames_after_setup < _capture_settle_frames:
		return
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_capture_path)
	if error == OK:
		print("GPU_CLOTH_CAPTURE:", _capture_path)
	else:
		push_error("Could not save GPU cloth capture: %s" % error_string(error))
	_capture_path = ""
	_finish_capture(error)


func _setup_cloth() -> void:
	var body_root := _creator._preview_body as Node3D
	var outfit_root := _creator._preview_outfit as Node3D
	var body_mesh := body_root.find_child("SuperHero_Male", true, false) as MeshInstance3D
	var shirt_mesh := outfit_root.find_child(
			"Male_Peasant_Body", true, false) as MeshInstance3D
	var pants_mesh := outfit_root.find_child(
			"Male_Peasant_Legs", true, false) as MeshInstance3D
	var body_skeleton := _find_skeleton(body_root)
	var outfit_skeleton := _find_skeleton(outfit_root)
	if (body_mesh == null or shirt_mesh == null or pants_mesh == null
			or body_skeleton == null or outfit_skeleton == null):
		push_error("GPU cloth harness could not resolve the male body/outfit nodes")
		return
	if not _skeletons_are_compatible(body_skeleton, outfit_skeleton):
		push_error("GPU cloth harness requires matching body and outfit skeletons")
		return
	_body_skeleton = body_skeleton
	_outfit_skeleton = outfit_skeleton
	_creator._fit_editor.auto_adjust(0.005)
	_creator._on_outfit_debug_colors_toggled(false)
	_creator.outfit_debug_colors.set_pressed_no_signal(false)
	var collider_mesh := _make_body_collider_mesh(
			body_mesh, outfit_skeleton, outfit_root)
	_apply_cloth_weights(shirt_mesh, SHIRT_FREE_Y, SHIRT_ANCHOR_Y, 1.0)
	_apply_cloth_weights(pants_mesh, PANTS_FREE_Y, PANTS_ANCHOR_Y, 0.08)
	_add_peer_solvers(
			shirt_mesh, pants_mesh, collider_mesh, outfit_skeleton)
	_creator._face_focused = false
	_creator._orbit_target = _creator.DEFAULT_ORBIT_TARGET
	_creator._orbit_distance = _creator.DEFAULT_ORBIT_DISTANCE
	_creator._update_orbit_camera()
	_setup_done = true
	print("GPU_CLOTH_OUTFIT_READY")


func _animate_skeletons(delta: float) -> void:
	_animation_time += delta
	var spine_twist := sin(_animation_time * 1.4) * 0.12
	for skeleton in [_body_skeleton, _outfit_skeleton]:
		var spine: int = skeleton.find_bone("spine_01")
		skeleton.set_bone_pose_rotation(
				spine, Quaternion(Vector3.UP, spine_twist))
		skeleton.advance(0.0)


func _finish_capture(error: Error) -> void:
	var solvers := _creator.get_node_or_null("GPUClothSolvers")
	if solvers != null:
		solvers.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(error)


func _find_skeleton(root: Node) -> Skeleton3D:
	for node in root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


func _skeletons_are_compatible(first: Skeleton3D, second: Skeleton3D) -> bool:
	if first.get_bone_count() != second.get_bone_count():
		return false
	var maximum_rest_error := 0.0
	for bone_index in first.get_bone_count():
		if first.get_bone_name(bone_index) != second.get_bone_name(bone_index):
			return false
		maximum_rest_error = maxf(
				maximum_rest_error,
				first.get_bone_global_rest(bone_index).origin.distance_to(
						second.get_bone_global_rest(bone_index).origin))
	print("GPU_CLOTH_SKELETON_REST_ERROR:", maximum_rest_error)
	return true


func _make_body_collider_mesh(
	source: MeshInstance3D,
	skeleton: Skeleton3D,
	parent: Node,
) -> MeshInstance3D:
	var collider := MeshInstance3D.new()
	collider.name = "BodyClothCollider"
	collider.mesh = source.mesh
	collider.visible = false
	var skin := Skin.new()
	for bone_index in skeleton.get_bone_count():
		skin.add_bind(bone_index, skeleton.get_bone_global_rest(
				bone_index).affine_inverse())
		skin.set_bind_bone(bone_index, bone_index)
		skin.set_bind_name(bone_index, skeleton.get_bone_name(bone_index))
	collider.skin = skin
	parent.add_child(collider)
	collider.global_transform = source.global_transform
	collider.skeleton = collider.get_path_to(skeleton)
	return collider


func _apply_cloth_weights(
	mesh_instance: MeshInstance3D,
	free_y: float,
	anchor_y: float,
	maximum_weight: float,
) -> void:
	var source := mesh_instance.mesh
	var rebuilt := ArrayMesh.new()
	for blend_shape_index in source.get_blend_shape_count():
		rebuilt.add_blend_shape(source.get_blend_shape_name(blend_shape_index))
	rebuilt.blend_shape_mode = source.blend_shape_mode
	for surface_index in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		for vertex_index in vertices.size():
			var unit := inverse_lerp(free_y, anchor_y, vertices[vertex_index].y)
			var weight := (1.0 - clampf(unit, 0.0, 1.0)) * maximum_weight
			colors[vertex_index] = Color(weight, 0.0, 0.0, 1.0)
		arrays[Mesh.ARRAY_COLOR] = colors
		var format: int = (
				source.surface_get_format(surface_index) | Mesh.ARRAY_FORMAT_COLOR)
		rebuilt.add_surface_from_arrays(
				source.surface_get_primitive_type(surface_index),
				arrays,
				source.surface_get_blend_shape_arrays(surface_index),
				{},
				format)
		rebuilt.surface_set_material(
				surface_index, source.surface_get_material(surface_index))
		rebuilt.surface_set_name(surface_index, source.surface_get_name(surface_index))
	mesh_instance.mesh = rebuilt


func _add_peer_solvers(
	shirt_mesh: MeshInstance3D,
	pants_mesh: MeshInstance3D,
	body_mesh: MeshInstance3D,
	skeleton: Skeleton3D,
) -> void:
	var solver_root := Node3D.new()
	solver_root.name = "GPUClothSolvers"
	var shirt_solver := _make_solver(
			"ShirtCloth", shirt_mesh, body_mesh, skeleton)
	var pants_solver := _make_solver(
			"PantsCloth", pants_mesh, body_mesh, skeleton)
	pants_solver.max_travel_distance = 0.008
	pants_solver.stiffness = 0.98
	pants_solver.bend_stiffness = 0.9
	shirt_solver.peer_cloth_solvers = [NodePath("../PantsCloth")]
	pants_solver.peer_cloth_solvers = [NodePath("../ShirtCloth")]
	solver_root.add_child(shirt_solver)
	solver_root.add_child(pants_solver)
	_creator.add_child(solver_root)


func _make_solver(
	solver_name: String,
	target: MeshInstance3D,
	body: MeshInstance3D,
	skeleton: Skeleton3D,
) -> GPUClothSolver:
	var solver := GPUClothSolver.new()
	solver.name = solver_name
	solver.target_mesh = target.get_path()
	solver.skeleton = skeleton.get_path()
	solver.body_mesh = body.get_path()
	solver.solver_iterations = 4
	solver.substeps = 2
	solver.stiffness = 0.9
	solver.bend_stiffness = 0.65
	solver.damping = 0.96
	solver.max_travel_distance = 0.035
	solver.cloth_skin_offset = 0.003
	solver.body_collider_voxel_resolution = 12
	solver.body_collider_thickness = 0.006
	solver.peer_collider_voxel_resolution = 8
	solver.collider_friction = 0.5
	return solver


func _argument_value(key: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="):
			return argument.trim_prefix(key + "=")
	return ""
