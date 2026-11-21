extends SceneTree
## Headless check of the native HairSway (the spring that swings the hair when its character moves or turns):
##   godot --headless --fixed-fps 60 --path . -s res://tests/manual/humans/human_sway_check.gd
## (--fixed-fps makes a rendered frame and a physics frame the same length, as the spring assumes.) Prints HUMAN_SWAY_CHECK PASS or FAIL lines, exit code nonzero on failure.
## What it asserts: an acceleration swings the hair against it; a turn that STARTS kicks it, a steady turn does not hold it on the stop (the offset settles); it comes back to rest;
## the offset never passes max_swing and a huge kick does not leave the hair stuck at the limit; the swing reaches the mesh instance's own `sway` uniform.

var _failures: int = 0


func _init() -> void:
	if not ClassDB.class_exists(&"HairSway"):
		_fail("HairSway is not registered (is the native library built?)")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var target := Node3D.new()
	var hair := MeshInstance3D.new()
	var sway := HairSway.new()
	get_root().add_child(target)
	get_root().add_child(hair)
	get_root().add_child(sway)
	sway.hair = hair
	sway.target = target
	await physics_frame
	await physics_frame
	# 1. the character speeds up along the hair's +Z (forward): the hair lags behind it, toward -Z
	var speed: float = 0.0
	var peak: Vector3 = Vector3.ZERO
	for frame: int in 40:
		speed += 0.25
		target.position += Vector3(0.0, 0.0, speed / 60.0)
		await physics_frame
		if sway.get_offset().length() > peak.length():
			peak = sway.get_offset()
	_expect(peak.length() > 0.001, "speeding up swung the hair only %.4f m" % peak.length())
	_expect(peak.z < 0.0, "speeding up forward swung the hair to %+.4f in z, it should lag (negative)" % peak.z)
	_expect(sway.get_offset().length() <= sway.max_swing + 1e-6, "the offset %.4f passed max_swing" % sway.get_offset().length())
	# 2. at rest again: the swing dies down
	for frame: int in 200:
		await physics_frame
	_expect(sway.get_offset().length() < 0.002, "the hair did not come back to rest (%.4f m)" % sway.get_offset().length())
	# 3. a turn starts: a kick; the turn goes on at a steady rate: the hair settles (it used to be pushed all the time and pinned at max_swing above 1.4 rad/s)
	var kick_peak: float = 0.0
	var yaw: float = 0.0
	for frame: int in 20:
		yaw += 3.0 / 60.0
		target.rotation.y = yaw
		await physics_frame
		kick_peak = maxf(kick_peak, sway.get_offset().length())
	_expect(kick_peak > 0.004, "the start of a turn kicked the hair only %.4f m" % kick_peak)
	var steady_worst: float = 0.0
	for frame: int in 120:
		yaw += 3.0 / 60.0
		target.rotation.y = yaw
		await physics_frame
		if frame > 60:
			steady_worst = maxf(steady_worst, sway.get_offset().length())
	_expect(steady_worst < sway.max_swing * 0.25, "a steady turn holds the hair at %.4f m (more than a quarter of max_swing)" % steady_worst)
	for frame: int in 240:
		await physics_frame
	_expect(sway.get_offset().length() < 0.002, "the hair did not come back to rest after the turn (%.4f m)" % sway.get_offset().length())
	# 4. a huge kick: the offset stops at max_swing and the hair is not stuck there afterwards
	sway.kick(Vector3(50.0, 0.0, 0.0))
	await physics_frame
	await physics_frame
	_expect(sway.get_offset().length() <= sway.max_swing + 1e-6, "a kick pushed the offset to %.4f, past max_swing" % sway.get_offset().length())
	for frame: int in 120:
		await physics_frame
	_expect(sway.get_offset().length() < 0.01, "after a huge kick the hair is still at %.4f m (stuck on the stop)" % sway.get_offset().length())
	# 5. the offset reaches the mesh instance's own uniform
	sway.kick(Vector3(0.0, 0.0, 2.0))
	await physics_frame
	await physics_frame
	var written: Variant = hair.get_instance_shader_parameter(&"sway")
	_expect(written is Vector3 and (written as Vector3).distance_to(sway.get_offset()) < 0.0001, "the `sway` instance uniform is %s, the offset %s" % [str(written), str(sway.get_offset())])
	print("HUMAN_SWAY_CHECK PASS" if _failures == 0 else "HUMAN_SWAY_CHECK FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	print("HUMAN_SWAY_CHECK failed: ", message)
