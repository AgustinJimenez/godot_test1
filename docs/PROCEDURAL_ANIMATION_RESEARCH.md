# Procedural Animation in Godot 4: Complete Technical Guide, Math, Engine Built-Ins & Survival Horror Roadmap

---

## 1. Executive Summary & Core Philosophy

**Procedural Animation** is the generation and modification of character poses and movement in real time using mathematics, physics, and sensory feedback (e.g. raycasts, velocities, collisions) rather than relying solely on static, pre-baked animation clips.

In modern game design, procedural animation is **not** an all-or-nothing replacement for hand-crafted keyframes. Rather, it serves as a **layer of dynamic responsiveness** on top of authored animation:
1. **Authored Animations** supply style, personality, key character silhouettes, and artistic intent.
2. **Procedural Layers** adapt those poses to unpredictable environments: conforming feet to uneven stairs, leaning into tight corners, imparting physical weight to weapon aiming, dynamically flinching upon bullet impact, and allowing multi-legged monstrosities to traverse walls and ceilings without foot sliding.

---

## 2. Godot 4.6 Core Built-In Procedural Systems

In Godot 4.6, the old `SkeletonModificationStack3D` has been superseded by a deterministic, node-based **`SkeletonModifier3D`** pipeline that executes directly inside `Skeleton3D` immediately after animation playback evaluation and before mesh skinning.

```
┌────────────────────────────────────────────────────────┐
│                      Skeleton3D                        │
│                                                        │
│  1. AnimationPlayer / AnimationTree (Base Poses)       │
│                            │                           │
│                            ▼                           │
│  2. SkeletonModifier3D Stack (Executed in Order)       │
│     ├── RetargetModifier3D       (Pose retargeting)    │
│     ├── PlayerLookPoseModifier   (Gaze & aiming)       │
│     ├── PlayerFootIKModifier     (Terrain foot plant)  │
│     ├── SpringBoneSimulator3D    (Hair/gear jiggle)    │
│     └── Custom HitFlinchModifier (Bullet impacts)      │
│                            │                           │
│                            ▼                           │
│  3. ArrayMesh / Skin Deformation (GPU Skinning)        │
└────────────────────────────────────────────────────────┘
```

### A. Engine Built-In Classes Reference

| Node / Class | Category | Mathematical Basis | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **`SkeletonModifier3D`** | Base Class | Custom Matrix Operations | Base class for GDScript procedural bone transformers (`_process_modification_with_delta`). |
| **`SpringBoneSimulator3D`** | Secondary Physics | Semi-Implicit Euler Springs | Real-time spring-damper jiggle for hair, dangling pouches, weapon straps, tails, and holsters. |
| **`SpringBoneCollisionSphere3D`** / **`Capsule3D`** | Physics Colliders | Geometric Penalty Projection | Attached to body bones to prevent spring bones from clipping into the character mesh. |
| **`TwoBoneIK3D`** | Analytical IK | Law of Cosines (Closed-Form) | Ultra-fast 2-joint limb solver (human arms/legs with knee/elbow pole targets). |
| **`FABRIK3D`** | Heuristic IK | Forward & Backward Projection | Multi-joint chains (spines, tentacles, ropes, arachnid/creature legs). |
| **`CCDIK3D`** | Heuristic IK | Cyclic Coordinate Descent | Highly constrained chains (robotic arms, mechanical limbs). |
| **`SplineIK3D`** | Curve IK | Cubic Hermite / Bezier Splines | Smooth curve-driven bone chains (tails, tongues, hoses, flexible spines). |
| **`LookAtModifier3D`** | Gaze / Aim | Spherical Rotation Clamping | Constrained rotation of head, neck, or eyes toward 3D target coordinates. |
| **`AimModifier3D`** | Weapon Aim | Multi-Bone Axis Orientation | Orients weapon bones and upper spine toward a target point while preserving grip transforms. |
| **`RetargetModifier3D`** | Retargeting | Model-Space Basis Conversion | Real-time bone mapping and pose transfer between skeletons of different proportions. |
| **`PhysicalBone3D`** | Rigid Body Physics | Jolt Physics Simulation | Rigid bodies bound to skeleton bones for active ragdolls, physical hit reactions, and death physics. |

---

## 3. Seven In-Depth Procedural Modules & GDScript Templates

---

### Module 1: Second-Order Dynamics (Weapon Sway, Flashlight Inertia, Camera Bob)

#### Theoretical Formulation
Second-Order Dynamics mathematically model a physical mass attached to a target via a damped spring. Based on the differential equation:
$$\ddot{y} + 2\zeta\omega_n \dot{y} + \omega_n^2 y = \omega_n^2 x + r \cdot 2\zeta\omega_n \dot{x}$$

Where:
- $f$ ($Hz$): **Natural Frequency** (response speed).
- $\zeta$ (Dimensionless): **Damping Ratio** ($\zeta = 1.0$ is critically damped, $\zeta < 1.0$ introduces springy overshoot, $\zeta > 1.0$ is sluggish).
- $r$ (Dimensionless): **Initial Response** ($r = 0$ is pure lag, $r = 1$ is immediate reaction, $r > 1$ creates an anticipatory overshoot/kick).

#### Stable GDScript Reference (`SecondOrderDynamics.gd`)
```gdscript
class_name SecondOrderDynamics
extends RefCounted

var _xp: Vector3 = Vector3.ZERO # Previous input
var _y: Vector3 = Vector3.ZERO  # Current output position
var _yd: Vector3 = Vector3.ZERO # Current output velocity

var _k1: float
var _k2: float
var _k3: float

func _init(f: float, z: float, r: float, initial_value: Vector3 = Vector3.ZERO) -> void:
	recompute_constants(f, z, r)
	_xp = initial_value
	_y = initial_value
	_yd = Vector3.ZERO

func recompute_constants(f: float, z: float, r: float) -> void:
	_k1 = z / (PI * f)
	_k2 = 1.0 / pow(2.0 * PI * f, 2.0)
	_k3 = r * z / (2.0 * PI * f)

func update(x: Vector3, delta: float) -> Vector3:
	if delta <= 0.0:
		return _y
	var xd := (x - _xp) / delta
	_xp = x
	
	# Clamp time step for numerical stability under frame drops
	var iterations := maxi(1, int(ceil(delta / 0.016)))
	var dt := delta / float(iterations)
	
	for i in iterations:
		_y += dt * _yd
		_yd += dt * (x + _k3 * xd - _y - _k1 * _yd) / _k2
	return _y
```

#### Application: FPS Weapon & Flashlight Sway
```gdscript
# In weapon_controller.gd:
var _rot_spring := SecondOrderDynamics.new(3.5, 0.75, -0.4) # Springy inertia
var _pos_spring := SecondOrderDynamics.new(4.0, 0.85, 0.0)

func update_sway(mouse_delta: Vector2, walk_bob: Vector3, delta: float) -> void:
	var target_rot := Vector3(-mouse_delta.y * 0.02, -mouse_delta.x * 0.03, mouse_delta.x * 0.015)
	rotation = _rot_spring.update(target_rot, delta)
	position = _pos_spring.update(walk_bob, delta)
```

---

### Module 2: Dynamic Locomotion Leaning & Centrifugal Banking

#### Theoretical Formulation
When a character changes horizontal velocity, inertia exerts a virtual force $\mathbf{F} = -m\mathbf{a}$. To maintain balance, the body must lean in the direction of acceleration. When turning at speed $v$ along angular velocity $\omega$, centrifugal acceleration is $a_c = v \cdot \omega$.

#### GDScript Implementation (`LocomotionLeanModifier3D.gd`)
```gdscript
class_name LocomotionLeanModifier3D
extends SkeletonModifier3D

@export var max_pitch_lean_deg: float = 6.0
@export var max_roll_bank_deg: float = 8.0
@export var lean_smoothing: float = 8.0

var _prev_velocity: Vector3 = Vector3.ZERO
var _current_pitch: float = 0.0
var _current_roll: float = 0.0

func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	var actor := get_parent().get_parent() as CharacterBody3D
	if skel == null or actor == null or delta <= 0.0:
		return
		
	var local_vel := actor.global_basis.inverse() * actor.velocity
	var local_accel := (local_vel - _prev_velocity) / delta
	_prev_velocity = local_vel
	
	var target_pitch := clampf(-local_accel.z * 0.02, -deg_to_rad(max_pitch_lean_deg), deg_to_rad(max_pitch_lean_deg))
	var target_roll := clampf(-local_accel.x * 0.02, -deg_to_rad(max_roll_bank_deg), deg_to_rad(max_roll_bank_deg))
	
	_current_pitch = move_toward(_current_pitch, target_pitch, lean_smoothing * delta)
	_current_roll = move_toward(_current_roll, target_roll, lean_smoothing * delta)
	
	# Apply progressive tilt across spine hierarchy
	for bone_name: StringName in [&"Spine", &"Spine1", &"Spine2"]:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			var pose := skel.get_bone_global_pose(idx)
			pose.basis = Basis(Vector3.RIGHT, _current_pitch * 0.33) * Basis(Vector3.FORWARD, _current_roll * 0.33) * pose.basis
			skel.set_bone_global_pose(idx, pose)
```

---

### Module 3: Procedural Multi-Legged Gaits (Raycast + Bezier Foot Stepping)

#### Theoretical Formulation
Multi-legged creatures (quadrupeds, 6-legged mutants, 8-legged arachnids) navigate arbitrary 3D geometry by evaluating each leg independently:
1. **Ideal Footprint**: $\mathbf{P}_{\text{ideal}} = \mathbf{P}_{\text{hip}} + \text{Basis} \cdot \mathbf{O}_{\text{rest}} + \mathbf{v} \cdot T_{\text{lead}}$.
2. **Liftoff Trigger**: When $|\mathbf{P}_{\text{current}} - \mathbf{P}_{\text{ideal}}| > D_{\text{threshold}}$ and the paired leg group is grounded.
3. **Trajectory**: Evaluated using a 3D Quadratic or Cubic Bezier curve with vertical apex height $H$.

$$\mathbf{B}(t) = (1-t)^2 \mathbf{P}_{\text{start}} + 2(1-t)t (\mathbf{P}_{\text{mid}} + H \cdot \mathbf{n}) + t^2 \mathbf{P}_{\text{target}}$$

```
       Trajectory Apex (P_mid + H * UP)
             ▲
           /   \
          /     \
         /       ▼
     P_start    P_target (Raycast on surface)
```

#### GDScript Stepper (`ProceduralLegStepper.gd`)
```gdscript
class_name ProceduralLegStepper
extends RefCounted

var current_position: Vector3
var target_position: Vector3
var start_position: Vector3
var step_progress: float = 1.0 # 1.0 = fully planted
var is_stepping: bool = false

func update_step(ideal_ground: Vector3, step_height: float, step_speed: float, delta: float) -> Vector3:
	if is_stepping:
		step_progress = minf(step_progress + delta * step_speed, 1.0)
		var t := step_progress
		# Parabolic lift
		var ground_pos := start_position.lerp(target_position, t)
		var lift := 4.0 * t * (1.0 - t) * step_height
		current_position = ground_pos + Vector3.UP * lift
		if step_progress >= 1.0:
			is_stepping = false
			current_position = target_position
	elif current_position.distance_to(ideal_ground) > 0.4:
		start_step(ideal_ground)
	return current_position

func start_step(new_target: Vector3) -> void:
	start_position = current_position
	target_position = new_target
	step_progress = 0.0
	is_stepping = true
```

---

### Module 4: Additive Procedural Hit Reactions & Dynamic Flinching

#### Theoretical Formulation
When struck by a projectile or melee attack, traditional animations are often overridden or interrupted. Procedural flinching injects an instantaneous rotational velocity $\vec{\omega}_{\text{impact}}$ into specific bones, which decays via a critically damped angular spring without resetting current locomotion playback.

#### GDScript Modifier (`ProceduralFlinchModifier3D.gd`)
```gdscript
class_name ProceduralFlinchModifier3D
extends SkeletonModifier3D

var _flinch_spring := SecondOrderDynamics.new(4.5, 0.7, 0.0)
var _current_flinch_rot: Vector3 = Vector3.ZERO
var _target_impulse: Vector3 = Vector3.ZERO

func inject_hit(impact_point: Vector3, hit_direction: Vector3, strength: float = 1.0) -> void:
	var skel := get_skeleton()
	var chest_idx := skel.find_bone(&"Spine1")
	var chest_pos := skel.get_bone_global_pose(chest_idx).origin if chest_idx >= 0 else Vector3.ZERO
	var local_impact := (impact_point - chest_pos).normalized()
	
	# Torque = r x F
	var torque := local_impact.cross(hit_direction) * strength
	_target_impulse = torque

func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
		
	_current_flinch_rot = _flinch_spring.update(_target_impulse, delta)
	_target_impulse = _target_impulse.move_toward(Vector3.ZERO, 15.0 * delta)
	
	if is_zero_approx(_current_flinch_rot.length_squared()):
		return
		
	for bone_name: StringName in [&"Spine1", &"Spine2", &"Head"]:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			var pose := skel.get_bone_global_pose(idx)
			pose.basis = Basis.from_euler(_current_flinch_rot * 0.33) * pose.basis
			skel.set_bone_global_pose(idx, pose)
```

---

### Module 5: Dynamic Motion Warping for Obstacle Mantling & Vaulting

#### Theoretical Formulation
When a player interacts with a ledge or obstacle of arbitrary height, motion warping scales the translation and rotation curves of a base root-motion vaulting clip so that the character's hands and feet land with exact precision on the ledge geometry.

$$\mathbf{P}_{\text{character}}(t) = \mathbf{P}_{\text{start}} + \frac{\mathbf{P}_{\text{ledge}} - \mathbf{P}_{\text{start}}}{\mathbf{P}_{\text{anim\_end}} - \mathbf{P}_{\text{anim\_start}}} \cdot \Delta \mathbf{P}_{\text{anim}}(t)$$

---

### Module 6: Procedural Gaze & Saccadic Eye / Head Tracking

#### Theoretical Formulation
Human eyes and heads do not move with smooth linear interpolation. They perform **saccades**: rapid, ballistic jumps between fixation points, followed by micro-tremors (micro-saccades) to refresh photoreceptor cells.

```gdscript
# Saccade generator
var _saccade_offset: Vector2 = Vector2.ZERO
var _saccade_timer: float = 0.0

func _update_gaze_saccades(delta: float) -> Vector2:
	_saccade_timer -= delta
	if _saccade_timer <= 0.0:
		_saccade_timer = randf_range(0.4, 1.8) # Next saccade in 0.4 - 1.8s
		_saccade_offset = Vector2(randf_range(-0.04, 0.04), randf_range(-0.03, 0.03))
	return _saccade_offset
```

---

### Module 7: Procedural Dynamic Injury Limp & Fatigue

#### Theoretical Formulation
Instead of requiring an entire separate suite of injured mocap files, an injury modifier introduces:
1. **Pelvis Drop on Damaged Leg**: When the injured leg enters stance phase, sink the pelvis by $5\text{–}12\text{ cm}$.
2. **Contact Time Asymmetry**: The injured leg spends 35% less time in stance, causing an abrupt, hurried weight transfer to the healthy leg.
3. **Upper Body Heavy Lean**: Tilt the upper spine over the healthy leg to simulate weight unburdening.

---

## 4. Specific Applications for Survival Horror FPS

| Feature Area | Procedural Technique | Horror Atmosphere & Gameplay Impact |
| :--- | :--- | :--- |
| **Flashlight & Darkness** | Second-Order Lag + Breathing Bob | The flashlight cone lags realistically as the player rapidly pans across terrifying dark corners, building immense claustrophobic tension. |
| **Weapon Handling** | Procedural Inertia & Dynamic Recoil | Firearms feel heavy, weighty, and desperate rather than snappy arcade pointers; stamina depletion introduces physical weapon sway. |
| **Limping & Health State** | Dynamic Pelvis Sinking & Stride Asymmetry | When wounded by an enemy, the character visibly limps and sways, visually communicating physical vulnerability without breaking player control. |
| **Monster Locomotion** | Raycast Multileg Bezier Stepping | Multi-limbed monstrosities and crawler mutants dynamically scale walls, navigate debris, and scuttle unpredictably toward the player. |
| **Combat Feedback** | Additive Directional Hit Flinches | Enemies physically stagger backwards or twist away exactly where gunshots hit their limbs or chest. |

---

## 5. Implementation Roadmap for the Project

```
  ┌────────────────────────────────────────────────────────┐
  │  Phase 1: First-Person Weight & Atmosphere Polish      │
  │  ├── 1. Second-Order Dynamics for Weapon Sway & Lag    │
  │  ├── 2. Flashlight Inertia & Breathing Modulation      │
  │  └── 3. Locomotion Leaning & Banking Modifier          │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼
  ┌────────────────────────────────────────────────────────┐
  │  Phase 2: Combat Feedback & Secondary Physics          │
  │  ├── 1. Additive Procedural Hit Reactions (Flinch)     │
  │  ├── 2. SpringBoneSimulator3D Setup on Character Gear   │
  │  └── 3. Dynamic Injury / Limp Modifier                 │
  └──────────────────────────┬─────────────────────────────┘
                             │
                             ▼
  ┌────────────────────────────────────────────────────────┐
  │  Phase 3: Horror Monster & Multi-Legged AI Gaits       │
  │  ├── 1. Wall/Ceiling Crawler Procedural Stepper        │
  │  └── 2. Procedural Head Tracking & Gaze Saccades       │
  └────────────────────────────────────────────────────────┘
```
