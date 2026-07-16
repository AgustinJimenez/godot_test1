class_name Player
extends CharacterBody3D
## First-person controller: mouse look, walk/sprint/crouch, stamina,
## flashlight toggle and interaction ray. No jump — classic survival horror.

const STAND_CAPSULE_HEIGHT := 1.8
const CROUCH_CAPSULE_HEIGHT := 1.2
## How far out to draw the FOV wireframe in the debug view - purely visual,
## does not affect the camera's actual near/far planes.
const FOV_GIZMO_DISTANCE := 2.5
## Minimum distance the eye must keep from the chest bone while looking down,
## so the camera's own near-clip volume never ends up inside the hood/collar
## mesh - the neck-bend angle clamp alone isn't enough for that.
const EYE_CHEST_CLEARANCE := 0.25
var eye_offset := Vector3(0, 0.05, -0.15)

func set_eye_offset(v: Vector3) -> void:
	eye_offset = v

@export_group("Look")
@export var mouse_sensitivity: float = 0.002
@export var pitch_limit_deg: float = 85.0

@export_group("Movement")
@export var walk_speed: float = 3.2
@export var sprint_speed: float = 5.8
@export var crouch_speed: float = 1.7
@export var acceleration: float = 12.0

@export_group("Stamina")
@export var sprint_duration: float = 6.0
@export var stamina_refill_time: float = 9.0
## After draining fully, sprint stays locked until stamina recovers this fraction.
@export var sprint_recover_fraction: float = 0.3

var stamina: float
var _sprint_locked := false
var _crouched := false
var _dead := false
var _debug_cam_active := false
var _debug_cam_offset := Vector3.ZERO
var _head_bone_idx := -1
var _chest_bone_idx := -1
var _crouch_offset := 0.0
var _eye_marker: MeshInstance3D
var _fov_gizmo: MeshInstance3D
var _fov_mesh := ImmediateMesh.new()

@onready var head: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var flashlight: SpotLight3D = $HeadPivot/Camera3D/Flashlight
@onready var interact_ray: RayCast3D = $HeadPivot/Camera3D/InteractRay
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var capsule: CapsuleShape3D = collision.shape
@onready var uncrouch_check: ShapeCast3D = $UncrouchCheck
@onready var hud: CanvasLayer = $HUD
@onready var inventory: Inventory = $Inventory
@onready var health: Health = $Health
@onready var weapon: PistolWeapon = $HeadPivot/Camera3D/WeaponRig
@onready var body: PlayerBody = $Body
@onready var skeleton: Skeleton3D = $Body/Skeleton3D
@onready var debug_cam: Camera3D = $DebugCam


func _ready() -> void:
	add_to_group(&"player")
	_head_bone_idx = skeleton.find_bone("Head")
	_chest_bone_idx = skeleton.find_bone("Spine2")
	_spawn_eye_marker()
	_spawn_fov_gizmo()
	stamina = sprint_duration
	hud.bind_inventory(inventory)
	hud.bind_health(health)
	weapon.setup(inventory)
	hud.bind_weapon(weapon)
	inventory.changed.connect(_update_weapon_equip)
	weapon.fired.connect(_on_weapon_fired)
	health.died.connect(_on_died)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotate_x(-motion.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x,
				-deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))
	elif event.is_action_pressed(&"flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed(&"crouch"):
		if _crouched and uncrouch_check.is_colliding():
			pass  # no headroom to stand up
		else:
			_crouched = not _crouched
	elif event.is_action_pressed(&"interact"):
		var target := _current_interactable()
		if target:
			target.interact(self)
	elif event.is_action_pressed(&"debug_camera"):
		# Dev view: follow camera trails the player in world space, saving
		# the offset direction at activation so it does not yaw with the
		# player — rotating the character lets you see them from any angle.
		if debug_cam.current:
			camera.make_current()
			body.hide_head = true
			_debug_cam_active = false
		else:
			debug_cam.top_level = true
			_debug_cam_offset = -global_transform.basis.z * 2.6 + Vector3(0, 1.75, 0)
			debug_cam.global_position = global_position + _debug_cam_offset
			debug_cam.look_at(global_position + Vector3(0, 1.25, 0))
			debug_cam.make_current()
			body.hide_head = false
			_debug_cam_active = true
	elif event.is_action_pressed(&"inventory"):
		hud.toggle_inventory()
	elif event.is_action_pressed(&"debug_menu"):
		hud.toggle_debug()
	elif event.is_action_pressed(&"pause"):
		# Until a pause menu exists, Esc just releases/captures the mouse.
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var input_dir := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var sprinting := _update_stamina(delta, input_dir)
	_update_capsule(delta)

	var speed := crouch_speed if _crouched else (sprint_speed if sprinting else walk_speed)
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	body.update_motion(_crouched, weapon.equipped,
			Vector2(velocity.x, velocity.z).length(), sprinting)
	body.head_pitch = head.rotation.x

	if _head_bone_idx >= 0:
		var head_pose := skeleton.get_bone_global_pose(_head_bone_idx)
		var head_pos := body.transform * head_pose.origin
		var safe_pitch := _solve_safe_pitch(head.rotation.x, head_pos)
		var pitch_rot := Basis(Vector3.RIGHT, safe_pitch)
		head.position = head_pos + pitch_rot * eye_offset

	var target_crouch := -0.58 if _crouched else 0.0
	_crouch_offset = lerpf(_crouch_offset, target_crouch, 10.0 * delta)
	head.position.y += _crouch_offset
	_eye_marker.position = head.position
	_update_fov_gizmo()

	var target := _current_interactable()
	hud.set_prompt("[E] " + target.prompt if target else "")

	if _debug_cam_active:
		debug_cam.global_position = global_position + _debug_cam_offset
		debug_cam.look_at(global_position + Vector3(0, 1.25, 0))


 
## Starts from the neck-bend angle clamp (body.clamp_head_pitch), then binary
## searches back toward level (0) for the largest look-down angle that still
## keeps the eye at least EYE_CHEST_CLEARANCE from the chest bone. The angle
## clamp alone stops the mesh from folding the chin into the chest, but the
## hood still bulges out close enough to the eye that the camera's near clip
## can end up inside it - this keeps the eye pinned outside that volume.
func _solve_safe_pitch(raw_pitch: float, head_pos: Vector3) -> float:
	var candidate := body.clamp_head_pitch(raw_pitch)
	if candidate >= 0.0 or _chest_bone_idx < 0:
		return candidate
	var chest_pos := body.transform * skeleton.get_bone_global_pose(_chest_bone_idx).origin
	if _eye_distance(head_pos, chest_pos, candidate) >= EYE_CHEST_CLEARANCE:
		return candidate
	var lo := 0.0
	var hi := candidate
	for i in 8:
		var mid := (lo + hi) * 0.5
		if _eye_distance(head_pos, chest_pos, mid) >= EYE_CHEST_CLEARANCE:
			lo = mid
		else:
			hi = mid
	return lo


func _eye_distance(head_pos: Vector3, chest_pos: Vector3, pitch: float) -> float:
	var eye := head_pos + Basis(Vector3.RIGHT, pitch) * eye_offset
	return eye.distance_to(chest_pos)


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
	_fov_gizmo.visible = _debug_cam_active
	if not _debug_cam_active:
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
	var wants_sprint: bool = (Input.is_action_pressed(&"sprint")
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
	# Single weapon slot for now: owning the pistol item means it is equipped.
	weapon.equipped = inventory.count_of(weapon.weapon_item) > 0


func _on_weapon_fired() -> void:
	# Recoil stays player-side: the weapon signals up, the player owns the head.
	head.rotation.x = minf(head.rotation.x + 0.014, deg_to_rad(pitch_limit_deg))


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
