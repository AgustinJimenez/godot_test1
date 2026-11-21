extends SceneTree
## Headless check of the humans' rig (native HumanRig + assets/models/humans/*_rigged.glb and *_rig.json):
##   godot --headless --path . -s res://tests/manual/humans/human_rig_check.gd
## Prints HUMAN_RIG_CHECK PASS or FAIL lines and exits with a nonzero code on failure.
## What it asserts: the skeleton matches the rig data; after apply() the skin's bind poses are the inverse of the bones' new global rests; every joint of the
## skeleton sits inside the shaped body (near its surface) at every extreme, so the bones really followed the blend shapes; a bone turned from the rest pose
## moves the vertices skinned to it (the skin works); the rig does not share its skin with another rig made from the same glb.

const RIGS: Dictionary = {
	"male": ["res://assets/models/humans/male_rigged.glb", "res://assets/models/humans/male_rig.json"],
	"female": ["res://assets/models/humans/female_rigged.glb", "res://assets/models/humans/female_rig.json"],
}
const SHAPES: Array[StringName] = [&"height_short", &"height_tall", &"weight_light", &"weight_heavy", &"muscle_low", &"muscle_high"]

var _failures: int = 0


func _init() -> void:
	if not ClassDB.class_exists(&"HumanRig"):
		_fail("HumanRig is not registered (is the native library built?)")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	for gender: String in RIGS:
		await _check(gender)
	print("HUMAN_RIG_CHECK PASS" if _failures == 0 else "HUMAN_RIG_CHECK FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(gender: String) -> void:
	var root: Node = (load(RIGS[gender][0]) as PackedScene).instantiate()
	get_root().add_child(root)
	var skeleton: Skeleton3D = _find(root, "Skeleton3D") as Skeleton3D
	var mesh: MeshInstance3D = _find(root, "MeshInstance3D") as MeshInstance3D
	if skeleton == null or mesh == null or mesh.skin == null:
		_fail("%s: no skeleton or skinned mesh in the rigged glb" % gender)
		root.free()
		return
	var data: Dictionary = HumanRig.load_data(RIGS[gender][1])
	_expect(not data.is_empty(), "%s: the rig data did not load" % gender)
	var rig := HumanRig.new()
	_expect(rig.setup(skeleton, [mesh], data), "%s: setup failed" % gender)
	_expect(rig.get_base_error() < 0.001, "%s: the skeleton is %.4f m off the rig data" % [gender, rig.get_base_error()])
	_expect(skeleton.get_bone_count() == 52 and rig.get_bone_count() == 52, "%s: %d bones, 52 expected" % [gender, skeleton.get_bone_count()])
	var array_mesh: ArrayMesh = mesh.mesh as ArrayMesh
	var arrays: Array = array_mesh.surface_get_arrays(0)
	var base_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shapes: Array = array_mesh.surface_get_blend_shape_arrays(0)
	var normalized: bool = array_mesh.get_blend_shape_mode() == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var hips: int = skeleton.find_bone("mixamorig_Hips")
	var base_hips: Vector3 = skeleton.get_bone_global_rest(hips).origin
	# the skin is this rig's own: a second rig made from the same scene must not move this one's binds
	var other_root: Node = (load(RIGS[gender][0]) as PackedScene).instantiate()
	var other := HumanRig.new()
	var other_skeleton: Skeleton3D = _find(other_root, "Skeleton3D") as Skeleton3D
	var other_mesh: MeshInstance3D = _find(other_root, "MeshInstance3D") as MeshInstance3D
	other.setup(other_skeleton, [other_mesh], data)
	_expect(other_mesh.skin != mesh.skin, "%s: two rigs share one skin" % gender)
	other_root.free()
	var worst_joint: float = 0.0
	var line: String = ""
	for shape: StringName in SHAPES:
		var weights: Dictionary = {shape: 1.0}
		rig.apply(weights)
		# the skin's bind poses are the inverse of the new global rests
		var worst_bind: float = 0.0
		for b: int in mesh.skin.get_bind_count():
			var bone: int = skeleton.find_bone(mesh.skin.get_bind_name(b))
			var expected: Transform3D = skeleton.get_bone_global_rest(bone).affine_inverse()
			worst_bind = maxf(worst_bind, (expected.origin - mesh.skin.get_bind_pose(b).origin).length())
		_expect(worst_bind < 0.0001, "%s %s: a bind pose is %.5f m off the inverse of its bone's rest" % [gender, shape, worst_bind])
		# the joints are inside the shaped body: the shaped vertices, this shape at weight 1
		var shaped: PackedVector3Array = base_vertices.duplicate()
		var shape_index: int = SHAPES.find(shape)
		var positions: PackedVector3Array = (shapes[shape_index] as Array)[Mesh.ARRAY_VERTEX]
		for i: int in shaped.size():
			shaped[i] = positions[i] if normalized else base_vertices[i] + positions[i]
		var farthest: float = 0.0
		for bone: int in skeleton.get_bone_count():
			var origin: Vector3 = skeleton.get_bone_global_rest(bone).origin
			var nearest: float = INF
			for v: Vector3 in shaped:
				nearest = minf(nearest, origin.distance_squared_to(v))
			farthest = maxf(farthest, sqrt(nearest))
		worst_joint = maxf(worst_joint, farthest)
		line += " %s: joint %.3f m from the body, hips %+.3f;" % [shape, farthest, skeleton.get_bone_global_rest(hips).origin.y - base_hips.y]
		_expect(farthest < 0.16, "%s %s: a joint is %.3f m from the shaped body (the bones did not follow the shape)" % [gender, shape, farthest])
	rig.apply({})
	_expect(skeleton.get_bone_global_rest(hips).origin.distance_to(base_hips) < 0.0001, "%s: apply({}) did not go back to the base rig" % gender)
	# a bone turned from the rest pose moves the vertices skinned to it, and only about as far as the arm is long
	var arm: int = skeleton.find_bone("mixamorig_LeftArm")
	skeleton.set_bone_pose_rotation(arm, Quaternion(Vector3.FORWARD, deg_to_rad(60.0)))
	await process_frame # (the skeleton applies a pose at the end of the frame)
	var skin_transforms: Array[Transform3D] = []
	for b: int in mesh.skin.get_bind_count():
		skin_transforms.append(skeleton.get_bone_global_pose(skeleton.find_bone(mesh.skin.get_bind_name(b))) * mesh.skin.get_bind_pose(b))
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_array: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / base_vertices.size()
	var moved_far: int = 0
	var moved_wrong: int = 0
	for i: int in range(0, base_vertices.size(), 7):
		var skinned := Vector3.ZERO
		for k: int in stride:
			var weight: float = weights_array[i * stride + k]
			if weight > 0.0:
				skinned += (skin_transforms[bones[i * stride + k]] * base_vertices[i]) * weight
		var moved: float = skinned.distance_to(base_vertices[i])
		if moved > 0.05:
			moved_far += 1
		if moved > 0.9:
			moved_wrong += 1
	_expect(moved_far > 100, "%s: turning the arm moved only %d vertices (the skin does not work)" % [gender, moved_far])
	_expect(moved_wrong == 0, "%s: turning the arm threw %d vertices more than 0.9 m" % [gender, moved_wrong])
	# the underwear takes the body's weights (every vertex has bones and weights that add up to 1), the eyes follow the head bone rigidly
	var base: String = "res://assets/models/humans/%s_" % gender
	var underwear: MeshInstance3D = _take_mesh(base + "underwear.glb")
	_expect(HumanRig.attach_skinned(underwear, mesh, skeleton), "%s: attach_skinned failed" % gender)
	var cloth_arrays: Array = (underwear.mesh as ArrayMesh).surface_get_arrays(0)
	var cloth_vertices: PackedVector3Array = cloth_arrays[Mesh.ARRAY_VERTEX]
	var cloth_weights: PackedFloat32Array = cloth_arrays[Mesh.ARRAY_WEIGHTS]
	var cloth_bones: PackedInt32Array = cloth_arrays[Mesh.ARRAY_BONES]
	_expect(cloth_bones.size() == cloth_vertices.size() * 4 and cloth_weights.size() == cloth_bones.size(), "%s: the underwear has %d bone slots for %d vertices" % [gender, cloth_bones.size(), cloth_vertices.size()])
	var worst_sum: float = 0.0
	for i: int in cloth_vertices.size():
		var total: float = cloth_weights[i * 4] + cloth_weights[i * 4 + 1] + cloth_weights[i * 4 + 2] + cloth_weights[i * 4 + 3]
		worst_sum = maxf(worst_sum, absf(total - 1.0))
	_expect(worst_sum < 0.01, "%s: underwear weights do not add up to 1 (off by %.3f)" % [gender, worst_sum])
	_expect(underwear.get_parent() == skeleton and underwear.skin != null and underwear.skin != mesh.skin, "%s: the underwear is not under the skeleton with a skin of its own" % gender)
	var eyes: MeshInstance3D = _take_mesh(base + "eyes.glb")
	_expect(HumanRig.attach_rigid(eyes, skeleton, &"mixamorig_Head"), "%s: attach_rigid failed" % gender)
	var head: int = skeleton.find_bone("mixamorig_Head")
	rig.apply({})
	skeleton.reset_bone_poses()
	skeleton.set_bone_pose_rotation(head, skeleton.get_bone_rest(head).basis.get_rotation_quaternion() * Quaternion(Vector3.UP, deg_to_rad(40.0)))
	await process_frame
	var head_move: Transform3D = skeleton.get_bone_global_pose(head) * eyes.skin.get_bind_pose(0)
	var eye_vertices: PackedVector3Array = (eyes.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var eye_shift: float = 0.0
	for v: Vector3 in eye_vertices:
		eye_shift = maxf(eye_shift, (head_move * v).distance_to(v))
	_expect(eye_shift > 0.02, "%s: turning the head moved the eyes only %.3f m" % [gender, eye_shift])
	underwear.free()
	# the eyes (and hair) are skinned meshes: Godot sizes them from the base vertices, so the box must hold every shape (at Height +1 the head is 0.42 m higher)
	var eye_shapes: Array = (eyes.mesh as ArrayMesh).surface_get_blend_shape_arrays(0)
	var eye_top: float = -INF
	for shape: Array in eye_shapes:
		for p: Vector3 in (shape[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			eye_top = maxf(eye_top, p.y)
	_expect(eyes.custom_aabb.end.y >= eye_top - 0.001, "%s: the eyes' custom box ends at %.3f, below the tall-shape top %.3f" % [gender, eyes.custom_aabb.end.y, eye_top])
	eyes.free()
	# a hair attached AFTER setup and apply is adopted: its bind poses follow the next apply (without adopt the head bone and its blend shape both moved it)
	rig.apply({})
	skeleton.reset_bone_poses()
	var tall: Dictionary = {&"height_tall": 0.6}
	rig.apply(tall)
	var hair := MeshInstance3D.new()
	hair.mesh = HumanHair.build(mesh.mesh as ArrayMesh, HumanHair.default_params_for(gender))
	skeleton.add_child(hair)
	_expect(HumanRig.attach_rigid(hair, skeleton, &"mixamorig_Head"), "%s: attach_rigid of the hair failed" % gender)
	_expect(rig.adopt(hair), "%s: adopt failed" % gender)
	rig.apply({&"height_tall": 0.3})
	var head_bone: int = skeleton.find_bone("mixamorig_Head")
	var bind_error: float = (skeleton.get_bone_global_rest(head_bone).affine_inverse().origin - hair.skin.get_bind_pose(0).origin).length()
	_expect(bind_error < 0.0001, "%s: an adopted hair's bind pose is %.4f m off after the next apply" % [gender, bind_error])
	# setup may be called again on a skeleton apply() has moved
	var again := HumanRig.new()
	_expect(again.setup(skeleton, [mesh], data), "%s: setup again on a moved skeleton failed (base error %.4f)" % [gender, again.get_base_error()])
	hair.free()
	print("%s:%s %d vertices moved by a turned arm" % [gender, line, moved_far])
	root.free()


# The mesh instance of a glb, taken out of its scene.
func _take_mesh(path: String) -> MeshInstance3D:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var found: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	found.get_parent().remove_child(found)
	scene.free()
	return found


func _find(node: Node, type: String) -> Node:
	if node.get_class() == type:
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, type)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	print("HUMAN_RIG_CHECK failed: ", message)
