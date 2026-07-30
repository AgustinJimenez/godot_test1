extends CanvasLayer
## HUD: interaction prompt, stamina bar, toast messages, note reader and
## the inventory screen. Overlays pause the tree; the HUD itself runs with
## PROCESS_MODE_ALWAYS so it can close them.

const ITEM_PICKUP_SCENE := preload("res://levels/props/item_pickup.tscn")
const GAMEPLAY_ITEMS: ItemCatalog = preload("res://items/gameplay_items.tres")
const ITEM_GROUP_ORDER: Array[int] = [
	Item.Kind.WEAPON,
	Item.Kind.CONSUMABLE,
	Item.Kind.AMMO,
	Item.Kind.KEY,
	Item.Kind.MISC,
]
const ITEM_GROUP_NAMES: Dictionary[int, String] = {
	Item.Kind.WEAPON: "WEAPONS",
	Item.Kind.CONSUMABLE: "CONSUMABLES",
	Item.Kind.AMMO: "AMMUNITION",
	Item.Kind.KEY: "KEY ITEMS",
	Item.Kind.MISC: "MISCELLANEOUS",
}
const CHARACTER_CATALOG := preload("res://characters/character_catalog.gd")

@export var show_fps_debug := false

var _inventory: Inventory
var _health: Health
var _weapon: PistolWeapon
var _slot_buttons: Array[Button] = []
var _selected := -1
var _toast_tween: Tween
var _hurt_tween: Tween
var _fps_refresh_left := 0.0
var _object_list_built := false
var _object_rows: Array[Dictionary] = []
var _character_rows: Array[Dictionary] = []

@onready var fps_label: Label = $FPSLabel
@onready var center_dot: ColorRect = $CenterDot
@onready var prompt_label: Label = $PromptLabel
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var health_bar: ProgressBar = $HealthBar
@onready var ammo_label: Label = $AmmoLabel
@onready var inventory_hint: Label = $InventoryHint
@onready var hurt_flash: ColorRect = $HurtFlash
@onready var death_overlay: Control = $DeathOverlay
@onready var toast_label: Label = $ToastLabel
@onready var note_overlay: Control = $NoteOverlay
@onready var note_text: Label = $NoteOverlay/Center/Panel/Margin/VBox/NoteText
@onready var inv_overlay: Control = $InventoryOverlay
@onready var slot_grid: GridContainer = $InventoryOverlay/Center/Panel/Margin/VBox/Grid
@onready var desc_label: Label = $InventoryOverlay/Center/Panel/Margin/VBox/Desc
@onready var use_button: Button = $InventoryOverlay/Center/Panel/Margin/VBox/Buttons/UseButton
@onready var drop_button: Button = $InventoryOverlay/Center/Panel/Margin/VBox/Buttons/DropButton
@onready var debug_overlay: Control = $DebugOverlay
@onready var main_panel: PanelContainer = $DebugOverlay/Center/MainPanel
@onready var main_guide_button: Button = get_node(
		^"DebugOverlay/Center/MainPanel/MainMargin/MainVBox/GuideButton")
@onready var main_settings_button: Button = get_node(
		^"DebugOverlay/Center/MainPanel/MainMargin/MainVBox/SettingsButton")
@onready var main_debug_button: Button = get_node(
		^"DebugOverlay/Center/MainPanel/MainMargin/MainVBox/DebugButton")
@onready var main_close_app_button: Button = get_node(
		^"DebugOverlay/Center/MainPanel/MainMargin/MainVBox/CloseAppButton")
@onready var main_close_button: Button = get_node(
		^"DebugOverlay/Center/MainPanel/MainMargin/MainVBox/CloseButton")
@onready var guide_panel: PanelContainer = $DebugOverlay/Center/GuidePanel
@onready var guide_back_button: Button = get_node(
		^"DebugOverlay/Center/GuidePanel/GuideMargin/GuideVBox/BackButton")
@onready var debug_panel: PanelContainer = $DebugOverlay/Center/DebugPanel
@onready var debug_field_x: LineEdit = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/FieldX")
@onready var debug_field_y: LineEdit = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/FieldY")
@onready var debug_field_z: LineEdit = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/FieldZ")
@onready var debug_apply: Button = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/ApplyButton")
@onready var anim_clips_button: Button = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/AnimClipsButton")
@onready var object_list_button: Button = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/ObjectListButton")
@onready var fov_gizmo_button: Button = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/FovGizmoButton")
@onready var show_fps_toggle: CheckButton = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/ShowFPSToggle")
@onready var visual_filters_toggle: CheckButton = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/VisualFiltersToggle")
@onready var debug_back_button: Button = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/BackButton")
@onready var settings_menu: SettingsMenu = $DebugOverlay/Center/SettingsMenu
@onready var object_panel: PanelContainer = $DebugOverlay/Center/ObjectPanel
@onready var object_list: VBoxContainer = get_node(
		^"DebugOverlay/Center/ObjectPanel/ObjectMargin/ObjectVBox/ObjectScroll/ObjectList")
@onready var object_back_button: Button = get_node(
		^"DebugOverlay/Center/ObjectPanel/ObjectMargin/ObjectVBox/BackButton")
@onready var character_list_button: Button = get_node(
		^"DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/CharacterListButton")
@onready var character_panel: PanelContainer = $DebugOverlay/Center/CharacterPanel
@onready var character_status_label: Label = get_node(
		^"DebugOverlay/Center/CharacterPanel/CharacterMargin/CharacterVBox/StatusLabel")
@onready var character_list: VBoxContainer = get_node(
		^"DebugOverlay/Center/CharacterPanel/CharacterMargin/CharacterVBox/CharacterScroll/CharacterList")
@onready var character_back_button: Button = get_node(
		^"DebugOverlay/Center/CharacterPanel/CharacterMargin/CharacterVBox/BackButton")
@onready var anim_panel_anchor: Control = $DebugOverlay/AnimPanelAnchor
@onready var anim_list: VBoxContainer = get_node(
		^"DebugOverlay/AnimPanelAnchor/AnimPanel/AnimMargin/AnimVBox/AnimScroll/AnimList")
@onready var anim_back_button: Button = get_node(
		^"DebugOverlay/AnimPanelAnchor/AnimPanel/AnimMargin/AnimVBox/BackButton")

var _anim_list_built := false
var _character_list_built := false
var _character_swap_in_progress := false


func _ready() -> void:
	add_to_group(&"hud")
	use_button.pressed.connect(_on_use_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	debug_apply.pressed.connect(_on_debug_apply)
	fov_gizmo_button.pressed.connect(_on_fov_gizmo_button_pressed)
	show_fps_toggle.toggled.connect(_on_show_fps_toggled)
	visual_filters_toggle.toggled.connect(_on_visual_filters_toggled)
	main_debug_button.pressed.connect(_show_debug_page)
	main_guide_button.pressed.connect(_show_guide_page)
	main_settings_button.pressed.connect(_show_settings_page)
	main_close_app_button.pressed.connect(_close_app)
	main_close_button.pressed.connect(_close_debug)
	guide_back_button.pressed.connect(_show_debug_main)
	anim_clips_button.pressed.connect(_show_anim_page)
	object_list_button.pressed.connect(_show_object_page)
	character_list_button.pressed.connect(_show_character_page)
	debug_back_button.pressed.connect(_show_debug_main)
	settings_menu.back_requested.connect(_show_debug_main)
	anim_back_button.pressed.connect(_show_debug_page)
	object_back_button.pressed.connect(_show_debug_page)
	character_back_button.pressed.connect(_show_debug_page)
	show_fps_toggle.button_pressed = show_fps_debug
	fps_label.visible = show_fps_debug


func _process(delta: float) -> void:
	if not fps_label.visible:
		return
	_fps_refresh_left -= delta
	if _fps_refresh_left <= 0.0:
		fps_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())
		_fps_refresh_left = 0.25


func _unhandled_input(event: InputEvent) -> void:
	if death_overlay.visible:
		if event.is_action_pressed(&"interact"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()
	elif note_overlay.visible and (event.is_action_pressed(&"interact")
			or event.is_action_pressed(&"pause")):
		note_overlay.hide()
		get_tree().paused = false
		get_viewport().set_input_as_handled()
	elif inv_overlay.visible and (event.is_action_pressed(&"inventory")
			or event.is_action_pressed(&"pause")):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif debug_overlay.visible and (event.is_action_pressed(&"pause")
			or event.is_action_pressed(&"debug_menu")
			or event.is_action_pressed(&"inventory")):
		toggle_debug()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"debug_menu"):
		toggle_debug()
		get_viewport().set_input_as_handled()


func bind_inventory(inventory: Inventory) -> void:
	_inventory = inventory
	_inventory.changed.connect(_refresh_inventory)
	for i in _inventory.capacity:
		var button := Button.new()
		button.custom_minimum_size = Vector2(112, 64)
		button.pressed.connect(_on_slot_pressed.bind(i))
		slot_grid.add_child(button)
		_slot_buttons.append(button)
	_refresh_object_list()


func bind_health(health: Health) -> void:
	_health = health
	_health.changed.connect(_set_health)
	_health.damaged.connect(_on_player_damaged)
	_set_health(_health.current, _health.max_health)


func bind_weapon(weapon: PistolWeapon) -> void:
	_weapon = weapon
	_weapon.ammo_changed.connect(_set_ammo)


func _set_health(current: float, max_value: float) -> void:
	health_bar.max_value = max_value
	health_bar.value = current


func _on_player_damaged(_amount: float) -> void:
	if _hurt_tween:
		_hurt_tween.kill()
	hurt_flash.color.a = 0.35
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(hurt_flash, "color:a", 0.0, 0.45)


func _set_ammo(magazine: int, reserve: int) -> void:
	ammo_label.visible = _weapon.equipped
	ammo_label.text = "%d / %d" % [magazine, reserve]


func show_death() -> void:
	death_overlay.show()
	set_prompt("")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = text != ""


## The center dot is a first-person aiming reference - meaningless once the
## camera isn't riding on the character's own view anymore.
func set_center_dot_visible(v: bool) -> void:
	center_dot.visible = v


func set_stamina(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
	stamina_bar.visible = value < max_value - 0.01


func toast(message: String) -> void:
	toast_label.text = message
	toast_label.modulate.a = 1.0
	toast_label.show()
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


func show_note(text: String) -> void:
	note_text.text = text
	note_overlay.show()
	set_prompt("")
	get_tree().paused = true


func toggle_inventory() -> void:
	if note_overlay.visible or _inventory == null:
		return
	if inv_overlay.visible:
		inv_overlay.hide()
		inventory_hint.show()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_selected = -1
		_refresh_inventory()
		inv_overlay.show()
		inventory_hint.hide()
		set_prompt("")
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_inventory() -> void:
	if _inventory == null:
		return
	for i in _slot_buttons.size():
		var button := _slot_buttons[i]
		var slot := _inventory.slots[i]
		if slot.is_empty():
			button.text = "—"
			button.disabled = true
		else:
			var item: Item = slot["item"]
			button.text = item.display_name
			if slot["count"] > 1:
				button.text += "\n×%d" % slot["count"]
			button.disabled = false
		button.modulate = Color(1.0, 0.85, 0.5) if i == _selected else Color.WHITE
	var has_selection := (_selected >= 0
			and not _inventory.slots[_selected].is_empty())
	use_button.disabled = not has_selection
	drop_button.disabled = not has_selection
	use_button.text = "Use"
	if has_selection:
		var selected_item: Item = _inventory.slots[_selected]["item"]
		if selected_item.kind == Item.Kind.WEAPON:
			var player := get_tree().get_first_node_in_group(&"player")
			var equipped := (player != null
					and bool(player.call(&"is_item_equipped", selected_item)))
			use_button.text = "Unequip" if equipped else "Equip"
	desc_label.text = (_inventory.slots[_selected]["item"].description
			if has_selection else "")
	_refresh_object_list()


func toggle_debug() -> void:
	if note_overlay.visible or inv_overlay.visible:
		return
	if debug_overlay.visible:
		_close_debug()
	else:
		_open_debug()


func _open_debug() -> void:
	var p := get_tree().get_first_node_in_group(&"player")
	if p and p.has_method(&"set_eye_offset"):
		var v: Vector3 = p.eye_offset
		debug_field_x.text = "%.3f" % v.x
		debug_field_y.text = "%.3f" % v.y
		debug_field_z.text = "%.3f" % v.z
	_build_anim_list(p)
	_show_debug_main()
	debug_overlay.show()
	set_prompt("")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_debug() -> void:
	debug_overlay.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close_app() -> void:
	get_tree().paused = false
	get_tree().quit()


## Debug menu is one overlay with pages shown/hidden in place, not separate
## overlays - only one of these should ever be visible.
func _show_debug_main() -> void:
	main_panel.show()
	guide_panel.hide()
	debug_panel.hide()
	settings_menu.hide()
	object_panel.hide()
	character_panel.hide()
	anim_panel_anchor.hide()


func _show_guide_page() -> void:
	main_panel.hide()
	guide_panel.show()
	debug_panel.hide()
	settings_menu.hide()
	object_panel.hide()
	character_panel.hide()
	anim_panel_anchor.hide()


func _show_settings_page() -> void:
	main_panel.hide()
	guide_panel.hide()
	debug_panel.hide()
	settings_menu.show()
	settings_menu.refresh()
	object_panel.hide()
	character_panel.hide()
	anim_panel_anchor.hide()


func _show_debug_page() -> void:
	main_panel.hide()
	guide_panel.hide()
	debug_panel.show()
	settings_menu.hide()
	object_panel.hide()
	character_panel.hide()
	anim_panel_anchor.hide()


func _show_anim_page() -> void:
	main_panel.hide()
	guide_panel.hide()
	debug_panel.hide()
	settings_menu.hide()
	object_panel.hide()
	character_panel.hide()
	anim_panel_anchor.show()


func _show_object_page() -> void:
	_build_object_list()
	main_panel.hide()
	guide_panel.hide()
	debug_panel.hide()
	settings_menu.hide()
	character_panel.hide()
	anim_panel_anchor.hide()
	object_panel.show()
	_refresh_object_list()


func _show_character_page() -> void:
	_build_character_list()
	main_panel.hide()
	guide_panel.hide()
	debug_panel.hide()
	settings_menu.hide()
	object_panel.hide()
	anim_panel_anchor.hide()
	character_panel.show()
	_refresh_character_list()


func _build_object_list() -> void:
	if _object_list_built:
		return
	_object_list_built = true
	for kind: int in ITEM_GROUP_ORDER:
		var group_items: Array[Item] = []
		for resource: Resource in GAMEPLAY_ITEMS.items:
			var item := resource as Item
			if item != null and item.kind == kind:
				group_items.append(item)
		if group_items.is_empty():
			continue
		var header := Label.new()
		header.text = ITEM_GROUP_NAMES[kind]
		header.add_theme_color_override(&"font_color", Color(0.6, 0.7, 1, 1))
		header.add_theme_font_size_override(&"font_size", 14)
		object_list.add_child(header)
		for item: Item in group_items:
			_add_object_row(item)


func _add_object_row(item: Item) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	object_list.add_child(row)

	var name_label := Label.new()
	name_label.text = item.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var count_label := Label.new()
	count_label.custom_minimum_size.x = 72.0
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count_label)

	var add_button := Button.new()
	add_button.custom_minimum_size.x = 72.0
	add_button.text = "Add"
	add_button.pressed.connect(_on_debug_add_item.bind(item))
	row.add_child(add_button)

	var equip_button: Button = null
	if item.kind == Item.Kind.WEAPON:
		equip_button = Button.new()
		equip_button.custom_minimum_size.x = 84.0
		equip_button.text = "Equip"
		equip_button.pressed.connect(_on_debug_equip_item.bind(item))
		row.add_child(equip_button)

	_object_rows.append({
		"item": item,
		"count_label": count_label,
		"add_button": add_button,
		"equip_button": equip_button,
	})


func _refresh_object_list() -> void:
	if not _object_list_built or _inventory == null:
		return
	var player := get_tree().get_first_node_in_group(&"player")
	for row: Dictionary in _object_rows:
		var item: Item = row["item"]
		var count: int = _inventory.count_of(item)
		var count_label: Label = row["count_label"]
		var add_button: Button = row["add_button"]
		count_label.text = "Owned: %d" % count
		add_button.disabled = item.max_stack == 1 and count > 0
		add_button.text = "Owned" if add_button.disabled else "Add"
		var equip_button: Button = row["equip_button"]
		if equip_button == null:
			continue
		var equipped := (player != null
				and bool(player.call(&"is_item_equipped", item)))
		equip_button.text = "Equipped" if equipped else "Equip"
		equip_button.disabled = equipped


## Lists whatever CharacterCatalog.list_all() finds on disk - the same
## catalog the character editor tool builds/persists (see
## characters/character_catalog.gd) - so this can never drift out of sync
## with what's actually available to import/rig. Built lazily, once; new
## imports made mid-session while the debug menu was never opened won't
## appear until the next session, same tradeoff _build_object_list() and
## _build_anim_list() already make for their own lists.
func _build_character_list() -> void:
	if _character_list_built:
		return
	_character_list_built = true
	var catalog: Dictionary = CHARACTER_CATALOG.list_all()
	var kind_ids := catalog.keys()
	kind_ids.sort_custom(func(a, b):
		return String(catalog[a].get("display_name", a)) < String(catalog[b].get("display_name", b)))
	for kind_id: String in kind_ids:
		_add_character_row(catalog[kind_id])
	if kind_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No catalog characters yet - import one in the character editor tool."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		character_list.add_child(empty_label)


func _add_character_row(info: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	character_list.add_child(row)

	var name_label := Label.new()
	name_label.text = String(info.get("display_name", info.get("kind_id", "?")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var select_button := Button.new()
	select_button.custom_minimum_size.x = 84.0
	select_button.text = "Select"
	select_button.pressed.connect(_on_character_button_pressed.bind(info))
	row.add_child(select_button)

	_character_rows.append({"info": info, "select_button": select_button})


func _refresh_character_list() -> void:
	for row: Dictionary in _character_rows:
		var select_button: Button = row["select_button"]
		select_button.disabled = _character_swap_in_progress


## Rebaking a full retargeted clip library onto an arbitrary skeleton isn't
## instant (~15 clips, the same synchronous cost PlayerBody._ready() already
## pays once at scene start) - shows a status message and disables the list
## for two frames before doing the actual swap, so the message has a chance
## to actually paint before the hitch, rather than the game visibly hanging
## with no explanation (see CURRENT_TASK.md's Phase 5 checklist).
func _on_character_button_pressed(info: Dictionary) -> void:
	if _character_swap_in_progress:
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not ("body" in player) or player.body == null:
		return
	var model_path: String = info.get("model_path", "")
	if not ResourceLoader.exists(model_path):
		toast("Character asset missing: %s" % model_path)
		return
	var display_name: String = info.get("display_name", model_path.get_file())
	_character_swap_in_progress = true
	character_status_label.text = "Loading %s..." % display_name
	character_status_label.show()
	_refresh_character_list()
	for _frame in 2:
		await get_tree().process_frame
	player.body.swap_character(load(model_path) as PackedScene)
	_character_swap_in_progress = false
	character_status_label.hide()
	_refresh_character_list()
	toast("Switched to " + display_name)


func _on_debug_add_item(item: Item) -> void:
	if _inventory == null:
		return
	if _inventory.add_item(item, 1) == 0:
		toast("Added " + item.display_name)
	else:
		toast("Inventory full")
	_refresh_object_list()


func _on_debug_equip_item(item: Item) -> void:
	if _inventory == null:
		return
	if _inventory.count_of(item) == 0 and _inventory.add_item(item, 1) != 0:
		toast("Inventory full")
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"toggle_equip_item"):
		return
	if not bool(player.call(&"is_item_equipped", item)):
		player.call(&"toggle_equip_item", item)
	toast("Equipped " + item.display_name)
	_refresh_inventory()


## Lazily builds one section (label + buttons) per group returned by
## PlayerBody.get_animation_groups(), rather than hardcoding clip names or
## groups here, so this can't drift out of sync with whatever clips
## actually exist.
func _build_anim_list(player: Node) -> void:
	if _anim_list_built or player == null or not ("body" in player):
		return
	var body: Node = player.body
	if body == null or not body.has_method(&"get_animation_groups"):
		return
	_anim_list_built = true
	var groups: Dictionary = body.get_animation_groups()
	for group_name: StringName in groups:
		var header := Label.new()
		header.text = String(group_name).to_upper()
		header.add_theme_color_override(&"font_color", Color(0.6, 0.7, 1, 1))
		header.add_theme_font_size_override(&"font_size", 13)
		anim_list.add_child(header)
		for anim_name: StringName in groups[group_name]:
			var button := Button.new()
			button.text = "Default" if anim_name == &"unarmed_idle" else String(anim_name)
			button.pressed.connect(_on_anim_button_pressed.bind(anim_name))
			anim_list.add_child(button)


func _on_anim_button_pressed(anim_name: StringName) -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player and "body" in player and player.body.has_method(&"play_debug_anim"):
		player.body.play_debug_anim(anim_name)


func _on_fov_gizmo_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"toggle_fov_gizmo"):
		return
	player.toggle_fov_gizmo()
	fov_gizmo_button.text = "FOV Gizmo: ON" if player.show_fov_gizmo else "FOV Gizmo: OFF"


func _on_show_fps_toggled(enabled: bool) -> void:
	show_fps_debug = enabled
	fps_label.visible = enabled
	_fps_refresh_left = 0.0


## Toggles any full-screen post-process overlay in the "visual_filters" group
## (e.g. the VHS/liminal-horror camcorder shader). Scene-scoped rather than a
## HUD-owned node, since only test scenes like
## tests/manual/effects/vhs_liminal_overlay_test.tscn currently have one -
## the toggle is a no-op with nothing to hide in scenes without one.
func _on_visual_filters_toggled(enabled: bool) -> void:
	for overlay in get_tree().get_nodes_in_group(&"visual_filters"):
		if overlay is CanvasItem:
			(overlay as CanvasItem).visible = enabled


func _on_debug_apply() -> void:
	var x := float(debug_field_x.text)
	var y := float(debug_field_y.text)
	var z := float(debug_field_z.text)
	var player := get_tree().get_first_node_in_group(&"player")
	if player:
		player.set_eye_offset(Vector3(x, y, z))
	toast("EYE_OFFSET = (%.3f, %.3f, %.3f)" % [x, y, z])


func _on_slot_pressed(index: int) -> void:
	_selected = index
	_refresh_inventory()


func _on_use_pressed() -> void:
	if _selected < 0 or _inventory.slots[_selected].is_empty():
		return
	var item: Item = _inventory.slots[_selected]["item"]
	if item.kind == Item.Kind.WEAPON:
		var player := get_tree().get_first_node_in_group(&"player")
		if player == null or not player.has_method(&"toggle_equip_item"):
			return
		var equipped := bool(player.call(&"toggle_equip_item", item))
		toast(("Equipped " if equipped else "Unequipped ") + item.display_name)
	elif item.kind == Item.Kind.CONSUMABLE and item.heal_amount > 0 and _health:
		var restored := _health.heal(float(item.heal_amount))
		if restored <= 0.0:
			toast("Health is already full")
		else:
			_inventory.remove_at(_selected, 1)
			toast("Used %s (+%d HP)" % [item.display_name, int(restored)])
	elif item.kind == Item.Kind.CONSUMABLE:
		_inventory.remove_at(_selected, 1)
		toast("Used " + item.display_name)
	else:
		toast("No use for that right now")
	_refresh_inventory()


func _on_drop_pressed() -> void:
	if _selected < 0 or _inventory.slots[_selected].is_empty():
		return
	var item: Item = _inventory.slots[_selected]["item"]
	_inventory.remove_at(_selected, 1)
	var player := _inventory.get_parent() as Node3D
	var pickup: ItemPickup = ITEM_PICKUP_SCENE.instantiate()
	pickup.item = item
	pickup.count = 1
	get_tree().current_scene.add_child(pickup)
	var forward: Vector3 = -player.global_transform.basis.z
	pickup.global_position = player.global_position + forward * 0.9 + Vector3(0, 0.05, 0)
	toast("Dropped " + item.display_name)
	_refresh_inventory()
