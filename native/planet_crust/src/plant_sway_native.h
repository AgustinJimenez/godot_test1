#pragma once

// The branches of a tree near the walker bending and springing back: every branch of a grown tree (PlantMeshNative "branches"
// table: parent, level, foot, tip, radius, length) is a damped spring that turns about its foot, pushed out of the way by the
// walker's body (an upright capsule). A branch carries what grows on it (its twigs and leaves), so the turns stack down the
// tree; the plant shader applies them to the vertices (CUSTOM0 is a vertex's branch).
// Pure computation on its own data: any thread may call it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class PlantSwayNative : public RefCounted {
	GDCLASS(PlantSwayNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// One step of `p_dt` seconds. `p_table`: the branches, ten floats each (the first row is the trunk, which never moves);
	// `p_state`: six floats each (the turn as a rotation vector about the branch's foot, relative to its parent, and its
	// rate; empty: at rest); `p_body`: the walker in the tree's own space (axis from a to b, radius: 7 floats; empty: nobody).
	// Returns {"state", "awake": false once everything has come to rest}.
	Dictionary step(const PackedFloat32Array &p_table, const PackedFloat32Array &p_state, const PackedFloat32Array &p_body, double p_dt) const;
	// What the shader reads: the turns, four floats a branch (the rotation vector and a spare).
	PackedFloat32Array turns(const PackedFloat32Array &p_state) const;
	// The rows of the shader's texture that never change: the foot of each branch and the id of its parent, four floats each.
	PackedFloat32Array feet(const PackedFloat32Array &p_table) const;
	// The trees of a MultiMesh buffer (16 floats an instance: the basis rows with the origin, then the colour) whose origin is
	// within `p_radius` of (x, z): their indices.
	PackedInt32Array within(const PackedFloat32Array &p_buffer, double p_x, double p_z, double p_radius) const;
};

} // namespace godot
