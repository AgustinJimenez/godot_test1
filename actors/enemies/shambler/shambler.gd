class_name Shambler
extends CharacterBody3D
## First enemy: slow, tanky, relentless. Same clip-borrowing trick as
## tests/manual/animation/animation_preview.gd - the configured character
## uses the same Mixamo skeleton as the standalone action-pack clips, so they
## are copied into its AnimationPlayer at runtime without retargeting.

enum State { PATROL, INVESTIGATE, CHASE, ATTACK, SEARCH }

const CLIPS: Dictionary = {
	&"idle": "res://assets/models/action_adventure_pack/idle.fbx",
	&"walking": "res://assets/models/action_adventure_pack/walking.fbx",
	&"running": "res://assets/models/action_adventure_pack/running.fbx",
}
# No dedicated death clip in the pack; "hard landing" is the closest
# collapse-like motion and reuses the same borrow-a-clip trick.
const DEATH_CLIP := "res://assets/models/action_adventure_pack/hard landing.fbx"
const SOURCE_BONE_PREFIX := "mixamorig_"

@export var patrol_points: Array[NodePath] = []
@export var character_scene: PackedScene
@export var character_bone_prefix := SOURCE_BONE_PREFIX
@export var character_yaw_offset_deg := 180.0
@export var walk_speed: float = 1.1
@export var chase_speed: float = 2.4
@export var attack_range: float = 1.3
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.2
@export var attack_windup: float = 0.4
@export_range(1.0, 90.0, 1.0) var attack_facing_angle_deg: float = 12.0
@export var lose_sight_time: float = 4.0
@export var search_time: float = 3.0
@export var turn_speed: float = 6.0
@export var show_facing_debug := true

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: Health = $Health
@onready var perception: Perception = $Perception
var character: Node3D
var boss_ap: AnimationPlayer
var _character_rest_position := Vector3.ZERO
var _character_rest_rotation := Vector3.ZERO
var _attack_tween: Tween

var state: State = State.PATROL
var _patrol_positions: Array[Vector3] = []
var _patrol_idx := 0
var _time_since_seen := 0.0
var _search_timer := 0.0
var _attack_cooldown_left := 0.0
var _attack_windup_left := 0.0
var _attack_turn_locked := false
var _current_anim := &""
var _nav_target := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"enemies")
	_setup_character()
	_setup_facing_debug()
	if boss_ap == null:
		push_error("Shambler character scene needs an AnimationPlayer")
		set_physics_process(false)
		return
	_setup_animations()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	for path: NodePath in patrol_points:
		var point := get_node_or_null(path) as Node3D
		if point:
			_patrol_positions.append(point.global_position)
	_go_to_patrol_point()


func _setup_character() -> void:
	if character_scene == null:
		return
	character = character_scene.instantiate() as Node3D
	if character == null:
		return
	character.name = &"Character"
	add_child(character)
	# These Mixamo FBXs are authored facing +Z, opposite Godot's -Z actor
	# forward. Keep the correction on the visual child so AI/navigation retain
	# the engine convention and alternative character assets remain configurable.
	character.rotation.y += deg_to_rad(character_yaw_offset_deg)
	_character_rest_position = character.position
	_character_rest_rotation = character.rotation
	boss_ap = character.find_child("AnimationPlayer", true, false) as AnimationPlayer


## Bright body-forward arrow used to distinguish AI yaw from an imported
## character visual whose authored forward axis may not match the actor.
func _setup_facing_debug() -> void:
	if not show_facing_debug:
		return
	var arrow := Node3D.new()
	arrow.name = &"FacingDebugArrow"
	arrow.position = Vector3(0.0, 2.25, 0.0)
	add_child(arrow)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.08, 0.04)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.5
	material.no_depth_test = true
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.025
	shaft_mesh.bottom_radius = 0.025
	shaft_mesh.height = 0.8
	shaft_mesh.material = material
	var shaft := MeshInstance3D.new()
	shaft.mesh = shaft_mesh
	shaft.position.z = -0.4
	shaft.rotation_degrees.x = -90.0
	arrow.add_child(shaft)
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.3
	head_mesh.material = material
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.position.z = -0.92
	head.rotation_degrees.x = -90.0
	arrow.add_child(head)


func _setup_animations() -> void:
	build_clip_library(boss_ap, character_bone_prefix)
	_play(&"idle")


## Borrows CLIPS + DEATH_CLIP's standalone animations into anim_player's own
## "pack" library, exactly the trick tests/manual/animation/animation_preview.gd
## also uses. Extracted to a static function so tools/character_editor's
## MixamoCharacterAdapter can build the same library on a bare Mixamo FBX
## instance without needing a full Shambler (CharacterBody3D + AI/nav/
## patrol) - the editor tool has no use for any of that.
static func build_clip_library(anim_player: AnimationPlayer,
		target_bone_prefix: String = SOURCE_BONE_PREFIX) -> void:
	var lib := AnimationLibrary.new()
	for clip: StringName in CLIPS:
		var inst: Node = (load(CLIPS[clip]) as PackedScene).instantiate()
		var src: AnimationPlayer = inst.get_node("AnimationPlayer")
		var anim: Animation = src.get_animation(&"mixamo_com").duplicate()
		if clip == &"walking" or clip == &"running":
			_make_clip_in_place(anim)
		_rewrite_bone_prefix(anim, target_bone_prefix)
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip, anim)
		inst.queue_free()
	var death_inst: Node = (load(DEATH_CLIP) as PackedScene).instantiate()
	var death_anim: Animation = (death_inst.get_node("AnimationPlayer") as AnimationPlayer)\
			.get_animation(&"mixamo_com").duplicate()
	_rewrite_bone_prefix(death_anim, target_bone_prefix)
	death_anim.loop_mode = Animation.LOOP_NONE
	lib.add_animation(&"death", death_anim)
	death_inst.queue_free()
	anim_player.add_animation_library(&"pack", lib)


## Mixamo's walk/run files translate the hips several meters per cycle. The
## CharacterBody3D already owns movement, so retaining that displacement makes
## the mesh run ahead and snap back at every loop. Remove only the accumulated
## horizontal travel; vertical bob and cyclic stride offsets remain intact.
static func _make_clip_in_place(animation: Animation) -> void:
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track_index)).ends_with("Hips"):
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2 or animation.length <= 0.0:
			return
		var first := animation.track_get_key_value(track_index, 0) as Vector3
		var last := animation.track_get_key_value(track_index, key_count - 1) as Vector3
		var travel := Vector3(last.x - first.x, 0.0, last.z - first.z)
		for key_index in key_count:
			var progress := animation.track_get_key_time(track_index, key_index) / animation.length
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			animation.track_set_key_value(track_index, key_index, value - travel * progress)
		return


static func _rewrite_bone_prefix(animation: Animation, target_bone_prefix: String) -> void:
	if target_bone_prefix == SOURCE_BONE_PREFIX:
		return
	var source_marker := ":" + SOURCE_BONE_PREFIX
	var target_marker := ":" + target_bone_prefix
	for track_index in animation.get_track_count():
		var path_text := String(animation.track_get_path(track_index))
		if source_marker in path_text:
			animation.track_set_path(
					track_index, NodePath(path_text.replace(source_marker, target_marker)))


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
	_move_toward_target(chase_speed, delta, player)
	if global_position.distance_to(player.global_position) <= attack_range:
		state = State.ATTACK
		_attack_cooldown_left = 0.0
		_attack_windup_left = 0.0


func _process_attack(player: Node3D, delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if not _attack_turn_locked:
		_face_point(player.global_position, delta)
	_play(&"idle")
	var distance := global_position.distance_to(player.global_position)
	if distance > attack_range * 1.5:
		_attack_windup_left = 0.0
		_cancel_attack_visual()
		state = State.CHASE
		return
	if _attack_windup_left > 0.0:
		_attack_windup_left = maxf(_attack_windup_left - delta, 0.0)
		if _attack_windup_left == 0.0 and distance <= attack_range * 1.3:
			_deal_attack_damage(player)
		return
	_attack_cooldown_left -= delta
	if (_attack_cooldown_left <= 0.0
			and _is_facing_point(player.global_position, attack_facing_angle_deg)):
		_attack_cooldown_left = attack_cooldown
		_attack_windup_left = maxf(attack_windup, 0.0)
		_begin_attack_visual()
		if _attack_windup_left == 0.0:
			_deal_attack_damage(player)


func _deal_attack_damage(player: Node3D) -> void:
	var target_health := player.get_node_or_null(^"Health") as Health
	if target_health:
		target_health.apply_damage(attack_damage)


## Temporary readable telegraph until a Mixamo-compatible zombie strike clip
## is imported: pull back, lunge at contact, then recover. This only translates
## the visual child; navigation and collision remain authoritative.
func _begin_attack_visual() -> void:
	if character == null:
		return
	_cancel_attack_visual()
	_attack_turn_locked = true
	character.position = _character_rest_position
	var windup_first := maxf(attack_windup * 0.6, 0.01)
	var windup_second := maxf(attack_windup - windup_first, 0.01)
	_attack_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_attack_tween.tween_property(character, ^"position",
			_character_rest_position + Vector3(0.0, 0.0, 0.04), windup_first)
	_attack_tween.tween_property(character, ^"position",
			_character_rest_position + Vector3(0.0, 0.0, -0.12), windup_second)
	_attack_tween.tween_property(character, ^"position", _character_rest_position, 0.25)
	_attack_tween.finished.connect(_finish_attack_visual)


func _finish_attack_visual() -> void:
	_attack_tween = null
	_attack_turn_locked = false
	if character != null:
		character.position = _character_rest_position
		character.rotation = _character_rest_rotation


func _cancel_attack_visual() -> void:
	if _attack_tween != null:
		_attack_tween.kill()
		_attack_tween = null
	_attack_turn_locked = false
	if character != null:
		character.position = _character_rest_position
		character.rotation = _character_rest_rotation


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


func _move_toward_target(speed: float, delta: float, look_target: Node3D = null) -> void:
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
			if look_target:
				_face_point(look_target.global_position, delta)
			else:
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
	if _attack_turn_locked:
		return
	# Godot's forward axis is -Z; positive Y rotation turns it toward -X.
	# Negating X therefore maps a world-space direction to the matching yaw.
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _face_point(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		_face_direction(dir.normalized(), delta)


func _is_facing_point(point: Vector3, tolerance_deg: float) -> bool:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		return true
	return (-global_basis.z).dot(dir.normalized()) >= cos(deg_to_rad(tolerance_deg))


func _play(anim_name: StringName) -> void:
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	boss_ap.play("pack/" + anim_name, 0.2)


func _on_died() -> void:
	set_physics_process(false)
	collision_layer = 0
	_cancel_attack_visual()
	_current_anim = &"death"
	boss_ap.play("pack/death", 0.15)


func _on_damaged(_amount: float) -> void:
	if health.is_dead():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player:
		state = State.CHASE
		_time_since_seen = 0.0
		_nav_target = player.global_position
