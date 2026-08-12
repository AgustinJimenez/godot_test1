class_name HumanoidActor
extends CharacterBody3D
## Biped-specific execution for an NPCController. Locomotion borrows the
## compatible Mixamo action pack; its strike is retargeted from UAL2 at startup.

const CLIPS: Dictionary = {
	&"idle": "res://assets/models/action_adventure_pack/idle.fbx",
	&"walking": "res://assets/models/action_adventure_pack/walking.fbx",
	&"running": "res://assets/models/action_adventure_pack/running.fbx",
}
# No dedicated death clip in the pack; "hard landing" is the closest
# collapse-like motion and reuses the same borrow-a-clip trick.
const DEATH_CLIP := "res://assets/models/action_adventure_pack/hard landing.fbx"
const ATTACK_SOURCE := "res://assets/models/universal_animation_library_2/UAL2_Standard.glb"
const ATTACK_SOURCE_CLIP := &"Zombie_Scratch"
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
@export_range(0.0, 1.0, 0.01) var attack_contact_ratio: float = 0.48
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 1.0
@export_range(1.0, 90.0, 1.0) var attack_facing_angle_deg: float = 12.0
@export var lose_sight_time: float = 4.0
@export var search_time: float = 3.0
@export var turn_speed: float = 6.0
@export var show_facing_debug := false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: Health = $Health
@onready var perception: Perception = $Perception
@onready var npc_controller: NPCController = $NPCController
var character: Node3D
var boss_ap: AnimationPlayer

var _patrol_positions: Array[Vector3] = []
var _patrol_idx := 0
var _time_since_seen := 0.0
var _search_timer := 0.0
var _attack_cooldown_left := 0.0
var _attack_animation_left := 0.0
var _attack_contact_emitted := false
var _attack_turn_locked := false
var _current_anim := &""
var _nav_target := Vector3.ZERO


func _ready() -> void:
	_setup_character()
	_setup_facing_debug()
	if boss_ap == null:
		push_error("HumanoidActor character scene needs an AnimationPlayer")
		set_physics_process(false)
		return
	_setup_animations()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	npc_controller.disposition_changed.connect(_on_disposition_changed)
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
	var target_skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	if target_skeleton == null:
		push_error("HumanoidActor character scene needs a Skeleton3D")
		return
	build_clip_library(boss_ap, target_skeleton, character_bone_prefix)
	_play(&"idle")


## Borrows CLIPS + DEATH_CLIP's standalone animations into anim_player's own
## "pack" library, exactly the trick tests/manual/animation/animation_preview.gd
## also uses. A static function so it doesn't need a full HumanoidActor
## (CharacterBody3D + AI/nav/patrol) to call.
##
## Retargets each clip for real via HumanoidRetargeter (same core
## player_body.gd now runs on - see CURRENT_TASK.md's Phase 3) instead of
## the previous _rewrite_bone_prefix() trick, which only ever relabeled an
## animation's track paths and copied its rotation/position values onto the
## target verbatim - correct only when source and target skeletons happen
## to share near-identical rest poses/proportions (true of the Mixamo-family
## skins used today, not guaranteed for an arbitrary catalog character).
static func build_clip_library(anim_player: AnimationPlayer, target_skeleton: Skeleton3D,
		target_bone_prefix: String = SOURCE_BONE_PREFIX) -> void:
	var target_humanoid_map := CharacterEditorRigHandler.full_map_from_prefix(
			target_skeleton, target_bone_prefix)
	var lib := AnimationLibrary.new()
	for clip: StringName in CLIPS:
		var anim := _retarget_action_clip(CLIPS[clip], target_skeleton, target_humanoid_map)
		if clip == &"walking" or clip == &"running":
			HumanoidRetargeter.make_clip_in_place(anim)
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip, anim)
	var death_anim := _retarget_action_clip(DEATH_CLIP, target_skeleton, target_humanoid_map)
	death_anim.loop_mode = Animation.LOOP_NONE
	lib.add_animation(&"death", death_anim)
	var attack_anim := UnrealMixamoAnimation.retarget_clip(
			ATTACK_SOURCE, ATTACK_SOURCE_CLIP, target_skeleton, target_bone_prefix)
	if attack_anim != null:
		attack_anim.loop_mode = Animation.LOOP_NONE
		lib.add_animation(&"attack", attack_anim)
	anim_player.add_animation_library(&"pack", lib)


## clip_path's own FBX ships one clip on one Skeleton3D+AnimationPlayer -
## describes that skeleton via prefix_role_map() (all the action-pack/death
## sources use the same "mixamorig_" convention SOURCE_BONE_PREFIX names)
## and retargets its "mixamo_com" animation onto target_skeleton.
static func _retarget_action_clip(clip_path: String, target_skeleton: Skeleton3D,
		target_humanoid_map: Dictionary) -> Animation:
	var inst: Node = (load(clip_path) as PackedScene).instantiate()
	var src_skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var src_ap: AnimationPlayer = inst.get_node("AnimationPlayer")
	var src_animation := src_ap.get_animation(&"mixamo_com")
	var config := HumanoidRetargeter.build_bone_map_config(
			HumanoidRetargeter.prefix_role_map(src_skeleton, SOURCE_BONE_PREFIX),
			target_humanoid_map)
	var anim := HumanoidRetargeter.retarget_clip(
			src_skeleton, src_animation, target_skeleton, config, false)
	inst.queue_free()
	return anim


func _physics_process(delta: float) -> void:
	if health.is_dead():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if not npc_controller.is_hostile():
		_process_non_hostile(player, delta)
		return
	if not player:
		_process_patrol(delta)
		return
	_update_perception(player, delta)
	match npc_controller.behavior:
		NPCController.Behavior.IDLE:
			_stop_body(delta)
			_play(&"idle")
		NPCController.Behavior.PATROL:
			_process_patrol(delta)
		NPCController.Behavior.INVESTIGATE:
			_process_investigate(delta)
		NPCController.Behavior.CHASE:
			_process_chase(player, delta)
		NPCController.Behavior.ATTACK:
			_process_attack(player, delta)
		NPCController.Behavior.SEARCH:
			_process_search(delta)
		NPCController.Behavior.FLEE:
			_stop_body(delta)
			_play(&"idle")


func _process_non_hostile(player: Node3D, delta: float) -> void:
	if (npc_controller.disposition == NPCController.Disposition.SUSPICIOUS
			and player != null and (perception.can_see(player) or perception.can_hear(player))):
		_nav_target = player.global_position
		npc_controller.set_behavior(NPCController.Behavior.INVESTIGATE)
	if npc_controller.behavior == NPCController.Behavior.INVESTIGATE:
		_process_investigate(delta)
	elif npc_controller.behavior == NPCController.Behavior.IDLE:
		_stop_body(delta)
		_play(&"idle")
	else:
		if npc_controller.behavior != NPCController.Behavior.PATROL:
			npc_controller.set_behavior(NPCController.Behavior.PATROL)
		_process_patrol(delta)


func _update_perception(player: Node3D, delta: float) -> void:
	if perception.can_see(player):
		_time_since_seen = 0.0
		if (npc_controller.behavior == NPCController.Behavior.PATROL
				or npc_controller.behavior == NPCController.Behavior.INVESTIGATE
				or npc_controller.behavior == NPCController.Behavior.SEARCH):
			npc_controller.set_behavior(NPCController.Behavior.CHASE)
			return
	_time_since_seen += delta
	if (npc_controller.behavior == NPCController.Behavior.CHASE
			and _time_since_seen > lose_sight_time):
		npc_controller.set_behavior(NPCController.Behavior.SEARCH)
		_search_timer = 0.0
		_nav_target = player.global_position
	elif (npc_controller.behavior == NPCController.Behavior.PATROL
			and perception.can_hear(player)):
		npc_controller.set_behavior(NPCController.Behavior.INVESTIGATE)
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
		npc_controller.set_behavior(NPCController.Behavior.PATROL)
		_go_to_patrol_point()


func _process_chase(player: Node3D, delta: float) -> void:
	_play(&"running")
	_nav_target = player.global_position
	_move_toward_target(chase_speed, delta, player)
	if global_position.distance_to(player.global_position) <= attack_range:
		npc_controller.set_behavior(NPCController.Behavior.ATTACK)
		_attack_cooldown_left = 0.0


func _process_attack(player: Node3D, delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if _attack_animation_left > 0.0:
		_attack_animation_left = maxf(_attack_animation_left - delta, 0.0)
		if _attack_animation_left == 0.0:
			_finish_attack_animation()
	if not _attack_turn_locked:
		_face_point(player.global_position, delta)
		_play(&"idle")
	var distance := global_position.distance_to(player.global_position)
	if distance > attack_range * 1.5 and not _attack_turn_locked:
		npc_controller.set_behavior(NPCController.Behavior.CHASE)
		return
	_attack_cooldown_left -= delta
	if _attack_turn_locked:
		_try_attack_contact(player, distance)
		return
	if (_attack_cooldown_left <= 0.0
			and _is_facing_point(player.global_position, attack_facing_angle_deg)):
		if _begin_attack_animation():
			_attack_cooldown_left = attack_cooldown


func _try_attack_contact(player: Node3D, distance: float) -> void:
	if _attack_contact_emitted or boss_ap.current_animation != &"pack/attack":
		return
	var attack_animation := boss_ap.get_animation(&"pack/attack")
	var contact_time := attack_animation.length * attack_contact_ratio
	if boss_ap.current_animation_position < contact_time:
		return
	_attack_contact_emitted = true
	if distance <= attack_range * 1.3:
		_deal_attack_damage(player)


func _deal_attack_damage(player: Node3D) -> void:
	var target_health := player.get_node_or_null(^"Health") as Health
	if target_health:
		target_health.apply_damage(attack_damage)


func _begin_attack_animation() -> bool:
	if not boss_ap.has_animation(&"pack/attack"):
		return false
	_attack_turn_locked = true
	_attack_contact_emitted = false
	_current_anim = &"attack"
	boss_ap.play(&"pack/attack", 0.1, attack_animation_speed)
	var attack_animation := boss_ap.get_animation(&"pack/attack")
	_attack_animation_left = attack_animation.length / attack_animation_speed
	return true


func _finish_attack_animation() -> void:
	_attack_turn_locked = false
	_current_anim = &""


func _cancel_attack_animation() -> void:
	_attack_animation_left = 0.0
	_attack_contact_emitted = true
	_attack_turn_locked = false
	_current_anim = &""


func _process_search(delta: float) -> void:
	_play(&"walking")
	_move_toward_target(walk_speed, delta)
	if nav_agent.is_navigation_finished():
		_search_timer += delta
		if _search_timer > search_time:
			npc_controller.set_behavior(NPCController.Behavior.PATROL)
			_go_to_patrol_point()


func _stop_body(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()


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
	_cancel_attack_animation()
	_current_anim = &"death"
	boss_ap.play("pack/death", 0.15)


func _on_damaged(_amount: float) -> void:
	if health.is_dead():
		return
	npc_controller.become_hostile()
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player:
		npc_controller.set_behavior(NPCController.Behavior.CHASE)
		_time_since_seen = 0.0
		_nav_target = player.global_position


func _on_disposition_changed(_previous: int, current: int) -> void:
	if current == NPCController.Disposition.HOSTILE:
		return
	_cancel_attack_animation()
	_attack_cooldown_left = 0.0
	if (npc_controller.behavior == NPCController.Behavior.CHASE
			or npc_controller.behavior == NPCController.Behavior.ATTACK
			or npc_controller.behavior == NPCController.Behavior.SEARCH):
		npc_controller.set_behavior(NPCController.Behavior.PATROL)
		_go_to_patrol_point()
