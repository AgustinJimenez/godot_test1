#pragma once

// Head hair for the parametric humans (assets/models/humans/*_body.glb): locks of hair (flat tapered ribbons the hair shader fills with
// strands) grown from the scalp of a body mesh, plus a thin cap over the scalp. The result carries the same blend shapes as the body, so the
// body's sliders (height, weight, muscle) move the hair with the head.
//
// Three steps, so the slow part can run on a worker thread:
//   prepare(body)            main thread, once per body: reads the ArrayMesh (surface_get_arrays stalls the GPU) into plain arrays, kept in the mesh's
//                            meta "human_hair_body" so the next call is free (prepare(body, true) reads it again after the mesh changed)
//   build_arrays(data, p)    any thread: grows the hair, returns {"arrays", "blend_arrays", "blend_names"} (no scene or rendering object is touched)
//   make_mesh(built)         main thread: the ArrayMesh from that
// build(body, params) does the three in a row.
//
// Blend shapes: every hair vertex follows the head by a fit of the whole scalp to each shape (a scale and a move, so the hair grows with the head at
// Height +-1), plus the local residual of the body vertex its lock starts on (fading out along the strand), and hair that hangs on the neck and shoulders
// follows the nearest body vertex instead (Weight and Muscle move the shoulders).

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// A body mesh read once into plain arrays (surface 0 and its blend shapes as per-vertex deltas).
class HumanHairBody : public RefCounted {
	GDCLASS(HumanHairBody, RefCounted)

protected:
	static void _bind_methods();

public:
	std::vector<Vector3> vertices;
	std::vector<Vector3> normals;
	std::vector<int32_t> indices;
	std::vector<std::vector<Vector3>> shape_deltas; // for every blend shape, the move of each vertex
	std::vector<StringName> shape_names;

	static Ref<HumanHairBody> from_mesh(const Ref<ArrayMesh> &p_mesh); // main thread
	bool is_valid() const;
	int64_t get_vertex_count() const { return int64_t(vertices.size()); }
	int64_t get_shape_count() const { return int64_t(shape_deltas.size()); }
};

class HumanHair : public RefCounted {
	GDCLASS(HumanHair, RefCounted)

protected:
	static void _bind_methods();

public:
	// The style (all optional):
	//   seed (int, 1)          the dice; the same seed gives the same hair on the same build (other platforms or float precisions may differ in a few locks: they use other maths libraries)
	//   length (m, 0.12)       how long the hair grows (0.02 cropped .. 0.35 past the shoulders)
	//   locks (int, 2600)      how many locks (cards of hair; up to 9000)
	//   lock_width (m, 0.018)  how wide one lock is at its widest
	//   volume (0.0 .. 1.5, 1) how far the hair stands off the head
	//   curl (0.0 .. 1.0, 0)   waviness
	//   fringe (0.0 .. 1.0, 0.4) how much of the front hair falls forward over the forehead (0 = combed back)
	//   parting (-1 .. 1, 0.0) where the parting is, across the head
	//   gravity (0.0 .. 2.0, 1) how much the hair falls
	//   strands (int, 0)       0 = wide ribbons (locks). >0: each guide lock grows this many single hairs (hair-thin ribbons, up to 24), up to 6000 guides
	//   strand_width (m, 0.0009) the width of one hair in strands mode; clump (m, 0.007): how far the hairs of one guide spread apart
	//   points (int, 0)        points per hair (3..16, 2 vertices each); 0 = automatic (up to 11, 7 in strands mode)
	//   side_trim (0.0 .. 1.0, 0) how much shorter the sides and back are than the top (a short back and sides; 1 leaves them bald: locks under 4 mm are not made)
	//   eye_drop (m, 0.105)    how far the eyes are below the top of the head (sets the hairline); default_params_for("male") 0.108, ("female") 0.107 (both from the eye landmarks)
	static Ref<HumanHairBody> prepare(const Ref<ArrayMesh> &p_body, bool p_refresh = false);
	static Dictionary build_arrays(const Ref<HumanHairBody> &p_body, const Dictionary &p_params);
	static Ref<ArrayMesh> make_mesh(const Dictionary &p_built);
	// Returns an ArrayMesh with one surface and the body's blend shapes (empty when the body has no usable surface).
	static Ref<ArrayMesh> build(const Ref<ArrayMesh> &p_body, const Dictionary &p_params);
	static Dictionary default_params();
	static Dictionary default_params_for(const String &p_gender); // default_params() with this body's eye_drop ("male" or "female")
};

} // namespace godot
