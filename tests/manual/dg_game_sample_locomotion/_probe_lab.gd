extends SceneTree
## Runs the lab scene for a moment and prints what the body actually does, to check the HUD.

const LAB := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_lab.tscn"
)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab: Node3D = LAB.instantiate()
	get_root().add_child(lab)
	for i in 120:
		await physics_frame
		if i % 20 == 0:
			print("frame %d  pos %s  speed %.2f  state %s" % [
				i, lab.body.global_position, lab.body.get_planar_speed(),
				lab.body.get_state_name()
			])
	print("hud pos %s size %s text '%s'" % [
		lab.hud.position, lab.hud.size, lab.hud.text.split("\n")[3]
	])
	quit()
