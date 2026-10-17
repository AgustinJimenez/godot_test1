class_name UniverseStartMenu
extends CanvasLayer
## The menu in front of the universe: the saved universes (open one, delete one) and a new universe
## (the seed and size of its first planet, a random seed, or just the default one). Choosing sets
## what the next planet is made from (PlanetMenu.pending and pending_state) and makes the scene
## again, which builds it. A universe has one planet today; the player will be able to travel to
## others.

## True when the next start of the scene should show this menu (set by "Main menu" in the Planet
## page); a start with no arguments shows it too.
static var requested := false

var _saves: ItemList
var _seed_field: LineEdit
var _radius_field: LineEdit
var _home: OptionButton
var _readability: HSlider
var _note: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.07)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 8)
	centre.add_child(column)
	_add_label(column, "Universe", 32)
	_add_label(column, "Saved universes", 16)
	_saves = ItemList.new()
	_saves.custom_minimum_size = Vector2(0, 190)
	_saves.item_activated.connect(func(_index: int) -> void: _open_selected())
	column.add_child(_saves)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_button(row, "Open", _open_selected)
	_add_button(row, "Delete", _delete_selected)
	column.add_child(HSeparator.new())
	_add_label(column, "New universe (it starts on one planet)", 16)
	var fields := HBoxContainer.new()
	column.add_child(fields)
	_add_label(fields, "seed", 16)
	_seed_field = LineEdit.new()
	_seed_field.text = str(PlanetSettings.new().world_seed)
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(_seed_field)
	_add_label(fields, "  radius (m)", 16)
	_radius_field = LineEdit.new()
	_radius_field.placeholder_text = "from the planet"
	_radius_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(_radius_field)
	var home_row := HBoxContainer.new()
	column.add_child(home_row)
	_add_label(home_row, "home planet ", 16)
	_home = OptionButton.new()
	_home.add_item("Sun-like star, habitable planet")
	_home.add_item("Any star and planet")
	_home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_row.add_child(_home)
	var colour_row := HBoxContainer.new()
	column.add_child(colour_row)
	_add_label(colour_row, "star colours: physical ", 16)
	_readability = HSlider.new()
	_readability.max_value = 1.0
	_readability.step = 0.05
	_readability.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colour_row.add_child(_readability)
	_add_label(colour_row, " readable", 16)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_add_button(buttons, "Create", func() -> void: _create(_seed_field.text))
	_add_button(buttons, "Random seed", func() -> void: _create(str(randi() % 100000)))
	_add_button(buttons, "Quick start (default universe)",
			func() -> void: _begin(PlanetSettings.new(), {}))
	_note = _add_label(column, "", 14)
	_fill_saves()


func _fill_saves() -> void:
	_saves.clear()
	for entry in UniverseSave.list():
		var when := Time.get_datetime_string_from_unix_time(int(entry["saved_at"]), true)
		var count := int(entry["planets"])
		_saves.add_item("%s    %d planet%s, seed %d, radius %d m    %s" % [entry["name"], count,
				"" if count == 1 else "s", entry["seed"], int(entry["radius"]), when])
		_saves.set_item_metadata(_saves.item_count - 1, entry["name"])
	if _saves.item_count > 0:
		_saves.select(0)
	else:
		_saves.add_item("(no saved universe yet)")
		_saves.set_item_disabled(0, true)


func _selected_save() -> String:
	var chosen := _saves.get_selected_items()
	if chosen.is_empty() or _saves.is_item_disabled(chosen[0]):
		return ""
	return str(_saves.get_item_metadata(chosen[0]))


func _open_selected() -> void:
	var save_name := _selected_save()
	var data := UniverseSave.load_data(save_name)
	if data.is_empty():
		_note.text = "Choose a saved universe to open"
		return
	_begin(UniverseSave.settings_from(data), data.get("state", {}))


func _delete_selected() -> void:
	var save_name := _selected_save()
	if save_name != "":
		UniverseSave.delete(save_name)
		_note.text = "Deleted '%s'" % save_name
	_fill_saves()


func _create(seed_text: String) -> void:
	var universe := UniverseSettings.new()
	var text := seed_text.strip_edges()
	universe.universe_seed = int(text) if text.is_valid_int() else hash(text)
	universe.sunlike_home = _home.selected == 0
	var settings := universe.home_settings(_readability.value)
	if _radius_field.text.strip_edges().is_valid_float():
		settings.radius = clampf(_radius_field.text.to_float(), 2000.0, 6.4e6)
	_begin(settings, {})


func _begin(settings: PlanetSettings, state: Dictionary) -> void:
	PlanetMenu.pending = settings
	PlanetMenu.pending_state = state
	requested = false
	get_tree().reload_current_scene()


func _add_label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _add_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button
