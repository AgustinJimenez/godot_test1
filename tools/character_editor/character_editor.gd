extends Node3D
## General held-object contact-pose calibration. Bone corrections are additive
## to the selected animation so presets remain reusable by gameplay systems.

const GRIP_MODIFIER := preload("res://actors/player/player_hand_grip_modifier.gd")
const RAW_COMPARISON := preload("res://tools/character_editor/raw_animation_comparison.gd")
const DEFAULT_OBJECT_PATH := "res://assets/models/flashlight/flashlight.glb"
const DEFAULT_POSE_PRESET_PATH := "res://actors/player/flashlight_grip_pose.json"
const DEFAULT_ATTACHMENT_BONE := &"RightHand"
const DEFAULT_ANIMATION := &"unarmed_torch_idle"
const DEFAULT_OBJECT_SCALE := 0.12
const DEFAULT_OBJECT_POSITION := Vector3(-0.09, -0.03, -0.01)
const DEFAULT_OBJECT_ROTATION := Vector3(-95.0, -180.0, 1.0)
const INITIAL_RIGHT_ARM_ROTATION := Vector3(14.0, 5.0, 10.0)
const MOVE_SPEED := 1.0
const LOOK_SENS := 0.003
const ORBIT_SENS := 0.006
const MIN_ORBIT_DISTANCE := 0.45
const MAX_ORBIT_DISTANCE := 5.0
const ZOOM_STEP := 0.88
const JOINT_RADIUS := 0.022
const SELECTED_JOINT_RADIUS := 0.029
const BONE_RADIUS := 0.009
const ROTATION_RING_RADIUS := 0.105
const ROTATION_RING_THICKNESS := 0.006
const RING_PICK_TOLERANCE := 0.025
const CHARACTER_PICK_RADIUS_PIXELS := 72.0
const CAMERA_MODE_ORBIT := 0
const CAMERA_MODE_MOVE := 1
const BASE_UI_HEIGHT := 900.0
const MIN_PANEL_WIDTH := 720.0
const MAX_PANEL_WIDTH := 1000.0
const MIN_PANEL_HEIGHT := 680.0
const MAX_PANEL_HEIGHT := 1000.0
const PANEL_WIDTH_RATIO := 0.62
const MAX_UI_SCALE := 1.5
const MIN_USER_PANEL_SIZE := Vector2(620.0, 560.0)
const MIN_BONE_SCROLL_HEIGHT := 150.0
const COLLAPSED_PANEL_HEIGHT := 58.0
const COLLAPSE_ICON := preload("res://assets/ui/icons/lucide/chevron-up.svg")
const EXPAND_ICON := preload("res://assets/ui/icons/lucide/chevron-down.svg")
const AXIS_COLORS := [
	Color(0.95, 0.25, 0.22),
	Color(0.3, 0.9, 0.38),
	Color(0.25, 0.55, 1.0),
]
const BONE_SECTION_LAYOUT: Array[Dictionary] = [
	{"key": &"body", "label": "Body", "parent": &"", "depth": 0},
	{"key": &"right_arm", "label": "Right arm", "parent": &"body", "depth": 1},
	{"key": &"right_hand", "label": "Hand", "parent": &"right_arm", "depth": 2},
	{"key": &"right_thumb", "label": "Thumb", "parent": &"right_hand", "depth": 3},
	{"key": &"right_index", "label": "Index finger", "parent": &"right_hand", "depth": 3},
	{"key": &"right_middle", "label": "Middle finger", "parent": &"right_hand", "depth": 3},
	{"key": &"right_ring", "label": "Ring finger", "parent": &"right_hand", "depth": 3},
	{"key": &"right_pinky", "label": "Little finger", "parent": &"right_hand", "depth": 3},
	{"key": &"left_arm", "label": "Left arm", "parent": &"body", "depth": 1},
	{"key": &"left_hand", "label": "Hand", "parent": &"left_arm", "depth": 2},
	{"key": &"left_thumb", "label": "Thumb", "parent": &"left_hand", "depth": 3},
	{"key": &"left_index", "label": "Index finger", "parent": &"left_hand", "depth": 3},
	{"key": &"left_middle", "label": "Middle finger", "parent": &"left_hand", "depth": 3},
	{"key": &"left_ring", "label": "Ring finger", "parent": &"left_hand", "depth": 3},
	{"key": &"left_pinky", "label": "Little finger", "parent": &"left_hand", "depth": 3},
	{"key": &"right_leg", "label": "Right leg", "parent": &"body", "depth": 1},
	{"key": &"right_foot", "label": "Foot", "parent": &"right_leg", "depth": 2},
	{"key": &"left_leg", "label": "Left leg", "parent": &"body", "depth": 1},
	{"key": &"left_foot", "label": "Foot", "parent": &"left_leg", "depth": 2},
	{"key": &"other", "label": "Other joints", "parent": &"body", "depth": 1},
]

@onready var body: PlayerBody = $Body
@onready var target_compare_label: Label3D = $Body/CompareLabel
@onready var raw_source_ual1: Node3D = $RawSourceUAL1
@onready var raw_source_ual2: Node3D = $RawSourceUAL2
@onready var camera: Camera3D = $Camera
@onready var ui_layer: CanvasLayer = $UI
@onready var panel: Panel = $UI/Panel
@onready var viewport_toolbar: PanelContainer = $UI/ViewportToolbar
@onready var panel_vbox: VBoxContainer = $UI/Panel/PanelScroll/Margin/VBox
@onready var title_bar: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/TitleBar
@onready var collapse_panel_button: Button = $UI/Panel/PanelScroll/Margin/VBox/TitleBar/Collapse
@onready var panel_resize_handle: Button = $UI/PanelResizeHandle
@onready var orbit_camera_button: Button = $UI/ViewportToolbar/Margin/Buttons/Orbit
@onready var move_camera_button: Button = $UI/ViewportToolbar/Margin/Buttons/Move
@onready var zoom_out_button: Button = $UI/ViewportToolbar/Margin/Buttons/ZoomOut
@onready var zoom_in_button: Button = $UI/ViewportToolbar/Margin/Buttons/ZoomIn
@onready var reset_view_button: Button = $UI/ViewportToolbar/Margin/Buttons/ResetView
@onready var animation_group_picker: OptionButton = $UI/Panel/PanelScroll/Margin/VBox/AnimationRow/GroupPicker
@onready var animation_picker: OptionButton = $UI/Panel/PanelScroll/Margin/VBox/AnimationRow/AnimationPicker
@onready var edit_mode_button: Button = $UI/Panel/PanelScroll/Margin/VBox/EditorModeRow/Edit
@onready var compare_mode_button: Button = $UI/Panel/PanelScroll/Margin/VBox/EditorModeRow/Compare
@onready var object_path_field: LineEdit = $UI/Panel/PanelScroll/Margin/VBox/ObjectRow/ObjectPath
@onready var attachment_picker: OptionButton = $UI/Panel/PanelScroll/Margin/VBox/AttachmentRow/AttachmentPicker
@onready var scale_slider: HSlider = $UI/Panel/PanelScroll/Margin/VBox/AttachmentRow/ScaleSlider
@onready var scale_value: Label = $UI/Panel/PanelScroll/Margin/VBox/AttachmentRow/ScaleValue
@onready var preset_path_field: LineEdit = $UI/Panel/PanelScroll/Margin/VBox/PresetRow/PresetPath
@onready var view_picker: OptionButton = $UI/Panel/PanelScroll/Margin/VBox/ViewRow/ViewPicker
@onready var pause_toggle: CheckButton = $UI/Panel/PanelScroll/Margin/VBox/DisplayOptions/PauseAnimation
@onready var show_bones_toggle: CheckButton = $UI/Panel/PanelScroll/Margin/VBox/DisplayOptions/ShowBones
@onready var free_camera_toggle: CheckButton = $UI/Panel/PanelScroll/Margin/VBox/DisplayOptions/FreeCamera
@onready var axis_ring_toggles: Array[CheckButton] = [
	$UI/Panel/PanelScroll/Margin/VBox/BoneSection/XRing,
	$UI/Panel/PanelScroll/Margin/VBox/BoneSection/YRing,
	$UI/Panel/PanelScroll/Margin/VBox/BoneSection/ZRing,
]
@onready var pose_helpers: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/PoseHelpers
@onready var pose_helper_title: Label = $UI/Panel/PanelScroll/Margin/VBox/PoseHelpers/Title
@onready var pose_helper_controls: HFlowContainer = $UI/Panel/PanelScroll/Margin/VBox/PoseHelpers/Controls
@onready var bone_scroll: ScrollContainer = $UI/Panel/PanelScroll/Margin/VBox/BoneScroll
@onready var bone_controls: VBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/BoneScroll/BoneControls
@onready var position_sliders: Array[HSlider] = [
	$UI/Panel/PanelScroll/Margin/VBox/PositionX/Slider,
	$UI/Panel/PanelScroll/Margin/VBox/PositionY/Slider,
	$UI/Panel/PanelScroll/Margin/VBox/PositionZ/Slider,
]
@onready var position_values: Array[Label] = [
	$UI/Panel/PanelScroll/Margin/VBox/PositionX/Value,
	$UI/Panel/PanelScroll/Margin/VBox/PositionY/Value,
	$UI/Panel/PanelScroll/Margin/VBox/PositionZ/Value,
]
@onready var rotation_sliders: Array[HSlider] = [
	$UI/Panel/PanelScroll/Margin/VBox/RotationX/Slider,
	$UI/Panel/PanelScroll/Margin/VBox/RotationY/Slider,
	$UI/Panel/PanelScroll/Margin/VBox/RotationZ/Slider,
]
@onready var rotation_values: Array[Label] = [
	$UI/Panel/PanelScroll/Margin/VBox/RotationX/Value,
	$UI/Panel/PanelScroll/Margin/VBox/RotationY/Value,
	$UI/Panel/PanelScroll/Margin/VBox/RotationZ/Value,
]
@onready var status_label: Label = $UI/Panel/PanelScroll/Margin/VBox/Status
@onready var object_dialog: FileDialog = $UI/ObjectDialog
@onready var open_preset_dialog: FileDialog = $UI/OpenPresetDialog
@onready var save_preset_dialog: FileDialog = $UI/SavePresetDialog

var _modifier: PlayerHandGripModifier
var _comparison: RawAnimationComparison
var _held_object: Node3D
var _object_attachment: BoneAttachment3D
var _full_body_mesh: Mesh
var _isolated_attachment_mesh: ArrayMesh
var _bone_debug_root: Node3D
var _bone_segment_mesh: CylinderMesh
var _joint_mesh: SphereMesh
var _rotation_ring_mesh: TorusMesh
var _bone_segment_material: StandardMaterial3D
var _joint_material: StandardMaterial3D
var _selected_joint_material: StandardMaterial3D
var _bone_segments: Dictionary = {}
var _joint_instances: Dictionary = {}
var _rotation_rings: Array[MeshInstance3D] = []
var _visible_bone_indices: Array[int] = []
var _bone_slider_controls: Dictionary = {}
var _section_headers: Dictionary = {}
var _section_contents: Dictionary = {}
var _section_expanded: Dictionary = {}
var _section_parents: Dictionary = {}
var _selected_bone := &"RightArm"
var _attachment_bone := DEFAULT_ATTACHMENT_BONE
var _current_animation := DEFAULT_ANIMATION
var _current_object_path := DEFAULT_OBJECT_PATH
var _current_pose_path := DEFAULT_POSE_PRESET_PATH
var _animation_groups: Dictionary = {}
var _hand_helper_baseline: Dictionary = {}
var _hand_helper_side := ""
var _hand_openness_slider: HSlider
var _joint_focus_active := false
var _focused_camera_offset := Vector3.ZERO
var _drag_axis := -1
var _drag_start_rotation := Vector3.ZERO
var _drag_start_vector := Vector3.ZERO
var _drag_plane_normal := Vector3.ZERO
var _drag_center := Vector3.ZERO
var _captured := false
var _orbiting := false
var _orbiting_joint := false
var _moving_camera := false
var _camera_mode := CAMERA_MODE_ORBIT
var _orbit_target := Vector3.ZERO
var _orbit_distance := 2.5
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _syncing_controls := false
var _yaw := 0.0
var _pitch := 0.0
var _ui_scale := 1.0
var _panel_user_layout := false
var _panel_collapsed := false
var _resizing_panel := false
var _dragging_panel := false
var _expanded_panel_size := Vector2.ZERO
var _edit_panel_size_before_compare := Vector2.ZERO


func _ready() -> void:
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	camera.current = true
	body.set_held_flashlight_visible(false)
	_full_body_mesh = body.mesh.mesh
	_setup_modifier()
	_setup_held_object()
	_setup_bone_debug()
	_comparison = RAW_COMPARISON.new()
	_comparison.setup(body, target_compare_label, raw_source_ual1, raw_source_ual2)
	_setup_controls()
	_load_pose_from_path(DEFAULT_POSE_PRESET_PATH, true)
	if "show_bones" in OS.get_cmdline_user_args():
		show_bones_toggle.set_pressed_no_signal(true)
		_on_show_bones_toggled(true)
	if EngineDebugger.is_active():
		# Lets addons/mcp_bridge query this exact running instance's live
		# pose over the editor debugger message channel, as opposed to the
		# invocation-based dump_bones= automation arg, which only ever reads
		# a fresh, separately-configured headless process.
		EngineDebugger.register_message_capture("mcp", _on_mcp_debugger_message)
	await get_tree().process_frame
	_frame_full_body()
	await _run_automation_args()


func _update_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_ui_scale = clampf(viewport_size.y / BASE_UI_HEIGHT, 1.0, MAX_UI_SCALE)
	ui_layer.transform = Transform2D.IDENTITY.scaled(Vector2.ONE * _ui_scale)
	var logical_viewport_size := viewport_size / _ui_scale
	var panel_width := clampf(
			logical_viewport_size.x * PANEL_WIDTH_RATIO,
			MIN_PANEL_WIDTH,
			MAX_PANEL_WIDTH)
	var panel_height := clampf(
			logical_viewport_size.y - 32.0,
			MIN_PANEL_HEIGHT,
			MAX_PANEL_HEIGHT)
	if not _panel_user_layout:
		panel.position = Vector2(16.0, 16.0)
		panel.size = Vector2(panel_width, panel_height)
		_expanded_panel_size = panel.size
	else:
		_clamp_panel_to_viewport(logical_viewport_size)
	viewport_toolbar.position = Vector2(
			logical_viewport_size.x - viewport_toolbar.size.x - 16.0,
			logical_viewport_size.y - viewport_toolbar.size.y - 16.0)
	_update_panel_dependent_layout()
	_update_panel_resize_handle()


func _clamp_panel_to_viewport(logical_viewport_size: Vector2) -> void:
	var max_position := Vector2(
			maxf(16.0, logical_viewport_size.x - 240.0),
			maxf(16.0, logical_viewport_size.y - COLLAPSED_PANEL_HEIGHT))
	panel.position = panel.position.clamp(Vector2(0.0, 0.0), max_position)
	var available_size := logical_viewport_size - panel.position - Vector2(8.0, 8.0)
	if _panel_collapsed:
		panel.size.y = COLLAPSED_PANEL_HEIGHT
		panel.size.x = minf(panel.size.x, available_size.x)
	else:
		panel.size = Vector2(
				clampf(panel.size.x, minf(MIN_USER_PANEL_SIZE.x, available_size.x),
						available_size.x),
				clampf(panel.size.y, minf(MIN_USER_PANEL_SIZE.y, available_size.y),
						available_size.y))
		_expanded_panel_size = panel.size


func _update_panel_dependent_layout() -> void:
	if not _panel_collapsed:
		bone_scroll.custom_minimum_size.y = MIN_BONE_SCROLL_HEIGHT + maxf(
				panel.size.y - MIN_PANEL_HEIGHT, 0.0)


func _update_panel_resize_handle() -> void:
	panel_resize_handle.visible = not _panel_collapsed
	panel_resize_handle.position = panel.position + panel.size - panel_resize_handle.size


func _setup_modifier() -> void:
	_modifier = GRIP_MODIFIER.new() as PlayerHandGripModifier
	_modifier.name = &"HeldObjectPoseModifier"
	_modifier.set_bone_rotation(&"RightArm", INITIAL_RIGHT_ARM_ROTATION)
	body.skeleton.add_child(_modifier)


func _build_isolated_attachment_mesh() -> ArrayMesh:
	var source := body.mesh.mesh
	var skin := body.mesh.skin
	if source == null or skin == null:
		push_warning("Character editor could not isolate the attachment mesh")
		return null
	var attachment_index := body.skeleton.find_bone(_attachment_bone)
	if attachment_index < 0:
		return null
	var attachment_binds := {}
	for bind_index in skin.get_bind_count():
		var bone_index := body.skeleton.find_bone(skin.get_bind_name(bind_index))
		if _bone_is_descendant_of(bone_index, attachment_index):
			attachment_binds[bind_index] = true
	var isolated := ArrayMesh.new()
	for surface_index in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if vertices.is_empty() or bones.is_empty() or indices.is_empty():
			continue
		var influences_per_vertex := bones.size() / vertices.size()
		var attachment_vertices := PackedByteArray()
		attachment_vertices.resize(vertices.size())
		for vertex_index in vertices.size():
			var attachment_weight := 0.0
			for influence in influences_per_vertex:
				var offset := vertex_index * influences_per_vertex + influence
				if attachment_binds.has(bones[offset]):
					attachment_weight += weights[offset]
			attachment_vertices[vertex_index] = 1 if attachment_weight >= 0.25 else 0
		var attachment_indices := PackedInt32Array()
		for triangle_start in range(0, indices.size(), 3):
			if (attachment_vertices[indices[triangle_start]] > 0
					and attachment_vertices[indices[triangle_start + 1]] > 0
					and attachment_vertices[indices[triangle_start + 2]] > 0):
				attachment_indices.append(indices[triangle_start])
				attachment_indices.append(indices[triangle_start + 1])
				attachment_indices.append(indices[triangle_start + 2])
		if attachment_indices.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = attachment_indices
		isolated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		isolated.surface_set_material(
				isolated.get_surface_count() - 1, source.surface_get_material(surface_index))
	if isolated.get_surface_count() == 0:
		push_warning("Character editor found no mesh weighted to %s" % _attachment_bone)
		return null
	return isolated


func _bone_is_descendant_of(bone_index: int, ancestor_index: int) -> bool:
	while bone_index >= 0:
		if bone_index == ancestor_index:
			return true
		bone_index = body.skeleton.get_bone_parent(bone_index)
	return false


func _setup_held_object() -> void:
	_object_attachment = BoneAttachment3D.new()
	_object_attachment.name = &"HeldObjectAttachment"
	_object_attachment.bone_name = _attachment_bone
	body.skeleton.add_child(_object_attachment)
	_load_object(DEFAULT_OBJECT_PATH, true)


func _load_object(path: String, reset_transform: bool) -> bool:
	var resource_path := _localize_resource_path(path)
	var resource := load(resource_path)
	if not resource is PackedScene:
		status_label.text = "Object must import as a PackedScene"
		return false
	var instance := (resource as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		status_label.text = "Object scene root must be Node3D"
		return false
	if is_instance_valid(_held_object):
		_held_object.free()
	_held_object = instance as Node3D
	_held_object.name = &"HeldObject"
	_object_attachment.add_child(_held_object)
	_current_object_path = resource_path
	if reset_transform:
		_held_object.position = Vector3.ZERO
		_held_object.rotation = Vector3.ZERO
		_held_object.scale = Vector3.ONE
	object_path_field.text = _current_object_path
	return true


func _localize_resource_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return ProjectSettings.localize_path(path)


func _setup_bone_debug() -> void:
	_bone_debug_root = Node3D.new()
	_bone_debug_root.name = &"BoneRotationGizmo"
	_bone_debug_root.visible = false
	body.skeleton.add_child(_bone_debug_root)

	_bone_segment_mesh = CylinderMesh.new()
	_bone_segment_mesh.top_radius = BONE_RADIUS
	_bone_segment_mesh.bottom_radius = BONE_RADIUS
	_bone_segment_mesh.height = 1.0
	_bone_segment_mesh.radial_segments = 8
	_joint_mesh = SphereMesh.new()
	_joint_mesh.radius = JOINT_RADIUS
	_joint_mesh.height = JOINT_RADIUS * 2.0
	_joint_mesh.radial_segments = 12
	_joint_mesh.rings = 8
	_rotation_ring_mesh = TorusMesh.new()
	_rotation_ring_mesh.inner_radius = ROTATION_RING_RADIUS - ROTATION_RING_THICKNESS
	_rotation_ring_mesh.outer_radius = ROTATION_RING_RADIUS + ROTATION_RING_THICKNESS
	_rotation_ring_mesh.rings = 48
	_rotation_ring_mesh.ring_segments = 8

	_bone_segment_material = _make_debug_material(Color(0.12, 0.72, 0.95, 0.9))
	_joint_material = _make_debug_material(Color(0.2, 0.86, 1.0, 1.0))
	_selected_joint_material = _make_debug_material(Color(1.0, 0.72, 0.12, 1.0))
	for axis in 3:
		var ring := _make_debug_mesh_instance(
				_rotation_ring_mesh, _make_debug_material(AXIS_COLORS[axis]))
		ring.name = StringName("RotationRing%s" % "XYZ"[axis])
		_rotation_rings.append(ring)
		_bone_debug_root.add_child(ring)
	body.skeleton.skeleton_updated.connect(_update_bone_gizmo)
	_rebuild_bone_gizmo()


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _make_debug_mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _setup_controls() -> void:
	_setup_animation_controls()
	_setup_attachment_controls()
	edit_mode_button.pressed.connect(_on_editor_mode_pressed.bind(false))
	compare_mode_button.pressed.connect(_on_editor_mode_pressed.bind(true))
	view_picker.add_item("Full body")
	view_picker.add_item("Attachment close-up")
	view_picker.add_item("Isolated attachment")
	view_picker.item_selected.connect(_on_view_selected)
	pause_toggle.toggled.connect(_on_pause_toggled)
	show_bones_toggle.toggled.connect(_on_show_bones_toggled)
	free_camera_toggle.toggled.connect(_on_free_camera_toggled)
	orbit_camera_button.pressed.connect(_on_camera_mode_pressed.bind(CAMERA_MODE_ORBIT))
	move_camera_button.pressed.connect(_on_camera_mode_pressed.bind(CAMERA_MODE_MOVE))
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	reset_view_button.pressed.connect(_on_reset_camera_view_pressed)
	collapse_panel_button.pressed.connect(_on_collapse_panel_pressed)
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	panel_resize_handle.gui_input.connect(_on_panel_resize_handle_gui_input)
	for axis in 3:
		axis_ring_toggles[axis].toggled.connect(_on_axis_ring_toggled.bind(axis))
	_populate_bone_controls()
	for axis in 3:
		position_sliders[axis].value_changed.connect(_on_object_position_changed.bind(axis))
		rotation_sliders[axis].value_changed.connect(_on_object_rotation_changed.bind(axis))
		_color_axis_slider(position_sliders[axis], position_values[axis], axis)
		_color_axis_slider(rotation_sliders[axis], rotation_values[axis], axis)
	scale_slider.value_changed.connect(_on_object_scale_changed)
	_sync_object_controls()
	preset_path_field.text = _current_pose_path
	_update_camera_mode_buttons()
	_update_editor_mode_buttons()


func _on_editor_mode_pressed(compare_enabled: bool) -> void:
	var mode_changed: bool = compare_enabled != _comparison.enabled
	if mode_changed and compare_enabled and not _panel_collapsed:
		_edit_panel_size_before_compare = panel.size
		panel.size.x = minf(panel.size.x, MIN_USER_PANEL_SIZE.x)
		_expanded_panel_size = panel.size
		_panel_user_layout = true
	elif (mode_changed and not compare_enabled
			and not _panel_collapsed and not _edit_panel_size_before_compare.is_zero_approx()):
		panel.size = _edit_panel_size_before_compare
		_expanded_panel_size = panel.size
		_clamp_panel_to_viewport(get_viewport().get_visible_rect().size / _ui_scale)
	_update_panel_dependent_layout()
	_update_panel_resize_handle()
	view_picker.select(0)
	view_picker.disabled = compare_enabled
	body.mesh.mesh = _full_body_mesh
	_joint_focus_active = false
	_orbiting = false
	_orbiting_joint = false
	var comparison_status: String = _comparison.set_enabled(
			compare_enabled, _current_animation)
	_comparison.set_paused(pause_toggle.button_pressed)
	_update_editor_mode_buttons()
	_frame_full_body()
	status_label.text = comparison_status


func _update_editor_mode_buttons() -> void:
	edit_mode_button.set_pressed_no_signal(not _comparison.enabled)
	compare_mode_button.set_pressed_no_signal(_comparison.enabled)


func _on_camera_mode_pressed(mode: int) -> void:
	_camera_mode = mode
	_captured = false
	_orbiting = false
	_orbiting_joint = false
	_moving_camera = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if free_camera_toggle.button_pressed:
		free_camera_toggle.set_pressed_no_signal(false)
	_update_camera_mode_buttons()
	status_label.text = ("Drag empty 3D space to orbit" if mode == CAMERA_MODE_ORBIT
			else "Drag empty 3D space to move the camera")


func _update_camera_mode_buttons() -> void:
	orbit_camera_button.set_pressed_no_signal(_camera_mode == CAMERA_MODE_ORBIT)
	move_camera_button.set_pressed_no_signal(_camera_mode == CAMERA_MODE_MOVE)


func _on_zoom_out_pressed() -> void:
	_apply_camera_zoom(1.0 / ZOOM_STEP)


func _on_zoom_in_pressed() -> void:
	_apply_camera_zoom(ZOOM_STEP)


func _on_reset_camera_view_pressed() -> void:
	view_picker.select(0)
	_on_view_selected(0)
	status_label.text = "Camera view reset"


func _on_collapse_panel_pressed() -> void:
	_panel_collapsed = not _panel_collapsed
	_panel_user_layout = true
	if _panel_collapsed:
		_expanded_panel_size = panel.size
	for child in panel_vbox.get_children():
		if child != title_bar:
			(child as Control).visible = not _panel_collapsed
	collapse_panel_button.icon = EXPAND_ICON if _panel_collapsed else COLLAPSE_ICON
	collapse_panel_button.tooltip_text = (
			"Restore panel" if _panel_collapsed else "Minimize panel")
	if _panel_collapsed:
		panel.size.y = COLLAPSED_PANEL_HEIGHT
	else:
		panel.size = _expanded_panel_size
	_update_panel_dependent_layout()
	_update_panel_resize_handle()


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_panel = event.pressed
		if event.pressed:
			_panel_user_layout = true
	elif event is InputEventMouseMotion and _dragging_panel:
		panel.position += event.relative / _ui_scale
		_clamp_panel_to_viewport(get_viewport().get_visible_rect().size / _ui_scale)
		_update_panel_resize_handle()


func _on_panel_resize_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing_panel = event.pressed
		if event.pressed:
			_panel_user_layout = true
	elif event is InputEventMouseMotion and _resizing_panel:
		var logical_viewport_size := get_viewport().get_visible_rect().size / _ui_scale
		var available_size := logical_viewport_size - panel.position - Vector2(8.0, 8.0)
		var desired_size: Vector2 = panel.size + event.relative / _ui_scale
		desired_size = Vector2(
				clampf(desired_size.x, minf(MIN_USER_PANEL_SIZE.x, available_size.x),
						available_size.x),
				clampf(desired_size.y, minf(MIN_USER_PANEL_SIZE.y, available_size.y),
						available_size.y))
		bone_scroll.custom_minimum_size.y = MIN_BONE_SCROLL_HEIGHT + maxf(
				desired_size.y - MIN_PANEL_HEIGHT, 0.0)
		panel.size = desired_size
		_expanded_panel_size = panel.size
		_update_panel_resize_handle()


func _color_axis_slider(slider: HSlider, value_label: Label, axis: int) -> void:
	var axis_color: Color = AXIS_COLORS[axis]
	slider.modulate = axis_color
	value_label.add_theme_color_override(&"font_color", axis_color)
	var axis_label := slider.get_parent().get_node_or_null("Axis") as Label
	if axis_label != null:
		axis_label.add_theme_color_override(&"font_color", axis_color)


func _setup_animation_controls() -> void:
	_animation_groups = body.get_animation_groups()
	for group_name in _animation_groups:
		animation_group_picker.add_item(String(group_name))
		animation_group_picker.set_item_metadata(
				animation_group_picker.item_count - 1, StringName(group_name))
	animation_group_picker.item_selected.connect(_on_animation_group_selected)
	animation_picker.item_selected.connect(_on_animation_selected)
	_select_animation_in_ui(_current_animation)
	body.play_debug_anim(_current_animation, 0.0)


func _setup_attachment_controls() -> void:
	for bone_index in body.skeleton.get_bone_count():
		var bone_name := body.skeleton.get_bone_name(bone_index)
		attachment_picker.add_item(String(bone_name))
		attachment_picker.set_item_metadata(attachment_picker.item_count - 1, bone_name)
	attachment_picker.item_selected.connect(_on_attachment_selected)
	_select_attachment_in_ui(_attachment_bone)
	_isolated_attachment_mesh = _build_isolated_attachment_mesh()


func _on_animation_group_selected(index: int) -> void:
	_populate_animation_picker(animation_group_picker.get_item_metadata(index))


func _populate_animation_picker(group_name: StringName) -> void:
	animation_picker.clear()
	var animations: Array = _animation_groups.get(group_name, [])
	for animation_name in animations:
		animation_picker.add_item(String(animation_name))
		animation_picker.set_item_metadata(
				animation_picker.item_count - 1, StringName(animation_name))


func _on_animation_selected(index: int) -> void:
	_set_animation(animation_picker.get_item_metadata(index))


func _set_animation(animation_name: StringName) -> void:
	_current_animation = animation_name
	body.play_debug_anim(animation_name, 0.0)
	var comparison_status: String = _comparison.play_animation(animation_name)
	if pause_toggle.button_pressed:
		body.anim_player.pause()
		_comparison.set_paused(true)
	status_label.text = (comparison_status if not comparison_status.is_empty()
			else "Playing %s" % animation_name)


func _select_animation_in_ui(animation_name: StringName) -> void:
	for group_index in animation_group_picker.item_count:
		var group_name: StringName = animation_group_picker.get_item_metadata(group_index)
		if animation_name in _animation_groups.get(group_name, []):
			animation_group_picker.select(group_index)
			_populate_animation_picker(group_name)
			for animation_index in animation_picker.item_count:
				if animation_picker.get_item_metadata(animation_index) == animation_name:
					animation_picker.select(animation_index)
					return


func _on_attachment_selected(index: int) -> void:
	_set_attachment_bone(attachment_picker.get_item_metadata(index), true)


func _set_attachment_bone(bone_name: StringName, update_view: bool) -> void:
	if body.skeleton.find_bone(bone_name) < 0:
		return
	_attachment_bone = bone_name
	_object_attachment.bone_name = bone_name
	_isolated_attachment_mesh = _build_isolated_attachment_mesh()
	if update_view and view_picker.selected == 2:
		body.mesh.mesh = (_isolated_attachment_mesh
				if _isolated_attachment_mesh != null else _full_body_mesh)
	if update_view and view_picker.selected != 0:
		_frame_attachment()
	status_label.text = "Object attached to %s" % bone_name


func _select_attachment_in_ui(bone_name: StringName) -> void:
	for index in attachment_picker.item_count:
		if attachment_picker.get_item_metadata(index) == bone_name:
			attachment_picker.select(index)
			return


func _populate_bone_controls() -> void:
	_bone_slider_controls.clear()
	_section_headers.clear()
	_section_contents.clear()
	_section_expanded.clear()
	_section_parents.clear()
	for child in bone_controls.get_children():
		child.free()
	var section_bones := {}
	for section: Dictionary in BONE_SECTION_LAYOUT:
		var key: StringName = section["key"]
		section_bones[key] = PackedStringArray()
		_section_parents[key] = section["parent"]
		_section_expanded[key] = true
	for bone_index in body.skeleton.get_bone_count():
		var bone_name := body.skeleton.get_bone_name(bone_index)
		var section_key := _get_bone_section(bone_name)
		var names: PackedStringArray = section_bones[section_key]
		names.append(bone_name)
		section_bones[section_key] = names
	for section: Dictionary in BONE_SECTION_LAYOUT:
		var key: StringName = section["key"]
		var bones: PackedStringArray = section_bones[key]
		if bones.is_empty():
			continue
		var header := Button.new()
		header.custom_minimum_size.y = 34.0
		header.toggle_mode = true
		header.button_pressed = true
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override(&"font_size", 13)
		header.toggled.connect(_on_bone_section_toggled.bind(key))
		bone_controls.add_child(header)
		_section_headers[key] = header
		var content := VBoxContainer.new()
		content.add_theme_constant_override(&"separation", 3)
		bone_controls.add_child(content)
		_section_contents[key] = content
		for bone_name in bones:
			_add_bone_control_row(content, bone_name)
	_refresh_bone_section_visibility()
	_update_selected_bone_ui()
	_update_pose_helpers()


func _add_bone_control_row(container: VBoxContainer, bone_name: StringName) -> void:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 52.0
	row_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row_panel.gui_input.connect(_on_bone_row_gui_input.bind(bone_name))
	container.add_child(row_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override(&"separation", 8)
	row_panel.add_child(row)
	var joint_label := Label.new()
	joint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joint_label.custom_minimum_size.x = 140.0
	joint_label.text = _display_bone_name(String(bone_name))
	joint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(joint_label)
	var rotation := _modifier.get_bone_rotation(bone_name)
	var sliders: Array[HSlider] = []
	var labels: Array[Label] = []
	for axis in 3:
		var axis_box := VBoxContainer.new()
		axis_box.mouse_filter = Control.MOUSE_FILTER_PASS
		axis_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_box.add_theme_constant_override(&"separation", 0)
		row.add_child(axis_box)
		var value_label := Label.new()
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.text = "%s  %+.0f" % ["XYZ"[axis], rotation[axis]]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override(&"font_size", 11)
		value_label.add_theme_color_override(&"font_color", AXIS_COLORS[axis])
		axis_box.add_child(value_label)
		var slider := HSlider.new()
		slider.min_value = -180.0
		slider.max_value = 180.0
		slider.step = 1.0
		slider.value = rotation[axis]
		slider.modulate = AXIS_COLORS[axis]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_bone_slider_changed.bind(
				bone_name, axis, value_label))
		axis_box.add_child(slider)
		sliders.append(slider)
		labels.append(value_label)
	_bone_slider_controls[bone_name] = {
		"sliders": sliders,
		"labels": labels,
		"row": row_panel,
		"joint_label": joint_label,
	}


func _on_bone_section_toggled(expanded: bool, section_key: StringName) -> void:
	_section_expanded[section_key] = expanded
	_refresh_bone_section_visibility()
	if expanded:
		var representative := _get_section_representative_bone(section_key)
		if representative != &"" and body.skeleton.find_bone(representative) >= 0:
			_select_bone(representative, true)


func _get_section_representative_bone(section_key: StringName) -> StringName:
	var representatives := {
		&"body": &"Hips",
		&"right_arm": &"RightArm",
		&"right_hand": &"RightHand",
		&"right_thumb": &"RightHandThumb1",
		&"right_index": &"RightHandIndex1",
		&"right_middle": &"RightHandMiddle1",
		&"right_ring": &"RightHandRing1",
		&"right_pinky": &"RightHandPinky1",
		&"left_arm": &"LeftArm",
		&"left_hand": &"LeftHand",
		&"left_thumb": &"LeftHandThumb1",
		&"left_index": &"LeftHandIndex1",
		&"left_middle": &"LeftHandMiddle1",
		&"left_ring": &"LeftHandRing1",
		&"left_pinky": &"LeftHandPinky1",
		&"right_leg": &"RightUpLeg",
		&"right_foot": &"RightFoot",
		&"left_leg": &"LeftUpLeg",
		&"left_foot": &"LeftFoot",
	}
	return representatives.get(section_key, &"")


func _refresh_bone_section_visibility() -> void:
	for section: Dictionary in BONE_SECTION_LAYOUT:
		var key: StringName = section["key"]
		if not _section_headers.has(key):
			continue
		var ancestors_expanded := true
		var parent: StringName = _section_parents[key]
		while parent != &"":
			if not _section_expanded.get(parent, true):
				ancestors_expanded = false
				break
			parent = _section_parents.get(parent, &"")
		var expanded: bool = _section_expanded[key]
		var header: Button = _section_headers[key]
		header.visible = ancestors_expanded
		header.text = "%s%s  %s" % [
			"  ".repeat(section["depth"]), "-" if expanded else "+", section["label"]]
		(_section_contents[key] as VBoxContainer).visible = ancestors_expanded and expanded


func _get_bone_section(bone_name: StringName) -> StringName:
	var name := String(bone_name)
	if name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]:
		return &"body"
	for side: String in ["Right", "Left"]:
		var side_key: String = side.to_lower()
		if name in [side + "Shoulder", side + "Arm", side + "ForeArm"]:
			return StringName(side_key + "_arm")
		if name == side + "Hand":
			return StringName(side_key + "_hand")
		if name.begins_with(side + "Hand"):
			for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
				if finger in name:
					return StringName(side_key + "_" + finger.to_lower())
			return StringName(side_key + "_hand")
		if name in [side + "UpLeg", side + "Leg"]:
			return StringName(side_key + "_leg")
		if name.begins_with(side + "Foot") or name.begins_with(side + "Toe"):
			return StringName(side_key + "_foot")
	return &"other"


func _display_bone_name(bone_name: String) -> String:
	if bone_name in ["RightShoulder", "LeftShoulder"]:
		return "Shoulder"
	if bone_name in ["RightArm", "LeftArm"]:
		return "Upper arm"
	if bone_name in ["RightForeArm", "LeftForeArm"]:
		return "Forearm"
	if bone_name in ["RightHand", "LeftHand"]:
		return "Wrist"
	var label := bone_name.trim_prefix("RightHand").trim_prefix("LeftHand")
	label = label.replace("Pinky", "Little")
	for joint in range(1, 5):
		label = label.replace(str(joint), " joint " + str(joint))
	return label


func _on_view_selected(index: int) -> void:
	_joint_focus_active = false
	_orbiting = false
	_orbiting_joint = false
	body.mesh.mesh = (_isolated_attachment_mesh
			if index == 2 and _isolated_attachment_mesh != null else _full_body_mesh)
	if index == 0:
		_frame_full_body()
	else:
		_frame_attachment()


func _on_free_camera_toggled(enabled: bool) -> void:
	_captured = false
	_orbiting = false
	_orbiting_joint = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if enabled:
		status_label.text = "Click the 3D view to move the camera"
	elif _joint_focus_active:
		_frame_selected_joint()
	else:
		_focus_character_general()


func _focus_character_general() -> void:
	_joint_focus_active = false
	if view_picker.selected == 0:
		_frame_full_body()
	else:
		_frame_attachment()


func _on_pause_toggled(paused: bool) -> void:
	_comparison.set_paused(paused)
	if paused:
		body.anim_player.pause()
		status_label.text = "Animation paused"
	else:
		body.anim_player.play()
		status_label.text = "Animation playing"


func _frame_full_body() -> void:
	if _comparison.enabled:
		camera.fov = 50.0
		camera.h_offset = -1.9
		_orbit_target = _comparison.get_frame_target()
		camera.global_position = _orbit_target + Vector3(0.35, 0.2, 4.6)
	else:
		camera.fov = 44.0
		camera.h_offset = -0.95
		camera.global_position = body.global_position + Vector3(0.5, 1.2, 2.5)
		_orbit_target = body.global_position + Vector3(0.0, 1.05, 0.0)
	camera.look_at(_orbit_target)
	var orbit_offset := camera.global_position - _orbit_target
	_orbit_distance = orbit_offset.length()
	_orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
	_orbit_pitch = asin(clampf(
			orbit_offset.y / maxf(_orbit_distance, 0.001), -1.0, 1.0))
	_pitch = camera.rotation.x
	_yaw = camera.rotation.y


func _update_orbit_camera() -> void:
	var direction := _get_orbit_direction()
	camera.global_position = _orbit_target + direction * _orbit_distance
	camera.look_at(_orbit_target)


func _get_orbit_direction() -> Vector3:
	var horizontal := cos(_orbit_pitch)
	return Vector3(
			sin(_orbit_yaw) * horizontal,
			sin(_orbit_pitch),
			cos(_orbit_yaw) * horizontal)


func _begin_focused_joint_orbit() -> void:
	_orbiting = true
	_orbiting_joint = true
	_orbit_distance = _focused_camera_offset.length()
	if _orbit_distance <= 0.001:
		_orbit_distance = MIN_ORBIT_DISTANCE
	var direction := _focused_camera_offset / _orbit_distance
	_orbit_yaw = atan2(direction.x, direction.z)
	_orbit_pitch = asin(clampf(direction.y, -1.0, 1.0))
	status_label.text = "Joint focus locked; drag to orbit and use the wheel to zoom"


func _apply_camera_zoom(zoom_factor: float) -> void:
	if _joint_focus_active:
		var focus_distance := clampf(
				_focused_camera_offset.length() * zoom_factor,
				MIN_ORBIT_DISTANCE * 0.5, MAX_ORBIT_DISTANCE)
		_focused_camera_offset = _focused_camera_offset.normalized() * focus_distance
		_orbit_distance = focus_distance
		_update_focused_camera()
	else:
		_orbit_distance = clampf(
				_orbit_distance * zoom_factor,
				MIN_ORBIT_DISTANCE, MAX_ORBIT_DISTANCE)
		_update_orbit_camera()


func _frame_attachment() -> void:
	var attachment_index := body.skeleton.find_bone(_attachment_bone)
	if attachment_index < 0:
		return
	var attachment_position := body.skeleton.to_global(
			body.skeleton.get_bone_global_pose(attachment_index).origin)
	camera.fov = 38.0
	camera.h_offset = -0.68
	camera.global_position = attachment_position + Vector3(-0.48, 0.12, 0.55)
	camera.look_at(attachment_position)
	_orbit_target = attachment_position
	var orbit_offset := camera.global_position - _orbit_target
	_orbit_distance = orbit_offset.length()
	_orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
	_orbit_pitch = asin(clampf(
			orbit_offset.y / maxf(_orbit_distance, 0.001), -1.0, 1.0))
	_pitch = camera.rotation.x
	_yaw = camera.rotation.y


func _frame_selected_joint() -> void:
	var bone_index := body.skeleton.find_bone(_selected_bone)
	if bone_index < 0:
		return
	var target := body.skeleton.to_global(
			body.skeleton.get_bone_global_pose(bone_index).origin)
	var view_direction := (camera.global_position - target).normalized()
	if view_direction.is_zero_approx():
		view_direction = Vector3.FORWARD
	var focus_distance := 0.48 if "Hand" in String(_selected_bone) else 0.72
	_focused_camera_offset = view_direction * focus_distance
	camera.fov = 38.0
	camera.h_offset = 0.0
	camera.global_position = target + _focused_camera_offset
	camera.look_at(target)
	_pitch = camera.rotation.x
	_yaw = camera.rotation.y


func _update_focused_camera() -> void:
	var bone_index := body.skeleton.find_bone(_selected_bone)
	if bone_index < 0:
		return
	var target := body.skeleton.to_global(
			body.skeleton.get_bone_global_pose(bone_index).origin)
	camera.global_position = target + _focused_camera_offset
	camera.look_at(target)


func _on_bone_slider_changed(value: float, bone_name: StringName, axis: int,
		value_label: Label) -> void:
	var rotation := _modifier.get_bone_rotation(bone_name)
	rotation[axis] = value
	_modifier.set_bone_rotation(bone_name, rotation)
	value_label.text = "%s  %+.0f" % ["XYZ"[axis], value]
	_refresh_skeleton()
	_update_bone_gizmo()


func _on_bone_row_gui_input(event: InputEvent, bone_name: StringName) -> void:
	if (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		if not show_bones_toggle.button_pressed:
			show_bones_toggle.set_pressed_no_signal(true)
			_on_show_bones_toggled(true)
		_select_bone(bone_name, true)
		status_label.text = "%s selected; drag an X, Y, or Z ring" % _display_bone_name(
				bone_name)
		get_viewport().set_input_as_handled()


func _select_bone(bone_name: StringName, focus_joint: bool) -> void:
	_selected_bone = bone_name
	_expand_section_for_bone(bone_name)
	if bone_name in [&"RightHand", &"LeftHand"]:
		_expand_finger_sections(String(bone_name).trim_suffix("Hand"))
	_update_selected_bone_ui()
	_update_pose_helpers()
	_update_bone_gizmo()
	if focus_joint:
		_joint_focus_active = true
		if not free_camera_toggle.button_pressed:
			_frame_selected_joint()
	var controls: Dictionary = _bone_slider_controls.get(bone_name, {})
	if not controls.is_empty():
		bone_scroll.call_deferred(&"ensure_control_visible", controls["row"])


func _expand_finger_sections(side: String) -> void:
	for finger in ["thumb", "index", "middle", "ring", "pinky"]:
		var section_key := StringName(side.to_lower() + "_" + finger)
		_section_expanded[section_key] = true
		if _section_headers.has(section_key):
			(_section_headers[section_key] as Button).set_pressed_no_signal(true)
	_refresh_bone_section_visibility()


func _update_pose_helpers() -> void:
	for child in pose_helper_controls.get_children():
		child.free()
	_hand_openness_slider = null
	var bone_name := String(_selected_bone)
	var side := "Right" if bone_name.begins_with("Right") else (
			"Left" if bone_name.begins_with("Left") else "")
	if "Hand" in bone_name:
		_setup_hand_pose_helper(side)
	elif bone_name in [side + "Shoulder", side + "Arm", side + "ForeArm"]:
		_setup_animation_pose_helpers("%s ARM" % side.to_upper(), {
			"Relaxed": &"unarmed_idle",
			"Aim Front": &"Pistol_Aim_Neutral",
			"Carry": &"Walk_Carry",
			"Hand to Face": &"Idle_TalkingPhone",
		})
	elif bone_name in ["Head", "Neck"]:
		_setup_animation_pose_helpers("HEAD / NECK", {
			"Neutral": &"unarmed_idle",
			"Look Up": &"Pistol_Aim_Up",
			"Look Down": &"Pistol_Aim_Down",
			"Phone": &"Idle_TalkingPhone",
		})
	elif ("Leg" in bone_name or "Foot" in bone_name or "Toe" in bone_name
			or bone_name == "Hips"):
		_setup_animation_pose_helpers("LEGS / STANCE", {
			"Idle": &"unarmed_idle",
			"Crouch": &"unarmed_crouch_idle",
			"Jump": &"unarmed_jump",
			"Run": &"unarmed_sprint",
		})
	elif bone_name in ["Spine", "Spine1", "Spine2"]:
		_setup_animation_pose_helpers("BODY POSE", {
			"Idle": &"unarmed_idle",
			"Crouch": &"unarmed_crouch_idle",
			"Jump": &"unarmed_jump",
			"Run": &"unarmed_sprint",
		})
	else:
		pose_helpers.visible = false


func _setup_animation_pose_helpers(title: String, presets: Dictionary) -> void:
	pose_helpers.visible = true
	pose_helper_title.text = title
	for label: String in presets:
		var button := Button.new()
		button.custom_minimum_size = Vector2(92.0, 32.0)
		button.text = label
		button.pressed.connect(_apply_reference_pose.bind(presets[label]))
		pose_helper_controls.add_child(button)


func _apply_reference_pose(animation_name: StringName) -> void:
	_select_animation_in_ui(animation_name)
	_set_animation(animation_name)


func _setup_hand_pose_helper(side: String) -> void:
	if side.is_empty():
		pose_helpers.visible = false
		return
	pose_helpers.visible = true
	pose_helper_title.text = "%s HAND" % side.to_upper()
	_hand_helper_side = side
	_hand_helper_baseline.clear()
	for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		for joint in range(1, 4):
			var bone_name := StringName("%sHand%s%d" % [side, finger, joint])
			if body.skeleton.find_bone(bone_name) >= 0:
				_hand_helper_baseline[bone_name] = _modifier.get_bone_rotation(bone_name)
	var open_label := Label.new()
	open_label.text = "Open"
	pose_helper_controls.add_child(open_label)
	_hand_openness_slider = HSlider.new()
	_hand_openness_slider.custom_minimum_size = Vector2(300.0, 32.0)
	_hand_openness_slider.min_value = -1.0
	_hand_openness_slider.max_value = 1.0
	_hand_openness_slider.step = 0.01
	_hand_openness_slider.value = 0.0
	_hand_openness_slider.value_changed.connect(_on_hand_openness_changed)
	pose_helper_controls.add_child(_hand_openness_slider)
	var close_label := Label.new()
	close_label.text = "Close"
	pose_helper_controls.add_child(close_label)
	var center_button := Button.new()
	center_button.custom_minimum_size = Vector2(76.0, 32.0)
	center_button.text = "Center"
	center_button.pressed.connect(_center_hand_openness)
	pose_helper_controls.add_child(center_button)


func _center_hand_openness() -> void:
	if is_instance_valid(_hand_openness_slider):
		_hand_openness_slider.value = 0.0


func _on_hand_openness_changed(value: float) -> void:
	var open_amounts := [35.0, 25.0, 15.0]
	var close_amounts := [12.0, 18.0, 24.0]
	for finger in ["Index", "Middle", "Ring", "Pinky"]:
		for joint_index in 3:
			var bone_name := StringName("%sHand%s%d" % [
					_hand_helper_side, finger, joint_index + 1])
			if not _hand_helper_baseline.has(bone_name):
				continue
			var rotation: Vector3 = _hand_helper_baseline[bone_name]
			rotation.z += (close_amounts[joint_index] * value
					if value >= 0.0 else open_amounts[joint_index] * value)
			_modifier.set_bone_rotation(bone_name, rotation)
	var thumb_name := StringName("%sHandThumb1" % _hand_helper_side)
	if _hand_helper_baseline.has(thumb_name):
		var thumb_rotation: Vector3 = _hand_helper_baseline[thumb_name]
		thumb_rotation.z -= value * 10.0
		_modifier.set_bone_rotation(thumb_name, thumb_rotation)
	_sync_bone_controls()
	_refresh_skeleton()
	_update_bone_gizmo()


func _expand_section_for_bone(bone_name: StringName) -> void:
	var section_key := _get_bone_section(bone_name)
	while section_key != &"":
		_section_expanded[section_key] = true
		if _section_headers.has(section_key):
			(_section_headers[section_key] as Button).set_pressed_no_signal(true)
		section_key = _section_parents.get(section_key, &"")
	_refresh_bone_section_visibility()


func _update_selected_bone_ui() -> void:
	for bone_name: StringName in _bone_slider_controls:
		var controls: Dictionary = _bone_slider_controls[bone_name]
		var row := controls["row"] as PanelContainer
		var joint_label := controls["joint_label"] as Label
		if bone_name == _selected_bone:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(0.12, 0.42, 0.68, 0.55)
			selected_style.corner_radius_top_left = 3
			selected_style.corner_radius_top_right = 3
			selected_style.corner_radius_bottom_right = 3
			selected_style.corner_radius_bottom_left = 3
			row.add_theme_stylebox_override(&"panel", selected_style)
			joint_label.add_theme_color_override(&"font_color", Color(0.75, 0.9, 1.0))
		else:
			row.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
			joint_label.remove_theme_color_override(&"font_color")


func _set_bone_axis_from_gizmo(bone_name: StringName, axis: int, value: float) -> void:
	var rotation := _modifier.get_bone_rotation(bone_name)
	rotation[axis] = wrapf(value, -180.0, 180.0)
	_modifier.set_bone_rotation(bone_name, rotation)
	var controls: Dictionary = _bone_slider_controls.get(bone_name, {})
	if not controls.is_empty():
		var sliders: Array = controls["sliders"]
		var labels: Array = controls["labels"]
		(sliders[axis] as HSlider).set_value_no_signal(rotation[axis])
		(labels[axis] as Label).text = "%s  %+.0f" % ["XYZ"[axis], rotation[axis]]
	_refresh_skeleton()
	_update_bone_gizmo()


func _on_show_bones_toggled(enabled: bool) -> void:
	_bone_debug_root.visible = enabled
	if enabled:
		_update_bone_gizmo()


func _on_axis_ring_toggled(_enabled: bool, axis: int) -> void:
	if _drag_axis == axis and not axis_ring_toggles[axis].button_pressed:
		_drag_axis = -1
	_update_bone_gizmo()


func _rebuild_bone_gizmo() -> void:
	if _bone_debug_root == null:
		return
	for instance: MeshInstance3D in _joint_instances.values():
		instance.queue_free()
	for instance: MeshInstance3D in _bone_segments.values():
		instance.queue_free()
	_joint_instances.clear()
	_bone_segments.clear()
	_visible_bone_indices.clear()
	var visible_set := {}
	for bone_index in body.skeleton.get_bone_count():
		_visible_bone_indices.append(bone_index)
		visible_set[bone_index] = true
	for bone_index in _visible_bone_indices:
		var joint := _make_debug_mesh_instance(_joint_mesh, _joint_material)
		joint.name = StringName("Joint_%s" % body.skeleton.get_bone_name(bone_index))
		_joint_instances[bone_index] = joint
		_bone_debug_root.add_child(joint)
		var parent_index := body.skeleton.get_bone_parent(bone_index)
		if visible_set.has(parent_index):
			var segment := _make_debug_mesh_instance(
					_bone_segment_mesh, _bone_segment_material)
			segment.name = StringName("Bone_%s" % body.skeleton.get_bone_name(bone_index))
			_bone_segments[bone_index] = segment
			_bone_debug_root.add_child(segment)
	_update_bone_gizmo()


func _update_bone_gizmo() -> void:
	if _bone_debug_root == null or not show_bones_toggle.button_pressed:
		return
	var selected_index := body.skeleton.find_bone(_selected_bone)
	for bone_index in _visible_bone_indices:
		var pose := body.skeleton.get_bone_global_pose(bone_index)
		var joint: MeshInstance3D = _joint_instances[bone_index]
		joint.position = pose.origin
		var selected := bone_index == selected_index
		joint.material_override = _selected_joint_material if selected else _joint_material
		var radius_scale := SELECTED_JOINT_RADIUS / JOINT_RADIUS if selected else 1.0
		joint.scale = Vector3.ONE * radius_scale
		if _bone_segments.has(bone_index):
			var parent_index := body.skeleton.get_bone_parent(bone_index)
			var parent_position := body.skeleton.get_bone_global_pose(parent_index).origin
			var offset := pose.origin - parent_position
			var segment: MeshInstance3D = _bone_segments[bone_index]
			segment.position = parent_position + offset * 0.5
			if offset.length_squared() > 0.000001:
				segment.basis = Basis(Quaternion(Vector3.UP, offset.normalized())).scaled_local(
						Vector3(1.0, offset.length(), 1.0))
	_update_rotation_rings(selected_index)


func _update_rotation_rings(selected_index: int) -> void:
	var rings_visible := selected_index >= 0 and selected_index in _visible_bone_indices
	for axis in 3:
		_rotation_rings[axis].visible = (
				rings_visible and axis_ring_toggles[axis].button_pressed)
	if not rings_visible:
		return
	var pose := body.skeleton.get_bone_global_pose(selected_index)
	var bone_basis := pose.basis.orthonormalized()
	var axis_rotations := [
		Basis.from_euler(Vector3(0.0, 0.0, -PI * 0.5)),
		Basis.IDENTITY,
		Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)),
	]
	for axis in 3:
		_rotation_rings[axis].position = pose.origin
		_rotation_rings[axis].basis = bone_basis * axis_rotations[axis]


func _on_object_position_changed(value: float, axis: int) -> void:
	if _syncing_controls:
		return
	var position := _held_object.position
	position[axis] = value
	_held_object.position = position
	position_values[axis].text = "%+.3f" % value
	_refresh_skeleton()


func _on_object_rotation_changed(value: float, axis: int) -> void:
	if _syncing_controls:
		return
	var rotation := _held_object.rotation_degrees
	rotation[axis] = value
	_held_object.rotation_degrees = rotation
	rotation_values[axis].text = "%+.1f" % value
	_refresh_skeleton()


func _on_object_scale_changed(value: float) -> void:
	if _syncing_controls:
		return
	_held_object.scale = Vector3.ONE * value
	scale_value.text = "%.3f" % value


func _refresh_skeleton() -> void:
	# The preview animation is deliberately paused. Explicitly advance the
	# modifier stack so UI edits update the skinned mesh immediately.
	body.skeleton.advance(0.0)


func _sync_object_controls() -> void:
	_syncing_controls = true
	for axis in 3:
		position_sliders[axis].value = _held_object.position[axis]
		position_values[axis].text = "%+.3f" % _held_object.position[axis]
		rotation_sliders[axis].value = _held_object.rotation_degrees[axis]
		rotation_values[axis].text = "%+.1f" % _held_object.rotation_degrees[axis]
	scale_slider.value = _held_object.scale.x
	scale_value.text = "%.3f" % _held_object.scale.x
	object_path_field.text = _current_object_path
	preset_path_field.text = _current_pose_path
	_syncing_controls = false


func _sync_bone_controls() -> void:
	for bone_name: StringName in _bone_slider_controls:
		var controls: Dictionary = _bone_slider_controls[bone_name]
		var sliders: Array = controls["sliders"]
		var labels: Array = controls["labels"]
		var rotation := _modifier.get_bone_rotation(bone_name)
		for axis in 3:
			(sliders[axis] as HSlider).set_value_no_signal(rotation[axis])
			(labels[axis] as Label).text = "%s  %+.0f" % ["XYZ"[axis], rotation[axis]]


func _on_reset_bone_pressed() -> void:
	_modifier.reset_bone(_selected_bone)
	_sync_bone_controls()
	_refresh_skeleton()
	status_label.text = "Selected bone reset"


func _on_reset_all_pressed() -> void:
	_modifier.reset_all()
	_held_object.position = Vector3.ZERO
	_held_object.rotation = Vector3.ZERO
	_held_object.scale = Vector3.ONE
	_sync_bone_controls()
	_sync_object_controls()
	_refresh_skeleton()
	status_label.text = "All values reset"


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(JSON.stringify(_get_pose_data(), "  "))
	status_label.text = "Values copied to clipboard"


func _get_pose_data() -> Dictionary:
	return {
		"format_version": 2,
		"animation": String(_current_animation),
		"object_scene": _current_object_path,
		"attachment_bone": String(_attachment_bone),
		"bone_rotations_degrees": _modifier.get_serializable_values(),
		"object_position": _vector3_to_array(_held_object.position),
		"object_rotation_degrees": _vector3_to_array(_held_object.rotation_degrees),
		"object_scale": _held_object.scale.x,
		# Compatibility fields used by PlayerBody's flashlight loader.
		"hand": String(_attachment_bone),
		"flashlight_position": [
			_held_object.position.x,
			_held_object.position.y,
			_held_object.position.z,
		],
		"flashlight_rotation_degrees": [
			_held_object.rotation_degrees.x,
			_held_object.rotation_degrees.y,
			_held_object.rotation_degrees.z,
		],
	}


func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _on_save_pose_pressed() -> void:
	if _current_pose_path.is_empty():
		_on_save_preset_as_pressed()
		return
	_save_pose_to_path(_current_pose_path)


func _save_pose_to_path(path: String) -> bool:
	if path.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_label.text = "Could not save pose: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(_get_pose_data(), "  ") + "\n")
	_current_pose_path = path
	preset_path_field.text = path
	status_label.text = "Pose saved to %s" % path.get_file()
	return true


func _on_load_pose_pressed() -> void:
	if _current_pose_path.is_empty():
		status_label.text = "This pose has not been saved yet"
		return
	_load_pose_from_path(_current_pose_path, true)


func _on_new_preset_pressed() -> void:
	_modifier.reset_all()
	_held_object.position = Vector3.ZERO
	_held_object.rotation = Vector3.ZERO
	_held_object.scale = Vector3.ONE
	_current_pose_path = ""
	_sync_bone_controls()
	_sync_object_controls()
	preset_path_field.text = "(unsaved pose)"
	_refresh_skeleton()
	status_label.text = "New pose; choose Save or Save As when ready"


func _on_browse_object_pressed() -> void:
	object_dialog.current_path = _current_object_path
	object_dialog.popup_centered_ratio(0.82)


func _on_object_file_selected(path: String) -> void:
	if _load_object(path, true):
		_sync_object_controls()
		status_label.text = "Loaded object %s" % _current_object_path.get_file()


func _on_open_preset_pressed() -> void:
	open_preset_dialog.current_path = _globalize_if_resource(_current_pose_path)
	open_preset_dialog.popup_centered_ratio(0.82)


func _on_save_preset_as_pressed() -> void:
	save_preset_dialog.current_path = _globalize_if_resource(_current_pose_path)
	save_preset_dialog.popup_centered_ratio(0.82)


func _on_preset_file_selected(path: String) -> void:
	_load_pose_from_path(_localize_resource_path(path), true)


func _on_save_preset_file_selected(path: String) -> void:
	_save_pose_to_path(_localize_resource_path(path))


func _globalize_if_resource(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _load_pose_from_path(path: String, update_ui: bool) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if update_ui:
			status_label.text = "Could not load pose: %s" % error_string(
					FileAccess.get_open_error())
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		if update_ui:
			status_label.text = "Pose file is not valid JSON"
		return false
	var data := parsed as Dictionary
	var object_scene := String(data.get("object_scene", _current_object_path))
	if not object_scene.is_empty() and object_scene != _current_object_path:
		if not _load_object(object_scene, true):
			return false
	var attachment_name := StringName(data.get(
			"attachment_bone", data.get("hand", String(DEFAULT_ATTACHMENT_BONE))))
	_set_attachment_bone(attachment_name, false)
	_select_attachment_in_ui(_attachment_bone)
	var animation_name := StringName(data.get("animation", String(DEFAULT_ANIMATION)))
	_select_animation_in_ui(animation_name)
	_set_animation(animation_name)
	_modifier.reset_all()
	var rotations: Dictionary = data.get("bone_rotations_degrees", {})
	for bone_name: String in rotations:
		var values: Array = rotations[bone_name]
		if values.size() >= 3 and body.skeleton.find_bone(StringName(bone_name)) >= 0:
			_modifier.set_bone_rotation(StringName(bone_name), Vector3(
					float(values[0]), float(values[1]), float(values[2])))
	var position_values_data: Array = data.get(
			"object_position", data.get("flashlight_position", []))
	if position_values_data.size() >= 3:
		_held_object.position = Vector3(
				float(position_values_data[0]),
				float(position_values_data[1]),
				float(position_values_data[2]))
	var rotation_values_data: Array = data.get(
			"object_rotation_degrees", data.get("flashlight_rotation_degrees", []))
	if rotation_values_data.size() >= 3:
		_held_object.rotation_degrees = Vector3(
				float(rotation_values_data[0]),
				float(rotation_values_data[1]),
				float(rotation_values_data[2]))
	var object_scale := float(data.get("object_scale", _held_object.scale.x))
	_held_object.scale = Vector3.ONE * object_scale
	_current_pose_path = path
	if update_ui:
		_sync_bone_controls()
		_sync_object_controls()
		_refresh_skeleton()
		_update_bone_gizmo()
		status_label.text = "Pose loaded from %s" % path.get_file()
	return true


func _on_save_image_pressed() -> void:
	var directory := ProjectSettings.globalize_path("user://pose_captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := directory.path_join("character_pose_%s.png" % timestamp)
	await _capture_pose_image(path, false)
	status_label.text = "Image saved: %s" % path


func _capture_pose_image(path: String, include_ui: bool) -> Error:
	var global_path := ProjectSettings.globalize_path(path)
	var ui_was_visible := ui_layer.visible
	if not include_ui:
		ui_layer.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(global_path)
	ui_layer.visible = ui_was_visible
	return result


func _run_automation_args() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if "=" in argument:
			options[argument.get_slice("=", 0)] = argument.get_slice("=", 1)
	if options.has("pose"):
		_load_pose_from_path(options["pose"], true)
	if options.has("animation"):
		var animation_name := StringName(options["animation"])
		_select_animation_in_ui(animation_name)
		_set_animation(animation_name)
	if options.has("object"):
		_load_object(options["object"], true)
	if options.has("attachment"):
		_set_attachment_bone(StringName(options["attachment"]), false)
		_select_attachment_in_ui(_attachment_bone)
	var position_option: String = options.get(
			"object_position", options.get("flashlight_position", ""))
	if not position_option.is_empty():
		_held_object.position = _parse_vector3_option(
				position_option, _held_object.position)
	var rotation_option: String = options.get(
			"object_rotation", options.get("flashlight_rotation", ""))
	if not rotation_option.is_empty():
		_held_object.rotation_degrees = _parse_vector3_option(
				rotation_option, _held_object.rotation_degrees)
	if options.has("object_scale"):
		var object_scale := float(options["object_scale"])
		_held_object.scale = Vector3.ONE * object_scale
	if options.has("bones"):
		for bone_override: String in String(options["bones"]).split(";"):
			var separator := bone_override.find(":")
			if separator <= 0:
				continue
			var bone_name := StringName(bone_override.left(separator))
			if body.skeleton.find_bone(bone_name) >= 0:
				_modifier.set_bone_rotation(bone_name, _parse_vector3_option(
						bone_override.substr(separator + 1),
						_modifier.get_bone_rotation(bone_name)))
	_sync_bone_controls()
	_sync_object_controls()
	_refresh_skeleton()
	if options.has("view"):
		var view_index: int = {"full": 0, "hand": 1, "isolated": 2}.get(
				options["view"], 0)
		view_picker.select(view_index)
		_on_view_selected(view_index)
	if options.get("comparison", "false") == "true":
		_on_editor_mode_pressed(true)
	if options.has("panel_size"):
		var panel_size_components := String(options["panel_size"]).split(",")
		if panel_size_components.size() >= 2:
			_panel_user_layout = true
			panel.size = Vector2(
					float(panel_size_components[0]), float(panel_size_components[1]))
			_expanded_panel_size = panel.size
			_clamp_panel_to_viewport(get_viewport().get_visible_rect().size / _ui_scale)
			_update_panel_dependent_layout()
			_update_panel_resize_handle()
	if options.get("panel_collapsed", "false") == "true" and not _panel_collapsed:
		_on_collapse_panel_pressed()
	if options.has("time"):
		var preview_time := float(options["time"])
		body.anim_player.seek(preview_time, true)
		_comparison.seek(preview_time)
		body.anim_player.pause()
		_comparison.set_paused(true)
		pause_toggle.set_pressed_no_signal(true)
		_refresh_skeleton()
	if options.has("bone"):
		var bone_name := StringName(options["bone"])
		if body.skeleton.find_bone(bone_name) >= 0:
			_select_bone(bone_name, true)
	if options.has("pick"):
		var pick_components := String(options["pick"]).split(",")
		if pick_components.size() >= 2:
			for _frame in 2:
				await get_tree().process_frame
			var pick_position := Vector2(
					float(pick_components[0]), float(pick_components[1]))
			var previous_bone := _selected_bone
			var pick_event := InputEventMouseButton.new()
			pick_event.position = pick_position
			pick_event.button_index = MOUSE_BUTTON_LEFT
			pick_event.pressed = true
			pick_event.double_click = true
			_input(pick_event)
			if _selected_bone != previous_bone:
				print("CHARACTER_EDITOR_PICKED:", _selected_bone)
	if options.has("hand_openness") and not _hand_helper_side.is_empty():
		var openness := clampf(float(options["hand_openness"]), -1.0, 1.0)
		if is_instance_valid(_hand_openness_slider):
			_hand_openness_slider.set_value_no_signal(openness)
		_on_hand_openness_changed(openness)
	if options.has("angle") and _joint_focus_active:
		var distance := _focused_camera_offset.length()
		match options["angle"]:
			"right":
				_focused_camera_offset = Vector3.RIGHT * distance
			"left":
				_focused_camera_offset = Vector3.LEFT * distance
			"top":
				_focused_camera_offset = Vector3(0.0, 0.85, 0.5).normalized() * distance
			"bottom":
				_focused_camera_offset = Vector3(0.0, -0.85, 0.5).normalized() * distance
			"back":
				_focused_camera_offset = Vector3(0.0, 0.0, -distance)
			_:
				_focused_camera_offset = Vector3(0.0, 0.0, distance)
		_update_focused_camera()
	if options.has("capture"):
		for _frame in 3:
			await get_tree().process_frame
		var result := await _capture_pose_image(options["capture"],
				options.get("capture_ui", "false") == "true")
		if result != OK:
			push_error("Pose capture failed: %s" % error_string(result))
		get_tree().quit()
	elif options.has("dump_bones"):
		for _frame in 3:
			await get_tree().process_frame
		_dump_bone_poses(String(options["dump_bones"]))
		get_tree().quit()


func _build_bone_pose_dump(name_filter: String) -> Dictionary:
	var poses := {}
	for bone_index in body.skeleton.get_bone_count():
		var bone_name := body.skeleton.get_bone_name(bone_index)
		if not name_filter.is_empty() and name_filter not in String(bone_name):
			continue
		var pose := body.skeleton.get_bone_pose(bone_index)
		var global_pose := body.skeleton.get_bone_global_pose(bone_index)
		poses[String(bone_name)] = {
			"parent": body.skeleton.get_bone_parent(bone_index),
			"local_rotation_degrees": _basis_euler_degrees(pose.basis),
			"global_rotation_degrees": _basis_euler_degrees(global_pose.basis),
			"global_origin": [global_pose.origin.x, global_pose.origin.y, global_pose.origin.z],
		}
	return poses


func _dump_bone_poses(name_filter: String) -> void:
	print("POSE_DUMP:", JSON.stringify(_build_bone_pose_dump(name_filter)))


func _on_mcp_debugger_message(message: String, data: Array) -> bool:
	# EngineDebugger.register_message_capture("mcp", ...) strips the "mcp:"
	# prefix before invoking this callback, so the message here is e.g.
	# "request_pose_dump", not "mcp:request_pose_dump" - unlike
	# EditorDebuggerPlugin._capture() on the editor side, which keeps the
	# full prefixed string.
	match message:
		"request_pose_dump":
			var name_filter := String(data[0]) if data.size() > 0 else ""
			var poses := _build_bone_pose_dump(name_filter)
			EngineDebugger.send_message("mcp:pose_dump", [JSON.stringify(poses)])
			return true
		"set_bone_rotation":
			_mcp_set_bone_rotation(data)
			return true
		"set_object_transform":
			_mcp_set_object_transform(data)
			return true
		"capture_screenshot":
			var include_ui: bool = bool(data[1]) if data.size() > 1 else false
			_mcp_capture_screenshot(String(data[0]), include_ui)
			return true
		"set_view":
			_mcp_set_view(String(data[0]))
			return true
		"select_bone":
			_mcp_select_bone(String(data[0]))
			return true
		"set_camera_angle":
			_mcp_set_camera_angle(String(data[0]))
			return true
		"load_pose":
			_mcp_load_pose(String(data[0]))
			return true
		"save_pose":
			_mcp_save_pose(String(data[0]))
			return true
		"set_animation":
			_mcp_set_animation(String(data[0]))
			return true
		"set_hand_openness":
			_mcp_set_hand_openness(float(data[0]))
			return true
		"pick_bone":
			_mcp_pick_bone(float(data[0]), float(data[1]))
			return true
	return false


func _mcp_load_pose(path: String) -> void:
	if not _load_pose_from_path(path, true):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Could not load pose from %s" % path})])
		return
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Pose loaded from %s" % path})])


func _mcp_save_pose(path: String) -> void:
	if not _save_pose_to_path(path):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Could not save pose to %s" % path})])
		return
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Pose saved to %s" % path})])


func _mcp_set_animation(animation_name: String) -> void:
	var name := StringName(animation_name)
	_select_animation_in_ui(name)
	_set_animation(name)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Animation set to %s" % animation_name})])


func _mcp_set_hand_openness(value: float) -> void:
	if _hand_helper_side.is_empty():
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "No hand is currently focused - select a hand-side bone first"})])
		return
	var openness := clampf(value, -1.0, 1.0)
	if is_instance_valid(_hand_openness_slider):
		_hand_openness_slider.set_value_no_signal(openness)
	_on_hand_openness_changed(openness)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Hand openness set to %s" % openness})])


func _mcp_pick_bone(screen_x: float, screen_y: float) -> void:
	# Deliberately not awaited from _on_mcp_debugger_message - same reasoning
	# as _mcp_capture_screenshot: fire-and-forget so the message-capture
	# dispatch always gets an immediate bool back.
	for _frame in 2:
		await get_tree().process_frame
	var previous_bone := _selected_bone
	var pick_event := InputEventMouseButton.new()
	pick_event.position = Vector2(screen_x, screen_y)
	pick_event.button_index = MOUSE_BUTTON_LEFT
	pick_event.pressed = true
	pick_event.double_click = true
	_input(pick_event)
	if _selected_bone != previous_bone:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": true, "result": "Picked bone %s" % _selected_bone})])
	else:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": true, "result": "No bone was picked at that position (selection unchanged)"})])


func _mcp_set_view(view_name: String) -> void:
	var view_index: int = {"full": 0, "hand": 1, "isolated": 2}.get(view_name, -1)
	if view_index < 0:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown view '%s' (expected full/hand/isolated)" % view_name})])
		return
	view_picker.select(view_index)
	_on_view_selected(view_index)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "View set to %s" % view_name})])


func _mcp_select_bone(bone_name: String) -> void:
	if body.skeleton.find_bone(StringName(bone_name)) < 0:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown bone %s" % bone_name})])
		return
	_select_bone(StringName(bone_name), true)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Selected bone %s" % bone_name})])


func _mcp_set_camera_angle(angle_name: String) -> void:
	if not _joint_focus_active:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "No bone is focused - call select_bone first"})])
		return
	var distance := _focused_camera_offset.length()
	match angle_name:
		"right":
			_focused_camera_offset = Vector3.RIGHT * distance
		"left":
			_focused_camera_offset = Vector3.LEFT * distance
		"top":
			_focused_camera_offset = Vector3(0.0, 0.85, 0.5).normalized() * distance
		"bottom":
			_focused_camera_offset = Vector3(0.0, -0.85, 0.5).normalized() * distance
		"back":
			_focused_camera_offset = Vector3(0.0, 0.0, -distance)
		_:
			_focused_camera_offset = Vector3(0.0, 0.0, distance)
	_update_focused_camera()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Camera angle set to %s" % angle_name})])


func _mcp_set_bone_rotation(data: Array) -> void:
	var bone_name := StringName(data[0])
	if body.skeleton.find_bone(bone_name) < 0:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown bone %s" % bone_name})])
		return
	var rotation := Vector3(float(data[1]), float(data[2]), float(data[3]))
	# Same call the UI's per-axis sliders make (_on_bone_slider_changed) -
	# additive on top of the current animation pose, not a replacement.
	_modifier.set_bone_rotation(bone_name, rotation)
	_refresh_skeleton()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "%s rotation set to %s" % [bone_name, rotation]})])


func _mcp_set_object_transform(data: Array) -> void:
	var payload = JSON.parse_string(String(data[0]))
	if typeof(payload) != TYPE_DICTIONARY:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Malformed set_object_transform payload"})])
		return
	# Same fields the UI's position/rotation/scale sliders write
	# (_on_object_position_changed etc.) - relative to the attachment bone.
	if payload.get("position") != null:
		var p: Array = payload["position"]
		_held_object.position = Vector3(p[0], p[1], p[2])
	if payload.get("rotation") != null:
		var r: Array = payload["rotation"]
		_held_object.rotation_degrees = Vector3(r[0], r[1], r[2])
	if payload.get("scale") != null:
		_held_object.scale = Vector3.ONE * float(payload["scale"])
	_refresh_skeleton()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Object transform updated"})])


func _mcp_capture_screenshot(path: String, include_ui: bool) -> void:
	# Deliberately not awaited from _on_mcp_debugger_message - it's
	# uncertain whether EngineDebugger's message-capture dispatch correctly
	# handles a callback that returns a suspended coroutine instead of an
	# immediate bool, so this runs fire-and-forget instead and reports its
	# own result asynchronously once the capture actually completes.
	var result := await _capture_pose_image(path, include_ui)
	if result != OK:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Capture failed: %s" % error_string(result)})])
	else:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": true, "result": "Captured to %s" % path})])


func _basis_euler_degrees(basis: Basis) -> Array[float]:
	var euler := basis.get_euler()
	return [rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)]


func _parse_vector3_option(value: String, fallback: Vector3) -> Vector3:
	var components := value.split(",")
	if components.size() < 3:
		return fallback
	return Vector3(float(components[0]), float(components[1]), float(components[2]))


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button_event := event as InputEventMouseButton
	if (not button_event.pressed
			or button_event.button_index != MOUSE_BUTTON_LEFT
			or _captured
			or _is_pointer_over_tuner_ui(button_event.position)):
		return
	if show_bones_toggle.button_pressed and _begin_ring_drag(button_event.position):
		get_viewport().set_input_as_handled()
	elif button_event.double_click and _select_character_bone_at(button_event.position):
		get_viewport().set_input_as_handled()


func _is_pointer_over_tuner_ui(screen_position: Vector2) -> bool:
	var logical_position := screen_position / _ui_scale
	return (Rect2(panel.position, panel.size).has_point(logical_position)
			or Rect2(viewport_toolbar.position, viewport_toolbar.size).has_point(
					logical_position)
			or (panel_resize_handle.visible
				and Rect2(panel_resize_handle.position, panel_resize_handle.size).has_point(
						logical_position)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_drag_axis = -1
		_orbiting = false
		_orbiting_joint = false
		_moving_camera = false
		_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif (event is InputEventMagnifyGesture
			and not free_camera_toggle.button_pressed
			and (view_picker.selected == 0 or _joint_focus_active)):
		_apply_camera_zoom(1.0 / maxf(event.factor, 0.01))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if (button_event.pressed
				and button_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
				and not free_camera_toggle.button_pressed
				and (view_picker.selected == 0 or _joint_focus_active)):
			var zoom_factor := ZOOM_STEP if button_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
			_apply_camera_zoom(zoom_factor)
			get_viewport().set_input_as_handled()
			return
		if button_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not button_event.pressed and _drag_axis >= 0:
			_drag_axis = -1
			status_label.text = "%s rotation set" % _display_bone_name(_selected_bone)
			get_viewport().set_input_as_handled()
		elif not button_event.pressed and _orbiting:
			_orbiting = false
			_orbiting_joint = false
			get_viewport().set_input_as_handled()
		elif not button_event.pressed and _moving_camera:
			_moving_camera = false
			get_viewport().set_input_as_handled()
		elif button_event.pressed and not _captured:
			if show_bones_toggle.button_pressed and _begin_ring_drag(button_event.position):
				get_viewport().set_input_as_handled()
			elif free_camera_toggle.button_pressed:
				_captured = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif _camera_mode == CAMERA_MODE_MOVE:
				_begin_camera_move()
			elif _joint_focus_active:
				_begin_focused_joint_orbit()
			else:
				_orbiting = true
				_orbiting_joint = false
				status_label.text = "Drag to orbit; use the wheel to zoom"
	elif event is InputEventMouseMotion and _drag_axis >= 0:
		_drag_rotation_ring((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * ORBIT_SENS
		_orbit_pitch = clampf(
				_orbit_pitch + motion.relative.y * ORBIT_SENS,
				-deg_to_rad(80.0), deg_to_rad(80.0))
		if _orbiting_joint:
			_focused_camera_offset = _get_orbit_direction() * _orbit_distance
			_update_focused_camera()
		else:
			_update_orbit_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _moving_camera:
		_move_camera_from_drag((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _captured:
		_yaw -= event.relative.x * LOOK_SENS
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENS,
				-deg_to_rad(89.0), deg_to_rad(89.0))
		camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _select_character_bone_at(mouse_position: Vector2) -> bool:
	var closest_index := -1
	var closest_distance := CHARACTER_PICK_RADIUS_PIXELS
	for bone_index in _visible_bone_indices:
		var world_position := body.skeleton.to_global(
				body.skeleton.get_bone_global_pose(bone_index).origin)
		if camera.is_position_behind(world_position):
			continue
		var distance := camera.unproject_position(world_position).distance_to(mouse_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = bone_index
		var parent_index := body.skeleton.get_bone_parent(bone_index)
		if parent_index < 0 or parent_index not in _visible_bone_indices:
			continue
		var parent_world_position := body.skeleton.to_global(
				body.skeleton.get_bone_global_pose(parent_index).origin)
		if camera.is_position_behind(parent_world_position):
			continue
		var segment_distance := _screen_point_segment_distance(
				mouse_position,
				camera.unproject_position(parent_world_position),
				camera.unproject_position(world_position))
		if segment_distance < closest_distance:
			closest_distance = segment_distance
			closest_index = bone_index
	if closest_index < 0:
		return false
	_select_bone(body.skeleton.get_bone_name(closest_index), true)
	status_label.text = "%s selected; drag an X, Y, or Z ring" % _display_bone_name(
			_selected_bone)
	return true


func _screen_point_segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)


func _begin_camera_move() -> void:
	_moving_camera = true
	_joint_focus_active = false
	_orbiting = false
	_orbiting_joint = false
	camera.h_offset = 0.0
	_orbit_target = camera.global_position - camera.global_basis.z * _orbit_distance
	var orbit_offset := camera.global_position - _orbit_target
	_orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
	_orbit_pitch = asin(clampf(
			orbit_offset.y / maxf(_orbit_distance, 0.001), -1.0, 1.0))
	status_label.text = "Moving camera; drag and use +/- to zoom"


func _move_camera_from_drag(relative: Vector2) -> void:
	var scale_factor := maxf(_orbit_distance, MIN_ORBIT_DISTANCE) * 0.0015
	var offset := (camera.global_basis.x * -relative.x
			+ camera.global_basis.y * relative.y) * scale_factor
	camera.global_position += offset
	_orbit_target += offset


func _begin_ring_drag(mouse_position: Vector2) -> bool:
	var selected_index := body.skeleton.find_bone(_selected_bone)
	if selected_index < 0 or selected_index not in _visible_bone_indices:
		return false
	var pose := body.skeleton.get_bone_global_pose(selected_index)
	var center := body.skeleton.to_global(pose.origin)
	var bone_basis := pose.basis.orthonormalized()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var best_axis := -1
	var best_error := RING_PICK_TOLERANCE
	var best_hit := Vector3.ZERO
	var best_normal := Vector3.ZERO
	for axis in 3:
		if not axis_ring_toggles[axis].button_pressed:
			continue
		var local_axis: Vector3 = bone_basis[axis]
		var world_axis := (body.skeleton.global_basis * local_axis).normalized()
		var hit = Plane(world_axis, center).intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var hit_position: Vector3 = hit
		var radius_error := absf(hit_position.distance_to(center) - ROTATION_RING_RADIUS)
		if radius_error < best_error:
			best_error = radius_error
			best_axis = axis
			best_hit = hit_position
			best_normal = world_axis
	if best_axis < 0:
		return false
	_drag_axis = best_axis
	_drag_center = center
	_drag_plane_normal = best_normal
	_drag_start_vector = (best_hit - center).normalized()
	_drag_start_rotation = _modifier.get_bone_rotation(_selected_bone)
	status_label.text = "Dragging %s %s axis" % [
		_display_bone_name(_selected_bone), "XYZ"[_drag_axis]]
	return true


func _drag_rotation_ring(mouse_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var hit = Plane(_drag_plane_normal, _drag_center).intersects_ray(
			ray_origin, ray_direction)
	if hit == null:
		return
	var current_vector := ((hit as Vector3) - _drag_center).normalized()
	if current_vector.is_zero_approx():
		return
	var angle_delta := _drag_start_vector.signed_angle_to(
			current_vector, _drag_plane_normal)
	_set_bone_axis_from_gizmo(_selected_bone, _drag_axis,
			_drag_start_rotation[_drag_axis] + rad_to_deg(angle_delta))


func _process(delta: float) -> void:
	if not free_camera_toggle.button_pressed:
		if _joint_focus_active:
			_update_focused_camera()
		return
	if not _captured:
		return
	var input := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical := Input.get_axis(&"crouch", &"jump")
	var speed := MOVE_SPEED * (3.0 if Input.is_action_pressed(&"sprint") else 1.0)
	var direction := (camera.global_basis * Vector3(input.x, vertical, input.y)).normalized()
	camera.global_position += direction * speed * delta
