extends RefCounted
## Renders the gait modifier's persistent alternating footstep queue. The gait owns and consumes
## the plan; this object is deliberately only a view so calculations and markers cannot disagree.
const MARKERS := 6 # Three future placements for each foot.
const SIDE_COLORS: Array[Color] = [Color(0.62, 0.2, 1.0), Color(0.2, 0.45, 1.0)] # left, right
## A flat foot print instead of a sphere: laid on the tread, long axis along the walk direction.
const FOOT_SIZE := Vector2(0.10, 0.26)
const MARK_LIFT := 0.006
var _marks: Array[MeshInstance3D] = []
var _shown := true
var _previous_targets: Array[Vector3] = []
var _previous_sides: Array[int] = []
var _stable := true
var _queue_shifts := 0


func build(parent: Node3D) -> void:
	for i in MARKERS:
		var mark := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = FOOT_SIZE
		mesh.orientation = PlaneMesh.FACE_Y
		mark.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color.a = 0.85
		mark.material_override = material
		parent.add_child(mark)
		_marks.append(mark)


func set_shown(shown: bool) -> void:
	_shown = shown
	for mark in _marks:
		mark.visible = shown


func reset_validation() -> void:
	_previous_targets.clear()
	_previous_sides.clear()
	_stable = true
	_queue_shifts = 0


func plan_is_stable() -> bool:
	return _stable and _queue_shifts > 0


func update(_anchor: Vector3, modifier) -> void:
	if _marks.is_empty() or modifier == null or not _shown:
		return
	var count := int(modifier.planned_step_count())
	_validate_queue(modifier, count)
	for i in MARKERS:
		var available: bool = i < count
		_marks[i].visible = available
		if not available:
			continue
		var side: int = int(modifier.planned_step_side(i))
		var target: Vector3 = modifier.planned_step_target(i)
		target.y = float(modifier.ground_height(target)) + MARK_LIFT
		_marks[i].global_position = target
		var material := _marks[i].material_override as StandardMaterial3D
		material.albedo_color = SIDE_COLORS[side]


func _validate_queue(modifier, count: int) -> void:
	if count != MARKERS:
		_previous_targets.clear()
		_previous_sides.clear()
		return
	var targets: Array[Vector3] = []
	var sides: Array[int] = []
	for i in count:
		targets.append(modifier.planned_step_target(i))
		sides.append(int(modifier.planned_step_side(i)))
	if _previous_targets.size() == MARKERS and targets != _previous_targets:
		var shifted := true
		for i in MARKERS - 1:
			shifted = shifted and targets[i].is_equal_approx(_previous_targets[i + 1]) \
					and sides[i] == _previous_sides[i + 1]
		_stable = _stable and shifted
		_queue_shifts += 1 if shifted else 0
	_previous_targets = targets
	_previous_sides = sides
