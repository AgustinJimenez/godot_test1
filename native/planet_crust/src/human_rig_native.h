#pragma once

// HumanRig: the skeleton of a parametric human follows the body's shape sliders (assets/models/humans/{male,female}_rigged.glb, made by tools/blender/make_rig.py).
//
// The body's blend shapes move its vertices when Height, Weight or Muscle change, but a skeleton has no blend shapes. make_rig.py fits MPFB's Mixamo rig to the body
// at every macro extreme and stores the joint moves in {male,female}_rig.json; this class applies the same slider weights to the skeleton: every bone's rest
// origin moves by the weighted sum of its stored moves (the bone's orientation stays the base one), the local rests are rebuilt from the moved globals, and the
// skin's bind poses are set to the inverse of the new global rests (skinning is world-of-bone times bind pose: with both moved together the body at rest is
// unchanged, and any pose, animation or IK deforms the mesh the blend shapes made). The skin resource is copied per HumanRig, so characters do not share one.
//
//   var rig := HumanRig.new()
//   rig.setup(skeleton, [body_mesh_instance], HumanRig.load_data("res://assets/models/humans/male_rig.json"))
//   rig.apply({&"height_tall": 0.6})        # the same weights as the body's blend shapes
//
// Bone names: Blender's "mixamorig:Hips" arrives in Godot as "mixamorig_Hips" (the importer turns the colon into an underscore); both are found.

#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <map>
#include <string>
#include <vector>

namespace godot {

class HumanRig : public RefCounted {
	GDCLASS(HumanRig, RefCounted)

	struct SkinUse {
		ObjectID mesh;
		Ref<Skin> skin; // this rig's own copy
		std::vector<int> bone_of_bind; // the skeleton bone of each bind
	};

	ObjectID skeleton_id;
	std::vector<Transform3D> base_global; // the global rest of every bone as imported
	std::vector<int> parent;
	std::vector<int> order; // bones, parents first
	std::map<std::string, std::vector<Vector3>> shape_head; // per shape, the move of every bone's head, by skeleton bone index
	std::vector<SkinUse> skins;
	double base_error = 0.0;

	void add_skin(Skeleton3D *p_skeleton, MeshInstance3D *p_mesh);
	void refresh_skins(); // every bind is the inverse of its bone's CURRENT global rest

protected:
	static void _bind_methods();

public:
	// The slider mapping every human scene uses, in one place: height, weight and muscle in -1..1 become the weights of the six blend shapes. Height -1..1 is 0.6 of a
	// full shape (a full one adds 0.70 m or takes 0.36 m: too much); weight heavy x3 and light x1.25, muscle high x2 and low x1.25 (the shapes are small; pushing a
	// light shape to x3 folded the female waist and hips).
	static Dictionary shape_weights(double p_height, double p_weight, double p_muscle);
	// Skinning the other meshes of a human to this skeleton (call these first, then pass the mesh instances to setup() so the skins follow the sliders):
	//   skin_to_bone(mesh)            a copy of the ArrayMesh (blend shapes kept) with every vertex bound to bind 0, weight 1: for what moves rigidly with a bone
	//   transfer_skin(cloth, body)    a copy of the cloth with every vertex given the bones and weights of the nearest vertex of the body (both in the base pose): clothes
	//   attach_rigid(mesh, skeleton, bone)   skin_to_bone + a one-bind skin of that bone + the instance moved under the skeleton: eyes, brows, lashes, hair on the head bone
	//   attach_skinned(cloth, body, skeleton) transfer_skin + the body skin's bind names + the instance moved under the skeleton: the underwear
	static Ref<ArrayMesh> skin_to_bone(const Ref<ArrayMesh> &p_mesh);
	static Ref<ArrayMesh> transfer_skin(const Ref<ArrayMesh> &p_cloth, const Ref<ArrayMesh> &p_body);
	static bool attach_rigid(MeshInstance3D *p_mesh, Skeleton3D *p_skeleton, const StringName &p_bone);
	static bool attach_skinned(MeshInstance3D *p_cloth, MeshInstance3D *p_body, Skeleton3D *p_skeleton);
	// The JSON written by make_rig.py as a Dictionary ({} when the file is missing or broken).
	static Dictionary load_data(const String &p_path);

	// Takes the skeleton and the mesh instances skinned to it (their skins are replaced by copies) and the rig data. May be called again later (the base rest is kept in the
	// skeleton's meta "human_rig_base_rest", so a skeleton that apply() has moved is still recognised). Returns false when a bone of the data is not in the
	// skeleton or the skeleton is not the one the data was made for (the base heads must match the skeleton's rest to a millimetre: see get_base_error()).
	bool setup(Skeleton3D *p_skeleton, const Array &p_meshes, const Dictionary &p_data);
	// A mesh attached after setup() (the hair, rebuilt for another style): it joins the rig, so its bind poses follow the next apply() too (without this the head bone and the
	// mesh's own blend shape would both move it). Its blend shapes must already carry the current weights.
	bool adopt(MeshInstance3D *p_mesh);
	// weights: shape name -> weight, the weights of the body's blend shapes (height_short, height_tall, weight_light, weight_heavy, muscle_low, muscle_high).
	void apply(const Dictionary &p_weights);
	double get_base_error() const { return base_error; } // the largest distance between a base head in the data and the skeleton's rest origin
	int64_t get_bone_count() const { return int64_t(base_global.size()); }
	// Where the bone's origin is now, in the skeleton's space (-1 index: a zero vector).
	Vector3 bone_origin(const StringName &p_bone) const;
};

} // namespace godot
