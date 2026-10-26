#pragma once

// PlanetSurface (was systems/planet/planet_surface.gd): the ground of a planet as tiles, finer the closer they are (a quadtree on each cube face).
// Keeps the tiles around a point of the planet built, on worker threads, and a tile is only dropped once the tiles that replace it are in, so the
// ground never has holes. Tiles are placed in the world by the PlanetFrame. The tile selection is PlanetSurfaceNative; the script's own selection
// (the fallback without the library) is gone with the port. Plants are a second job on threads of their own.

#include "native_props.h"
#include "planet_frame_native.h"
#include "planet_noise_native.h"
#include "planet_tile_native.h"

#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/semaphore.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <atomic>
#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <vector>

namespace godot {

class PlanetSurface : public Node3D {
	GDCLASS(PlanetSurface, Node3D)

	struct Entry {
		int face = 0, level = 0, x = 0, y = 0;
		double distance = 0.0;
		bool collides = false;
		int plants = 0;
		double sort = 0.0;
	};
	struct PlantJob {
		PlanetTile *tile = nullptr;
		int detail = 0;
	};
	struct PlantDone {
		uint64_t tile = 0; // instance id
		Node3D *holder = nullptr;
		int detail = 0;
	};

	Ref<PlanetSettings> settings_;
	Ref<RefCounted> native_; // PlanetSurfaceNative (the tile selection and the order)
	PackedVector3Array faces_;
	std::map<int64_t, Entry> wanted;
	std::set<int64_t> pending; // true while queued or being built
	std::deque<Entry> jobs;
	std::deque<PlanetTile *> done;
	std::vector<Ref<Thread>> workers; // the ground is made by several threads, the plants by one
	std::vector<Ref<Thread>> plant_workers;
	std::mutex mutex;
	Ref<Semaphore> semaphore, plant_semaphore;
	std::atomic<bool> stop{ false };
	Vector3 near_; // the point the tiles are chosen for (planet space)
	double height_ = 0.0; // m the player is over the ground there
	int tiles_per_frame = 2;
	std::vector<Entry> inline_jobs; // without a worker thread (headless): tiles built here, a few a frame
	std::deque<PlantJob> plant_jobs;
	std::deque<PlantDone> plant_done;
	std::vector<std::pair<uint64_t, int>> plant_inline;
	std::set<uint64_t> plant_pending; // tile instance id -> while queued or being grown
	std::vector<PlanetTile *> retired; // tiles taken out of the world, freed once no plant job holds them

	void select_native(const Vector3 &p_at);
	void queue_plants();
	void adopt_plants();
	void retire(PlanetTile *p_tile);
	void free_retired();
	void add(PlanetTile *p_tile);
	PlanetTile *make(const Entry &p_entry);
	PlanetTile *tile_at(int64_t p_key) const;
	void drop_stale();
	bool covered(PlanetTile *p_tile) const;
	static bool overlap(PlanetTile *p_tile, const Entry &p_entry);
	void wait_while_paused();

protected:
	static void _bind_methods();

public:
	static constexpr double PLANT_RANGE = 6000.0; // m: the horizon trees (sparse, cheap) are planted out to here
	static constexpr int BURST_TILES = 24;

	NP_FIELD(Ref<PlanetNoise>, noise, Ref<PlanetNoise>())
	NP_FIELD(Ref<PlanetFrame>, frame, Ref<PlanetFrame>())
	NP_FIELD(bool, threaded, true)
	NP_FIELD(Dictionary, tiles, Dictionary()) // key -> PlanetTile (in the tree)
	NP_FIELD(bool, paused, false) // true while the map is open: workers keep their jobs (the charts get the CPU)
	NP_FIELD(bool, burst, false) // true while the player waits: many tiles a frame, hitches do not matter

	PlanetSurface();
	void setup(const Ref<PlanetNoise> &p_noise, const Ref<PlanetFrame> &p_frame);
	void _exit_tree() override;
	void _process(double p_delta) override;
	void update(const Vector3 &p_at);
	int64_t coarse_level() const;
	void build_all(const Vector3 &p_at, bool p_near_only = false);
	double progress(double p_ground_metres, double p_plant_metres) const;
	bool is_threaded() const { return !workers.empty(); }
	int64_t wanted_count() const { return (int64_t)wanted.size(); }
	void place_all();
	void work();
	void work_plants();
};

} // namespace godot
