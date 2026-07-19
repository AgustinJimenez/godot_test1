class_name WorldHealthBar
extends Node3D

## Camera-facing NPC health bar, visible only at close range during an
## attack or briefly after this actor takes damage.

const BAR_WIDTH := 0.9
const BAR_HEIGHT := 0.09

@export var max_visible_distance: float = 7.0
@export var damaged_reveal_time: float = 3.0

var _damaged_time_left := 0.0
var _actor: Node3D
var _health: Health
var _npc_controller: NPCController
var _fill_mesh: QuadMesh
var _fill: MeshInstance3D


func _ready() -> void:
	_actor = get_parent() as Node3D
	_health = get_parent().get_node_or_null(^"Health") as Health
	_npc_controller = get_parent().get_node_or_null(^"NPCController") as NPCController
	if _health == null or _npc_controller == null:
		push_error("WorldHealthBar requires Health and NPCController siblings")
		set_process(false)
		return
	_build_meshes()
	_health.changed.connect(_on_health_changed)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_refresh_current_health.call_deferred()
	visible = false


func _process(delta: float) -> void:
	_damaged_time_left = maxf(_damaged_time_left - delta, 0.0)
	if _health.is_dead():
		visible = false
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		visible = false
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		look_at(camera.global_position, Vector3.UP)
	var close := _actor.global_position.distance_to(
			player.global_position) <= max_visible_distance
	var attacking := (_npc_controller.is_hostile()
			and _npc_controller.behavior == NPCController.Behavior.ATTACK)
	visible = close and (attacking or _damaged_time_left > 0.0)


func _build_meshes() -> void:
	var background_material := _make_material(Color(0.035, 0.04, 0.045, 0.94))
	var background_mesh := QuadMesh.new()
	background_mesh.size = Vector2(BAR_WIDTH + 0.06, BAR_HEIGHT + 0.05)
	background_mesh.material = background_material
	var background := MeshInstance3D.new()
	background.mesh = background_mesh
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(background)

	var fill_material := _make_material(Color(1.0, 0.055, 0.035, 1.0))
	_fill_mesh = QuadMesh.new()
	_fill_mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_fill_mesh.material = fill_material
	_fill = MeshInstance3D.new()
	_fill.position.z = 0.006
	_fill.mesh = _fill_mesh
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _on_health_changed(current: float, max_value: float) -> void:
	_refresh_fill(current, max_value)


func _refresh_current_health() -> void:
	_refresh_fill(_health.current, _health.max_health)


func _on_damaged(_amount: float) -> void:
	_damaged_time_left = damaged_reveal_time


func _on_died() -> void:
	visible = false
	set_process(false)


func _refresh_fill(current: float, max_value: float) -> void:
	if _fill_mesh == null:
		return
	var ratio := clampf(current / maxf(max_value, 0.001), 0.0, 1.0)
	var width := BAR_WIDTH * ratio
	_fill_mesh.size = Vector2(maxf(width, 0.001), BAR_HEIGHT)
	_fill.position.x = -(BAR_WIDTH - width) * 0.5
