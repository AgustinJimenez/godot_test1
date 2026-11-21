#include "player_stair_controller_native.h"

#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
const double TREAD_PROBE_FORWARD = 0.04;
const double TREAD_NORMAL_MIN_DOT = 0.9;
const double REPEAT_CONTACT_DISTANCE = 1.0;
// Seamless authored stair proxies use this dedicated layer so ordinary slope motion, not discrete riser stepping, owns the physical root.
const uint32_t CONTINUOUS_TRAVERSAL_LAYER = 1u << 4;
const double CONTINUOUS_FLOOR_PROBE_UP = 0.1;
const double CONTINUOUS_FLOOR_PROBE_DOWN = 0.75;
const double INF_D = std::numeric_limits<double>::infinity();

bool approx(double p_a, double p_b) { // GDScript is_equal_approx
	if (p_a == p_b) {
		return true;
	}
	const double tolerance = std::max(0.00001 * std::abs(p_a), 0.00001);
	return std::abs(p_a - p_b) < tolerance;
}

double xz_distance(const Vector3 &p_a, const Vector3 &p_b) {
	return std::hypot((double)p_a.x - (double)p_b.x, (double)p_a.z - (double)p_b.z);
}
} // namespace

void PlayerStairControllerNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "host", "body", "third_person_arm"), &PlayerStairControllerNative::setup);
	ClassDB::bind_method(D_METHOD("begin_frame"), &PlayerStairControllerNative::begin_frame);
	ClassDB::bind_method(D_METHOD("is_climbing"), &PlayerStairControllerNative::is_climbing);
	ClassDB::bind_method(D_METHOD("has_recent_transition"), &PlayerStairControllerNative::has_recent_transition);
	ClassDB::bind_method(D_METHOD("is_near_stairs"), &PlayerStairControllerNative::is_near_stairs);
	ClassDB::bind_method(D_METHOD("get_debug_state"), &PlayerStairControllerNative::get_debug_state);
	ClassDB::bind_method(D_METHOD("get_body_rest_y"), &PlayerStairControllerNative::get_body_rest_y);
	ClassDB::bind_method(D_METHOD("apply_step_up", "motion", "delta", "step_height", "step_rise_rate"), &PlayerStairControllerNative::apply_step_up);
	ClassDB::bind_method(D_METHOD("apply_step_down", "motion", "delta", "step_height", "step_fall_rate", "jump_velocity_threshold"), &PlayerStairControllerNative::apply_step_down);
	ClassDB::bind_method(D_METHOD("is_short_step_down", "frame_start_y", "horizontal_motion", "step_height", "jump_velocity_threshold"), &PlayerStairControllerNative::is_short_step_down);
	ClassDB::bind_method(D_METHOD("record_presentation_delta", "delta_y", "step_height", "balance_strength", "balance_limit"), &PlayerStairControllerNative::record_presentation_delta);
	ClassDB::bind_method(D_METHOD("update_presentation", "delta", "hover_speed"), &PlayerStairControllerNative::update_presentation);
	ClassDB::bind_method(D_METHOD("reset"), &PlayerStairControllerNative::reset);

	ClassDB::bind_method(D_METHOD("get_hover_offset_y"), &PlayerStairControllerNative::get_hover_offset_y);
	ClassDB::bind_method(D_METHOD("set_hover_offset_y", "value"), &PlayerStairControllerNative::set_hover_offset_y);
	ClassDB::bind_method(D_METHOD("get_balance_offset_y"), &PlayerStairControllerNative::get_balance_offset_y);
	ClassDB::bind_method(D_METHOD("set_balance_offset_y", "value"), &PlayerStairControllerNative::set_balance_offset_y);
	ClassDB::bind_method(D_METHOD("get_camera_snap_y"), &PlayerStairControllerNative::get_camera_snap_y);
	ClassDB::bind_method(D_METHOD("set_camera_snap_y", "value"), &PlayerStairControllerNative::set_camera_snap_y);
	ClassDB::bind_method(D_METHOD("get_consumed_horizontal_motion"), &PlayerStairControllerNative::get_consumed_horizontal_motion);
	ClassDB::bind_method(D_METHOD("set_consumed_horizontal_motion", "value"), &PlayerStairControllerNative::set_consumed_horizontal_motion);
	ClassDB::bind_method(D_METHOD("get_continuous_traversal_active"), &PlayerStairControllerNative::get_continuous_traversal_active);
	ClassDB::bind_method(D_METHOD("set_continuous_traversal_active", "value"), &PlayerStairControllerNative::set_continuous_traversal_active);
	ClassDB::add_property("PlayerStairControllerNative", PropertyInfo(Variant::FLOAT, "hover_offset_y"), "set_hover_offset_y", "get_hover_offset_y");
	ClassDB::add_property("PlayerStairControllerNative", PropertyInfo(Variant::FLOAT, "balance_offset_y"), "set_balance_offset_y", "get_balance_offset_y");
	ClassDB::add_property("PlayerStairControllerNative", PropertyInfo(Variant::FLOAT, "camera_snap_y"), "set_camera_snap_y", "get_camera_snap_y");
	ClassDB::add_property("PlayerStairControllerNative", PropertyInfo(Variant::BOOL, "consumed_horizontal_motion"), "set_consumed_horizontal_motion", "get_consumed_horizontal_motion");
	ClassDB::add_property("PlayerStairControllerNative", PropertyInfo(Variant::BOOL, "continuous_traversal_active"), "set_continuous_traversal_active", "get_continuous_traversal_active");
}

CharacterBody3D *PlayerStairControllerNative::host() const {
	return Object::cast_to<CharacterBody3D>(UtilityFunctions::instance_from_id(host_id));
}

Node3D *PlayerStairControllerNative::node(uint64_t p_id) const {
	return p_id == 0 ? nullptr : Object::cast_to<Node3D>(UtilityFunctions::instance_from_id(p_id)); // null when freed, like is_instance_valid
}

Dictionary PlayerStairControllerNative::ray(const Vector3 &p_from, const Vector3 &p_to, uint32_t p_mask, bool p_bodies_only) const {
	CharacterBody3D *body = host();
	Ref<World3D> world = body->get_world_3d();
	PhysicsDirectSpaceState3D *space = world.is_valid() ? world->get_direct_space_state() : nullptr;
	if (space == nullptr) {
		return Dictionary();
	}
	Ref<PhysicsRayQueryParameters3D> query;
	query.instantiate();
	query->set_from(p_from);
	query->set_to(p_to);
	query->set_collision_mask(p_mask);
	TypedArray<RID> exclude;
	exclude.push_back(body->get_rid());
	query->set_exclude(exclude);
	if (p_bodies_only) {
		query->set_collide_with_areas(false);
		query->set_collide_with_bodies(true);
	}
	return space->intersect_ray(query);
}

void PlayerStairControllerNative::setup(CharacterBody3D *p_host, Node3D *p_body, Node3D *p_third_person_arm) {
	host_id = p_host->get_instance_id();
	body_id = p_body->get_instance_id();
	arm_id = p_third_person_arm->get_instance_id();
	body_rest_y = p_body->get_position().y;
	arm_rest_y = p_third_person_arm->get_position().y;
	balance_smoothed_root_y = p_host->get_global_position().y;
}

void PlayerStairControllerNative::begin_frame() {
	consumed_horizontal_motion = false;
	continuous_traversal_active = false;
	// The repeat guard is local to one riser crossing, not permanent level history. After walking away (commonly down the staircase), returning to
	// the same first riser must be allowed to start a fresh climb.
	if (std::isfinite(last_tread_y) && xz_distance(host()->get_global_position(), last_contact) >= REPEAT_CONTACT_DISTANCE) {
		last_tread_y = -INF_D;
		last_contact = Vector3(INF_D, INF_D, INF_D);
	}
}

bool PlayerStairControllerNative::has_recent_transition() const {
	return climb_active || std::isfinite(pending_step_down_y) || std::abs(hover_offset_y) > 0.005;
}

// True only around real stairs: a climb in progress, a step down being taken, or a tread riser touched within REPEAT_CONTACT_DISTANCE of here. Unlike
// has_recent_transition it ignores the hover offset, which any floor snap on natural terrain also sets (the walk slowdown used to trigger there).
bool PlayerStairControllerNative::is_near_stairs() const {
	if (climb_active || std::isfinite(pending_step_down_y)) {
		return true;
	}
	if (!std::isfinite(last_tread_y)) {
		return false;
	}
	return xz_distance(host()->get_global_position(), last_contact) < REPEAT_CONTACT_DISTANCE;
}

Dictionary PlayerStairControllerNative::get_debug_state() const {
	Dictionary state;
	state["climbing"] = climb_active;
	state["climb_target_y"] = climb_target_y;
	state["pending_step_down_y"] = pending_step_down_y;
	state["last_tread_y"] = last_tread_y;
	state["last_contact"] = last_contact;
	state["consumed_horizontal_motion"] = consumed_horizontal_motion;
	state["continuous_traversal"] = continuous_traversal_active;
	state["recent_transition"] = has_recent_transition();
	state["near_stairs"] = is_near_stairs();
	state["balance_offset_y"] = balance_offset_y;
	state["camera_snap_y"] = camera_snap_y;
	return state;
}

bool PlayerStairControllerNative::uses_continuous_traversal(const Ref<KinematicCollision3D> &p_collision) const {
	CollisionObject3D *collider = Object::cast_to<CollisionObject3D>(p_collision->get_collider());
	return collider != nullptr && (collider->get_collision_layer() & CONTINUOUS_TRAVERSAL_LAYER) != 0;
}

double PlayerStairControllerNative::apply_step_up(const Vector3 &p_motion, double p_delta, double p_step_height, double p_step_rise_rate) {
	CharacterBody3D *body = host();
	if (climb_active) {
		return continue_step_climb(p_motion, p_delta);
	}
	// Do not gate on is_on_floor(): touching the riser can unset it briefly.
	Tread tread;
	if (!p_motion.is_zero_approx()) {
		Ref<KinematicCollision3D> wall;
		wall.instantiate();
		if (body->test_move(body->get_global_transform(), p_motion, wall)) {
			// A seamless proxy can have shallow transition facets that satisfy the tread-normal threshold. Treating each one as a tiny riser made
			// climb_active alternate every frame and created a root-Y sawtooth.
			if (uses_continuous_traversal(wall)) {
				continuous_traversal_active = true;
				return 0.0;
			}
			Transform3D lifted = body->get_global_transform().translated(Vector3(0.0, (real_t)p_step_height, 0.0));
			if (!body->test_move(lifted, p_motion)) {
				tread = find_step_up_tread(p_motion, wall, p_step_height);
				if (tread.valid) {
					lifted.origin.y = (real_t)((double)body->get_global_position().y + tread.rise);
					if (body->test_move(lifted, p_motion)) {
						tread = Tread();
					}
				}
			}
		}
	}
	if (tread.valid) {
		last_tread_y = tread.y;
		last_contact = tread.contact;
		climb_start_y = body->get_global_position().y;
		climb_target_y = climb_start_y + tread.rise;
		// A short trapezoidal velocity profile rounds lift-off/touchdown while retaining almost all of the old constant-speed interval. A full
		// smoothstep lasted 50% longer and exposed the swing foot to the riser for extra frames, measurably worsening body penetration.
		climb_peak_speed = std::max(p_step_rise_rate, 0.001);
		// One 60Hz frame on each end is enough to replace the discontinuity without materially lengthening the swing/riser overlap window.
		climb_acceleration_time = std::min(1.0 / 60.0, tread.rise / climb_peak_speed);
		climb_duration = tread.rise / climb_peak_speed + climb_acceleration_time;
		climb_elapsed = 0.0;
		climb_active = true;
		return continue_step_climb(p_motion, p_delta);
	}
	return 0.0;
}

double PlayerStairControllerNative::continue_step_climb(const Vector3 &p_motion, double p_delta) {
	CharacterBody3D *body = host();
	const double previous_y = body->get_global_position().y;
	climb_elapsed = std::min(climb_elapsed + p_delta, climb_duration);
	const double distance = climb_target_y - climb_start_y;
	const double remaining_time = climb_duration - climb_elapsed;
	double travelled;
	if (climb_elapsed < climb_acceleration_time) {
		travelled = 0.5 * climb_peak_speed / climb_acceleration_time * climb_elapsed * climb_elapsed;
	} else if (remaining_time < climb_acceleration_time) {
		travelled = distance - (0.5 * climb_peak_speed / climb_acceleration_time * remaining_time * remaining_time);
	} else {
		travelled = climb_peak_speed * (climb_elapsed - 0.5 * climb_acceleration_time);
	}
	const double desired_y = climb_start_y + travelled;
	const double rise = desired_y - previous_y;
	if (body->test_move(body->get_global_transform(), Vector3(0.0, (real_t)rise, 0.0))) {
		clear_climb();
		return 0.0;
	}
	Vector3 next_position = body->get_global_position();
	next_position.y += (real_t)rise;
	body->set_global_position(next_position);
	consumed_horizontal_motion = true;
	body->set_velocity(Vector3());
	// Always applied: gating horizontal travel at each partial height caused one-to-two stationary frames followed by a visible catch-up jump.
	body->set_global_position(body->get_global_position() + p_motion);
	if (climb_elapsed >= climb_duration || approx(body->get_global_position().y, climb_target_y)) {
		body->set_global_position(Vector3(body->get_global_position().x, (real_t)climb_target_y, body->get_global_position().z));
		clear_climb();
		body->apply_floor_snap();
	}
	return std::max((double)body->get_global_position().y - previous_y, 0.0);
}

void PlayerStairControllerNative::clear_climb() {
	climb_start_y = -INF_D;
	climb_target_y = -INF_D;
	climb_duration = 0.0;
	climb_elapsed = 0.0;
	climb_acceleration_time = 0.0;
	climb_peak_speed = 0.0;
	climb_active = false;
}

PlayerStairControllerNative::Tread PlayerStairControllerNative::find_step_up_tread(const Vector3 &p_motion, const Ref<KinematicCollision3D> &p_wall, double p_step_height) const {
	CharacterBody3D *body = host();
	const Vector3 direction = p_motion.normalized();
	const Vector3 contact = p_wall->get_position();
	const Vector3 probe_xz = contact + direction * (real_t)TREAD_PROBE_FORWARD;
	const double margin = body->get_safe_margin();
	const double host_y = body->get_global_position().y;
	const uint32_t mask = body->get_collision_mask();
	const Dictionary hit = ray(Vector3(probe_xz.x, (real_t)(host_y + p_step_height + margin), probe_xz.z), Vector3(probe_xz.x, (real_t)(host_y + margin), probe_xz.z), mask, false);
	if (hit.is_empty()) {
		return Tread();
	}
	// Compare floor surfaces instead of assigning the tread height directly; the CharacterBody origin is not necessarily at its collider sole.
	const Vector3 here = body->get_global_position();
	const Dictionary current_floor = ray(here + Vector3(0, 1, 0) * (real_t)(p_step_height + margin), here - Vector3(0, 1, 0) * (real_t)(p_step_height + margin), mask, false);
	if (current_floor.is_empty()) {
		return Tread();
	}
	const Vector3 tread_normal = hit["normal"];
	const double tread_y = ((Vector3)hit["position"]).y;
	const double current_floor_y = ((Vector3)current_floor["position"]).y;
	const double rise = tread_y - current_floor_y;
	if ((double)tread_normal.dot(Vector3(0, 1, 0)) < TREAD_NORMAL_MIN_DOT) {
		return Tread();
	}
	const double repeated_contact = std::hypot((double)probe_xz.x - (double)last_contact.x, (double)probe_xz.z - (double)last_contact.z);
	if (approx(tread_y, last_tread_y) && repeated_contact < REPEAT_CONTACT_DISTANCE) {
		return Tread();
	}
	if (rise <= margin || rise > p_step_height + margin) {
		return Tread();
	}
	Tread tread;
	tread.valid = true;
	tread.y = tread_y;
	tread.rise = rise;
	tread.contact = probe_xz;
	return tread;
}

double PlayerStairControllerNative::apply_step_down(const Vector3 &p_motion, double p_delta, double p_step_height, double p_step_fall_rate, double p_jump_velocity_threshold) {
	CharacterBody3D *body = host();
	if (p_motion.is_zero_approx() || (double)body->get_velocity().y > p_jump_velocity_threshold) {
		pending_step_down_y = -INF_D;
		return 0.0;
	}
	if (!std::isfinite(pending_step_down_y)) {
		const Tread tread = find_step_down_tread(p_motion, p_step_height);
		if (!tread.valid) {
			return 0.0;
		}
		pending_step_down_y = tread.y;
	}
	const double remaining_drop = (double)body->get_global_position().y - pending_step_down_y;
	if (remaining_drop <= body->get_safe_margin()) {
		pending_step_down_y = -INF_D;
		return 0.0;
	}
	// Move horizontally first, then lower the capsule by only one controlled increment. The old implementation swept the entire remaining drop in a
	// single tick; a 35cm tread therefore produced matching 25cm+ root/head discontinuities once the rounded heel cleared the old edge.
	Transform3D moved = body->get_global_transform();
	moved.origin += p_motion;
	const double frame_drop = std::min(remaining_drop, std::max(p_step_fall_rate, 0.001) * p_delta);
	Ref<KinematicCollision3D> collision;
	collision.instantiate();
	const Vector3 down_motion = Vector3(0, -1, 0) * (real_t)(frame_drop + body->get_safe_margin());
	if (body->test_move(moved, down_motion, collision)) {
		// The extra safe-margin distance belongs only to the contact probe. It must never become presentation/root travel: doing so produced nearly
		// 10cm descent frames despite a 4.7cm configured frame ceiling.
		const double collision_drop = std::max(-(double)collision->get_travel().y, 0.0);
		moved.origin.y -= (real_t)std::min(collision_drop, frame_drop);
	} else {
		moved.origin += Vector3(0, -1, 0) * (real_t)frame_drop;
	}
	moved.origin.y = (real_t)std::max((double)moved.origin.y, pending_step_down_y);
	const double previous_y = body->get_global_position().y;
	body->set_global_transform(moved);
	Vector3 velocity = body->get_velocity();
	velocity.y = 0.0;
	body->set_velocity(velocity);
	consumed_horizontal_motion = true;
	if ((double)body->get_global_position().y <= pending_step_down_y + body->get_safe_margin()) {
		pending_step_down_y = -INF_D;
		body->apply_floor_snap();
	}
	return std::max(previous_y - (double)body->get_global_position().y, 0.0);
}

PlayerStairControllerNative::Tread PlayerStairControllerNative::find_step_down_tread(const Vector3 &p_motion, double p_step_height) const {
	CharacterBody3D *body = host();
	const double probe_height = p_step_height + body->get_safe_margin() + 0.05;
	const uint32_t mask = body->get_collision_mask();
	const Vector3 here = body->get_global_position();
	const Vector3 up(0, 1, 0);
	const Dictionary current_floor = ray(here + up * (real_t)probe_height, here - up * (real_t)probe_height, mask, false);
	const Vector3 next_position = here + p_motion;
	const Dictionary next_floor = ray(next_position + up * (real_t)probe_height, next_position - up * (real_t)probe_height, mask, false);
	if (current_floor.is_empty() || next_floor.is_empty()) {
		return Tread();
	}
	const Vector3 current_normal = current_floor["normal"];
	const Vector3 next_normal = next_floor["normal"];
	if ((double)current_normal.dot(up) < TREAD_NORMAL_MIN_DOT || (double)next_normal.dot(up) < TREAD_NORMAL_MIN_DOT) {
		return Tread();
	}
	const double drop = (double)((Vector3)current_floor["position"]).y - (double)((Vector3)next_floor["position"]).y;
	if (drop <= body->get_safe_margin() || drop > p_step_height + body->get_safe_margin()) {
		return Tread();
	}
	Tread tread;
	tread.valid = true;
	tread.y = ((Vector3)next_floor["position"]).y;
	return tread;
}

bool PlayerStairControllerNative::is_short_step_down(double p_frame_start_y, const Vector3 &p_horizontal_motion, double p_step_height, double p_jump_velocity_threshold) const {
	CharacterBody3D *body = host();
	const double drop = p_frame_start_y - (double)body->get_global_position().y;
	return !p_horizontal_motion.is_zero_approx() && body->is_on_floor() && (double)body->get_floor_normal().dot(Vector3(0, 1, 0)) > 0.99 && drop > 0.001 &&
			drop <= p_step_height + 0.01 && (double)body->get_velocity().y <= p_jump_velocity_threshold;
}

void PlayerStairControllerNative::record_presentation_delta(double p_delta_y, double p_step_height, double p_balance_strength, double p_balance_limit) {
	hover_offset_y = std::clamp(hover_offset_y + p_delta_y, -p_step_height, p_step_height);
	// Low-pass the root trajectory rather than applying each frame's delta as an unrelated Spine offset. The old per-frame value changed abruptly at
	// lift-off/touchdown and recreated the path corner it was meant to hide.
	if (!balance_active) {
		balance_smoothed_root_y = (double)host()->get_global_position().y + p_delta_y;
		balance_active = true;
	}
	balance_strength = p_balance_strength;
	balance_limit = p_balance_limit;
}

void PlayerStairControllerNative::update_presentation(double p_delta, double p_hover_speed) {
	CharacterBody3D *body = host();
	continuous_traversal_active = continuous_traversal_active || has_continuous_floor_contact();
	// Hover/balance offsets hide discrete riser transitions. On a seamless traversal surface they instead lag behind the already-smooth slope and
	// translate Spine away from Hips, visibly compressing/stretching the mesh.
	if (continuous_traversal_active) {
		hover_offset_y = 0.0;
		balance_offset_y = 0.0;
		balance_active = false;
		balance_smoothed_root_y = body->get_global_position().y;
		apply_presentation_offsets();
		return;
	}
	const double blend = 1.0 - std::exp(-p_hover_speed * p_delta);
	hover_offset_y += (0.0 - hover_offset_y) * blend;
	camera_snap_y += (0.0 - camera_snap_y) * blend;
	if (balance_active) {
		const double root_y = body->get_global_position().y;
		balance_smoothed_root_y += (root_y - balance_smoothed_root_y) * blend;
		balance_offset_y = std::clamp((balance_smoothed_root_y - root_y) * balance_strength, -balance_limit, balance_limit);
		if (!has_recent_transition() && std::abs(balance_offset_y) < 0.0005) {
			balance_active = false;
			balance_smoothed_root_y = root_y;
			balance_offset_y = 0.0;
		}
	}
	apply_presentation_offsets();
}

bool PlayerStairControllerNative::has_continuous_floor_contact() const {
	// A walkable floor does not necessarily appear in CharacterBody3D's slide collision list every frame (especially while floor snapping or standing
	// still). Query the dedicated proxy layer directly so presentation state cannot flicker merely because no slide was reported this tick.
	CharacterBody3D *body = host();
	const Vector3 here = body->get_global_position();
	const Vector3 up(0, 1, 0);
	if (!ray(here + up * (real_t)CONTINUOUS_FLOOR_PROBE_UP, here - up * (real_t)CONTINUOUS_FLOOR_PROBE_DOWN, CONTINUOUS_TRAVERSAL_LAYER, true).is_empty()) {
		return true;
	}
	for (int index = 0; index < body->get_slide_collision_count(); index++) {
		Ref<KinematicCollision3D> collision = body->get_slide_collision(index);
		if ((double)collision->get_normal().dot(up) <= 0.0) {
			continue;
		}
		if (uses_continuous_traversal(collision)) {
			return true;
		}
	}
	return false;
}

void PlayerStairControllerNative::apply_presentation_offsets() {
	if (Node3D *body = node(body_id)) {
		Vector3 position = body->get_position();
		position.y = (real_t)body_rest_y;
		body->set_position(position);
	}
	if (Node3D *arm = node(arm_id)) {
		Vector3 position = arm->get_position();
		position.y = (real_t)(arm_rest_y + hover_offset_y + camera_snap_y);
		arm->set_position(position);
	}
}

void PlayerStairControllerNative::reset() {
	hover_offset_y = 0.0;
	camera_snap_y = 0.0;
	balance_offset_y = 0.0;
	clear_climb();
	last_tread_y = -INF_D;
	last_contact = Vector3(INF_D, INF_D, INF_D);
	pending_step_down_y = -INF_D;
	balance_active = false;
	balance_smoothed_root_y = host()->get_global_position().y;
	balance_strength = 0.0;
	balance_limit = 0.0;
	consumed_horizontal_motion = false;
	continuous_traversal_active = false;
	if (Node3D *body = node(body_id)) {
		Vector3 position = body->get_position();
		position.y = (real_t)body_rest_y;
		body->set_position(position);
	}
	if (Node3D *arm = node(arm_id)) {
		Vector3 position = arm->get_position();
		position.y = (real_t)arm_rest_y;
		arm->set_position(position);
	}
}
