class_name PlanetMenu
extends VBoxContainer
## The "Planet" page of the Esc menu (the planet's counterpart of the flat world's "World" page):
## the time (speed forward and backward, pause, jumps, the hour of the day, the day of the year),
## the weather (follow the planet's climate or force one), the seed and the size of the planet, and
## the map. The planet adds it through the HUD's add_menu_page when it starts with a player.

## The settings the next planet is made with (the scene is reloaded to make it).
static var pending: PlanetSettings
## The moment of a save to go back to when the scene has been made again (see PlanetWorld.snapshot).
static var pending_state := {}

var _planet: PlanetWorld
var _info: Label
var _rate_label: Label
var _hour_slider: HSlider
var _year_slider: HSlider
var _weather: OptionButton
var _seed_field: LineEdit
var _radius_field: LineEdit
var _save_name: LineEdit
var _saves: OptionButton
var _save_note: Label


func setup(planet: PlanetWorld) -> void:
	_planet = planet
	custom_minimum_size = Vector2(420, 0)
	_info = _label("")
	_add_time_rows()
	_add_weather_row()
	_add_new_planet_rows()
	_add_save_rows()
	var map := Button.new()
	map.text = "Open the map (M)"
	map.pressed.connect(func() -> void:
		_planet.map.toggle()
		_planet.map.show_zoom(6.0))
	add_child(map)


func refresh() -> void:
	_seed_field.text = str(_planet.settings.world_seed)
	_radius_field.text = str(int(_planet.settings.radius))
	_weather.select(_planet.weather_override + 1)
	_fill_saves()
	_sync()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_sync()


func _sync() -> void:
	var here := _planet.planet_position().normalized()
	var hour := _planet.clock.local_hour(here)
	_info.text = "%02d:%02d   %s\n%s" % [int(hour), int((hour - floorf(hour)) * 60.0),
			_planet.season_text(), _planet.weather_text]
	_hour_slider.set_value_no_signal(hour)
	_year_slider.set_value_no_signal(_planet.clock.year_share())
	var rate := "paused" if _planet.time_rate == 0.0 else "%d×" % int(_planet.time_rate)
	_rate_label.text = "Speed: %s   (a day lasts %d s at 1×)" % [rate,
			int(_planet.clock.day_seconds)]


func _add_time_rows() -> void:
	_rate_label = _label("")
	var row := HBoxContainer.new()
	add_child(row)
	for rate in [-1000, -100, -10, -1, 0, 1, 10, 100, 1000]:
		var button := Button.new()
		button.text = "pause" if rate == 0 else "%d×" % rate
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _planet.time_rate = float(rate))
		row.add_child(button)
	var jumps := HBoxContainer.new()
	add_child(jumps)
	for entry: Array in [["-1/8 year", -0.125], ["-day", -1.0], ["+day", 1.0], ["+1/8 year", 0.125]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var step: float = entry[1] # a day, or a share of the year
		button.pressed.connect(func() -> void:
			_planet.jump_time(step if absf(step) >= 1.0 else step * _planet.clock.year_days))
		jumps.add_child(button)
	_label("Hour of the day")
	_hour_slider = HSlider.new()
	_hour_slider.max_value = 24.0
	_hour_slider.step = 0.05
	_hour_slider.value_changed.connect(func(hours: float) -> void:
		if _hour_slider.get_global_rect().has_point(_hour_slider.get_global_mouse_position()):
			_planet.set_hour(hours))
	add_child(_hour_slider)
	_label("Day of the year (0: northern spring equinox)")
	_year_slider = HSlider.new()
	_year_slider.max_value = 1.0
	_year_slider.step = 0.002
	_year_slider.value_changed.connect(func(share: float) -> void:
		if _year_slider.get_global_rect().has_point(_year_slider.get_global_mouse_position()):
			_planet.set_year_share(share))
	add_child(_year_slider)


func _add_weather_row() -> void:
	_label("Weather")
	_weather = OptionButton.new()
	_weather.add_item("Follow the planet's climate")
	for state_name: String in WorldWeather.State.keys():
		_weather.add_item("Force " + state_name.to_lower())
	_weather.item_selected.connect(func(index: int) -> void:
		_planet.weather_override = index - 1)
	add_child(_weather)


func _add_new_planet_rows() -> void:
	_label("A new planet (the scene is reloaded)")
	var row := HBoxContainer.new()
	add_child(row)
	var seed_label := Label.new()
	seed_label.text = "seed"
	row.add_child(seed_label)
	_seed_field = LineEdit.new()
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed_field)
	var radius_label := Label.new()
	radius_label.text = "  radius (m)"
	row.add_child(radius_label)
	_radius_field = LineEdit.new()
	_radius_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_radius_field)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	var make := Button.new()
	make.text = "Make this planet"
	make.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make.pressed.connect(func() -> void: _new_planet(_seed_field.text, _radius_field.text))
	buttons.add_child(make)
	var random := Button.new()
	random.text = "Random seed"
	random.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random.pressed.connect(func() -> void:
		_new_planet(str(randi() % 100000), _radius_field.text))
	buttons.add_child(random)


func _add_save_rows() -> void:
	_label("Saved planets (the land is made again from the seed)")
	var row := HBoxContainer.new()
	add_child(row)
	_save_name = LineEdit.new()
	_save_name.text = "world"
	_save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_save_name)
	var save := Button.new()
	save.text = "Save here"
	save.pressed.connect(_save_here)
	row.add_child(save)
	_saves = OptionButton.new()
	add_child(_saves)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	var open := Button.new()
	open.text = "Open"
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.pressed.connect(_open_selected)
	buttons.add_child(open)
	var remove := Button.new()
	remove.text = "Delete"
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.pressed.connect(_delete_selected)
	buttons.add_child(remove)
	_save_note = _label("")
	_fill_saves()


func _fill_saves() -> void:
	_saves.clear()
	for entry in PlanetSave.list():
		_saves.add_item("%s   (seed %d, radius %d m)" % [entry["name"], entry["seed"],
				int(entry["radius"])])
		_saves.set_item_metadata(_saves.item_count - 1, entry["name"])


func _selected_save() -> String:
	if _saves.item_count == 0 or _saves.selected < 0:
		return ""
	return str(_saves.get_item_metadata(_saves.selected))


func _save_here() -> void:
	var save_name := _save_name.text.strip_edges()
	if save_name == "":
		save_name = "world"
	var written := PlanetSave.save(_planet, save_name)
	_save_note.text = ("Saved '%s'" % save_name) if written else "Could not save '%s'" % save_name
	_fill_saves()


func _open_selected() -> void:
	var save_name := _selected_save()
	var data := PlanetSave.load_data(save_name)
	if data.is_empty():
		_save_note.text = "Nothing to open"
		return
	pending = PlanetSave.settings_from(data)
	pending_state = data.get("state", {})
	get_tree().paused = false
	get_tree().reload_current_scene()


func _delete_selected() -> void:
	var save_name := _selected_save()
	if save_name != "":
		PlanetSave.delete(save_name)
		_save_note.text = "Deleted '%s'" % save_name
	_fill_saves()


func _new_planet(seed_text: String, radius_text: String) -> void:
	var settings := _planet.settings.duplicate() as PlanetSettings
	var text := seed_text.strip_edges()
	settings.world_seed = int(text) if text.is_valid_int() else hash(text)
	if radius_text.strip_edges().is_valid_float():
		settings.radius = clampf(radius_text.to_float(), 2000.0, 6.4e6)
	pending = settings
	get_tree().paused = false
	get_tree().reload_current_scene()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label
