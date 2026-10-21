#pragma once

// The prints' profiles worked out natively (PlanetImprinter.profile_of and PlanetDents.sole_profile, which looped over
// 192 x 192 pixels in script). Pure computation on its own data, so any thread may call it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class PlanetImprintNative : public RefCounted {
	GDCLASS(PlanetImprintNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// From the grey levels (RGBA bytes, `p_tile` x `p_tile`) the camera under the ground read to a profile (one byte a
	// pixel, 255 the deepest); empty when almost nothing touches (or the lowest point is above `p_reach` levels).
	// `p_span` is how many grey levels the pressing part reaches up from the lowest point.
	PackedByteArray profile_of(const PackedByteArray &p_levels, int p_tile, int p_nothing, int p_reach, double p_span) const;
	// A bare foot as a profile (`p_side` +1 right, -1 left), `p_span` metres across the picture.
	PackedByteArray sole_profile(double p_side, int p_tile, double p_span) const;
};

} // namespace godot
