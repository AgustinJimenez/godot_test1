#include "foot_ik_ledge_native.h"

#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/skin_reference.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace {
const double LEDGE_DROP = 0.25; // m: ground lower than this below the body is not ground to stand on
const double LEDGE_RADII[3] = { 0.15, 0.3, 0.45 };
const int LEDGE_DIRECTIONS = 8;
const double HEEL_SOLE_BAND = 0.04; // the heel is the rearmost point within this of the lowest vertex
const double KEEP_BAND = 0.10; // vertices this near the rest sole can become the lowest point
} // namespace

// ---------------------------------------------------------------- ledge

void FootIKV2LedgeNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "owner"), &FootIKV2LedgeNative::bind);
	ClassDB::bind_method(D_METHOD("over_drop", "side", "body", "ankle", "hip"), &FootIKV2LedgeNative::over_drop);
	ClassDB::bind_method(D_METHOD("on_ground", "side"), &FootIKV2LedgeNative::on_ground);
	ClassDB::bind_method(D_METHOD("push"), &FootIKV2LedgeNative::push);
	ClassDB::bind_method(D_METHOD("set_step", "world_way", "body_basis"), &FootIKV2LedgeNative::set_step);
	ClassDB::bind_method(D_METHOD("get_stepping"), &FootIKV2LedgeNative::get_stepping);
	ClassDB::bind_method(D_METHOD("set_stepping", "stepping"), &FootIKV2LedgeNative::set_stepping);
	ClassDB::bind_method(D_METHOD("get_step_input"), &FootIKV2LedgeNative::get_step_input);
	ClassDB::bind_method(D_METHOD("set_step_input", "input"), &FootIKV2LedgeNative::set_step_input);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "stepping"), "set_stepping", "get_stepping");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "step_input"), "set_step_input", "get_step_input");
}

void FootIKV2LedgeNative::bind(Node *p_owner) {
	owner_id = p_owner != nullptr ? (uint64_t)p_owner->get_instance_id() : 0;
}

void FootIKV2LedgeNative::over_drop(const StringName &p_side, const Vector3 &p_body, const Vector3 &p_ankle, const Vector3 &p_hip) {
	Array entry;
	entry.push_back(p_body);
	entry.push_back(p_ankle);
	entry.push_back(p_hip);
	over_[p_side] = entry;
}

void FootIKV2LedgeNative::on_ground(const StringName &p_side) {
	over_.erase(p_side);
}

Vector3 FootIKV2LedgeNative::push() {
	Vector3 total;
	const Array values = over_.values();
	for (int i = 0; i < values.size(); i++) {
		const Array entry = values[i];
		total += safe_way(entry[0], entry[1], entry[2]);
	}
	return total.normalized();
}

// The floor hit under `p_point`, {} when none (the shell's old `_ray`): the same query the foot pass uses.
Dictionary FootIKV2LedgeNative::ray(const Vector3 &p_point, const Vector3 &p_hip) {
	Node *owner = owner_id != 0 ? Object::cast_to<Node>(ObjectDB::get_instance(owner_id)) : nullptr;
	Skeleton3D *skel = owner != nullptr ? Object::cast_to<Skeleton3D>((Object *)owner->call("get_skeleton")) : nullptr;
	if (skel == nullptr) {
		return Dictionary();
	}
	Ref<World3D> world = skel->get_world_3d();
	PhysicsDirectSpaceState3D *space = world.is_valid() ? world->get_direct_space_state() : nullptr;
	if (space == nullptr) {
		return Dictionary();
	}
	Ref<PhysicsRayQueryParameters3D> query;
	query.instantiate();
	query->set_collision_mask((uint32_t)(int64_t)owner->get("ground_mask"));
	Node *body = Object::cast_to<Node>((Object *)owner->get("player_body"));
	CollisionObject3D *host = body != nullptr ? Object::cast_to<CollisionObject3D>(body->get_parent()) : nullptr;
	if (host != nullptr) {
		TypedArray<RID> exclude;
		exclude.push_back(host->get_rid());
		query->set_exclude(exclude);
	}
	const double ray_up = owner->get("ray_up");
	const double ray_down = owner->get("ray_down");
	query->set_from(Vector3(p_point.x, (real_t)std::max((double)p_hip.y, (double)p_point.y + ray_up), p_point.z));
	query->set_to(p_point - Vector3(0, 1, 0) * (real_t)ray_down);
	return space->intersect_ray(query);
}

// The horizontal direction from `p_ankle` to the nearest ground at the body's level; the way to the body when there is none.
Vector3 FootIKV2LedgeNative::safe_way(const Vector3 &p_body, const Vector3 &p_ankle, const Vector3 &p_hip) {
	const Vector3 toward = Vector3(p_body.x - p_ankle.x, 0.0f, p_body.z - p_ankle.z).normalized();
	if (owner_id == 0 || ObjectDB::get_instance(owner_id) == nullptr) {
		return toward;
	}
	for (double radius : LEDGE_RADII) {
		Vector3 best;
		double best_dot = -2.0;
		for (int index = 0; index < LEDGE_DIRECTIONS; index++) {
			const Vector3 way = Vector3(0, 0, -1).rotated(Vector3(0, 1, 0), (real_t)(Math_TAU * (double)index / LEDGE_DIRECTIONS));
			const Dictionary hit = ray(p_ankle + way * (real_t)radius, p_hip);
			if (hit.is_empty() || (double)p_body.y - (double)((Vector3)hit["position"]).y > LEDGE_DROP || ((Vector3)hit["normal"]).y < 0.7f) {
				continue;
			}
			const double d = (double)way.dot(toward); // of the ones with ground, the one toward the body
			if (d > best_dot) {
				best_dot = d;
				best = way;
			}
		}
		if (best != Vector3()) {
			return best;
		}
	}
	return toward;
}

// `stepping`: the body walks to the safe zone, so the legs STEP there (a walk clip) instead of the whole body sliding on planted feet.
// `step_input` is the move direction in the body's frame (x right, y backward) that picks the walk clip.
void FootIKV2LedgeNative::set_step(const Vector3 &p_world_way, const Basis &p_body_basis) {
	stepping_ = p_world_way.length_squared() > 0.0000001f;
	const Vector3 local = p_body_basis.inverse().xform(p_world_way);
	step_input_ = stepping_ ? Vector2(local.x, local.z) : Vector2();
}

// ---------------------------------------------------------------- sole

void FootIKV2SoleNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "skel", "character", "foot", "toe"), &FootIKV2SoleNative::build);
	ClassDB::bind_method(D_METHOD("is_empty"), &FootIKV2SoleNative::is_empty);
	ClassDB::bind_method(D_METHOD("points", "skel", "live"), &FootIKV2SoleNative::points);
	ClassDB::bind_method(D_METHOD("depth", "skel"), &FootIKV2SoleNative::depth);
	ClassDB::bind_method(D_METHOD("heel_local", "skel"), &FootIKV2SoleNative::heel_local);
	ClassDB::bind_method(D_METHOD("level_points", "skel", "to_world", "band"), &FootIKV2SoleNative::level_points);
	ClassDB::bind_method(D_METHOD("lowest_world_y", "skel", "to_world"), &FootIKV2SoleNative::lowest_world_y);
}

void FootIKV2SoleNative::build(Skeleton3D *p_skel, Node *p_character, int p_foot, int p_toe) {
	foot = p_foot;
	toe = p_toe;
	foot_weight.clear();
	toe_weight.clear();
	foot_local.clear();
	toe_local.clear();
	if (p_skel == nullptr || p_character == nullptr) {
		return;
	}
	const TypedArray<Node> parts = p_character->find_children("*", "MeshInstance3D", true, false);
	for (int i = 0; i < parts.size(); i++) {
		MeshInstance3D *part = Object::cast_to<MeshInstance3D>((Object *)parts[i]);
		if (part != nullptr && part->get_mesh().is_valid() && part->get_skin_reference().is_valid()) {
			add_mesh(p_skel, part);
		}
	}
	prune(p_skel, KEEP_BAND);
}

void FootIKV2SoleNative::add_mesh(Skeleton3D *p_skel, MeshInstance3D *p_part) {
	const Ref<Skin> skin = p_part->get_skin_reference()->get_skin();
	if (skin.is_null()) {
		return;
	}
	const Ref<Mesh> mesh = p_part->get_mesh();
	for (int surface = 0; surface < mesh->get_surface_count(); surface++) {
		const Array arrays = mesh->surface_get_arrays(surface);
		const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
		const PackedInt32Array bones = arrays[Mesh::ARRAY_BONES];
		const PackedFloat32Array weights = arrays[Mesh::ARRAY_WEIGHTS];
		if (vertices.is_empty() || bones.is_empty() || weights.is_empty()) {
			continue;
		}
		const int influences = bones.size() / vertices.size();
		for (int vertex = 0; vertex < vertices.size(); vertex++) {
			add_vertex(p_skel, skin, vertices[vertex], bones, weights, vertex * influences, influences);
		}
	}
}

void FootIKV2SoleNative::add_vertex(Skeleton3D *p_skel, const Ref<Skin> &p_skin, const Vector3 &p_vertex, const PackedInt32Array &p_bones,
		const PackedFloat32Array &p_weights, int p_first, int p_influences) {
	double total = 0.0, foot_share = 0.0, toe_share = 0.0;
	Vector3 foot_sum, toe_sum;
	for (int slot = p_first; slot < p_first + p_influences; slot++) {
		const int bind = p_bones[slot];
		const double weight = p_weights[slot];
		if (weight <= 0.0 || bind < 0 || bind >= p_skin->get_bind_count()) {
			continue;
		}
		int bone = p_skin->get_bind_bone(bind);
		if (bone < 0) {
			bone = p_skel->find_bone(p_skin->get_bind_name(bind));
		}
		if (bone < 0 || (bone != foot && bone != toe)) {
			continue;
		}
		const Vector3 local = p_skin->get_bind_pose(bind).xform(p_vertex) * (real_t)weight;
		total += weight;
		if (bone == foot) {
			foot_share += weight;
			foot_sum += local;
		} else {
			toe_share += weight;
			toe_sum += local;
		}
	}
	if (total > 0.5) {
		foot_weight.push_back((float)(foot_share / total));
		toe_weight.push_back((float)(toe_share / total));
		foot_local.push_back(foot_sum / (real_t)total);
		toe_local.push_back(toe_sum / (real_t)total);
	}
}

PackedVector3Array FootIKV2SoleNative::points(Skeleton3D *p_skel, bool p_live) const {
	const Transform3D foot_pose = p_live ? p_skel->get_bone_global_pose(foot) : p_skel->get_bone_global_rest(foot);
	const Transform3D toe_pose = p_live ? p_skel->get_bone_global_pose(toe) : p_skel->get_bone_global_rest(toe);
	const int n = foot_weight.size();
	PackedVector3Array out;
	out.resize(n);
	for (int i = 0; i < n; i++) {
		out.set(i, foot_pose.basis.xform(foot_local[i]) + foot_pose.origin * foot_weight[i] + toe_pose.basis.xform(toe_local[i]) + toe_pose.origin * toe_weight[i]);
	}
	return out;
}

// How far the lowest foot-mesh vertex sits below the foot bone at rest.
double FootIKV2SoleNative::depth(Skeleton3D *p_skel) const {
	const double foot_rest_y = p_skel->get_bone_global_rest(foot).origin.y;
	double lowest = std::numeric_limits<double>::infinity();
	const PackedVector3Array all = points(p_skel, false);
	for (int i = 0; i < all.size(); i++) {
		lowest = std::min(lowest, (double)all[i].y);
	}
	return std::isfinite(lowest) ? foot_rest_y - lowest : foot_rest_y;
}

// The rearmost sole-level point of the foot mesh, in the foot bone's rest space.
Vector3 FootIKV2SoleNative::heel_local(Skeleton3D *p_skel) const {
	const PackedVector3Array all = points(p_skel, false);
	const Transform3D foot_rest = p_skel->get_bone_global_rest(foot);
	if (all.is_empty() || toe < 0) {
		return Vector3();
	}
	Vector3 forward = p_skel->get_bone_global_rest(toe).origin - foot_rest.origin;
	forward.y = 0.0f;
	forward = forward.normalized();
	double lowest = std::numeric_limits<double>::infinity();
	for (int i = 0; i < all.size(); i++) {
		lowest = std::min(lowest, (double)all[i].y);
	}
	Vector3 heel = foot_rest.origin;
	double rearmost = std::numeric_limits<double>::infinity();
	for (int i = 0; i < all.size(); i++) {
		if ((double)all[i].y > lowest + HEEL_SOLE_BAND) {
			continue;
		}
		const double along = (double)all[i].dot(forward);
		if (along < rearmost) {
			rearmost = along;
			heel = all[i];
		}
	}
	heel.y = (real_t)lowest; // the contact point straight below the back of the heel, on the sole
	return foot_rest.affine_inverse().xform(heel);
}

// The sole-level points in WORLD space under `p_to_world`: every vertex within `p_band` of the lowest.
PackedVector3Array FootIKV2SoleNative::level_points(Skeleton3D *p_skel, const Transform3D &p_to_world, double p_band) const {
	const PackedVector3Array local = points(p_skel, true);
	const Basis b = p_to_world.basis;
	const Vector3 up(b.rows[1][0], b.rows[1][1], b.rows[1][2]); // the world-Y row: a point's world height is up.dot(p)
	std::vector<real_t> heights(local.size());
	real_t lowest = std::numeric_limits<real_t>::infinity();
	for (int i = 0; i < local.size(); i++) {
		heights[i] = up.dot(local[i]);
		lowest = std::min(lowest, heights[i]);
	}
	PackedVector3Array level;
	for (int i = 0; i < local.size(); i++) {
		if (heights[i] <= lowest + p_band) {
			level.push_back(p_to_world.xform(local[i]));
		}
	}
	return level;
}

// World height of the lowest sole point under `p_to_world`, from the CURRENT bone poses.
double FootIKV2SoleNative::lowest_world_y(Skeleton3D *p_skel, const Transform3D &p_to_world) const {
	double lowest = std::numeric_limits<double>::infinity();
	const PackedVector3Array local = points(p_skel, true);
	for (int i = 0; i < local.size(); i++) {
		lowest = std::min(lowest, (double)p_to_world.xform(local[i]).y);
	}
	return lowest;
}

// Keep only the vertices within `p_band` of the sole at rest: a foot pitched or rolled by the IK still bottoms out on those, and the
// rest (ankle, laces, cuff) are never the lowest point.
void FootIKV2SoleNative::prune(Skeleton3D *p_skel, double p_band) {
	const PackedVector3Array rest = points(p_skel, false);
	double lowest = std::numeric_limits<double>::infinity();
	for (int i = 0; i < rest.size(); i++) {
		lowest = std::min(lowest, (double)rest[i].y);
	}
	PackedFloat32Array fw, tw;
	PackedVector3Array fl, tl;
	for (int i = 0; i < rest.size(); i++) {
		if ((double)rest[i].y <= lowest + p_band) {
			fw.push_back(foot_weight[i]);
			tw.push_back(toe_weight[i]);
			fl.push_back(foot_local[i]);
			tl.push_back(toe_local[i]);
		}
	}
	foot_weight = fw;
	toe_weight = tw;
	foot_local = fl;
	toe_local = tl;
}
