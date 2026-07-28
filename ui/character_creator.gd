extends Node3D
## Player-facing character customization: pick body, hairstyle, facial hair, eyebrows, hair color,
## eye color, and skin tone, see a live preview, then spawn into the game as that combination.
## PlayerProfile (autoload) stores the choice; PlayerBody reads it on _ready() and swaps to the
## matching catalog character.

const FEMALE_DIR := "res://assets/models/imported_characters/402453fc-7d0e-4139-9cb0-f2dbe6276161/"
const MALE_DIR := "res://assets/models/imported_characters/8bcc06df-6c6e-42f0-b2c1-5f37ccf2b28b/"
const HAIR_DIR := "res://assets/models/universal_base_characters/hairstyles/"
const OUTFIT_DIR := "res://assets/models/modular_outfits_fantasy/"

## TEMPORARY debug feature to preview Quaternius's "Modular Character Outfits - Fantasy" pack
## (dropped in ~/Downloads, not yet a real gameplay feature - no PlayerProfile field, no
## player_body_cosmetics.gd wiring). Its own README confirms it's built for this exact base kit,
## and its bone names match ours 1:1 (pelvis/spine_01-03/clavicle_l-r/full finger chains), so no
## new humanoid_map is needed. Each outfit ships its own complete rest-pose skeleton at identity
## transform, so it lines up with the base character without retargeting. The free base pack has
## no separate head mesh even though the outfit README requires one. This baseline deliberately
## renders the complete base body under clothing so overlap can be evaluated without masking.
## These paths point at the original pack files, unmodified - no clearance adjustment applied.
## See CURRENT_TASK.md.
const OUTFITS := [
	{"id": "none", "label": "None"},
	{"id": "peasant", "label": "Peasant"},
	{"id": "ranger", "label": "Ranger"},
]
const OUTFIT_PATHS := {
	"custom_superhero_female_fullbody": {
		"peasant": OUTFIT_DIR + "Female_Peasant.gltf",
		"ranger": OUTFIT_DIR + "Female_Ranger.gltf",
	},
	"custom_superhero_male_fullbody": {
		"peasant": OUTFIT_DIR + "Male_Peasant.gltf",
		"ranger": OUTFIT_DIR + "Male_Ranger.gltf",
	},
}
const DISCARD_SURFACE_SHADER := preload("res://shaders/discard_surface.gdshader")

## Both bodies were imported from the "Universal Base Characters" pack with
## a hand-built humanoid_map (see the character catalog manifests next to
## each model) since their UE-Mannequin bone convention isn't one
## HumanoidRetargeter.detect_bone_prefix() recognizes - not relevant here,
## just why these particular kind_ids exist.
const BODIES := [
	{
		"kind_id": "custom_superhero_female_fullbody",
		"label": "Female",
		"dir": FEMALE_DIR,
		"model_path": FEMALE_DIR + "Superhero_Female_FullBody.gltf",
		"mesh_name": "Superhero_Female",
		"base_texture": FEMALE_DIR + "T_Superhero_Female_Light_BaseColor.png",
	},
	{
		"kind_id": "custom_superhero_male_fullbody",
		"label": "Male",
		"dir": MALE_DIR,
		"model_path": MALE_DIR + "Superhero_Male_FullBody.gltf",
		"mesh_name": "SuperHero_Male",
		"base_texture": MALE_DIR + "T_Superhero_Male_Light_BaseColor.png",
	},
]

## The pack's "Light"/"Dark" texture pair turned out to differ only in outfit color, not skin tone
## (confirmed by comparing the two files directly) - there's no actual light/pale skin art to
## select, so tones are approximated by tinting the one base texture above; "Tan" (no tint) is as
## light as this asset pack gets, since a multiply tint can only darken a texture, never lighten
## it beyond its own baked color.
const SKIN_TONES := [
	{"id": "tan", "label": "Tan", "tint": Color(1.0, 1.0, 1.0)},
	{"id": "caramel", "label": "Caramel", "tint": Color(0.82, 0.68, 0.56)},
	{"id": "brown", "label": "Brown", "tint": Color(0.62, 0.48, 0.38)},
	{"id": "deep", "label": "Deep", "tint": Color(0.42, 0.31, 0.24)},
]

## The pack's only shipped eye art is T_Eye_Brown.png, with no other iris colors - real eye/skin
## shader customization is a paid "Source"-tier feature of this pack (confirmed on its itch.io
## page), not included in what we imported. These are real texture variants (not a runtime tint):
## generated once by recoloring just the iris pixels of that one texture in HSV space (hue in
## [0.04, 0.14], saturation >= 0.35, value in [0.08, 0.9] - isolates the iris from the sclera,
## pupil, and highlight glint) while preserving its original shading, then saved per body as
## T_Eye_<Label>.png next to the source.
const EYE_COLORS := [
	{"id": "brown", "label": "Brown"},
	{"id": "blue", "label": "Blue"},
	{"id": "green", "label": "Green"},
	{"id": "gray", "label": "Gray"},
	{"id": "hazel", "label": "Hazel"},
]

## Three independent head-attachment slots, so e.g. a male can combine any hairstyle with Beard
## instead of picking only one. Hair_Buns and Hair_BuzzedFemale are excluded from HAIRSTYLES -
## their source files bake vertex positions in a different scale/axis convention (centimeters, a
## swapped up-axis) than the rest, and don't place correctly with the same offset formula. Left
## for later individual tuning.
const HAIRSTYLES := [
	{"id": "none", "label": "None", "path": ""},
	{"id": "long", "label": "Long", "path": HAIR_DIR + "Hair_Long.gltf"},
	{"id": "simple_parted", "label": "Simple Parted", "path": HAIR_DIR + "Hair_SimpleParted.gltf"},
	{"id": "buzzed", "label": "Buzzed", "path": HAIR_DIR + "Hair_Buzzed.gltf"},
]
const FACIAL_HAIR := [
	{"id": "none", "label": "None", "path": ""},
	{"id": "beard", "label": "Beard", "path": HAIR_DIR + "Hair_Beard.gltf",
			"bodies": ["custom_superhero_male_fullbody"]},
]
## No "None" entry - the base skin texture already bakes in eyebrows, so an unattached face looks
## identical to the Regular mesh; offering a "None" that doesn't visibly do anything is confusing.
const EYEBROWS := [
	{"id": "eyebrows_regular", "label": "Regular", "path": HAIR_DIR + "Eyebrows_Regular.gltf"},
	{"id": "eyebrows_female", "label": "Female", "path": HAIR_DIR + "Eyebrows_Female.gltf",
			"bodies": ["custom_superhero_female_fullbody"]},
]

## The hair/beard/eyebrow meshes share a near-white base texture (unlike the skin textures) made
## for tinting - white multiplies against any tint near-losslessly, so this palette reaches real
## blonde/gray, not just progressively darker shades like SKIN_TONES. Applies uniformly to
## whichever of Hairstyle/Facial Hair/Eyebrows is currently attached.
const HAIR_COLORS := [
	{"id": "black", "label": "Black", "tint": Color(0.05, 0.045, 0.045)},
	{"id": "dark_brown", "label": "Dark Brown", "tint": Color(0.22, 0.14, 0.09)},
	{"id": "brown", "label": "Brown", "tint": Color(0.4, 0.26, 0.15)},
	{"id": "blonde", "label": "Blonde", "tint": Color(0.82, 0.68, 0.42)},
	{"id": "auburn", "label": "Auburn", "tint": Color(0.45, 0.16, 0.09)},
	{"id": "gray", "label": "Gray", "tint": Color(0.75, 0.75, 0.75)},
]

## Each mesh is baked against one specific body's Head-bone rest position; on the other body it
## needs an extra vertical nudge (in the same world-baked space _rebuild_cosmetic() re-expresses
## via bone-rest-inverse) - empirically tuned per combination by rendering this scene itself (via
## a forced PlayerProfile) and zoom-cropping the captured frame; a plain full-frame screenshot
## isn't close enough to catch a wrong-by-half correction.
const HAIR_Y_CORRECTIONS := {
	"custom_superhero_male_fullbody": {"long": 0.05, "eyebrows_female": 0.03},
	"custom_superhero_female_fullbody":
			{"buzzed": -0.03, "simple_parted": -0.05, "eyebrows_regular": -0.04},
}

const NEXT_SCENE := "res://levels/nature_playground.tscn"
const ORBIT_SENS := 0.006
const ZOOM_STEP := 0.15
const MIN_ORBIT_DISTANCE := 0.5
const MAX_ORBIT_DISTANCE := 4.0
const DEFAULT_ORBIT_TARGET := Vector3(0, 1.0, 0)
const DEFAULT_ORBIT_DISTANCE := 3.0
const FACE_ORBIT_TARGET := Vector3(0, 1.65, 0)
const FACE_ORBIT_DISTANCE := 0.8

@onready var camera: Camera3D = $Camera
@onready var preview_root: Node3D = $PreviewRoot
@onready var body_option: OptionButton = $UI/Panel/Margin/VBox/BodyRow/BodyOption
@onready var hair_option: OptionButton = $UI/Panel/Margin/VBox/HairRow/HairOption
@onready var facial_hair_row: VBoxContainer = $UI/Panel/Margin/VBox/FacialHairRow
@onready var facial_hair_option: OptionButton = $UI/Panel/Margin/VBox/FacialHairRow/FacialHairOption
@onready var eyebrows_row: VBoxContainer = $UI/Panel/Margin/VBox/EyebrowsRow
@onready var eyebrows_option: OptionButton = $UI/Panel/Margin/VBox/EyebrowsRow/EyebrowsOption
@onready var hair_color_option: OptionButton = $UI/Panel/Margin/VBox/HairColorRow/HairColorOption
@onready var eye_color_option: OptionButton = $UI/Panel/Margin/VBox/EyeColorRow/EyeColorOption
@onready var skin_tone_option: OptionButton = $UI/Panel/Margin/VBox/SkinToneRow/SkinToneOption
@onready var outfit_option: OptionButton = $UI/Panel/Margin/VBox/OutfitRow/OutfitOption
@onready var outfit_debug_colors: CheckButton = $UI/Panel/Margin/VBox/OutfitRow/DebugColors
@onready var outfit_show_clipping: CheckButton = $UI/Panel/Margin/VBox/OutfitRow/ShowClipping
@onready var edit_fit_button: Button = $UI/Panel/Margin/VBox/OutfitRow/EditFit
@onready var start_button: Button = $UI/Panel/Margin/VBox/StartButton
@onready var fit_panel: PanelContainer = $UI/FitPanel
@onready var fit_show_control_points: CheckButton = (
		$UI/FitPanel/Margin/VBox/ShowControlPoints)
@onready var fit_selection: Label = $UI/FitPanel/Margin/VBox/Selection
@onready var fit_surface_selector: OptionButton = (
		$UI/FitPanel/Margin/VBox/SurfaceRow/SurfaceSelector)
@onready var fit_distance: SpinBox = $UI/FitPanel/Margin/VBox/Grid/Distance
@onready var fit_distance_slider: HSlider = $UI/FitPanel/Margin/VBox/Grid/DistanceSlider
@onready var fit_reset_distance: Button = $UI/FitPanel/Margin/VBox/Grid/ResetDistance
@onready var fit_radius: SpinBox = $UI/FitPanel/Margin/VBox/Grid/Radius
@onready var fit_radius_slider: HSlider = $UI/FitPanel/Margin/VBox/Grid/RadiusSlider
@onready var fit_reset_radius: Button = $UI/FitPanel/Margin/VBox/Grid/ResetRadius
@onready var fit_auto_clearance: SpinBox = $UI/FitPanel/Margin/VBox/Grid/AutoClearance
@onready var fit_auto_clearance_slider: HSlider = $UI/FitPanel/Margin/VBox/Grid/AutoClearanceSlider
@onready var fit_reset_auto_clearance: Button = $UI/FitPanel/Margin/VBox/Grid/ResetAutoClearance
@onready var fit_auto_adjust: Button = $UI/FitPanel/Margin/VBox/ButtonRow/AutoAdjust
@onready var fit_reset_all: Button = $UI/FitPanel/Margin/VBox/ButtonRow/ResetAll
@onready var fit_save: Button = $UI/FitPanel/Margin/VBox/Save
@onready var fit_status: Label = $UI/FitPanel/Margin/VBox/Status

## One independent OptionButton-backed choice (Hairstyle, Facial Hair, or Eyebrows). `items` is
## one of the consts above; `indices` maps each dropdown row back to an `items` index since
## Beard/Eyebrows (Female) are filtered per body.
class Slot:
	var items: Array
	var option: OptionButton
	var index := 0
	var indices: Array[int] = []
	var preview: BoneAttachment3D

	func _init(p_items: Array, p_option: OptionButton) -> void:
		items = p_items
		option = p_option

	func populate(kind_id: String) -> void:
		option.clear()
		indices.clear()
		for i in items.size():
			var allowed: Array = items[i].get("bodies", [])
			if allowed.is_empty() or kind_id in allowed:
				option.add_item(items[i]["label"])
				indices.append(i)

	func select(target_index: int) -> void:
		var option_index := indices.find(target_index)
		if option_index < 0:
			option_index = 0
			target_index = indices[0] if not indices.is_empty() else 0
		index = target_index
		option.select(option_index)

	func current_id() -> String:
		return String(items[index]["id"])

	func current_item() -> Dictionary:
		return items[index]


var _body_index := 1
var _hair_color := "brown"
var _eye_color := "brown"
var _skin_tone := "caramel"
var _outfit_id := "peasant"
var _outfit_debug_colors := true
var _show_outfit_clipping := true
var _preview_body: Node3D
var _preview_outfit: Node3D
var _hair_slot: Slot
var _facial_hair_slot: Slot
var _eyebrows_slot: Slot
var _orbit_yaw := 0.0
var _orbit_pitch := -0.05
var _orbit_distance := FACE_ORBIT_DISTANCE
var _orbit_target := FACE_ORBIT_TARGET
var _orbiting := false
var _face_focused := true
var _fit_editor: OutfitFitEditor
var _updating_fit_controls := false
var _camera_tween: Tween


func _ready() -> void:
	for body in BODIES:
		body_option.add_item(body["label"])
	for tone in SKIN_TONES:
		skin_tone_option.add_item(String(tone["label"]))
	for color in HAIR_COLORS:
		hair_color_option.add_item(String(color["label"]))
	for color in EYE_COLORS:
		eye_color_option.add_item(String(color["label"]))
	for outfit in OUTFITS:
		outfit_option.add_item(String(outfit["label"]))
	for i in OUTFITS.size():
		if OUTFITS[i]["id"] == _outfit_id:
			outfit_option.select(i)
			break
	_hair_slot = Slot.new(HAIRSTYLES, hair_option)
	_find_slot_index(_hair_slot, "simple_parted")
	_facial_hair_slot = Slot.new(FACIAL_HAIR, facial_hair_option)
	_eyebrows_slot = Slot.new(EYEBROWS, eyebrows_option)
	_find_slot_index(_eyebrows_slot, "eyebrows_regular")
	body_option.item_selected.connect(_on_body_selected)
	hair_option.item_selected.connect(_on_slot_selected.bind(_hair_slot))
	facial_hair_option.item_selected.connect(_on_slot_selected.bind(_facial_hair_slot))
	eyebrows_option.item_selected.connect(_on_slot_selected.bind(_eyebrows_slot))
	hair_color_option.item_selected.connect(_on_hair_color_selected)
	eye_color_option.item_selected.connect(_on_eye_color_selected)
	skin_tone_option.item_selected.connect(_on_skin_tone_selected)
	outfit_option.item_selected.connect(_on_outfit_selected)
	outfit_debug_colors.toggled.connect(_on_outfit_debug_colors_toggled)
	outfit_show_clipping.toggled.connect(_on_outfit_show_clipping_toggled)
	edit_fit_button.toggled.connect(_on_edit_fit_toggled)
	fit_show_control_points.toggled.connect(_on_fit_show_control_points_toggled)
	fit_distance.value_changed.connect(_on_fit_value_changed)
	fit_radius.value_changed.connect(_on_fit_value_changed)
	fit_distance_slider.value_changed.connect(
			_on_fit_slider_changed.bind(fit_distance))
	fit_radius_slider.value_changed.connect(
			_on_fit_slider_changed.bind(fit_radius))
	fit_reset_distance.pressed.connect(_on_fit_reset_distance)
	fit_reset_radius.pressed.connect(_on_fit_reset_radius)
	fit_auto_clearance.value_changed.connect(_on_fit_auto_clearance_changed)
	fit_auto_clearance_slider.value_changed.connect(_on_fit_auto_clearance_changed)
	fit_reset_auto_clearance.pressed.connect(_on_fit_reset_auto_clearance)
	fit_auto_adjust.pressed.connect(_on_fit_auto_adjust)
	fit_surface_selector.item_selected.connect(_on_fit_surface_selected)
	fit_reset_all.pressed.connect(_on_fit_reset_all)
	fit_save.pressed.connect(_on_fit_save)
	start_button.pressed.connect(_on_start_pressed)
	_fit_editor = OutfitFitEditor.new()
	add_child(_fit_editor)
	_fit_editor.setup(camera)
	_fit_editor.selection_changed.connect(_on_fit_selection_changed)
	_fit_editor.selection_cleared.connect(_on_fit_selection_cleared)
	_fit_editor.status_changed.connect(_on_fit_status_changed)
	if PlayerProfile.has_profile:
		_select_stored_profile()
	body_option.select(_body_index)
	_select_hair_color_option()
	_select_eye_color_option()
	_select_skin_tone_option()
	_populate_and_select_slots()
	_update_orbit_camera()
	_rebuild_preview()


## Defaults (Male/Simple Parted/no Beard/Regular eyebrows/Brown hair/Brown eyes/Caramel skin) are
## set on the state vars above and by the _find_slot_index() calls in _ready() before this ever
## runs; a stored profile overrides whichever of those it actually has an opinion on.
func _select_stored_profile() -> void:
	for i in BODIES.size():
		if BODIES[i]["kind_id"] == PlayerProfile.character_kind:
			_body_index = i
			break
	_find_slot_index(_hair_slot, PlayerProfile.hairstyle_id)
	_find_slot_index(_facial_hair_slot, PlayerProfile.facial_hair_id)
	_find_slot_index(_eyebrows_slot, PlayerProfile.eyebrows_id)
	_hair_color = PlayerProfile.hair_color_id
	_eye_color = PlayerProfile.eye_color_id
	_skin_tone = PlayerProfile.skin_tone


func _select_hair_color_option() -> void:
	for i in HAIR_COLORS.size():
		if HAIR_COLORS[i]["id"] == _hair_color:
			hair_color_option.select(i)
			return


func _select_eye_color_option() -> void:
	for i in EYE_COLORS.size():
		if EYE_COLORS[i]["id"] == _eye_color:
			eye_color_option.select(i)
			return


func _select_skin_tone_option() -> void:
	for i in SKIN_TONES.size():
		if SKIN_TONES[i]["id"] == _skin_tone:
			skin_tone_option.select(i)
			return


func _find_slot_index(slot: Slot, id: String) -> void:
	for i in slot.items.size():
		if slot.items[i]["id"] == id:
			slot.index = i
			return


## Repopulates all three dropdowns for the current body (e.g. no Beard for Female) and re-selects
## each slot's target index, falling back to "None" if it's no longer valid for this body.
func _populate_and_select_slots() -> void:
	var kind_id: String = BODIES[_body_index]["kind_id"]
	for slot in [_hair_slot, _facial_hair_slot, _eyebrows_slot]:
		slot.populate(kind_id)
		slot.select(slot.index)
	facial_hair_row.visible = _facial_hair_slot.indices.size() > 1
	eyebrows_row.visible = _eyebrows_slot.indices.size() > 1


func _on_body_selected(index: int) -> void:
	_body_index = index
	_populate_and_select_slots()
	_rebuild_preview()


func _on_slot_selected(option_index: int, slot: Slot) -> void:
	slot.index = slot.indices[option_index]
	slot.preview = _rebuild_cosmetic(slot)


## Re-tints whichever of Hairstyle/Facial Hair/Eyebrows is currently attached - all three share
## one hair color, matching how a real head/beard/eyebrows usually match.
func _on_hair_color_selected(index: int) -> void:
	_hair_color = String(HAIR_COLORS[index]["id"])
	for slot in [_hair_slot, _facial_hair_slot, _eyebrows_slot]:
		slot.preview = _rebuild_cosmetic(slot)


func _on_eye_color_selected(index: int) -> void:
	_eye_color = String(EYE_COLORS[index]["id"])
	_apply_eye_color()


func _on_skin_tone_selected(index: int) -> void:
	_skin_tone = String(SKIN_TONES[index]["id"])
	_apply_skin_tone()
	if _outfit_id != "none":
		_rebuild_outfit()


func _on_outfit_selected(index: int) -> void:
	_outfit_id = String(OUTFITS[index]["id"])
	_rebuild_outfit()


func _on_outfit_debug_colors_toggled(enabled: bool) -> void:
	_outfit_debug_colors = enabled
	outfit_show_clipping.disabled = not enabled
	_refresh_outfit_debug_preview()


func _on_outfit_show_clipping_toggled(enabled: bool) -> void:
	_show_outfit_clipping = enabled
	_refresh_outfit_debug_preview()


func _refresh_outfit_debug_preview() -> void:
	if not is_instance_valid(_preview_body) or not is_instance_valid(_preview_outfit):
		return
	var body: Dictionary = BODIES[_body_index]
	var base_mesh := _preview_body.find_child(
			String(body["mesh_name"]), true, false) as MeshInstance3D
	if base_mesh == null:
		return
	_fit_editor.set_clipping_visualization(
			_outfit_debug_colors and _show_outfit_clipping)
	_apply_body_debug_material(base_mesh)
	_apply_outfit_materials(_preview_outfit)


func _on_edit_fit_toggled(enabled: bool) -> void:
	if enabled and not _fit_editor.has_outfit():
		edit_fit_button.set_pressed_no_signal(false)
		return
	fit_panel.visible = enabled
	_fit_editor.set_editing(enabled)
	if enabled:
		_face_focused = false
		_orbit_target = DEFAULT_ORBIT_TARGET
		_orbit_distance = DEFAULT_ORBIT_DISTANCE
		_update_orbit_camera()


func _on_fit_show_control_points_toggled(enabled: bool) -> void:
	_fit_editor.set_control_points_visible(enabled)


func _on_fit_selection_changed(label: String, distance: float, radius: float) -> void:
	_updating_fit_controls = true
	fit_selection.text = label
	fit_distance.value = distance * 100.0
	fit_radius.value = radius
	fit_distance_slider.value = distance * 100.0
	fit_radius_slider.value = radius
	_set_fit_controls_enabled(true)
	_sync_surface_selector_to_selection(label)
	_updating_fit_controls = false
	var body: Dictionary = BODIES[_body_index]
	var base_mesh := _preview_body.find_child(
			String(body["mesh_name"]), true, false) as MeshInstance3D
	if base_mesh != null:
		_apply_body_debug_material(base_mesh)
	_apply_outfit_materials(_preview_outfit)
	_focus_camera_on_selected_surface()


func _focus_camera_on_selected_surface() -> void:
	var center := _fit_editor.get_selected_surface_center()
	if center.is_zero_approx():
		return
	var current_pos := camera.global_position
	var dir_h := (center - current_pos) * Vector3(1, 0, 1)
	if dir_h.length_squared() < 0.0001:
		dir_h = Vector3(0, 0, -1)
	else:
		dir_h = dir_h.normalized()
	var target_pos := center - dir_h * 1.2
	target_pos.y = center.y
	var orbit_offset := target_pos - center
	_face_focused = false
	_orbit_target = center
	_orbit_distance = orbit_offset.length()
	if _orbit_distance > 0.0001:
		_orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
		_orbit_pitch = asin(clampf(
				orbit_offset.y / _orbit_distance, -1.0, 1.0))
	if is_instance_valid(_camera_tween):
		_camera_tween.kill()
	_camera_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_method(
			func(p: Vector3) -> void:
				camera.global_position = p
				camera.look_at(center, Vector3.UP),
			current_pos, target_pos, 0.35)


func _on_fit_selection_cleared() -> void:
	fit_selection.text = "No point selected"
	_set_fit_controls_enabled(false)
	if fit_surface_selector.item_count > 0:
		fit_surface_selector.select(0)
	var body: Dictionary = BODIES[_body_index]
	var base_mesh := _preview_body.find_child(
			String(body["mesh_name"]), true, false) as MeshInstance3D
	if base_mesh != null:
		_apply_body_debug_material(base_mesh)
	if is_instance_valid(_preview_outfit):
		_apply_outfit_materials(_preview_outfit)


func _on_fit_value_changed(_value: float) -> void:
	if _updating_fit_controls:
		return
	_updating_fit_controls = true
	fit_distance_slider.value = fit_distance.value
	fit_radius_slider.value = fit_radius.value
	_updating_fit_controls = false
	_apply_fit_control_values()


func _on_fit_slider_changed(value: float, input: SpinBox) -> void:
	if _updating_fit_controls:
		return
	_updating_fit_controls = true
	input.value = value
	_updating_fit_controls = false
	_apply_fit_control_values()


func _apply_fit_control_values() -> void:
	_fit_editor.set_selected_distance(fit_distance.value / 100.0, fit_radius.value)


func _on_fit_reset_distance() -> void:
	_fit_editor.reset_selected_distance()


func _on_fit_reset_radius() -> void:
	_updating_fit_controls = true
	fit_radius.value = 0.08
	fit_radius_slider.value = 0.08
	_updating_fit_controls = false
	_apply_fit_control_values()


func _on_fit_reset_all() -> void:
	_fit_editor.reset_all()


func _on_fit_auto_clearance_changed(value: float) -> void:
	if _updating_fit_controls:
		return
	_updating_fit_controls = true
	fit_auto_clearance.value = value
	fit_auto_clearance_slider.value = value
	_updating_fit_controls = false


func _on_fit_reset_auto_clearance() -> void:
	fit_auto_clearance.value = 0.5


func _on_fit_auto_adjust() -> void:
	fit_auto_adjust.disabled = true
	var selected_surface := _fit_editor.get_selected_surface()
	if selected_surface.is_empty():
		fit_status.text = "Contact-fitting all surfaces with %.1f mm clearance..." % [
			fit_auto_clearance.value * 10.0]
	else:
		fit_status.text = "Contact-fitting selected surface with %.1f mm clearance..." % [
			fit_auto_clearance.value * 10.0]
	await get_tree().process_frame
	if selected_surface.is_empty():
		_fit_editor.auto_adjust(fit_auto_clearance.value / 100.0)
	else:
		_fit_editor.fit_selected_surface(fit_auto_clearance.value / 100.0)
	fit_auto_adjust.disabled = false


func _on_fit_surface_selected(index: int) -> void:
	if _updating_fit_controls:
		return
	if index == 0:
		_fit_editor.clear_surface_selection()
		return
	var items := _fit_editor.get_clothing_surfaces()
	var surface_index := index - 1
	if surface_index < 0 or surface_index >= items.size():
		return
	_fit_editor.select_surface(
			items[surface_index]["mesh_key"], items[surface_index]["surface_index"])


func _refresh_surface_selector() -> void:
	fit_surface_selector.clear()
	fit_surface_selector.add_item("All surfaces")
	var items := _fit_editor.get_clothing_surfaces()
	for item in items:
		fit_surface_selector.add_item(item["name"])
	fit_surface_selector.select(0)
	if items.is_empty():
		fit_status.text = "No clothing surfaces found"
	else:
		var names := PackedStringArray()
		for item in items:
			names.append("\"%s\"" % item["name"])
		fit_status.text = "Surfaces: " + ", ".join(names)


func _sync_surface_selector_to_selection(label: String) -> void:
	var parts := label.split(" · ", false)
	if parts.size() < 2:
		fit_surface_selector.selected = -1
		return
	var selected_mesh := parts[0]
	var selected_surface := parts[1].trim_prefix("surface ").to_int()
	var items := _fit_editor.get_clothing_surfaces()
	for i in items.size():
		if items[i]["mesh_key"] == selected_mesh and items[i]["surface_index"] == selected_surface:
			fit_surface_selector.selected = i + 1
			return
	fit_surface_selector.select(0)


func _on_fit_save() -> void:
	_fit_editor.save_profile()


func _on_fit_status_changed(message: String) -> void:
	fit_status.text = message


func _set_fit_controls_enabled(enabled: bool) -> void:
	fit_distance.editable = enabled
	fit_radius.editable = enabled
	fit_distance_slider.editable = enabled
	fit_radius_slider.editable = enabled
	fit_reset_distance.disabled = not enabled
	fit_reset_radius.disabled = not enabled


func _on_start_pressed() -> void:
	var body: Dictionary = BODIES[_body_index]
	PlayerProfile.set_profile(
			body["kind_id"], _hair_slot.current_id(), _facial_hair_slot.current_id(),
			_eyebrows_slot.current_id(), _hair_color, _eye_color, _skin_tone)
	get_tree().change_scene_to_file(NEXT_SCENE)


func _rebuild_preview() -> void:
	if is_instance_valid(_preview_body):
		_preview_body.queue_free()
	var body: Dictionary = BODIES[_body_index]
	var scene := load(body["model_path"]) as PackedScene
	_preview_body = scene.instantiate() as Node3D
	preview_root.add_child(_preview_body)
	_hide_builtin_eyebrows()
	_apply_skin_tone()
	_apply_eye_color()
	for slot in [_hair_slot, _facial_hair_slot, _eyebrows_slot]:
		slot.preview = _rebuild_cosmetic(slot)
	_rebuild_outfit()


## TEMPORARY debug preview - see the OUTFITS/OUTFIT_PATHS doc comment. Each body/outfit pair uses
## Baseline preview: keep the complete body and layer clothing over it. Outfit-authored duplicate
## skin primitives are hidden so only the selected base character supplies skin.
func _rebuild_outfit() -> void:
	if is_instance_valid(_fit_editor):
		_fit_editor.clear_outfit()
	edit_fit_button.disabled = true
	if is_instance_valid(_preview_outfit):
		_preview_outfit.queue_free()
		_preview_outfit = null
	var body: Dictionary = BODIES[_body_index]
	var base_mesh := _preview_body.find_child(
			String(body["mesh_name"]), true, false) as MeshInstance3D
	var path: String = OUTFIT_PATHS.get(body["kind_id"], {}).get(_outfit_id, "")
	if base_mesh:
		_apply_body_debug_material(base_mesh)
	if path.is_empty():
		edit_fit_button.set_pressed_no_signal(false)
		fit_panel.visible = false
		_fit_editor.set_editing(false)
		return
	var resource := load(path)
	if not resource is PackedScene:
		return
	var instance := (resource as PackedScene).instantiate() as Node3D
	if instance == null:
		return
	preview_root.add_child(instance)
	_preview_outfit = instance
	_apply_outfit_materials(instance)
	_fit_editor.load_outfit(
			instance, base_mesh, String(body["kind_id"]), _outfit_id,
			_outfit_debug_colors and _show_outfit_clipping)
	_refresh_surface_selector()
	edit_fit_button.disabled = not _fit_editor.has_outfit()


func _apply_body_debug_material(
	mesh_instance: MeshInstance3D,
) -> void:
	if not _outfit_debug_colors:
		mesh_instance.material_override = null
		return
	if _show_outfit_clipping and not _fit_editor.get_selected_surface().is_empty():
		# The rebuilt body mesh uses its authored material with per-vertex debug
		# tinting, allowing unaffected body areas to remain visually unchanged.
		mesh_instance.material_override = null
		return
	var material := _make_debug_material(
			Color.WHITE if _show_outfit_clipping else Color(0.9, 0.04, 0.04))
	material.vertex_color_use_as_albedo = _show_outfit_clipping
	mesh_instance.material_override = material


## Outfit meshes include duplicate exposed skin. Hide those surfaces in this baseline so the
## complete base body is the only skin source; color only clothing blue in diagnostic mode.
func _apply_outfit_materials(root: Node3D) -> void:
	var hidden_skin_material := ShaderMaterial.new()
	hidden_skin_material.shader = DISCARD_SURFACE_SHADER
	var clothes_material := _make_debug_material(
			Color.WHITE if _show_outfit_clipping else Color(0.03, 0.18, 0.95))
	clothes_material.vertex_color_use_as_albedo = _show_outfit_clipping
	var selected := _fit_editor.get_selected_surface()
	var filter_debug_surface := _show_outfit_clipping and not selected.is_empty()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh_key := String(root.get_path_to(mesh_instance))
		for surface_index in mesh_instance.mesh.get_surface_count():
			var source_material := mesh_instance.mesh.surface_get_material(surface_index)
			var material_name := ""
			if source_material != null:
				material_name = source_material.resource_name.to_lower()
			var is_skin := "regular_male" in material_name or "regular_female" in material_name
			if is_skin:
				mesh_instance.set_surface_override_material(surface_index, hidden_skin_material)
			elif _outfit_debug_colors:
				var is_selected: bool = (
					not filter_debug_surface
					or (
						selected["mesh_key"] == mesh_key
						and selected["surface_index"] == surface_index
					)
				)
				mesh_instance.set_surface_override_material(
						surface_index, clothes_material if is_selected else null)
			else:
				mesh_instance.set_surface_override_material(surface_index, null)


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.9
	return material


## The imported body ships its own permanently-visible, never-tinted "Eyebrows" sibling mesh (same
## T_Hair_1_BaseColor.png as our own attachable eyebrows) - it's what was actually showing through
## as a second, uncolored eyebrow, not the skin texture. Removing it once is the real fix.
func _hide_builtin_eyebrows() -> void:
	var builtin := _preview_body.find_child("Eyebrows", true, false)
	if builtin != null:
		builtin.queue_free()


func _apply_eye_color() -> void:
	if not is_instance_valid(_preview_body):
		return
	var body: Dictionary = BODIES[_body_index]
	var mesh_instance := _preview_body.find_child("Eyes", true, false) as MeshInstance3D
	if mesh_instance == null:
		return
	var suffix := "Brown"
	for color in EYE_COLORS:
		if color["id"] == _eye_color:
			suffix = String(color["label"])
			break
	var texture := load(String(body["dir"]) + "T_Eye_" + suffix + ".png") as Texture2D
	for i in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_active_material(i)
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).albedo_texture = texture


func _apply_skin_tone() -> void:
	if not is_instance_valid(_preview_body):
		return
	var body: Dictionary = BODIES[_body_index]
	var mesh_instance := _preview_body.find_child(
			String(body["mesh_name"]), true, false) as MeshInstance3D
	if mesh_instance == null:
		return
	var texture := load(String(body["base_texture"])) as Texture2D
	var tint := Color.WHITE
	for tone in SKIN_TONES:
		if tone["id"] == _skin_tone:
			tint = tone["tint"]
			break
	for i in mesh_instance.mesh.get_surface_count():
		# mesh.surface_get_material(), not get_active_material(): the active material can
		# currently be the outfit head-mask shader rather than the tintable base material.
		var material := mesh_instance.mesh.surface_get_material(i)
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).albedo_texture = texture
			(material as BaseMaterial3D).albedo_color = tint


## Frees slot's previous attachment and attaches its current selection to the loaded body's Head
## bone, re-expressed in the bone's own rest-relative space (the mesh is baked in world-space, not
## local-to-bone) so BoneAttachment3D carries it correctly through animated poses too, not just
## cancel translation at rest.
func _rebuild_cosmetic(slot: Slot) -> BoneAttachment3D:
	if is_instance_valid(slot.preview):
		slot.preview.queue_free()
	var item := slot.current_item()
	if String(item["path"]).is_empty() or not is_instance_valid(_preview_body):
		return null
	var skeleton := _preview_body.find_child("Skeleton3D", true, false) as Skeleton3D
	var bone_idx := skeleton.find_bone(&"Head") if skeleton != null else -1
	if bone_idx < 0:
		return null
	var resource := load(String(item["path"]))
	if not resource is PackedScene:
		return null
	var instance := (resource as PackedScene).instantiate() as Node3D
	if instance == null:
		return null
	var tint := Color.WHITE
	for color in HAIR_COLORS:
		if color["id"] == _hair_color:
			tint = color["tint"]
			break
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(i)
			if material is BaseMaterial3D:
				(material as BaseMaterial3D).albedo_color = tint
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = &"Head"
	skeleton.add_child(attachment)
	var kind_id: String = BODIES[_body_index]["kind_id"]
	var correction_y: float = HAIR_Y_CORRECTIONS.get(kind_id, {}).get(item["id"], 0.0)
	instance.transform = (skeleton.get_bone_global_rest(bone_idx).affine_inverse()
			* Transform3D(Basis.IDENTITY, Vector3(0, correction_y, 0)))
	attachment.add_child(instance)
	return attachment


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed and _fit_editor.pick(button_event.position):
				_orbiting = false
				get_viewport().set_input_as_handled()
			else:
				_orbiting = button_event.pressed
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(
					_orbit_distance - ZOOM_STEP, MIN_ORBIT_DISTANCE, MAX_ORBIT_DISTANCE)
			_update_orbit_camera()
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(
					_orbit_distance + ZOOM_STEP, MIN_ORBIT_DISTANCE, MAX_ORBIT_DISTANCE)
			_update_orbit_camera()
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch gestures report a scale around 1.0. Dividing the orbit
		# distance makes pinch-out magnify the character and pinch-in zoom away.
		var magnify_event := event as InputEventMagnifyGesture
		_orbit_distance = clampf(
				_orbit_distance / maxf(magnify_event.factor, 0.01),
				MIN_ORBIT_DISTANCE,
				MAX_ORBIT_DISTANCE)
		_update_orbit_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * ORBIT_SENS
		_orbit_pitch = clampf(
				_orbit_pitch + motion.relative.y * ORBIT_SENS, -deg_to_rad(60.0), deg_to_rad(60.0))
		_update_orbit_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_P:
			_toggle_face_focus()


## P toggles between the default full-body framing and a tight close-up on the face, so hair/
## beard/eyebrow colors and placement can be checked without fighting the scroll-wheel zoom.
func _toggle_face_focus() -> void:
	_face_focused = not _face_focused
	_orbit_target = FACE_ORBIT_TARGET if _face_focused else DEFAULT_ORBIT_TARGET
	_orbit_distance = FACE_ORBIT_DISTANCE if _face_focused else DEFAULT_ORBIT_DISTANCE
	_update_orbit_camera()


func _update_orbit_camera() -> void:
	if is_instance_valid(_camera_tween):
		_camera_tween.kill()
		_camera_tween = null
	var horizontal := cos(_orbit_pitch)
	var direction := Vector3(
			sin(_orbit_yaw) * horizontal, sin(_orbit_pitch), cos(_orbit_yaw) * horizontal)
	camera.global_position = _orbit_target + direction * _orbit_distance
	camera.look_at(_orbit_target)
