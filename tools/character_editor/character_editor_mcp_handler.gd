class_name CharacterEditorMcpHandler
extends RefCounted

## MCP live-bridge diagnostic/automation handlers - the _mcp_* functions
## _on_mcp_debugger_message dispatches to, plus the CLI automation-args
## entry point and the held-object penetration check. Holds a back-
## reference to the main CharacterEditor (see character_editor.gd) since
## these all need to read/drive its live UI/scene state - extracted purely
## to keep character_editor.gd under a manageable size, not because this
## logic is actually independent of it.

var editor: CharacterEditor


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func _run_automation_args() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if "=" in argument:
			options[argument.get_slice("=", 0)] = argument.get_slice("=", 1)
	if options.is_empty():
		return
	if options.has("pose"):
		editor._pose_io_handler._load_pose_from_path(options["pose"], true)
	if options.has("animation"):
		var animation_name := StringName(options["animation"])
		editor._ui_setup_handler._select_animation_in_ui(animation_name)
		editor._ui_setup_handler._set_animation(animation_name)
	# Held-object options (object/attachment/object_position/etc.) are
	# meaningless - and _held_object is null - for characters that don't
	# support held objects (see MIXAMO_CHARACTERS).
	if editor.body.supports_held_object:
		if options.has("attachment_index"):
			editor._attachment_handler.select(int(options["attachment_index"]))
		if options.has("object"):
			editor._load_object(options["object"], true)
		if options.has("attachment"):
			editor._ui_setup_handler._set_attachment_bone(StringName(options["attachment"]), false)
			editor._ui_setup_handler._select_attachment_in_ui(editor._attachment_bone)
		var position_option: String = options.get(
				"object_position", options.get("flashlight_position", ""))
		if not position_option.is_empty():
			editor._held_object.position = _parse_vector3_option(
					position_option, editor._held_object.position)
		var rotation_option: String = options.get(
				"object_rotation", options.get("flashlight_rotation", ""))
		if not rotation_option.is_empty():
			editor._held_object.rotation_degrees = _parse_vector3_option(
					rotation_option, editor._held_object.rotation_degrees)
		if options.has("object_scale"):
			var object_scale := float(options["object_scale"])
			editor._held_object.scale = Vector3.ONE * object_scale
	if options.has("bones"):
		for bone_override: String in String(options["bones"]).split(";"):
			var separator := bone_override.find(":")
			if separator <= 0:
				continue
			var bone_name := StringName(bone_override.left(separator))
			if editor.body.skeleton.find_bone(bone_name) >= 0:
				editor._modifier.set_bone_rotation(bone_name, _parse_vector3_option(
						bone_override.substr(separator + 1),
						editor._modifier.get_bone_rotation(bone_name)))
	editor._bone_controls_handler._sync_bone_controls()
	if editor.body.supports_held_object and is_instance_valid(editor._held_object):
		editor._gizmo_handler._sync_object_controls()
	editor._gizmo_handler._refresh_skeleton()
	if options.has("view"):
		var view_index: int = {"full": 0, "hand": 1, "isolated": 2}.get(
				options["view"], 0)
		editor.view_picker.select(view_index)
		editor._camera_handler._on_view_selected(view_index)
	if options.get("comparison", "false") == "true":
		editor._ui_setup_handler._on_editor_mode_pressed(true)
	if options.has("panel_size"):
		var panel_size_components := String(options["panel_size"]).split(",")
		if panel_size_components.size() >= 2:
			editor._panel_user_layout = true
			editor.panel.size = Vector2(
					float(panel_size_components[0]), float(panel_size_components[1]))
			editor._expanded_panel_size = editor.panel.size
			editor._ui_setup_handler._clamp_panel_to_viewport(
					editor.get_viewport().get_visible_rect().size / editor._ui_scale)
			editor._ui_setup_handler._update_panel_dependent_layout()
			editor._ui_setup_handler._update_panel_resize_handle()
	if options.get("panel_collapsed", "false") == "true" and not editor._panel_collapsed:
		editor._ui_setup_handler._on_collapse_panel_pressed()
	if options.get("root_motion", "false") == "true":
		editor.root_motion_toggle.set_pressed_no_signal(true)
		editor._camera_handler._on_root_motion_toggled(true)
	if options.has("time"):
		var preview_time := float(options["time"])
		editor.body.anim_player.seek(preview_time, true)
		editor._comparison.seek(preview_time)
		editor.body.anim_player.pause()
		editor._comparison.set_paused(true)
		editor.pause_toggle.set_pressed_no_signal(true)
		editor._gizmo_handler._refresh_skeleton()
	if options.has("bone"):
		var bone_name := StringName(options["bone"])
		if editor.body.skeleton.find_bone(bone_name) >= 0:
			editor._gizmo_handler._select_bone(bone_name, true)
	if options.has("pick"):
		var pick_components := String(options["pick"]).split(",")
		if pick_components.size() >= 2:
			for _frame in 2:
				await editor.get_tree().process_frame
			var pick_position := Vector2(
					float(pick_components[0]), float(pick_components[1]))
			var previous_bone := editor._selected_bone
			var pick_event := InputEventMouseButton.new()
			pick_event.position = pick_position
			pick_event.button_index = MOUSE_BUTTON_LEFT
			pick_event.pressed = true
			pick_event.double_click = true
			editor._input(pick_event)
			if editor._selected_bone != previous_bone:
				print("CHARACTER_EDITOR_PICKED:", editor._selected_bone)
	if options.has("hand_openness") and not editor._hand_helper_side.is_empty():
		var openness := clampf(float(options["hand_openness"]), -1.0, 1.0)
		if is_instance_valid(editor._hand_openness_slider):
			editor._hand_openness_slider.set_value_no_signal(openness)
		editor._bone_controls_handler._on_hand_openness_changed(openness)
	if options.has("angle"):
		if editor._joint_focus_active:
			var distance := editor._focused_camera_offset.length()
			match options["angle"]:
				"right":
					editor._focused_camera_offset = Vector3.RIGHT * distance
				"left":
					editor._focused_camera_offset = Vector3.LEFT * distance
				"top":
					editor._focused_camera_offset = Vector3(0.0, 0.85, 0.5).normalized() * distance
				"bottom":
					editor._focused_camera_offset = Vector3(0.0, -0.85, 0.5).normalized() * distance
				"back":
					editor._focused_camera_offset = Vector3(0.0, 0.0, -distance)
				_:
					editor._focused_camera_offset = Vector3(0.0, 0.0, distance)
			editor._camera_handler._update_focused_camera()
		else:
			match options["angle"]:
				"right": editor._orbit_yaw = PI * 0.5
				"left": editor._orbit_yaw = -PI * 0.5
				"back": editor._orbit_yaw = PI
				"top": editor._orbit_pitch = 1.2
				"bottom": editor._orbit_pitch = -1.2
				_: editor._orbit_yaw = 0.0
			editor._camera_handler._update_orbit_camera()
	var requested_stage := CharacterEditorStageHandler.Stage.ANIMATION
	if options.get("stage", "") == "rig":
		requested_stage = CharacterEditorStageHandler.Stage.RIG
	if options.has("pose"):
		requested_stage = CharacterEditorStageHandler.Stage.REVIEW
	if (options.has("object") or options.has("attachment_index")
			or options.has("attachment") or options.has("object_position")
			or options.has("object_rotation") or options.has("object_scale")):
		requested_stage = CharacterEditorStageHandler.Stage.ATTACHMENTS
	if (options.has("bone") or options.has("bones")
			or options.has("hand_openness") or options.has("pick")):
		requested_stage = CharacterEditorStageHandler.Stage.POSE
	if options.get("stage", "") == "rig":
		requested_stage = CharacterEditorStageHandler.Stage.RIG
	editor._stage_handler.set_stage(requested_stage, true)
	if options.has("capture"):
		for _frame in 3:
			await editor.get_tree().process_frame
		var result := await editor._pose_io_handler._capture_pose_image(options["capture"],
				options.get("capture_ui", "false") == "true")
		if result != OK:
			push_error("Pose capture failed: %s" % error_string(result))
		editor.get_tree().quit()
	elif options.has("dump_bones"):
		for _frame in 3:
			await editor.get_tree().process_frame
		_dump_bone_poses(String(options["dump_bones"]))
		editor.get_tree().quit()


func _build_bone_pose_dump(name_filter: String) -> Dictionary:
	var poses := {}
	for bone_index in editor.body.skeleton.get_bone_count():
		var bone_name := editor.body.skeleton.get_bone_name(bone_index)
		if not name_filter.is_empty() and name_filter not in String(bone_name):
			continue
		var pose := editor.body.skeleton.get_bone_pose(bone_index)
		var global_pose := editor.body.skeleton.get_bone_global_pose(bone_index)
		poses[String(bone_name)] = {
			"parent": editor.body.skeleton.get_bone_parent(bone_index),
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
	if editor.body == null and message not in [
			"set_character", "capture_screenshot", "import_asset_result",
			"test_import_character"]:
		editor._load_character(editor.DEFAULT_CHARACTER_KIND)
	match message:
		"request_pose_dump":
			var name_filter := String(data[0]) if data.size() > 0 else ""
			var poses := _build_bone_pose_dump(name_filter)
			EngineDebugger.send_message("mcp:pose_dump", [JSON.stringify(poses)])
		"set_bone_rotation":
			_mcp_set_bone_rotation(data)
		"set_object_transform":
			_mcp_set_object_transform(data)
		"capture_screenshot":
			var include_ui: bool = bool(data[1]) if data.size() > 1 else false
			_mcp_capture_screenshot(String(data[0]), include_ui)
		"set_view":
			_mcp_set_view(String(data[0]))
		"select_bone":
			_mcp_select_bone(String(data[0]))
		"set_camera_angle":
			_mcp_set_camera_angle(String(data[0]))
		"load_pose":
			_mcp_load_pose(String(data[0]))
		"save_pose":
			_mcp_save_pose(String(data[0]))
		"set_animation":
			_mcp_set_animation(String(data[0]))
		"set_hand_openness":
			_mcp_set_hand_openness(float(data[0]))
		"pick_bone":
			_mcp_pick_bone(float(data[0]), float(data[1]))
		"get_object_state":
			_mcp_get_object_state()
		"check_penetration":
			_mcp_check_penetration()
		"set_mesh_visible":
			_mcp_set_mesh_visible(bool(data[0]))
		"set_show_bones":
			_mcp_set_show_bones(bool(data[0]))
		"set_character":
			_mcp_set_character(String(data[0]))
		"import_asset_result":
			var parsed = JSON.parse_string(String(data[0]) if data.size() > 0 else "{}")
			editor._pending_import_result = parsed if typeof(parsed) == TYPE_DICTIONARY else (
					{"ok": false, "error": "Malformed import result"})
		"test_import_character":
			_mcp_test_import_character(String(data[0]))
		"test_button_click":
			# Kept permanently (like test_import_character) - emits the node's
			# real "pressed" signal instead of calling its handler function
			# directly, so it actually exercises whatever wiring connects that
			# signal to that handler. Found a real, otherwise invisible class
			# of bug this way: several buttons here were connected via
			# character_editor.tscn's own [connection] resource data (made by
			# dragging a connection in the Godot editor's Node dock), not by
			# any `.connect()` call in GDScript - so grepping the scripts for
			# a button's name never revealed anything wrong, and calling its
			# handler function directly (as every other diagnostic in this
			# dispatcher does) always "worked" regardless of whether the
			# actual signal was connected to anything at all.
			editor.get_node(String(data[0])).emit_signal("pressed")
			EngineDebugger.send_message("mcp:command_result", [JSON.stringify({
				"ok": true, "result": editor.status_label.text,
			})])
		"test_popup_item_click":
			# Same reasoning as test_button_click, for MenuButton/PopupMenu
			# item selections specifically - those fire id_pressed(id), not
			# the zero-argument "pressed" test_button_click already covers,
			# so they need their own emit_signal call with that argument.
			# node_path names the MenuButton (its PopupMenu is created at
			# runtime via get_popup(), not a distinct scene node/path).
			var menu_button: MenuButton = editor.get_node(String(data[0]))
			menu_button.get_popup().emit_signal("id_pressed", int(data[1]))
			EngineDebugger.send_message("mcp:command_result", [JSON.stringify({
				"ok": true, "result": editor.status_label.text,
			})])
		"test_retarget_parity":
			_mcp_test_retarget_parity(
					String(data[0]), StringName(data[1]), StringName(data[2]), String(data[3]))
		_:
			return false
	return true


## Exercises the exact same _on_import_file_selected() the "Import
## Character..." button's file dialog callback calls - not _import_character
## directly, which would skip the spinner/button-disable state _on_
## import_file_selected itself sets up around it - see _mcp_pick_bone's
## doc comment for why this isn't awaited directly from the dispatcher.
func _mcp_test_import_character(source_path: String) -> void:
	var characters_before := editor._custom_characters.size()
	editor._import_mode = editor.ImportMode.CHARACTER
	await editor._import_handler._on_import_file_selected(source_path)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify({
		"ok": editor._custom_characters.size() > characters_before,
		"result": editor.status_label.text,
	})])


## Regression check for the player-swappable-skin plan's Phase 1 (see
## CURRENT_TASK.md): bakes source_clip from source_glb_path onto the
## currently-loaded character's skeleton via HumanoidRetargeter +
## build_bone_map_config (using manifest_path's persisted humanoid_map),
## then diffs every track numerically against gameplay_clip - the same
## clip already baked into editor.body's own "moves"/equivalent library by
## whatever the currently-loaded character's normal retargeting path is.
## Bit-for-bit (well within floating-point tolerance) equality here is the
## actual proof that HumanoidRetargeter can replace a character's own
## inline retargeting without changing what players see - not just "looks
## right in Compare mode".
func _mcp_test_retarget_parity(
		source_glb_path: String, source_clip: StringName, gameplay_clip: StringName,
		manifest_path: String) -> void:
	var result := {"ok": false}
	var reference_anim: Animation = editor.body.anim_player.get_animation_library(
			&"moves").get_animation(gameplay_clip)
	if reference_anim == null:
		result["error"] = (
				"gameplay_clip %s not found in the loaded character's moves library" % gameplay_clip)
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(result)])
		return
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text()) if manifest_file else {}
	var humanoid_map: Dictionary = manifest.get("humanoid_map", {})
	var source_instance: Node = (load(source_glb_path) as PackedScene).instantiate()
	var src_skeleton: Skeleton3D = source_instance.find_child("Skeleton3D", true, false)
	var src_ap: AnimationPlayer = source_instance.find_child("AnimationPlayer", true, false)
	var src_animation: Animation = null
	for lib_name in src_ap.get_animation_library_list():
		var lib := src_ap.get_animation_library(lib_name)
		if lib.has_animation(source_clip):
			src_animation = lib.get_animation(source_clip)
			break
	if src_animation == null:
		source_instance.free()
		result["error"] = "%s not found in %s" % [source_clip, source_glb_path]
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(result)])
		return
	const HUMANOID_RETARGETER := preload("res://tools/character_editor/humanoid_retargeter.gd")
	var config := HUMANOID_RETARGETER.build_bone_map_config(PlayerBody.BONE_MAP, humanoid_map)
	var new_anim: Animation = HUMANOID_RETARGETER.retarget_clip(
			src_skeleton, src_animation, editor.body.skeleton, config, false)
	source_instance.free()
	var diff := _diff_animations(reference_anim, new_anim)
	diff["bone_map_entries"] = config.bone_map.size()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify({
		"ok": true, "result": diff,
	})])


func _diff_animations(reference_anim: Animation, new_anim: Animation) -> Dictionary:
	var ref_bones := _tracked_bone_names(reference_anim)
	var new_bones := _tracked_bone_names(new_anim)
	var max_rot_diff := 0.0
	var max_pos_diff := 0.0
	var mismatches := 0
	var compared := 0
	var per_bone_max_rot_diff: Dictionary = {}
	for bone_name: String in ref_bones:
		if not new_bones.has(bone_name):
			mismatches += 1
			continue
		var ref_track: int = ref_bones[bone_name]
		var new_track: int = new_bones[bone_name]
		var key_count := reference_anim.track_get_key_count(ref_track)
		if key_count != new_anim.track_get_key_count(new_track):
			mismatches += 1
			continue
		for k in key_count:
			compared += 1
			if reference_anim.track_get_type(ref_track) == Animation.TYPE_ROTATION_3D:
				var ref_val: Quaternion = reference_anim.track_get_key_value(ref_track, k)
				var new_val: Quaternion = new_anim.track_get_key_value(new_track, k)
				var diff: float = ref_val.angle_to(new_val)
				max_rot_diff = maxf(max_rot_diff, diff)
				per_bone_max_rot_diff[bone_name] = maxf(
						per_bone_max_rot_diff.get(bone_name, 0.0), diff)
				if diff > 0.001:
					mismatches += 1
			else:
				var ref_val: Vector3 = reference_anim.track_get_key_value(ref_track, k)
				var new_val: Vector3 = new_anim.track_get_key_value(new_track, k)
				var diff: float = ref_val.distance_to(new_val)
				max_pos_diff = maxf(max_pos_diff, diff)
				if diff > 0.0001:
					mismatches += 1
	var worst_bones: Array = per_bone_max_rot_diff.keys()
	worst_bones.sort_custom(
			func(a, b): return per_bone_max_rot_diff[a] > per_bone_max_rot_diff[b])
	var worst_summary := {}
	for i in mini(8, worst_bones.size()):
		var name: String = worst_bones[i]
		worst_summary[name] = per_bone_max_rot_diff[name]
	return {
		"worst_bones_rot_diff_radians": worst_summary,
		# The caller wraps this under a top-level "ok": true, "result": {...}
		# - the MCP bridge client treats a top-level ok:false as the *call*
		# failing and discards the rest of the payload (confirmed the hard
		# way: a real mismatches>0 result came back as an opaque "Unknown
		# editor bridge error" with none of this data visible). The actual
		# parity verdict lives here as "parity_ok" instead.
		"parity_ok": mismatches == 0,
		"ref_bone_count": ref_bones.size(),
		"new_bone_count": new_bones.size(),
		"keys_compared": compared,
		"max_rot_diff_radians": max_rot_diff,
		"max_pos_diff_meters": max_pos_diff,
		"mismatches": mismatches,
	}


func _tracked_bone_names(anim: Animation) -> Dictionary:
	var result := {}
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		if path.get_subname_count() > 0:
			result[String(path.get_subname(0))] = t
	return result


## Copies source_path (from the native file dialog, an absolute OS path)
## into the project at dest_res_path and waits for the editor to import it -
## see pose_debugger_plugin.gd's _import_asset for why this has to be a
## round trip through the editor process rather than something this played
## scene can do on its own (only the editor can run Godot's importer).
func _request_import_asset(source_path: String, dest_res_path: String) -> Dictionary:
	if not EngineDebugger.is_active():
		return {"ok": false, "error": (
				"Import requires running inside the editor "
				+ "(Play the scene from the Godot editor, not a standalone build)")}
	editor._pending_import_result = {}
	EngineDebugger.send_message("mcp:import_asset_request", [source_path, dest_res_path])
	var start_msec := Time.get_ticks_msec()
	while editor._pending_import_result.is_empty() and (Time.get_ticks_msec() - start_msec) < 15000.0:
		await editor.get_tree().process_frame
	if editor._pending_import_result.is_empty():
		return {"ok": false, "error": "Timed out waiting for the editor to import the asset"}
	return editor._pending_import_result


func _mcp_set_character(kind: String) -> void:
	if not kind in editor.CHARACTER_KINDS and not editor._custom_characters.has(kind):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown character '%s' (expected %s, or a session-imported kind)" % [
						kind, ", ".join(editor.CHARACTER_KINDS)]})])
		return
	editor._load_character(kind)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Loaded %s" % editor.body.display_name})])


func _mcp_set_mesh_visible(visible: bool) -> void:
	for mesh_part in editor.body.meshes:
		mesh_part.visible = visible
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Mesh visibility set to %s" % visible})])


func _mcp_set_show_bones(enabled: bool) -> void:
	editor.show_bones_toggle.set_pressed_no_signal(enabled)
	editor._gizmo_handler._on_show_bones_toggled(enabled)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Show bones set to %s" % enabled})])


func _mcp_get_object_state() -> void:
	if not is_instance_valid(editor._held_object):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify({
			"ok": false,
			"error": "The current pose has no selected attachment",
			"attachments": editor._attachment_handler.serialize(),
		})])
		return
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify({
		"ok": true,
		"result": {
			"selected_attachment_index": editor._attachment_handler.selected_index,
			"attachments": editor._attachment_handler.serialize(),
			"object_scene": editor._current_object_path,
			"attachment_bone": String(editor._attachment_bone),
			"position": [
				editor._held_object.position.x, editor._held_object.position.y,
				editor._held_object.position.z],
			"rotation_degrees": [
				editor._held_object.rotation_degrees.x,
				editor._held_object.rotation_degrees.y,
				editor._held_object.rotation_degrees.z,
			],
			"scale": editor._held_object.scale.x,
			"world_position": [
				editor._held_object.global_position.x,
				editor._held_object.global_position.y,
				editor._held_object.global_position.z,
			],
		},
	})])


## Exact mesh-vs-mesh penetration check, not a bone-position approximation.
## The earlier capsule-based approach (bone segment + estimated radius) was
## verified geometrically correct but consistently failed to detect
## penetration that was visually obvious in screenshots - a stylized/
## armored glove's actual skinned surface bulges well beyond what a
## bone-position estimate can capture. This uses
## MeshInstance3D.bake_mesh_from_current_skeleton_pose() (Godot 4.4+) to
## read back the REAL currently-deformed hand mesh, and tests its triangles
## against the held object's real (rigid, unskinned) mesh triangles via
## Geometry3D.segment_intersects_triangle() - the standard edge-vs-triangle
## construction for exact triangle-triangle intersection, since Godot has
## no built-in tri-tri test. PhysicsServer3D shape queries are deliberately
## avoided: documented unreliable specifically in editor/@tool context
## (godotengine/godot#87429), which is exactly where this runs.
const _MAX_REPORTED_INTERSECTIONS := 25


func _mcp_check_penetration() -> void:
	var report := _build_penetration_report()
	if report.has("error"):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": report["error"]})])
		return
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": report})])


func _build_penetration_report() -> Dictionary:
	if not editor.body.supports_held_object:
		return {"error": (
				"%s has no held-object system to check penetration against"
				% editor.body.display_name)}
	if not is_instance_valid(editor._held_object):
		return {"error": "No held object is loaded"}
	if editor.body.meshes.is_empty():
		return {"error": "Character body mesh not found"}

	var object_triangles := []
	MeshPenetrationGeometry.collect_mesh_triangles(
			editor._held_object, object_triangles, AABB(), false)
	if object_triangles.is_empty():
		return {"error": "Held object has no mesh geometry to measure"}
	var object_aabb := MeshPenetrationGeometry.triangles_aabb(object_triangles).grow(0.03)

	# Bake and combine every mesh part - not every character is one single
	# skinned mesh the way PlayerBody's MotusMan rig is (Shambler's Mixamo
	# import is 11 separate parts), and a held object could plausibly clip
	# any of them.
	var body_triangles := []
	for mesh_part in editor.body.meshes:
		var baked: ArrayMesh = mesh_part.bake_mesh_from_current_skeleton_pose()
		MeshPenetrationGeometry.append_mesh_triangles(
				baked, mesh_part.global_transform, body_triangles, object_aabb, true)

	var intersections := []
	for body_tri in body_triangles:
		for object_tri in object_triangles:
			var hit_point = MeshPenetrationGeometry.triangle_intersection_point(body_tri, object_tri)
			if hit_point != null:
				intersections.append([hit_point.x, hit_point.y, hit_point.z])
				break
		if intersections.size() >= _MAX_REPORTED_INTERSECTIONS:
			break

	# Edge-vs-triangle crossing tests (above) miss full containment: if the
	# object is small enough to sit entirely inside the hand mesh's volume,
	# none of its edges ever cross the hand's surface, so the crossing test
	# alone reports zero intersections despite genuine, deep overlap.
	# Confirmed this is a real, not theoretical, case: an object placed dead
	# center on the attachment bone (guaranteed inside the wrist) produced
	# zero crossings and vanished entirely from a screenshot at that pose.
	# Ray-cast from each unique object vertex and count triangle crossings -
	# odd count means the point is inside the body mesh (even-odd rule).
	var unique_object_vertices := MeshPenetrationGeometry.unique_triangle_vertices(object_triangles)
	var contained_points := []
	if intersections.size() < _MAX_REPORTED_INTERSECTIONS:
		# object_aabb is what body_triangles was filtered against, so its
		# diagonal is already long enough to cross clean out the far side.
		var ray_length := object_aabb.size.length()
		for vertex in unique_object_vertices:
			if MeshPenetrationGeometry.point_inside_triangles(vertex, body_triangles, ray_length):
				contained_points.append([vertex.x, vertex.y, vertex.z])
				if intersections.size() + contained_points.size() >= _MAX_REPORTED_INTERSECTIONS:
					break

	return {
		"any_penetrating": not intersections.is_empty() or not contained_points.is_empty(),
		"surface_crossing_count": intersections.size(),
		"surface_crossing_points": intersections,
		"contained_vertex_count": contained_points.size(),
		"contained_vertex_points": contained_points,
		"body_triangles_checked": body_triangles.size(),
		"object_triangles_checked": object_triangles.size(),
	}


func _mcp_load_pose(path: String) -> void:
	if not editor._pose_io_handler._load_pose_from_path(path, true):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Could not load pose from %s" % path})])
		return
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Pose loaded from %s" % path})])


func _mcp_save_pose(path: String) -> void:
	if not editor._pose_io_handler._save_pose_to_path(path):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Could not save pose to %s" % path})])
		return
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Pose saved to %s" % path})])


func _mcp_set_animation(animation_name: String) -> void:
	var name := StringName(animation_name)
	editor._ui_setup_handler._select_animation_in_ui(name)
	editor._ui_setup_handler._set_animation(name)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Animation set to %s" % animation_name})])


func _mcp_set_hand_openness(value: float) -> void:
	if editor._hand_helper_side.is_empty():
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "No hand is currently focused - select a hand-side bone first"})])
		return
	var openness := clampf(value, -1.0, 1.0)
	if is_instance_valid(editor._hand_openness_slider):
		editor._hand_openness_slider.set_value_no_signal(openness)
	editor._bone_controls_handler._on_hand_openness_changed(openness)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Hand openness set to %s" % openness})])


func _mcp_pick_bone(screen_x: float, screen_y: float) -> void:
	# Deliberately not awaited from _on_mcp_debugger_message - same reasoning
	# as _mcp_capture_screenshot: fire-and-forget so the message-capture
	# dispatch always gets an immediate bool back.
	for _frame in 2:
		await editor.get_tree().process_frame
	var previous_bone := editor._selected_bone
	var pick_event := InputEventMouseButton.new()
	pick_event.position = Vector2(screen_x, screen_y)
	pick_event.button_index = MOUSE_BUTTON_LEFT
	pick_event.pressed = true
	pick_event.double_click = true
	editor._input(pick_event)
	if editor._selected_bone != previous_bone:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": true, "result": "Picked bone %s" % editor._selected_bone})])
	else:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": true, "result": "No bone was picked at that position (selection unchanged)"})])


func _mcp_set_view(view_name: String) -> void:
	var view_index: int = {"full": 0, "hand": 1, "isolated": 2}.get(view_name, -1)
	if view_index < 0:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown view '%s' (expected full/hand/isolated)" % view_name})])
		return
	editor.view_picker.select(view_index)
	editor._camera_handler._on_view_selected(view_index)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "View set to %s" % view_name})])


func _mcp_select_bone(bone_name: String) -> void:
	if editor.body.skeleton.find_bone(StringName(bone_name)) < 0:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown bone %s" % bone_name})])
		return
	editor._gizmo_handler._select_bone(StringName(bone_name), true)
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Selected bone %s" % bone_name})])


func _mcp_set_camera_angle(angle_name: String) -> void:
	if not editor._joint_focus_active:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "No bone is focused - call select_bone first"})])
		return
	var distance := editor._focused_camera_offset.length()
	match angle_name:
		"right":
			editor._focused_camera_offset = Vector3.RIGHT * distance
		"left":
			editor._focused_camera_offset = Vector3.LEFT * distance
		"top":
			editor._focused_camera_offset = Vector3(0.0, 0.85, 0.5).normalized() * distance
		"bottom":
			editor._focused_camera_offset = Vector3(0.0, -0.85, 0.5).normalized() * distance
		"back":
			editor._focused_camera_offset = Vector3(0.0, 0.0, -distance)
		_:
			editor._focused_camera_offset = Vector3(0.0, 0.0, distance)
	editor._camera_handler._update_focused_camera()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Camera angle set to %s" % angle_name})])


func _mcp_set_bone_rotation(data: Array) -> void:
	var bone_name := StringName(data[0])
	if editor.body.skeleton.find_bone(bone_name) < 0:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Unknown bone %s" % bone_name})])
		return
	var rotation := Vector3(float(data[1]), float(data[2]), float(data[3]))
	# Same call the UI's per-axis sliders make (_on_bone_slider_changed) -
	# additive on top of the current animation pose, not a replacement.
	editor._modifier.set_bone_rotation(bone_name, rotation)
	editor._gizmo_handler._refresh_skeleton()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "%s rotation set to %s" % [bone_name, rotation]})])


func _mcp_set_object_transform(data: Array) -> void:
	var payload = JSON.parse_string(String(data[0]))
	if typeof(payload) != TYPE_DICTIONARY:
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "Malformed set_object_transform payload"})])
		return
	if payload.get("attachment_index") != null:
		editor._attachment_handler.select(int(payload["attachment_index"]))
	if not is_instance_valid(editor._held_object):
		EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
				{"ok": false, "error": "The current pose has no selected attachment"})])
		return
	# Same fields the UI's position/rotation/scale sliders write
	# (_on_object_position_changed etc.) - relative to the attachment bone.
	if payload.get("position") != null:
		var p: Array = payload["position"]
		editor._held_object.position = Vector3(p[0], p[1], p[2])
	if payload.get("rotation") != null:
		var r: Array = payload["rotation"]
		editor._held_object.rotation_degrees = Vector3(r[0], r[1], r[2])
	if payload.get("scale") != null:
		editor._held_object.scale = Vector3.ONE * float(payload["scale"])
	editor._gizmo_handler._refresh_skeleton()
	EngineDebugger.send_message("mcp:command_result", [JSON.stringify(
			{"ok": true, "result": "Object transform updated"})])


func _mcp_capture_screenshot(path: String, include_ui: bool) -> void:
	# Deliberately not awaited from _on_mcp_debugger_message - it's
	# uncertain whether EngineDebugger's message-capture dispatch correctly
	# handles a callback that returns a suspended coroutine instead of an
	# immediate bool, so this runs fire-and-forget instead and reports its
	# own result asynchronously once the capture actually completes.
	var result := await editor._pose_io_handler._capture_pose_image(path, include_ui)
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
