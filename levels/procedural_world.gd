extends Node3D
## The generated world to walk around in. Debug keys: F1 next weather, F2 +3 hours, F3 day cycle
## on / off, F4 a new seed (the whole world is rebuilt), F5 weather changes by itself on / off.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var world: ProceduralWorld
var player: Player
var _label: Label
var realistic := false # the style the world is moving toward (F9)


func _ready() -> void:
	world = ProceduralWorld.new()
	world.settings = WorldSettings.new()
	add_child(world)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	world.set_target(player)
	world.generator.chunks_per_frame = 2
	_spawn()
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)


func _spawn() -> void:
	world.build_around(Vector3.ZERO)
	player.global_position = Vector3(0.0, world.ground_height(0.0, 0.0) + 0.5, 0.0)
	player.velocity = Vector3.ZERO


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			world.weather.set_state(
					(world.weather.state + 1) % WorldWeather.State.size() as WorldWeather.State)
		KEY_F5:
			world.weather.auto = not world.weather.auto
		KEY_F9:
			realistic = not realistic
		KEY_F6:
			world.autumn = 0.0 if world.autumn > 0.5 else 1.0
		KEY_F2:
			world.atmosphere.time_of_day = fposmod(world.atmosphere.time_of_day + 3.0, 24.0)
		KEY_F3:
			world.atmosphere.day_seconds = 0.0 if world.atmosphere.day_seconds > 0.0 else 240.0
		KEY_F4:
			world.settings.world_seed = randi() % 100000
			world.rebuild()
			_spawn()


func _process(_delta: float) -> void:
	world.realism = move_toward(world.realism, 1.0 if realistic else 0.0, _delta * 0.8)
	_label.text = ("Procedural world  seed %d   %02d:%02d%s   weather: %s%s\n"
			+ "[F1] weather  [F2] +3 h  [F3] day cycle  [F4] new seed  [F5] auto weather\n"
			+ "[F6] autumn  [F9] realistic") % [
			world.settings.world_seed, int(world.atmosphere.time_of_day),
			int(fposmod(world.atmosphere.time_of_day, 1.0) * 60.0),
			" (cycle)" if world.atmosphere.day_seconds > 0.0 else "", world.weather.state_name(),
			" (auto)" if world.weather.auto else ""]
