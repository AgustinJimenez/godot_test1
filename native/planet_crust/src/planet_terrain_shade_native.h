#pragma once

// PlanetTerrainShade: the ground's height round the player as a picture (a gnomonic map of a square of the planet), so the ground shader can march
// from a point toward the star over it and find the long shadows of hills and mountains that the sun's own shadow map (150 m) never reaches.
// The picture is made on a thread of its own and drawn again when the player has walked a quarter of the way to its edge or the star has moved.
// The thread marches from every pixel's ground toward the star over the heights (on the CPU, once), so the shaders only read the answer.
// Published as shader globals: terrain_shade_map (R8: how much of the star the ground there sees), terrain_shade_c / _e1 / _e2 (the square's middle
// direction and axes, planet space), terrain_shade (tan of the half side, strength).

#include "planet_noise_native.h"

#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetTerrainShade : public RefCounted {
	GDCLASS(PlanetTerrainShade, RefCounted)

	static constexpr int SIZE = 768; // pixels a side
	static constexpr double HALF_SIDE = 14000.0; // metres from the middle to the edge (smaller on a small planet)

	Ref<PlanetNoise> noise;
	double radius = 1.0;
	Ref<Thread> worker;
	bool working = false;
	// the picture being made
	Vector3 job_c, job_e1, job_e2, job_sun;
	double job_tan = 0.0;
	PackedByteArray result;
	bool result_ready = false;
	// the picture shown
	Vector3 shown_c, shown_sun;
	bool shown = false;
	double shown_tan = 0.0;
	Ref<ImageTexture> texture;

	void publish();

protected:
	static void _bind_methods();

public:
	void setup(const Ref<PlanetNoise> &p_noise, double p_radius);
	void bake_run();
	// Call often with the player's place and the star's direction (both in planet space): collects a finished picture, starts a new one when the
	// player is near the edge or the star has moved.
	void update(const Vector3 &p_dir, const Vector3 &p_sun);
	void stop();
	void clear();
};

} // namespace godot
