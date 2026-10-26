#pragma once

// PlanetImpostors and PlanetCloudShell (were systems/planet/planet_impostors.gd and planet_cloud_shell.gd).
// PlanetImpostors bakes the far trees' impostors: for each tree variant the lighter tree mesh is drawn from VIEWS angles round it (and from straight
// above) by a small orthographic camera into one atlas (planet_impostor.gdshader shows the nearest two). A tile built after a variant is baked hangs
// quads where it used to hang the lighter trees. The script's `await` of each frame is a step per frame_post_draw now.
// PlanetCloudShell is the clouds seen from in and above their layer: a screen quad whose pixels march the layer (planet_clouds.gdshader), with the
// cloud cover picture made on a background thread every few seconds.

#include "native_props.h"
#include "planet_chart_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace godot {

class PlanetImpostors : public Node {
	GDCLASS(PlanetImpostors, Node)

	struct Task {
		int id = 0, variant = 0;
	};
	ObjectID registry_id;
	SubViewport *viewport = nullptr;
	Camera3D *camera = nullptr;
	MeshInstance3D *holder = nullptr;
	std::vector<Task> tasks;
	size_t next_task = 0;
	// the bake in hand
	Task current;
	Ref<Image> atlas;
	int view = 0;
	double side = 0.0, middle = 0.0, box_top = 0.0;

	Object *species() const { return ObjectDB::get_instance(registry_id); }
	void begin_next();
	void aim(int p_view);
	void finish_bake();
	void swap(int p_id, int p_variant);

protected:
	static void _bind_methods();

public:
	static constexpr int VIEWS = 8;
	static constexpr int CELL = 160; // pixels across one view
	static constexpr int VARIANTS = 2; // the lighter versions a scatter uses (variant % 2)

	void start(Object *p_registry);
	void frame_done();
};

class PlanetCloudShell : public MeshInstance3D {
	GDCLASS(PlanetCloudShell, MeshInstance3D)

	Ref<ShaderMaterial> material;
	Ref<PlanetChart> chart;
	double wait = 0.0;
	double drawn_time = -1.0e12;

	void refresh_the_cover(double p_delta);

protected:
	static void _bind_methods();

public:
	static constexpr double REFRESH = 2.5; // seconds between pictures

	NP_OBJECT(planet)

	void _ready() override;
	void _process(double p_delta) override;
	void _exit_tree() override;
};

} // namespace godot
