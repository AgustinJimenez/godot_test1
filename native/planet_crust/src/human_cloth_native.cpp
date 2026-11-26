#include "human_rig_native.h"

#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>

namespace godot {

Dictionary HumanRig::prepare_cloth_arms(const Dictionary &p_data) {
	Dictionary result;
	PackedVector3Array vertices = p_data.get("vertices", PackedVector3Array());
	const PackedInt32Array indices = p_data.get("indices", PackedInt32Array());
	const PackedInt32Array bones = p_data.get("bones", PackedInt32Array());
	const PackedFloat32Array weights = p_data.get("weights", PackedFloat32Array());
	const PackedInt32Array bind_to_bone = p_data.get("bind_to_bone", PackedInt32Array());
	const PackedStringArray names = p_data.get("bone_names", PackedStringArray());
	const Array binds = p_data.get("bind_poses", Array());
	if (vertices.is_empty() || indices.size() % 3 != 0 || bones.size() != vertices.size() * 4
			|| weights.size() != bones.size() || binds.size() != bind_to_bone.size()) return result;
	const Array shapes = p_data.get("shape_vertices", Array());
	const PackedFloat32Array shape_weights = p_data.get("shape_weights", PackedFloat32Array());
	if (shapes.size() != shape_weights.size()) return result;
	const bool relative = p_data.get("relative_shapes", false);
	const PackedVector3Array base = vertices;
	for (int s = 0; s < shapes.size(); ++s) {
		if (shape_weights[s] == 0.0f) continue;
		const PackedVector3Array moved = shapes[s];
		if (moved.size() != vertices.size()) return result;
		for (int i = 0; i < vertices.size(); ++i) vertices.set(i, vertices[i] + (relative ? moved[i] : moved[i] - base[i]) * shape_weights[s]);
	}
	std::vector<bool> arm_bone(names.size(), false), arm_vertex(vertices.size(), false);
	for (int i = 0; i < names.size(); ++i) {
		const String name = names[i];
		arm_bone[i] = name == "mixamorig_LeftArm" || name == "mixamorig_RightArm"
			|| name == "mixamorig_LeftForeArm" || name == "mixamorig_RightForeArm";
	}
	for (int i = 0; i < vertices.size(); ++i) {
		double arm_weight = 0.0;
		for (int k = 0; k < 4; ++k) {
			const int bind = bones[i * 4 + k];
			if (bind < 0 || bind >= bind_to_bone.size()) continue;
			const int bone = bind_to_bone[bind];
			if (bone >= 0 && bone < int(arm_bone.size()) && arm_bone[bone]) arm_weight += weights[i * 4 + k];
		}
		arm_vertex[i] = arm_weight >= 0.25;
	}
	std::vector<int> remap(vertices.size(), -1);
	PackedVector3Array local;
	PackedInt32Array skin_bones, triangles;
	PackedFloat32Array skin_weights;
	for (int i = 0; i < indices.size(); i += 3) {
		const int a = indices[i], b = indices[i + 1], c = indices[i + 2];
		if (a < 0 || b < 0 || c < 0 || a >= vertices.size() || b >= vertices.size() || c >= vertices.size()) return Dictionary();
		if (!arm_vertex[a] || !arm_vertex[b] || !arm_vertex[c]) continue;
		for (int vertex : { a, b, c }) {
			if (remap[vertex] < 0) {
				remap[vertex] = int(local.size() / 4);
				for (int k = 0; k < 4; ++k) {
					const int bind = bones[vertex * 4 + k];
					const bool valid = bind >= 0 && bind < binds.size() && bind_to_bone[bind] >= 0
						&& bind_to_bone[bind] < names.size();
					const Transform3D inverse_bind = valid ? Transform3D(binds[bind]) : Transform3D();
					local.append(inverse_bind.xform(vertices[vertex]));
					skin_bones.append(valid ? bind_to_bone[bind] : -1);
					skin_weights.append(valid ? weights[vertex * 4 + k] : 0.0f);
				}
			}
			triangles.append(remap[vertex]);
		}
	}
	result["local"] = local;
	result["bones"] = skin_bones;
	result["weights"] = skin_weights;
	result["indices"] = triangles;
	return result;
}

PackedByteArray HumanRig::skin_cloth_arms(const Dictionary &p_data, const Array &p_poses) {
	const PackedVector3Array local = p_data.get("local", PackedVector3Array());
	const PackedInt32Array bones = p_data.get("bones", PackedInt32Array());
	const PackedFloat32Array weights = p_data.get("weights", PackedFloat32Array());
	const PackedInt32Array indices = p_data.get("indices", PackedInt32Array());
	if (local.size() % 4 != 0 || bones.size() != local.size() || weights.size() != local.size()
			|| indices.size() % 3 != 0) return PackedByteArray();
	std::vector<Transform3D> poses;
	poses.reserve(p_poses.size());
	for (int i = 0; i < p_poses.size(); ++i) poses.push_back(Transform3D(p_poses[i]));
	std::vector<Vector3> skinned(local.size() / 4);
	for (int i = 0; i < int(skinned.size()); ++i) {
		for (int k = 0; k < 4; ++k) {
			const int bone = bones[i * 4 + k];
			if (bone >= 0 && bone < int(poses.size())) skinned[i] += poses[bone].xform(local[i * 4 + k]) * weights[i * 4 + k];
		}
	}
	PackedFloat32Array output;
	output.resize(indices.size() * 4);
	float *out = output.ptrw();
	for (int i = 0; i < indices.size(); ++i) {
		// Godot render triangles are clockwise; contact triangles expose an
		// outward cross-product normal for signed, one-sided body contact.
		const int source = (i / 3) * 3 + (i % 3 == 0 ? 0 : 3 - i % 3);
		if (indices[source] < 0 || indices[source] >= int(skinned.size())) return PackedByteArray();
		const Vector3 &p = skinned[indices[source]];
		out[i * 4] = float(p.x); out[i * 4 + 1] = float(p.y); out[i * 4 + 2] = float(p.z); out[i * 4 + 3] = 0.0f;
	}
	return output.to_byte_array();
}

} // namespace godot
