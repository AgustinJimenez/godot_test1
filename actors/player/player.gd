class_name Player
extends CharacterBody3D
## First-person controller: mouse look, walk/sprint/crouch, stamina,
## jump, flashlight toggle and interaction ray.

const STAND_CAPSULE_HEIGHT := 1.8
const CROUCH_CAPSULE_HEIGHT := 1.2
const STAIR_CONTROLLER := preload("res://actors/player/player_stair_controller.gd")
## How far out to draw the FOV wireframe in the debug view - purely visual,
## does not affect the camera's actual near/far planes.
const FOV_GIZMO_DISTANCE := 2.5
## Minimum distance the eye must keep from each torso/arm bone, so the
## camera's own near-clip volume never ends up inside the hood/collar/
## shoulder/arm mesh - the neck-bend angle clamp alone isn't enough for
## that. Per-bone, not one shared radius: the shoulder joints sit only
## ~6.5cm from the head bone's own rest position in this rig (anatomically
## close), so eye_offset (whose own magnitude is ~0.16m) can never clear a
## 0.25m radius there - the best case is offset pointing directly away,
## giving ~0.22m at most. The chest bone has more baseline room, so it
## keeps the larger radius. The arms are included because the idle pose
## holds them crossed low - looking down and to a side swings the eye
## toward the upper arm, which was the closest obstacle of all of them.
const TORSO_CLEARANCE: Dictionary = {
	&"Spine2": 0.3,
	&"LeftShoulder": 0.19,
	&"RightShoulder": 0.19,
	&"LeftArm": 0.17,
	&"RightArm": 0.17,
}
var eye_offset := Vector3(0, 0.07, -0.17)

func set_eye_offset(v: Vector3) -> void:
	eye_offset = v

@export_group("Look")
@export var mouse_sensitivity: float = 0.002
@export var pitch_limit_deg: float = 85.0
## How far the head can turn from the body before the body starts rotating
## to catch up - real necks don't swivel a full 180, so past this the torso
## has to turn instead.
@export var head_yaw_limit_deg: float = 60.0

@export_group("Movement")
@export var walk_speed: float = 3.2
@export var sprint_speed: float = 5.8
@export var crouch_speed: float = 1.7
@export var acceleration: float = 12.0
@export var jump_velocity: float = 5.0
@export var roll_speed: float = 7.0
@export var roll_duration: float = 0.75
@export var roll_cooldown: float = 0.4
## Clears the ~0.33m worst generated riser; taller walls still block.
@export var step_height: float = 0.4
## Spreads a step-up's rise over several frames in PlayerStairController.
@export_range(0.5, 3.0, 0.1) var step_rise_rate: float = 2.8
## Collision steps immediately; this eases only the camera presentation.
@export_range(1.0, 30.0, 0.5) var stair_hover_speed: float = 12.0
## Maximum presentation-only counter-motion applied to the upper body after
## foot IK. Hips, legs, collision, and contact timing remain authoritative.
@export_range(0.0, 0.05, 0.005) var stair_balance_limit: float = 0.03
@export_range(0.0, 0.75, 0.05) var stair_balance_strength: float = 0.75
## TEMP evaluation: synchronized physical/animation slowdown around a stair
## transition. Keep at 1.0 for normal gameplay; 0.5 is the requested visual trial.
@export_range(0.25, 1.0, 0.05) var stair_walk_speed_scale: float = 1.0
@export_range(0.0, 3.0, 0.05) var punch_delay_min: float = 0.25
@export_range(0.0, 3.0, 0.05) var punch_delay_max: float = 0.75

@export_group("Stamina")
@export var sprint_duration: float = 18.0
@export var stamina_refill_time: float = 9.0
## After draining fully, sprint stays locked until stamina recovers this fraction.
@export var sprint_recover_fraction: float = 0.3

## Third-person debug camera zoom range (SpringArm3D.spring_length), and how
## much each scroll-wheel tick moves it.
const THIRD_PERSON_ZOOM_MIN := 1.5
const THIRD_PERSON_ZOOM_MAX := 8.0
const THIRD_PERSON_ZOOM_STEP := 0.4

var stamina: float
var _sprint_locked := false
var _crouched := false
var _dead := false
var _debug_cam_active := false
var _roll_time_left := 0.0
var _roll_cooldown_left := 0.0
## See the report_on_floor comment in _physics_process(). Covers stepping up
## (is_on_floor() can flicker false around the step-up snap) and stepping
## down (each tread edge is a real few-cm drop before the next tread catches).
const AIRBORNE_ANIMATION_GRACE := 0.15
## A deliberate jump's velocity.y (jump_velocity, see @export above) is well
## past this - used to tell "just jumped, animate instantly" apart from
## "briefly airborne between stair treads, don't pop the fall pose yet".
const JUMP_VELOCITY_THRESHOLD := 0.5
var _airborne_time := 0.0
var _roll_direction := Vector3.ZERO
var _next_punch_is_jab := true
var _punch_cooldown_left := 0.0
var _action_rng := RandomNumberGenerator.new()
var _pending_melee_animation := &""
var _pending_melee_damage := 0.0
var _pending_melee_range := 0.0
## Debug menu toggle: the FOV gizmo already only shows up while the third-
## person view is active (no point drawing the first-person camera's FOV
## from inside its own view) - this is a second, manual gate on top of
## that, for when it's just cluttering the third-person view too.
var show_fov_gizmo := false

func toggle_fov_gizmo() -> void:
	show_fov_gizmo = not show_fov_gizmo

## Debug menu toggle: fly freely with no gravity and no collision, for
## inspecting generated layouts (e.g. procedural rooms) from outside/above
## without needing a valid walkable path. _physics_process() branches to
## _process_free_mode() entirely instead of the normal grounded-movement
## code while this is on; collision is zeroed rather than just skipping
## move_and_slide() so the player also can't be hit/detected by other
## collision-based systems (AI perception, hitscans) while noclipping.
@export var free_mode_speed: float = 8.0
@export var free_mode_sprint_multiplier: float = 3.0
var free_mode_enabled := false
var _free_mode_default_collision_layer := 0
var _free_mode_default_collision_mask := 0
var movement_input_override: Variant = null
var debug_movement_input := Vector2.ZERO
var _smoothed_input_dir := Vector2.ZERO
var gameplay_action_input_enabled := true
var _stair_controller := STAIR_CONTROLLER.new()
var _stair_hover_offset_y: float:
	get:
		return _stair_controller.hover_offset_y
	set(value):
		_stair_controller.hover_offset_y = value
var _body_rest_y: float:
	get:
		return _stair_controller.get_body_rest_y()

func set_free_mode(enabled: bool) -> void:
	if free_mode_enabled == enabled:
		return
	free_mode_enabled = enabled
	if enabled:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = _free_mode_default_collision_layer
		collision_mask = _free_mode_default_collision_mask
	velocity = Vector3.ZERO
	_reset_stair_hover()

## Debug menu toggle: a fully independent spectator camera with its own
## yaw/pitch, unlike free_mode (which flies the player's own body/first-
## person camera) or debug_camera (third-person, but still orbits using the
## same look input the body's own head-then-body yaw catch-up reads) -
## looking around here never touches the character's actual rotation, for
## inspecting things (e.g. foot IK) where the body's own pose/facing has to
## stay exactly what gameplay/animation put it at while the view moves
## independently around it. Gravity/animation on the body continue normally
## while this is active, but move_* input is deliberately ignored by the
## body's own _physics_process() while it's on (see the input_dir override
## there) - otherwise WASD, read independently by both this camera's own
## _process() and the body's normal movement code, would walk the character
## at the same time as flying the camera, which defeats the point of a
## "detached" view for inspecting a character that should hold still.
@export var detached_cam_speed: float = 6.0
@export var detached_cam_sprint_multiplier: float = 3.0
@export var detached_cam_sensitivity: float = 0.0015
var detached_cam_active := false
var _detached_yaw := 0.0
var _detached_pitch := 0.0

func set_detached_camera_active(enabled: bool) -> void:
	if detached_cam_active == enabled:
		return
	detached_cam_active = enabled
	if enabled:
		var source_cam := debug_cam if _debug_cam_active else camera
		detached_cam.global_transform = source_cam.global_transform
		_detached_yaw = detached_cam.rotation.y
		_detached_pitch = detached_cam.rotation.x
		detached_cam.make_current()
		hud.set_center_dot_visible(false)
	else:
		(debug_cam if _debug_cam_active else camera).make_current()
		hud.set_center_dot_visible(not _debug_cam_active)

func _process(delta: float) -> void:
	if not detached_cam_active:
		return
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_direction := detached_cam.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if Input.is_action_pressed(&"jump"):
		move_direction.y += 1.0
	if Input.is_action_pressed(&"crouch"):
		move_direction.y -= 1.0
	if move_direction.is_zero_approx():
		return
	var speed := detached_cam_speed
	if Input.is_action_pressed(&"sprint"):
		speed *= detached_cam_sprint_multiplier
	detached_cam.global_position += move_direction.normalized() * speed * delta

var _head_bone_idx := -1
var _torso_bone_indices: PackedInt32Array = []
var _torso_bone_clearances: PackedFloat32Array = []
var _crouch_offset := 0.0
var _eye_marker: MeshInstance3D
var _fov_gizmo: MeshInstance3D
var _fov_mesh := ImmediateMesh.new()
## Pitch and head-yaw, owned here as plain floats and only ever written into
## head.rotation - never read back out of it. Godot's Euler decomposition of
## a Basis is ambiguous/unstable near the pitch extremes (gimbal lock), so
## accumulating "next value = head.rotation.x + delta" round-trips through
## that instability every event; sustained diagonal mouse movement pushed it
## into visible spin. Plain float addition has no such ambiguity.
var _look_pitch := 0.0
var _look_yaw := 0.0
var equipped_item: Item

@onready var head: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var flashlight: SpotLight3D = $HeadPivot/Camera3D/Flashlight
@onready var interact_ray: RayCast3D = $HeadPivot/Camera3D/InteractRay
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var capsule: CapsuleShape3D = collision.shape
@onready var uncrouch_check: ShapeCast3D = $UncrouchCheck
@onready var hud: CanvasLayer = $HUD
@onready var inventory: Inventory = $Inventory
@onready var melee_weapon: MeleeWeapon = $MeleeWeapon
@onready var health: Health = $Health
@onready var weapon: PistolWeapon = $HeadPivot/Camera3D/WeaponRig
@onready var body: PlayerBody = $Body
# Not a fixed $Body/Skeleton3D path anymore - Body's own _setup_character_scene()
# instantiates its skin as a child and finds Skeleton3D dynamically underneath
# that, not as Body's own direct child, so this has to go through body's
# already-resolved reference instead (Body's _ready() runs before Player's own,
# same as every other child-before-parent case, so body.skeleton is valid here).
@onready var skeleton: Skeleton3D = body.skeleton
@onready var third_person_arm: SpringArm3D = $ThirdPersonArm
@onready var debug_cam: Camera3D = $ThirdPersonArm/DebugCam
@onready var detached_cam: Camera3D = $DetachedCam

func _ready() -> void:
	add_to_group(&"player")
	_resolve_body_bone_indices()
	_spawn_eye_marker()
	_spawn_fov_gizmo()
	stamina = sprint_duration
	hud.bind_inventory(inventory)
	hud.bind_health(health)
	weapon.setup(inventory)
	hud.bind_weapon(weapon)
	inventory.changed.connect(_update_weapon_equip)
	weapon.fired.connect(_on_weapon_fired)
	body.action_finished.connect(_on_body_action_finished)
	body.action_contact.connect(_on_body_action_contact)
	body.character_changed.connect(_resolve_body_bone_indices)
	health.died.connect(_on_died)
	_action_rng.randomize()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_free_mode_default_collision_layer = collision_layer
	_free_mode_default_collision_mask = collision_mask
	_stair_controller.setup(self, body, third_person_arm)
	# Must reach at least as far as step_height, or apply_floor_snap() in
	# The stair controller can fail to find the tread it just lifted onto (the
	# gap between the lift and the actual step surface varies with each
	# step's real riser height, up to step_height) - a snap that occasionally
	# comes up short reads as is_on_floor() flicking false for a frame, which
	# is exactly what was triggering the falling animation on every step.
	floor_snap_length = step_height

## TORSO_CLEARANCE's keys (and "Head") are canonical role names, not
## necessarily this skeleton's own real bone names - resolve each through
## body.resolve_bone_name() before find_bone() so this still works after
## body.swap_character() puts on a differently-prefixed skin (e.g.
## "Head" -> "mixamorig_Head" for x_bot/y_bot). Re-run via
## body.character_changed whenever that happens - skeleton itself is
## reassigned here too, since body.swap_character() replaces body.skeleton
## with a brand new Skeleton3D instance, not the one this was last resolved
## against.
func _resolve_body_bone_indices() -> void:
	skeleton = body.skeleton
	_head_bone_idx = skeleton.find_bone(body.resolve_bone_name(&"Head"))
	_torso_bone_indices.clear()
	_torso_bone_clearances.clear()
	for bone_name: StringName in TORSO_CLEARANCE:
		var idx := skeleton.find_bone(body.resolve_bone_name(bone_name))
		if idx >= 0:
			_torso_bone_indices.append(idx)
			_torso_bone_clearances.append(TORSO_CLEARANCE[bone_name])

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if detached_cam_active and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Deliberately bypasses _apply_yaw()/head.rotation entirely - this
		# camera's yaw/pitch are its own state, never the body's, which is
		# the whole point of "detached".
		var detached_motion := event as InputEventMouseMotion
		_detached_yaw -= detached_motion.relative.x * detached_cam_sensitivity
		_detached_pitch = clampf(_detached_pitch - detached_motion.relative.y * detached_cam_sensitivity,
				-1.5, 1.5)
		detached_cam.rotation = Vector3(_detached_pitch, _detached_yaw, 0.0)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_apply_yaw(-motion.relative.x * mouse_sensitivity)
		_look_pitch = clampf(_look_pitch - motion.relative.y * mouse_sensitivity,
				-deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))
		if _debug_cam_active:
			# Third person: pitch orbits the camera itself (SpringArm3D's
			# own rotation) using the raw, uncapped pitch - the head still
			# follows it too, but only up to a natural limit (see
			# _physics_process, where body.head_pitch is fed the clamped
			# version), so the camera can keep tilting past where the neck
			# would stop.
			third_person_arm.rotation.x = _look_pitch
		else:
			head.rotation.x = _look_pitch
	elif event.is_action_pressed(&"flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed(&"crouch") and not detached_cam_active:
		# "crouch" also drives the detached camera's own descend - see
		# _process() - without this guard it toggled the body's crouch
		# state too every time you flew the camera downward.
		if _crouched and uncrouch_check.is_colliding():
			pass  # no headroom to stand up
		else:
			_crouched = not _crouched
	elif event.is_action_pressed(&"interact"):
		var target := _current_interactable()
		if target:
			if target.animation_name != &"":
				body.play_action_animation(target.animation_name, 1.35)
			target.interact(self)
	elif event.is_action_pressed(&"debug_camera"):
		# Third-person dev view: ThirdPersonArm is a plain child of the
		# player (see player.tscn), tracking body yaw through normal node
		# parenting plus _look_yaw directly (see _apply_yaw) - the same
		# head-leads-then-body-catches-up system first person uses, just
		# with the camera also picking up the head's yaw offset instead of
		# only riding on HeadPivot. No reset needed on switch: both modes
		# share the same _look_yaw/_look_pitch state continuously.
		if debug_cam.current:
			camera.make_current()
			_debug_cam_active = false
			hud.set_center_dot_visible(true)
		else:
			debug_cam.make_current()
			_debug_cam_active = true
			hud.set_center_dot_visible(false)
			# Pitch still gets a level start - the camera's orbit pitch has
			# no equivalent "catch up" partner to stay consistent with like
			# yaw does, so carrying over a steep first-person pitch would
			# just be a jarring snap.
			_look_pitch = 0.0
			head.rotation.x = 0.0
			third_person_arm.rotation.x = 0.0
	elif _debug_cam_active and event.is_action_pressed(&"zoom_in"):
		_set_third_person_zoom(third_person_arm.spring_length - THIRD_PERSON_ZOOM_STEP)
	elif _debug_cam_active and event.is_action_pressed(&"zoom_out"):
		_set_third_person_zoom(third_person_arm.spring_length + THIRD_PERSON_ZOOM_STEP)
	elif event.is_action_pressed(&"inventory"):
		hud.toggle_inventory()
	# "pause" (Esc) is handled entirely by hud.gd's own _unhandled_input,
	# not here - it needs to check which overlay (if any) is already open
	# to decide whether to close that or open the debug/pause menu, and
	# handling it in both places would double-toggle on a single press.

## SpringArm3D repositions its children itself every frame (to spring_length,
## pulled closer via its own collision raycast when something's in the way)
## - changing spring_length is the whole job, no manual position sync needed.
func _set_third_person_zoom(length: float) -> void:
	third_person_arm.spring_length = clampf(length, THIRD_PERSON_ZOOM_MIN, THIRD_PERSON_ZOOM_MAX)


## Head and body rotate about the same (world Y) axis, so their yaws are
## simply additive - turn the head first, and once it hits the limit, any
## further input carries over 1:1 into rotating the body instead. This way
## total camera yaw always tracks the mouse exactly, whether it comes from
## the head, the body, or a mix of both mid-turn.
func _apply_yaw(delta_yaw: float) -> void:
	var limit := deg_to_rad(head_yaw_limit_deg)
	var new_head_yaw := _look_yaw + delta_yaw
	_look_yaw = clampf(new_head_yaw, -limit, limit)
	head.rotation.y = _look_yaw
	# Third person has no HeadPivot in its parent chain (ThirdPersonArm
	# hangs off the player root, not the head), so it needs this offset
	# applied explicitly to see the same head-leads-then-body-catches-up
	# turn first person gets for free through node parenting.
	third_person_arm.rotation.y = _look_yaw
	var overflow := new_head_yaw - _look_yaw
	if overflow != 0.0:
		rotate_y(overflow)


## While actually walking, gradually turn the body to face wherever the head
## is looking - this transfers the offset from head to body (total yaw, and
## so the camera's actual look direction, is unchanged), it doesn't add to
## it. Otherwise walking toward a glanced-at direction would strafe there
## forever with the body never turning to face it.
const BODY_CATCHUP_DEG_PER_SEC := 220.0

func _catch_up_body_yaw(input_dir: Vector2, delta: float) -> void:
	if input_dir.length() < 0.1 or _look_yaw == 0.0:
		return
	var max_step := deg_to_rad(BODY_CATCHUP_DEG_PER_SEC) * delta
	var step := clampf(_look_yaw, -max_step, max_step)
	_look_yaw -= step
	head.rotation.y = _look_yaw
	third_person_arm.rotation.y = _look_yaw
	rotate_y(step)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if free_mode_enabled:
		_process_free_mode(delta)
		return
	# The detached spectator camera reads move_*/jump/crouch for its own
	# flight (see set_detached_camera_active()'s doc comment and this
	# script's own _process()) - without suppressing them here too, flying
	# the camera also walked/jumped/crouched the body underneath it. A full
	# early return was tried first and was worse: it also skipped gravity
	# and move_and_slide() every frame this is on, so the body never
	# settles onto the floor from spawn and just hovers at its spawn
	# height - gravity/floor snapping/animation all need to keep running,
	# only the *input-driven* reactions (movement, jump, crouch - crouch's
	# own toggle is guarded separately in _unhandled_input) get suppressed.
	var input_dir := Vector2.ZERO
	if movement_input_override is Vector2:
		input_dir = movement_input_override
		_smoothed_input_dir = input_dir
	elif not detached_cam_active:
		input_dir = Input.get_vector(
				&"move_left", &"move_right", &"move_forward", &"move_back")
		_smoothed_input_dir = _smoothed_input_dir.move_toward(input_dir, delta * 8.0)
	else:
		_smoothed_input_dir = Vector2.ZERO
	debug_movement_input = _smoothed_input_dir
	_catch_up_body_yaw(_smoothed_input_dir, delta)
	var sprinting := _update_stamina(delta, _smoothed_input_dir)
	_update_capsule(delta)
	_roll_cooldown_left = maxf(_roll_cooldown_left - delta, 0.0)
	_punch_cooldown_left = maxf(_punch_cooldown_left - delta, 0.0)
	var look_basis := Basis(Vector3.UP, rotation.y + _look_yaw)
	if (gameplay_action_input_enabled and Input.is_action_just_pressed(&"roll") and is_on_floor()
			and _roll_time_left <= 0.0 and _roll_cooldown_left <= 0.0
			and not body.is_action_active()):
		var roll_input := Vector3(input_dir.x, 0.0, input_dir.y)
		var requested_direction := (look_basis * (
				roll_input.normalized() if not roll_input.is_zero_approx() else Vector3.FORWARD)
				).normalized()
		if body.play_action_animation(&"unarmed_roll", 1.8, 0.08):
			_crouched = false
			_roll_direction = requested_direction
			_roll_time_left = roll_duration
			_roll_cooldown_left = roll_duration + roll_cooldown
	elif (gameplay_action_input_enabled and Input.is_action_just_pressed(&"melee") and is_on_floor()
			and _roll_time_left <= 0.0 and _punch_cooldown_left <= 0.0
			and not body.is_action_active()):
		var held_melee := (equipped_item != null
				and equipped_item != weapon.weapon_item
				and equipped_item.melee_damage > 0.0)
		var attack_animation := &"weapon_sword_attack" if held_melee else (
				&"unarmed_punch_jab" if _next_punch_is_jab else &"unarmed_punch_cross")
		var contact_ratio := 0.48 if held_melee else 0.42
		if body.play_action_animation(attack_animation, 1.3, 0.08, contact_ratio):
			_pending_melee_animation = StringName("moves/" + String(attack_animation))
			_pending_melee_damage = equipped_item.melee_damage if held_melee else 8.0
			_pending_melee_range = equipped_item.melee_range if held_melee else 1.15
			if not held_melee:
				_next_punch_is_jab = not _next_punch_is_jab
	if (gameplay_action_input_enabled and Input.is_action_just_pressed(&"jump") and is_on_floor()
			and _roll_time_left <= 0.0 and not detached_cam_active):
		_crouched = false
		velocity.y = jump_velocity

	var speed := crouch_speed if _crouched else (sprint_speed if sprinting else walk_speed)
	var stair_walk_slowed := (not _crouched and not sprinting
			and _stair_controller.has_recent_transition())
	if stair_walk_slowed:
		speed *= stair_walk_speed_scale
	body.locomotion_playback_scale = stair_walk_speed_scale if stair_walk_slowed else 1.0
	# Movement follows where you're actually looking (body yaw + the head's
	# offset from it), not just the body's facing - otherwise glancing to the
	# side while walking forward would strafe instead of walking that way.
	var direction := (look_basis * Vector3(
			_smoothed_input_dir.x, 0.0, _smoothed_input_dir.y)).normalized()
	if _roll_time_left > 0.0:
		_roll_time_left = maxf(_roll_time_left - delta, 0.0)
		if _roll_time_left > 0.0:
			velocity.x = _roll_direction.x * roll_speed
			velocity.z = _roll_direction.z * roll_speed
		else:
			# The roll owns horizontal velocity, so it must also release it.
			# Leaving the final roll velocity for normal acceleration to decay
			# makes the idle pose visibly slide for another half-second.
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	var frame_start_y := global_position.y
	var preserved_horizontal_velocity := Vector2(velocity.x, velocity.z)
	_stair_controller.begin_frame()
	var stepped_up := _stair_controller.apply_step_up(
			horizontal_motion, delta, step_height, step_rise_rate)
	var stepped_down := _stair_controller.apply_step_down(
			horizontal_motion, delta, step_height, step_rise_rate,
			JUMP_VELOCITY_THRESHOLD) if stepped_up <= 0.0 else 0.0
	if _stair_controller.consumed_horizontal_motion:
		velocity.x = 0.0
		velocity.z = 0.0
	# Skip mid-climb: the stair controller already validated/applied its
	# own motion this frame; depenetration here would add an extra push.
	if not _stair_controller.is_climbing():
		move_and_slide()
	if _stair_controller.consumed_horizontal_motion:
		velocity.x = preserved_horizontal_velocity.x
		velocity.z = preserved_horizontal_velocity.y
	if stepped_up > 0.0:
		_stair_controller.record_presentation_delta(
				-stepped_up, step_height, stair_balance_strength, stair_balance_limit)
	elif stepped_down > 0.0:
		_stair_controller.record_presentation_delta(
				stepped_down, step_height, stair_balance_strength, stair_balance_limit)
	elif _stair_controller.is_short_step_down(
			frame_start_y, horizontal_motion, step_height, JUMP_VELOCITY_THRESHOLD):
		_stair_controller.record_presentation_delta(
				frame_start_y - global_position.y, step_height,
				stair_balance_strength, stair_balance_limit)
	_update_stair_hover(delta)

	# update_motion() treats any not-on-floor frame as a launch into the
	# jump/fall pose, but stairs make brief, real losses of floor contact in
	# both directions: stepping up can leave is_on_floor() flickering false
	# for a frame around the step-up snap, and stepping down means an actual
	# few-cm gap to the next tread every time. Debounce it - a jump still
	# reports instantly (clear upward velocity.y), but anything else has to
	# stay airborne past the grace window before the fall pose kicks in, so
	# neither direction pops it on every step.
	if is_on_floor():
		_airborne_time = 0.0
	else:
		_airborne_time += delta
	var jumped := velocity.y > JUMP_VELOCITY_THRESHOLD
	var report_on_floor := (
			is_on_floor() or (not jumped and _airborne_time < AIRBORNE_ANIMATION_GRACE))
	body.update_motion(_crouched, weapon.equipped,
			Vector2(velocity.x, velocity.z).length(), sprinting,
			report_on_floor, velocity.y, delta, flashlight.visible, _smoothed_input_dir)
	# Yaw: _look_yaw is already clamped to head_yaw_limit_deg in _apply_yaw
	# (same head-leads-then-body-catches-up system in both modes now), so
	# feeding it straight through is safe in third person too.
	# Pitch: unlike yaw, the camera keeps orbiting past the neck's natural
	# range (third_person_arm.rotation.x uses the raw, uncapped
	# _look_pitch), but the head still visibly follows it up to the same
	# anatomical limit first person uses, instead of staying rigidly level -
	# it just stops following once the camera pitches further than a real
	# neck could.
	body.head_pitch = body.clamp_head_pitch(_look_pitch) if _debug_cam_active else _look_pitch
	body.head_yaw = _look_yaw

	if _head_bone_idx >= 0:
		var head_pose := body.get_visual_bone_global_pose(_head_bone_idx)
		var head_pos := body.transform * head_pose.origin
		var safe_look := _solve_safe_look(_look_pitch, _look_yaw, head_pos)
		var pitch_rot := Basis(Vector3.UP, safe_look.y) * Basis(Vector3.RIGHT, safe_look.x)
		# The stair controller already spreads the root's rise across several
		# frames (step_rise_rate), so head_pos is already smooth here. An
		# older per-camera compensation used to pull this down further during
		# a climb, to mask what WAS an instant one-frame teleport - now that
		# the root itself never teleports, that extra pull only fought the
		# already-smooth motion (confirmed live: reported shake on stairs).
		head.position = head_pos + pitch_rot * eye_offset


func _update_stair_hover(delta: float) -> void:
	_stair_controller.update_presentation(delta, stair_hover_speed)
	body.stair_balance_offset = _stair_controller.balance_offset_y
func _reset_stair_hover() -> void:
	_stair_controller.reset()
	if is_instance_valid(body):
		body.stair_balance_offset = 0.0


func get_stair_debug_state() -> Dictionary:
	return _stair_controller.get_debug_state()


## Movement follows the camera's exact look direction (forward/back tilt up
## and down with pitch, unlike normal grounded movement which stays flat) -
## jump/crouch add pure world-space up/down independent of where the camera
## is looking. Moves via direct position change, not move_and_slide(), so it
## passes through every mesh regardless of collision_layer/mask.
func _process_free_mode(delta: float) -> void:
	var input_dir := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_direction := camera.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if Input.is_action_pressed(&"jump"):
		move_direction.y += 1.0
	if Input.is_action_pressed(&"crouch"):
		move_direction.y -= 1.0
	if not move_direction.is_zero_approx():
		move_direction = move_direction.normalized()
	var current_speed := free_mode_speed
	if Input.is_action_pressed(&"sprint"):
		current_speed *= free_mode_sprint_multiplier
	velocity = move_direction * current_speed
	global_position += velocity * delta

	var target_crouch := -0.58 if _crouched else 0.0
	_crouch_offset = lerpf(_crouch_offset, target_crouch, 10.0 * delta)
	head.position.y += _crouch_offset
	_eye_marker.position = head.position
	_update_fov_gizmo()

	var target := _current_interactable()
	hud.set_prompt("[E] " + target.prompt if target else "")



## Keeps the eye clear of each torso bone's own TORSO_CLEARANCE radius. Only
## affects this small position nudge, not the camera's actual look direction
## (_look_pitch/_look_yaw, set directly from mouse input) - so you can still
## look anywhere, this just stops the near clip from riding inside your own
## mesh while doing it.
##
## Yaw is solved first, checked at level pitch (0): that's the least
## constrained case for a given yaw, so if it's already unsafe there, no
## amount of pitch clamping would help either (this is what plain pitch-only
## clamping missed - turning far enough to the side puts the shoulder in the
## way even before you look down at all). Pitch is then solved at whatever
## yaw came out of that first step.
func _solve_safe_look(raw_pitch: float, raw_yaw: float, head_pos: Vector3) -> Vector2:
	var pitch_candidate := body.clamp_head_pitch(raw_pitch)
	if _torso_bone_indices.is_empty():
		return Vector2(pitch_candidate, raw_yaw)
	var torso_points := _torso_points()
	var safe_yaw := raw_yaw
	if not _look_is_safe(head_pos, torso_points, 0.0, raw_yaw):
		safe_yaw = _bisect_toward_safe(0.0, raw_yaw,
				func(y): return _look_is_safe(head_pos, torso_points, 0.0, y))
	var safe_pitch := pitch_candidate
	if pitch_candidate < 0.0 and not _look_is_safe(head_pos, torso_points, pitch_candidate, safe_yaw):
		safe_pitch = _bisect_toward_safe(0.0, pitch_candidate,
				func(p): return _look_is_safe(head_pos, torso_points, p, safe_yaw))
	return Vector2(safe_pitch, safe_yaw)


## Binary search between a known-safe value and a candidate that failed
## clearance, for the value closest to the candidate that's still safe.
func _bisect_toward_safe(safe: float, candidate: float, is_safe_at: Callable) -> float:
	var lo := safe
	var hi := candidate
	for i in 8:
		var mid := (lo + hi) * 0.5
		if is_safe_at.call(mid):
			lo = mid
		else:
			hi = mid
	return lo


func _torso_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for idx in _torso_bone_indices:
		pts.append(body.transform * body.get_visual_bone_global_pose(idx).origin)
	return pts


## Matches the real eye-position formula (head_pos + yaw-then-pitch rotated
## eye_offset) exactly - a clearance check built from a different formula
## than the one actually used to place the camera checks the wrong point.
func _look_is_safe(
		head_pos: Vector3, torso_points: Array[Vector3], pitch: float, yaw: float) -> bool:
	var eye := head_pos + Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * eye_offset
	for i in torso_points.size():
		if eye.distance_to(torso_points[i]) < _torso_bone_clearances[i]:
			return false
	return true


func _spawn_eye_marker() -> void:
	_eye_marker = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	_eye_marker.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0, 0)
	_eye_marker.material_override = mat
	# It's invisible from the FP camera itself (smaller than the near clip
	# distance), but shadow casting ignores camera visibility entirely - left
	# on, this shows up as a sphere-shaped blob in the player's own shadow
	# instead of a head shape, since the actual (collapsed) head casts next
	# to nothing by comparison.
	_eye_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_eye_marker)


func _spawn_fov_gizmo() -> void:
	_fov_gizmo = MeshInstance3D.new()
	_fov_gizmo.mesh = _fov_mesh
	# The mesh's vertices are written in world space each frame (see
	# _update_fov_gizmo), so this node must ignore the Player's own
	# transform rather than compose with it.
	_fov_gizmo.top_level = true
	_fov_gizmo.visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.25, 0.25)
	_fov_gizmo.material_override = mat
	add_child(_fov_gizmo)


## Wireframe pyramid from the camera's actual global transform/fov, out to
## FOV_GIZMO_DISTANCE - lets you see the camera's viewing cone from outside
## (debug camera) instead of just where it sits.
func _update_fov_gizmo() -> void:
	_fov_gizmo.visible = _debug_cam_active and show_fov_gizmo
	if not _fov_gizmo.visible:
		return
	var cam_t := camera.global_transform
	var half_h := tan(deg_to_rad(camera.fov * 0.5)) * FOV_GIZMO_DISTANCE
	var half_w := half_h * get_viewport().get_visible_rect().size.aspect()
	var corners: Array[Vector3] = [
		cam_t * Vector3(-half_w, half_h, -FOV_GIZMO_DISTANCE),
		cam_t * Vector3(half_w, half_h, -FOV_GIZMO_DISTANCE),
		cam_t * Vector3(half_w, -half_h, -FOV_GIZMO_DISTANCE),
		cam_t * Vector3(-half_w, -half_h, -FOV_GIZMO_DISTANCE),
	]
	_fov_mesh.clear_surfaces()
	_fov_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for corner in corners:
		_fov_mesh.surface_add_vertex(cam_t.origin)
		_fov_mesh.surface_add_vertex(corner)
	for i in corners.size():
		_fov_mesh.surface_add_vertex(corners[i])
		_fov_mesh.surface_add_vertex(corners[(i + 1) % corners.size()])
	_fov_mesh.surface_end()

func _update_stamina(delta: float, input_dir: Vector2) -> bool:
	# Sprint only counts while actually moving forward, standing up.
	var wants_sprint: bool = (gameplay_action_input_enabled and Input.is_action_pressed(&"sprint")
			and not _crouched and input_dir.y < -0.1)
	var sprinting := wants_sprint and not _sprint_locked and stamina > 0.0
	if sprinting:
		stamina = maxf(stamina - delta, 0.0)
		if stamina == 0.0:
			_sprint_locked = true
	else:
		stamina = minf(stamina + delta * sprint_duration / stamina_refill_time,
				sprint_duration)
		if _sprint_locked and stamina >= sprint_duration * sprint_recover_fraction:
			_sprint_locked = false
	hud.set_stamina(stamina, sprint_duration)
	return sprinting


func _update_capsule(delta: float) -> void:
	var target_height := CROUCH_CAPSULE_HEIGHT if _crouched else STAND_CAPSULE_HEIGHT
	capsule.height = lerpf(capsule.height, target_height, 8.0 * delta)
	collision.position.y = capsule.height * 0.5


func _update_weapon_equip() -> void:
	if equipped_item != null and inventory.count_of(equipped_item) == 0:
		equipped_item = null
	if equipped_item == null and inventory.count_of(weapon.weapon_item) > 0:
		equipped_item = weapon.weapon_item
	_apply_equipped_item()


func toggle_equip_item(item: Item) -> bool:
	if item == null or item.kind != Item.Kind.WEAPON or inventory.count_of(item) == 0:
		return false
	equipped_item = null if equipped_item == item else item
	_apply_equipped_item()
	return equipped_item == item


func is_item_equipped(item: Item) -> bool:
	return equipped_item == item


func _apply_equipped_item() -> void:
	var pistol_selected := equipped_item == weapon.weapon_item
	weapon.equipped = pistol_selected
	body.set_equipped_item(null if pistol_selected else equipped_item)
	if equipped_item != null and not pistol_selected:
		flashlight.visible = false


func _on_weapon_fired() -> void:
	# Recoil stays player-side: the weapon signals up, the player owns the head.
	_look_pitch = minf(_look_pitch + 0.014, deg_to_rad(pitch_limit_deg))
	head.rotation.x = _look_pitch


func _on_body_action_finished(animation_name: StringName) -> void:
	if animation_name == _pending_melee_animation:
		_clear_pending_melee()
	if animation_name not in [
			&"moves/unarmed_punch_jab",
			&"moves/unarmed_punch_cross",
			&"moves/weapon_sword_attack",
	]:
		return
	var low := minf(punch_delay_min, punch_delay_max)
	var high := maxf(punch_delay_min, punch_delay_max)
	_punch_cooldown_left = _action_rng.randf_range(low, high)


func _on_body_action_contact(animation_name: StringName) -> void:
	if animation_name != _pending_melee_animation:
		return
	melee_weapon.attack(camera, _pending_melee_damage, _pending_melee_range)
	_clear_pending_melee()


func _clear_pending_melee() -> void:
	_pending_melee_animation = &""
	_pending_melee_damage = 0.0
	_pending_melee_range = 0.0


## Radius (meters) at which the player's current movement noise can be
## heard by AI - crouching stays quiet, sprinting carries the farthest.
func noise_radius() -> float:
	if _crouched:
		return 2.5
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.1:
		return 0.0
	return lerp(4.0, 9.0, clamp(speed / sprint_speed, 0.0, 1.0))


func _on_died() -> void:
	_dead = true
	weapon.equipped = false
	hud.set_prompt("")
	hud.show_death()


func _current_interactable() -> Interactable:
	var collider: Object = interact_ray.get_collider()
	if collider is Node:
		var found := (collider as Node).get_node_or_null(^"Interactable") as Interactable
		if found and found.enabled:
			return found
	return null
