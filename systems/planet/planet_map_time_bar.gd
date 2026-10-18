class_name PlanetMapTimeBar
extends HBoxContainer
## The map's row of buttons that move time: the speed (backward too), a jump of a day or an
## eighth of a year, and a slider through the year, to watch the temperature (and the sun) change.

var _planet: PlanetWorld
var _season_slider: HSlider
var _rate_label: Label


func _init(planet: PlanetWorld) -> void:
	_planet = planet
	alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.text = "Time:  "
	add_child(title)
	for rate in [-1000, -100, -10, -1]:
		_button("%d×" % rate, func() -> void: _planet.time_rate = float(rate))
	_button("pause", func() -> void: _planet.time_rate = 0.0)
	for rate in [1, 10, 100, 1000]:
		_button("%d×" % rate, func() -> void: _planet.time_rate = float(rate))
	_button("-day", func() -> void: _planet.jump_time(-1.0))
	_button("+day", func() -> void: _planet.jump_time(1.0))
	_button("-1/8 year", func() -> void: _planet.jump_time(-_planet.clock.year_days / 8.0))
	_button("+1/8 year", func() -> void: _planet.jump_time(_planet.clock.year_days / 8.0))
	var year := Label.new()
	year.text = "  year:"
	add_child(year)
	_season_slider = HSlider.new()
	_season_slider.custom_minimum_size = Vector2(200.0, 0.0)
	_season_slider.max_value = 1.0
	_season_slider.step = 0.002
	_season_slider.focus_mode = Control.FOCUS_NONE
	_season_slider.value_changed.connect(func(value: float) -> void:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_planet.set_year_share(value))
	add_child(_season_slider)
	_rate_label = Label.new()
	add_child(_rate_label)


## Shows where the year is and how fast time runs.
func refresh() -> void:
	_season_slider.set_value_no_signal(_planet.clock.year_share())
	var rate := "paused" if _planet.time_rate == 0.0 else "%d×" % int(_planet.time_rate)
	_rate_label.text = "   " + rate


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	add_child(button)
