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
	_lab.set("_cloth_sim", false)
	_lab.call("_restart_cloth")
	await _settle()
	_expect(_lab.get("_cloth_rig") == null, "simulation off releases rig")
	_expect((_lab.get("_shirt_mesh") as MeshInstance3D).visible, "static shirt restored")
	_lab.set("_cloth_sim", true)
	_lab.call("_restart_cloth")
	await _settle()
	_check_running("simulation re-enabled")
	# This used to leave the simulated shirt and trousers visible over underwear.
	_lab.call("_on_clothes_selected", 1)
	await _settle()
	_expect(_lab.get("_cloth_rig") == null, "underwear releases rig")
	_expect((_lab.get("_cloth_solvers") as Array).is_empty(), "underwear releases solvers")
	_expect((_lab.get("_underwear_mesh") as MeshInstance3D).visible, "underwear visible")
	_lab.call("_on_clothes_selected", 0)
	await _settle()
	_check_running("villager restored")
	for gender: String in ["Female", "Male"]:
		_lab.call("_on_gender_button", gender)
		await _settle()
		_check_running(gender)
		for height: float in [-1.0, 1.0]:
			_lab.set("_height", height)
			_lab.call("_apply")
			await _settle()
			_check_running("%s height %+.1f" % [gender, height])
		_lab.set("_height", 0.0)
		for shape: String in ["_weight", "_muscle"]:
			for amount: float in [-1.0, 1.0]:
				_lab.set(shape, amount)
				_lab.call("_apply")
				await _settle()
				_check_running("%s %s %+.1f" % [gender, shape, amount])
			_lab.set(shape, 0.0)
	_lab.queue_free()
	await _settle()
	if not _failed:
		print("HUMAN_CLOTH_CHECK PASS: toggle, outfits, gender, body extremes, teardown")
	get_tree().quit(1 if _failed else 0)


func _settle() -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw


func _check_running(label: String) -> void:
	var solvers: Array = _lab.get("_cloth_solvers")
	_expect(solvers.size() == 2, label + ": two solvers")
	for solver: GPUClothSolver in solvers:
		_expect(solver._gpu_init_done, label + ": GPU initialized")
		if solver.name == &"ShirtCloth":
			_expect(not solver._native_collider_data.is_empty(), label + ": native arm contact")
		var material: ShaderMaterial = solver._surf_mat
		_expect(bool(material.get_shader_parameter(&"gpu_driven")), label + ": GPU material drawn")
	for piece: MeshInstance3D in _lab.get("_cloth_pieces"):
		_expect(piece.visible, label + ": simulated garment visible")
	_expect(not (_lab.get("_shirt_mesh") as MeshInstance3D).visible, label + ": static hidden")
	print("HUMAN_CLOTH_CHECK state ", label)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		print("HUMAN_CLOTH_CHECK FAIL: ", message)
