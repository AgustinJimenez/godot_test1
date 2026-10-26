#pragma once

// PlanetTurf (was systems/planet/planet_turf.gd): the short grass that covers the ground where grass grows: thousands of small tufts round the
// walker, made in chunks of a tile's ground (16 m squares) by the camera's view and the walker's distance, in three levels (a fine ring round the
// walker, a thinner one, a thin, bigger one far out in the view), each chunk one MultiMesh made by PlanetScatterNative.turf_chunk. With
// `gravel` it makes the small stones of the bare ground instead (PlanetScatterNative.gravel_chunk). Off with `PLANET_NO_TURF`.

#include "native_props.h"

#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <map>
#include <vector>

namespace godot {

class PlanetTurf : public Node {
	GDCLASS(PlanetTurf, Node)

	struct Chunk {
		int level = 0;
		std::vector<ObjectID> nodes, shadows;
		ObjectID holder;
		Dictionary grid;
		Vector2 at;
		std::vector<PackedFloat32Array> buffers;
	};
	std::map<int64_t, Chunk> chunks; // key -> chunk
	double since = 0.0;

	double enter() const;
	double leave() const;
	double far_reach() const;
	int level_of(double p_distance) const;
	static PackedFloat32Array bigger(const PackedFloat32Array &p_buffer, double p_factor);
	void make(int64_t p_key, Node3D *p_holder, const Dictionary &p_grid, int p_ix, int p_iz, int p_level = 0);
	void let_go(const Vector3 &p_here, const Vector3 &p_way);
	void drop(int64_t p_key);
	static Vector3 grid_of(const Dictionary &p_grid, const Vector3 &p_local);
	static double spacing();

protected:
	static void _bind_methods();

public:
	static constexpr double CHUNK = 16.0; // m: the square of a tile's ground made at a time
	static constexpr double ENTER = 26.0; // m: chunks whose middle is closer than this are made
	static constexpr double LEAVE = 36.0; // m: and let go beyond this
	// m: one tuft for each spot of a jittered grid of this (PLANET_TURF_SPACING: another, to try)
	static constexpr double SPACING = 0.21;
	// the odds of a tuft are the field times this (the field is 1 only where grass grows best)
	static constexpr double DENSITY = 1.6;
	static constexpr double DRAWN = 32.0; // m: how far a tuft is drawn (it fades out)
	// the grass seen from afar follows the camera, not a ring round the walker
	static constexpr double MID_ENTER = 62.0;
	static constexpr double FAR_ENTER = 130.0;
	static constexpr double FAR_LEAVE = 150.0;
	static constexpr double FAR_DRAWN = 68.0;
	static constexpr double VERY_DRAWN = 140.0;
	static constexpr double FAR_THIN = 2.0;
	static constexpr double VERY_THIN = 4.0;
	static constexpr double VERY_BIG = 2.2;
	static constexpr double FAR_COS = 0.62; // about 50 degrees either side of where the camera looks
	static constexpr double LEAVE_COS = 0.1; // about 84 degrees
	// m: one stone for each spot of a jittered grid of this (the odds make them thin where grass grows)
	static constexpr double GRAVEL_SPACING = 0.12;
	static constexpr double GRAVEL_DRAWN = 14.0; // m: how far a stone is drawn (its size is under a pixel beyond)
	static constexpr double LOOK_EVERY = 0.3; // s
	static constexpr int MAKE_EACH_LOOK = 3; // chunks made at most in each look: the walker is never held up
	static constexpr double NEAR = 12.0; // m: chunks this close are made at once, whatever the budget
	static constexpr double VIEW_COS = 0.35; // a chunk within about 70 degrees of where the camera looks counts as in view
	static constexpr double VIEW_BONUS = 30.0; // m: how much sooner an in-view chunk is made than one out of view

	NP_OBJECT(planet)
	NP_OBJECT(player)
	NP_FIELD(bool, gravel, false) // true: the small stones of the bare ground instead of grass

	void _physics_process(double p_delta) override;
	Array chunk_sets() const;
	int64_t tuft_count() const;
	int64_t far_count() const;
};

} // namespace godot
