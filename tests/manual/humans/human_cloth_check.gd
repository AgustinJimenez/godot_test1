extends Node
## Rendered lifecycle regression for the body lab's simulated garments.

var _lab: Node3D
var _failed: bool = false


func _ready() -> void:
	_lab = (load("res://tests/manual/humans/human_body_lab.tscn") as PackedScene).instantiate()
	# The forest preview has separate GPU caches; exercise cloth in the studio.
	_lab.set("_background", "Studio")
	add_child(_lab)
	await _settle()
	_check_running("initial male")
	_check_settings("initial male")
	_lab.set("_cloth_sim", false)
	_lab.call("_restart_cloth")
	await _settle()
	_expect(_lab.get("_cloth_rig") == null, "simulation off releases rig")
	for static_piece: MeshInstance3D in _lab.get("_garment_meshes"):
		_expect(static_piece.visible, "static garments restored")
	_lab.set("_cloth_sim", true)
	_lab.call("_restart_cloth")
	await _settle()
	_check_running("simulation re-enabled")
	# This used to leave the simulated shirt and trousers visible over underwear.
	var clothes_list: Array = _lab.get("_clothes_list")
	_expect(clothes_list.has("villager") and clothes_list.back() == "Underwear", "the outfits from the folder, then Underwear: %s" % [clothes_list])
	_lab.call("_on_clothes_selected", clothes_list.find("Underwear"))
	await _settle()
	_expect(_lab.get("_cloth_rig") == null, "underwear releases rig")
	_expect((_lab.get("_cloth_solvers") as Array).is_empty(), "underwear releases solvers")
	_expect((_lab.get("_underwear_mesh") as MeshInstance3D).visible, "underwear visible")
	_lab.call("_on_clothes_selected", clothes_list.find("villager"))
	await _settle()
	_check_running("villager restored")
	# every outfit in the folder loads and runs (one static mesh and one solver per garment)
	for outfit_name: String in ClothSetup.outfit_names():
		_lab.call("_on_clothes_selected", clothes_list.find(outfit_name))
		await _settle()
		_check_running("outfit " + outfit_name)
	_lab.call("_on_clothes_selected", clothes_list.find("villager"))
	await _settle()
	# an outfit listed before its garments are built: a warning and the underwear, not a script error
	var unbuilt := ClothSetup.OUTFITS_DIR + "zz_unbuilt_check.json"
	var file := FileAccess.open(unbuilt, FileAccess.WRITE)
	file.store_string('{"name": "zz_unbuilt_check", "garments": ["shirt"]}')
	file.close()
	_lab.set("_clothes_list", [])
	_lab.set("_clothes", "zz_unbuilt_check")
	_lab.call("_load_clothes")
	await _settle()
	_expect(_lab.get("_clothes") == "Underwear", "an unbuilt outfit falls back to the underwear (got %s)" % _lab.get("_clothes"))
	_expect((_lab.get("_underwear_mesh") as MeshInstance3D).visible, "an unbuilt outfit shows the underwear")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(unbuilt))
	_lab.set("_clothes_list", [])
	_lab.set("_clothes", "villager")
	_lab.call("_load_clothes")
	await _settle()
	for gender: String in ["Female", "Male"]:
		_lab.call("_on_gender_button", gender)
		await _settle()
		_check_running(gender)
		for height: float in [-1.0, 1.0]:
			_lab.set("_height", height)
			_lab.call("_apply")
			await _settle()
			_check_running("%s height %+.1f" % [gender, height])
			await _check_layers("%s height %+.1f" % [gender, height])
		_lab.set("_height", 0.0)
		for shape: String in ["_weight", "_muscle"]:
			for amount: float in [-1.0, 1.0]:
				_lab.set(shape, amount)
				_lab.call("_apply")
				await _settle()
				_check_running("%s %s %+.1f" % [gender, shape, amount])
				await _check_layers("%s %s %+.1f" % [gender, shape, amount])
			_lab.set(shape, 0.0)
	_lab.queue_free()
	await _settle()
	if not _failed:
		print("HUMAN_CLOTH_CHECK PASS: toggle, outfits, gender, body extremes, teardown")
	get_tree().quit(1 if _failed else 0)


func _settle() -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw


# At rest no garment's points are inside the garment under it (the overlap probe, on the render thread).
func _check_layers(label: String) -> void:
	await get_tree().create_timer(1.0).timeout
	RenderingServer.call_on_render_thread(ClothOverlapProbe.count_inside.bind(_lab.get("_cloth_solvers")))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_expect(ClothOverlapProbe.last_inside == 0, label + ": %d points inside the layer under them; deepest: %s" % [ClothOverlapProbe.last_inside, ClothOverlapProbe.last_worst])


func _check_running(label: String) -> void:
	var solvers: Array = _lab.get("_cloth_solvers")
	var garments: Array = _lab.get("_garment_meshes")
	var recipes: Array = (_lab.get("_outfit") as Dictionary).get("garments", [])
	var simulated: Array = []
	for i in recipes.size():
		if ClothSetup.is_simulated(recipes[i]):
			simulated.append(i)
	_expect(garments.size() >= 1 and solvers.size() == simulated.size(), label + ": one solver per simulated garment (%d solvers, %d simulated)" % [solvers.size(), simulated.size()])
	for solver: GPUClothSolver in solvers:
		_expect(solver._gpu_init_done, label + ": GPU initialized")
		if (solver.get_meta(&"garment", {}) as Dictionary).get("covers", []).has("forearm"):
			_expect(not solver._native_collider_data.is_empty(), label + ": native arm contact")
		var material: ShaderMaterial = solver._surf_mat
		_expect(bool(material.get_shader_parameter(&"gpu_driven")), label + ": GPU material drawn")
	for piece: MeshInstance3D in _lab.get("_cloth_pieces"):
		_expect(piece.visible, label + ": simulated garment visible")
	for i in garments.size():
		var static_piece: MeshInstance3D = garments[i]
		if simulated.has(i):
			_expect(not static_piece.visible, label + ": static hidden")
		else:
			_expect(static_piece.visible, label + ": a garment not simulated (footwear) stays drawn")
	print("HUMAN_CLOTH_CHECK state ", label)


# The solver settings come from each garment (ClothSetup): exact arm contact where it covers the forearms, full shin capsules where it covers the
# shins, the lopsided pelvis and upper-spine capsules shrunk, flipped normals, and every garment a peer of every other.
func _check_settings(label: String) -> void:
	var solvers: Array = _lab.get("_cloth_solvers")
	for solver: GPUClothSolver in solvers:
		_expect(solver.has_meta(&"garment"), label + ": %s knows its garment" % solver.name)
		if not solver.has_meta(&"garment"):
			continue
		var garment: Dictionary = solver.get_meta(&"garment")
		var covers: Array = garment.get("covers", [])
		_expect(solver.flip_normals, label + ": %s flipped normals" % solver.name)
		_expect(solver.auto_collider_bone_overrides.get("mixamorig_Hips") == Vector2(0.0, 0.1), label + ": %s pelvis capsule shrunk" % solver.name)
		_expect(solver.auto_collider_bone_overrides.get("mixamorig_Spine2") == Vector2(0.0, 0.1), label + ": %s upper spine capsule shrunk" % solver.name)
		_expect(solver.peer_cloth_solvers.size() == solvers.size() - 1, label + ": %s peers with every other garment" % solver.name)
		if covers.has("forearm"):
			_expect(not solver._native_collider_data.is_empty(), label + ": %s exact arm contact" % solver.name)
			_expect(is_equal_approx(solver.cloth_render_offset, 0.001), label + ": %s render offset 1 mm" % solver.name)
		else:
			_expect(is_equal_approx(solver.cloth_render_offset, 0.004), label + ": %s render offset 4 mm" % solver.name)
		if covers.has("shin"):
			_expect(solver.auto_collider_bone_overrides.get("mixamorig_LeftLeg") == Vector2(0.85, 1.0), label + ": %s full shin capsules" % solver.name)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		print("HUMAN_CLOTH_CHECK FAIL: ", message)
