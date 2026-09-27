class_name ProceduralStepPlanDebug3D
extends Node3D
## Renders the gait modifier's persistent alternating footstep queue. The gait owns and consumes
## the plan; this object is deliberately only a view so calculations and markers cannot disagree.
const MARKERS := 6 # Three future placements for each foot.
const SIDE_COLORS: Array[Color] = [Color(0.62, 0.2, 1.0), Color(0.2, 0.45, 1.0)] # left, right
## A flat foot print instead of a sphere: laid on the tread, long axis along the walk direction.
const FOOT_SIZE := Vector2(0.10, 0.18)
const MARK_LIFT := 0.006
var _marks: Array[MeshInstance3D] = []
var _shown := true
var _previous_targets: Array[Vector3] = []
var _previous_sides: Array[int] = []
var _stable := true
var _queue_shifts := 0
var _plan: RefCounted
var _ground_height := Callable()


func _ready() -> void:
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
		add_child(mark)
		_marks.append(mark)
	set_shown(_shown)


func bind(plan: RefCounted, ground_height: Callable) -> void:
	_plan = plan
	_ground_height = ground_height


func _process(_delta: float) -> void:
	_update_markers()


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


func _update_markers() -> void:
	if _marks.is_empty() or _plan == null or not _shown:
		return
	var count: int = int(_plan.size())
	_validate_queue(count)
	for i in MARKERS:
		var available: bool = i < count
		_marks[i].visible = available
		if not available:
			continue
		var side: int = int(_plan.side(i))
		var target: Vector3 = _plan.target(i)
		if _ground_height.is_valid():
			target.y = float(_ground_height.call(target)) + MARK_LIFT
		_marks[i].global_position = target
		var material := _marks[i].material_override as StandardMaterial3D
		material.albedo_color = SIDE_COLORS[side]


func _validate_queue(count: int) -> void:
	if count != MARKERS:
		_previous_targets.clear()
		_previous_sides.clear()
		return
	var targets: Array[Vector3] = []
	var sides: Array[int] = []
	for i in count:
		targets.append(_plan.target(i))
		sides.append(_plan.side(i))
	if _previous_targets.size() == MARKERS and targets != _previous_targets:
		var shifted := true
		for i in MARKERS - 1:
			shifted = shifted and targets[i].is_equal_approx(_previous_targets[i + 1]) \
					and sides[i] == _previous_sides[i + 1]
		_stable = _stable and shifted
		_queue_shifts += 1 if shifted else 0
	_previous_targets = targets
	_previous_sides = sides
