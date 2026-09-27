class_name ProceduralPreviewStairs
extends ProceduralWalkStairCourse
## Preview-matched stair terrain for the procedural walker in foot_ik_preview.tscn.
## Subclasses ProceduralWalkStairCourse so it can be handed to ProceduralWalkLabModifier's
## `stair_course` (which is typed as that class), but overrides every height/placement function
## with this scene's own staircase geometry: 6 steps, 0.35 m rise, 0.6 m tread, ascending +Z from
## `base_z` (identical to foot_ik_preview.gd's `_stair_walker_tread_height`). The parent's own
## constants describe the lab's 12 x 0.35 x 0.18 course, so its methods cannot be reused here.

const PREVIEW_STEPS := 6
const PREVIEW_RISE := 0.35
const PREVIEW_TREAD := 0.6
## How close the ankle is allowed to the tread's front/rear edge (keeps the shoe on the tread).
const TOE_RESERVE := 0.16
const HEEL_RESERVE := 0.13

var base_z := 0.0

## Base Z of the staircase's bottom tread (the preview's stair platform origin).
func configure(base: float) -> void:
	base_z = base

func top_z() -> float:
	return base_z + float(PREVIEW_STEPS) * PREVIEW_TREAD

func top_height() -> float:
	return float(PREVIEW_STEPS) * PREVIEW_RISE

func support_height(world_z: float) -> float:
	var d := world_z - base_z
	if d < 0.0:
		return 0.0
	if d >= float(PREVIEW_STEPS) * PREVIEW_TREAD:
		return top_height()
	var tread := clampi(int(floorf(d / PREVIEW_TREAD)), 0, PREVIEW_STEPS - 1)
	return float(tread + 1) * PREVIEW_RISE

func root_height(world_z: float) -> float:
	return support_height(world_z)

## Keep an ankle target on its tread (clamped away from both edges), matching the parent's intent.
func safe_ankle(target: Vector3, long_toe: bool = false) -> Vector3:
	var d := target.z - base_z
	if d < 0.0 or d >= float(PREVIEW_STEPS) * PREVIEW_TREAD:
		return target
	var tread_start := floorf(d / PREVIEW_TREAD) * PREVIEW_TREAD
	var front_edge := base_z + tread_start
	var rear_edge := front_edge + PREVIEW_TREAD
	var toe_reserve := TOE_RESERVE + (0.05 if long_toe else 0.0)
	target.z = clampf(target.z, front_edge + toe_reserve, rear_edge - HEEL_RESERVE)
	return target

func is_climbing(world_z: float) -> bool:
	var d := world_z - base_z
	return d >= 0.0 and d < float(PREVIEW_STEPS) * PREVIEW_TREAD

func is_finished(world_z: float) -> bool:
	return world_z - base_z > float(PREVIEW_STEPS) * PREVIEW_TREAD + 0.5
