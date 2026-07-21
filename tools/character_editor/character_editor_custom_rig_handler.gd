class_name CharacterEditorCustomRigHandler
extends RefCounted

## "Build Custom Rig" mode on the Rig tab: click-to-place bones anywhere on
## an imported mesh, for skeleton shapes the fixed humanoid autorigger
## (CharacterEditorRigHandler._on_generate_rig_pressed,
## CharacterEditorAutorigger.generate) can't produce - quadrupeds, creatures
## with wings/tails/tentacles, anything that isn't roughly a T/A-pose human.
## Extracted out of character_editor_rig_handler.gd purely to keep that file
## under the lint line-count ceiling, not because this logic is actually
## independent of it - see _resolved_custom_kind()/_save_profile()/
## _save_generated_character() calls below, all reached through
## editor._rig_handler.
##
## _custom_rig_bones is the authoritative record of what's been placed -
## {name, parent, origin: Vector3} per bone, origin in the live skeleton's
## own local space, in placement order (always parent-before-child, since a
## bone can only be parented to one that's already placed). Skeleton3D has
## no API to rename or remove an individual bone once added, so any
## structural edit (delete, rename) rebuilds a fresh Skeleton3D from this
## list rather than trying to mutate the live one in place - see
## _rebuild_custom_rig_skeleton().

const AUTORIGGER := preload("res://tools/character_editor/character_editor_autorigger.gd")
const CATALOG := preload("res://characters/character_catalog.gd")

var editor: CharacterEditor
var active := false
var _custom_rig_bones: Array[Dictionary] = []
var _custom_rig_active_parent: StringName = &""
var _custom_rig_next_number := 1
var _custom_rig_builder: VBoxContainer
var _custom_rig_instructions: Label
var _custom_rig_active_parent_label: Label
var _custom_rig_bone_list: VBoxContainer
var _custom_rig_finish_button: Button
var _custom_rig_cancel_button: Button
var _build_custom_rig_button: Button
## Collected once per Build Custom Rig session (see _on_build_custom_rig_
## pressed) instead of on every click - re-extracting every surface's full
## vertex/index arrays from a dense character mesh on each click was the
## dominant cost behind clicks taking tens of seconds, dwarfing the actual
## raycast work.
var _cached_mesh_triangles: Array = []


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	_custom_rig_builder = editor.get_node(
			^"UI/Panel/PanelScroll/Margin/VBox/RigSection/CustomRigBuilder")
	_custom_rig_instructions = _custom_rig_builder.get_node(^"Instructions")
	_custom_rig_active_parent_label = _custom_rig_builder.get_node(^"ActiveParent")
	_custom_rig_bone_list = _custom_rig_builder.get_node(^"BoneScroll/BoneList")
	_custom_rig_finish_button = _custom_rig_builder.get_node(^"Actions/Finish")
	_custom_rig_cancel_button = _custom_rig_builder.get_node(^"Actions/Cancel")
	_build_custom_rig_button = editor.get_node(
			^"UI/Panel/PanelScroll/Margin/VBox/RigSection/ExternalActions/BuildCustomRig")
	_build_custom_rig_button.pressed.connect(_on_build_custom_rig_pressed)
	_custom_rig_finish_button.pressed.connect(_on_finish_custom_rig_pressed)
	_custom_rig_cancel_button.pressed.connect(_on_cancel_custom_rig_pressed)


## Called by CharacterEditorRigHandler.on_character_loaded() - the character
## (and its skeleton) being switched out from under us is about to be freed
## by _clear_loaded_character() regardless, so this only needs to drop our
## own in-progress bone-placement state/UI, not touch the old skeleton
## itself.
func on_character_loaded() -> void:
	if active:
		_custom_rig_bones.clear()
		_exit_custom_rig_mode()


## Enters Build Custom Rig mode. editor.body.skeleton is already a real,
## empty Skeleton3D at this point - see _create_posable_only_adapter() in
## character_editor.gd, which creates one for any imported character with no
## skeleton of its own - bones get added to it directly as the user clicks,
## with the gizmo drawing them immediately via the same code that already
## draws any other skeleton.
func _on_build_custom_rig_pressed() -> void:
	if editor.body == null:
		return
	active = true
	_custom_rig_bones.clear()
	_custom_rig_active_parent = &""
	_custom_rig_next_number = 1
	_cached_mesh_triangles.clear()
	MeshPenetrationGeometry.collect_mesh_triangles(
			editor.body.node, _cached_mesh_triangles, AABB(), false)
	editor.rig_external_actions.hide()
	_custom_rig_builder.show()
	_rebuild_custom_rig_bone_list_ui()
	_update_custom_rig_parent_label()
	_update_finish_button_state()
	editor.status_label.text = "Click the character's mesh to place bones"


## Called from character_editor.gd's _input() when a mesh-surface click
## lands during Build Custom Rig mode (see that file for the raycast itself -
## MeshPenetrationGeometry.raycast_mesh_surface). global_point is in world
## space; converted here to the skeleton's own local space, since that's
## what Skeleton3D.set_bone_rest()/get_bone_global_rest() work in.
func place_custom_bone(global_point: Vector3) -> void:
	if not active or editor.body == null:
		return
	var skeleton := editor.body.skeleton
	var origin := skeleton.global_transform.affine_inverse() * global_point
	var bone_name := _next_custom_bone_name()
	var parent_name := String(_custom_rig_active_parent)
	_custom_rig_bones.append({"name": bone_name, "parent": parent_name, "origin": origin})
	var bone_index := skeleton.get_bone_count()
	skeleton.add_bone(bone_name)
	if not parent_name.is_empty():
		var parent_index := skeleton.find_bone(parent_name)
		skeleton.set_bone_parent(bone_index, parent_index)
		var parent_origin: Vector3 = _find_custom_bone(parent_name)["origin"]
		skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, origin - parent_origin))
	else:
		skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, origin))
	_custom_rig_active_parent = StringName(bone_name)
	_rebuild_custom_rig_bone_list_ui()
	_update_custom_rig_parent_label()
	_update_finish_button_state()
	editor._gizmo_handler._rebuild_bone_gizmo()


## Called from character_editor.gd's _input() for every click while active -
## an existing bone's gizmo sets it as the active parent for the next
## placement (the user's chosen interaction model for supporting branching
## skeletons, e.g. one spine bone parenting two separately-placed wings,
## rather than only ever chaining off the most recent bone); anywhere else
## on the character's actual mesh surface places a new bone there. Reuses
## the same triangle-collection the held-object penetration checker uses
## (MeshPenetrationGeometry.collect_mesh_triangles) for the surface hit
## test, since neither PhysicsServer3D shape queries nor a dedicated
## collision layer exist for these tool-only meshes.
func handle_click(screen_position: Vector2) -> void:
	var bone_name := editor._gizmo_handler._bone_at_screen_position(screen_position)
	if bone_name != &"":
		on_bone_clicked(bone_name)
		return
	if _cached_mesh_triangles.is_empty():
		return
	var ray_origin := editor.camera.project_ray_origin(screen_position)
	var ray_direction := editor.camera.project_ray_normal(screen_position)
	var hit = MeshPenetrationGeometry.raycast_mesh_surface(
			_cached_mesh_triangles, ray_origin, ray_direction, editor.camera.far)
	if hit != null:
		place_custom_bone(hit)


func on_bone_clicked(bone_name: StringName) -> void:
	if not active:
		return
	_custom_rig_active_parent = bone_name
	_update_custom_rig_parent_label()


func _on_custom_bone_set_parent_pressed(bone_name: String) -> void:
	_custom_rig_active_parent = StringName(bone_name)
	_update_custom_rig_parent_label()


func _on_custom_bone_renamed(new_name: String, old_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == old_name:
		_rebuild_custom_rig_bone_list_ui()
		return
	if not _find_custom_bone(new_name).is_empty():
		editor.status_label.text = "A bone named %s already exists" % new_name
		_rebuild_custom_rig_bone_list_ui()
		return
	for entry: Dictionary in _custom_rig_bones:
		if entry["name"] == old_name:
			entry["name"] = new_name
		elif entry["parent"] == old_name:
			entry["parent"] = new_name
	if String(_custom_rig_active_parent) == old_name:
		_custom_rig_active_parent = StringName(new_name)
		_update_custom_rig_parent_label()
	_rebuild_custom_rig_skeleton()


func _on_custom_bone_position_changed(value: float, bone_name: String, axis: int) -> void:
	var entry := _find_custom_bone(bone_name)
	if entry.is_empty():
		return
	var origin: Vector3 = entry["origin"]
	origin[axis] = value
	entry["origin"] = origin
	_rebuild_custom_rig_skeleton()


## Only leaves (no other placed bone parented to this one) can be deleted -
## avoids needing to decide what happens to descendants (reparent to the
## grandparent? cascade-delete the whole subtree?) for what's meant to be a
## simple v1 correction tool, not a full rig-editing undo system.
func _on_custom_bone_delete_pressed(bone_name: String) -> void:
	if _custom_bone_has_children(bone_name):
		editor.status_label.text = (
				"Can't delete %s - it has child bones. Delete those first." % bone_name)
		return
	var index := -1
	for i in _custom_rig_bones.size():
		if _custom_rig_bones[i]["name"] == bone_name:
			index = i
			break
	if index < 0:
		return
	_custom_rig_bones.remove_at(index)
	if String(_custom_rig_active_parent) == bone_name:
		_custom_rig_active_parent = &""
	_rebuild_custom_rig_skeleton()
	_rebuild_custom_rig_bone_list_ui()
	_update_custom_rig_parent_label()
	_update_finish_button_state()


func _update_finish_button_state() -> void:
	_custom_rig_finish_button.disabled = _custom_rig_bones.is_empty()


func _custom_bone_has_children(bone_name: String) -> bool:
	for entry: Dictionary in _custom_rig_bones:
		if entry["parent"] == bone_name:
			return true
	return false


func _find_custom_bone(bone_name: String) -> Dictionary:
	for entry: Dictionary in _custom_rig_bones:
		if entry["name"] == bone_name:
			return entry
	return {}


func _next_custom_bone_name() -> String:
	var bone_name := "Bone%d" % _custom_rig_next_number
	_custom_rig_next_number += 1
	while not _find_custom_bone(bone_name).is_empty():
		bone_name = "Bone%d" % _custom_rig_next_number
		_custom_rig_next_number += 1
	return bone_name


## Skeleton3D has no API to rename or remove an individual bone once added
## (see this file's own doc comment on _custom_rig_bones), so any structural
## edit - a delete or a rename - rebuilds a fresh Skeleton3D from
## _custom_rig_bones instead: parents always precede children in that list
## (a bone can only ever be parented to one already placed), so a single
## forward pass is enough.
func _rebuild_custom_rig_skeleton() -> void:
	if editor.body == null:
		return
	var old_skeleton := editor.body.skeleton
	var new_skeleton := Skeleton3D.new()
	new_skeleton.name = &"Skeleton3D"
	old_skeleton.get_parent().add_child(new_skeleton)
	for entry: Dictionary in _custom_rig_bones:
		var bone_index := new_skeleton.get_bone_count()
		new_skeleton.add_bone(entry["name"])
		var parent_name: String = entry["parent"]
		if not parent_name.is_empty():
			var parent_index := new_skeleton.find_bone(parent_name)
			new_skeleton.set_bone_parent(bone_index, parent_index)
			var parent_origin: Vector3 = _find_custom_bone(parent_name)["origin"]
			new_skeleton.set_bone_rest(
					bone_index, Transform3D(Basis.IDENTITY, entry["origin"] - parent_origin))
		else:
			new_skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, entry["origin"]))
	old_skeleton.free()
	editor.body.skeleton = new_skeleton
	editor._gizmo_handler._rebuild_bone_gizmo()


func _rebuild_custom_rig_bone_list_ui() -> void:
	for child in _custom_rig_bone_list.get_children():
		child.free()
	for entry: Dictionary in _custom_rig_bones:
		_add_custom_bone_row(entry)


func _add_custom_bone_row(entry: Dictionary) -> void:
	var bone_name: String = entry["name"]
	var origin: Vector3 = entry["origin"]
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	_custom_rig_bone_list.add_child(row)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 6)
	row.add_child(header)
	var name_field := LineEdit.new()
	name_field.text = bone_name
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.text_submitted.connect(_on_custom_bone_renamed.bind(bone_name))
	header.add_child(name_field)
	var is_active_parent := String(_custom_rig_active_parent) == bone_name
	var set_parent_button := Button.new()
	set_parent_button.text = "Parent ✓" if is_active_parent else "Set Parent"
	set_parent_button.disabled = is_active_parent
	set_parent_button.custom_minimum_size.x = 90.0
	set_parent_button.pressed.connect(_on_custom_bone_set_parent_pressed.bind(bone_name))
	header.add_child(set_parent_button)
	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.disabled = _custom_bone_has_children(bone_name)
	delete_button.custom_minimum_size.x = 70.0
	delete_button.pressed.connect(_on_custom_bone_delete_pressed.bind(bone_name))
	header.add_child(delete_button)

	for axis in 3:
		var axis_row := HBoxContainer.new()
		axis_row.add_theme_constant_override(&"separation", 6)
		row.add_child(axis_row)
		var axis_label := Label.new()
		axis_label.custom_minimum_size.x = 20.0
		axis_label.text = "XYZ"[axis]
		axis_label.add_theme_color_override(&"font_color", editor.AXIS_COLORS[axis])
		axis_row.add_child(axis_label)
		var slider := HSlider.new()
		slider.min_value = -2.0
		slider.max_value = 2.0
		slider.step = 0.001
		slider.value = origin[axis]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_custom_bone_position_changed.bind(bone_name, axis))
		axis_row.add_child(slider)


func _update_custom_rig_parent_label() -> void:
	_custom_rig_active_parent_label.text = (
			"Parent: none (next bone becomes a root)" if _custom_rig_active_parent == &""
			else "Parent: %s" % _custom_rig_active_parent)


func _on_cancel_custom_rig_pressed() -> void:
	_custom_rig_bones.clear()
	_exit_custom_rig_mode()
	if editor.body == null:
		return
	var old_skeleton := editor.body.skeleton
	var new_skeleton := Skeleton3D.new()
	new_skeleton.name = &"Skeleton3D"
	old_skeleton.get_parent().add_child(new_skeleton)
	old_skeleton.free()
	editor.body.skeleton = new_skeleton
	editor._gizmo_handler._rebuild_bone_gizmo()


func _exit_custom_rig_mode() -> void:
	active = false
	_custom_rig_active_parent = &""
	_cached_mesh_triangles.clear()
	_custom_rig_builder.hide()
	editor.rig_external_actions.show()
	for child in _custom_rig_bone_list.get_children():
		child.free()


## Weights the mesh against the skeleton built up by place_custom_bone()
## calls and saves it - the custom-skeleton counterpart to
## CharacterEditorRigHandler._on_generate_rig_pressed(), reusing the exact
## same persistence calls (_save_profile/_save_generated_character) and
## info-dict shape so the result is indistinguishable from a
## humanoid-generated rig to every other consumer (Rig tab's own
## joint-adjustment UI included, once reloaded).
func _on_finish_custom_rig_pressed() -> void:
	if _custom_rig_bones.is_empty():
		editor.status_label.text = "Place at least one bone first"
		return
	var rig_handler: CharacterEditorRigHandler = editor._rig_handler
	var resolved_kind: String = rig_handler._resolved_custom_kind()
	var info: Dictionary = editor._custom_characters.get(resolved_kind, {})
	if info.is_empty():
		return
	var source_path: String = info.get("source_model_path", info.get("model_path", ""))
	if source_path.is_empty():
		editor.rig_summary.text = "The imported character has no source model path"
		return
	var output_path := CATALOG.generated_output_path(CATALOG.ensure_id(info), source_path)
	_custom_rig_finish_button.disabled = true
	editor.status_label.text = "Weighting mesh to the custom skeleton..."
	await editor.get_tree().process_frame
	var result: Dictionary = AUTORIGGER.generate_from_skeleton(
			editor.body.skeleton, source_path, output_path)
	_custom_rig_finish_button.disabled = false
	if not result.get("ok", false):
		editor.status_label.text = "Could not save custom rig · %s" % result.get("error", "unknown error")
		return
	info["source_model_path"] = source_path
	info["kind_id"] = resolved_kind
	info["model_path"] = result["path"]
	info["bone_prefix"] = null
	info["has_skin"] = true
	info["humanoid_map"] = result["humanoid_map"]
	info["generated_rig"] = true
	info["joint_positions"] = result["joint_positions"]
	info["default_joint_positions"] = result["joint_positions"].duplicate(true)
	editor._custom_characters[resolved_kind] = info
	rig_handler._save_profile(result["path"], result["humanoid_map"])
	rig_handler._save_generated_character(info)
	_custom_rig_bones.clear()
	_exit_custom_rig_mode()
	editor._load_character(editor._character_kind)
	editor.show_bones_toggle.set_pressed_no_signal(true)
	editor._gizmo_handler._on_show_bones_toggled(true)
	editor._stage_handler.set_stage(CharacterEditorStageHandler.Stage.RIG)
	editor.status_label.text = "Saved custom rig · %d bones" % int(result["bone_count"])
