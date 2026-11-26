#pragma once

// Body hair for the parametric humans: short single hairs on the chest, the belly line, the back, the arms, the legs and in the armpits, grown on the
// body mesh the head hair is grown on (HumanHair::prepare). The same vertex layout as the beard (COLOR.b 0.3 marks a beard-like hair, so the hair
// shader gives it the beard's colour, grey and ginger), so the head hair's material draws it; HumanHair::make_mesh turns the result into a mesh.
//
// Where the hair grows comes from the skeleton's joints (the lab reads them from <gender>_rig.json), passed in params["joints"]: a limb is the band
// round the line between two joints, the torso is split by the nipples, the navel height and the neck. Every hair is bound to the body vertex nearest
// its root and moves with it: the result carries the body's height / weight / muscle blend shapes (each vertex follows its bound vertex's move), and
// HumanRig.attach_skinned gives it the bound vertex's bone weights.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class HumanHairBody;

class HumanBodyHair : public RefCounted {
	GDCLASS(HumanBodyHair, RefCounted)

protected:
	static void _bind_methods();

public:
	// params (all optional):
	//   seed (int, 1)
	//   amount (0..1, 0)       how hairy overall (0: no hair; scales the density of every area)
	//   chest, belly, back, arms, legs, armpits (0..1)   each area's own amount (defaults: 1, 1, 0.3, 1, 1, 1)
	//   length (m, 0.012)      the length of a chest hair; the other areas are a share of it (forearm 0.75, shin 0.8, armpit 1.6 ...)
	//   curl (0..1, 0.4)       how much the hairs coil (the chest and the armpits more, the limbs less)
	//   max_hairs (int, 60000) a ceiling: the densities are scaled down to it
	//   joints (Dictionary)    body-space points: shoulder_l/r, elbow_l/r, wrist_l/r, hip_l/r, knee_l/r, ankle_l/r, neck, hips, nipple_l/r
	// Returns {"arrays", "blend_arrays", "blend_names", "hairs", "area_hairs" (area name -> count), "roots"}; empty arrays when no hair grows.
	static Dictionary build_arrays(const Ref<HumanHairBody> &p_body, const Dictionary &p_params);
	static Dictionary default_params();
};

} // namespace godot
