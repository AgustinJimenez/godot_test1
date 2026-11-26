#include "human_rig_native.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>

namespace godot {

namespace {

// "mixamorig:Hips" (Blender) and "mixamorig_Hips" (what the Godot importer makes of it) are the same bone.
int find_bone_named(const Skeleton3D *p_skeleton, const String &p_name) {
	int found = p_skeleton->find_bone(p_name);
	if (found < 0) {
		found = p_skeleton->find_bone(p_name.replace(":", "_"));
	}
	return found;
}

// The mesh again with these bones and weights (blend shapes, material and everything else kept).
Ref<ArrayMesh> with_skin(const Ref<ArrayMesh> &p_mesh, const PackedInt32Array &p_bones, const PackedFloat32Array &p_weights) {
	Ref<ArrayMesh> result;
	if (p_mesh.is_null() || p_mesh->get_surface_count() < 1) {
		return result;
	}
	Array arrays = p_mesh->surface_get_arrays(0);
	arrays[Mesh::ARRAY_BONES] = p_bones;
	arrays[Mesh::ARRAY_WEIGHTS] = p_weights;
	Array shapes = p_mesh->surface_get_blend_shape_arrays(0);
	result.instantiate();
	for (int i = 0; i < p_mesh->get_blend_shape_count(); i++) {
		result->add_blend_shape(p_mesh->get_blend_shape_name(i));
	}
	result->set_blend_shape_mode(p_mesh->get_blend_shape_mode());
	// The custom channels keep their format: an array in CUSTOM0 (the hair's guide data, a float RGBA) is refused ("Invalid array format for surface") and the surface is
	// not made at all when the flags say nothing about it (the hair could not be attached to the rig).
	const uint64_t source_format = p_mesh->surface_get_format(0);
	uint64_t flags = 0;
	const uint64_t shifts[4] = { Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT, Mesh::ARRAY_FORMAT_CUSTOM1_SHIFT, Mesh::ARRAY_FORMAT_CUSTOM2_SHIFT, Mesh::ARRAY_FORMAT_CUSTOM3_SHIFT };
	for (int c = 0; c < 4; c++) {
		flags |= ((source_format >> shifts[c]) & uint64_t(Mesh::ARRAY_FORMAT_CUSTOM_MASK)) << shifts[c];
	}
	result->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, shapes, Dictionary(), flags);
	if (result->get_surface_count() < 1) {
		return Ref<ArrayMesh>(); // (the callers return false instead of leaving the instance with an empty mesh)
	}
	result->surface_set_material(0, p_mesh->surface_get_material(0));
	// what the hair carries as meta (hair_guides, hair_scalp_weight: the simulation and the scalp darkening read them from the mesh)
	PackedStringArray metas = p_mesh->get_meta_list();
	for (int m = 0; m < metas.size(); m++) {
		result->set_meta(StringName(metas[m]), p_mesh->get_meta(StringName(metas[m])));
	}
	return result;
}

// Godot sizes a skinned mesh from its bones and the base vertices, ignoring the blend shapes: at Height +1 the head is drawn 0.42 m above that box and is culled
// when only the tall head is in view (or in a shadow cascade). The box of the base AND of every shape, plus room for the pose, goes on the instance.
AABB shaped_bounds(const Ref<ArrayMesh> &p_mesh, double p_margin) {
	AABB box;
	if (p_mesh.is_null() || p_mesh->get_surface_count() < 1) {
		return box;
	}
	Array arrays = p_mesh->surface_get_arrays(0);
	PackedVector3Array base = arrays[Mesh::ARRAY_VERTEX];
	if (base.is_empty()) {
		return box;
	}
	box = AABB(base[0], Vector3());
	for (int i = 0; i < base.size(); i++) {
		box.expand_to(base[i]);
	}
	const bool normalized = p_mesh->get_blend_shape_mode() == Mesh::BLEND_SHAPE_MODE_NORMALIZED;
	Array shapes = p_mesh->surface_get_blend_shape_arrays(0);
	for (int s = 0; s < shapes.size(); s++) {
		Array shape = shapes[s];
		PackedVector3Array positions = shape[Mesh::ARRAY_VERTEX];
		for (int i = 0; i < positions.size() && i < base.size(); i++) {
			box.expand_to(normalized ? positions[i] : base[i] + positions[i]);
		}
	}
	return box.grow(real_t(p_margin));
}

Ref<ArrayMesh> array_mesh_of(const MeshInstance3D *p_instance) {
	Ref<ArrayMesh> mesh;
	if (p_instance != nullptr) {
		mesh = Ref<ArrayMesh>(Object::cast_to<ArrayMesh>(p_instance->get_mesh().ptr()));
	}
	return mesh;
}

void move_under(Node *p_node, Node *p_parent) {
	if (p_node->get_parent() != nullptr) {
		p_node->get_parent()->remove_child(p_node);
	}
	p_parent->add_child(p_node);
}

Vector3 vector_of(const Variant &p_value) {
	Array a = p_value;
	if (a.size() < 3) {
		return Vector3();
	}
	return Vector3(real_t(double(a[0])), real_t(double(a[1])), real_t(double(a[2])));
}

} // namespace

void HumanRig::_bind_methods() {
	ClassDB::bind_static_method("HumanRig", D_METHOD("prepare_cloth_arms", "data"), &HumanRig::prepare_cloth_arms);
	ClassDB::bind_static_method("HumanRig", D_METHOD("skin_cloth_arms", "data", "poses"), &HumanRig::skin_cloth_arms);
	ClassDB::bind_static_method("HumanRig", D_METHOD("load_data", "path"), &HumanRig::load_data);
	ClassDB::bind_static_method("HumanRig", D_METHOD("shape_weights", "height", "weight", "muscle"), &HumanRig::shape_weights);
	ClassDB::bind_static_method("HumanRig", D_METHOD("skin_to_bone", "mesh"), &HumanRig::skin_to_bone);
	ClassDB::bind_static_method("HumanRig", D_METHOD("transfer_skin", "cloth", "body"), &HumanRig::transfer_skin);
	ClassDB::bind_static_method("HumanRig", D_METHOD("attach_rigid", "mesh", "skeleton", "bone"), &HumanRig::attach_rigid);
	ClassDB::bind_static_method("HumanRig", D_METHOD("attach_skinned", "cloth", "body", "skeleton"), &HumanRig::attach_skinned);
	ClassDB::bind_method(D_METHOD("setup", "skeleton", "meshes", "data"), &HumanRig::setup);
	ClassDB::bind_method(D_METHOD("apply", "weights"), &HumanRig::apply);
	ClassDB::bind_method(D_METHOD("adopt", "mesh"), &HumanRig::adopt);
	ClassDB::bind_method(D_METHOD("get_base_error"), &HumanRig::get_base_error);
	ClassDB::bind_method(D_METHOD("get_bone_count"), &HumanRig::get_bone_count);
	ClassDB::bind_method(D_METHOD("bone_origin", "bone"), &HumanRig::bone_origin);
}

Ref<ArrayMesh> HumanRig::skin_to_bone(const Ref<ArrayMesh> &p_mesh) {
	if (p_mesh.is_null() || p_mesh->get_surface_count() < 1) {
		return Ref<ArrayMesh>();
	}
	Array arrays = p_mesh->surface_get_arrays(0);
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	PackedInt32Array bones;
	PackedFloat32Array weights;
	bones.resize(vertices.size() * 4);
	weights.resize(vertices.size() * 4);
	bones.fill(0);
	weights.fill(0.0f);
	for (int i = 0; i < vertices.size(); i++) {
		weights.ptrw()[i * 4] = 1.0f;
	}
	return with_skin(p_mesh, bones, weights);
}

Ref<ArrayMesh> HumanRig::transfer_skin(const Ref<ArrayMesh> &p_cloth, const Ref<ArrayMesh> &p_body) {
	if (p_cloth.is_null() || p_body.is_null() || p_cloth->get_surface_count() < 1 || p_body->get_surface_count() < 1) {
		return Ref<ArrayMesh>();
	}
	Array cloth_arrays = p_cloth->surface_get_arrays(0);
	Array body_arrays = p_body->surface_get_arrays(0);
	PackedVector3Array cloth_vertices = cloth_arrays[Mesh::ARRAY_VERTEX];
	PackedVector3Array body_vertices = body_arrays[Mesh::ARRAY_VERTEX];
	PackedInt32Array body_bones = body_arrays[Mesh::ARRAY_BONES];
	PackedFloat32Array body_weights = body_arrays[Mesh::ARRAY_WEIGHTS];
	const int body_count = body_vertices.size();
	if (body_count == 0 || body_bones.size() % body_count != 0 || body_bones.size() != body_weights.size()) {
		return Ref<ArrayMesh>();
	}
	if (body_bones.size() / body_count != 4) {
		return Ref<ArrayMesh>(); // (a 4-bone mesh: the format flag for 8 bones is not set here)
	}
	// the body's vertices in a grid, to find the nearest one of each vertex of the cloth
	const double cell = 0.03;
	auto key = [](int x, int y, int z) { return (int64_t(x + 4096) << 40) ^ (int64_t(y + 4096) << 20) ^ int64_t(z + 4096); };
	std::unordered_map<int64_t, std::vector<int>> cells;
	for (int i = 0; i < body_count; i++) {
		const Vector3 v = body_vertices[i];
		cells[key(int(std::floor(v.x / cell)), int(std::floor(v.y / cell)), int(std::floor(v.z / cell)))].push_back(i);
	}
	const int cloth_count = cloth_vertices.size();
	PackedInt32Array bones;
	PackedFloat32Array weights;
	bones.resize(cloth_count * 4);
	weights.resize(cloth_count * 4);
	for (int i = 0; i < cloth_count; i++) {
		const Vector3 v = cloth_vertices[i];
		const int cx = int(std::floor(v.x / cell)), cy = int(std::floor(v.y / cell)), cz = int(std::floor(v.z / cell));
		int best = -1;
		double best_distance = 1e18;
		for (int ring = 1; ring <= 6 && best < 0; ring++) { // widen the search until something is found
			for (int x = cx - ring; x <= cx + ring; x++) {
				for (int y = cy - ring; y <= cy + ring; y++) {
					for (int z = cz - ring; z <= cz + ring; z++) {
						auto found = cells.find(key(x, y, z));
						if (found == cells.end()) {
							continue;
						}
						for (int index : found->second) {
							const double d = double(body_vertices[index].distance_squared_to(v));
							if (d < best_distance) {
								best_distance = d;
								best = index;
							}
						}
					}
				}
			}
		}
		if (best < 0) {
			best = 0;
		}
		for (int k = 0; k < 4; k++) {
			bones.ptrw()[i * 4 + k] = body_bones[best * 4 + k];
			weights.ptrw()[i * 4 + k] = body_weights[best * 4 + k];
		}
	}
	return with_skin(p_cloth, bones, weights);
}

bool HumanRig::attach_rigid(MeshInstance3D *p_mesh, Skeleton3D *p_skeleton, const StringName &p_bone) {
	if (p_mesh == nullptr || p_skeleton == nullptr) {
		return false;
	}
	const int bone = find_bone_named(p_skeleton, String(p_bone));
	Ref<ArrayMesh> source = array_mesh_of(p_mesh);
	if (bone < 0 || source.is_null()) {
		return false;
	}
	Ref<ArrayMesh> skinned = skin_to_bone(source);
	if (skinned.is_null()) {
		return false;
	}
	Ref<Skin> skin;
	skin.instantiate();
	skin->add_named_bind(p_skeleton->get_bone_name(bone), p_skeleton->get_bone_global_rest(bone).affine_inverse());
	p_mesh->set_mesh(skinned);
	p_mesh->set_custom_aabb(shaped_bounds(skinned, 0.4));
	p_mesh->set_skin(skin);
	move_under(p_mesh, p_skeleton);
	p_mesh->set_transform(Transform3D());
	p_mesh->set_skeleton_path(NodePath(".."));
	return true;
}

bool HumanRig::attach_skinned(MeshInstance3D *p_cloth, MeshInstance3D *p_body, Skeleton3D *p_skeleton) {
	if (p_cloth == nullptr || p_body == nullptr || p_skeleton == nullptr || p_body->get_skin().is_null()) {
		return false;
	}
	Ref<ArrayMesh> skinned = transfer_skin(array_mesh_of(p_cloth), array_mesh_of(p_body));
	if (skinned.is_null()) {
		return false;
	}
	Ref<Skin> body_skin = p_body->get_skin();
	Ref<Skin> skin;
	skin.instantiate();
	for (int b = 0; b < body_skin->get_bind_count(); b++) {
		skin->add_named_bind(body_skin->get_bind_name(b), body_skin->get_bind_pose(b));
	}
	p_cloth->set_mesh(skinned);
	p_cloth->set_custom_aabb(shaped_bounds(skinned, 0.4));
	p_cloth->set_skin(skin);
	move_under(p_cloth, p_skeleton);
	p_cloth->set_transform(Transform3D());
	p_cloth->set_skeleton_path(NodePath(".."));
	return true;
}

Dictionary HumanRig::shape_weights(double p_height, double p_weight, double p_muscle) {
	// (gain_heavy 1.0: weight_heavy is built heavy in Blender now, tools/blender/heavy_mix.py; it was MakeHuman's mild max-weight pushed to 3.0, which made lumps)
	const double height_range = 0.6, gain_heavy = 1.0, gain_light = 1.25, muscle_high = 2.0, muscle_low = 1.25;
	Dictionary weights;
	weights[StringName("height_tall")] = std::max(p_height, 0.0) * height_range;
	weights[StringName("height_short")] = std::max(-p_height, 0.0) * height_range;
	weights[StringName("weight_heavy")] = std::max(p_weight, 0.0) * gain_heavy;
	weights[StringName("weight_light")] = std::max(-p_weight, 0.0) * gain_light;
	weights[StringName("muscle_high")] = std::max(p_muscle, 0.0) * muscle_high;
	weights[StringName("muscle_low")] = std::max(-p_muscle, 0.0) * muscle_low;
	return weights;
}

Dictionary HumanRig::load_data(const String &p_path) {
	const String text = FileAccess::get_file_as_string(p_path);
	if (text.is_empty()) {
		return Dictionary();
	}
	const Variant parsed = JSON::parse_string(text);
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
}

bool HumanRig::setup(Skeleton3D *p_skeleton, const Array &p_meshes, const Dictionary &p_data) {
	skeleton_id = ObjectID();
	base_global.clear();
	parent.clear();
	order.clear();
	shape_head.clear();
	skins.clear();
	base_error = 0.0;
	if (p_skeleton == nullptr || !p_data.has("bones") || !p_data.has("head") || !p_data.has("shapes")) {
		return false;
	}
	const int count = p_skeleton->get_bone_count();
	Array names = p_data["bones"];
	Array heads = p_data["head"];
	Dictionary shapes = p_data["shapes"];
	if (names.size() != heads.size() || count == 0) {
		return false;
	}
	// the skeleton as imported: global rests and parents. A skeleton set up before (and moved by apply() since) keeps its imported rests in its meta.
	base_global.resize(count);
	parent.resize(count);
	const StringName base_meta("human_rig_base_rest");
	Array stored = p_skeleton->has_meta(base_meta) ? Array(p_skeleton->get_meta(base_meta)) : Array();
	const bool known = stored.size() == count;
	for (int i = 0; i < count; i++) {
		base_global[i] = known ? Transform3D(stored[i]) : p_skeleton->get_bone_global_rest(i);
		parent[i] = p_skeleton->get_bone_parent(i);
	}
	if (!known) {
		Array to_store;
		for (int i = 0; i < count; i++) {
			to_store.push_back(base_global[i]);
		}
		p_skeleton->set_meta(base_meta, to_store);
	}
	// bones parents first (the importer lists them that way, but do not rely on it)
	std::vector<char> done(count, 0);
	order.reserve(count);
	while (int(order.size()) < count) {
		const size_t before = order.size();
		for (int i = 0; i < count; i++) {
			if (!done[i] && (parent[i] < 0 || done[parent[i]])) {
				order.push_back(i);
				done[i] = 1;
			}
		}
		if (order.size() == before) {
			return false; // a loop in the hierarchy
		}
	}
	// the data's bones by skeleton index
	std::vector<int> index_of(names.size(), -1);
	for (int n = 0; n < names.size(); n++) {
		index_of[n] = find_bone_named(p_skeleton, String(names[n]));
		if (index_of[n] < 0) {
			UtilityFunctions::push_warning("HumanRig: the skeleton has no bone ", String(names[n]));
			return false;
		}
		const Vector3 head = vector_of(heads[n]);
		base_error = std::max(base_error, double((base_global[index_of[n]].origin - head).length()));
	}
	if (base_error > 0.001) {
		UtilityFunctions::push_warning("HumanRig: the skeleton does not match the rig data (largest head difference ", base_error, " m)");
		return false;
	}
	Array shape_names = shapes.keys();
	for (int s = 0; s < shape_names.size(); s++) {
		Dictionary shape = shapes[shape_names[s]];
		Array shape_heads = shape["head"];
		std::vector<Vector3> moves(count);
		for (int n = 0; n < names.size() && n < shape_heads.size(); n++) {
			moves[index_of[n]] = vector_of(shape_heads[n]);
		}
		shape_head[std::string(String(shape_names[s]).utf8().get_data())] = std::move(moves);
	}
	// the skins: this rig's own copy of each, so characters made from the same glb do not share bind poses
	skeleton_id = p_skeleton->get_instance_id();
	for (int m = 0; m < p_meshes.size(); m++) {
		add_skin(p_skeleton, Object::cast_to<MeshInstance3D>(p_meshes[m]));
	}
	refresh_skins(); // (a skeleton moved by an earlier apply(): the binds of these meshes are the inverse of where its bones are now)
	return true;
}

void HumanRig::add_skin(Skeleton3D *p_skeleton, MeshInstance3D *p_mesh) {
	if (p_mesh == nullptr || p_mesh->get_skin().is_null()) {
		return;
	}
	for (const SkinUse &known : skins) {
		if (uint64_t(known.mesh) == p_mesh->get_instance_id()) {
			return;
		}
	}
	Ref<Skin> original = p_mesh->get_skin();
	SkinUse use;
	use.mesh = p_mesh->get_instance_id();
	use.skin.instantiate();
	for (int b = 0; b < original->get_bind_count(); b++) {
		const String name = original->get_bind_name(b);
		const int bone = name.is_empty() ? original->get_bind_bone(b) : find_bone_named(p_skeleton, name);
		use.bone_of_bind.push_back(bone);
		use.skin->add_named_bind(name, original->get_bind_pose(b));
	}
	p_mesh->set_skin(use.skin);
	skins.push_back(use);
}

void HumanRig::refresh_skins() {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	if (skeleton == nullptr) {
		return;
	}
	const int count = skeleton->get_bone_count();
	for (SkinUse &use : skins) {
		for (int b = 0; b < int(use.bone_of_bind.size()); b++) {
			const int bone = use.bone_of_bind[b];
			if (use.skin.is_valid() && bone >= 0 && bone < count) {
				use.skin->set_bind_pose(b, skeleton->get_bone_global_rest(bone).affine_inverse());
			}
		}
	}
}

bool HumanRig::adopt(MeshInstance3D *p_mesh) {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	if (skeleton == nullptr || p_mesh == nullptr || p_mesh->get_skin().is_null()) {
		return false;
	}
	add_skin(skeleton, p_mesh);
	refresh_skins();
	return true;
}

void HumanRig::apply(const Dictionary &p_weights) {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	if (skeleton == nullptr || base_global.empty()) {
		return;
	}
	const int count = int(base_global.size());
	std::vector<Vector3> move(count);
	Array keys = p_weights.keys();
	for (int k = 0; k < keys.size(); k++) {
		const double weight = double(p_weights[keys[k]]);
		if (weight == 0.0) {
			continue;
		}
		auto found = shape_head.find(std::string(String(keys[k]).utf8().get_data()));
		if (found == shape_head.end()) {
			continue;
		}
		for (int i = 0; i < count; i++) {
			move[i] += found->second[i] * real_t(weight);
		}
	}
	// the new global rests (the base orientation, the moved origin), then the local rests from them, parents first
	std::vector<Transform3D> global(count);
	for (int i = 0; i < count; i++) {
		global[i] = Transform3D(base_global[i].basis, base_global[i].origin + move[i]);
	}
	for (int i : order) {
		const Transform3D local = parent[i] >= 0 ? global[parent[i]].affine_inverse() * global[i] : global[i];
		skeleton->set_bone_rest(i, local);
	}
	skeleton->reset_bone_poses(); // the pose is the rest again (an animation or an IK rewrites it every frame)
	for (SkinUse &use : skins) {
		if (use.skin.is_null()) {
			continue;
		}
		for (int b = 0; b < int(use.bone_of_bind.size()); b++) {
			const int bone = use.bone_of_bind[b];
			if (bone >= 0 && bone < count) {
				use.skin->set_bind_pose(b, global[bone].affine_inverse());
			}
		}
	}
}

Vector3 HumanRig::bone_origin(const StringName &p_bone) const {
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
	if (skeleton == nullptr) {
		return Vector3();
	}
	const int bone = find_bone_named(skeleton, String(p_bone));
	return bone >= 0 ? skeleton->get_bone_global_rest(bone).origin : Vector3();
}

} // namespace godot
