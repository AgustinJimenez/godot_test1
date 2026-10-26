#pragma once

// PlanetFrame (was systems/planet/planet_frame.gd): where the planet is in the game's world. A planet space point `q` is at
//   world = rot * (q - anchor) + origin_w
// `anchor` is the planet space point the player was last at; `rot` turns the ground there so its "up" is +Y. `rebase` turns the planet a
// little so the ground under the player is level again and the world coordinates stay small however far the player has walked.

#include "native_props.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetFrame : public RefCounted {
	GDCLASS(PlanetFrame, RefCounted)

	Vector3 unit_of(const PackedFloat64Array &p_position) const;

protected:
	static void _bind_methods();

public:
	static constexpr double NOISE_PERIOD = 1024.0;
	static constexpr double LAYER_RATE = 1.86;

	NP_FIELD(Basis, rot, Basis())
	NP_FIELD(PackedFloat64Array, anchor, PackedFloat64Array())
	NP_FIELD(Vector3, origin_w, Vector3()) // where the anchor is in the world

	PlanetFrame();
	void start(const PackedFloat64Array &p_planet_position, const Vector3 &p_world_position);
	PackedFloat64Array to_planet(const Vector3 &p_world_position) const;
	Vector3 to_world(const Vector3 &p_planet_position) const;
	void rebase(const Vector3 &p_world_position);
	void shift(const Vector3 &p_delta);
	Transform3D planet_to_world() const;
	Transform3D anchor_from_world() const;
	Vector3 anchor_wrap() const;
	Vector3 anchor_up() const;
	double anchor_phase() const;
	// `tile`: a PlanetTile (its `origin` in doubles and `local_basis`)
	Transform3D tile_transform(Object *p_tile) const;
};

} // namespace godot
