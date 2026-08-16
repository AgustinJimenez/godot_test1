class_name FootIKStairSurfaces
extends RefCounted
## Builds split stair collision for the manual Foot IK harness.
## Capsules use one seamless proxy; foot probes use the authored treads.

const TRAVERSAL_COLLISION_LAYER := PlayerStairController.CONTINUOUS_TRAVERSAL_LAYER
const CONTACT_COLLISION_LAYER := 1 << 5
const LANDING_LENGTH := 1.0
const TRANSITION_LENGTH := 0.1
const TRANSITION_SEGMENTS := 6
const SLOPE_TRANSITION_LENGTH := 0.4
const SLOPE_TRANSITION_SEGMENTS := 12


static func configure_player(player: Player) -> void:
	player.collision_mask |= TRAVERSAL_COLLISION_LAYER
	player.collision_mask &= ~CONTACT_COLLISION_LAYER
	# The 45-degree reference is intentionally the steepest preview case.
	# Leave numerical headroom so its proxy facets remain walkable floors
	# instead of intermittently becoming walls/free-fall at the exact limit.
	player.floor_max_angle = maxf(player.floor_max_angle, deg_to_rad(50.0))


static func configure_authored_stair(stair: CSGBox3D) -> void:
	stair.collision_layer = CONTACT_COLLISION_LAYER


static func build_traversal_slope(parent: Node3D, origin: Vector3,
		width: float, length: float, rise: float) -> void:
	var transition := SLOPE_TRANSITION_LENGTH * 2.0
	var transition_rise := rise / length * SLOPE_TRANSITION_LENGTH
	var profile := PackedVector2Array([
		Vector2(-SLOPE_TRANSITION_LENGTH - LANDING_LENGTH, 0.0),
	])
	for index in SLOPE_TRANSITION_SEGMENTS + 1:
		var ratio := float(index) / SLOPE_TRANSITION_SEGMENTS
		profile.append(Vector2(
				-SLOPE_TRANSITION_LENGTH + transition * ratio,
				transition_rise * ratio * ratio))
	profile.append(Vector2(
			length - SLOPE_TRANSITION_LENGTH, rise - transition_rise))
	for index in SLOPE_TRANSITION_SEGMENTS + 1:
		var ratio := float(index) / SLOPE_TRANSITION_SEGMENTS
		profile.append(Vector2(
				length - SLOPE_TRANSITION_LENGTH + transition * ratio,
				rise - transition_rise * (1.0 - ratio) * (1.0 - ratio)))
	profile.append(Vector2(length + SLOPE_TRANSITION_LENGTH + LANDING_LENGTH, rise))
	_build_profile_surface(parent, origin, width, profile)


static func build_traversal_ramp(parent: Node3D, origin: Vector3,
		width: float, _thickness: float, tread_depth: float,
		step_count: int, step_height: float) -> void:
	var ramp_start_z := -tread_depth
	var ramp_end_z := (step_count - 1) * tread_depth
	var rise := step_count * step_height
	var transition_span := TRANSITION_LENGTH * 2.0
	var transition_rise := rise / (ramp_end_z - ramp_start_z) * TRANSITION_LENGTH
	var profile := PackedVector2Array([
		Vector2(ramp_start_z - TRANSITION_LENGTH - LANDING_LENGTH, 0.0),
	])
	for index in TRANSITION_SEGMENTS + 1:
		var ratio := float(index) / TRANSITION_SEGMENTS
		profile.append(Vector2(
				ramp_start_z - TRANSITION_LENGTH + transition_span * ratio,
				transition_rise * ratio * ratio))
	profile.append(Vector2(ramp_end_z - TRANSITION_LENGTH, rise - transition_rise))
	for index in TRANSITION_SEGMENTS + 1:
		var ratio := float(index) / TRANSITION_SEGMENTS
		profile.append(Vector2(
				ramp_end_z - TRANSITION_LENGTH + transition_span * ratio,
				rise - transition_rise * (1.0 - ratio) * (1.0 - ratio)))
	profile.append(Vector2(ramp_end_z + TRANSITION_LENGTH + LANDING_LENGTH, rise))
	_build_profile_surface(parent, origin, width, profile)


static func build_top_landing(parent: Node3D, origin: Vector3,
		width: float, tread_depth: float, step_count: int, step_height: float,
		riser_material: Material = null, tread_material: Material = null) -> void:
	# The traversal ramp's flat top landing extends past the last authored
	# tread, but foot probes only raycast the contact layer. Without a
	# contact-layer landing there, a foot over the top-back edge misses all
	# geometry and the 4m idle fallback ray reads the floor 2.1m below,
	# producing the documented top-edge dangle. Author the landing on the
	# contact layer to match the capsule's walkable surface.
	var top_rise := step_height * step_count
	var ramp_end_z := (step_count - 1) * tread_depth
	var landing_end_z := ramp_end_z + TRANSITION_LENGTH + LANDING_LENGTH
	var landing_start_z := step_count * tread_depth
	var box := CSGBox3D.new()
	box.size = Vector3(width, top_rise, landing_end_z - landing_start_z)
	box.material = riser_material
	box.use_collision = true
	configure_authored_stair(box)
	box.position = origin + Vector3(
			0.0, top_rise * 0.5, (landing_start_z + landing_end_z) * 0.5)
	parent.add_child(box)
	var cap := CSGBox3D.new()
	cap.size = Vector3(width, 0.006, landing_end_z - landing_start_z)
	cap.material = tread_material
	cap.use_collision = false
	cap.position = origin + Vector3(
			0.0, top_rise + 0.003, (landing_start_z + landing_end_z) * 0.5)
	parent.add_child(cap)


static func _build_profile_surface(parent: Node3D, origin: Vector3,
		width: float, profile: PackedVector2Array) -> void:
	var faces := PackedVector3Array()
	var half_width := width * 0.5
	for index in profile.size() - 1:
		var start := profile[index]
		var finish := profile[index + 1]
		var near_left := Vector3(-half_width, start.y, start.x)
		var far_left := Vector3(-half_width, finish.y, finish.x)
		var far_right := Vector3(half_width, finish.y, finish.x)
		var near_right := Vector3(half_width, start.y, start.x)
		faces.append_array(PackedVector3Array([
			near_left, far_left, far_right,
			near_left, far_right, near_right,
		]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	# The repeated harness turns around on the top landing. Jolt's concave
	# triangles are one-sided by default, which let the capsule fall through
	# while descending even though ascent was supported by the same surface.
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var surface := StaticBody3D.new()
	surface.name = "StairTraversalSurface"
	surface.collision_layer = TRAVERSAL_COLLISION_LAYER
	surface.collision_mask = 0
	surface.position = origin
	surface.add_child(collision)
	parent.add_child(surface)
