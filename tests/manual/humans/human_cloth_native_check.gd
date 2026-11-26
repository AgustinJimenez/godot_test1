extends SceneTree
## Native contact keeps shared elbow weights, body shapes and outward winding.

var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vertices := PackedVector3Array([
		Vector3.ZERO, Vector3.RIGHT, Vector3.UP,
		Vector3(0, 2, 0), Vector3(1, 2, 0), Vector3(0, 3, 0),
	])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in 6:
		bones.append_array(PackedInt32Array([0, 1, 2, 0] if i < 3 else [2, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([0.5, 0.5, 0.0, 0.0] if i < 3 \
			else [1.0, 0.0, 0.0, 0.0]))
	var moved: PackedVector3Array = vertices.duplicate()
	for i in moved.size():
		moved[i] += Vector3(0, 0, 1)
	var data: Dictionary = {
		"vertices": vertices, "indices": PackedInt32Array([0, 1, 2, 3, 4, 5]),
		"bones": bones, "weights": weights,
		"bind_poses": [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, 0)),
			Transform3D.IDENTITY],
		"bind_to_bone": PackedInt32Array([0, 1, 2]),
		"bone_names": PackedStringArray(["mixamorig_LeftArm", "mixamorig_LeftForeArm", "Hips"]),
		"shape_vertices": [moved], "shape_weights": PackedFloat32Array([0.5]),
	}
	var prepared: Dictionary = HumanRig.prepare_cloth_arms(data)
	_expect((prepared.get("indices", PackedInt32Array()) as PackedInt32Array).size() == 3,
		"retain the elbow triangle; exclude the torso")
	var poses: Array = [Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(3.5, 0, 0)), Transform3D.IDENTITY]
	var packed: PackedByteArray = HumanRig.skin_cloth_arms(prepared, poses)
	_expect(packed.size() == 48, "one triangle of three vec4s")
	if packed.size() == 48:
		var output: PackedFloat32Array = packed.to_float32_array()
		var expected: Array[Vector3] = [Vector3(2, 0, 0.5), Vector3(2, 1, 0.5),
			Vector3(3, 0, 0.5)]
		for i in 3:
			var point := Vector3(output[i * 4], output[i * 4 + 1], output[i * 4 + 2])
			_expect(point.distance_to(expected[i]) < 0.00001,
				"weighted binds, shape and outward order at vertex %d" % i)
	var thread := Thread.new()
	var error: Error = thread.start(func() -> PackedByteArray:
		return HumanRig.skin_cloth_arms(HumanRig.prepare_cloth_arms(data), poses))
	_expect(error == OK, "start worker")
	if error == OK:
		_expect((thread.wait_to_finish() as PackedByteArray) == packed, "pure worker result")
	data["indices"] = PackedInt32Array([0, 1, 999])
	_expect(HumanRig.prepare_cloth_arms(data).is_empty(), "reject invalid indices")
	_expect(HumanRig.skin_cloth_arms({}, []).is_empty(), "empty input")
	prepared["indices"] = PackedInt32Array([0, 1])
	_expect(HumanRig.skin_cloth_arms(prepared, poses).is_empty(), "reject partial triangles")
	if not _failed:
		print("HUMAN_CLOTH_NATIVE_CHECK PASS: split weights, shapes, winding, worker, invalid data")
	quit(1 if _failed else 0)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		print("HUMAN_CLOTH_NATIVE_CHECK FAIL: ", message)
