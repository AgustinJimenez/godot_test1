class_name WorldSwim
extends Node
## Water for the player: wading slows the walk, and deeper than a metre the body floats at the
## surface and swims (jump rises, crouch dives, the swim clips play). It runs after the player each
## physics frame (priority) and adjusts the velocity the player just made.

const WADE_FROM := 0.35 ## m of water on the feet that starts slowing the walk
const SWIM_FROM := 1.0 ## m deep (at the feet): floating, not standing
const FLOAT_DEPTH := 1.2 ## m the feet hang under the surface while floating (head and chest out)
const SWIM_SPEED := 0.6 ## horizontal speed kept each frame while swimming
const WADE_SPEED := 0.75
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
	if noise != null:
		level = noise.water_level(player.global_position.x, player.global_position.z)
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
		player.velocity.x *= SWIM_SPEED
		player.velocity.z *= SWIM_SPEED
		_play(player, CLIP_MOVE if Vector2(player.velocity.x, player.velocity.z).length() > 0.5
				else CLIP_IDLE)
	elif depth > WADE_FROM and player.is_on_floor():
		player.velocity.x *= WADE_SPEED
		player.velocity.z *= WADE_SPEED
	if noise != null and depth > 0.2: # a river current carries you along
		var flow := noise.rivers.flow_at(player.global_position.x, player.global_position.z)
		player.velocity.x += flow.x * 0.8
		player.velocity.z += flow.y * 0.8
	_water_effects(player, depth)
	if was_swimming and not swimming:
		_clip = &""
		player.body._debug_preview_active = false # the normal clips take over again


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
