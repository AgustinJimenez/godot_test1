class_name ProceduralWalkInfiniteCheck
extends RefCounted
## Flat moving modes must continue beyond the old eight-cycle stop.


func run(lab: Node3D, character: Node3D, reference: Node3D,
		floor_stage: Node3D) -> bool:
	await lab.get_tree().physics_frame
	var panels := lab.find_children("*", "PanelContainer", true, false)
	if panels.is_empty():
		push_error("Procedural walk lab has no control panel")
		return false
	var panel := panels[0] as PanelContainer
	var camera := lab.get("_camera") as Camera3D
	var bank := lab.get("_reference_bank") as ProceduralWalkReferenceBank
	var all_passed := true
	var walk_mps := 0.0
	for mode_index in [0, 1, 2, 3, 4]: # Original and all four flat references.
		lab.call("_select_reference_mode", mode_index)
		if mode_index == 0:
			lab.call("_set_moving_mode", true)
		var stayed_moving := bool(lab.get("_moving_mode"))
		var cycles_per_second := float(lab.get("_speed"))
		var mode: StringName = (&"" if mode_index == 0
				else ProceduralWalkReferenceBank.MODE_ORDER[mode_index - 1])
		var stride: float = (2.0 * float((lab.get("_modifier") as ProceduralWalkLabModifier).stride)
				/ (1.0 - ProceduralWalkLabModifier.SWING_FRACTION) if mode_index == 0
				else float(bank.flat_travel_per_cycle[mode]))
		var meters_per_second := stride * cycles_per_second
		if mode_index == 1:
			walk_mps = meters_per_second
		lab.set("_speed", 5.0) # Exercise >8 cycles without a long wall-clock test.
		await lab.get_tree().physics_frame
		await lab.get_tree().physics_frame
		var smallest_panel := panel.size
		var largest_panel := panel.size
		for frame in 180:
			await lab.get_tree().physics_frame
			smallest_panel = smallest_panel.min(panel.size)
			largest_panel = largest_panel.max(panel.size)
		var distance := -character.global_position.z
		var floor_gap := absf(character.global_position.z - floor_stage.position.z)
		var follows := absf(reference.global_position.z - character.global_position.z) < 0.001
		var camera_offset := camera.global_position - character.global_position
		var side_view := camera_offset.x > 3.0 and absf(camera_offset.z) < 0.1
		var cycle_distance_error := absf(distance / float(lab.get("_travel_cycles")) - stride)
		var passed: bool = (bool(lab.get("_playing")) and stayed_moving and distance > 8.0
				and floor_gap <= 0.5 and follows and floor_stage.get_child_count() == 2
				and largest_panel.distance_to(smallest_panel) < 0.1 and side_view
				and cycle_distance_error < 0.01
				and (mode_index != 3 or meters_per_second > walk_mps * 2.0))
		all_passed = all_passed and passed
		print(("INFINITE_WALK %s %s cycles=%.1f distance=%.2fm "
				+ "floor_gap=%.2fm reference_follows=%s panel_delta=%.1fpx "
				+ "panel_min=%s panel_max=%s side_view=%s stride=%.2fm speed=%.2fmps") % [
				"original" if mode_index == 0 else String(mode),
				"PASS" if passed else "FAIL", float(lab.get("_travel_cycles")),
				distance, floor_gap, str(follows),
				largest_panel.distance_to(smallest_panel),
				str(smallest_panel), str(largest_panel), str(side_view),
				stride, meters_per_second])
	return all_passed
