extends CanvasLayer
## HUD: interaction prompt, stamina bar, toast messages, note reader and
## the inventory screen. Overlays pause the tree; the HUD itself runs with
## PROCESS_MODE_ALWAYS so it can close them.

const ITEM_PICKUP_SCENE := preload("res://levels/props/item_pickup.tscn")

var _inventory: Inventory
var _health: Health
var _weapon: PistolWeapon
var _slot_buttons: Array[Button] = []
var _selected := -1
var _toast_tween: Tween
var _hurt_tween: Tween

@onready var center_dot: ColorRect = $CenterDot
@onready var prompt_label: Label = $PromptLabel
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var health_bar: ProgressBar = $HealthBar
@onready var ammo_label: Label = $AmmoLabel
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
@onready var main_debug_button: Button = $DebugOverlay/Center/MainPanel/MainMargin/MainVBox/DebugButton
@onready var main_close_button: Button = $DebugOverlay/Center/MainPanel/MainMargin/MainVBox/CloseButton
@onready var debug_panel: PanelContainer = $DebugOverlay/Center/DebugPanel
@onready var debug_field_x: LineEdit = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/FieldX
@onready var debug_field_y: LineEdit = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/FieldY
@onready var debug_field_z: LineEdit = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/FieldZ
@onready var debug_apply: Button = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/EyeOffsetRow/ApplyButton
@onready var anim_clips_button: Button = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/AnimClipsButton
@onready var footstep_button: Button = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/FootstepButton
@onready var fov_gizmo_button: Button = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/FovGizmoButton
@onready var debug_back_button: Button = $DebugOverlay/Center/DebugPanel/DebugMargin/DebugVBox/BackButton
@onready var anim_panel_anchor: Control = $DebugOverlay/AnimPanelAnchor
@onready var anim_list: VBoxContainer = $DebugOverlay/AnimPanelAnchor/AnimPanel/AnimMargin/AnimVBox/AnimScroll/AnimList
@onready var anim_back_button: Button = $DebugOverlay/AnimPanelAnchor/AnimPanel/AnimMargin/AnimVBox/BackButton

var _anim_list_built := false


func _ready() -> void:
	add_to_group(&"hud")
	use_button.pressed.connect(_on_use_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	debug_apply.pressed.connect(_on_debug_apply)
	footstep_button.pressed.connect(_on_footstep_button_pressed)
	fov_gizmo_button.pressed.connect(_on_fov_gizmo_button_pressed)
	main_debug_button.pressed.connect(_show_debug_page)
	main_close_button.pressed.connect(_close_debug)
	anim_clips_button.pressed.connect(_show_anim_page)
	debug_back_button.pressed.connect(_show_debug_main)
	anim_back_button.pressed.connect(_show_debug_page)


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
			or event.is_action_pressed(&"inventory")):
		toggle_debug()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
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
	get_tree().paused = true


func toggle_inventory() -> void:
	if note_overlay.visible or _inventory == null:
		return
	if inv_overlay.visible:
		inv_overlay.hide()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_selected = -1
		_refresh_inventory()
		inv_overlay.show()
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
	desc_label.text = (_inventory.slots[_selected]["item"].description
			if has_selection else "")


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
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_debug() -> void:
	debug_overlay.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Debug menu is one overlay with three pages shown/hidden in place, not
## three separate overlays - only one of these should ever be visible.
func _show_debug_main() -> void:
	main_panel.show()
	debug_panel.hide()
	anim_panel_anchor.hide()


func _show_debug_page() -> void:
	main_panel.hide()
	debug_panel.show()
	anim_panel_anchor.hide()


func _show_anim_page() -> void:
	main_panel.hide()
	debug_panel.hide()
	anim_panel_anchor.show()


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


func _on_footstep_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not ("body" in player) or not player.body.has_method(&"toggle_debug_footsteps"):
		return
	player.body.toggle_debug_footsteps()
	footstep_button.text = "Footstep Markers: ON" if player.body.debug_footsteps else "Footstep Markers: OFF"


func _on_fov_gizmo_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"toggle_fov_gizmo"):
		return
	player.toggle_fov_gizmo()
	fov_gizmo_button.text = "FOV Gizmo: ON" if player.show_fov_gizmo else "FOV Gizmo: OFF"


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
	if item.kind == Item.Kind.CONSUMABLE and item.heal_amount > 0 and _health:
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
