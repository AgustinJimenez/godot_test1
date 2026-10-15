class_name ProceduralWorldMenu
extends VBoxContainer
## The "World" page of the Esc menu: style, weather, time of day, autumn and the seed. Only the
## procedural world level adds it (through the HUD's add_menu_page), so other scenes never see it.

var _level: Node # levels/procedural_world.gd: owns `world`, set_realistic() and apply_seed()
var _world: ProceduralWorld
var _style_buttons: Array[Button] = []
var _sky_buttons: Array[Button] = []
var _weather: OptionButton
var _auto_weather: CheckButton
var _time_slider: HSlider
var _time_label: Label
var _day_cycle: CheckButton
var _autumn: CheckButton
var _seed_field: LineEdit


func setup(level: Node, world: ProceduralWorld) -> void:
	_level = level
	_world = world
	custom_minimum_size = Vector2(360, 0)
	_add_style_row()
	_add_sky_row()
	_add_weather_rows()
	_add_time_rows()
	_autumn = _check("Autumn colours", func(on: bool) -> void: _world.autumn = 1.0 if on else 0.0)
	_add_seed_row()


func refresh() -> void:
	_style_buttons[1 if _level.realistic else 0].set_pressed_no_signal(true)
	_sky_buttons[1 if _world.atmosphere.sky3d_on else 0].set_pressed_no_signal(true)
	_weather.select(_world.weather.state)
	_auto_weather.set_pressed_no_signal(_world.weather.auto)
	_day_cycle.set_pressed_no_signal(_world.atmosphere.day_seconds > 0.0)
	_autumn.set_pressed_no_signal(_world.autumn > 0.5)
	_seed_field.text = str(_world.settings.world_seed)
	_sync_time()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_sync_time() # follows the clock when the day cycle runs


func _sync_time() -> void:
	var hours := _world.atmosphere.time_of_day
	_time_slider.set_value_no_signal(hours)
	_time_label.text = "Time of day  %02d:%02d" % [int(hours), int(fposmod(hours, 1.0) * 60.0)]


func _add_style_row() -> void:
	_label("Style")
	var row := HBoxContainer.new()
	add_child(row)
	var group := ButtonGroup.new()
	for style in ["Low-poly", "Realistic"]:
		var button := Button.new()
		button.text = style
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _level.set_realistic(style == "Realistic"))
		row.add_child(button)
		_style_buttons.append(button)


func _add_sky_row() -> void:
	_label("Sky")
	var row := HBoxContainer.new()
	add_child(row)
	var group := ButtonGroup.new()
	for sky in ["Built-in", "Sky3D"]:
		var button := Button.new()
		button.text = sky
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _world.atmosphere.use_sky3d(sky == "Sky3D"))
		row.add_child(button)
		_sky_buttons.append(button)


func _add_weather_rows() -> void:
	_label("Weather")
	_weather = OptionButton.new()
	for state_name: String in WorldWeather.State.keys():
		_weather.add_item(state_name.capitalize())
	_weather.item_selected.connect(func(index: int) -> void:
		_world.weather.set_state(index as WorldWeather.State))
	add_child(_weather)
	_auto_weather = _check("Weather changes by itself",
			func(on: bool) -> void: _world.weather.auto = on)


func _add_time_rows() -> void:
	_time_label = _label("Time of day")
	_time_slider = HSlider.new()
	_time_slider.max_value = 24.0
	_time_slider.step = 0.05
	_time_slider.value_changed.connect(func(hours: float) -> void:
		_world.atmosphere.time_of_day = hours)
	add_child(_time_slider)
	_day_cycle = _check("Day cycle",
			func(on: bool) -> void: _world.atmosphere.day_seconds = 240.0 if on else 0.0)


func _add_seed_row() -> void:
	_label("Seed")
	var row := HBoxContainer.new()
	add_child(row)
	_seed_field = LineEdit.new()
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_field.text_submitted.connect(func(_text: String) -> void: _apply_typed_seed())
	row.add_child(_seed_field)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_apply_typed_seed)
	row.add_child(apply)
	var random := Button.new()
	random.text = "Random"
	random.pressed.connect(func() -> void:
		_level.apply_seed(randi() % 100000)
		refresh())
	row.add_child(random)


func _apply_typed_seed() -> void:
	var text := _seed_field.text.strip_edges()
	_level.apply_seed(int(text) if text.is_valid_int() else hash(text)) # words work as seeds too
	refresh()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label


func _check(text: String, on_toggled: Callable) -> CheckButton:
	var button := CheckButton.new()
	button.text = text
	button.toggled.connect(on_toggled)
	add_child(button)
	return button
