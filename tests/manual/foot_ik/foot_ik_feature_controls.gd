extends Node
## Live feature switches and high-level tuning for the Foot IK preview only.

const PANEL_WIDTH := 390.0
const PANEL_MARGIN := 16.0

var _ik: PlayerFootIKModifier
var _player: Player
var _planner: FootIKLandingPlanner
var _runtime: FootIKRuntimeSettings
var _panel: PanelContainer
var _status: Label
var _registered_controls: Array[Dictionary] = []
var _resetting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await get_tree().process_frame
	var body := get_node_or_null("../Player/Body") as PlayerBody
	if body == null or body._foot_ik_modifier == null:
		push_warning("FootIkFeatureControls: Player Foot IK not found, disabling.")
		set_process(false)
		return
	_ik = body._foot_ik_modifier
	_player = body.get_parent() as Player
	_planner = _ik._ground_sampler._landing_planner
	_runtime = _ik._ground_sampler._settings
	_build_panel()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo
			and (event as InputEventKey).keycode == KEY_F6 and _panel != null):
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _status == null or _planner == null:
		return
	var sampler = _ik._ground_sampler
	var landing_target: String = "none"
	if _planner.safe_root_target.is_finite():
		landing_target = "(%.2f, %.2f) y=%.2f" % [
				_planner.safe_root_target.x, _planner.safe_root_target.z,
				_planner.committed_surface_y]
	var split_target: String = "none"
	if sampler.split_safe_root_target.is_finite():
		split_target = "(%.2f, %.2f) y=%.2f" % [
				sampler.split_safe_root_target.x, sampler.split_safe_root_target.z,
				sampler.split_safe_surface_y]
	var knee: Dictionary = _ik._leg_solver.debug_signed_knee_flexion
	var hip: Dictionary = _ik._leg_solver.debug_swing_degrees
	var shin: Dictionary = _ik._leg_solver.debug_shin_swing_degrees
	_status.text = ("Landing: %s\nTarget: %s\nGround recovery: %s\n"
			+ "Joints L/R: knee %.1f/%.1f°, hip %.1f/%.1f°, shin %.1f/%.1f°") % [
			_planner.decision, landing_target, split_target,
			float(knee.get(&"left", 0.0)), float(knee.get(&"right", 0.0)),
			float(hip.get(&"left", 0.0)), float(hip.get(&"right", 0.0)),
			float(shin.get(&"left", 0.0)), float(shin.get(&"right", 0.0))]


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.position = Vector2(PANEL_MARGIN, PANEL_MARGIN)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.add_theme_font_size_override("font_size", 18)
	layer.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(
			PANEL_WIDTH, minf(720.0, get_viewport().get_visible_rect().size.y - PANEL_MARGIN * 2.0))
	_panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.custom_minimum_size.x = PANEL_WIDTH - 28.0
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	scroll.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "Foot IK Features (F6 hides)"
	title.add_theme_font_size_override("font_size", 23)
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "` frees the mouse. Changes apply immediately and clear old IK locks."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)
	vbox.add_child(HSeparator.new())
	_add_heading(vbox, "Feature switches")
	_add_toggle(vbox, "Airborne safe-zone landing", _runtime, &"airborne_safe_zone_enabled")
	_add_toggle(vbox, "Grounded split recovery", _runtime, &"grounded_split_recovery_enabled")
	_add_toggle(vbox, "Higher-foot reposition", _runtime, &"upper_foot_reposition_enabled")
	_add_toggle(vbox, "Lower-foot support", _runtime, &"idle_lower_support_enabled")
	_add_toggle(vbox, "Lower-foot riser escape", _runtime, &"lower_riser_rehome_enabled")
	_add_toggle(vbox, "Idle stance rehome", _runtime, &"idle_stance_rehome_enabled")
	_add_toggle(vbox, "Idle foot freeze", _runtime, &"idle_freeze_enabled")
	_add_toggle(vbox, "Locomotion foot locks", _runtime, &"locomotion_target_lock_enabled")
	_add_toggle(vbox, "Stair prediction", _ik, &"step_prediction_enabled")
	_add_toggle(vbox, "Force both feet planted", _ik, &"force_plant_mode")
	_add_toggle(vbox, "Movement ledge safety", _player, &"ledge_safety_enabled")
	_add_option(vbox, "Locomotion mode", _ik, &"locomotion_mode", [
			{"label": "Legacy gait", "value": PlayerFootIKModifier.LocomotionMode.LEGACY},
			{"label": "Residual stair", "value": PlayerFootIKModifier.LocomotionMode.RESIDUAL_STAIR},
			{"label": "Phase locked", "value": PlayerFootIKModifier.LocomotionMode.PHASE_LOCKED},
	])
	vbox.add_child(HSeparator.new())
	_add_heading(vbox, "Safe-zone landing")
	_add_slider(vbox, "Correction speed", _runtime, &"landing_correction_speed", 0.0, 8.0, 0.1)
	_add_slider(vbox, "Max correction", _runtime, &"max_airborne_correction", 0.0, 0.6, 0.01)
	_add_slider(vbox, "Footprint depth", _runtime, &"landing_footprint_depth", 0.0, 0.25, 0.005)
	_add_slider(vbox, "Body clearance", _runtime,
			&"landing_root_clearance_radius", 0.2, 0.6, 0.01)
	_add_slider(vbox, "Allowed height split", _runtime, &"max_split_ik_height", 0.05, 0.7, 0.01)
	_add_slider(vbox, "Movement step height", _player, &"step_height", 0.05, 1.0, 0.01)
	_add_slider(vbox, "Short-fall allowance", _player, &"ledge_short_fall_height", 0.0, 2.0, 0.05)
	_add_heading(vbox, "Higher-foot reposition")
	_add_slider(vbox, "Foot move speed", _runtime, &"upper_foot_acquire_speed", 0.0, 8.0, 0.1)
	_add_slider(vbox, "Preferred knee flex", _runtime,
			&"preferred_upper_knee_flexion_degrees", 60.0, 150.0, 1.0)
	_add_slider(vbox, "Retained knee flex", _runtime,
			&"retained_upper_knee_flexion_degrees", 60.0, 150.0, 1.0)
	_add_slider(vbox, "Support radius", _runtime, &"upper_support_radius", 0.02, 0.2, 0.005)
	_add_heading(vbox, "Lower-foot support")
	_add_slider(vbox, "Foot move speed", _runtime, &"lower_foot_acquire_speed", 0.0, 8.0, 0.1)
	_add_slider(vbox, "Riser clearance", _runtime,
			&"lower_riser_clearance_radius", 0.05, 0.5, 0.01)
	_add_slider(vbox, "Stance rehome speed", _runtime,
			&"idle_stance_rehome_speed", 0.0, 8.0, 0.1)
	_add_slider(vbox, "Idle search depth", _ik, &"idle_settle_search_down", 0.5, 6.0, 0.1)
	_add_slider(vbox, "Idle speed threshold", _ik, &"idle_step_down_speed", 0.0, 0.3, 0.01)
	_add_slider(vbox, "Direct pelvis drop", _ik, &"step_down_pelvis_drop", 0.0, 0.75, 0.01)
	_add_slider(vbox, "Maximum crouch", _ik, &"step_down_max_crouch", 0.0, 1.0, 0.01)
	vbox.add_child(HSeparator.new())
	_add_heading(vbox, "Stairs and settling")
	_add_slider(vbox, "Prediction distance", _ik, &"step_prediction_distance", 0.1, 1.2, 0.05)
	_add_slider(vbox, "Minimum step rise", _ik, &"step_min_rise", 0.0, 0.3, 0.01)
	_add_slider(vbox, "Swing clearance", _ik, &"step_clearance_margin", 0.0, 0.4, 0.01)
	_add_slider(vbox, "Swing lift rate", _ik, &"step_lift_rate", 0.0, 12.0, 0.1)
	_add_slider(vbox, "Support transfer", _ik, &"support_transfer_blend_time", 0.0, 0.4, 0.01)
	_add_slider(vbox, "Step-down lift", _ik, &"step_down_transition_lift", 0.0, 0.4, 0.01)
	_add_slider(vbox, "Idle pelvis settle", _ik, &"shared_drop_idle_engage_rate", 0.0, 4.0, 0.1)
	_add_slider(vbox, "Pelvis release", _ik, &"shared_drop_release_rate", 0.0, 4.0, 0.1)
	_add_heading(vbox, "Leg joint angles")
	_add_slider(vbox, "Maximum knee flex", _ik, &"max_knee_flexion_degrees", 30.0, 170.0, 1.0)
	_add_slider(vbox, "Maximum hip swing", _ik, &"max_hip_swing_degrees", 10.0, 170.0, 1.0)
	_add_slider(vbox, "Upright shin cone", _runtime,
			&"max_upright_shin_swing_degrees", 10.0, 90.0, 1.0)
	_add_slider(vbox, "Shin steering starts", _runtime,
			&"upright_shin_steer_start_degrees", 0.0, 90.0, 1.0)
	_add_slider(vbox, "Knee forward bias", _runtime,
			&"minimum_knee_pole_alignment", 0.0, 1.0, 0.05)
	_add_heading(vbox, "Joint response")
	_add_slider(vbox, "Motion hip/knee speed", _runtime,
			&"joint_correction_speed_degrees", 1.0, 720.0, 1.0)
	_add_slider(vbox, "Standing hip/knee speed", _runtime,
			&"standing_joint_speed_degrees", 1.0, 360.0, 1.0)
	_add_slider(vbox, "Crouch joint speed", _runtime,
			&"crouch_joint_speed_degrees", 1.0, 360.0, 1.0)
	_add_heading(vbox, "Target response")
	_add_slider(vbox, "Target max speed", _ik, &"target_max_speed", 0.0, 20.0, 0.5)
	_add_slider(vbox, "Flat idle no-op", _ik, &"flat_idle_noop_distance", 0.0, 0.1, 0.005)
	_add_heading(vbox, "Alternate locomotion modes")
	_add_slider(vbox, "Residual pelvis rate", _ik, &"residual_pelvis_lerp_speed", 0.0, 15.0, 0.5)
	_add_slider(vbox, "Residual plant", _ik, &"residual_plant_threshold", 0.0, 0.5, 0.01)
	_add_slider(vbox, "Residual swing", _ik, &"residual_swing_threshold", 0.01, 0.7, 0.01)
	_add_slider(vbox, "Residual foot blend", _ik, &"residual_foot_blend_speed", 0.0, 20.0, 0.5)
	_add_slider(vbox, "Phase stance time", _ik, &"phase_locked_stance_time", 0.0, 1.0, 0.01)
	_add_slider(vbox, "Phase release time", _ik, &"phase_locked_release_time", 0.01, 1.0, 0.01)
	var reset_button := Button.new()
	reset_button.text = "Restore defaults"
	reset_button.pressed.connect(_restore_defaults)
	vbox.add_child(reset_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status)


func _add_heading(parent: VBoxContainer, value: String) -> void:
	var heading := Label.new()
	heading.text = value
	heading.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	parent.add_child(heading)


func _add_toggle(parent: VBoxContainer, label_text: String,
		target: Object, property: StringName) -> void:
	var button := CheckButton.new()
	button.text = label_text
	button.button_pressed = bool(target.get(property))
	button.toggled.connect(func(value: bool) -> void:
		target.set(property, value)
		_settings_changed())
	parent.add_child(button)
	_registered_controls.append({"target": target, "property": property,
			"default": target.get(property), "control": button, "kind": &"toggle"})


func _add_slider(parent: VBoxContainer, label_text: String, target: Object,
		property: StringName, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(155, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(target.get(property))
	slider.custom_minimum_size = Vector2(125, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(54, 0)
	value_label.text = "%.3f" % slider.value
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		target.set(property, value)
		value_label.text = "%.3f" % value
		_settings_changed())
	_registered_controls.append({"target": target, "property": property,
			"default": target.get(property), "control": slider, "kind": &"slider",
			"value_label": value_label})


func _add_option(parent: VBoxContainer, label_text: String, target: Object,
		property: StringName, choices: Array[Dictionary]) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	var current := int(target.get(property))
	for choice: Dictionary in choices:
		option.add_item(choice["label"], choice["value"])
		if int(choice["value"]) == current:
			option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int) -> void:
		target.set(property, option.get_item_id(index))
		_settings_changed())
	row.add_child(option)
	_registered_controls.append({"target": target, "property": property,
			"default": target.get(property), "control": option, "kind": &"option"})


func _settings_changed() -> void:
	if _resetting or _ik == null:
		return
	_ik.reset_runtime_state()
	var skeleton := _ik.get_skeleton()
	if skeleton != null:
		skeleton.advance(0.0)


func _restore_defaults() -> void:
	_resetting = true
	for setting: Dictionary in _registered_controls:
		var target: Object = setting["target"]
		var property: StringName = setting["property"]
		var value: Variant = setting["default"]
		target.set(property, value)
		if setting["kind"] == &"toggle":
			(setting["control"] as BaseButton).set_pressed_no_signal(bool(value))
		elif setting["kind"] == &"slider":
			(setting["control"] as Range).set_value_no_signal(float(value))
			(setting["value_label"] as Label).text = "%.3f" % float(value)
		else:
			var option := setting["control"] as OptionButton
			option.select(option.get_item_index(int(value)))
	_resetting = false
	_settings_changed()
