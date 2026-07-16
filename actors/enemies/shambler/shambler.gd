class_name Shambler
extends CharacterBody3D
## First enemy: slow, tanky, relentless. Same clip-borrowing trick as
## levels/animation_preview.gd - The Boss.fbx ships with no animation of its
## own, so the pack's standalone clip files (same Mixamo skeleton) get copied
## into its AnimationPlayer at runtime. No retargeting needed here since,
## unlike the player's MotusMan rig, source and target share one skeleton.

enum State { PATROL, INVESTIGATE, CHASE, ATTACK, SEARCH }

const CLIPS: Dictionary = {
	&"idle": "res://assets/models/action_adventure_pack/idle.fbx",
	&"walking": "res://assets/models/action_adventure_pack/walking.fbx",
	&"running": "res://assets/models/action_adventure_pack/running.fbx",
}
# No dedicated death clip in the pack; "hard landing" is the closest
# collapse-like motion and reuses the same borrow-a-clip trick.
const DEATH_CLIP := "res://assets/models/action_adventure_pack/hard landing.fbx"

@export var patrol_points: Array[NodePath] = []
@export var walk_speed: float = 1.1
@export var chase_speed: float = 2.4
@export var vision_range: float = 10.0
@export var vision_angle_deg: float = 60.0
@export var attack_range: float = 1.3
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.2
@export var lose_sight_time: float = 4.0
@export var search_time: float = 3.0
@export var turn_speed: float = 6.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: Health = $Health
@onready var boss_ap: AnimationPlayer = $Boss/AnimationPlayer

var state: State = State.PATROL
var _patrol_positions: Array[Vector3] = []
var _patrol_idx := 0
var _time_since_seen := 0.0
var _search_timer := 0.0
var _attack_cooldown_left := 0.0
var _current_anim := &""


func _ready() -> void:
	add_to_group(&"enemies")
	_setup_animations()
	health.died.connect(_on_died)
	for path: NodePath in patrol_points:
		var point := get_node_or_null(path) as Node3D
		if point:
			_patrol_positions.append(point.global_position)
	_go_to_patrol_point()


func _setup_animations() -> void:
	var lib := AnimationLibrary.new()
	for clip: StringName in CLIPS:
		var inst: Node = (load(CLIPS[clip]) as PackedScene).instantiate()
		var src: AnimationPlayer = inst.get_node("AnimationPlayer")
		var anim: Animation = src.get_animation(&"mixamo_com").duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip, anim)
		inst.queue_free()
	var death_inst: Node = (load(DEATH_CLIP) as PackedScene).instantiate()
	var death_anim: Animation = (death_inst.get_node("AnimationPlayer") as AnimationPlayer)\
			.get_animation(&"mixamo_com").duplicate()
	death_anim.loop_mode = Animation.LOOP_NONE
	lib.add_animation(&"death", death_anim)
	death_inst.queue_free()
	boss_ap.add_animation_library(&"pack", lib)
	_play(&"idle")


func _physics_process(delta: float) -> void:
	if health.is_dead():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if not player:
		return
	_update_perception(player, delta)
	match state:
		State.PATROL:
			_process_patrol(delta)
		State.INVESTIGATE:
			_process_investigate(delta)
		State.CHASE:
			_process_chase(player, delta)
		State.ATTACK:
			_process_attack(player, delta)
		State.SEARCH:
			_process_search(delta)


func _update_perception(player: Node3D, delta: float) -> void:
	var seen := _can_see_player(player)
	if seen:
		_time_since_seen = 0.0
		if state == State.PATROL or state == State.INVESTIGATE or state == State.SEARCH:
			state = State.CHASE
		return
	_time_since_seen += delta
	if state == State.CHASE and _time_since_seen > lose_sight_time:
		state = State.SEARCH
		_search_timer = 0.0
		nav_agent.target_position = player.global_position
	elif state == State.PATROL and _can_hear_player(player):
		state = State.INVESTIGATE
		nav_agent.target_position = player.global_position


func _can_see_player(player: Node3D) -> bool:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > vision_range:
		return false
	var forward := -global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(Vector3(to_player.x, 0.0, to_player.z).normalized()))
	if angle > vision_angle_deg * 0.5:
		return false
	var eye_pos := global_position + Vector3(0, 1.6, 0)
	var target_pos := player.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(eye_pos, target_pos, 1)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _can_hear_player(player: Node3D) -> bool:
	var noise: float = player.noise_radius()
	if noise <= 0.0:
		return false
	return global_position.distance_to(player.global_position) <= noise


func _process_patrol(delta: float) -> void:
	if _patrol_positions.is_empty():
		_play(&"idle")
		return
	_play(&"walking")
	_move_toward_target(walk_speed, delta)
	if nav_agent.is_navigation_finished():
		_patrol_idx = (_patrol_idx + 1) % _patrol_positions.size()
		_go_to_patrol_point()


func _process_investigate(delta: float) -> void:
	_play(&"walking")
	_move_toward_target(walk_speed, delta)
	if nav_agent.is_navigation_finished():
		state = State.PATROL
		_go_to_patrol_point()


func _process_chase(player: Node3D, delta: float) -> void:
	_play(&"running")
	nav_agent.target_position = player.global_position
	_move_toward_target(chase_speed, delta)
	if global_position.distance_to(player.global_position) <= attack_range:
		state = State.ATTACK
		_attack_cooldown_left = 0.0


func _process_attack(player: Node3D, delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()
	_face_point(player.global_position, delta)
	_play(&"idle")
	_attack_cooldown_left -= delta
	if _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = attack_cooldown
		if global_position.distance_to(player.global_position) <= attack_range * 1.3:
			var target_health := player.get_node_or_null(^"Health") as Health
			if target_health:
				target_health.apply_damage(attack_damage)
	if global_position.distance_to(player.global_position) > attack_range * 1.5:
		state = State.CHASE


func _process_search(delta: float) -> void:
	_play(&"walking")
	_move_toward_target(walk_speed, delta)
	if nav_agent.is_navigation_finished():
		_search_timer += delta
		if _search_timer > search_time:
			state = State.PATROL
			_go_to_patrol_point()


func _go_to_patrol_point() -> void:
	if _patrol_positions.is_empty():
		return
	nav_agent.target_position = _patrol_positions[_patrol_idx]


func _move_toward_target(speed: float, delta: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		move_and_slide()
		return
	var next_pos := nav_agent.get_next_path_position()
	var dir := next_pos - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
		_face_direction(dir, delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _face_direction(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _face_point(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		_face_direction(dir.normalized(), delta)


func _play(anim_name: StringName) -> void:
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	boss_ap.play("pack/" + anim_name, 0.2)


func _on_died() -> void:
	set_physics_process(false)
	collision_layer = 0
	_current_anim = &"death"
	boss_ap.play("pack/death", 0.15)
