extends RefCounted
## Immutable-after-build sparse skin samples. No skeleton, IK state, or bone writes.
## Rebuild when mesh geometry, skin bindings, or selected vertices change.
## Pose inputs are world-space skin matrices (including inverse bind), supplied per call.

var _vertices := PackedVector3Array()
var _offsets := PackedInt32Array([0])
var _binds := PackedInt32Array()
var _weights := PackedFloat32Array()


func append_surface(vertices: PackedVector3Array, bones: PackedInt32Array,
		weights: PackedFloat32Array, selected: PackedInt32Array) -> bool:
	if vertices.is_empty() or bones.size() != weights.size() \
			or bones.size() % vertices.size() != 0:
		return false
	for index in selected:
		if index < 0 or index >= vertices.size():
			return false
	var stride := bones.size() / vertices.size()
	for index in selected:
		_vertices.append(vertices[index])
		for influence in stride:
			var slot := index * stride + influence
			if weights[slot] > 0.0 and bones[slot] >= 0:
				_binds.append(bones[slot])
				_weights.append(weights[slot])
		_offsets.append(_binds.size())
	return true


func sample(transforms: Array[Transform3D], fallback: Transform3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(_vertices.size())
	for index in _vertices.size():
		var point := Vector3.ZERO
		var total := 0.0
		for slot in range(_offsets[index], _offsets[index + 1]):
			var bind := _binds[slot]
			if bind >= transforms.size():
				continue
			var weight: float = _weights[slot]
			point += (transforms[bind] * _vertices[index]) * weight
			total += weight
		points[index] = point / total if total > 0.0 else fallback * _vertices[index]
	return points
