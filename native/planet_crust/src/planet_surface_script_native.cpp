#include "planet_surface_script_native.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/os.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double PI_D = 3.14159265358979323846;

void PlanetSurface::_bind_methods() {
	BIND_CONSTANT(BURST_TILES);
	ClassDB::bind_method(D_METHOD("get_noise"), &PlanetSurface::get_noise);
	ClassDB::bind_method(D_METHOD("set_noise", "value"), &PlanetSurface::set_noise);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "noise", PROPERTY_HINT_RESOURCE_TYPE, "PlanetNoise", PROPERTY_USAGE_NO_EDITOR), "set_noise", "get_noise");
	ClassDB::bind_method(D_METHOD("get_frame"), &PlanetSurface::get_frame);
	ClassDB::bind_method(D_METHOD("set_frame", "value"), &PlanetSurface::set_frame);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "frame", PROPERTY_HINT_RESOURCE_TYPE, "PlanetFrame", PROPERTY_USAGE_NO_EDITOR), "set_frame", "get_frame");
	NP_BIND_STATE(PlanetSurface, Variant::BOOL, threaded)
	NP_BIND_STATE(PlanetSurface, Variant::DICTIONARY, tiles)
	NP_BIND_STATE(PlanetSurface, Variant::BOOL, paused)
	NP_BIND_STATE(PlanetSurface, Variant::BOOL, burst)
	ClassDB::bind_method(D_METHOD("setup", "planet_noise", "planet_frame"), &PlanetSurface::setup);
	ClassDB::bind_method(D_METHOD("update", "at"), &PlanetSurface::update);
	ClassDB::bind_method(D_METHOD("coarse_level"), &PlanetSurface::coarse_level);
	ClassDB::bind_method(D_METHOD("build_all", "at", "near_only"), &PlanetSurface::build_all, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("progress", "ground_metres", "plant_metres"), &PlanetSurface::progress);
	ClassDB::bind_method(D_METHOD("is_threaded"), &PlanetSurface::is_threaded);
	ClassDB::bind_method(D_METHOD("place_all"), &PlanetSurface::place_all);
	ClassDB::bind_method(D_METHOD("work"), &PlanetSurface::work);
	ClassDB::bind_method(D_METHOD("work_plants"), &PlanetSurface::work_plants);
}

PlanetSurface::PlanetSurface() {
	semaphore.instantiate();
	plant_semaphore.instantiate();
}

PlanetTile *PlanetSurface::tile_at(int64_t p_key) const {
	Variant found = tiles.get(p_key, Variant());
	return Object::cast_to<PlanetTile>((Object *)found);
}

void PlanetSurface::setup(const Ref<PlanetNoise> &p_noise, const Ref<PlanetFrame> &p_frame) {
	noise = p_noise;
	frame = p_frame;
	settings_ = noise->get_settings();
	native_ = ClassDBSingleton::get_singleton()->instantiate("PlanetSurfaceNative");
	Array all = PlanetTile::faces();
	for (int i = 0; i < all.size(); i++) {
		Array axes = all[i];
		for (int a = 0; a < axes.size(); a++) {
			faces_.append(axes[a]);
		}
	}
	if (threaded && DisplayServer::get_singleton()->get_name() != "headless") {
		int count = CLAMP((int)OS::get_singleton()->get_processor_count() - 2, 2, 4);
		for (int index = 0; index < count; index++) {
			Ref<Thread> worker;
			worker.instantiate();
			worker->start(Callable(this, "work"));
			workers.push_back(worker);
		}
		for (int index = 0; index < count; index++) {
			Ref<Thread> planter;
			planter.instantiate();
			planter->start(Callable(this, "work_plants"));
			plant_workers.push_back(planter);
		}
	}
}

void PlanetSurface::_exit_tree() {
	if (!workers.empty()) {
		stop = true;
		for (size_t i = 0; i < workers.size(); i++) {
			semaphore->post();
		}
		for (size_t i = 0; i < plant_workers.size(); i++) {
			plant_semaphore->post();
		}
		for (Ref<Thread> &worker : workers) {
			worker->wait_to_finish();
		}
		for (Ref<Thread> &planter : plant_workers) {
			planter->wait_to_finish();
		}
		workers.clear();
		plant_workers.clear();
	}
}

// Chooses the tiles for a player at `at` (planet space) and queues what is missing.
void PlanetSurface::update(const Vector3 &p_at) {
	near_ = p_at;
	// how high the player is over the ground under them: detail follows the distance in space, so up in the air the ground is coarse and nothing
	// grows (the trees below are far away)
	Vector3 here = p_at.normalized();
	height_ = std::max(p_at.length() - settings_->get_radius() - noise->height(here.x, here.y, here.z), 0.0);
	wanted.clear();
	select_native(p_at);
	std::vector<Entry> missing;
	PackedFloat64Array sorts;
	for (const auto &pair : wanted) {
		if (pending.count(pair.first)) {
			continue;
		}
		PlanetTile *built = tile_at(pair.first);
		if (built == nullptr || (pair.second.collides && !built->get_has_collider())) {
			missing.push_back(pair.second);
			sorts.append(pair.second.sort);
		}
	}
	PackedInt32Array order = native_->call("order", sorts);
	std::vector<Entry> ordered;
	for (int i = 0; i < order.size(); i++) {
		ordered.push_back(missing[order[i]]);
	}
	missing = ordered;
	{
		std::lock_guard<std::mutex> lock(mutex);
		for (const Entry &job : jobs) { // the player moved: the old queue may be for places it has left
			pending.erase(PlanetTile::key_of(job.face, job.level, job.x, job.y));
		}
		jobs.clear();
	}
	size_t batch = burst ? 600 : 48; // (the player waits: every tile that is missing, nearest first)
	if (threaded && !workers.empty()) {
		for (size_t i = 0; i < std::min(batch, missing.size()); i++) {
			const Entry &entry = missing[i];
			pending.insert(PlanetTile::key_of(entry.face, entry.level, entry.x, entry.y));
			{
				std::lock_guard<std::mutex> lock(mutex);
				jobs.push_back(entry);
			}
			semaphore->post();
		}
	} else {
		inline_jobs.assign(missing.begin(), missing.begin() + std::min((size_t)12, missing.size()));
	}
	queue_plants();
	drop_stale();
}

// The tiles wanted for a player at `at`, chosen natively.
void PlanetSurface::select_native(const Vector3 &p_at) {
	Dictionary config;
	config["near"] = p_at;
	config["height"] = height_;
	config["radius"] = settings_->get_radius();
	config["max_level"] = settings_->max_level();
	config["split_factor"] = settings_->get_split_factor();
	config["tile_max"] = settings_->get_tile_max();
	config["collide_tiles"] = settings_->get_collide_tiles();
	config["plants_on"] = settings_->get_plants_on();
	config["coarse_level"] = coarse_level();
	config["faces"] = faces_;
	Dictionary picked = native_->call("select", config);
	PackedInt32Array entries = picked["entries"];
	PackedFloat64Array distance = picked["distance"];
	PackedByteArray collides = picked["collides"];
	PackedByteArray plants = picked["plants"];
	PackedFloat64Array sort = picked["sort"];
	for (int index = 0; index < distance.size(); index++) {
		int at4 = index * 4;
		Entry entry;
		entry.face = entries[at4];
		entry.level = entries[at4 + 1];
		entry.x = entries[at4 + 2];
		entry.y = entries[at4 + 3];
		entry.distance = distance[index];
		entry.collides = collides[index] == 1;
		entry.plants = plants[index];
		entry.sort = sort[index];
		wanted[PlanetTile::key_of(entry.face, entry.level, entry.x, entry.y)] = entry;
	}
}

// The tile levels up to this make the planet's coarse shape (seen from far away).
int64_t PlanetSurface::coarse_level() const {
	return CLAMP(settings_->max_level() - 3, (int64_t)2, (int64_t)4);
}

// Builds everything wanted around `at` right now (labs and tests). `near_only`: just the tiles the player can stand on.
void PlanetSurface::build_all(const Vector3 &p_at, bool p_near_only) {
	update(p_at);
	for (const auto &pair : wanted) {
		const Entry &entry = pair.second;
		if (p_near_only && !entry.collides) {
			continue;
		}
		PlanetTile *built = tile_at(pair.first);
		if (built == nullptr || (entry.collides && !built->get_has_collider())) {
			if (built != nullptr) {
				retire(built);
			}
			add(make(entry));
		}
	}
	drop_stale();
}

void PlanetSurface::_process(double) {
	int added = 0;
	int limit = burst ? BURST_TILES : tiles_per_frame;
	while (added < limit && !inline_jobs.empty()) {
		Entry entry = inline_jobs.front();
		inline_jobs.erase(inline_jobs.begin());
		int64_t key = PlanetTile::key_of(entry.face, entry.level, entry.x, entry.y);
		if (wanted.count(key)) {
			PlanetTile *built = tile_at(key);
			if (built != nullptr) {
				retire(built);
			}
			add(make(entry));
			added += 1;
		}
	}
	while (added < limit) {
		PlanetTile *tile = nullptr;
		{
			std::lock_guard<std::mutex> lock(mutex);
			if (!done.empty()) {
				tile = done.front();
				done.pop_front();
			}
		}
		if (tile == nullptr) {
			break;
		}
		int64_t key = PlanetTile::key_of(tile->get_face(), tile->get_level(), tile->get_tile_x(), tile->get_tile_y());
		pending.erase(key);
		PlanetTile *existing = tile_at(key);
		if (!wanted.count(key) || (existing != nullptr && existing->get_has_collider())) {
			memdelete(tile);
			continue;
		}
		if (existing != nullptr) { // the same tile again, now with a collider
			retire(existing);
		}
		add(tile);
		added += 1;
	}
	adopt_plants();
	free_retired();
	if (added > 0) {
		drop_stale();
	}
}

// Asks for the plants of the built tiles that should have more than they have (nearest first).
void PlanetSurface::queue_plants() {
	struct Wish {
		PlanetTile *tile;
		int detail;
		double distance;
	};
	std::vector<Wish> wishes;
	for (const auto &pair : wanted) {
		PlanetTile *tile = tile_at(pair.first);
		if (tile == nullptr || plant_pending.count(tile->get_instance_id())) {
			continue;
		}
		int wanted_detail = pair.second.plants;
		if (wanted_detail == 0 || wanted_detail <= tile->get_plant_detail()) {
			continue;
		}
		if (!tile->get_plant_grid().is_empty()) {
			wishes.push_back({ tile, wanted_detail, pair.second.distance });
		}
	}
	std::sort(wishes.begin(), wishes.end(), [](const Wish &a, const Wish &b) { return a.distance < b.distance; });
	{
		std::lock_guard<std::mutex> lock(mutex);
		for (const PlantJob &job : plant_jobs) { // the player moved: the old queue may be for places it has left
			plant_pending.erase(job.tile->get_instance_id());
		}
		plant_jobs.clear();
	}
	plant_inline.clear();
	if (!plant_workers.empty()) {
		for (size_t i = 0; i < std::min((size_t)24, wishes.size()); i++) {
			plant_pending.insert(wishes[i].tile->get_instance_id());
			{
				std::lock_guard<std::mutex> lock(mutex);
				plant_jobs.push_back({ wishes[i].tile, wishes[i].detail });
			}
			plant_semaphore->post();
		}
	} else {
		for (size_t i = 0; i < std::min((size_t)4, wishes.size()); i++) {
			plant_inline.push_back({ (uint64_t)wishes[i].tile->get_instance_id(), wishes[i].detail });
		}
	}
}

// Puts the grown plants into their tiles (a few a frame).
void PlanetSurface::adopt_plants() {
	int adopted = 0;
	while (adopted < 4) {
		PlantDone finished;
		bool have = false;
		if (!plant_inline.empty()) {
			auto wish = plant_inline.front();
			plant_inline.erase(plant_inline.begin());
			PlanetTile *wished = Object::cast_to<PlanetTile>(ObjectDB::get_instance(wish.first));
			if (wished == nullptr || tile_at(wished->get_tile_key()) != wished) { // (the tile may have gone since the wish was made)
				continue;
			}
			finished.tile = wished->get_instance_id();
			finished.holder = wished->grow_plants(wish.second);
			finished.detail = wish.second;
			have = true;
		} else {
			std::lock_guard<std::mutex> lock(mutex);
			if (!plant_done.empty()) {
				finished = plant_done.front();
				plant_done.pop_front();
				have = true;
			}
		}
		if (!have) {
			return;
		}
		PlanetTile *tile = Object::cast_to<PlanetTile>(ObjectDB::get_instance(finished.tile));
		if (tile == nullptr) { // the tile went away while its plants were grown
			memdelete(finished.holder);
			continue;
		}
		plant_pending.erase(finished.tile);
		if (tile_at(tile->get_tile_key()) != tile || !tile->is_inside_tree()) {
			memdelete(finished.holder);
			continue;
		}
		Node *old = Object::cast_to<Node>(tile->get_plant_holder());
		if (old != nullptr) {
			old->queue_free();
		}
		tile->add_child(finished.holder);
		tile->set_plant_holder(finished.holder);
		tile->set_plant_detail(finished.detail);
		adopted += 1;
	}
}

// 0..1: how much of what the player needs close by is there: every tile within `ground_metres` built (with its collider where it needs one), and
// the plants of every tile within `plant_metres`.
double PlanetSurface::progress(double p_ground_metres, double p_plant_metres) const {
	int need = 0;
	int have = 0;
	for (const auto &pair : wanted) {
		const Entry &entry = pair.second;
		PlanetTile *built = tile_at(pair.first);
		if (entry.distance < p_ground_metres) {
			need += 1;
			if (built != nullptr && (!entry.collides || built->get_has_collider())) {
				have += 1;
			}
		}
		if (entry.distance >= p_ground_metres && entry.level <= coarse_level()) {
			need += 1; // the planet's coarse shape is part of arriving
			if (built != nullptr) {
				have += 1;
			}
		}
		if (entry.distance < p_plant_metres && entry.plants != 0) {
			need += 1;
			if (built != nullptr && (built->get_plant_grid().is_empty() || built->get_plant_detail() >= entry.plants)) {
				have += 1;
			}
		}
	}
	return need == 0 ? 1.0 : (double)have / (double)need;
}

// Puts every tile where the frame says it is (after the frame moved).
void PlanetSurface::place_all() {
	Array values = tiles.values();
	for (int i = 0; i < values.size(); i++) {
		PlanetTile *tile = Object::cast_to<PlanetTile>((Object *)values[i]);
		tile->set_transform(frame->tile_transform(tile));
	}
}

// Takes a tile out of the world. It is freed later, once no worker is still planting it.
void PlanetSurface::retire(PlanetTile *p_tile) {
	if (tile_at(p_tile->get_tile_key()) == p_tile) {
		tiles.erase(p_tile->get_tile_key());
	}
	if (p_tile->get_parent() != nullptr) {
		p_tile->get_parent()->remove_child(p_tile);
	}
	retired.push_back(p_tile);
}

void PlanetSurface::free_retired() {
	for (int index = (int)retired.size() - 1; index >= 0; index--) {
		PlanetTile *tile = retired[index];
		if (!plant_pending.count(tile->get_instance_id())) {
			memdelete(tile);
			retired.erase(retired.begin() + index);
		}
	}
}

void PlanetSurface::add(PlanetTile *p_tile) {
	p_tile->set_transform(frame->tile_transform(p_tile));
	add_child(p_tile);
	tiles[PlanetTile::key_of(p_tile->get_face(), p_tile->get_level(), p_tile->get_tile_x(), p_tile->get_tile_y())] = p_tile;
}

PlanetTile *PlanetSurface::make(const Entry &p_entry) {
	PlanetTile *tile = memnew(PlanetTile);
	return tile->build(p_entry.face, p_entry.level, p_entry.x, p_entry.y, noise, p_entry.collides);
}

// Removes a tile once every wanted tile that overlaps it is built.
void PlanetSurface::drop_stale() {
	Array keys = tiles.keys();
	for (int i = 0; i < keys.size(); i++) {
		int64_t key = keys[i];
		if (wanted.count(key)) {
			continue;
		}
		PlanetTile *tile = tile_at(key);
		if (tile != nullptr && covered(tile)) {
			retire(tile);
		}
	}
}

bool PlanetSurface::covered(PlanetTile *p_tile) const {
	for (const auto &pair : wanted) {
		if (pair.second.face != p_tile->get_face() || !overlap(p_tile, pair.second)) {
			continue;
		}
		if (tile_at(pair.first) == nullptr) {
			return false;
		}
	}
	return true;
}

// True if the wanted tile `entry` and `tile` are the same patch, or one lies inside the other.
bool PlanetSurface::overlap(PlanetTile *p_tile, const Entry &p_entry) {
	int64_t tile_level = p_tile->get_level();
	if (p_entry.level >= tile_level) {
		int64_t shift = p_entry.level - tile_level;
		return (p_entry.x >> shift) == p_tile->get_tile_x() && (p_entry.y >> shift) == p_tile->get_tile_y();
	}
	int64_t up = tile_level - p_entry.level;
	return (p_tile->get_tile_x() >> up) == p_entry.x && (p_tile->get_tile_y() >> up) == p_entry.y;
}

// A worker that has woken for a job holds it back while the map is open (until it is closed or the game ends).
void PlanetSurface::wait_while_paused() {
	while (paused && !stop) {
		OS::get_singleton()->delay_msec(30);
	}
}

void PlanetSurface::work() {
	while (true) {
		semaphore->wait();
		wait_while_paused();
		Entry job;
		bool have = false;
		{
			std::lock_guard<std::mutex> lock(mutex);
			if (!jobs.empty()) {
				job = jobs.front();
				jobs.pop_front();
				have = true;
			}
		}
		if (stop) {
			return;
		}
		if (!have) {
			continue;
		}
		PlanetTile *tile = make(job);
		std::lock_guard<std::mutex> lock(mutex);
		done.push_back(tile);
	}
}

void PlanetSurface::work_plants() {
	while (true) {
		plant_semaphore->wait();
		wait_while_paused();
		PlantJob job;
		bool have = false;
		{
			std::lock_guard<std::mutex> lock(mutex);
			if (!plant_jobs.empty()) {
				job = plant_jobs.front();
				plant_jobs.pop_front();
				have = true;
			}
		}
		if (stop) {
			return;
		}
		if (!have) {
			continue;
		}
		Node3D *holder = job.tile->grow_plants(job.detail);
		std::lock_guard<std::mutex> lock(mutex);
		plant_done.push_back({ job.tile->get_instance_id(), holder, job.detail });
	}
}
