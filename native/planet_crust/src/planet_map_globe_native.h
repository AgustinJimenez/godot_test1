#pragma once

// PlanetMapGlobe (was systems/planet/planet_map_globe.gd): the planet map as a small planet in 3D: a ball wearing the map's picture (whichever layer
// is showing, as sharp as the charting has got), turned with the mouse (drag), zoomed with the wheel or a pinch, and a pin where the player stands.
// The map shows it instead of the flat map (G).

#include "native_props.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/sub_viewport_container.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetMapGlobe : public SubViewportContainer {
	GDCLASS(PlanetMapGlobe, SubViewportContainer)

	SubViewport *viewport = nullptr;
	Camera3D *camera = nullptr;
	MeshInstance3D *ball = nullptr;
	MeshInstance3D *pin = nullptr;
	Ref<ShaderMaterial> material;
	double yaw = 0.0;
	double pitch = 0.3;
	double distance = 3.2;
	bool dragging = false;
	Ref<Texture2D> shown;
	Ref<Texture2D> detail_shown;

	void aim();

protected:
	static void _bind_methods();

public:
	static constexpr double ZOOM_SPAN = 0.6; // how much of the way round the sky the view takes at zoom 1 (x PI)
	static constexpr double FOV = 40.0;

	PlanetMapGlobe();
	void set_chart(const Ref<Texture2D> &p_texture);
	void set_detail(const Ref<Texture2D> &p_texture, const Rect2 &p_rect);
	void set_zoom(double p_zoom);
	void set_sun(const Vector3 &p_dir);
	void set_pin(const Vector3 &p_dir);
	void look_at_direction(const Vector3 &p_dir);
	bool handle_input(const Ref<InputEvent> &p_event);
	void release() { dragging = false; }
	Vector3 facing() const;
};

} // namespace godot
