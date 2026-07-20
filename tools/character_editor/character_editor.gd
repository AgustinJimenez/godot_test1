class_name CharacterEditor
extends Node3D
## General held-object contact-pose calibration. Bone corrections are additive
## to the selected animation so presets remain reusable by gameplay systems.

const GRIP_MODIFIER := preload("res://actors/player/player_hand_grip_modifier.gd")
const RAW_COMPARISON := preload("res://tools/character_editor/raw_animation_comparison.gd")
const RIG_HANDLER := preload("res://tools/character_editor/character_editor_rig_handler.gd")
const MAPPED_HUMANOID_ADAPTER := preload(
		"res://tools/character_editor/mapped_humanoid_adapter.gd")
const DEFAULT_OBJECT_PATH := "res://assets/models/flashlight/flashlight.glb"
const DEFAULT_POSE_PRESET_PATH := "res://actors/player/flashlight_grip_pose.json"
const DEFAULT_ATTACHMENT_BONE := &"RightHand"
const DEFAULT_ANIMATION := &"unarmed_torch_idle"
const CHARACTER_SPAWN_POSITION := Vector3(0, 0.1, 0)
const CHARACTER_KINDS: PackedStringArray = [
	"player", "shambler", "brute", "y_bot", "x_bot", "vanguard",
	"parasite", "copzombie", "zombiegirl", "ch08", "ch10", "ch15", "zombie1",
]
const DEFAULT_CHARACTER_KIND := "player"
## Every non-"player" kind maps to a bare Mixamo FBX + display name, loaded
## through MixamoCharacterAdapter - see that file for why this works without
## per-character adapter code. Ch15_nonPBR belongs here too, despite living
## alongside Ch08/10 in the same download batch: inspection showed it
## actually uses the plain "mixamorig_" prefix, not a numbered one.
const MIXAMO_CHARACTERS := {
	"shambler": ["res://assets/models/action_adventure_pack/The Boss.fbx", "Shambler"],
	"brute": ["res://assets/models/mixamo_characters/Brute.fbx", "Brute"],
	"y_bot": ["res://assets/models/mixamo_characters/Y Bot.fbx", "Y Bot"],
	"x_bot": ["res://assets/models/mixamo_characters/X Bot.fbx", "X Bot"],
	"vanguard": ["res://assets/models/mixamo_characters/Vanguard By T. Choonyung.fbx", "Vanguard"],
	"parasite": ["res://assets/models/mixamo_characters/Parasite L Starkie.fbx", "Parasite"],
	"copzombie": ["res://assets/models/mixamo_characters/copzombie_l_actisdato.fbx", "Cop Zombie"],
	"zombiegirl": ["res://assets/models/mixamo_characters/Zombiegirl W Kurniawan.fbx", "Zombie Girl"],
	"ch15": ["res://assets/models/mixamo_characters/Ch15_nonPBR.fbx", "Ch15"],
}
## Ch08/Ch10 use a numbered rig prefix ("mixamorig7_"/"mixamorig5_" -
## Mixamo increments this per download to avoid bone-name collisions, and
## the two ended up with different numbers despite being downloaded
## together) instead of the plain "mixamorig_" MIXAMO_CHARACTERS share, so
## they can't reuse action_adventure_pack's clips directly -
## RetargetedMixamoAdapter bakes a small clip library from Human Basic
## Motions FREE onto each one instead. Value is [model_path, display_name,
## bone_prefix].
const RETARGETED_MIXAMO_CHARACTERS := {
	"ch08": ["res://assets/models/mixamo_characters/Ch08_nonPBR.fbx", "Ch08", "mixamorig7_"],
	"ch10": ["res://assets/models/mixamo_characters/Ch10_nonPBR.fbx", "Ch10", "mixamorig5_"],
}
const DEFAULT_OBJECT_SCALE := 0.12
const DEFAULT_OBJECT_POSITION := Vector3(-0.09, -0.03, -0.01)
const DEFAULT_OBJECT_ROTATION := Vector3(-95.0, -180.0, 1.0)
const MOVE_SPEED := 1.0
const LOOK_SENS := 0.003
const ORBIT_SENS := 0.006
const MIN_ORBIT_DISTANCE := 0.45
const MAX_ORBIT_DISTANCE := 5.0
const ZOOM_STEP := 0.88
const JOINT_RADIUS := 0.015
const SELECTED_JOINT_RADIUS := 0.021
const BONE_RADIUS := 0.006
const ROTATION_RING_RADIUS := 0.085
const ROTATION_RING_THICKNESS := 0.0035
const RING_PICK_TOLERANCE := 0.018
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

## Not @onready - built dynamically by _load_character() so the tool can
## switch between characters at runtime. See character_adapter.gd.
var body: CharacterAdapter
@onready var target_compare_label: Label3D = $CompareLabel
@onready var raw_source_ual1: Node3D = $RawSourceUAL1
@onready var raw_source_ual2: Node3D = $RawSourceUAL2
@onready var camera: Camera3D = $Camera
@onready var ui_layer: CanvasLayer = $UI
@onready var panel: Panel = $UI/Panel
@onready var viewport_toolbar: PanelContainer = $UI/ViewportToolbar
@onready var playback_toolbar: PanelContainer = $UI/PlaybackToolbar
@onready var playback_button: Button = $UI/PlaybackToolbar/Margin/Controls/PlayPause
@onready var playback_slider: HSlider = $UI/PlaybackToolbar/Margin/Controls/Timeline
@onready var playback_time_label: Label = $UI/PlaybackToolbar/Margin/Controls/Time
@onready var inspection_floor: MeshInstance3D = $InspectionFloor
@onready var play_icon: Texture2D = preload("res://assets/ui/icons/lucide/play.svg")
@onready var pause_icon: Texture2D = preload("res://assets/ui/icons/lucide/pause.svg")
@onready var panel_vbox: VBoxContainer = $UI/Panel/PanelScroll/Margin/VBox
@onready var title_bar: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/TitleBar
@onready var collapse_panel_button: Button = $UI/Panel/PanelScroll/Margin/VBox/TitleBar/Collapse
@onready var stage_buttons: Array[Button] = [
	$UI/Panel/PanelScroll/Margin/VBox/StageRow/Character,
	$UI/Panel/PanelScroll/Margin/VBox/StageRow/Rig,
	$UI/Panel/PanelScroll/Margin/VBox/StageRow/Animation,
	$UI/Panel/PanelScroll/Margin/VBox/StageRow/Attachments,
	$UI/Panel/PanelScroll/Margin/VBox/StageRow/Pose,
	$UI/Panel/PanelScroll/Margin/VBox/StageRow/Review,
]
@onready var empty_state: Label = $UI/EmptyState
@onready var panel_resize_handle: Button = $UI/PanelResizeHandle
@onready var orbit_camera_button: Button = $UI/ViewportToolbar/Margin/Buttons/Orbit
@onready var move_camera_button: Button = $UI/ViewportToolbar/Margin/Buttons/Move
@onready var zoom_out_button: Button = $UI/ViewportToolbar/Margin/Buttons/ZoomOut
@onready var zoom_in_button: Button = $UI/ViewportToolbar/Margin/Buttons/ZoomIn
@onready var reset_view_button: Button = $UI/ViewportToolbar/Margin/Buttons/ResetView
@onready var character_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/CharacterRow
@onready var rig_section: VBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/RigSection
@onready var rig_summary: Label = $UI/Panel/PanelScroll/Margin/VBox/RigSection/Summary
@onready var rig_mapping_scroll: ScrollContainer = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/MappingScroll)
@onready var rig_mapping_list: VBoxContainer = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/MappingScroll/MappingList)
@onready var rig_auto_map_button: Button = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/MappingActions/AutoMap)
@onready var rig_apply_button: Button = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/MappingActions/Apply)
@onready var rig_external_actions: VBoxContainer = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/ExternalActions)
@onready var rig_generate_button: Button = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/ExternalActions/GenerateRig)
@onready var rig_mixamo_button: Button = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/ExternalActions/Buttons/Mixamo)
@onready var rig_blender_button: Button = (
		$UI/Panel/PanelScroll/Margin/VBox/RigSection/ExternalActions/Buttons/Blender)
@onready var animation_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/AnimationRow
@onready var editor_mode_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/EditorModeRow
@onready var character_picker: OptionButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/CharacterRow/CharacterPicker")
@onready var animation_group_picker: OptionButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AnimationRow/GroupPicker")
@onready var animation_picker: OptionButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AnimationRow/AnimationPicker")
@onready var animation_package_menu: MenuButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AnimationRow/PackageMenu")
@onready var edit_mode_button: Button = $UI/Panel/PanelScroll/Margin/VBox/EditorModeRow/Edit
@onready var compare_mode_button: Button = $UI/Panel/PanelScroll/Margin/VBox/EditorModeRow/Compare
@onready var attachment_slots_row: HBoxContainer = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AttachmentSlotsRow")
@onready var attachment_slot_picker: OptionButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AttachmentSlotsRow/SlotPicker")
@onready var add_attachment_button: Button = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AttachmentSlotsRow/Add")
@onready var remove_attachment_button: Button = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AttachmentSlotsRow/Remove")
@onready var attachment_visible_toggle: CheckButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AttachmentSlotsRow/Visible")
@onready var object_path_field: LineEdit = $UI/Panel/PanelScroll/Margin/VBox/ObjectRow/ObjectPath
@onready var attachment_picker: OptionButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AttachmentRow/AttachmentPicker")
@onready var scale_slider: HSlider = $UI/Panel/PanelScroll/Margin/VBox/AttachmentRow/ScaleSlider
@onready var scale_value: Label = $UI/Panel/PanelScroll/Margin/VBox/AttachmentRow/ScaleValue
@onready var preset_path_field: LineEdit = $UI/Panel/PanelScroll/Margin/VBox/PresetRow/PresetPath
@onready var object_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/ObjectRow
@onready var attachment_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/AttachmentRow
@onready var preset_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/PresetRow
@onready var view_row: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/ViewRow
@onready var display_options: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/DisplayOptions
@onready var bone_section: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/BoneSection
@onready var bone_buttons: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/BoneButtons
@onready var pose_actions: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/PoseActions
@onready var save_pose_button: Button = $UI/Panel/PanelScroll/Margin/VBox/PoseActions/SavePose
@onready var load_pose_button: Button = $UI/Panel/PanelScroll/Margin/VBox/PoseActions/LoadPose
@onready var object_transform_controls: Array[Control] = [
	$UI/Panel/PanelScroll/Margin/VBox/ObjectPositionSection,
	$UI/Panel/PanelScroll/Margin/VBox/PositionX,
	$UI/Panel/PanelScroll/Margin/VBox/PositionY,
	$UI/Panel/PanelScroll/Margin/VBox/PositionZ,
	$UI/Panel/PanelScroll/Margin/VBox/RotationSection,
	$UI/Panel/PanelScroll/Margin/VBox/RotationX,
	$UI/Panel/PanelScroll/Margin/VBox/RotationY,
	$UI/Panel/PanelScroll/Margin/VBox/RotationZ,
]
@onready var view_picker: OptionButton = $UI/Panel/PanelScroll/Margin/VBox/ViewRow/ViewPicker
@onready var pause_toggle: CheckButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/DisplayOptions/PauseAnimation")
@onready var show_bones_toggle: Button = $UI/ViewportToolbar/Margin/Buttons/ShowBones
@onready var free_camera_toggle: CheckButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/DisplayOptions/FreeCamera")
@onready var root_motion_toggle: CheckButton = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/DisplayOptions/RootMotionMoving")
@onready var axis_ring_toggles: Array[CheckButton] = [
	$UI/Panel/PanelScroll/Margin/VBox/BoneSection/XRing,
	$UI/Panel/PanelScroll/Margin/VBox/BoneSection/YRing,
	$UI/Panel/PanelScroll/Margin/VBox/BoneSection/ZRing,
]
@onready var pose_helpers: HBoxContainer = $UI/Panel/PanelScroll/Margin/VBox/PoseHelpers
@onready var pose_helper_title: Label = $UI/Panel/PanelScroll/Margin/VBox/PoseHelpers/Title
@onready var pose_helper_controls: HFlowContainer = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/PoseHelpers/Controls")
@onready var bone_scroll: ScrollContainer = $UI/Panel/PanelScroll/Margin/VBox/BoneScroll
@onready var bone_controls: VBoxContainer = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/BoneScroll/BoneControls")
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
@onready var pose_library_overlay: Control = $UI/PoseLibraryOverlay
@onready var pose_library_search: LineEdit = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Content/Browser/Search")
@onready var pose_library_grid: GridContainer = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Content/Browser/Scroll/PoseGrid")
@onready var pose_library_viewport: SubViewport = %Viewport
@onready var pose_library_viewport_container: SubViewportContainer = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Content/Preview/ViewportContainer")
@onready var pose_library_rotate_left_button: Button = %RotateLeft
@onready var pose_library_rotate_right_button: Button = %RotateRight
@onready var pose_library_rotate_up_button: Button = %RotateUp
@onready var pose_library_rotate_down_button: Button = %RotateDown
@onready var pose_library_zoom_out_button: Button = %ZoomOut
@onready var pose_library_zoom_in_button: Button = %ZoomIn
@onready var pose_library_preview_name: Label = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Content/Preview/PoseName")
@onready var pose_library_preview_details: Label = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Content/Preview/Details")
@onready var pose_library_browse_button: Button = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Actions/Browse")
@onready var pose_library_load_button: Button = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Actions/LoadSelected")
@onready var pose_library_close_button: Button = get_node(
		^"UI/PoseLibraryOverlay/Center/LibraryPanel/Margin/VBox/Actions/Close")
@onready var object_dialog: FileDialog = $UI/ObjectDialog
@onready var open_preset_dialog: FileDialog = $UI/OpenPresetDialog
@onready var import_dialog: FileDialog = $UI/ImportDialog
@onready var import_character_button: Button = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/CharacterRow/ImportCharacter")
@onready var import_animation_button: Button = get_node(
		^"UI/Panel/PanelScroll/Margin/VBox/AnimationRow/ImportAnimation")
@onready var save_preset_dialog: FileDialog = $UI/SavePresetDialog
@onready var animation_package_name_dialog: ConfirmationDialog = $UI/AnimationPackageNameDialog
@onready var animation_package_name_field: LineEdit = $UI/AnimationPackageNameDialog/Margin/Name
@onready var animation_package_delete_dialog: ConfirmationDialog = $UI/AnimationPackageDeleteDialog

var _character_kind := ""
## When true, _process() applies each frame's root_motion_track delta to
## body.node so the character actually walks/runs through world space -
## otherwise the AnimationMixer already plays every animation "in place"
## for free once root_motion_track is set (see _load_character()), since it
## strips the root bone's own translation from the applied pose regardless
## of whether anything reads get_root_motion_position().
var _root_motion_moving := false
## Populated by _on_mcp_debugger_message on "import_asset_result" - polled
## by _request_import_asset's await loop. Empty means "no reply yet".
var _pending_import_result: Dictionary = {}
## kind_id -> {model_path, display_name, bone_prefix (String) or null
## (unrecognized skeleton, posable only)}. Characters imported this session
## via the "Import Character..." button - not persisted; ask your assistant
## to add a character permanently once you know you want to keep it.
var _custom_characters: Dictionary = {
	"zombie1": {
		"model_path": "res://assets/models/zombie1/zombie1_source.glb",
		"source_model_path": "res://assets/models/zombie1/zombie1_source.glb",
		"display_name": "Zombie 1",
		"bone_prefix": null,
		"has_skin": false,
		"humanoid_map": {},
	},
}
## clip StringName -> Animation, rebuilt for the currently selected character
## from persistent CharacterAnimationPackage source paths.
var _custom_clips: Dictionary = {}
enum ImportMode { CHARACTER, ANIMATION }
var _import_mode := ImportMode.CHARACTER
## Copy + editor reimport + skeleton inspection + (for animations) retarget
## runs the actual reimport synchronously on the EDITOR's own main thread
## (EditorFileSystem.reimport_files() - see pose_debugger_plugin.gd's
## _import_asset), which blocks the editor for however long that takes.
## This played scene's own script keeps ticking normally throughout
## (confirmed live: a per-frame file log showed continuous updates with no
## gaps for the whole duration), but the window never actually presents a
## new frame until the editor comes back - a live-tested animated spinner
## here was provably running correctly and simply never visible on screen,
## on both a multi-second big-file import and a sub-second small one. Only
## the ONE status text set synchronously before the first await (in
## _on_import_file_selected) is guaranteed to actually render.
var _import_in_progress := false
var _modifier: PlayerHandGripModifier
var _comparison: RawAnimationComparison
var _held_object: Node3D
var _object_attachment: BoneAttachment3D
var _full_body_mesh: Mesh
var _isolated_attachment_mesh: ArrayMesh
var _bone_debug_root: Node3D
var _bone_segment_mesh: ArrayMesh
var _joint_mesh: SphereMesh
var _rotation_ring_mesh: TorusMesh
var _bone_segment_material: StandardMaterial3D
var _joint_material: StandardMaterial3D
var _selected_joint_material: StandardMaterial3D
var _selected_bone_material: StandardMaterial3D
var _bone_section_materials: Dictionary = {}
var _joint_section_materials: Dictionary = {}
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
var _current_animation := &""
var _current_object_path := DEFAULT_OBJECT_PATH
var _current_pose_path := ""
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

var _mcp_handler: CharacterEditorMcpHandler
var _import_handler: CharacterEditorImportHandler
var _pose_io_handler: CharacterEditorPoseIoHandler
var _ui_setup_handler: CharacterEditorUiSetupHandler
var _bone_controls_handler: CharacterEditorBoneControlsHandler
var _camera_handler: CharacterEditorCameraHandler
var _gizmo_handler: CharacterEditorGizmoHandler
var _pose_library_handler: CharacterEditorPoseLibraryHandler
var _attachment_handler: CharacterEditorAttachmentHandler
var _stage_handler: CharacterEditorStageHandler
var _animation_package_handler: CharacterEditorAnimationPackageHandler
var _animation_transport: CharacterEditorAnimationTransport
var _rig_handler


func _ready() -> void:
	_mcp_handler = CharacterEditorMcpHandler.new(self)
	_import_handler = CharacterEditorImportHandler.new(self)
	_pose_io_handler = CharacterEditorPoseIoHandler.new(self)
	_ui_setup_handler = CharacterEditorUiSetupHandler.new(self)
	_bone_controls_handler = CharacterEditorBoneControlsHandler.new(self)
	_camera_handler = CharacterEditorCameraHandler.new(self)
	_gizmo_handler = CharacterEditorGizmoHandler.new(self)
	_pose_library_handler = CharacterEditorPoseLibraryHandler.new(self)
	_attachment_handler = CharacterEditorAttachmentHandler.new(self)
	_stage_handler = CharacterEditorStageHandler.new(self)
	_animation_package_handler = CharacterEditorAnimationPackageHandler.new(self)
	_animation_transport = CharacterEditorAnimationTransport.new(self)
	_rig_handler = RIG_HANDLER.new(self)
	_rig_handler.restore_generated_characters()
	get_viewport().size_changed.connect(_ui_setup_handler._update_responsive_layout)
	_ui_setup_handler._update_responsive_layout()
	camera.current = true
	_comparison = RAW_COMPARISON.new()
	_ui_setup_handler._setup_controls()
	_attachment_handler.setup()
	_pose_library_handler.setup()
	_animation_package_handler.setup()
	_animation_transport.setup()
	_rig_handler.setup()
	_stage_handler.setup()
	var arguments := OS.get_cmdline_user_args()
	var initial_kind := ""
	for argument in arguments:
		if argument.begins_with("character="):
			initial_kind = argument.get_slice("=", 1)
	if initial_kind.is_empty() and not arguments.is_empty():
		initial_kind = DEFAULT_CHARACTER_KIND
	if not initial_kind.is_empty():
		_load_character(initial_kind)
	if "show_bones" in OS.get_cmdline_user_args():
		show_bones_toggle.set_pressed_no_signal(true)
		_gizmo_handler._on_show_bones_toggled(true)
	if EngineDebugger.is_active():
		# Lets addons/mcp_bridge query this exact running instance's live
		# pose over the editor debugger message channel, as opposed to the
		# invocation-based dump_bones= automation arg, which only ever reads
		# a fresh, separately-configured headless process.
		EngineDebugger.register_message_capture("mcp", _mcp_handler._on_mcp_debugger_message)
	await get_tree().process_frame
	if body != null:
		_camera_handler._frame_full_body()
	await _mcp_handler._run_automation_args()


## Builds (or rebuilds, when switching at runtime) whichever character
## "kind" is requested, tearing down the previous one's character-specific
## nodes first. See character_adapter.gd for why most of the tool's code
## doesn't need to know which character is loaded - only the pieces that
## touch the held-object/hand-grip system, comparison mode, or the mesh
## directly do.
func _load_character(kind: String) -> void:
	if not kind in CHARACTER_KINDS and not _custom_characters.has(kind):
		kind = DEFAULT_CHARACTER_KIND
	_clear_loaded_character()
	_custom_clips.clear()

	if kind == "player":
		body = PlayerBodyAdapter.create(self, CHARACTER_SPAWN_POSITION)
	elif RETARGETED_MIXAMO_CHARACTERS.has(kind):
		var config: Array = RETARGETED_MIXAMO_CHARACTERS[kind]
		body = RetargetedMixamoAdapter.create(
				self, CHARACTER_SPAWN_POSITION, config[0], config[1], config[2])
	elif _custom_characters.has(kind):
		body = _create_custom_character_adapter(_custom_characters[kind])
	else:
		var config: Array = MIXAMO_CHARACTERS[kind]
		body = MixamoCharacterAdapter.create(self, CHARACTER_SPAWN_POSITION, config[0], config[1])
	_character_kind = kind
	_current_animation = &""
	_animation_package_handler.on_character_changed()
	_setup_root_motion_track()

	_setup_modifier()
	if body.supports_held_object:
		body.set_held_flashlight_visible(false)
		_full_body_mesh = (body.mesh.mesh
				if body.supports_isolated_attachment and body.mesh != null else null)
	else:
		_full_body_mesh = null
	_setup_bone_debug()
	if body.supports_comparison:
		_comparison.setup(body.node as PlayerBody, target_compare_label, raw_source_ual1, raw_source_ual2)
	else:
		# Not _comparison.set_enabled(false, ...) - that touches _target/
		# _target_label, which are still null if setup() was never called
		# (e.g. Shambler loaded first, before any PlayerBody session).
		_comparison.enabled = false
		_comparison.has_raw_reference = false
		target_compare_label.hide()
		raw_source_ual1.hide()
		raw_source_ual2.hide()
	compare_mode_button.visible = body.supports_comparison
	attachment_slots_row.visible = body.supports_held_object
	object_row.visible = body.supports_held_object
	attachment_row.visible = body.supports_held_object
	preset_row.visible = body.supports_held_object
	for control in object_transform_controls:
		control.visible = body.supports_held_object
	# Save/Reload act on _current_pose_path, a held-object pose preset file -
	# Save Image and Copy Values stay visible, they're generic utilities.
	save_pose_button.visible = body.supports_held_object
	load_pose_button.visible = body.supports_held_object
	# "Isolated attachment" swaps body.mesh.mesh for a cutaway generated
	# around the held-object attachment point - meaningless (and, since
	# _full_body_mesh/_isolated_attachment_mesh are both null here, actively
	# wrong: it would blank out one mesh part) for a character with no held
	# objects at all.
	view_picker.set_item_disabled(2, not body.supports_isolated_attachment)
	if not body.supports_isolated_attachment and view_picker.selected == 2:
		view_picker.select(0)
		_camera_handler._on_view_selected(0)

	_attachment_bone = DEFAULT_ATTACHMENT_BONE
	_ui_setup_handler._populate_attachment_controls()
	_ui_setup_handler._populate_animation_controls()
	_bone_controls_handler._populate_bone_controls()

	# _selected_bone otherwise carries over from the previous character
	# (or its "RightArm" default) - a name that generally doesn't exist on
	# the new skeleton, leaving the pose-helper panel showing stale
	# buttons for animations the new character doesn't have.
	if body.skeleton.get_bone_count() > 0:
		_gizmo_handler._select_bone(body.skeleton.get_bone_name(0), false)

	_bone_controls_handler._sync_bone_controls()
	_gizmo_handler._refresh_skeleton()
	_ui_setup_handler._select_character_in_ui(_character_kind)
	_camera_handler.position_inspection_floor()
	_camera_handler._frame_full_body()
	_rig_handler.on_character_loaded()
	_stage_handler.on_character_loaded()


func _unload_character() -> void:
	_clear_loaded_character()
	_rig_handler.on_character_unloaded()
	_custom_clips.clear()
	_character_kind = ""
	_current_animation = &""
	_current_pose_path = ""
	_current_object_path = ""
	_animation_groups.clear()
	_animation_package_handler.on_character_changed()
	animation_group_picker.clear()
	animation_picker.clear()
	attachment_picker.clear()
	character_picker.select(0)
	compare_mode_button.hide()
	preset_path_field.text = ""
	status_label.text = "Select a character model"
	_stage_handler.enter_empty()


func _clear_loaded_character() -> void:
	if body != null and body.supports_comparison and _comparison.enabled:
		_comparison.set_enabled(false, _current_animation)
	_comparison.enabled = false
	_comparison.has_raw_reference = false
	target_compare_label.hide()
	raw_source_ual1.hide()
	raw_source_ual2.hide()
	if is_instance_valid(_modifier):
		_modifier.queue_free()
	_modifier = null
	_attachment_handler.clear()
	if is_instance_valid(_bone_debug_root):
		_bone_debug_root.queue_free()
	_bone_debug_root = null
	if body != null:
		body.free_node()
	body = null
	_bone_segments.clear()
	_joint_instances.clear()
	_rotation_rings.clear()
	_visible_bone_indices.clear()
	_joint_focus_active = false


## Picks the right adapter for a session-imported character based on the
## bone_prefix _import_character detected: exact "mixamorig_" reuses
## MixamoCharacterAdapter's action_adventure_pack-direct path, any other
## numbered/empty prefix goes through RetargetedMixamoAdapter's full
## retarget, and an unrecognized skeleton (null) falls back to the plain
## CharacterAdapter base class directly - posable (skeleton/mesh work fine
## generically) but with no animation pools, since there's no bone map for
## a convention this tool has never seen.
func _create_custom_character_adapter(info: Dictionary) -> CharacterAdapter:
	var model_path: String = info["model_path"]
	var display_name: String = info["display_name"]
	var bone_prefix: Variant = info["bone_prefix"]
	var humanoid_map: Dictionary = info.get("humanoid_map", {})
	var adapter: CharacterAdapter
	if bone_prefix == "mixamorig_" and info.get("has_skin", true):
		adapter = MixamoCharacterAdapter.create(self, CHARACTER_SPAWN_POSITION, model_path, display_name)
	elif bone_prefix != null and bone_prefix != "B-" and info.get("has_skin", true):
		adapter = RetargetedMixamoAdapter.create(
				self, CHARACTER_SPAWN_POSITION, model_path, display_name, bone_prefix)
	elif _rig_mapping_complete(humanoid_map) and info.get("has_skin", false):
		var mapped_adapter = MAPPED_HUMANOID_ADAPTER.new()
		adapter = mapped_adapter.bind(
				self, CHARACTER_SPAWN_POSITION, model_path, display_name, humanoid_map)
	else:
		adapter = _create_posable_only_adapter(model_path, display_name, info)
	adapter.model_path = model_path
	adapter.humanoid_map = humanoid_map.duplicate(true)
	adapter.has_skin = info.get("has_skin", true)
	adapter.humanoid_ready = adapter.has_skin and _rig_mapping_complete(adapter.humanoid_map)
	CharacterImportMaterialFixups.disable_mesh_transparency(adapter.meshes)
	CharacterImportMaterialFixups.fix_unwired_textures(adapter.meshes, model_path)
	return adapter


func _create_posable_only_adapter(
		model_path: String, display_name: String, info: Dictionary) -> CharacterAdapter:
	var instance: Node3D = (load(model_path) as PackedScene).instantiate()
	instance.position = CHARACTER_SPAWN_POSITION
	add_child(instance)
	var adapter := CharacterAdapter.new()
	adapter.node = instance
	adapter.skeleton = instance.find_child("Skeleton3D", true, false)
	if adapter.skeleton == null:
		adapter.skeleton = Skeleton3D.new()
		adapter.skeleton.name = &"Skeleton3D"
		instance.add_child(adapter.skeleton)
	adapter.meshes = []
	for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
		adapter.meshes.append(child as MeshInstance3D)
	adapter.mesh = adapter.meshes[0] if not adapter.meshes.is_empty() else null
	# Character-only exports commonly ship with no baked animation at all -
	# other code (root-motion setup, custom-clip playback) assumes
	# body.anim_player is always a real node to attach libraries to.
	var found_anim_player: AnimationPlayer = instance.find_child("AnimationPlayer", true, false)
	if found_anim_player == null:
		found_anim_player = AnimationPlayer.new()
		found_anim_player.name = &"AnimationPlayer"
		instance.add_child(found_anim_player)
	adapter.anim_player = found_anim_player
	adapter.supports_held_object = true
	adapter.display_name = display_name
	adapter.model_path = model_path
	adapter.has_skin = info.get("has_skin", false)
	adapter.humanoid_map = info.get("humanoid_map", {}).duplicate(true)
	adapter.humanoid_ready = false
	adapter.supports_held_object = adapter.skeleton.get_bone_count() > 0
	return adapter


func _rig_mapping_complete(mapping: Dictionary) -> bool:
	for role_info: Dictionary in RIG_HANDLER.REQUIRED_ROLES:
		if String(mapping.get(role_info["role"], "")).is_empty():
			return false
	return true


## Points anim_player at the skeleton's hips bone - "Hips" for PlayerBody/
## UAL-retargeted clips, "mixamorig_Hips" for the Mixamo characters - so
## every animation plays "in place" by default: once root_motion_track is
## set, Godot's AnimationMixer strips that bone's own translation from the
## applied pose every frame regardless of whether anything reads
## get_root_motion_position() - confirmed empirically, see the root-motion
## toggle investigation in task history. _process() opts back into real
## translation by reading that same delta when root_motion_toggle is on.
##
## Not just skeleton bone 0: PlayerBody's MotusMan rig has an extra
## technical "Root" bone above Hips at index 0 that carries no animation of
## its own (every retargeted UAL clip writes its position track to "Hips"
## specifically, per player_body.gd's _retarget_clip) - the Mixamo
## characters happen to put Hips at index 0 with no such wrapper, but
## searching by name handles both without needing a per-adapter override.
func _setup_root_motion_track() -> void:
	var root_bone_idx := -1
	for i in body.skeleton.get_bone_count():
		if body.skeleton.get_bone_name(i).ends_with("Hips"):
			root_bone_idx = i
			break
	if root_bone_idx < 0 and body.skeleton.get_bone_count() > 0:
		root_bone_idx = 0
	if root_bone_idx < 0:
		body.anim_player.root_motion_track = NodePath()
		return
	var root_bone_name := body.skeleton.get_bone_name(root_bone_idx)
	# Track paths (root_motion_track included) resolve relative to
	# anim_player's root_node (default: its own parent), the same way every
	# other track in these animations already does - e.g. player_body.gd's
	# _retarget_clip always writes plain NodePath("Skeleton3D:" + bone), not
	# a path relative to the AnimationPlayer itself. get_path_to(skeleton)
	# would prepend an extra ".." (skeleton is anim_player's sibling, not
	# child) and resolve one level too far up, silently matching no track.
	body.anim_player.root_motion_track = NodePath(
			String(body.skeleton.name) + ":" + root_bone_name)


## Drains the per-frame root-motion delta every frame regardless of the
## toggle state, so switching the toggle mid-playback never dumps a huge
## backlog of skipped deltas onto the character in one jump - only whether
## the drained delta gets APPLIED to body.node depends on
## root_motion_toggle. See _setup_root_motion_track() for why "in place"
## needs no extra work at all.
func _process_root_motion() -> void:
	if body == null or not is_instance_valid(body.anim_player):
		return
	var delta_position := body.anim_player.get_root_motion_position()
	if _root_motion_moving:
		body.node.position += delta_position


func _setup_modifier() -> void:
	_modifier = GRIP_MODIFIER.new() as PlayerHandGripModifier
	_modifier.name = &"HeldObjectPoseModifier"
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


func _load_object(path: String, reset_transform: bool) -> bool:
	if _attachment_handler.selected_slot() == null:
		return _attachment_handler.add(path, DEFAULT_ATTACHMENT_BONE)
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
	_attachment_handler.sync_selected_object(_held_object, resource_path)
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
	_bone_debug_root.visible = show_bones_toggle.button_pressed
	body.skeleton.add_child(_bone_debug_root)

	_bone_segment_mesh = _gizmo_handler.make_bone_segment_mesh()
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
	_selected_bone_material = _make_debug_material(Color(1.0, 0.64, 0.12, 0.95))
	_gizmo_handler._setup_bone_debug_materials()
	for axis in 3:
		var ring := _make_debug_mesh_instance(
				_rotation_ring_mesh, _make_debug_material(AXIS_COLORS[axis]))
		ring.name = StringName("RotationRing%s" % "XYZ"[axis])
		_rotation_rings.append(ring)
		_bone_debug_root.add_child(ring)
	body.skeleton.skeleton_updated.connect(_gizmo_handler._update_bone_gizmo)
	_gizmo_handler._rebuild_bone_gizmo()


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


func _input(event: InputEvent) -> void:
	if pose_library_overlay.visible:
		return
	if body == null or not _stage_handler.is_pose_stage():
		return
	if not event is InputEventMouseButton:
		return
	var button_event := event as InputEventMouseButton
	if (not button_event.pressed
			or button_event.button_index != MOUSE_BUTTON_LEFT
			or _captured
			or _is_pointer_over_tuner_ui(button_event.position)):
		return
	if show_bones_toggle.button_pressed and _gizmo_handler._begin_ring_drag(button_event.position):
		get_viewport().set_input_as_handled()
	elif button_event.double_click and _gizmo_handler._select_character_bone_at(button_event.position):
		get_viewport().set_input_as_handled()

func _is_pointer_over_tuner_ui(screen_position: Vector2) -> bool:
	var logical_position := screen_position / _ui_scale
	return (Rect2(panel.position, panel.size).has_point(logical_position)
			or Rect2(viewport_toolbar.position, viewport_toolbar.size).has_point(
					logical_position)
			or (playback_toolbar.visible
				and Rect2(playback_toolbar.position, playback_toolbar.size).has_point(
						logical_position))
			or (panel_resize_handle.visible
				and Rect2(panel_resize_handle.position, panel_resize_handle.size).has_point(
						logical_position))
			or _rig_handler.is_pointer_over_reference(logical_position))


func _unhandled_input(event: InputEvent) -> void:
	if pose_library_overlay.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_pose_library_handler.close()
		get_viewport().set_input_as_handled()
		return
	if body == null:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_drag_axis = -1
		_orbiting = false
		_orbiting_joint = false
		_camera_handler._end_camera_move()
		_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif (event is InputEventMagnifyGesture
			and not free_camera_toggle.button_pressed
			and (view_picker.selected == 0 or _joint_focus_active)):
		_camera_handler._apply_camera_zoom(1.0 / maxf(event.factor, 0.01))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if (button_event.pressed
				and button_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
				and not free_camera_toggle.button_pressed
				and (view_picker.selected == 0 or _joint_focus_active)):
			var zoom_factor := (
					ZOOM_STEP if button_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
			_camera_handler._apply_camera_zoom(zoom_factor)
			get_viewport().set_input_as_handled()
			return
		if button_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not button_event.pressed and _drag_axis >= 0:
			_drag_axis = -1
			status_label.text = "%s rotation set" % _bone_controls_handler._display_bone_name(_selected_bone)
			get_viewport().set_input_as_handled()
		elif not button_event.pressed and _orbiting:
			_orbiting = false
			_orbiting_joint = false
			get_viewport().set_input_as_handled()
		elif not button_event.pressed and _moving_camera:
			_camera_handler._end_camera_move()
			get_viewport().set_input_as_handled()
		elif button_event.pressed and not _captured:
			if show_bones_toggle.button_pressed and _gizmo_handler._begin_ring_drag(button_event.position):
				get_viewport().set_input_as_handled()
			elif free_camera_toggle.button_pressed:
				_captured = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif _camera_mode == CAMERA_MODE_MOVE:
				_camera_handler._begin_camera_move(button_event.position)
			elif _joint_focus_active:
				_camera_handler._begin_focused_joint_orbit()
			else:
				_orbiting = true
				_orbiting_joint = false
				status_label.text = ""
	elif event is InputEventMouseMotion and _drag_axis >= 0:
		_gizmo_handler._drag_rotation_ring((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * ORBIT_SENS
		_orbit_pitch = clampf(
				_orbit_pitch + motion.relative.y * ORBIT_SENS,
				-deg_to_rad(80.0), deg_to_rad(80.0))
		if _orbiting_joint:
			_focused_camera_offset = _camera_handler._get_orbit_direction() * _orbit_distance
			_camera_handler._update_focused_camera()
		else:
			_camera_handler._update_orbit_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _moving_camera:
		_camera_handler._move_camera_from_drag((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _captured:
		_yaw -= event.relative.x * LOOK_SENS
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENS,
				-deg_to_rad(89.0), deg_to_rad(89.0))
		camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	_animation_transport.update()
	if body == null:
		return
	_process_root_motion()
	if not free_camera_toggle.button_pressed:
		if _joint_focus_active:
			_camera_handler._update_focused_camera()
		return
	if not _captured:
		return
	var input := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical := Input.get_axis(&"crouch", &"jump")
	var speed := MOVE_SPEED * (3.0 if Input.is_action_pressed(&"sprint") else 1.0)
	var direction := (camera.global_basis * Vector3(input.x, vertical, input.y)).normalized()
	camera.global_position += direction * speed * delta
