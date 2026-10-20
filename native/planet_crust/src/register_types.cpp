#include "register_types.h"

#include "planet_crust_native.h"
#include "planet_drainage_native.h"
#include "planet_seasons_native.h"
#include "plant_mesh_native.h"
#include "plant_sway_native.h"
#include "planet_scatter_native.h"
#include "planet_surface_native.h"
#include "planet_water_native.h"
#include "planet_map_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_planet_crust_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(PlanetCrustNative);
	GDREGISTER_CLASS(PlanetDrainageNative);
	GDREGISTER_CLASS(PlanetSeasonsNative);
	GDREGISTER_CLASS(PlantMeshNative);
	GDREGISTER_CLASS(PlantSwayNative);
	GDREGISTER_CLASS(PlanetScatterNative);
	GDREGISTER_CLASS(PlanetSurfaceNative);
	GDREGISTER_CLASS(PlanetWaterNative);
	GDREGISTER_CLASS(PlanetMapNative);
}

void uninitialize_planet_crust_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT planet_crust_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_object(p_get_proc_address, p_library, r_initialization);
	init_object.register_initializer(initialize_planet_crust_module);
	init_object.register_terminator(uninitialize_planet_crust_module);
	init_object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
}
