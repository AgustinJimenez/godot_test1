class_name ProceduralWalkReferenceBank
extends RefCounted
## Lab-only, phase-sampled whole-body poses from this repository's animation assets.
## The procedural character uses these as a style reference, then independently
## solves its feet. The optional comparison character plays the source clip.

const MODEL := preload(
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Relaxed_Idle_IPC.fbx")
const MESH_CLEARANCE := preload(
		"res://tests/manual/procedural_walk/procedural_walk_mesh_clearance.gd")
const NATIVE_DIR := "res://assets/models/pistol_starter/Animation/In-Place/"
const UAL := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const STAIRS := "res://assets/models/stair_clips/"
const SAMPLE_COUNT := 120
const MODE_ORDER := [
	&"walk", &"walk_aim", &"sprint", &"crouch", &"stair_up", &"stair_down",
]
const MODE_LABELS := {
	&"walk": "Walk (UAL)",
	&"walk_aim": "Walk (MotusMan aim)",
	&"sprint": "Sprint (UAL)",
	&"crouch": "Crouch walk (UAL)",
	&"stair_up": "Stair up (Mixamo)",
	&"stair_down": "Stair down (Mixamo)",
}

var clips: Dictionary = {} # mode -> Animation on the MotusMan rig
var frames: Dictionary = {} # mode -> Array[Array[Transform3D]] at uniform phase
var foot_frames: Dictionary = {} # mode -> Array[Array[Quaternion]] global shoe rotations
var mesh_min_frames: Dictionary = {} # mode -> Array[Array[float]] lowest foot-mesh vertex
var clearance_frames: Dictionary = {} # mode -> floor-safe, rate-limited Hips lift
var flat_travel_per_cycle: Dictionary = {} # mode -> distance inferred from planted feet
var bone_count := 0


func build(parent: Node3D, target_skeleton: Skeleton3D) -> bool:
	clips[&"walk_aim"] = _native_clip("W1_Walk_Aim_F_Loop_IPC")
	# The retargeter can temporarily pose its target while matching arms. Never
	# pass the live procedural skeleton here: doing so changed its frozen idle
	# base and invalidated the otherwise independent in-place walk check.
	var target_root := MODEL.instantiate() as Node3D
	target_root.visible = false
	parent.add_child(target_root)
	var retarget_target := target_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var ual_root := (load(UAL) as PackedScene).instantiate()
	var ual_skel := ual_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var ual_player := ual_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var role_map: Dictionary = {}
	for bone in retarget_target.get_bone_count():
		var name := retarget_target.get_bone_name(bone)
		role_map[String(name)] = String(name)
	var config := HumanoidRetargeter.build_bone_map_config(PlayerBody.BONE_MAP, role_map)
	for pair: Array in [[&"walk", &"Walk"], [&"sprint", &"Sprint"],
			[&"crouch", &"Crouch_Fwd"]]:
		var source := ual_player.get_animation(pair[1])
		clips[pair[0]] = HumanoidRetargeter.retarget_clip(
				ual_skel, source, retarget_target, config, true)
	ual_root.free()
	target_root.queue_free()
	clips[&"stair_up"] = (load(STAIRS + "stair_walk_up.res") as Animation).duplicate()
	clips[&"stair_down"] = (load(STAIRS + "stair_walk_down.res") as Animation).duplicate()
	for mode: StringName in MODE_ORDER:
		if clips.get(mode) == null:
			push_error("Procedural walk lab: missing reference clip %s" % mode)
			return false
		(clips[mode] as Animation).loop_mode = Animation.LOOP_LINEAR
	return _sample_clips(parent, target_skeleton.get_bone_count())


func _native_clip(name: String) -> Animation:
	var root := (load(NATIVE_DIR + name + ".fbx") as PackedScene).instantiate()
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := player.get_animation(name).duplicate() as Animation
	root.free()
	return clip


func _sample_clips(parent: Node3D, expected_bones: int) -> bool:
	var root := MODEL.instantiate() as Node3D
	root.name = &"ReferenceSampler"
	root.visible = false
	parent.add_child(root)
	var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skel == null or player == null or skel.get_bone_count() != expected_bones:
		push_error("Procedural walk lab: reference sampler skeleton mismatch")
		root.queue_free()
		return false
	bone_count = expected_bones
	player.stop()
	player.root_node = player.get_path_to(skel.get_parent())
	var library := AnimationLibrary.new()
	var mesh_check := MESH_CLEARANCE.new() as ProceduralWalkMeshClearance
	mesh_check.prepare(root, skel)
	for mode: StringName in MODE_ORDER:
		library.add_animation(mode, clips[mode])
	player.add_animation_library(&"references", library)
	for mode: StringName in MODE_ORDER:
		var clip: Animation = clips[mode]
		var poses: Array = []
		var feet: Array = []
		var mesh_mins: Array = []
		var ankle_z: Array = []
		var left_foot := skel.find_bone(&"LeftFoot")
		var right_foot := skel.find_bone(&"RightFoot")
		player.play("references/" + String(mode))
		for sample in SAMPLE_COUNT:
			player.seek(clip.length * float(sample) / float(SAMPLE_COUNT), true)
			player.advance(0.0)
			var bones: Array[Transform3D] = []
			for bone in bone_count:
				bones.append(skel.get_bone_pose(bone))
			poses.append(bones)
			feet.append([
				skel.get_bone_global_pose(left_foot).basis.get_rotation_quaternion(),
				skel.get_bone_global_pose(right_foot).basis.get_rotation_quaternion(),
			])
			ankle_z.append([
				skel.get_bone_global_pose(left_foot).origin.z,
				skel.get_bone_global_pose(right_foot).origin.z,
			])
			var globals: Array[Transform3D] = []
			for bone in bone_count:
				globals.append(skel.get_bone_global_pose(bone))
			mesh_mins.append(mesh_check.sample(skel, globals))
		# The imported stair-down clip has a roughly 40-degree one-frame shoe
		# rotation at mid-cycle. Smooth the global shoe orientation, not just
		# its local bone rotation: the leg parent chain also contributes to it.
		if mode == &"stair_down":
			_smooth_foot_rotations(feet)
			_smooth_stair_leg_rotations(poses, skel)
		frames[mode] = poses
		foot_frames[mode] = feet
		mesh_min_frames[mode] = mesh_mins
		var clearance := _clearance_envelope(mesh_mins)
		clearance_frames[mode] = clearance
		if mode not in [&"stair_up", &"stair_down"]:
			flat_travel_per_cycle[mode] = _flat_stance_travel(ankle_z, mesh_mins, clearance)
	root.queue_free()
	return true


func _flat_stance_travel(ankle_z: Array, mesh_mins: Array,
		clearance: Array[float]) -> float:
	# Forward motion corresponds to a negative local-Z displacement of a
	# planted foot. Estimate root speed from that displacement per contact
	# sample, including the airborne part of a running cycle.
	var contact_travel := 0.0
	var contact_samples := 0
	for side in 2:
		for sample in SAMPLE_COUNT:
			var next := (sample + 1) % SAMPLE_COUNT
			var touching: bool = (float(mesh_mins[sample][side]) + clearance[sample] < 0.04
					and float(mesh_mins[next][side]) + clearance[next] < 0.04)
			if touching:
				var step: float = float(ankle_z[sample][side]) - float(ankle_z[next][side])
				if step > 0.0:
					contact_travel += step
					contact_samples += 1
	if contact_samples == 0:
		push_error("Procedural walk lab: no planted backward foot travel in flat clip")
		return 0.0
	return contact_travel / float(contact_samples) * float(SAMPLE_COUNT)


func _clearance_envelope(mesh_mins: Array) -> Array[float]:
	# Smallest cyclic upper envelope that both clears the shoe and changes
	# by no more than 0.8 cm between adjacent phase samples. Sprint can cross
	# multiple samples per physics frame, so the sample-rate bound is tighter.
	# A single sharp
	# source-foot dip must not make the entire body jump in one frame.
	const MAX_STEP := 0.008
	var output: Array[float] = []
	for sample in SAMPLE_COUNT:
		var lift := 0.0
		for other in SAMPLE_COUNT:
			var distance := absi(sample - other)
			var cyclic_distance := mini(distance, SAMPLE_COUNT - distance)
			var foot_min: Array[float] = mesh_mins[other]
			var needed := 0.006 - minf(foot_min[0], foot_min[1])
			lift = maxf(lift, needed - MAX_STEP * float(cyclic_distance))
		output.append(maxf(0.0, lift))
	return output


func _smooth_foot_rotations(feet: Array) -> void:
	const RADIUS := 4
	for side in 2:
		var smoothed: Array[Quaternion] = []
		for sample in SAMPLE_COUNT:
			var total := 0.0
			var rotation := Quaternion.IDENTITY
			for offset in range(-RADIUS, RADIUS + 1):
				var neighbor := posmod(sample + offset, SAMPLE_COUNT)
				var weight := float(RADIUS + 1 - absi(offset))
				var source: Array = feet[neighbor]
				var next: Quaternion = source[side]
				rotation = (rotation.slerp(next, weight / (total + weight))
						if total > 0.0 else next)
				total += weight
			smoothed.append(rotation)
		for sample in SAMPLE_COUNT:
			var rotations: Array = feet[sample]
			rotations[side] = smoothed[sample]


func _smooth_stair_leg_rotations(poses: Array, skel: Skeleton3D) -> void:
	const RADIUS := 4
	for name: StringName in [&"LeftUpLeg", &"LeftLeg", &"RightUpLeg", &"RightLeg"]:
		var bone := skel.find_bone(name)
		if bone < 0:
			continue
		var smoothed: Array[Quaternion] = []
		for sample in SAMPLE_COUNT:
			var total := 0.0
			var rotation := Quaternion.IDENTITY
			for offset in range(-RADIUS, RADIUS + 1):
				var neighbor := posmod(sample + offset, SAMPLE_COUNT)
				var weight := float(RADIUS + 1 - absi(offset))
				var source: Array[Transform3D] = poses[neighbor]
				var next := source[bone].basis.get_rotation_quaternion()
				rotation = (rotation.slerp(next, weight / (total + weight))
						if total > 0.0 else next)
				total += weight
			smoothed.append(rotation)
		for sample in SAMPLE_COUNT:
			var bones: Array[Transform3D] = poses[sample]
			var pose := bones[bone]
			pose.basis = Basis(smoothed[sample]).scaled(pose.basis.get_scale())
			bones[bone] = pose


func sample_pose(mode: StringName, phase: float) -> Array[Transform3D]:
	var output: Array[Transform3D] = []
	var poses: Array = frames.get(mode, [])
	if poses.is_empty():
		return output
	var sample_position := fposmod(phase / TAU, 1.0) * float(SAMPLE_COUNT)
	var before := int(floorf(sample_position)) % SAMPLE_COUNT
	var after := (before + 1) % SAMPLE_COUNT
	var weight := sample_position - floorf(sample_position)
	var first: Array[Transform3D] = poses[before]
	var second: Array[Transform3D] = poses[after]
	for bone in bone_count:
		output.append(first[bone].interpolate_with(second[bone], weight))
	return output


func foot_basis(mode: StringName, phase: float, side: int) -> Basis:
	var rotations: Array = foot_frames.get(mode, [])
	if rotations.is_empty():
		return Basis.IDENTITY
	var sample_position := fposmod(phase / TAU, 1.0) * float(SAMPLE_COUNT)
	var before := int(floorf(sample_position)) % SAMPLE_COUNT
	var after := (before + 1) % SAMPLE_COUNT
	var weight := sample_position - floorf(sample_position)
	var first: Quaternion = rotations[before][side]
	var second: Quaternion = rotations[after][side]
	return Basis(first.slerp(second, weight))


func foot_mesh_min_y(mode: StringName, phase: float, side: int) -> float:
	var minimums: Array = mesh_min_frames.get(mode, [])
	if minimums.is_empty():
		return 0.0
	var sample_position := fposmod(phase / TAU, 1.0) * float(SAMPLE_COUNT)
	var before := int(floorf(sample_position)) % SAMPLE_COUNT
	var after := (before + 1) % SAMPLE_COUNT
	var weight := sample_position - floorf(sample_position)
	return lerpf(minimums[before][side], minimums[after][side], weight)


func floor_clearance(mode: StringName, phase: float) -> float:
	var lifts: Array = clearance_frames.get(mode, [])
	if lifts.is_empty():
		return 0.0
	var sample_position := fposmod(phase / TAU, 1.0) * float(SAMPLE_COUNT)
	var before := int(floorf(sample_position)) % SAMPLE_COUNT
	var after := (before + 1) % SAMPLE_COUNT
	return lerpf(lifts[before], lifts[after], sample_position - floorf(sample_position))


func clip(mode: StringName) -> Animation:
	return clips.get(mode) as Animation
