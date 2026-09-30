extends Node3D
## Live debug view: a leg joint (hip, knee, ankle) whose FINAL pose turns in one frame by more than
## the animation itself does (its largest per-frame turn over the last WINDOW frames, the walk
## cycle, times MARGIN) flashes a red sphere that fades out. Turns are in skeleton space, so the
## body moving or turning never counts. Reads the modifier's poses. Headless: prints instead.

const WINDOW := 120
const MARGIN := 1.5
const FLOOR_DEG := 4.0
const WARMUP_FRAMES := 30
const TELEPORT_METERS := 0.5
const BODY_TURN_DEG := 6.0 # spine / shoulder / arm: no animated reference, an absolute limit
const FLASH_SECONDS := 1.0
const SPHERE_RADIUS := 0.05
const ROLES := [&"hip", &"knee", &"foot"]

var flash_count := 0
var _last_origin := Vector3.ZERO
var _modifier: FootIKV2Modifier
var _skeleton: Skeleton3D
var _animated_previous := {}
var _final_previous := {}
var _animated_turns := {}
var _flashes: Array = []


func setup(modifier: FootIKV2Modifier, skeleton: Skeleton3D) -> Node3D:
	_modifier = modifier
	_skeleton = skeleton
	top_level = true
	return self


func _process(delta: float) -> void:
	if _modifier == null or not _modifier.enabled:
		return
	if _skeleton.global_position.distance_to(_last_origin) > TELEPORT_METERS:
		_animated_previous.clear() # a teleport (the checks move the body) is not a joint snap
		_animated_turns.clear()
	_last_origin = _skeleton.global_position
	for side: StringName in _modifier._base:
		for role: StringName in ROLES:
			_check(side, role)
	for role: StringName in FootIKV2Modifier.BODY_ROLES.slice(1):
		_check_body(role)
	for flash: Dictionary in _flashes.duplicate():
		flash["age"] = float(flash["age"]) + delta
		var sphere := flash["node"] as MeshInstance3D
		var fade := 1.0 - float(flash["age"]) / FLASH_SECONDS
		if fade <= 0.0:
			sphere.queue_free()
			_flashes.erase(flash)
		else:
			(sphere.material_override as StandardMaterial3D).albedo_color.a = fade


func _check(side: StringName, role: StringName) -> void:
	var bone := int((_modifier._legs[side] as Dictionary)[role])
	if not _modifier.final_pose.has(bone):
		return
	var key := [side, role]
	var animated := ((_modifier._base[side] as Dictionary)[role] as Transform3D).basis
	var final_world := _modifier.final_pose[bone] as Transform3D
	var final := _modifier.final_basis.inverse() * final_world.basis
	if _animated_previous.has(key):
		var anim_turn := _turn(_animated_previous[key], animated)
		var final_turn := _turn(_final_previous[key], final)
		var turns: Array = _animated_turns.get(key, [])
		turns.append(anim_turn)
		if turns.size() > WINDOW:
			turns.pop_front()
		_animated_turns[key] = turns
		var reference := maxf(FLOOR_DEG, (turns.max() as float) * MARGIN)
		if final_turn > reference and turns.size() > WARMUP_FRAMES:
			flash_count += 1
			if DisplayServer.get_name() == "headless":
				print("[JointFlash] f%d %s %s turned %.1f deg (animation max %.1f, this frame %.1f)"
						% [Engine.get_process_frames(), side, role, final_turn, reference / MARGIN, anim_turn])
			else:
				_spawn(final_world.origin)
	_animated_previous[key] = animated
	_final_previous[key] = final


func _turn(from: Basis, to: Basis) -> float:
	return rad_to_deg(from.get_rotation_quaternion().angle_to(to.get_rotation_quaternion()))


func _spawn(position_world: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = SPHERE_RADIUS
	mesh.height = SPHERE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.1, 0.1, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	var sphere := MeshInstance3D.new()
	sphere.mesh = mesh
	sphere.material_override = material
	sphere.top_level = true
	add_child(sphere)
	sphere.global_position = position_world
	_flashes.append({"node": sphere, "age": 0.0})


## Spine, shoulders, upper arms: turned against their parent bone by more than BODY_TURN_DEG.
func _check_body(role: StringName) -> void:
	var bone := _skeleton.find_bone(_modifier.player_body.resolve_bone_name(role))
	var parent := _skeleton.get_bone_parent(bone)
	if bone < 0 or not _modifier.final_pose.has(bone) or not _modifier.final_pose.has(parent):
		return
	var pose := _modifier.final_pose[bone] as Transform3D
	var local := ((_modifier.final_pose[parent] as Transform3D).affine_inverse() * pose).basis
	var key := ["body", role]
	if _animated_previous.has(key):
		var turned := _turn(_animated_previous[key], local)
		if turned > BODY_TURN_DEG:
			flash_count += 1
			if DisplayServer.get_name() == "headless":
				print("[JointFlash] f%d body %s turned %.1f deg" % [Engine.get_process_frames(), role, turned])
			else:
				_spawn(pose.origin)
	_animated_previous[key] = local
