extends Node3D
## Phase 1 scaffold for AGENT_TASKS/016 - an ALS-style locomotion prototype
## built from scratch, independent of actors/player/*. Character: Y Bot
## (assets/models/mixamo_characters/Y Bot.fbx), chosen after comparing X Bot
## and Y Bot in tests/manual/animation/als_retarget_preview.tscn - X Bot
## looks visibly feminine/androgynous, a poor match for the muscular ALS
## reference mesh. Previously used the default player rig
## (W1_Stand_Aim_Idle_IPC.fbx, what's really on screen in
## foot_ik_preview.tscn) - see git history for that variant.
## Animations are retargeted onto this rig via tools/retarget_cli.gd's
## target_model= mode (no catalog manifest needed). Every clip here must come
## from the same ALSHost export pipeline - never this project's own
## pistol_starter/Mixamo animations.
## AnimationTree root is an AnimationNodeStateMachine (Grounded/Airborne/
## Mantle/TurnXxx...), not a single flat blendspace, since travel() needs a
## named state to switch to on events like the is_on_floor() edge. Grounded
## holds a 2D BLEND_MODE_DIRECTIONAL blendspace (real ALS technique - idle at
## the origin, walk-speed and run-speed rings of 6 directional clips each,
## keyed by the character-LOCAL (right, forward) velocity); Airborne holds a
## 1D blendspace keyed by vertical-velocity sign (fall vs. jump loop).
##
## Split into als_locomotion_prototype_state.gd (this file) / _build.gd /
## als_locomotion_prototype.gd purely to stay under the project's
## max-file-lines lint cap - a pure mechanical relocation via GDScript's own
## extends-a-script-file inheritance, no logic moved or changed. This file
## holds every top-level const/var declaration (all three files' functions
## read/write them) plus the setup-only, low-coupling functions; _build.gd
## holds the full player/AnimationTree construction; the attached script
## holds the per-frame update loop and terrain building.

const CHARACTER_MODEL := "res://assets/models/mixamo_characters/Y Bot.fbx"
## ALS has no baked idle cycle - the pose export is a near-single-frame hold
## (ALS_N_Pose), not a looping clip. Real ALS idles by holding this pose plus
## an additive sway (ALS_N_SecondaryMotion), not modeled here yet.
const IDLE_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Pose_on_ybot.res"
const JUMP_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_JumpLoop_on_ybot.res"
const FALL_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_FallLoop_on_ybot.res"
const LAND_LIGHT_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Land_Light_on_ybot.res"
const LAND_HEAVY_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Land_Heavy_on_ybot.res"
## Real ALS (ALSBaseCharacter.cpp EventOnLanded, per source research) uses
## fall-SPEED thresholds to pick the landing reaction: |VelZ| > 1000 cm/s
## (10 m/s) ragdolls, >= 700 cm/s (7 m/s) + moving input breakfalls -
## neither is "pick a Light vs Heavy landing POSE", which is actually an
## AnimBP-side decision in real ALS too (not a C++ number to port exactly).
## This value is our own choice for that light/heavy pose split, not a
## ported constant - picked comfortably above JUMP_VELOCITY (6.0) so an
## ordinary jump always lands light, while falling off the taller mantle
## ledge or down a level lands heavy.
const LAND_HEAVY_SPEED_THRESHOLD := 5.0
## Directional locomotion clips for the Grounded 2D blendspace - clip_name ->
## [source .res path, (right, forward) direction unit vector]. ALS's own
## exported set has no pure left/right strafe (only forward/back + the 4
## diagonals), matching a standard 6-point radial blendspace rather than 8.
## The Run_* ring sits at RUN_SPEED, not SPRINT_SPEED: these are ALS's
## `ALS_N_Run_*` clips, authored against RunSpeed (375cm/s). ALS has no
## separate sprint clip set - it reuses the run cycle at a higher play rate
## (`CalculateStandingPlayRate`'s sprint lerp), so sprinting here simply
## saturates against the outer run ring.
const DIRECTIONAL_ANIMATIONS := {
	&"walk_f": ["res://assets/models/als_retarget_test/ALS_N_Walk_F_on_ybot.res",
			Vector2(0.0, 1.0), WALK_SPEED],
	&"walk_b": ["res://assets/models/als_retarget_test/ALS_N_Walk_B_on_ybot.res",
			Vector2(0.0, -1.0), WALK_SPEED],
	&"walk_lf": ["res://assets/models/als_retarget_test/ALS_N_Walk_LF_on_ybot.res",
			Vector2(-0.707, 0.707), WALK_SPEED],
	&"walk_rf": ["res://assets/models/als_retarget_test/ALS_N_Walk_RF_on_ybot.res",
			Vector2(0.707, 0.707), WALK_SPEED],
	&"walk_lb": ["res://assets/models/als_retarget_test/ALS_N_Walk_LB_on_ybot.res",
			Vector2(-0.707, -0.707), WALK_SPEED],
	&"walk_rb": ["res://assets/models/als_retarget_test/ALS_N_Walk_RB_on_ybot.res",
			Vector2(0.707, -0.707), WALK_SPEED],
	&"run_f": ["res://assets/models/als_retarget_test/ALS_N_Run_F_on_ybot.res",
			Vector2(0.0, 1.0), RUN_SPEED],
	&"run_b": ["res://assets/models/als_retarget_test/ALS_N_Run_B_on_ybot.res",
			Vector2(0.0, -1.0), RUN_SPEED],
	&"run_lf": ["res://assets/models/als_retarget_test/ALS_N_Run_LF_on_ybot.res",
			Vector2(-0.707, 0.707), RUN_SPEED],
	&"run_rf": ["res://assets/models/als_retarget_test/ALS_N_Run_RF_on_ybot.res",
			Vector2(0.707, 0.707), RUN_SPEED],
	&"run_lb": ["res://assets/models/als_retarget_test/ALS_N_Run_LB_on_ybot.res",
			Vector2(-0.707, -0.707), RUN_SPEED],
	&"run_rb": ["res://assets/models/als_retarget_test/ALS_N_Run_RB_on_ybot.res",
			Vector2(0.707, -0.707), RUN_SPEED],
}
## ALS's crouch locomotion set is 4-point - pure F/B/L/R strafes, with NO
## diagonal clips, unlike the 6-point radial standing set above. Retargeted
## from ALS_CLF_Walk_* onto Y Bot. `ALS_CLF_Pose` is the crouched idle (a
## single-frame pose, hence its ~0.03s length).
## clip_name -> [source .res path, (right, forward) direction unit vector].
const CROUCH_ANIMATIONS := {
	&"crouch_f": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_F_on_ybot.res",
			Vector2(0.0, 1.0)],
	&"crouch_b": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_B_on_ybot.res",
			Vector2(0.0, -1.0)],
	&"crouch_l": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_L_on_ybot.res",
			Vector2(-1.0, 0.0)],
	&"crouch_r": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_R_on_ybot.res",
			Vector2(1.0, 0.0)],
}
const CROUCH_IDLE_ANIMATION := "res://assets/models/als_retarget_test/ALS_CLF_Pose_on_ybot.res"

## ALS DOES ship a dedicated sprint cycle - an earlier version of this file
## claimed otherwise and drove sprint by speeding the run clip up instead,
## which is why sprinting looked wrong. It is forward-only, and that is
## consistent rather than a gap: `CalculateMovementDirection()` returns
## Forward unconditionally while sprinting, so no directional variants exist
## to miss. The clip is a normal absolute pose (hips at 0.93, checked - NOT
## additive like ALS_N_SecondaryMotion), but it only animates 21 bones: every
## major body bone, omitting Head and the fingers, which fall back to the rest
## pose. That matches the AnimBP's own "Apply Sprinting if not masked" comment.
const SPRINT_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Sprint_F_on_ybot.res"
## How fast the sprint layer eases in/out, this prototype's own value.
const SPRINT_BLEND_SPEED := 8.0
## The retargeted sprint clip is FINE - an earlier version of this comment
## claimed its arm chain was broken and disabled it. That was wrong, and the
## error is worth recording: it came from measuring hand positions in the
## running game and converting into "the character's local frame" using
## `_facing.global_rotation.y`, which ignores that the skeleton sits under the
## `visual` node carrying an extra 180 deg - so the sign was unreliable.
## Re-measured offline instead (retarget in isolation, apply straight to a
## fresh Y Bot skeleton, read skeleton-space X - no game, no camera, no
## facing conversion): left [-0.303, -0.089], right [0.089, 0.319]. No
## crossing. An A/B with `match_arm_positions` off confirms that pass is what
## keeps the chain correct, for run and sprint alike.
## ROOT-CAUSED AND FIXED - and the fix was in the RETARGET, not here.
##
## Every clip added this session (the 5 crouch clips and this one) came out
## with the arms thrown behind the back and mirrored, while the pre-existing
## walk/run clips were fine. The common factor was not the clips: it was that
## I retargeted these six myself, passing `PlayerBody.BONE_MAP` as the source
## role map instead of `retarget_cli.gd`'s own `ALS_SOURCE_ROLE_MAP`, on the
## strength of a comment saying the two were interchangeable.
##
## They differ in one load-bearing key: the CLI map has `"head" -> "Head"`
## (lowercase, matching the ALS source bone) where BONE_MAP has
## `"Head" -> "Head"`. So `head_source` resolved to a bone that does not
## exist, `_skeleton_height(src, hips, head)` fell through to its 0.0001
## floor, and `arm_position_scale` - which scales the desired wrist target fed
## to the arm IK pass - exploded. The two-bone IK then aimed at an
## unreachable point and clamped, which is what put the arms behind the back.
## Legs and spine were untouched because only the arm pass uses that scale.
##
## After re-retargeting with the correct map, every clip has clean left/right
## separation and matches the SOURCE's own convention (sprint: left
## [0.132, 0.332], right [-0.333, -0.132]); the broken map had also been
## mirroring them. Track counts rose by one per clip too, since the head bone
## now maps at all.
##
## Lesson worth keeping: two role maps that look identical can differ in one
## key, and a wrong ROLE MAP degrades gracefully into plausible-but-wrong
## output rather than failing loudly.
const SPRINT_CLIP_ENABLED := true

## One-shot turn-in-place clips (2s each, not looped). Kept as separate
## states rather than decoding the clips' own hip rotation to drive
## _character.rotation.y - the actual yaw is instead driven procedurally in
## _physics_process (see _update_turn_in_place()), timed to the clip length.
## clip_name -> [source .res path, state machine node name, signed turn angle in degrees].
const TURN_ANIMATIONS := {
	&"turn_l90": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_L90_on_ybot.res",
			&"TurnL90", -90.0],
	&"turn_r90": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_R90_on_ybot.res",
			&"TurnR90", 90.0],
	&"turn_l180": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_L180_on_ybot.res",
			&"TurnL180", -180.0],
	&"turn_r180": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_R180_on_ybot.res",
			&"TurnR180", 180.0],
}
## Real values read live from ALS_AnimBP / ALSCharacterAnimInstance.cpp
## (FALSTurnInPlaceValues defaults, ALSAnimationStructLibrary.h): Turn180Threshold
## picks the 90 vs 180 clip; TurnCheckMinAngle/AimYawRateLimit/Min/MaxAngleDelay
## gate a real ElapsedDelayTime accumulator (TurnInPlaceCheck) rather than firing
## instantly the moment the angle is crossed - a near-45 angle turns almost
## immediately, a near-180 angle waits up to MaxAngleDelay before committing,
## so a quick camera flick past the threshold doesn't trigger a turn.
const TURN_180_THRESHOLD_DEG := 130.0
const ALS_TURN_CHECK_MIN_ANGLE_DEG := 45.0
const ALS_AIM_YAW_RATE_LIMIT_DEG := 50.0
const ALS_TURN_MIN_ANGLE_DELAY := 0.0
const ALS_TURN_MAX_ANGLE_DELAY := 0.75

## Basic mantling: press jump facing a ledge in this height range to climb it
## instead of jumping. Like turn-in-place, the actual repositioning is driven
## procedurally (lerp body position to the ledge-top point, timed to the
## clip's length) rather than by decoding the clip's own root motion.
## Real ALS (ALSMantleComponent.cpp, per source research) splits into Low
## and High mantle TYPES at a 125cm height threshold, each with its own
## animation asset and a genuinely curve-driven (Timeline + authored
## PositionCorrectionCurve) blend, not a plain position lerp - that part of
## the real system isn't portable without the curve assets, but the
## height-based clip split IS a concrete, portable fact, so this now uses
## ALS_N_Mantle_1m below the real 1.25m threshold and ALS_N_Mantle_2m above it.
const MANTLE_LOW_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Mantle_1m_RH_on_ybot.res"
const MANTLE_HIGH_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Mantle_2m_on_ybot.res"
## Real `FALSMantleTraceSettings`, read live off the `MantleComponent`
## Blueprint's class defaults - the C++ only declares the struct, the actual
## numbers live on the BP, so this is another case where the asset side was
## the only possible source. ALS keeps SEPARATE profiles per situation, which
## this prototype previously collapsed into one invented set: a standing
## mantle reaches a 2.5m ledge, but a mantle caught mid-jump only reaches
## 1.5m. (ALS's third profile, AutomaticTraceSettings - 80/40/50 - drives its
## continuous auto-detect mantle, which this prototype doesn't have.)
## ALS's centimetres, converted to metres.
const MANTLE_GROUNDED_MAX_HEIGHT := 2.5
const MANTLE_GROUNDED_MIN_HEIGHT := 0.5
const MANTLE_GROUNDED_REACH := 0.75
const MANTLE_FALLING_MAX_HEIGHT := 1.5
const MANTLE_FALLING_MIN_HEIGHT := 0.5
const MANTLE_FALLING_REACH := 0.7
## Both profiles share these in real ALS. The forward/downward probes are
## RADIUS traces, not the zero-width rays this used before - a thin ray can
## slip past a ledge edge that a 30cm-radius probe catches.
const MANTLE_TRACE_RADIUS := 0.3
## The forward trace's capsule half-height is `1cm + (Max - Min) / 2`, so it
## spans the whole mantleable band plus a 1cm pad; the downward trace's start
## uses the same 1cm. ALS's literal `1.0f`.
const MANTLE_TRACE_HALF_HEIGHT_PAD := 0.01
## ALS pushes the downward probe 15cm INTO the wall along its impact normal
## before sweeping down, so it lands on the ledge top instead of skimming the
## outer edge.
const MANTLE_DOWN_TRACE_NORMAL_OFFSET := 0.15
## `Mantle_2m_Default.LowHeight` on the same Blueprint - the height at which
## ALS switches from its 1m mantle asset to the 2m one. This prototype
## already had 1.25 and it is confirmed correct.
const ALS_MANTLE_HIGH_THRESHOLD := 1.25
## ALSMantleComponent.cpp step 3 passes 2.0 (cm) as the ZOffset when turning a
## found ledge-top into the capsule location to room-check - a small lift so
## the capsule isn't tested exactly flush with the surface it's about to stand
## on. 2cm in ALS's centimeters is 0.02 in this project's meters.
const ALS_MANTLE_CAPSULE_Z_OFFSET := 0.02
## Real `FALSMantleAsset.StartingOffset` (per asset, read off the
## `MantleComponent` Blueprint's class defaults): (Y, Z) = how far BEHIND and
## BELOW the ledge target the animation's own root motion is actually
## authored to start - real ALS calls this `MantleAnimatedStartOffset` and
## blends the early part of the climb toward it rather than straight-lining
## from wherever the player happened to approach from. This is the actual
## mechanism that keeps a real ALS mantle from clipping through the ledge
## edge: for most of the climb the body tracks this animation-matched
## reference point, only snapping onto the true landing spot near the end
## (see `ALS_MANTLE_POSITION_CORRECTION_CURVE_*` below). cm -> m.
const ALS_MANTLE_LOW_START_OFFSET := Vector2(0.65, 1.0)
const ALS_MANTLE_HIGH_START_OFFSET := Vector2(0.65, 2.0)
## Real `FALSMantleAsset.LowHeight/HighHeight/LowStartPosition/
## HighStartPosition/LowPlayRate/HighPlayRate` (Mantle_1m_RH and
## Mantle_2m_Default, from the same `MantleComponent` class-defaults read).
## `StartingPosition` lets a real ledge SHORTER than the asset's own designed
## max skip ahead into the correction curve/animation rather than always
## playing it from the start - real ALS default `HighStartPosition=0.0f`
## (verified against the struct default, since the CDO dump omits
## unset-from-default properties) means the TALLEST ledge in an asset's own
## range plays the full curve, a SHORTER one starts partway in. Previously
## unwired entirely - every mantle here always sampled from t=0 regardless of
## how short the actual gap was, which is real ALS data left on the table.
## `PlayRate` is CONSTANT per asset (both range endpoints are equal, i.e. no
## interpolation actually happens) - 1.0 for the 1m asset, 1.2 for the 2m
## one - so the High mantle should visibly play faster.
const ALS_MANTLE_LOW_HEIGHT_RANGE := Vector2(0.5, 1.0)
const ALS_MANTLE_LOW_START_POSITION_RANGE := Vector2(0.5, 0.0)
const ALS_MANTLE_LOW_PLAY_RATE := 1.0
const ALS_MANTLE_HIGH_HEIGHT_RANGE := Vector2(1.25, 2.0)
const ALS_MANTLE_HIGH_START_POSITION_RANGE := Vector2(0.6, 0.0)
const ALS_MANTLE_HIGH_PLAY_RATE := 1.2

## Mirrors the CollisionShape3D built in _build_player(). Real ALS's math
## library helpers take the capsule component and ask it for these; there's no
## equivalent single object to query here, so they're constants the two stay
## in sync with.
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.8

## CharacterBody3D has no automatic stair-stepping (unlike some other
## engines' built-in character controllers) - a stair's vertical riser is
## just a wall to move_and_slide(), confirmed by user report ("cannot walk
## on stairs") after both stair flights (0.15m/0.3m steps) were added to the
## terrain in Phase 1. STAIR_STEP_HEIGHT covers the taller of the two flights.
const STAIR_STEP_HEIGHT := 0.3

## Real ALS gait speeds, read live from `MovementModelTable`'s "Normal" row
## (Standing). These are exactly the numbers that genuinely do NOT exist
## anywhere in ALS's C++ - `WalkSpeed`/`RunSpeed`/`SprintSpeed` are all
## `0.0f` there and get filled in from this DataTable at runtime - so the
## asset side was the only place they could ever have come from. ALS's
## centimetres, converted to this project's metres.
##
## Note ALS's default gait is RUNNING: walk and sprint are both held
## modifiers off that baseline, which is why RUN_SPEED (not WALK_SPEED) is
## the no-modifier speed below. The prototype previously had two invented
## tiers (3.0/6.0) and no middle gait at all.
const WALK_SPEED := 1.75
const RUN_SPEED := 3.75
const SPRINT_SPEED := 6.5
## The project's shared input map has `sprint` and `jump` but no walk
## modifier, and ALS needs one for its third gait. Registered at runtime
## instead of edited into project.godot, so this sandbox can't change input
## for the real game. The KEY is this prototype's own choice; only the speeds
## above are ALS's.
const WALK_ACTION := &"als_prototype_walk"
## Crouch gait speeds, same `MovementModelTable` "Normal" row but its
## Crouching column: 150/200/300 cm/s. ALS keeps all three gaits while
## crouched, just slower - it does not collapse crouch to a single speed.
const CROUCH_WALK_SPEED := 1.5
const CROUCH_RUN_SPEED := 2.0
const CROUCH_SPRINT_SPEED := 3.0
## ALS's real `CrouchedHalfHeight` is 60cm - it overrides UE's 40 default -
## read off `ALS_CharacterBP`'s movement component via `obj dump` (the
## component-reading tools can't see inherited native components). So a 1.2m
## crouched capsule against this prototype's 1.8m standing one.
const CROUCH_CAPSULE_HEIGHT := 1.2
## ALS drops the eye height by exactly the capsule half-height delta
## (BaseEyeHeight 64 -> CrouchedEyeHeight 32, capsule half 92 -> 60, both
## -32cm), so the camera follows the capsule rather than needing its own
## tuned number.
const CROUCH_ACTION := &"als_prototype_crouch"
## How fast the standing<->crouching POSE blend eases (collision and speed
## switch immediately; only the animation blend is smoothed). This prototype's
## own value - ALS gets the equivalent smoothing from BasePose_N/BasePose_CLF
## animation curves, which our retargeted clips don't carry.
const STANCE_BLEND_SPEED := 6.0
## Real `Config.AnimatedWalkSpeed/RunSpeed/SprintSpeed/CrouchSpeed`
## (150/350/600/150 cm/s) - the speeds ALS's locomotion clips were actually
## AUTHORED at, which is a different thing from the gait speeds the character
## moves at. ALS ships no sprint clip set at all: `CalculateStandingPlayRate`
## divides real speed by the authored speed and plays the run cycle faster,
## which is why sprinting must clamp onto the run ring rather than fly past it.
const ALS_ANIMATED_WALK_SPEED := 1.5
const ALS_ANIMATED_RUN_SPEED := 3.5
const ALS_ANIMATED_SPRINT_SPEED := 6.0
const ALS_ANIMATED_CROUCH_SPEED := 1.5
## ALS clamps the resulting play rate to [0, 3].
const ALS_PLAY_RATE_MAX := 3.0
const ACCELERATION := 12.0
const DECELERATION := 16.0
const ROTATION_SPEED := 10.0
## Read directly from ALSBaseCharacter.cpp::UpdateGroundedRotation - real
## exact values, not approximations.
const ALS_TARGET_INTERP_VELOCITY_DEG := 800.0
const ALS_TARGET_INTERP_LOOKING_DEG := 500.0
## ALSBaseCharacter.cpp::CalculateGroundedRotationRate is
## `RotationRateCurve(mapped speed) * GetMappedRangeValueClamped({0, 300},
## {1, 3}, AimYawRate)`. The curve half needs a per-character asset we don't
## have (ROTATION_SPEED above stands in for it), but the aim-yaw-rate half is
## a genuine portable number: the body rotates up to 3x faster while the
## camera is being spun quickly, so fast camera whips feel responsive without
## making slow ones twitchy.
const ALS_AIM_YAW_RATE_RANGE_DEG := 300.0
const ALS_AIM_YAW_RATE_MULT_MIN := 1.0
const ALS_AIM_YAW_RATE_MULT_MAX := 3.0
## ALSBaseCharacter.cpp's bCanUpdateMovingRot gate: Velocity Direction mode
## only updates rotation while moving-with-input OR Speed > 150 cm/s (1.5
## m/s) - real ALS doesn't rotate on ANY nonzero residual speed the way an
## earlier version of this script assumed.
const ALS_MOVING_ROT_SPEED_THRESHOLD := 1.5
## ALS_CharacterBP's real ThirdPersonFOV class default.
const ALS_THIRD_PERSON_FOV := 90.0
## Real ALS jump/gravity, read live via `obj dump` on `ALS_CharacterBP`'s
## `CharMoveComp` (the component-property tool can't see inherited native
## components by name, same gotcha as `CrouchedHalfHeight`):
## `JumpZVelocity=420` cm/s, `GravityScale=1.0` against UE's standard world
## gravity (980 cm/s² = 9.8 m/s²) - ALS does not override world gravity.
## Previously 6.0/18.0, both invented (and tuned taller per an earlier,
## explicit "make the jump a little higher" request) - real ALS's jump is
## floatier: ~0.43s to apex here vs ~0.33s before, for a similar peak height.
const JUMP_VELOCITY := 4.2
## Vertical-velocity range (m/s) the Airborne blendspace eases across around
## its apex, rather than snapping instantly the moment velocity.y crosses
## zero (what `signf(velocity.y)` did before - a hard -1/0/+1 step, not a
## blend at all). This prototype's own value, tuned so the ease-through
## happens near the top of a normal jump's arc without stretching visibly
## into the launch or landing. Kept proportional after JUMP_VELOCITY was
## ported from an invented 6.0 down to the real 4.2.
const AIR_BLEND_VELOCITY_RANGE := 1.4

## Real UALSCharacterAnimInstance::CalculateAirLeanAmount + UpdateInAirValues'
## FInterpTo of it. The formula: local (forward,right) velocity / 350cm,
## scaled by a fall-speed-keyed curve, interpolated at
## Config.GroundedLeanInterpSpeed=4.0 (real value - ALS reuses its GROUNDED
## lean interp speed for air lean too, there's no separate airborne one).
## LeanInAirAmount is a genuinely non-monotonic authored curve (dips to -0.93
## around -22.5 m/s fall speed before easing back toward 0 at terminal
## velocity) - read live off the real asset and baked exactly below, not
## approximated.
const ALS_LEAN_VELOCITY_DIVISOR := 3.5
const ALS_GROUNDED_LEAN_INTERP_SPEED := 4.0
## This prototype's own value: real ALS applies LeanAmount as a blend toward
## authored lean-pose clips via the AnimGraph, which we don't have retargeted
## (same situation as turn-in-place's 90/180 clips). Applied here instead as a
## direct tilt of the whole character node, scaled to this angle at
## LeanAmount's typical extremes (~1.0) - a procedural stand-in for the real
## blendspace, not a byte-for-byte port of its consumer.
const LEAN_MAX_ANGLE_DEG := 15.0

## Real UALSCharacterAnimInstance::CalculateLandPrediction. Fall-speed cutoff
## -200cm/s (-2.0 m/s - above this, no prediction at all), trace length
## mapped from fall speed over {0,-4000cm/s} -> {50,2000cm} i.e. {0,-40m/s} ->
## {0.5,20m}, converted to metres. The final weight comes from a real,
## authored LandPredictionBlend curve (1 at hit-time-fraction 0, ending 0 at
## fraction 1) - baked exactly below, same as the lean curve.
const ALS_LAND_PREDICTION_FALL_CUTOFF := -2.0
const ALS_LAND_PREDICTION_VELOCITY_RANGE := Vector2(0.0, -40.0)
const ALS_LAND_PREDICTION_TRACE_RANGE := Vector2(0.5, 20.0)
## This prototype's own choice for what land prediction actually DOES: real
## ALS blends toward a landing-recovery pose in the AnimGraph, which needs
## AnimGraph-level access this port doesn't have. Used here instead to fade
## the air lean back toward upright as the ground approaches, which is a
## real (if partial) piece of what "anticipating landing" should look like.
## UALSCharacterAnimInstance::OnJumped's real JumpPlayRate mapping,
## `GetMappedRangeValueClamped({0, 600}, {1.2, 1.5}, Speed)` - a jump taken at
## speed plays its animation faster, so a running jump doesn't read as a
## standing one. 600cm/s in ALS's units.
const ALS_JUMP_PLAY_RATE_SPEED_RANGE := 6.0
const ALS_JUMP_PLAY_RATE_MIN := 1.2
const ALS_JUMP_PLAY_RATE_MAX := 1.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.003

## Real ALS camera values. The algorithm is `ALSPlayerCameraManager.cpp`, but
## every tuning number in it comes from `GetCameraBehaviorParam(name)` - i.e.
## animation CURVES on the Camera_Skeleton rig, which is why reading only the
## C++ would have yielded the structure and none of the values. These were
## read off `ALS_PlayerCameraBehavior`'s own ModifyCurve nodes live: the pin
## defaults carry the numbers, and each node's `CurveNames` array (invisible
## to read_function_graphs, but readable via run_python's inspect_graph_node)
## carries which curve each slot maps to.
## Stored as (forward, right, up) in ALS's own axis order, converted to
## Godot's -Z-forward at point of use. Centimetres -> metres.
const ALS_CAM_VD_OFFSET := Vector3(-3.25, 0.0, 0.20)
const ALS_CAM_VD_PIVOT_LAG := Vector3(5.0, 5.0, 15.0)
const ALS_CAM_VD_PIVOT_OFFSET_Z := 0.30
const ALS_CAM_LD_OFFSET := Vector3(-2.80, 0.70, 0.35)
const ALS_CAM_LD_PIVOT_LAG := Vector3(8.0, 8.0, 15.0)
const ALS_CAM_LD_PIVOT_OFFSET_Z := 0.25
## Each mode has a second PivotOffset_Z, which is the stance variant. Which of
## the pair is standing vs crouching isn't determinable from the node dump
## alone; the larger is taken as crouched, because the pivot target (midpoint
## of Head and root) drops when crouched and a bigger offset lifts the camera
## back toward eye level. Flagged as inference, not a read value.
const ALS_CAM_VD_PIVOT_OFFSET_Z_CROUCH := 0.50
const ALS_CAM_LD_PIVOT_OFFSET_Z_CROUCH := 0.40
## Identical across all three of ALS's camera states.
const ALS_CAM_ROTATION_LAG_SPEED := 20.0
## ALSCharacter::GetThirdPersonTraceParams' real TraceRadius (15cm).
const ALS_CAM_TRACE_RADIUS := 0.15
const ALS_CAM_PITCH_MIN_DEG := -60.0
const ALS_CAM_PITCH_MAX_DEG := 60.0

## ALS's two baseline rotation modes. Velocity Direction: body faces
## whichever way it's actually moving. Looking Direction: body faces the
## camera's forward at all times, independent of move direction - the mode
## that makes strafing (moving sideways/backward while still facing forward)
## actually look right, since Velocity Direction always turns the body to
## face travel.
enum RotationMode { VELOCITY_DIRECTION, LOOKING_DIRECTION }

const FOOT_IK_MODIFIER := preload("res://actors/player/player_foot_ik_modifier.gd")
const SPINE_TWIST_MODIFIER := preload(
		"res://tests/manual/als_locomotion_prototype/prototype_spine_twist_modifier.gd")
const MANTLE_HAND_IK_MODIFIER := preload(
		"res://tests/manual/als_locomotion_prototype/prototype_mantle_hand_ik_modifier.gd")

var _body: CharacterBody3D
var _character: PrototypeBodyFacade
var _anim_player: AnimationPlayer
var _foot_ik_modifier: PlayerFootIKModifier
var _spine_twist_modifier: PrototypeSpineTwistModifier
var _mantle_hand_ik_modifier: PrototypeMantleHandIKModifier
var _skeleton: Skeleton3D
## The camera is NOT parented to the body: ALS's camera manager positions it
## in world space every frame with its own lag, which a parented node can't
## express. _camera_pivot survives purely as the control-rotation holder.
var _camera: Camera3D
var _camera_pitch := 0.0
var _camera_lag_yaw := 0.0
var _camera_lag_pitch := 0.0
var _smoothed_pivot := Vector3.ZERO
var _camera_initialized := false
var _anim_tree: AnimationTree
var _camera_pivot: Node3D
## Consecutive off-floor frames before actually switching the animation to
## Airborne - a plain edge-trigger (switch the instant is_on_floor() goes
## false) read every single stair-step's brief snap gap as a real fall,
## flickering the fall/land animation up an entire flight (confirmed via a
## per-frame automated on_floor-edge test: 8 flicker pairs climbing one
## 8-step flight, one per step). Debouncing the ANIMATION transition only -
## not gravity/is_on_floor() itself, which stay fully reactive for physics -
## fixes the visual flicker without touching how stair-stepping or gravity
## actually work.
const AIRBORNE_DEBOUNCE_FRAMES := 12
var _airborne_frames := 0
var _visually_airborne := false
var _anim_started := false
## ALS_CharacterBP's real `DesiredRotationMode` default, read off its class
## defaults - Looking Direction, not Velocity Direction as this prototype
## assumed. (The same read also confirmed `DesiredGait = Running`, which is
## why RUN_SPEED is the no-modifier gait above.)
var _rotation_mode := RotationMode.LOOKING_DIRECTION
## Mirrors ALSBaseCharacter.cpp's own intermediate "TargetRotation" member -
## real ALS smooths rotation in two stages (see _smooth_character_rotation()),
## not a single lerp straight to the desired yaw.
var _rotation_target_yaw := 0.0
var _mode_label: Label
## ALS's EALSStance. The blend is eased separately from the boolean so the
## pose transitions smoothly while collision/speed switch immediately.
var _is_crouching := false
var _stance_blend := 0.0
var _sprint_blend := 0.0
var _collision_shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _camera_pivot_stand_height := 0.0
var _is_turning := false
## Real ALS TurnInPlaceCheck's ElapsedDelayTime accumulator (see the
## ALS_TURN_CHECK_MIN_ANGLE_DEG doc comment above).
var _turn_check_elapsed := 0.0
## ALSBaseCharacter.cpp caches AimYawRate once per tick as
## `Abs((AimingRotation.Yaw - PreviousAimYaw) / DeltaTime)` - "the speed the
## camera is rotating left to right". Two separate ported systems read it (the
## turn-in-place delay gate and the grounded rotation rate), so like the real
## one it's computed once per physics frame rather than per consumer.
var _aim_yaw_rate_deg := 0.0
var _prev_camera_yaw := 0.0
var _has_prev_camera_yaw := false
var _turn_start_yaw := 0.0
var _turn_delta_yaw := 0.0
var _turn_elapsed := 0.0
var _turn_duration := 0.0
var _is_mantling := false
var _mantle_start_pos := Vector3.ZERO
var _mantle_target_pos := Vector3.ZERO
var _mantle_animated_start_pos := Vector3.ZERO
var _mantle_elapsed := 0.0
var _mantle_duration := 0.0
var _mantle_start_yaw := 0.0
var _mantle_target_yaw := 0.0
## Real ALSMantleComponent PositionCorrectionCurve, one CurveVector per
## mantle TYPE - each holds 3 independent Curve axes (X=PositionAlpha,
## Y=XYCorrectionAlpha, Z=ZCorrectionAlpha). Built once in _build_player().
var _mantle_low_curves: Dictionary
var _mantle_high_curves: Dictionary
var _mantle_active_curves: Dictionary
var _mantle_starting_position := 0.0
var _mantle_play_rate := 1.0
## Real Mantle_Timeline curve: BlendIn ramps 0->1 over the first 0.2s (real
## seconds) then holds at 1.0 - eases the very start of the climb in from the
## player's exact approach pose to avoid a pop, per ALS's own comment on it.
const ALS_MANTLE_BLEND_IN_TIME := 0.2
var _is_landing := false
var _land_elapsed := 0.0
var _land_duration := 0.0
var _land_node: AnimationNodeAnimation
var _last_fall_velocity_y := 0.0
var _lean_amount_lr := 0.0
var _lean_amount_fb := 0.0
var _land_prediction := 0.0
var _lean_in_air_curve: Curve
var _land_prediction_curve: Curve


func _ready() -> void:
	_lean_in_air_curve = _build_lean_in_air_curve()
	_land_prediction_curve = _build_land_prediction_curve()
	_mantle_low_curves = _build_mantle_low_curves()
	_mantle_high_curves = _build_mantle_high_curves()
	_register_walk_action()
	_build_terrain()
	_build_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ALSCharacter::GetThirdPersonPivotTarget: the MIDPOINT of the Head and root
## sockets - not a fixed camera height. That one detail is why crouching needs
## no separate camera rule: the head drops, so the pivot drops with it.
func _third_person_pivot_target() -> Vector3:
	var head_world := _body.global_position + Vector3(0.0, CAPSULE_HEIGHT, 0.0)
	if _skeleton != null:
		var head_idx := _skeleton.find_bone(_character.resolve_bone_name(&"Head"))
		if head_idx >= 0:
			head_world = (
					_skeleton.global_transform * _skeleton.get_bone_global_pose(head_idx)).origin
	# _body.global_position is already the capsule base, i.e. ALS's "root".
	return (head_world + _body.global_position) * 0.5


## UE's FInterpTo: a constant FRACTION of the remaining distance per second,
## clamped so a large delta can't overshoot. Deliberately not an exponential
## smoothing - matching ALS's own curve-tuned feel depends on this exact form.
func _finterp_to(current: float, target: float, speed: float, delta: float) -> float:
	if speed <= 0.0:
		return target
	return current + (target - current) * clampf(delta * speed, 0.0, 1.0)


## Ports AALSPlayerCameraManager::CalculateAxisIndependentLag. The lag is
## applied in the camera's YAW-ONLY frame (ALS explicitly zeroes roll and
## pitch first), so looking up or down never changes which way the camera
## lags - that separation is the whole trick, and it's why ALS can afford a
## much slower vertical lag (15) than horizontal (5) without it feeling odd.
func _axis_independent_lag(
		current: Vector3, target: Vector3, camera_yaw: float,
		lag_forward: float, lag_right: float, lag_up: float, delta: float) -> Vector3:
	var yaw_basis := Basis(Vector3.UP, camera_yaw)
	var cur := yaw_basis.inverse() * current
	var tgt := yaw_basis.inverse() * target
	return yaw_basis * Vector3(
			_finterp_to(cur.x, tgt.x, lag_right, delta),
			_finterp_to(cur.y, tgt.y, lag_up, delta),
			_finterp_to(cur.z, tgt.z, lag_forward, delta))


## ALSPlayerCameraManager.cpp step 6: sweep a sphere from the trace origin to
## the wanted camera spot and, on a hit, pull the camera in to where the
## sphere's CENTRE stopped. Functionally a spring arm, but with an origin
## independent of the pivot.
func _camera_collision_pullback(trace_origin: Vector3, target: Vector3) -> Vector3:
	var sphere := SphereShape3D.new()
	sphere.radius = ALS_CAM_TRACE_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), trace_origin)
	params.motion = target - trace_origin
	params.exclude = [_body.get_rid()]
	var fractions := _body.get_world_3d().direct_space_state.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return target
	return trace_origin + (target - trace_origin) * fractions[0]


## Ports AALSPlayerCameraManager::CustomCameraBehavior, step for step.
func _update_camera(delta: float) -> void:
	var looking := _rotation_mode == RotationMode.LOOKING_DIRECTION
	var cam_offset := ALS_CAM_LD_OFFSET if looking else ALS_CAM_VD_OFFSET
	var pivot_lag := ALS_CAM_LD_PIVOT_LAG if looking else ALS_CAM_VD_PIVOT_LAG
	var pivot_offset_z: float
	if looking:
		pivot_offset_z = (
				ALS_CAM_LD_PIVOT_OFFSET_Z_CROUCH if _is_crouching
				else ALS_CAM_LD_PIVOT_OFFSET_Z)
	else:
		pivot_offset_z = (
				ALS_CAM_VD_PIVOT_OFFSET_Z_CROUCH if _is_crouching
				else ALS_CAM_VD_PIVOT_OFFSET_Z)

	var pivot_target := _third_person_pivot_target()
	if not _camera_initialized:
		# ALS seeds SmoothedPivotTarget on possession; without this the camera
		# lags in from the world origin on the first frame.
		_smoothed_pivot = pivot_target
		_camera_lag_yaw = _camera_pivot.rotation.y
		_camera_lag_pitch = _camera_pitch
		_camera_initialized = true

	# Step 2: target rotation chases the control rotation with its own lag.
	var rot_alpha := clampf(delta * ALS_CAM_ROTATION_LAG_SPEED, 0.0, 1.0)
	_camera_lag_yaw = lerp_angle(_camera_lag_yaw, _camera_pivot.rotation.y, rot_alpha)
	_camera_lag_pitch = lerp_angle(_camera_lag_pitch, _camera_pitch, rot_alpha)

	# Step 3: smoothed pivot, via axis-independent lag.
	_smoothed_pivot = _axis_independent_lag(
			_smoothed_pivot, pivot_target, _camera_lag_yaw,
			pivot_lag.x, pivot_lag.y, pivot_lag.z, delta)

	# Step 4: PivotOffset_X/Y are 0 in every ALS camera state, so only the
	# vertical offset actually contributes here.
	var pivot_location := _smoothed_pivot + Vector3.UP * pivot_offset_z

	# Step 5: camera-relative offsets. ALS's (X fwd, Y right, Z up) becomes
	# Godot's (X right, Y up, -Z fwd).
	var cam_basis := Basis.from_euler(Vector3(_camera_lag_pitch, _camera_lag_yaw, 0.0))
	var target_location := pivot_location + cam_basis * Vector3(
			cam_offset.y, cam_offset.z, -cam_offset.x)

	# Step 6: pull in if something is between the character and the camera.
	# ALS traces from a shoulder socket (TP_CameraTrace_R/L); this rig has no
	# such socket, so the pivot stands in - documented substitution.
	_camera.global_position = _camera_collision_pullback(pivot_location, target_location)
	_camera.global_rotation = Vector3(_camera_lag_pitch, _camera_lag_yaw, 0.0)


## Ports UALSCharacterAnimInstance::CalculateAirLeanAmount + its FInterpTo in
## UpdateInAirValues, and CalculateLandPrediction, applying both to the whole
## character node as a procedural tilt (see the const doc comments above for
## what's real vs. this prototype's own choice of application).
func _update_air_lean_and_land_prediction(delta: float) -> void:
	var target_lr := 0.0
	var target_fb := 0.0
	if not _body.is_on_floor():
		# UnrotateVector(Velocity)/350 in real ALS, restricted to the X
		# (forward)/Y (right) components - equivalent to using horizontal
		# velocity directly under a pure-yaw rotation, since Z can't leak into
		# X/Y that way. local.x is this project's own established "right",
		# -local.z its "forward" (see the Grounded blendspace above).
		var local: Vector3 = (
				_character.transform.basis.inverse()
				* Vector3(_body.velocity.x, 0.0, _body.velocity.z) / ALS_LEAN_VELOCITY_DIVISOR)
		var curve_val := _lean_in_air_curve.sample(_body.velocity.y)
		target_lr = local.x * curve_val
		target_fb = -local.z * curve_val
		_land_prediction = _calculate_land_prediction()
	else:
		_land_prediction = 0.0
	var interp_alpha := clampf(delta * ALS_GROUNDED_LEAN_INTERP_SPEED, 0.0, 1.0)
	_lean_amount_lr = lerpf(_lean_amount_lr, target_lr, interp_alpha)
	_lean_amount_fb = lerpf(_lean_amount_fb, target_fb, interp_alpha)
	# Land prediction fades the lean back toward upright as the ground
	# approaches - see ALS_LAND_PREDICTION_TRACE_RANGE's doc comment above for
	# why this particular use, rather than a direct AnimGraph port.
	var landing_fade := 1.0 - _land_prediction
	_character.rotation.z = deg_to_rad(-_lean_amount_lr * LEAN_MAX_ANGLE_DEG * landing_fade)
	_character.rotation.x = deg_to_rad(_lean_amount_fb * LEAN_MAX_ANGLE_DEG * landing_fade)


## Ports UALSCharacterAnimInstance::OnJumped's JumpPlayRate. Set once at the
## moment of jumping, exactly as ALS does, rather than tracked continuously -
## the rate reflects the speed the jump was launched at, not current speed.
func _apply_jump_play_rate() -> void:
	var speed := Vector3(_body.velocity.x, 0.0, _body.velocity.z).length()
	_anim_tree.set(&"parameters/Airborne/JumpTimeScale/scale", remap(
			clampf(speed, 0.0, ALS_JUMP_PLAY_RATE_SPEED_RANGE),
			0.0, ALS_JUMP_PLAY_RATE_SPEED_RANGE,
			ALS_JUMP_PLAY_RATE_MIN, ALS_JUMP_PLAY_RATE_MAX))


## ALS's real LeanInAirAmount CurveFloat, read live via run_python's
## inspect_asset (FloatCurve keys) and reproduced exactly: Time in ALS's
## centimetres/second converted to this project's m/s (÷100), Value and
## tangents unitless so carried over unchanged. Non-monotonic by design -
## this is the authored ALS asset, not smoothed or simplified.
func _build_lean_in_air_curve() -> Curve:
	var curve := Curve.new()
	# Godot's Curve resource defaults BOTH its X domain and its Y value range
	# to [0,1], clamping anything outside either at add-time with no error -
	# this curve needs both widened before adding points: X to the curve's
	# real fall-speed range, Y because the authored curve genuinely dips
	# negative (down to -0.93).
	curve.min_domain = -40.0
	curve.max_domain = 0.0
	curve.min_value = -1.0
	curve.max_value = 1.0
	curve.add_point(Vector2(-40.0, 0.0))
	curve.add_point(Vector2(-32.77683, -0.122851), -0.0533, -0.0533)
	curve.add_point(Vector2(-22.51931, -0.932240), -0.0466, -0.0466)
	curve.add_point(Vector2(-12.47549, -0.794192), 0.0858, 0.0858)
	curve.add_point(Vector2(0.0, 1.0))
	return curve


## ALS's real Mantle_1m PositionCorrectionCurve (a CurveVector - 3
## independent axes), read live via `obj dump` + log grep (run_python's
## inspect_asset only surfaced axis 0 for a CurveVector's fixed-size
## FloatCurves[3] array). Domain is already within [0,1] for this asset - no
## Curve.min_domain/min_value widening needed, unlike the lean curve.
func _build_mantle_low_curves() -> Dictionary:
	var pos_alpha := Curve.new()
	pos_alpha.add_point(Vector2(0.0, 0.0))
	pos_alpha.add_point(Vector2(0.3, 0.0))
	pos_alpha.add_point(Vector2(0.7, 1.0))
	pos_alpha.add_point(Vector2(1.0, 1.0))
	var xy_alpha := Curve.new()
	xy_alpha.add_point(Vector2(0.1, 0.0))
	xy_alpha.add_point(Vector2(0.4, 1.0))
	var z_alpha := Curve.new()
	z_alpha.add_point(Vector2(0.3, 0.0))
	z_alpha.add_point(Vector2(0.6, 1.0))
	return {"pos_alpha": pos_alpha, "xy_alpha": xy_alpha, "z_alpha": z_alpha, "max_time": 1.0}


## ALS's real Mantle_2m PositionCorrectionCurve - a longer climb, so its real
## domain extends to 2.1 (seconds), not [0,1] like Mantle_1m. Sampled by
## real elapsed seconds directly (matching real ALS's
## `MantleTimeline->GetPlaybackPosition()`, itself in seconds), not a
## normalized 0-1 progress fraction - this needs its own real max_time
## rather than assuming both curves share one duration convention.
func _build_mantle_high_curves() -> Dictionary:
	var pos_alpha := Curve.new()
	pos_alpha.min_domain = 0.0
	pos_alpha.max_domain = 2.1
	pos_alpha.add_point(Vector2(0.0, 0.0))
	pos_alpha.add_point(Vector2(0.333, 0.0))
	pos_alpha.add_point(Vector2(1.0, 1.0))
	pos_alpha.add_point(Vector2(2.1, 1.0))
	var xy_alpha := Curve.new()
	xy_alpha.min_domain = 0.0
	xy_alpha.max_domain = 2.1
	xy_alpha.add_point(Vector2(0.0, 0.0))
	xy_alpha.add_point(Vector2(0.3, 1.0))
	var z_alpha := Curve.new()
	z_alpha.min_domain = 0.0
	z_alpha.max_domain = 2.1
	z_alpha.add_point(Vector2(0.0, 0.0))
	z_alpha.add_point(Vector2(0.333, 0.0))
	z_alpha.add_point(Vector2(0.7, 1.0))
	return {"pos_alpha": pos_alpha, "xy_alpha": xy_alpha, "z_alpha": z_alpha, "max_time": 2.1}


## ALS's real LandPredictionBlend CurveFloat, same live-read technique.
## Domain is a 0-1 sweep-hit fraction (unitless, no conversion needed):
## 1.0 at fraction 0 (about to land) easing to 0.0 at fraction 1 (barely
## found ground at the very end of the trace).
func _build_land_prediction_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0), 0.0, -2.066087)
	curve.add_point(Vector2(1.0, 0.0), -2.066088, 0.0)
	return curve


## Ports UALSCharacterAnimInstance::CalculateLandPrediction. Sweeps a capsule
## straight down along the (clamped) fall velocity direction from the body's
## current position; the real function's "HitResult.Time" (fraction along
## the sweep where a walkable surface was found) is exactly what
## cast_motion()'s safe fraction already gives us. Returns 0 if not falling
## fast enough to bother, or if the sweep finds nothing walkable in range.
func _calculate_land_prediction() -> float:
	if _body.velocity.y >= ALS_LAND_PREDICTION_FALL_CUTOFF:
		return 0.0
	var trace_length := remap(
			clampf(_body.velocity.y,
					ALS_LAND_PREDICTION_VELOCITY_RANGE.y, ALS_LAND_PREDICTION_VELOCITY_RANGE.x),
			ALS_LAND_PREDICTION_VELOCITY_RANGE.x, ALS_LAND_PREDICTION_VELOCITY_RANGE.y,
			ALS_LAND_PREDICTION_TRACE_RANGE.x, ALS_LAND_PREDICTION_TRACE_RANGE.y)
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	var start := _capsule_location_from_base(_body.global_position, 0.0)
	params.transform = Transform3D(Basis(), start)
	params.motion = Vector3(0.0, -trace_length, 0.0)
	params.exclude = [_body.get_rid()]
	var fractions := _body.get_world_3d().direct_space_state.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return 0.0
	return _land_prediction_curve.sample(fractions[0])


func _register_walk_action() -> void:
	for entry in [[WALK_ACTION, KEY_ALT], [CROUCH_ACTION, KEY_CTRL]]:
		var action: StringName = entry[0]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = entry[1]
		InputMap.action_add_event(action, key)


## Crouch/stand toggle. Standing back up is gated on ALS's own
## CapsuleHasRoomCheck at the STANDING capsule height - the exact thing that
## check exists for in real ALS - so the character can't stand up inside a
## low overhang. Crouching down is never blocked.
func _set_crouching(crouching: bool) -> void:
	if crouching == _is_crouching:
		return
	if not crouching:
		var stand_centre := _capsule_location_from_base(
				_body.global_position, ALS_MANTLE_CAPSULE_Z_OFFSET)
		if not _capsule_has_room(stand_centre):
			return
	_is_crouching = crouching
	var height := CROUCH_CAPSULE_HEIGHT if crouching else CAPSULE_HEIGHT
	_capsule.height = height
	# The shape is bottom-anchored (body origin is at the feet), so its centre
	# offset has to follow the height change or the capsule would shrink
	# around its middle and leave the feet floating.
	_collision_shape.position.y = height * 0.5
	# No camera adjustment here any more: since the ALS camera port, the pivot
	# target is the midpoint of the Head and root sockets, so it drops with
	# the crouching character on its own - which is exactly how real ALS
	# avoids needing a crouch-specific camera rule.
	_update_mode_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		_camera_pivot.rotation.y -= motion.x * MOUSE_SENSITIVITY
		# Pitch is new with the ALS camera port - the previous orbit cam was
		# yaw-only, so there was no control pitch for it to chase.
		_camera_pitch = clampf(
				_camera_pitch - motion.y * MOUSE_SENSITIVITY,
				deg_to_rad(ALS_CAM_PITCH_MIN_DEG), deg_to_rad(ALS_CAM_PITCH_MAX_DEG))
	elif event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			Input.mouse_mode = (
					Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
					else Input.MOUSE_MODE_CAPTURED)
		elif key == KEY_G:
			_rotation_mode = (
					RotationMode.LOOKING_DIRECTION if _rotation_mode == RotationMode.VELOCITY_DIRECTION
					else RotationMode.VELOCITY_DIRECTION)
			_update_mode_label()
