class_name WorldWeather
extends Node3D
## The weather over the world: clear, cloudy, rain, storm, fog, snow. Every number (clouds, sky
## greying, fog, rain, wind) eases toward the state's preset, so one weather melts into the next.
## In `auto` mode it picks a new weather now and then. Rain turns to snow where it is cold. Storms
## throw lightning. Wind also drives the plants (WorldWind) and the drifting clouds.

enum State { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }

## cover, darkness (clouds), overcast (sky), rain (0..1), wind, fog (extra density)
const PRESETS := {
	State.CLEAR: [0.25, 0.0, 0.0, 0.0, 0.12, 0.0],
	State.CLOUDY: [0.7, 0.35, 0.45, 0.0, 0.28, 0.0008],
	State.RAIN: [0.9, 0.6, 0.7, 0.6, 0.5, 0.002],
	State.STORM: [1.0, 0.95, 0.95, 1.0, 0.95, 0.003],
	State.FOG: [0.5, 0.2, 0.4, 0.0, 0.05, 0.012],
	State.SNOW: [0.9, 0.45, 0.6, 0.55, 0.3, 0.003],
}
## Which weathers may follow which (a clear day does not turn into a storm at once).
const NEXT := {
	State.CLEAR: [State.CLEAR, State.CLOUDY, State.FOG],
	State.CLOUDY: [State.CLEAR, State.CLOUDY, State.RAIN, State.FOG, State.SNOW],
	State.RAIN: [State.CLOUDY, State.RAIN, State.STORM],
	State.STORM: [State.RAIN, State.CLOUDY],
	State.FOG: [State.CLEAR, State.CLOUDY],
	State.SNOW: [State.CLOUDY, State.SNOW],
}

@export var auto := false
@export var change_every := 120.0 ## s between weathers in auto mode
@export var blend_seconds := 18.0
var forced_wind := Vector2.ZERO ## a planet gives the real wind direction here (zero: it wanders)

var state := State.CLEAR
var clouds := WorldClouds.new()
var rain := RainEffect.new()
var atmosphere: WorldAtmosphere
var noise: TerrainNoise
var wetness := 0.0 # 0 dry .. 1 soaked
var snow := 0.0 # 0 bare .. 1 covered
var _thunder_pending := false

var _values: Array[float] = [0.25, 0.0, 0.0, 0.0, 0.12, 0.0]
var _since_change := 0.0
var _storm_timer := 8.0
var _flash := 0.0
var _flash_left := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_child(clouds)
	add_child(rain)


func set_state(next: State) -> void:
	state = next
	_since_change = 0.0


func state_name() -> String:
	return State.keys()[state].capitalize()


func wind_strength() -> float:
	return _values[4]


func update(target: Vector3, delta: float) -> void:
	_time += delta
	_since_change += delta
	if auto and _since_change > change_every:
		var options: Array = NEXT[state]
		set_state(options[_rng.randi() % options.size()])
	var preset: Array = PRESETS[state]
	for index in _values.size():
		_values[index] = move_toward(_values[index], preset[index], delta / blend_seconds
				* maxf(absf(float(preset[index]) - _values[index]), 0.25))
	var wind_dir := Vector2.RIGHT.rotated(0.35 + sin(_time * 0.013) * 1.1)
	if forced_wind != Vector2.ZERO:
		wind_dir = forced_wind.normalized()
	WorldWind.set_wind(_values[4], wind_dir)
	clouds.wind = wind_dir
	clouds.cover = _values[0]
	clouds.darkness = _values[1]
	clouds.follow(target, _values[4], delta)
	var cold := noise != null and noise.heat(target.x, target.z, target.y) < 0.3
	rain.snowing = state == State.SNOW or (cold and _values[3] > 0.0)
	rain.amount_ratio = _values[3]
	rain.follow(target, wind_dir, _values[4])
	_wet(delta)
	_lightning(delta)
	if atmosphere != null:
		atmosphere.overcast = _values[2]
		atmosphere.fog_extra = _values[5]
		atmosphere.cloud_cover = _values[0]
		atmosphere.cloud_dark = _values[1]
		atmosphere.flash = _flash


func _wet(delta: float) -> void:
	var soaking := _values[3] > 0.1 and not rain.snowing
	wetness = move_toward(wetness, 1.0 if soaking else 0.0, delta / (20.0 if soaking else 90.0))
	var snowing := _values[3] > 0.1 and rain.snowing
	snow = move_toward(snow, 1.0 if snowing else 0.0, delta / (45.0 if snowing else 240.0))
	WorldWind.set_surface(wetness, snow, 0.0 if rain.snowing else _values[3])


func _lightning(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if state != State.STORM:
		return
	_storm_timer -= delta
	if _storm_timer <= 0.0:
		_storm_timer = _rng.randf_range(5.0, 16.0)
		_thunder_pending = true
		_flash = 1.0
		_flash_left = 0.18 # a second, weaker flash right behind the first
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash = 0.7


## Jumps to a weather at once (no easing): labs and screenshots.
func snap(next: State) -> void:
	set_state(next)
	var preset: Array = PRESETS[next]
	for index in _values.size():
		_values[index] = preset[index]
	snow = 1.0 if next == State.SNOW else 0.0
	wetness = 1.0 if next == State.RAIN or next == State.STORM else 0.0


## How hard it rains or snows now (0..1).
func rain_amount() -> float:
	return _values[3]


## True once after each lightning strike (so the sound can follow it).
func pop_thunder() -> bool:
	var was := _thunder_pending
	_thunder_pending = false
	return was
