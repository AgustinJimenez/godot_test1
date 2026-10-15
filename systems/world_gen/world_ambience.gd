class_name WorldAmbience
extends Node
## The sound of the world, made from noise and sine waves while it plays (no audio files): wind that
## rises and falls with the gusts, rain hiss, waves lapping near the sea, birdsong by day, crickets
## by night, and thunder that rolls in a moment after each lightning flash.

const RATE := 22050.0

var wind := 0.1 # 0..1
var rain := 0.0 # 0..1
var daylight := 1.0 # 0 night .. 1 day
var shore := 0.0 # 0 far from water .. 1 at the water
var underwater := false

var _player := AudioStreamPlayer.new()
var _playback: AudioStreamGeneratorPlayback
var _time := 0.0
var _wind_filter := 0.0
var _water_filter := 0.0
var _thunder_filter := 0.0
var _rain_previous := 0.0
var _chirp_left := 0.0
var _chirp_length := 0.1
var _chirp_pitch := 3000.0
var _chirp_phase := 0.0
var _next_chirp := 2.0
var _thunder_delay := -1.0
var _thunder_left := 0.0
var _muffle := 0.0
var _splash_left := 0.0
var _splash_amount := 0.0


func _ready() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = 0.25
	_player.stream = stream
	_player.volume_db = -9.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## A splash of water now (`strength` 0.3 .. 1.5): a short burst of filtered noise.
func splash(strength: float) -> void:
	_splash_left = 0.35
	_splash_amount = strength


## A roll of thunder, `delay` seconds from now (a flash was just seen).
func thunder(delay: float) -> void:
	_thunder_delay = delay


func _process(delta: float) -> void:
	if _playback == null:
		return
	_next_chirp -= delta
	if _next_chirp <= 0.0 and daylight > 0.4 and rain < 0.3:
		_next_chirp = randf_range(0.8, 4.0)
		_chirp_length = randf_range(0.06, 0.16)
		_chirp_left = _chirp_length
		_chirp_pitch = randf_range(2200.0, 4200.0)
	if _thunder_delay >= 0.0:
		_thunder_delay -= delta
		if _thunder_delay < 0.0:
			_thunder_left = randf_range(1.8, 3.2)
	var step := 1.0 / RATE
	var night := 1.0 - daylight
	for index in _playback.get_frames_available():
		_time += step
		var noise := randf() * 2.0 - 1.0
		_wind_filter += (noise - _wind_filter) * (0.015 + wind * 0.08)
		var gust := 0.6 + 0.4 * sin(_time * 0.7 + sin(_time * 0.23) * 2.0)
		var sample := _wind_filter * (0.3 + wind * 2.2) * gust
		_rain_previous = noise
		sample += (noise - _rain_previous * 0.5) * rain * 0.07
		_water_filter += (noise - _water_filter) * 0.004
		sample += _water_filter * shore * 5.0 * (0.55 + 0.45 * sin(_time * 0.45))
		if night > 0.3 and rain < 0.3: # crickets: short buzzing pulses
			var pulse := maxf(sin(_time * TAU * 7.0), 0.0)
			sample += sin(_time * TAU * 4300.0) * pulse * pulse * 0.025 * night
		if _chirp_left > 0.0:
			_chirp_left -= step
			var along := 1.0 - _chirp_left / _chirp_length
			_chirp_phase += TAU * (_chirp_pitch * (1.0 + along * 0.5)) * step
			sample += sin(_chirp_phase) * sin(along * PI) * 0.06 * daylight
		if _splash_left > 0.0:
			_splash_left -= step
			sample += noise * _splash_left * 2.2 * _splash_amount * (0.4 + 0.6 * _splash_left / 0.35)
		if _thunder_left > 0.0:
			_thunder_left -= step
			_thunder_filter += (noise - _thunder_filter) * 0.01
			sample += _thunder_filter * minf(_thunder_left, 1.0) * 6.0
		_muffle += (sample - _muffle) * (0.12 if underwater else 1.0) # under water: duller
		var out := clampf(_muffle, -1.0, 1.0)
		_playback.push_frame(Vector2(out, out))
