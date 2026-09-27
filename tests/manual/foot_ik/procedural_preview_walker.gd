extends Node3D
## Procedural (Path B) leg gait, shown on foot_ik_preview.tscn's own 0.35 m staircase so it can be
## compared by eye with the Foot IK characters walking the same stairs. Reuses the procedural lab's
## modifier and reference bank unchanged; only the terrain is this scene's (see
## procedural_preview_stairs.gd) and the driving loop is the lab's `_advance_moving` reduced to a
## straight climb. The upper body stays on the frozen idle base pose, exactly like the lab.

const MODEL := preload(
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Relaxed_Idle_IPC.fbx")
const MODIFIER := preload("res://tests/manual/procedural_walk/procedural_walk_modifier.gd")
const REFERENCE_BANK := preload(
		"res://tests/manual/procedural_walk/procedural_walk_reference_bank.gd")
const PREVIEW_STAIRS := preload(
		"res://tests/manual/foot_ik/procedural_preview_stairs.gd")

## Same stair platform as the preview's "Stairs 0.35m" case (origin x = 6 * PLATFORM_SPACING),
## offset sideways so the procedural walker and the Foot IK walker share the staircase without
## standing inside each other.
const LANE_X := 14.0
const BASE_Z := 0.0
const START_Z := -1.2
const CYCLES_PER_SEC := 0.7
const RESTART_MARGIN := 0.6

var _character: Node3D
var _skeleton: Skeleton3D
var _modifier: ProceduralWalkLabModifier
var _reference_bank: ProceduralWalkReferenceBank
var _stairs: ProceduralPreviewStairs
var _cycles := 0.0

func _ready() -> void:
	_stairs = PREVIEW_STAIRS.new() as ProceduralPreviewStairs
	_stairs.configure(BASE_Z)
	_character = MODEL.instantiate() as Node3D
	_character.name = &"Body"
	add_child(_character)
	_skeleton = _character.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := _character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null or player == null:
		push_error("Procedural preview walker: model needs a Skeleton3D and AnimationPlayer")
		return
	# Frozen idle base pose (the lab does the same) - the modifier owns the legs from here.
	player.play(&"W1_Stand_Relaxed_Idle_IPC")
	player.advance(0.0)
	player.pause()
	_reference_bank = REFERENCE_BANK.new() as ProceduralWalkReferenceBank
	if not _reference_bank.build(self, _skeleton):
		push_error("Procedural preview walker: could not build the reference pose bank")
		return
	_modifier = MODIFIER.new() as ProceduralWalkLabModifier
	_modifier.name = &"ProceduralWalk"
	_modifier.reference_bank = _reference_bank
	_modifier.reference_mode = &"stair_up"
	_modifier.stair_direction = 1
	_modifier.stair_course = _stairs
	_modifier.neutral_ankle_targets = [
		_skeleton.get_bone_global_pose(_skeleton.find_bone(&"LeftFoot")).origin,
		_skeleton.get_bone_global_pose(_skeleton.find_bone(&"RightFoot")).origin,
	]
	_skeleton.add_child(_modifier)
	_skeleton.set_modifier_callback_mode_process(Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS)
	_restart()
	_skeleton.advance(0.0)

func _restart() -> void:
	_cycles = 0.0
	_character.global_position = Vector3(LANE_X, _stairs.root_height(START_Z), START_Z)
	_modifier.moving_mode = true
	_modifier.reset_moving_state()

func _physics_process(delta: float) -> void:
	if _modifier == null or _reference_bank == null:
		return
	_cycles += delta * CYCLES_PER_SEC
	var travel_per_cycle := 2.0 * _modifier.stride * _modifier.amount / (
			1.0 - ProceduralWalkLabModifier.SWING_FRACTION)
	var next_z := _character.global_position.z + travel_per_cycle * delta * CYCLES_PER_SEC
	if next_z > _stairs.top_z() + RESTART_MARGIN:
		_restart()
		return
	_character.global_position = Vector3(LANE_X, _stairs.root_height(next_z), next_z)
	# One full gait cycle is 60 frames at the lab's 60 fps reference rate (CYCLE_FRAMES = 120 = two
	# steps), so the phase is just the cycle count wrapped to a turn.
	_modifier.phase = fposmod(_cycles * TAU, TAU)
