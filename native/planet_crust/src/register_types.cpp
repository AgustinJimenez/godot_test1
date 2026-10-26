#include "register_types.h"

#include "planet_crust_native.h"
#include "planet_climate_native.h"
#include "planet_climate_native.h"
#include "planet_rock_native.h"
#include "planet_frame_native.h"
#include "planet_sky_native.h"
#include "planet_sky_native.h"
#include "planet_sky_native.h"
#include "planet_star_native.h"
#include "planet_star_native.h"
#include "planet_star_native.h"
#include "planet_tectonics_native.h"
#include "planet_clock_native.h"
#include "planet_settings_native.h"
#include "planet_drainage_native.h"
#include "planet_imprint_native.h"
#include "planet_seasons_native.h"
#include "plant_mesh_native.h"
#include "plant_sway_native.h"
#include "planet_scatter_native.h"
#include "planet_surface_native.h"
#include "planet_water_native.h"
#include "planet_map_native.h"
#include "foot_ik_native.h"
#include "foot_ik_helpers_native.h"
#include "foot_ik_ledge_native.h"
#include "foot_ik_core_native.h"
#include "foot_ik_modifier_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_planet_crust_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(PlanetCrustNative);
	GDREGISTER_CLASS(PlanetClimate);
	GDREGISTER_CLASS(PlanetSeasons);
	GDREGISTER_CLASS(PlanetRock);
	GDREGISTER_CLASS(PlanetFrame);
	GDREGISTER_CLASS(PlanetAir);
	GDREGISTER_CLASS(PlanetTides);
	GDREGISTER_CLASS(PlanetMoon);
	GDREGISTER_CLASS(StarSystem);
	GDREGISTER_CLASS(StarLight);
	GDREGISTER_CLASS(Star);
	GDREGISTER_CLASS(PlanetTectonics);
	GDREGISTER_CLASS(PlanetClock);
	GDREGISTER_CLASS(PlanetSettings);
	GDREGISTER_CLASS(PlanetDrainageNative);
	GDREGISTER_CLASS(PlanetImprintNative);
	GDREGISTER_CLASS(PlanetSeasonsNative);
	GDREGISTER_CLASS(PlantMeshNative);
	GDREGISTER_CLASS(PlantSwayNative);
	GDREGISTER_CLASS(PlanetScatterNative);
	GDREGISTER_CLASS(PlanetSurfaceNative);
	GDREGISTER_CLASS(PlanetWaterNative);
	GDREGISTER_CLASS(PlanetMapNative);
	GDREGISTER_CLASS(FootIKV2Native);
	GDREGISTER_CLASS(FootIKV2LimiterNative);
	GDREGISTER_CLASS(FootIKV2StepperNative);
	GDREGISTER_CLASS(FootIKV2LockNative);
	GDREGISTER_CLASS(FootIKV2BodySmootherNative);
	GDREGISTER_CLASS(FootIKV2GroundFilterNative);
	GDREGISTER_CLASS(FootIKV2KneeHintNative);
	GDREGISTER_CLASS(FootIKV2StretchHoldNative);
	GDREGISTER_CLASS(FootIKV2CoreNative);
	GDREGISTER_CLASS(FootIKV2LedgeNative);
	GDREGISTER_CLASS(FootIKV2SoleNative);
	GDREGISTER_CLASS(FootIKV2Modifier);
	GDREGISTER_CLASS(FootIKV2Solver);
	GDREGISTER_CLASS(FootIKV2Debug);
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
