class_name WorldSwim
extends Node
## Water for the player: wading slows the walk, and deeper than a metre the body floats at the
## surface and swims (jump rises, crouch dives, the swim clips play). It runs after the player each
## physics frame (priority) and adjusts the velocity the player just made.

const WADE_FROM := 0.35 ## m of water on the feet that starts slowing the walk
const SWIM_FROM := 1.0 ## m deep (at the feet): floating, not standing
const FLOAT_DEPTH := 1.2 ## m the feet hang under the surface while floating (head and chest out)
const SWIM_SPEED := 0.6 ## swim speed limit, as a fraction of the player's walk speed
const WADE_SPEED := 0.75
const CURRENT_PUSH := 0.4 ## how much of a river's flow carries you (1 = all of it)
const CLIP_IDLE := &"Swim_Idle"
const CLIP_MOVE := &"Swim_Fwd"

var target: Player
var noise: TerrainNoise # where the water stands (sea or a lake)
var splash: WaterSplash # splashes and ripples
var ambience: WorldAmbience # the sound of a splash
var level := 0.0
var swimming := false
var underwater := false # the camera is under the surface

var _clip: StringName = &""
var _was_wet := false
var _ripple_time := 0.0
var _last_vy := 0.0


func _init() -> void:
	process_priority = 100 # after the player's own physics


func _physics_process(_delta: float) -> void:
	if target != null:
		update(target)


func update(player: Player) -> void:
	level = _water_level(player)
	var depth := level - player.global_position.y
	var was_swimming := swimming
	swimming = depth > SWIM_FROM or (swimming and depth > SWIM_FROM - 0.25)
	var camera := player.get_viewport().get_camera_3d()
	underwater = camera != null and camera.global_position.y < level - 0.05
	if swimming:
		var wanted := level - FLOAT_DEPTH
		var rise := clampf((wanted - player.global_position.y) * 4.0, -2.5, 2.5)
		if Input.is_action_pressed(&"jump"):
			rise = 2.5
		elif Input.is_action_pressed(&"crouch"):
			rise = -2.5
		player.velocity.y = rise
		# The player only steers on the ground (or just after leaving it), so a floating body has to
		# steer itself: otherwise a swimmer from a standstill never gets going, and one that lets go
		# of the keys never stops. A cap, not a multiplier (scaling every frame would compound).
		var swim_speed := player.walk_speed * SWIM_SPEED
		var look := Basis(Vector3.UP, player.head.global_rotation.y)
		var input := player.debug_movement_input
		var goal := look * Vector3(input.x, 0.0, input.y) * swim_speed
		var horizontal := Vector2(player.velocity.x, player.velocity.z).move_toward(
				Vector2(goal.x, goal.z),
				player.acceleration * get_physics_process_delta_time()).limit_length(swim_speed)
		player.velocity.x = horizontal.x
		player.velocity.z = horizontal.y
		_play(player, CLIP_MOVE if Vector2(player.velocity.x, player.velocity.z).length() > 0.5
				else CLIP_IDLE)
	elif depth > WADE_FROM and player.is_on_floor():
		player.velocity.x *= WADE_SPEED
		player.velocity.z *= WADE_SPEED
	if depth > 0.2: # a river current carries you along
		var flow := _flow(player)
		player.velocity.x += flow.x * CURRENT_PUSH
		player.velocity.z += flow.y * CURRENT_PUSH
	_water_effects(player, depth)
	if was_swimming and not swimming:
		_clip = &""
		player.body._debug_preview_active = false # the normal clips take over again


## Where the water stands under the player (a world's sea or lake; a planet overrides this).
func _water_level(player: Player) -> float:
	if noise == null:
		return level
	return noise.water_level(player.global_position.x, player.global_position.z)


## The river's current at the player, in x and z (a planet overrides this).
func _flow(player: Player) -> Vector2:
	if noise == null:
		return Vector2.ZERO
	return noise.rivers.flow_at(player.global_position.x, player.global_position.z)


func _play(player: Player, clip: StringName) -> void:
	if clip == _clip:
		return
	_clip = clip
	player.body.play_debug_anim(clip, 0.25)


## The splash when the feet meet the water, rings while wading, a wake while swimming.
func _water_effects(player: Player, depth: float) -> void:
	if splash == null:
		return
	var wet := depth > 0.12
	var at := Vector3(player.global_position.x, level, player.global_position.z)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if wet and not _was_wet:
		var strength := clampf(absf(_last_vy) / 6.0 + 0.4, 0.4, 1.5)
		splash.splash(at, strength)
		if ambience != null:
			ambience.splash(strength)
	_ripple_time -= get_physics_process_delta_time()
	if wet and speed > 0.5 and _ripple_time <= 0.0:
		_ripple_time = 0.22 if swimming else 0.42
		splash.ripple(at, 1.6 if swimming else 1.0)
		if swimming and speed > 1.5:
			splash.splash(at, 0.35)
	_was_wet = wet
	_last_vy = player.velocity.y
