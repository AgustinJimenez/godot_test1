#include "register_types.h"

#include "voxel_generator_planet.h"

#include "core/object/class_db.h"

void initialize_voxel_planet_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	// (the voxel module registers its classes at the same level, earlier: "voxel" comes before "voxel_planet")
	ClassDB::register_class<zylann::voxel::VoxelGeneratorPlanet>();
}

void uninitialize_voxel_planet_module(ModuleInitializationLevel p_level) {
}
