#pragma once

// PlanetDents, PlanetImprinter and PlanetFootprints (were systems/planet/planet_dents.gd, planet_imprinter.gd and planet_footprints.gd):
// the prints the player leaves. On sand and desert a dent the ground shader works out (a list of stamps, each a PROFILE: a small picture of how
// deep each spot under whatever touched the sand is pressed, which PlanetImprinter takes from the real mesh with a small camera under the ground);
// in snow and mud one Decal a step, kept in planet space and faded out over LIFE seconds. The imprinter's picture comes a frame later: the script's
// `await` is a callable now (`take(at, forward, up, done)` calls `done` with the profile).

#include "native_props.h"
#include "planet_frame_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/decal.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class PlanetDents : public RefCounted {
	GDCLASS(PlanetDents, RefCounted)

	struct Stamp {
		PackedFloat64Array at; // planet position, doubles
		Vector3 forward, up;
		double born = 0.0;
		PackedByteArray profile;
		int id = 0;
	};
	std::vector<Stamp> stamps;
	int next_id = 1;
	std::vector<int> shown; // the ids in the atlas, in slot order
	Ref<Image> image;
	Ref<ImageTexture> texture;
	Ref<Image> atlas;
	Ref<ImageTexture> atlas_texture;
	double since = 0.25;
	Ref<ShaderMaterial> material;

protected:
	static void _bind_methods();

public:
	static constexpr int SHOWN = 32; // how many the shader gets (the nearest to the camera)
	static constexpr int KEPT = 240; // how many are remembered (the oldest go first)
	static constexpr double REFRESH = 0.25; // s between two choices of the nearest stamps
	static constexpr int TILE = 192; // pixels across a profile
	static constexpr double SPAN = 0.8; // m across a profile
	static constexpr int COLUMNS = 8; // the atlas: COLUMNS x (SHOWN / COLUMNS) profiles

	NP_FIELD(double, life, 240.0) // s, when a print has gone
	NP_FIELD(double, clock, 0.0) // s since the start; the stamps are made at this time

	// `PlanetDents.new(material)` of the script
	static Ref<PlanetDents> create(const Ref<ShaderMaterial> &p_material);
	void add(const PackedFloat64Array &p_at, const Vector3 &p_forward, const Vector3 &p_up, double p_side, double p_age = 0.0,
			const PackedByteArray &p_profile = PackedByteArray());
	void clear();
	void update(double p_delta, const Vector3 &p_near);
	static PackedByteArray sole_profile(double p_side);
};

class PlanetImprinter : public Node {
	GDCLASS(PlanetImprinter, Node)

	SubViewport *viewport = nullptr;
	Camera3D *camera = nullptr;
	bool busy = false;
	Callable pending;

protected:
	static void _bind_methods();

public:
	static constexpr double SLAB = 0.1; // m of the world above the ground the camera sees
	static constexpr double SINK = 0.04; // m: the part of the object within this of its lowest point presses the sand
	static constexpr int LAYER = 20; // the visual layer of the depth quad (the main cameras do not draw it)
	static constexpr int NOTHING = 250; // a grey level from here up is empty space
	static constexpr int REACH = 70; // the lowest point must be within 2.7 cm of the ground (grey levels)

	void _ready() override;
	// The profile of what touches the ground at world position `at` (its toe along `forward`, the ground's `up`): `done` is called with TILE x TILE
	// bytes (empty when nothing is within the slab above the ground, or another is being taken) a frame later.
	void take(const Vector3 &p_at, const Vector3 &p_forward, const Vector3 &p_up, const Callable &p_done);
	void taken();
	static PackedByteArray profile_of(const PackedByteArray &p_levels);
};

class PlanetFootprints : public Node3D {
	GDCLASS(PlanetFootprints, Node3D)

	struct Print {
		ObjectID decal;
		PackedFloat64Array at; // planet space, doubles
		Vector3 up, forward;
		double age = 0.0;
		Color tint;
	};
	std::vector<Print> prints;
	double since = 0.0;
	bool left = false;
	Vector3 last;
	bool have_last = false;
	int retry = 0;
	double fall = 0.0; // m/s, the fastest the player fell since they left the ground
	bool decals_on = false;
	Ref<PlanetDents> dents;
	PlanetImprinter *imprinter = nullptr;
	Node3D *dust = nullptr;

	void follow(double p_delta);
	void press(const Vector3 &p_feet);
	void dent_sand(const Vector3 &p_at, const Vector3 &p_forward, const Vector3 &p_up_world);
	void land(const Vector3 &p_feet, double p_speed);
	Color paint(const Vector3 &p_world_position) const;
	static bool is_sand(int p_biome);
	static Color tint_of(int p_biome, const Color &p_paint);
	Decal *next_decal();
	void clear_prints(bool p_with_dents = true);
	static Ref<ImageTexture> footprint_texture();
	static double blob(double p_u, double p_v, double p_a, double p_b);
	Node3D *dust_node();

protected:
	static void _bind_methods();

public:
	static constexpr int MAX = 48;
	static constexpr double STEP = 0.85; // m between two footprints
	static constexpr int RETRIES = 8; // frames a print is tried again while no foot is on the ground
	static constexpr double LIFE = 120.0; // s

	NP_OBJECT(planet)
	NP_OBJECT(target)

	void _physics_process(double p_delta) override;
	// (called a frame later with what the imprinter saw)
	void sand_taken(const PackedByteArray &p_profile, const PackedFloat64Array &p_where, const Vector3 &p_forward, const Vector3 &p_up, int64_t p_rebased,
			const Vector3 &p_at, const Vector3 &p_up_world);
};

} // namespace godot
