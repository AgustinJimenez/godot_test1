extends SceneTree
## Clip-level smoothness regression for the procedural walk reference animations. Samples each
## mode's own uniform-phase poses (procedural_walk_reference_bank.frames) and reports the worst
## per-frame joint rotation between adjacent samples, plus the loop-seam step. This isolates the
## authored/retargeted animation from the terrain and the leg solver: a snap measured here is the
## clip itself, so a bad source (e.g. a retargeted Mixamo stair clip) is caught directly instead of
## surfacing later as a visible pop on stairs. Mirrors `trace_query.py angular`'s flat-walk baseline
## (about 18 deg/frame) as the reference for what reads smooth.
##
## Run: godot --headless --path . --script \
##      res://tests/manual/procedural_walk/procedural_walk_clip_smoothness_check.gd

const MODEL := preload(
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Relaxed_Idle_IPC.fbx")
const REFERENCE_BANK := preload(
		"res://tests/manual/procedural_walk/procedural_walk_reference_bank.gd")
const REFERENCE_FPS := 60.0
## A joint rotating more than this between two adjacent rendered frames reads as a snap.
const MAX_DEG_PER_FRAME := 30.0


func _initialize() -> void:
	var model_root := MODEL.instantiate() as Node3D
	model_root.visible = false
	root.add_child(model_root)
	var skel := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		print("CLIP_SMOOTHNESS_CHECK FAIL reason=no-skeleton")
		quit(1)
		return
	var bank := REFERENCE_BANK.new() as ProceduralWalkReferenceBank
	if not bank.build(model_root, skel):
		print("CLIP_SMOOTHNESS_CHECK FAIL reason=reference-bank-build")
		quit(1)
		return
	var failed := false
	for mode: StringName in REFERENCE_BANK.MODE_ORDER:
		var poses: Array = bank.frames.get(mode, [])
		var clip: Animation = bank.clip(mode)
		if poses.is_empty() or clip == null:
			print("CLIP_SMOOTHNESS %s SKIP (no samples)" % mode)
			continue
		# One phase sample is clip.length / SAMPLE_COUNT seconds; convert a rotation step to a
		# per-rendered-frame rate so the number is comparable across clips of different length.
		var frames_per_step := maxf(clip.length, 0.0001) / float(
				REFERENCE_BANK.SAMPLE_COUNT) * REFERENCE_FPS
		var worst := 0.0
		var worst_joint := &""
		var worst_sample := -1
		var seam := 0.0
		var seam_joint := &""
		for sample in poses.size():
			var following: int = (sample + 1) % poses.size()
			var current: Array = poses[sample]
			var next_poses: Array = poses[following]
			for bone in mini(current.size(), next_poses.size()):
				var first := (current[bone] as Transform3D).basis.get_rotation_quaternion()
				var second := (next_poses[bone] as Transform3D).basis.get_rotation_quaternion()
				# Shortest-path angle: q and -q are the same rotation, so take |dot| or a
				# double-cover sign flip would read as a bogus ~180-360 deg "snap".
				var step := rad_to_deg(2.0 * acos(clampf(absf(first.dot(second)), -1.0, 1.0)))
				var per_frame := step / frames_per_step
				if per_frame > worst:
					worst = per_frame
					worst_joint = skel.get_bone_name(bone)
					worst_sample = sample
				if following == 0 and step > seam:
					seam = step
					seam_joint = skel.get_bone_name(bone)
		var status := "FAIL" if worst > MAX_DEG_PER_FRAME else "PASS"
		failed = failed or worst > MAX_DEG_PER_FRAME
		print(("CLIP_SMOOTHNESS %s %s worst=%.1fdeg/frame joint=%s sample=%d "
				+ "seam=%.1fdeg/frame seam_joint=%s len=%.3f limit=%.1f") % [
				mode, status, worst, worst_joint, worst_sample,
				seam / frames_per_step, seam_joint, clip.length, MAX_DEG_PER_FRAME])
	print("CLIP_SMOOTHNESS_CHECK ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
