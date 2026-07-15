extends CanvasLayer
## HUD: interaction prompt, stamina bar, toast messages, note reader and
## the inventory screen. Overlays pause the tree; the HUD itself runs with
## PROCESS_MODE_ALWAYS so it can close them.

const ITEM_PICKUP_SCENE := preload("res://levels/props/item_pickup.tscn")

var _inventory: Inventory
var _slot_buttons: Array[Button] = []
var _selected := -1
var _toast_tween: Tween

@onready var prompt_label: Label = $PromptLabel
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var toast_label: Label = $ToastLabel
@onready var note_overlay: Control = $NoteOverlay
@onready var note_text: Label = $NoteOverlay/Center/Panel/Margin/VBox/NoteText
@onready var inv_overlay: Control = $InventoryOverlay
@onready var slot_grid: GridContainer = $InventoryOverlay/Center/Panel/Margin/VBox/Grid
@onready var desc_label: Label = $InventoryOverlay/Center/Panel/Margin/VBox/Desc
@onready var use_button: Button = $InventoryOverlay/Center/Panel/Margin/VBox/Buttons/UseButton
@onready var drop_button: Button = $InventoryOverlay/Center/Panel/Margin/VBox/Buttons/DropButton


func _ready() -> void:
	add_to_group(&"hud")
	use_button.pressed.connect(_on_use_pressed)
	drop_button.pressed.connect(_on_drop_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if note_overlay.visible and (event.is_action_pressed(&"interact")
			or event.is_action_pressed(&"pause")):
		note_overlay.hide()
		get_tree().paused = false
		get_viewport().set_input_as_handled()
	elif inv_overlay.visible and (event.is_action_pressed(&"inventory")
			or event.is_action_pressed(&"pause")):
		toggle_inventory()
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


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = text != ""


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


func _on_slot_pressed(index: int) -> void:
	_selected = index
	_refresh_inventory()


func _on_use_pressed() -> void:
	var item: Item = _inventory.slots[_selected]["item"]
	if item.kind == Item.Kind.CONSUMABLE:
		_inventory.remove_at(_selected, 1)
		toast("Used " + item.display_name)  # real effects arrive with health in M3
	else:
		toast("No use for that right now")
	_refresh_inventory()


func _on_drop_pressed() -> void:
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
