class_name Shambler
extends CharacterBody3D
## First enemy: slow, tanky, relentless. Same clip-borrowing trick as
## tests/manual/animation/animation_preview.gd - The Boss.fbx ships with no animation of its
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
@export var attack_range: float = 1.3
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.2
@export var lose_sight_time: float = 4.0
@export var search_time: float = 3.0
@export var turn_speed: float = 6.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: Health = $Health
@onready var perception: Perception = $Perception
@onready var boss_ap: AnimationPlayer = $Boss/AnimationPlayer

var state: State = State.PATROL
var _patrol_positions: Array[Vector3] = []
var _patrol_idx := 0
var _time_since_seen := 0.0
var _search_timer := 0.0
var _attack_cooldown_left := 0.0
var _current_anim := &""
var _nav_target := Vector3.ZERO


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
	build_clip_library(boss_ap)
	_play(&"idle")


## Borrows CLIPS + DEATH_CLIP's standalone animations into anim_player's own
## "pack" library, exactly the trick tests/manual/animation/animation_preview.gd
## also uses. Extracted to a static function so tools/character_editor's
## ShamblerAdapter can build the same library on a bare Boss.fbx instance
## without needing a full Shambler (CharacterBody3D + AI/nav/patrol) - the
## editor tool has no use for any of that.
static func build_clip_library(anim_player: AnimationPlayer) -> void:
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
	anim_player.add_animation_library(&"pack", lib)


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
	if perception.can_see(player):
		_time_since_seen = 0.0
		if state == State.PATROL or state == State.INVESTIGATE or state == State.SEARCH:
			state = State.CHASE
		return
	_time_since_seen += delta
	if state == State.CHASE and _time_since_seen > lose_sight_time:
		state = State.SEARCH
		_search_timer = 0.0
		_nav_target = player.global_position
	elif state == State.PATROL and perception.can_hear(player):
		state = State.INVESTIGATE
		_nav_target = player.global_position


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
	_nav_target = player.global_position
	_move_toward_target(chase_speed, delta)
	if global_position.distance_to(player.global_position) <= attack_range:
		state = State.ATTACK
		_attack_cooldown_left = 0.0


func _process_attack(player: Node3D, delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
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
	_nav_target = _patrol_positions[_patrol_idx]


func _move_toward_target(speed: float, delta: float) -> void:
	# Reapplied every frame, not just on state entry: if this lands before
	# the room's navmesh finishes its runtime bake, the agent finds no path
	# and - since it then never moves - nothing else would prompt it to
	# retry once the navmesh becomes ready.
	nav_agent.target_position = _nav_target
	var dir := Vector3.ZERO
	if not nav_agent.is_navigation_finished():
		dir = nav_agent.get_next_path_position() - global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			dir = dir.normalized()
			_face_direction(dir, delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta


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
