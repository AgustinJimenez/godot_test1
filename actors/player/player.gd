class_name Player
extends CharacterBody3D
## First-person controller: mouse look, walk/sprint/crouch, stamina,
## flashlight toggle and interaction ray. No jump — classic survival horror.

const STAND_CAPSULE_HEIGHT := 1.8
const CROUCH_CAPSULE_HEIGHT := 1.2
const STAND_HEAD_Y := 1.62
const CROUCH_HEAD_Y := 1.05

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

@export_group("Head bob")
@export var bob_amplitude: float = 0.035
@export var bob_frequency: float = 2.2

var stamina: float
var _sprint_locked := false
var _crouched := false
var _bob_time := 0.0
var _dead := false

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


func _ready() -> void:
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
	elif event.is_action_pressed(&"inventory"):
		hud.toggle_inventory()
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

	_update_head_bob(delta)
	var target := _current_interactable()
	hud.set_prompt("[E] " + target.prompt if target else "")


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


func _update_head_bob(delta: float) -> void:
	var base_y := CROUCH_HEAD_Y if _crouched else STAND_HEAD_Y
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var bob := 0.0
	if is_on_floor() and ground_speed > 0.5:
		_bob_time += delta * ground_speed
		bob = sin(_bob_time * bob_frequency) * bob_amplitude
	head.position.y = lerpf(head.position.y, base_y + bob, 10.0 * delta)


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
