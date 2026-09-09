extends SceneTree
## Permanent regression suite for tests/manual/als_locomotion_prototype/
## als_locomotion_prototype.gd - consolidates ~9 scratch scripts written and
## thrown away individually while porting real ALS values into that
## prototype (turn-in-place, rotation rate, mantle, spine twist, camera,
## crouch, jump play rate, gait/sprint blending, airborne blend easing, air
## lean, land prediction). Nothing here was invented for this file - every
## check is a real assertion that caught (or would have caught) an actual
## bug during that work; see AGENT_TASKS/016's status log for the story
## behind each one.
##
## Run: godot --headless --script res://tests/automated/als_locomotion_prototype/locomotion_test.gd
## Exit code 0 = all pass, 1 = at least one failure (also printed to stdout).
##
## Each test_xxx() function is independent: it re-instantiates the prototype
## scene fresh rather than sharing state with the others, so a failure in one
## can't cascade into false failures in the next. This costs some runtime
## (each scene instantiation + settle is a few seconds) but was worth it -
## several of the original scratch scripts chained scenarios in one instance
## and a bug in an earlier scenario silently corrupted a later assertion.

var _scene: Node
var _body: CharacterBody3D
var _facing: Node3D
var _skel: Skeleton3D
var _tree: AnimationTree
var _fails := 0
var _total_fails := 0


func _init() -> void:
	_run_all.call_deferred()


# ---------------------------------------------------------------- helpers --

func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("  %s  %-56s %s" % ["PASS" if ok else "FAIL", label, detail])


# For boolean actual-vs-expected checks (e.g. did a mantle attempt succeed)
# where the interesting detail is simply "got X, expected Y".
func _check_bool(label: String, actual: bool, expected: bool) -> void:
	_check(label, actual == expected, "got=%s expect=%s" % [actual, expected])


func _settle(n: int = 20) -> void:
	for i in n:
		await physics_frame


func _new_scene() -> void:
	_scene = (load("res://tests/manual/als_locomotion_prototype/als_locomotion_prototype.tscn")
			as PackedScene).instantiate()
	root.add_child(_scene)
	for i in 15:
		await process_frame
	_body = _scene.find_child("PrototypeBody", true, false)
	_facing = _body.find_child("CharacterFacing", true, false)
	_skel = _scene.get("_skeleton")
	_tree = _scene.find_child("AnimationTree", true, false)
	_body.global_position = Vector3(0.0, 0.0, 8.0)
	await _settle()


func _teardown_scene() -> void:
	_scene.queue_free()
	await process_frame


func _drive(speed: float, frames: int = 5) -> void:
	for i in frames:
		_body.velocity = Vector3(0.0, _body.velocity.y, -speed)
		await physics_frame


# Head height ABOVE THE FEET - independent of what the terrain is doing under
# the character, which world-space pivot height is not.
func _head_above_body() -> float:
	var idx := _skel.find_bone(_facing.call("resolve_bone_name", &"Head"))
	var head := (_skel.global_transform * _skel.get_bone_global_pose(idx)).origin
	return head.y - _body.global_position.y


func _add_static_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	# StaticBody3D + BoxShape3D, never CSGBox3D: a CSG box added mid-run has
	# been observed to sometimes not register collision in time, which makes
	# a case pass/fail for reasons unrelated to the code under test.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	_scene.add_child(body)
	return body


func _section(name: String) -> void:
	print("--- %s ---" % name)


# --------------------------------------------------------- rotation / TIP --

func _test_rotation_and_turn_in_place() -> void:
	_section("rotation rate + turn-in-place")
	await _new_scene()

	# CalculateGroundedRotationRate's aim-yaw-rate multiplier: the body must
	# converge measurably faster when the camera is being whipped around.
	var slow := await _converge_rotation(0.0)
	var fast := await _converge_rotation(300.0)
	_check("aim rate 300 converges faster than 0", fast > slow + 1.0,
			"slow=%.2f deg  fast=%.2f deg" % [slow, fast])
	_check("neither overshoots the 90 deg target", slow <= 90.01 and fast <= 90.01,
			"slow=%.2f fast=%.2f" % [slow, fast])

	# Idle turn-in-place: settle, snap the camera 90 deg, hold it, and it
	# should fire after roughly ALS's real mapped delay (0.75 * 45/135 =
	# 0.25s for a 90 deg angle), not instantly and not never.
	_scene.set("_rotation_mode", 1)  # LOOKING_DIRECTION
	_scene.set("_is_turning", false)
	_body.global_position = Vector3(0.0, 0.0, 8.0)
	_facing.rotation.y = 0.0
	_scene.set("_rotation_target_yaw", 0.0)
	var pivot: Node3D = _scene.get("_camera_pivot")
	pivot.rotation.y = 0.0
	await _settle(30)
	_check("settled on floor before turn test", _body.is_on_floor(),
			"is_on_floor=%s" % _body.is_on_floor())

	pivot.rotation.y = deg_to_rad(90.0)
	var fired_after := -1
	for i in 60:
		await physics_frame
		if _scene.get("_is_turning"):
			fired_after = i
			break
	_check("idle turn-in-place fires on a held 90 deg", fired_after >= 0,
			"fired after %d physics frames (~%.2fs)" % [fired_after, fired_after / 60.0])

	# A camera held only 20 deg away (under the real 45 deg TurnCheckMinAngle)
	# must never fire.
	_scene.set("_is_turning", false)
	_facing.rotation.y = 0.0
	_scene.set("_rotation_target_yaw", 0.0)
	pivot.rotation.y = deg_to_rad(20.0)
	var fired_small := false
	for i in 60:
		await physics_frame
		if _scene.get("_is_turning"):
			fired_small = true
			break
	_check("20 deg (under 45 threshold) never fires", not fired_small,
			"fired=%s" % fired_small)

	await _teardown_scene()


# Drives _smooth_character_rotation directly at a fixed aim yaw rate and
# returns how far (deg) the body got toward a 90-degree target in 30 fixed
# 60Hz steps.
func _converge_rotation(aim_rate: float) -> float:
	_scene.set("_rotation_target_yaw", 0.0)
	_facing.rotation.y = 0.0
	var target := deg_to_rad(90.0)
	for i in 30:
		_scene.set("_aim_yaw_rate_deg", aim_rate)
		_scene.call("_smooth_character_rotation", target, 500.0, 1.0 / 60.0)
	return rad_to_deg(_facing.rotation.y)


# --------------------------------------------------------------- mantling --

func _test_mantle() -> void:
	_section("mantle (real ALSMantleComponent trace settings)")
	await _new_scene()

	# Low ledge (top y=1.0) at x=0, z in [3,5]; high ledge (top y=1.8) at
	# x=4, z in [3,5] - both built into the prototype scene itself.
	_check_bool("low ledge (1.0m), grounded profile", await _mantles(0.0, 2.6, true), true)
	_check_bool("high ledge (1.8m), grounded profile", await _mantles(4.0, 2.6, true), true)

	# Real grounded/falling split: falling maxes out at 1.5m, so the 1.8m
	# ledge is reachable standing but NOT caught mid-jump.
	_check_bool("low ledge (1.0m), falling profile", await _mantles(0.0, 2.6, false), true)
	_check_bool("high ledge (1.8m) REJECTED mid-jump", await _mantles(4.0, 2.6, false), false)

	# Real reach: grounded 0.75m. Standing back at 2.15 (0.85m from the wall
	# face at z=3.0) is outside it.
	_check_bool("out of reach at 0.85m, grounded", await _mantles(0.0, 2.15, true), false)

	# Room check (CapsuleHasRoomCheck port): a 0.5m slot narrower than the
	# 0.7m body, caught at sweep-start. Centred on z=3.15, the REAL landing
	# spot (the downward-trace hit point itself, pushed only 15cm into the
	# ledge - not the +0.5m further forward this prototype used to add, a
	# redundant invented offset removed after a live user report of
	# clipping; see the status log). This moved from the old z~3.8 for the
	# same reason.
	#
	# The earlier "low overhang, mid-sweep" case is gone, not just moved:
	# with the redundant offset removed, the ledge-detection trace and the
	# room-check sweep now correctly happen at the SAME real XZ column (they
	# always did in real ALS - `CapsuleLocationFBase` IS `DownTraceLocation`,
	# see ALSMantleComponent.cpp). Any obstruction low enough to fail the
	# room check at that column is now, correctly, ALSO in the path of the
	# ledge-detection sweep itself - so it gets found (and rejected or
	# reinterpreted) as part of ledge detection, not preserved as an
	# independent "valid ledge, blocked room" scenario. That was only
	# possible to construct before because of the 0.5m artificial gap
	# between the two locations - itself the bug just fixed. The mid-sweep
	# (cast_motion) branch of _capsule_has_room is still exercised for real,
	# just via a different real call site: see the crouch section's "low
	# ceiling BLOCKS standing up" case, which hits the identical code path.
	var slot_a := _add_static_box(Vector3(1.0, 2.0, 0.6), Vector3(-0.75, 2.0, 3.15))
	var slot_b := _add_static_box(Vector3(1.0, 2.0, 0.6), Vector3(0.75, 2.0, 3.15))
	await _settle(12)
	_check_bool("0.5m slot rejects mantle (start-penetration)",
			await _mantles(0.0, 2.6, true), false)
	slot_a.queue_free()
	slot_b.queue_free()
	await _settle(12)
	_check_bool("...and mantles again once removed", await _mantles(0.0, 2.6, true), true)

	# --- real PositionCorrectionCurve-driven motion (ALSMantleComponent::
	#     MantleUpdate, not an invented arc) ---
	var low: Dictionary = _scene.get("_mantle_low_curves")
	_check("low pos_alpha curve: ~0 before its 0.3 ramp start",
			(low["pos_alpha"] as Curve).sample(0.2) < 0.01,
			"%.4f" % (low["pos_alpha"] as Curve).sample(0.2))
	_check_bool("low pos_alpha curve: 1.0 at t=0.7 (end of real ramp)",
			absf((low["pos_alpha"] as Curve).sample(0.7) - 1.0) < 0.01, true)
	var high: Dictionary = _scene.get("_mantle_high_curves")
	_check("high curve domain extends to 2.1 (real, longer than low's [0,1])",
			absf((high["pos_alpha"] as Curve).max_domain - 2.1) < 0.001,
			"%.3f" % (high["pos_alpha"] as Curve).max_domain)

	# Load-bearing regression: the new curve-driven path must still land
	# EXACTLY where the old smoothstep lerp did - the curve reshapes the
	# JOURNEY, not the destination.
	var low_final := await _run_full_mantle(0.0, 2.6, true)
	_check("low mantle lands EXACTLY on target (curve math is a means, not an end)",
			(low_final[0] as Vector3).distance_to(low_final[1] as Vector3) < 0.01,
			"final=%s target=%s" % [low_final[0], low_final[1]])
	var high_final := await _run_full_mantle(4.0, 2.6, true)
	_check("high mantle lands EXACTLY on target too (exercises the 2.1s-domain curve)",
			(high_final[0] as Vector3).distance_to(high_final[1] as Vector3) < 0.01,
			"final=%s target=%s" % [high_final[0], high_final[1]])

	# The actual point of porting this: the path must genuinely differ from
	# a naive straight lerp, or the real per-axis curve timing did nothing.
	var mid_run := await _run_full_mantle(0.0, 2.6, true)
	var mid_actual := mid_run[2] as Vector3
	var mid_naive := Vector3(0.0, 0.0, 2.6).lerp(mid_run[1] as Vector3, 0.3)
	_check("mid-climb position diverges from a naive straight lerp",
			mid_actual.distance_to(mid_naive) > 0.05,
			"curve-driven=%s naive-lerp=%s dist=%.3f"
					% [mid_actual, mid_naive, mid_actual.distance_to(mid_naive)])

	# Real PlayRate is a per-asset CONSTANT (1.0 for the 1m asset, 1.2 for
	# the 2m one - both range endpoints are equal, so no interpolation
	# actually happens) - and real StartingPosition lets a shorter real
	# ledge skip ahead into the curve rather than always starting at 0.
	await _mantles(0.0, 2.6, true)  # low ledge, height 1.0m = this asset's own HighHeight
	_check("low mantle PlayRate is the real constant 1.0",
			is_equal_approx(_scene.get("_mantle_play_rate"), 1.0),
			"%.3f" % _scene.get("_mantle_play_rate"))
	_check("low mantle at its OWN HighHeight uses StartingPosition 0 (full curve)",
			is_zero_approx(_scene.get("_mantle_starting_position")),
			"%.4f" % _scene.get("_mantle_starting_position"))
	await _settle(30)

	await _mantles(4.0, 2.6, true)  # high ledge, height 1.8m - between this asset's Low/High
	_check("high mantle PlayRate is the real constant 1.2",
			is_equal_approx(_scene.get("_mantle_play_rate"), 1.2),
			"%.3f" % _scene.get("_mantle_play_rate"))
	_check("high mantle at a mid-range height skips partway into the curve",
			_scene.get("_mantle_starting_position") > 0.01
					and _scene.get("_mantle_starting_position") < 0.6,
			"%.4f (expect between 0 and HighStartPosition's own range max 0.6)"
					% _scene.get("_mantle_starting_position"))

	await _teardown_scene()


func _test_mantle_hand_ik() -> void:
	_section("mantle hand IK (prototype-only, not an ALS mechanism)")
	await _new_scene()

	# NOT testing raw hand-to-target distance: that's fundamentally bounded
	# by shoulder-to-target distance minus arm length regardless of the IK
	# gate, so it stays similar with or without the fix and is not useful
	# evidence either way (confirmed directly - an earlier "before/after"
	# comparison by that metric alone looked identical, which was itself
	# what exposed this and led to reading the gate values directly instead).
	# What actually distinguishes correct behaviour: effective IK influence
	# must stay LOW while the target is still far beyond arm's reach (an
	# early bug pinned toward the ledge regardless of distance, measurably
	# making the right hand's distance-to-target WORSE, up to 1.09m, than no
	# IK at all - a fully outstretched arm reaching for an unreachable point)
	# and rise toward full strength only once genuinely close.
	_body.global_position = Vector3(0.0, 0.0, 2.6)
	_body.velocity = Vector3.ZERO
	_facing.rotation.y = PI
	await physics_frame
	_scene.call("_try_start_mantle", true)
	var ik_mod = _scene.get("_mantle_hand_ik_modifier")
	var duration: float = _scene.get("_mantle_duration")

	var early_weight := -1.0
	var late_weight := -1.0
	var saw_full_reach := false
	while _scene.get("_is_mantling"):
		await physics_frame
		var elapsed: float = _scene.get("_mantle_elapsed")
		var w: float = ik_mod.weight
		if elapsed < duration * 0.1 and early_weight < 0.0:
			early_weight = w
		if elapsed > duration * 0.8:
			late_weight = maxf(late_weight, w)
		if w > 0.5:
			saw_full_reach = true

	_check("IK weight stays low right after triggering, far from the ledge",
			early_weight < 0.1, "weight=%.3f" % early_weight)
	_check("IK weight rises to meaningful strength once genuinely close",
			saw_full_reach, "saw weight > 0.5 at some point: %s" % saw_full_reach)
	_check("IK weight has faded back out by the very end (hands release)",
			late_weight < 0.3, "max weight in final 20%%=%.3f" % late_weight)

	await _teardown_scene()


func _mantles(x: float, z: float, grounded: bool) -> bool:
	_scene.set("_is_mantling", false)
	_body.global_position = Vector3(x, 0.0, z)
	_body.velocity = Vector3.ZERO
	_facing.rotation.y = PI
	await physics_frame
	return _scene.call("_try_start_mantle", grounded)


# Runs a mantle to completion. Returns [final_position, target_position,
# position_at_30%_elapsed].
func _run_full_mantle(x: float, z: float, grounded: bool) -> Array:
	_scene.set("_is_mantling", false)
	_body.global_position = Vector3(x, 0.0, z)
	_body.velocity = Vector3.ZERO
	_facing.rotation.y = PI
	await physics_frame
	_scene.call("_try_start_mantle", grounded)
	var target: Vector3 = _scene.get("_mantle_target_pos")
	var duration: float = _scene.get("_mantle_duration")
	var mid_pos := Vector3.ZERO
	var got_mid := false
	while _scene.get("_is_mantling"):
		await physics_frame
		var elapsed: float = _scene.get("_mantle_elapsed")
		if not got_mid and elapsed >= duration * 0.3:
			mid_pos = _body.global_position
			got_mid = true
	return [_body.global_position, target, mid_pos]


# ----------------------------------------------------------- spine twist --

func _test_spine_twist() -> void:
	_section("spine twist (currently disabled - see doc comment)")
	await _new_scene()

	var mod: SkeletonModifier3D = _scene.get("_spine_twist_modifier")
	_check("modifier is attached to the skeleton", mod.get_skeleton() == _skel,
			"skeleton=%s" % mod.get_skeleton())
	_check("modifier runs after the foot IK modifier",
			mod.get_index() > (_scene.get("_foot_ik_modifier") as Node).get_index(),
			"foot_ik=%d spine=%d"
					% [(_scene.get("_foot_ik_modifier") as Node).get_index(), mod.get_index()])

	_scene.set("_rotation_mode", 1)
	_body.global_position = Vector3(0.0, 0.0, 8.0)
	_facing.rotation.y = 0.0
	_scene.set("_rotation_target_yaw", 0.0)
	(_scene.get("_camera_pivot") as Node3D).rotation.y = 0.0
	await _settle(30)

	# The math itself stays verified (0.25/0.50/0.75 cumulative weights, real
	# sign) even though it's not currently driven from anywhere - see the
	# SPRINT_CLIP_ENABLED-style doc comment on why: Enable_SpineRotation is a
	# real ALS animation curve our retargeted clips don't carry, so real ALS
	# would apply none here either.
	var d_spine := _twist_delta(mod, &"Spine", 60.0)
	var d_spine1 := _twist_delta(mod, &"Spine1", 60.0)
	var d_spine2 := _twist_delta(mod, &"Spine2", 60.0)
	_check("Spine twists TOWARD camera (sign)", d_spine > 0.0, "%.2f deg" % d_spine)
	_check("Spine  = 25% of aim angle", absf(d_spine - 15.0) < 0.5,
			"%.2f deg (expect 15.0)" % d_spine)
	_check("Spine1 = 50% of aim angle", absf(d_spine1 - 30.0) < 0.5,
			"%.2f deg (expect 30.0)" % d_spine1)
	_check("Spine2 = 75% of aim angle", absf(d_spine2 - 45.0) < 0.5,
			"%.2f deg (expect 45.0)" % d_spine2)
	var d_neg := _twist_delta(mod, &"Spine2", -60.0)
	_check("negative aim delta mirrors", absf(d_neg + 45.0) < 0.5,
			"%.2f deg (expect -45.0)" % d_neg)

	# The actual runtime wiring: disabled in BOTH rotation modes.
	_scene.set("_rotation_mode", 0)
	(_scene.get("_camera_pivot") as Node3D).rotation.y = deg_to_rad(60.0)
	await _settle(5)
	_check("Velocity Direction leaves twist disabled",
			is_zero_approx(mod.get("twist_yaw")), "twist_yaw=%.4f" % mod.get("twist_yaw"))
	_scene.set("_rotation_mode", 1)
	await _settle(5)
	_check("Looking Direction leaves twist disabled too",
			is_zero_approx(mod.get("twist_yaw")), "twist_yaw=%.4f" % mod.get("twist_yaw"))

	await _teardown_scene()


# World-space yaw (deg) of a fixed vector carried by the bone. Only the
# CHANGE is meaningful - the absolute value depends on the bone's rest
# convention (and would be affected by the visual node's 180 deg offset).
func _bone_world_yaw(role: StringName) -> float:
	var idx := _skel.find_bone(_facing.call("resolve_bone_name", role))
	var world := _skel.global_transform * _skel.get_bone_global_pose(idx)
	var v: Vector3 = world.basis * Vector3.RIGHT
	return rad_to_deg(atan2(v.x, v.z))


func _twist_delta(mod: SkeletonModifier3D, role: StringName, twist_deg: float) -> float:
	mod.set("twist_yaw", 0.0)
	mod.call("_process_modification_with_delta", 1.0 / 60.0)
	var before := _bone_world_yaw(role)
	mod.set("twist_yaw", deg_to_rad(twist_deg))
	mod.call("_process_modification_with_delta", 1.0 / 60.0)
	var after := _bone_world_yaw(role)
	return rad_to_deg(wrapf(deg_to_rad(after - before), -PI, PI))


# --------------------------------------------------------------- camera --

func _test_camera() -> void:
	_section("camera (ALSPlayerCameraManager::CustomCameraBehavior)")
	await _new_scene()
	var cam: Camera3D = _scene.get("_camera")
	var pivot: Node3D = _scene.get("_camera_pivot")

	_check("camera is NOT parented to the body",
			not _body.is_ancestor_of(cam), "parent=%s" % cam.get_parent().name)
	_check("FOV is ALS's ThirdPersonFOV 90", absf(cam.fov - 90.0) < 0.01, "%.1f" % cam.fov)

	pivot.rotation.y = 0.0
	_scene.set("_rotation_mode", 0)  # VELOCITY_DIRECTION
	await _settle(60)

	var target: Vector3 = _scene.call("_third_person_pivot_target")
	_check("pivot target is mid-body (Head/root midpoint)",
			target.y > 0.5 and target.y < 1.2, "y=%.3f" % target.y)
	var to_cam := cam.global_position - target
	_check("camera sits ~3.25m behind the pivot (VD offset)",
			absf(to_cam.z - 3.25) < 0.25, "dz=%.3f" % to_cam.z)
	_check("no sideways offset in Velocity Direction", absf(to_cam.x) < 0.15,
			"dx=%.3f" % to_cam.x)

	_scene.set("_rotation_mode", 1)  # LOOKING_DIRECTION
	await _settle(60)
	var target_ld: Vector3 = _scene.call("_third_person_pivot_target")
	var to_cam_ld := cam.global_position - target_ld
	_check("Looking Direction pulls in to ~2.8m", absf(to_cam_ld.z - 2.80) < 0.3,
			"dz=%.3f" % to_cam_ld.z)
	_check("Looking Direction offsets over the shoulder (+0.7m right)", to_cam_ld.x > 0.4,
			"dx=%.3f" % to_cam_ld.x)
	_scene.set("_rotation_mode", 0)
	await _settle(60)

	pivot.rotation.y = deg_to_rad(90.0)
	await physics_frame
	var after_one: float = _scene.get("_camera_lag_yaw")
	_check("camera yaw LAGS one frame behind control yaw",
			absf(rad_to_deg(after_one)) < 89.0, "%.2f deg after 1 frame" % rad_to_deg(after_one))
	await _settle(60)
	var settled: float = _scene.get("_camera_lag_yaw")
	_check("...and converges to it", absf(rad_to_deg(settled) - 90.0) < 1.0,
			"%.2f deg" % rad_to_deg(settled))
	pivot.rotation.y = 0.0
	await _settle(60)

	var wall := _add_static_box(Vector3(8.0, 4.0, 0.5), Vector3(0.0, 2.0, 9.5))
	await _settle(30)
	var target_walled: Vector3 = _scene.call("_third_person_pivot_target")
	var dist_walled := (cam.global_position - target_walled).length()
	_check("wall behind the camera pulls it in", dist_walled < 2.0,
			"dist=%.3f (unobstructed was ~3.3)" % dist_walled)
	wall.queue_free()
	await _settle(60)
	var target_clear: Vector3 = _scene.call("_third_person_pivot_target")
	var dist_clear := (cam.global_position - target_clear).length()
	_check("...and it returns once the wall is gone", dist_clear > 3.0,
			"dist=%.3f" % dist_clear)

	await _teardown_scene()


# -------------------------------------------------------- crouch + jump --

func _test_crouch_and_jump_play_rate() -> void:
	_section("crouch + jump play rate")
	await _new_scene()

	# OnJumped's JumpPlayRate: {0,600}cm/s -> {1.2,1.5}.
	_body.velocity = Vector3.ZERO
	_scene.call("_apply_jump_play_rate")
	var standing_rate: float = _tree.get("parameters/Airborne/JumpTimeScale/scale")
	_body.velocity = Vector3(0.0, 0.0, -6.0)  # 6 m/s = ALS's 600cm/s cap
	_scene.call("_apply_jump_play_rate")
	var running_rate: float = _tree.get("parameters/Airborne/JumpTimeScale/scale")
	_body.velocity = Vector3(0.0, 0.0, -3.0)  # midpoint
	_scene.call("_apply_jump_play_rate")
	var mid_rate: float = _tree.get("parameters/Airborne/JumpTimeScale/scale")
	_check("standing jump play rate = 1.2", absf(standing_rate - 1.2) < 0.001,
			"%.4f" % standing_rate)
	_check("full-speed jump play rate = 1.5", absf(running_rate - 1.5) < 0.001,
			"%.4f" % running_rate)
	_check("half-speed jump play rate = 1.35", absf(mid_rate - 1.35) < 0.001,
			"%.4f" % mid_rate)

	# Crouch: capsule, camera pivot follow, stand-up room gating.
	var shape: CollisionShape3D = _scene.get("_collision_shape")
	var stand_h: float = (shape.shape as CapsuleShape3D).height
	_body.velocity = Vector3.ZERO
	_body.global_position = Vector3(0.0, 0.0, 8.0)
	await _settle(30)
	var head_standing := _head_above_body()

	_scene.call("_set_crouching", true)
	_check("crouch shrinks capsule to ALS 1.2m",
			absf((shape.shape as CapsuleShape3D).height - 1.2) < 0.001,
			"%.3f (was %.3f)" % [(shape.shape as CapsuleShape3D).height, stand_h])
	_check("capsule stays bottom-anchored at the feet",
			absf(shape.position.y - 0.6) < 0.001, "shape.y=%.3f" % shape.position.y)
	_check("crouched flag set", _scene.get("_is_crouching"), "true")

	# 40 frames, not fewer: the stance blend needs time to reach 1.0 AND the
	# AnimationTree needs to actually publish the pose to the skeleton. A
	# too-short settle here previously reported byte-identical numbers across
	# changes that provably altered the pose - i.e. it was reading a stale
	# skeleton, not a real result.
	await _settle(40)
	var head_crouched := _head_above_body()
	_check("head lowers when crouched, so the camera pivot follows (no separate rule needed)",
			head_crouched < head_standing - 0.05,
			"%.3f -> %.3f m above the feet" % [head_standing, head_crouched])
	var blend: float = _tree.get("parameters/Grounded/StanceBlend/blend_amount")
	_check("stance blend eases toward crouched", blend > 0.9, "blend=%.3f" % blend)

	_scene.call("_set_crouching", false)
	_check("stands back up with headroom",
			not _scene.get("_is_crouching")
					and absf((shape.shape as CapsuleShape3D).height - stand_h) < 0.001,
			"height=%.3f" % (shape.shape as CapsuleShape3D).height)

	# Load-bearing case: a ceiling that clears the crouched capsule (1.2m)
	# but blocks the standing one (1.8m) must BLOCK standing up.
	var ceiling := _add_static_box(Vector3(4.0, 0.2, 4.0), Vector3(0.0, 1.4, 8.0))
	await _settle(20)
	_scene.call("_set_crouching", true)
	await _settle(20)
	_scene.call("_set_crouching", false)
	_check("low ceiling BLOCKS standing up", _scene.get("_is_crouching"),
			"still crouched=%s" % _scene.get("_is_crouching"))
	_check("...and capsule stayed crouched",
			absf((shape.shape as CapsuleShape3D).height - 1.2) < 0.001,
			"%.3f" % (shape.shape as CapsuleShape3D).height)
	ceiling.queue_free()
	await _settle(20)
	_scene.call("_set_crouching", false)
	_check("...and stands once the ceiling is gone", not _scene.get("_is_crouching"),
			"crouched=%s" % _scene.get("_is_crouching"))

	await _teardown_scene()


# -------------------------------------------------------- gait / sprint --

func _test_gait_and_sprint() -> void:
	_section("gait speeds + sprint blending")
	await _new_scene()

	var run_speed: float = _scene.get("RUN_SPEED")
	var sprint_speed: float = _scene.get("SPRINT_SPEED")
	var walk_speed: float = _scene.get("WALK_SPEED")

	# Regression for the sprint-animation break: sprint velocity (6.5) sits
	# far outside the blendspace's outermost run ring (3.75) under ALS's real
	# gait speeds, so an unclamped blend position falls off the triangulated
	# hull and stops resolving to the run clips. Sprint must clamp ONTO the
	# ring and raise the play rate instead.
	await _drive(sprint_speed)
	var bp: Vector2 = _tree.get("parameters/Grounded/StandBlend/blend_position")
	_check("sprint blend position stays on the run ring", bp.length() <= run_speed + 0.01,
			"|bp|=%.3f (run ring %.2f, sprint %.2f)" % [bp.length(), run_speed, sprint_speed])
	_check("sprint blend position is not collapsed to idle", bp.length() > run_speed - 0.5,
			"|bp|=%.3f" % bp.length())

	# Compared against the body's ACTUAL horizontal speed, not the nominal
	# target: _physics_process decelerates toward zero-input every frame
	# after velocity is written, so the nominal value is always one frame
	# stale.
	await _drive(run_speed)
	var bp_run: Vector2 = _tree.get("parameters/Grounded/StandBlend/blend_position")
	var actual_run := Vector3(_body.velocity.x, 0.0, _body.velocity.z).length()
	_check("run is NOT clamped - sits at its real speed",
			absf(bp_run.length() - actual_run) < 0.05 and bp_run.length() < run_speed + 0.01,
			"|bp|=%.3f actual=%.3f" % [bp_run.length(), actual_run])

	await _drive(walk_speed)
	var bp_walk: Vector2 = _tree.get("parameters/Grounded/StandBlend/blend_position")
	var actual_walk := Vector3(_body.velocity.x, 0.0, _body.velocity.z).length()
	_check("walk is NOT clamped - sits at its real speed",
			absf(bp_walk.length() - actual_walk) < 0.05 and bp_walk.length() < walk_speed + 0.01,
			"|bp|=%.3f actual=%.3f" % [bp_walk.length(), actual_walk])

	await _drive(sprint_speed)
	var rate_sprint: float = _tree.get("parameters/Grounded/GroundTimeScale/scale")
	_check("play rate scales with speed while sprinting",
			rate_sprint > 1.0 and rate_sprint <= 3.0, "%.3f" % rate_sprint)

	# The dedicated sprint clip is gated by SPRINT_CLIP_ENABLED (its retarget
	# once crossed the arms until a wrong bone-map argument was fixed - see
	# the status log). Assert the layer matches the flag, so a silent flip
	# either way gets caught.
	Input.action_press(&"sprint")
	await _drive(sprint_speed, 10)
	var sprint_layer: float = _tree.get("parameters/Grounded/SprintBlend/blend_amount")
	var expect_on: bool = _scene.get("SPRINT_CLIP_ENABLED")
	_check("sprint clip layer matches SPRINT_CLIP_ENABLED", (sprint_layer > 0.5) == expect_on,
			"SprintBlend=%.3f enabled=%s" % [sprint_layer, expect_on])
	Input.action_release(&"sprint")
	await _drive(0.0)

	_body.velocity = Vector3.ZERO
	await _settle(20)
	var rate_idle: float = _tree.get("parameters/Grounded/GroundTimeScale/scale")
	_check("idle play rate never falls to 0 (would freeze the pose)", rate_idle > 0.01,
			"%.3f" % rate_idle)

	await _teardown_scene()


# ------------------------------------------------- airborne blend easing --

func _test_airborne_blend_eases() -> void:
	_section("airborne jump/fall blend eases (not a hard step)")
	await _new_scene()

	var blend_range: float = _scene.get("AIR_BLEND_VELOCITY_RANGE")
	var jump_v: float = _scene.get("JUMP_VELOCITY")
	_check("blend range is smaller than a real jump's peak speed", blend_range < jump_v,
			"range=%.2f jump_velocity=%.2f" % [blend_range, jump_v])

	# The old signf(velocity.y) bug produced ONLY -1, 0, or 1 - three
	# discrete values no matter how many distinct velocities were sampled.
	# A real ease must produce more distinct values than that.
	var samples: Array[float] = []
	for v: float in [jump_v, jump_v * 0.5, 0.5, 0.0, -0.5, -jump_v * 0.5, -jump_v]:
		_body.velocity.y = v
		_scene.call("_physics_process", 1.0 / 60.0)
		samples.append(_tree.get("parameters/Airborne/AirBlend/blend_position"))
	var distinct: Dictionary = {}
	for s in samples:
		distinct[snappedf(s, 0.01)] = true
	_check("blend position takes more than 3 discrete values (a real ease)",
			distinct.size() > 3, "%d distinct values across %d velocities"
					% [distinct.size(), samples.size()])

	var v_mid := 0.5
	_body.velocity.y = v_mid
	_scene.call("_physics_process", 1.0 / 60.0)
	var bp_mid: float = _tree.get("parameters/Airborne/AirBlend/blend_position")
	_check("mid-range velocity maps to itself, not a step", absf(bp_mid - v_mid) < 0.01,
			"velocity=%.2f -> blend=%.3f" % [v_mid, bp_mid])

	_body.velocity.y = jump_v
	_scene.call("_physics_process", 1.0 / 60.0)
	var bp_full: float = _tree.get("parameters/Airborne/AirBlend/blend_position")
	_check("full jump speed clamps to the range endpoint", absf(bp_full - range_) < 0.01,
			"blend=%.3f (range=%.2f)" % [bp_full, range_])

	await _teardown_scene()


# ----------------------------------- jump physics / air lean / land pred --

func _test_jump_physics_lean_and_land_prediction() -> void:
	_section("jump physics + air lean + land prediction")
	await _new_scene()

	_check("JUMP_VELOCITY is ALS real 4.2 m/s (420cm/s)",
			is_equal_approx(_scene.get("JUMP_VELOCITY"), 4.2), "%.2f" % _scene.get("JUMP_VELOCITY"))
	_check("GRAVITY is real 9.8 m/s2", is_equal_approx(_scene.get("GRAVITY"), 9.8),
			"%.2f" % _scene.get("GRAVITY"))

	# Both curves were read live off the real ALS assets (run_python's
	# inspect_asset) and must be baked EXACTLY, not approximated - Godot's
	# Curve resource silently clamps both its X domain and Y value range to
	# [0,1] by default, which zeroed every interior lean-curve point until
	# both were explicitly widened.
	var lean_curve: Curve = _scene.get("_lean_in_air_curve")
	_check("lean curve: 0 at -40 (cutoff)", absf(lean_curve.sample(-40.0)) < 0.01,
			"%.4f" % lean_curve.sample(-40.0))
	_check("lean curve: ~-0.932 at -22.52 (authored dip, NOT clamped to 0)",
			absf(lean_curve.sample(-22.51931) - (-0.932240)) < 0.01,
			"%.4f" % lean_curve.sample(-22.51931))
	_check("lean curve: 1.0 at 0 (launch/apex)", absf(lean_curve.sample(0.0) - 1.0) < 0.01,
			"%.4f" % lean_curve.sample(0.0))

	var land_curve: Curve = _scene.get("_land_prediction_curve")
	_check("land curve: 1.0 at fraction 0", absf(land_curve.sample(0.0) - 1.0) < 0.01,
			"%.4f" % land_curve.sample(0.0))
	_check("land curve: 0.0 at fraction 1", absf(land_curve.sample(1.0)) < 0.01,
			"%.4f" % land_curve.sample(1.0))

	# Lean actually tilts the character while airborne and moving sideways...
	_body.global_position = Vector3(0.0, 5.0, 8.0)
	_facing.rotation.x = 0.0
	_facing.rotation.z = 0.0
	_body.velocity = Vector3(3.0, -3.0, 0.0)
	await _settle(30)
	_check("airborne lateral movement produces a non-zero roll",
			not is_zero_approx(_facing.rotation.z), "rotation.z=%.4f rad" % _facing.rotation.z)

	# ...and decays back to upright once grounded.
	_body.global_position = Vector3(0.0, 0.0, 8.0)
	_body.velocity = Vector3.ZERO
	await _settle(60)
	_check("lean decays back to upright once grounded",
			absf(_facing.rotation.z) < 0.01 and absf(_facing.rotation.x) < 0.01,
			"rotation=(%.4f, %.4f)" % [_facing.rotation.x, _facing.rotation.z])

	# Land prediction: 0 above the real -2.0 m/s cutoff...
	_body.velocity.y = -1.0
	_scene.call("_update_air_lean_and_land_prediction", 1.0 / 60.0)
	_check("land prediction is 0 above the fall-speed cutoff",
			is_zero_approx(_scene.get("_land_prediction")), "%.4f" % _scene.get("_land_prediction"))

	# ...and non-zero falling fast with ground close below. is_on_floor()
	# only updates from a real move_and_slide() call - reading state in the
	# same frame as a teleport (no intervening physics frame) previously
	# read a stale "grounded" flag and silently short-circuited to 0.
	_body.global_position = Vector3(0.0, 1.0, 8.0)
	_body.velocity = Vector3(0.0, -8.0, 0.0)
	await _settle(3)
	_check("land prediction is non-zero when falling fast near the ground",
			_scene.get("_land_prediction") > 0.1, "%.4f" % _scene.get("_land_prediction"))

	await _teardown_scene()


# ------------------------------------------------------------- run all --

func _run_all() -> void:
	var sections: Array[Callable] = [
		_test_rotation_and_turn_in_place,
		_test_mantle,
		_test_mantle_hand_ik,
		_test_spine_twist,
		_test_camera,
		_test_crouch_and_jump_play_rate,
		_test_gait_and_sprint,
		_test_airborne_blend_eases,
		_test_jump_physics_lean_and_land_prediction,
	]
	for section: Callable in sections:
		_fails = 0
		await section.call()
		if _fails > 0:
			print("  ^ %d failure(s) in this section" % _fails)
		_total_fails += _fails

	print("")
	print("=========================================")
	print("TOTAL RESULT: %s (%d failure(s) across %d sections)"
			% ["PASS" if _total_fails == 0 else "FAIL", _total_fails, sections.size()])
	quit(1 if _total_fails > 0 else 0)
