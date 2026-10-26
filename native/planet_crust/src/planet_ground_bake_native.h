#pragma once

// PlanetGroundBake (was systems/planet/planet_ground_bake.gd): the heights of the packed ground plates, drawn into a picture round the camera, so
// that the ground shader's parallax march reads one texel a step instead of working the procedural pattern out at every step. The picture wraps
// round (a torus): when the camera walks only the strip of ground it has just reached is drawn. Everything is in the march's own coordinates
// ("flat": the ground's metres along the anchor's right and forward axes, see `flat_of`); `follow` takes a key for that frame and draws the
// whole picture again when the key changes.

#include "native_props.h"
#include "planet_frame_native.h"

#include <godot_cpp/classes/color_rect.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace godot {

class PlanetGroundBake : public Node {
	GDCLASS(PlanetGroundBake, Node)

	SubViewport *view = nullptr;
	std::vector<ColorRect *> rects;
	std::vector<Ref<ShaderMaterial>> materials;
	Ref<ShaderMaterial> ground;
	Vector2i origin; // the world texel at the window's corner
	int64_t key_ = 0;
	bool valid = false;
	int used = 0; // the rects drawn this frame
	bool paused = false;

	Vector2i corner_for(const Vector2i &p_middle) const;
	Vector2i gained(int p_old, int p_now) const;
	void draw(const Vector2i &p_corner, const Vector2i &p_size);
	std::vector<Vector2i> cut(int p_start, int p_length) const;
	void place(const Vector2i &p_world, const Vector2i &p_size);
	void publish();

protected:
	static void _bind_methods();

public:
	static constexpr int STEP = 64; // texels the window moves at a time: a strip this wide is drawn when it does
	static constexpr int RECTS = 8; // a strip is at most four pieces (it wraps in x and in y), and two strips

	NP_FIELD(int64_t, pixels, 2048) // the picture is this many texels on a side
	NP_FIELD(bool, hdr, false) // 16-bit floats (32 MB) or 8 bits (16 MB: heights in 0.1 mm steps, same look)
	NP_FIELD(double, metres, 12.0) // and covers this much ground

	void setup(const Ref<ShaderMaterial> &p_ground, int64_t p_texels = 2048, double p_size_metres = 12.0);
	void set_parameter(const StringName &p_key, const Variant &p_value);
	void pause();
	static Vector2 flat_of(const Ref<PlanetFrame> &p_frame, const Vector3 &p_at);
	void follow(const Vector2 &p_centre, int64_t p_key);
};

} // namespace godot
