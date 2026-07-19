class_name PistolWeapon
extends Node3D
## Hitscan pistol viewmodel. Lives under the camera; owns the magazine.
## Reserve ammo lives in the player's Inventory as ammo_item stacks.
##
## Input is polled in _process (not _unhandled_input) on purpose: the node is
## PAUSABLE, so opening any overlay that pauses the tree also stops the gun —
## no firing through the inventory screen.

signal fired
signal ammo_changed(magazine: int, reserve: int)

## World (1) + damageable actors (4); bullets ignore the player and trigger areas.
const HIT_MASK := 0b101
const HOLE_LIFETIME := 20.0

@export var weapon_item: Item
@export var ammo_item: Item
@export var damage: float = 25.0
@export var fire_range: float = 40.0
@export var magazine_size: int = 7
@export var fire_interval: float = 0.35
@export var reload_time: float = 1.4
@export var aim_fov: float = 55.0
@export var hip_position := Vector3(0.24, -0.21, -0.46)
@export var aim_position := Vector3(0.0, -0.165, -0.38)

var equipped := false: set = set_equipped
var magazine := 0

var _inventory: Inventory
var _cooldown := 0.0
var _flash_left := 0.0
var _base_fov := 75.0
var _hole_mesh: QuadMesh

@onready var camera: Camera3D = get_parent()
@onready var muzzle_flash: OmniLight3D = $MuzzleFlash
@onready var fire_sound: AudioStreamPlayer = $FireSound
@onready var dry_sound: AudioStreamPlayer = $DrySound
@onready var reload_sound: AudioStreamPlayer = $ReloadSound


func _ready() -> void:
	_base_fov = camera.fov
	visible = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.04, 0.045)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hole_mesh = QuadMesh.new()
	_hole_mesh.size = Vector2(0.06, 0.06)
	_hole_mesh.material = mat


## Called by the player in _ready. The inventory is the source of truth for
## reserve ammo, so any pickup/drop refreshes the HUD counter too.
func setup(inventory: Inventory) -> void:
	_inventory = inventory
	_inventory.changed.connect(_emit_ammo)


func set_equipped(value: bool) -> void:
	if equipped == value:
		return
	equipped = value
	visible = value
	if not value:
		camera.fov = _base_fov
	_emit_ammo()


func reserve() -> int:
	if _inventory == null or ammo_item == null:
		return 0
	return _inventory.count_of(ammo_item)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			muzzle_flash.visible = false
	if not equipped:
		return
	if Input.is_action_just_pressed(&"fire"):
		_try_fire()
	elif Input.is_action_just_pressed(&"reload"):
		_try_reload()
	var aiming := Input.is_action_pressed(&"aim")
	position = position.lerp(aim_position if aiming else hip_position, 12.0 * delta)
	camera.fov = lerpf(camera.fov, aim_fov if aiming else _base_fov, 10.0 * delta)


func _try_fire() -> void:
	if _cooldown > 0.0:
		return
	if magazine == 0:
		dry_sound.play()
		_cooldown = 0.3
		return
	magazine -= 1
	_cooldown = fire_interval
	fire_sound.play()
	muzzle_flash.visible = true
	_flash_left = 0.05
	fired.emit()
	_emit_ammo()
	_hitscan()


func _try_reload() -> void:
	if _cooldown > 0.0 or magazine >= magazine_size:
		return
	var available := reserve()
	if available == 0:
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud:
			hud.toast("No 9mm ammo left")
		return
	var taken: int = mini(magazine_size - magazine, available)
	_inventory.remove_item(ammo_item, taken)
	magazine += taken
	_cooldown = reload_time
	reload_sound.play()
	_emit_ammo()


func _hitscan() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * fire_range
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit["collider"] as Node
	var target_health := collider.get_node_or_null(^"Health") as Health
	if target_health:
		var applied := target_health.apply_damage(damage)
		if applied > 0.0:
			DamageHitEffect.spawn(
					get_tree().current_scene, hit["position"], hit["normal"])
	else:
		_spawn_bullet_hole(hit["position"], hit["normal"])


func _spawn_bullet_hole(pos: Vector3, normal: Vector3) -> void:
	var hole := MeshInstance3D.new()
	hole.mesh = _hole_mesh
	get_tree().current_scene.add_child(hole)
	var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD
	# QuadMesh faces +Z, look_at points -Z at the target: aim into the surface
	# so the visible face points back out along the normal.
	hole.look_at_from_position(pos + normal * 0.01, pos - normal, up)
	# Tween is bound to the hole node, so it dies with it — no dangling timer
	# callback if the scene reloads before the lifetime elapses.
	var tween := hole.create_tween()
	tween.tween_interval(HOLE_LIFETIME)
	tween.tween_callback(hole.queue_free)


func _emit_ammo() -> void:
	ammo_changed.emit(magazine, reserve())
