#pragma once

// The scenery that is not a plant (rocks, stumps, fallen logs, rock spires, pebbles, litter, twigs), the tufts of
// the turf, the chips of the gravel, and the shared plant materials (was systems/world_gen/flora_meshes.gd). Each
// kind comes in a few variants and is built once and shared. All statics; any thread may call them.

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class FloraMeshes : public RefCounted {
	GDCLASS(FloraMeshes, RefCounted)

protected:
	static void _bind_methods();

public:
	// The numbers stay what they were when plants shared this enum, so the rocks keep their shapes.
	enum Kind { ROCK = 5, STUMP = 10, LOG = 14, SPIRE = 15, PEBBLES = 16, LITTER = 17, TWIGS = 18 };
	static constexpr int TURF_VARIANTS = 3;
	static constexpr int TURF_BLADES = 10;
	static constexpr int CHIP_VARIANTS = 8;

	static Ref<ShaderMaterial> material();
	// The same plant shader with board-wood on the browns, for the buildings.
	static Ref<ShaderMaterial> structure_material();
	static Ref<ArrayMesh> mesh(int p_kind, int p_variant, bool p_detailed = false);
	static int variant_count(int p_kind);
	static Dictionary variants(); // kind -> how many variants
	static bool get_detailed(); // the realistic look wants the finer meshes (set by the world)
	static void set_detailed(bool p_on);
	// The tufts of short grass for the turf of the ground (PlanetTurf): TURF_VARIANTS arrangements of TURF_BLADES blades.
	static Ref<ArrayMesh> turf_tuft(int p_variant);
	// The look of the small stones of the ground (planet_chip.gdshader).
	static Ref<ShaderMaterial> chip_material();
	// The dark patch under every stone of `p_buffer` (16 floats an instance), a node of its own.
	static MultiMeshInstance3D *chip_shadow(const PackedFloat32Array &p_buffer);
	// A small angular stone for the gravel of the ground (PlanetTurf): CHIP_VARIANTS shapes.
	static Ref<ArrayMesh> chip(int p_variant);
};

} // namespace godot

VARIANT_ENUM_CAST(FloraMeshes::Kind);
