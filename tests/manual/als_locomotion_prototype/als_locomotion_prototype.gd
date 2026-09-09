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
	&"walk_f": ["res://assets/models/als_retarget_test/ALS_N_Walk_F_on_ybot.res", Vector2(0.0, 1.0), WALK_SPEED],
	&"walk_b": ["res://assets/models/als_retarget_test/ALS_N_Walk_B_on_ybot.res", Vector2(0.0, -1.0), WALK_SPEED],
	&"walk_lf": ["res://assets/models/als_retarget_test/ALS_N_Walk_LF_on_ybot.res", Vector2(-0.707, 0.707), WALK_SPEED],
	&"walk_rf": ["res://assets/models/als_retarget_test/ALS_N_Walk_RF_on_ybot.res", Vector2(0.707, 0.707), WALK_SPEED],
	&"walk_lb": ["res://assets/models/als_retarget_test/ALS_N_Walk_LB_on_ybot.res", Vector2(-0.707, -0.707), WALK_SPEED],
	&"walk_rb": ["res://assets/models/als_retarget_test/ALS_N_Walk_RB_on_ybot.res", Vector2(0.707, -0.707), WALK_SPEED],
	&"run_f": ["res://assets/models/als_retarget_test/ALS_N_Run_F_on_ybot.res", Vector2(0.0, 1.0), RUN_SPEED],
	&"run_b": ["res://assets/models/als_retarget_test/ALS_N_Run_B_on_ybot.res", Vector2(0.0, -1.0), RUN_SPEED],
	&"run_lf": ["res://assets/models/als_retarget_test/ALS_N_Run_LF_on_ybot.res", Vector2(-0.707, 0.707), RUN_SPEED],
	&"run_rf": ["res://assets/models/als_retarget_test/ALS_N_Run_RF_on_ybot.res", Vector2(0.707, 0.707), RUN_SPEED],
	&"run_lb": ["res://assets/models/als_retarget_test/ALS_N_Run_LB_on_ybot.res", Vector2(-0.707, -0.707), RUN_SPEED],
	&"run_rb": ["res://assets/models/als_retarget_test/ALS_N_Run_RB_on_ybot.res", Vector2(0.707, -0.707), RUN_SPEED],
}
## ALS's crouch locomotion set is 4-point - pure F/B/L/R strafes, with NO
## diagonal clips, unlike the 6-point radial standing set above. Retargeted
## from ALS_CLF_Walk_* onto Y Bot. `ALS_CLF_Pose` is the crouched idle (a
## single-frame pose, hence its ~0.03s length).
## clip_name -> [source .res path, (right, forward) direction unit vector].
const CROUCH_ANIMATIONS := {
	&"crouch_f": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_F_on_ybot.res", Vector2(0.0, 1.0)],
	&"crouch_b": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_B_on_ybot.res", Vector2(0.0, -1.0)],
	&"crouch_l": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_L_on_ybot.res", Vector2(-1.0, 0.0)],
	&"crouch_r": ["res://assets/models/als_retarget_test/ALS_CLF_Walk_R_on_ybot.res", Vector2(1.0, 0.0)],
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
	&"turn_l90": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_L90_on_ybot.res", &"TurnL90", -90.0],
	&"turn_r90": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_R90_on_ybot.res", &"TurnR90", 90.0],
	&"turn_l180": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_L180_on_ybot.res", &"TurnL180", -180.0],
	&"turn_r180": ["res://assets/models/als_retarget_test/ALS_N_TurnIP_R180_on_ybot.res", &"TurnR180", 180.0],
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


func _build_player() -> void:
	_body = CharacterBody3D.new()
	_body.name = &"PrototypeBody"
	_body.position = Vector3(0.0, 1.0, 8.0)
	# Wider than STAIR_STEP_HEIGHT so move_and_slide() reliably re-acquires
	# the floor the same frame after _apply_stair_step_up() lifts the body -
	# the default (0.1) left a 1-frame is_on_floor()=false gap on every
	# single stair step, which the Grounded/Airborne/Landing state machine
	# read as a real fall, flickering the fall/landing animation up an
	# entire flight instead of a smooth walk (confirmed by live user report).
	_body.floor_snap_length = STAIR_STEP_HEIGHT + 0.1

	var shape := CollisionShape3D.new()
	_collision_shape = shape
	var capsule := CapsuleShape3D.new()
	_capsule = capsule
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	_body.add_child(shape)

	# _character is the LOGICAL facing node every rotation-mode/turn-in-place
	# calculation manipulates - kept as a bare wrapper, separate from the
	# instantiated mesh, because the mesh's own visual front turned out not to
	# match what a bone-position-based facing probe reported (confirmed wrong
	# by direct user observation after the probe said otherwise - see
	# AGENT_TASKS/016's status notes). Correcting the offset here, on the
	# purely-visual child, means every rotation formula above stays the
	# textbook-correct Godot -Z convention with no compensating fudge baked
	# into the movement/camera/turn math itself.
	_character = PrototypeBodyFacade.new()
	_character.name = &"CharacterFacing"
	_body.add_child(_character)
	var visual := (load(CHARACTER_MODEL) as PackedScene).instantiate()
	visual.rotation.y = PI
	_character.add_child(visual)
	_character.character = visual
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false)
	_skeleton = skeleton
	_anim_player = _character.find_child("AnimationPlayer", true, false)
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = &"AnimationPlayer"
		_character.add_child(_anim_player)
	_character.anim_player = _anim_player
	# Track paths resolve relative to root_node (the character's own parent
	# here), not to the AnimationPlayer itself - see 015/016 retarget notes.
	_anim_player.root_node = _anim_player.get_path_to(skeleton.get_parent())
	var anim_root: Node = _anim_player.get_node(_anim_player.root_node)
	var skeleton_path := anim_root.get_path_to(skeleton)

	# Same auto-detect PlayerBody._detect_target_humanoid_map() falls back to
	# for a character with no characters/*.json catalog entry - needed here so
	# PlayerFootIKModifier.resolve_bone_name() (via the facade) can map its
	# canonical leg-bone roles (LeftUpLeg/LeftLeg/LeftFoot/...) onto Y Bot's
	# real mixamorig_-prefixed bone names.
	var prefix = HumanoidRetargeter.detect_bone_prefix(skeleton)
	_character._target_humanoid_map = (
			CharacterEditorRigHandler.auto_map(skeleton) if prefix == null or prefix == "B-"
			else CharacterEditorRigHandler.full_map_from_prefix(skeleton, prefix))

	var lib := AnimationLibrary.new()
	for entry in [[&"idle", IDLE_ANIMATION], [&"jump", JUMP_ANIMATION], [&"fall", FALL_ANIMATION]]:
		var anim: Animation = (load(entry[1]) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(entry[0], anim)
	for clip_name: StringName in DIRECTIONAL_ANIMATIONS:
		var dir_info: Array = DIRECTIONAL_ANIMATIONS[clip_name]
		var anim: Animation = (load(String(dir_info[0])) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
	for clip_name: StringName in CROUCH_ANIMATIONS:
		var crouch_info: Array = CROUCH_ANIMATIONS[clip_name]
		var anim: Animation = (load(String(crouch_info[0])) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
	var crouch_idle: Animation = (load(CROUCH_IDLE_ANIMATION) as Animation).duplicate()
	crouch_idle.loop_mode = Animation.LOOP_LINEAR
	_retarget_track_paths(crouch_idle, skeleton_path)
	lib.add_animation(&"crouch_idle", crouch_idle)
	var sprint_anim: Animation = (load(SPRINT_ANIMATION) as Animation).duplicate()
	sprint_anim.loop_mode = Animation.LOOP_LINEAR
	_retarget_track_paths(sprint_anim, skeleton_path)
	lib.add_animation(&"sprint", sprint_anim)
	for entry in [[&"mantle_low", MANTLE_LOW_ANIMATION], [&"mantle_high", MANTLE_HIGH_ANIMATION]]:
		var mantle_anim: Animation = (load(entry[1]) as Animation).duplicate()
		mantle_anim.loop_mode = Animation.LOOP_NONE
		_retarget_track_paths(mantle_anim, skeleton_path)
		lib.add_animation(entry[0], mantle_anim)
	for entry in [[&"land_light", LAND_LIGHT_ANIMATION], [&"land_heavy", LAND_HEAVY_ANIMATION]]:
		var land_anim: Animation = (load(entry[1]) as Animation).duplicate()
		land_anim.loop_mode = Animation.LOOP_NONE
		_retarget_track_paths(land_anim, skeleton_path)
		lib.add_animation(entry[0], land_anim)
	for clip_name: StringName in TURN_ANIMATIONS:
		var turn_info: Array = TURN_ANIMATIONS[clip_name]
		var anim: Animation = (load(String(turn_info[0])) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_NONE
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
	_anim_player.add_animation_library(&"clips", lib)

	# Grounded: 2D directional blendspace (real ALS technique) - idle at the
	# origin, a walk-speed ring of 6 directional clips, and a run-speed ring
	# of the same 6 directions at a larger radius. Godot 4.6's
	# AnimationNodeBlendSpace2D only has Interpolated/Discrete/Carry modes -
	# no separate "Directional" mode like some other engines (confirmed via
	# property-list introspection, not assumed) - but the default
	# Interpolated mode already does a Delaunay-triangulation blend between
	# the nearest enclosing points, which is exactly the technique needed here.
	var ground_blend := AnimationNodeBlendSpace2D.new()
	ground_blend.min_space = Vector2(-SPRINT_SPEED, -SPRINT_SPEED)
	ground_blend.max_space = Vector2(SPRINT_SPEED, SPRINT_SPEED)
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"clips/idle"
	ground_blend.add_blend_point(idle_node, Vector2.ZERO)
	for clip_name: StringName in DIRECTIONAL_ANIMATIONS:
		var dir_info: Array = DIRECTIONAL_ANIMATIONS[clip_name]
		var dir_node := AnimationNodeAnimation.new()
		dir_node.animation = StringName("clips/" + String(clip_name))
		var direction: Vector2 = dir_info[1]
		var speed: float = dir_info[2]
		ground_blend.add_blend_point(dir_node, direction * speed)

	# Crouch: its own 4-point blendspace (ALS's crouch set has no diagonals),
	# rings at the crouch gait speeds rather than the standing ones.
	var crouch_blend := AnimationNodeBlendSpace2D.new()
	crouch_blend.min_space = Vector2(-CROUCH_SPRINT_SPEED, -CROUCH_SPRINT_SPEED)
	crouch_blend.max_space = Vector2(CROUCH_SPRINT_SPEED, CROUCH_SPRINT_SPEED)
	var crouch_idle_node := AnimationNodeAnimation.new()
	crouch_idle_node.animation = &"clips/crouch_idle"
	crouch_blend.add_blend_point(crouch_idle_node, Vector2.ZERO)
	for clip_name: StringName in CROUCH_ANIMATIONS:
		var crouch_info: Array = CROUCH_ANIMATIONS[clip_name]
		var crouch_node := AnimationNodeAnimation.new()
		crouch_node.animation = StringName("clips/" + String(clip_name))
		crouch_blend.add_blend_point(crouch_node, (crouch_info[1] as Vector2) * CROUCH_RUN_SPEED)

	# Stance is a Blend2 INSIDE the Grounded state rather than a sibling state.
	# Real ALS does use separate (N) Standing / (CLF) Crouching states, but it
	# also curve-blends between the two base poses; a Blend2 gets the same
	# visual result here while leaving every existing playback.travel(
	# &"Grounded") call - turn-in-place, landing, mantle exits - working
	# untouched, which a new sibling state would have silently broken.
	var ground_tree := AnimationNodeBlendTree.new()
	ground_tree.add_node(&"StandBlend", ground_blend)
	ground_tree.add_node(&"CrouchBlend", crouch_blend)
	var stance_blend := AnimationNodeBlend2.new()
	stance_blend.sync = true
	ground_tree.add_node(&"StanceBlend", stance_blend)
	# Sprint layers over the standing blendspace before stance is applied, so
	# crouching still wins over it (ALS has no crouched sprint clip either).
	var sprint_node := AnimationNodeAnimation.new()
	sprint_node.animation = &"clips/sprint"
	ground_tree.add_node(&"SprintClip", sprint_node)
	var sprint_blend := AnimationNodeBlend2.new()
	# Synchronised: run is a 0.8s cycle and sprint a 0.6s one, so without this
	# Godot advances them independently and they drift out of phase - blending
	# two locomotion cycles at opposite phases puts one arm forward and the
	# other back at the same time, which reads exactly as "the arms cross".
	sprint_blend.sync = true
	ground_tree.add_node(&"SprintBlend", sprint_blend)
	ground_tree.connect_node(&"SprintBlend", 0, &"StandBlend")
	ground_tree.connect_node(&"SprintBlend", 1, &"SprintClip")
	ground_tree.connect_node(&"StanceBlend", 0, &"SprintBlend")
	ground_tree.connect_node(&"StanceBlend", 1, &"CrouchBlend")
	# Same trick as the Airborne branch: Godot has no per-state play rate, and
	# ALS's whole sprint presentation is the run cycle played faster
	# (CalculateStandingPlayRate) rather than a separate clip set.
	var ground_time_scale := AnimationNodeTimeScale.new()
	ground_tree.add_node(&"GroundTimeScale", ground_time_scale)
	ground_tree.connect_node(&"GroundTimeScale", 0, &"StanceBlend")
	ground_tree.connect_node(&"output", 0, &"GroundTimeScale")

	# Airborne: 1D blendspace keyed by vertical velocity - fall loop while
	# descending, jump loop while still rising. min/max are a real velocity
	# RANGE (m/s), not a normalized -1..1 pair: the blend position fed in
	# is clamped raw velocity.y (see _physics_process), so this genuinely
	# eases through zero at the arc's apex instead of the two clips ever
	# being weighted 50/50 by construction.
	var air_blend := AnimationNodeBlendSpace1D.new()
	air_blend.min_space = -AIR_BLEND_VELOCITY_RANGE
	air_blend.max_space = AIR_BLEND_VELOCITY_RANGE
	var fall_node := AnimationNodeAnimation.new()
	fall_node.animation = &"clips/fall"
	var jump_node := AnimationNodeAnimation.new()
	jump_node.animation = &"clips/jump"
	air_blend.add_blend_point(fall_node, -AIR_BLEND_VELOCITY_RANGE)
	air_blend.add_blend_point(jump_node, AIR_BLEND_VELOCITY_RANGE)

	# The Airborne state is a blend tree rather than the bare blendspace, only
	# so an AnimationNodeTimeScale can sit between it and the output: Godot has
	# no per-state play rate, and real ALS scales the jump animation by
	# OnJumped's JumpPlayRate. Driven via
	# "parameters/Airborne/JumpTimeScale/scale" (see _apply_jump_play_rate).
	var air_tree := AnimationNodeBlendTree.new()
	air_tree.add_node(&"AirBlend", air_blend)
	var air_time_scale := AnimationNodeTimeScale.new()
	air_tree.add_node(&"JumpTimeScale", air_time_scale)
	air_tree.connect_node(&"JumpTimeScale", 0, &"AirBlend")
	air_tree.connect_node(&"output", 0, &"JumpTimeScale")

	# Grounded <-> Airborne, switched explicitly via playback.travel() on
	# is_on_floor() transitions (see _physics_process) rather than an
	# advance_condition, since the trigger is a one-frame edge, not a
	# continuously-true condition.
	var state_machine := AnimationNodeStateMachine.new()
	state_machine.add_node(&"Grounded", ground_tree)
	state_machine.add_node(&"Airborne", air_tree)
	var to_air := AnimationNodeStateMachineTransition.new()
	to_air.xfade_time = 0.15
	to_air.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Grounded", &"Airborne", to_air)
	var to_ground := AnimationNodeStateMachineTransition.new()
	to_ground.xfade_time = 0.2
	to_ground.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Airborne", &"Grounded", to_ground)

	# Landing: one-shot ALS_N_Land_Light played on a genuine Airborne->Grounded
	# landing edge (see _physics_process), instead of the plain Airborne->
	# Grounded crossfade above (kept as a fallback for other paths, e.g. the
	# very first frame's forced start()). Which clip plays (light vs heavy) is
	# picked by fall speed at trigger time - _land_node.animation is swapped
	# right before travel(&"Landing"), see LAND_HEAVY_SPEED_THRESHOLD.
	_land_node = AnimationNodeAnimation.new()
	_land_node.animation = &"clips/land_light"
	state_machine.add_node(&"Landing", _land_node)
	var to_landing := AnimationNodeStateMachineTransition.new()
	to_landing.xfade_time = 0.1
	to_landing.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Airborne", &"Landing", to_landing)
	var from_landing := AnimationNodeStateMachineTransition.new()
	from_landing.xfade_time = 0.2
	from_landing.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Landing", &"Grounded", from_landing)

	# Mantle: one-shot, can start from either Grounded or Airborne (a running
	# jump toward a ledge is airborne at the moment mantle triggers) and
	# always returns to Grounded (mantling always ends standing on solid
	# ground). Two states (Low/High), matching real ALS's Low/High mantle
	# TYPE split (see MANTLE_LOW_ANIMATION/MANTLE_HIGH_ANIMATION doc comment).
	for mantle_state in [&"MantleLow", &"MantleHigh"]:
		var mantle_node := AnimationNodeAnimation.new()
		mantle_node.animation = StringName(
				"clips/mantle_low" if mantle_state == &"MantleLow" else "clips/mantle_high")
		# Wrapped in a blend tree, same reason as Airborne/Grounded: Godot has
		# no per-state play rate, and real ALS's PlayRate is a genuine
		# per-asset constant (1.0 for the 1m asset, 1.2 for the 2m one) it
		# applies to both the montage AND the position-correction timeline.
		var mantle_tree := AnimationNodeBlendTree.new()
		mantle_tree.add_node(&"Clip", mantle_node)
		var mantle_time_scale := AnimationNodeTimeScale.new()
		mantle_tree.add_node(&"PlayRate", mantle_time_scale)
		mantle_tree.connect_node(&"PlayRate", 0, &"Clip")
		mantle_tree.connect_node(&"output", 0, &"PlayRate")
		state_machine.add_node(mantle_state, mantle_tree)
		for from_state in [&"Grounded", &"Airborne"]:
			var to_mantle := AnimationNodeStateMachineTransition.new()
			to_mantle.xfade_time = 0.1
			to_mantle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
			state_machine.add_transition(from_state, mantle_state, to_mantle)
		var from_mantle := AnimationNodeStateMachineTransition.new()
		from_mantle.xfade_time = 0.15
		from_mantle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		state_machine.add_transition(mantle_state, &"Grounded", from_mantle)

	# Turn-in-place states: one per clip, each just Grounded<->TurnXxx (never
	# Airborne<->TurnXxx - turning only triggers while standing on the floor).
	for clip_name: StringName in TURN_ANIMATIONS:
		var turn_node := AnimationNodeAnimation.new()
		turn_node.animation = StringName("clips/" + String(clip_name))
		var state_name: StringName = TURN_ANIMATIONS[clip_name][1]
		state_machine.add_node(state_name, turn_node)
		var to_turn := AnimationNodeStateMachineTransition.new()
		to_turn.xfade_time = 0.15
		to_turn.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		state_machine.add_transition(&"Grounded", state_name, to_turn)
		var from_turn := AnimationNodeStateMachineTransition.new()
		from_turn.xfade_time = 0.15
		from_turn.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		state_machine.add_transition(state_name, &"Grounded", from_turn)

	var anim_tree_root := AnimationTree.new()
	anim_tree_root.name = &"AnimationTree"
	anim_tree_root.tree_root = state_machine
	_character.add_child(anim_tree_root)
	anim_tree_root.anim_player = anim_tree_root.get_path_to(_anim_player)
	anim_tree_root.active = true
	_anim_tree = anim_tree_root

	_camera_pivot = Node3D.new()
	_camera_pivot.name = &"CameraPivot"
	_body.add_child(_camera_pivot)
	_camera_pivot.position = Vector3(0.0, 1.6, 0.0)
	_camera_pivot_stand_height = _camera_pivot.position.y
	var camera := Camera3D.new()
	camera.name = &"Camera3D"
	# ALS_CharacterBP's real ThirdPersonFOV (its FirstPersonFOV is also 90).
	camera.fov = ALS_THIRD_PERSON_FOV
	camera.current = true
	# Added to the SCENE, not to the pivot: _update_camera() writes its world
	# transform every frame, ALS-style. Parenting it would re-apply the body's
	# motion on top of the lag and defeat the whole point.
	add_child(camera)
	_camera = camera

	# _body must already be inside the live scene tree before attaching
	# anything that itself calls add_child() during _ready() (like
	# PlayerFootIKModifier's native-backend setup below) - otherwise Godot
	# refuses with "Parent node is busy setting up children" (confirmed via a
	# headless run, not assumed): the real Player scene never hits this
	# because its whole hierarchy already exists via its own .tscn before
	# _ready() runs anywhere in it, but this prototype builds everything
	# procedurally in one _ready() call, so ordering here actually matters.
	add_child(_body)

	# Stretch goal (AGENT_TASKS/016 Phase 6): reuse the existing Foot IK
	# system rather than fork a second implementation, per the task doc's own
	# instruction. PlayerFootIKModifier only needs 6 members off its
	# player_body (see prototype_body_facade.gd's own header comment for how
	# that was confirmed) - the facade above already satisfies all of them.
	# This runs on top of whatever pose the AnimationTree above produced, as
	# a SkeletonModifier3D (the engine calls it automatically after
	# animation, same as real gameplay).
	_foot_ik_modifier = FOOT_IK_MODIFIER.new() as PlayerFootIKModifier
	_foot_ik_modifier.player_body = _character
	skeleton.add_child(_foot_ik_modifier)

	# Added AFTER the foot IK modifier deliberately: SkeletonModifier3D runs in
	# sibling order, and the spine twist writes absolute global poses. Running
	# it second means it snapshots a pose foot IK has already adjusted, rather
	# than writing a pose foot IK then moves out from under it.
	_spine_twist_modifier = SPINE_TWIST_MODIFIER.new() as PrototypeSpineTwistModifier
	_spine_twist_modifier.player_body = _character
	skeleton.add_child(_spine_twist_modifier)

	_mantle_hand_ik_modifier = MANTLE_HAND_IK_MODIFIER.new() as PrototypeMantleHandIKModifier
	_mantle_hand_ik_modifier.player_body = _character
	skeleton.add_child(_mantle_hand_ik_modifier)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_mode_label = Label.new()
	_mode_label.offset_left = 16.0
	_mode_label.offset_top = 16.0
	layer.add_child(_mode_label)
	_update_mode_label()


func _update_mode_label() -> void:
	var mode_name := (
			"Velocity Direction" if _rotation_mode == RotationMode.VELOCITY_DIRECTION
			else "Looking Direction")
	_mode_label.text = (
			"Rotation mode: %s  |  %s  (G toggles mode, Ctrl crouch, Alt walk, Shift sprint)"
			% [mode_name, "Crouching" if _is_crouching else "Standing"])


## Ports ALSBaseCharacter.cpp::SmoothCharacterRotation exactly: NOT a single
## lerp straight to the desired yaw (what this prototype did before reading
## the real source). Two stages - (1) an internal "TargetRotation" chases the
## desired yaw at a CONSTANT angular speed (RInterpConstantTo, i.e. a hard
## cap on how fast the target itself can move, independent of how far away it
## is), then (2) the actual character rotation exponentially chases that
## TargetRotation (RInterpTo). The result is snappier at first (constant-rate
## catch-up) and eases in at the end (exponential), rather than a single lerp
## which is fastest at the start and slowest at the end regardless of gap size.
func _smooth_character_rotation(
		target_yaw: float, target_interp_speed_deg: float, delta: float) -> void:
	_rotation_target_yaw = rotate_toward(
			_rotation_target_yaw, target_yaw, deg_to_rad(target_interp_speed_deg) * delta)
	# Stage 2's rate is CalculateGroundedRotationRate: the (unportable) speed
	# curve, stood in for by ROTATION_SPEED, times the real aim-yaw-rate
	# multiplier - see ALS_AIM_YAW_RATE_RANGE_DEG.
	var rate_multiplier := remap(
			clampf(_aim_yaw_rate_deg, 0.0, ALS_AIM_YAW_RATE_RANGE_DEG),
			0.0, ALS_AIM_YAW_RATE_RANGE_DEG,
			ALS_AIM_YAW_RATE_MULT_MIN, ALS_AIM_YAW_RATE_MULT_MAX)
	_character.rotation.y = lerp_angle(
			_character.rotation.y, _rotation_target_yaw,
			1.0 - exp(-ROTATION_SPEED * rate_multiplier * delta))


## Ported from UALSCharacterAnimInstance::TurnInPlaceCheck: counts up only
## while the camera has drifted past the threshold AND isn't currently being
## spun fast (a quick camera flick shouldn't commit to a turn), then fires
## once the elapsed time exceeds a delay mapped from the angle. Note the
## mapping direction: GetMappedRangeValueClamped maps the MIN angle (45) to
## MinAngleDelay and 180 to MaxAngleDelay, so a barely-over-threshold angle
## turns almost instantly while a fully-behind one waits up to 0.75s.
## diff_deg is real ALS's AimingValues.AimingAngle.X - the RAW (unsmoothed)
## aim-vs-actor yaw delta, confirmed against UpdateAimingValues; the separate
## SmoothedAimingAngle exists only for aim-offset blending, which this
## prototype has no equivalent of.
func _update_turn_in_place_check(
		delta: float, camera_yaw: float, playback: AnimationNodeStateMachinePlayback) -> void:
	var diff_deg := rad_to_deg(wrapf(camera_yaw - _character.rotation.y, -PI, PI))
	if absf(diff_deg) <= ALS_TURN_CHECK_MIN_ANGLE_DEG or _aim_yaw_rate_deg >= ALS_AIM_YAW_RATE_LIMIT_DEG:
		_turn_check_elapsed = 0.0
		return
	_turn_check_elapsed += delta
	var delay := remap(
			clampf(absf(diff_deg), ALS_TURN_CHECK_MIN_ANGLE_DEG, 180.0),
			ALS_TURN_CHECK_MIN_ANGLE_DEG, 180.0,
			ALS_TURN_MIN_ANGLE_DELAY, ALS_TURN_MAX_ANGLE_DELAY)
	if _turn_check_elapsed > delay:
		_turn_check_elapsed = 0.0
		_maybe_start_turn_in_place(camera_yaw, playback)


## Picks the smallest clip whose magnitude comfortably covers the actual
## angle to turn (a 130 threshold before reaching for one of the four fixed
## clip magnitudes gives the 90 clip room for real angles up to ~130,
## rather than needing exact 90/180 matches).
func _maybe_start_turn_in_place(
		camera_yaw: float, playback: AnimationNodeStateMachinePlayback) -> void:
	var diff := wrapf(camera_yaw - _character.rotation.y, -PI, PI)
	var diff_deg := rad_to_deg(diff)
	if absf(diff_deg) < ALS_TURN_CHECK_MIN_ANGLE_DEG:
		return
	var use_180 := absf(diff_deg) >= TURN_180_THRESHOLD_DEG
	var clip_name := (
			(&"turn_r180" if diff_deg > 0.0 else &"turn_l180") if use_180
			else (&"turn_r90" if diff_deg > 0.0 else &"turn_l90"))
	var turn_info: Array = TURN_ANIMATIONS[clip_name]
	_is_turning = true
	_turn_start_yaw = _character.rotation.y
	_turn_delta_yaw = deg_to_rad(float(turn_info[2]))
	_turn_elapsed = 0.0
	var anim: Animation = _anim_player.get_animation_library(&"clips").get_animation(clip_name)
	_turn_duration = anim.length
	playback.travel(turn_info[1] as StringName)


## Drives _character.rotation.y procedurally over the clip's duration rather
## than reading the retargeted clip's own hip rotation back out - see the
## TURN_ANIMATIONS doc comment for why.
func _update_turn_in_place(delta: float) -> void:
	_turn_elapsed += delta
	var t := clampf(_turn_elapsed / _turn_duration, 0.0, 1.0)
	_character.rotation.y = _turn_start_yaw + _turn_delta_yaw * t
	if t >= 1.0:
		_is_turning = false
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
		playback.travel(&"Grounded")


## Standard CharacterBody3D auto-step recipe: test_move() with the intended
## horizontal motion at the current height; if blocked, retest the same
## motion after lifting the body by STAIR_STEP_HEIGHT. If THAT'S clear, the
## obstruction was a short step (not a real wall) - lift the body and let
## move_and_slide()'s own floor snap settle it back onto the step surface
## right after this call. If still blocked even after lifting, leave it
## alone - too tall to step, correctly still reads as a wall.
## Second attempt's downward-raycast placement was itself broken: the probe
## point was lifted_transform.origin + motion, but `motion` is only THIS
## FRAME'S tiny velocity*delta displacement (millimeters), not remotely far
## enough to have actually reached the step ahead - so the raycast kept
## hitting the flat floor short of the step, snapping the body back down to
## y=0 every frame and leaving move_and_slide() to re-detect the same wall
## on the very next frame. Net effect: completely stuck, confirmed via a
## per-frame trace showing zero net progress in Z OR Y (caught by live user
## report after the "zero flicker" headless check missed it - that check
## only verified on_floor never flickered, not that the character actually
## climbed, and a permanently-stuck-at-the-bottom character trivially also
## never flickers). Back to a plain lift; the animation flicker this was
## trying to avoid is now handled separately, by debouncing the Airborne
## transition instead of trying to make on_floor never blip - see
## _AIRBORNE_DEBOUNCE_FRAMES in _physics_process.
func _apply_stair_step_up(delta: float) -> void:
	if not _body.is_on_floor():
		return
	var horizontal_vel := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if horizontal_vel.length() < 0.1:
		return
	var motion := horizontal_vel * delta
	var base_transform := _body.global_transform
	if not _body.test_move(base_transform, motion):
		return
	var lifted_transform := base_transform
	lifted_transform.origin += Vector3.UP * STAIR_STEP_HEIGHT
	if _body.test_move(lifted_transform, motion):
		return
	_body.global_position.y += STAIR_STEP_HEIGHT


func _update_landing(delta: float) -> void:
	_land_elapsed += delta
	if _land_elapsed >= _land_duration:
		_is_landing = false
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
		playback.travel(&"Grounded")


## Detects a mantleable ledge directly ahead: a wall within
## MANTLE_WALL_CHECK_DISTANCE, and a walkable surface on top of it within
## [MANTLE_MIN_HEIGHT, MANTLE_MAX_HEIGHT] above the body. Starts the mantle
## and returns true if found, otherwise returns false (leaving the caller to
## fall back to a normal jump).
## Ported from UALSMathLibrary::GetCapsuleLocationFromBase - converts a
## base/feet location into the capsule CENTRE that _capsule_has_room() expects.
## Its inverse (GetCapsuleBaseLocation) isn't ported because it has no work to
## do here: this prototype's _body origin already sits at the capsule base (the
## CollisionShape3D carries the +half-height offset), which is exactly what
## real ALS calls the capsule base location.
func _capsule_location_from_base(base_location: Vector3, z_offset: float) -> Vector3:
	var result := base_location
	result.y += CAPSULE_HEIGHT * 0.5 + z_offset
	return result


## Ported from UALSMathLibrary::CapsuleHasRoomCheck - real ALS's actual "can
## the character stand here" test. Sweeps a sphere of the capsule's own radius
## along the capsule's cylindrical segment (half_height - radius, above and
## below the centre), which traces out exactly the capsule's own volume. This
## replaces an invented zero-width downward raycast, which could thread
## straight through a gap the 0.7m-wide body could never actually fit through.
## target_location is the capsule CENTRE, not the feet.
func _capsule_has_room(
		target_location: Vector3, height_offset := 0.0, radius_offset := 0.0) -> bool:
	var half_height_without_hemisphere := CAPSULE_HEIGHT * 0.5 - CAPSULE_RADIUS
	var z_target := half_height_without_hemisphere - radius_offset + height_offset
	var sphere := SphereShape3D.new()
	sphere.radius = CAPSULE_RADIUS + radius_offset
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), target_location + Vector3(0.0, z_target, 0.0))
	params.exclude = [_body.get_rid()]
	var space_state := _body.get_world_3d().direct_space_state

	# Godot's cast_motion is NOT equivalent to Unreal's SweepSingleByChannel:
	# it reports only collisions newly ENTERED during the motion and silently
	# returns [1.0, 1.0] for a shape that already overlaps something at its
	# start position - verified directly, a start position with 4 confirmed
	# intersect_shape overlaps still reported a completely clear sweep. Unreal
	# reports that case as bStartPenetrating, which ALS explicitly checks, so
	# the two halves of ALS's own `!(bBlockingHit || bStartPenetrating)` need
	# two separate Godot queries.
	if not space_state.intersect_shape(params, 1).is_empty():
		return false
	params.motion = Vector3(0.0, -2.0 * z_target, 0.0)
	# [safe_fraction, unsafe_fraction]; safe below 1.0 means the sweep was
	# blocked partway. An empty return is a malformed query - treated
	# conservatively as "no room".
	var result := space_state.cast_motion(params)
	return result.size() >= 1 and result[0] >= 1.0


## Sweeps a sphere from `from` to `to`. ALS's mantle probes are RADIUS traces
## (`ForwardTraceRadius`/`DownwardTraceRadius`, both 30cm on the real
## MantleComponent) rather than the zero-width rays this used before - a thin
## ray slips past a ledge edge that a fat probe catches. Returns {} on no hit,
## else "position"/"normal" keyed the same way intersect_ray's result is, so
## callers read it identically.
func _shape_probe(shape: Shape3D, from: Vector3, to: Vector3) -> Dictionary:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), from)
	params.motion = to - from
	params.exclude = [_body.get_rid()]
	var space_state := _body.get_world_3d().direct_space_state
	var fractions := space_state.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {}
	# Rest info is taken at the UNSAFE fraction - the safe one is by definition
	# the last position that is NOT yet touching, so asking there returns
	# nothing. This also reports the real contact point rather than the sphere
	# centre, which would otherwise overstate a ledge's height by the radius.
	params.transform = Transform3D(Basis(), from + (to - from) * fractions[1])
	params.motion = Vector3.ZERO
	var rest := space_state.get_rest_info(params)
	if rest.is_empty():
		return {}
	return {"position": rest["point"], "normal": rest["normal"]}


## `grounded` picks which of ALS's real trace profiles applies - a standing
## jump-press reaches further and higher than a mantle caught mid-jump.
func _try_start_mantle(grounded: bool) -> bool:
	var min_height := MANTLE_GROUNDED_MIN_HEIGHT if grounded else MANTLE_FALLING_MIN_HEIGHT
	var max_height := MANTLE_GROUNDED_MAX_HEIGHT if grounded else MANTLE_FALLING_MAX_HEIGHT
	var reach := MANTLE_GROUNDED_REACH if grounded else MANTLE_FALLING_REACH
	var facing_dir: Vector3 = -_character.transform.basis.z
	var base := _body.global_position + Vector3(0.0, ALS_MANTLE_CAPSULE_Z_OFFSET, 0.0)

	# Step 1 (ALSMantleComponent.cpp): sweep a tall CAPSULE forward, spanning
	# the entire mantleable height band in one trace, rather than the single
	# low probe this used before - which is why real ALS needs no
	# "probe below the lowest ledge" trick to catch ledges of any height.
	# The start is offset BACKWARD by exactly the trace radius, so the probe's
	# leading surface begins at the body and ReachDistance means real reach
	# rather than reach-plus-a-radius.
	var forward_shape := CapsuleShape3D.new()
	forward_shape.radius = MANTLE_TRACE_RADIUS
	forward_shape.height = 2.0 * (MANTLE_TRACE_HALF_HEIGHT_PAD + (max_height - min_height) * 0.5)
	var trace_start := base - facing_dir * MANTLE_TRACE_RADIUS
	trace_start.y += (max_height + min_height) * 0.5
	var wall_hit := _shape_probe(forward_shape, trace_start, trace_start + facing_dir * reach)
	if wall_hit.is_empty():
		return false
	# ALS rejects a hit it could simply walk up (its IsWalkable check) - a
	# mantle needs a wall, not a ramp.
	if (wall_hit["normal"] as Vector3).y > cos(_body.floor_max_angle):
		return false

	# Step 2: sweep a sphere straight down from above the ledge to foot level,
	# starting from the wall impact point pushed 15cm INTO the surface along
	# its own normal so the probe lands on the ledge top rather than skimming
	# its outer edge.
	var down_shape := SphereShape3D.new()
	down_shape.radius = MANTLE_TRACE_RADIUS
	var down_end: Vector3 = wall_hit["position"]
	down_end.y = base.y
	down_end += (wall_hit["normal"] as Vector3) * -MANTLE_DOWN_TRACE_NORMAL_OFFSET
	var down_start := down_end
	down_start.y += max_height + MANTLE_TRACE_RADIUS + MANTLE_TRACE_HALF_HEIGHT_PAD
	var down_hit := _shape_probe(down_shape, down_start, down_end)
	if down_hit.is_empty():
		return false

	var ledge_top: Vector3 = down_hit["position"]
	var ledge_height := ledge_top.y - _body.global_position.y
	if ledge_height < min_height or ledge_height > max_height:
		return false

	# Real ALS's landing target IS the downward-trace hit point directly
	# (lifted to capsule-centre height) - `TargetTransform`'s position is
	# `CapsuleLocationFBase`, with NO further forward travel added past the
	# trace's own 15cm push-in. This prototype previously added a SECOND,
	# invented 0.5m forward offset on top of that real one - found by
	# actually reading ALSMantleComponent.cpp's Start() function past step 2,
	# prompted by a live user report that the whole body was still visibly
	# clipping through the ledge even after the curve-driven motion was
	# ported. That redundant 0.5m dragged the character nearly 4x deeper
	# across the ledge surface (through more of its volume) than real ALS
	# ever does, which is very plausibly what was actually causing the
	# clipping - not the motion curve, which was already faithfully ported.
	var landing_spot := ledge_top

	# Room check: does the character's whole body actually fit at the landing
	# spot, so a mantle can't pull it up into a low ceiling (ALSMantleComponent.cpp
	# step 3: convert the downward-trace hit into a capsule location with a
	# 2cm lift, then CapsuleHasRoomCheck it).
	if not _capsule_has_room(
			_capsule_location_from_base(landing_spot, ALS_MANTLE_CAPSULE_Z_OFFSET)):
		return false

	_is_mantling = true
	if _mantle_hand_ik_modifier != null:
		_mantle_hand_ik_modifier.weight = 0.0
	_mantle_start_pos = _body.global_position
	_mantle_target_pos = landing_spot
	_mantle_target_pos.y = ledge_top.y
	_body.velocity = Vector3.ZERO
	_mantle_elapsed = 0.0
	# Real ALS's Low/High mantle TYPE split, at the real 125cm threshold
	# (ALSMantleComponent.cpp) - a High ledge plays a visibly different climb.
	var is_high := ledge_height > ALS_MANTLE_HIGH_THRESHOLD
	var clip_name := &"mantle_high" if is_high else &"mantle_low"
	var anim: Animation = _anim_player.get_animation_library(&"clips").get_animation(clip_name)
	var start_offset := ALS_MANTLE_HIGH_START_OFFSET if is_high else ALS_MANTLE_LOW_START_OFFSET
	# Real MantleAnimatedStartOffset: a point behind (start_offset.x) and
	# below (start_offset.y) the ledge, matching where the clip's own root
	# motion actually begins - the early part of the climb tracks toward
	# THIS, not straight from wherever the player happened to approach from.
	_mantle_animated_start_pos = (
			ledge_top - facing_dir * start_offset.x - Vector3.UP * start_offset.y)
	_mantle_active_curves = _mantle_high_curves if is_high else _mantle_low_curves
	var height_range := ALS_MANTLE_HIGH_HEIGHT_RANGE if is_high else ALS_MANTLE_LOW_HEIGHT_RANGE
	var start_pos_range := (
			ALS_MANTLE_HIGH_START_POSITION_RANGE if is_high else ALS_MANTLE_LOW_START_POSITION_RANGE)
	_mantle_starting_position = remap(
			clampf(ledge_height, height_range.x, height_range.y),
			height_range.x, height_range.y, start_pos_range.x, start_pos_range.y)
	_mantle_play_rate = ALS_MANTLE_HIGH_PLAY_RATE if is_high else ALS_MANTLE_LOW_PLAY_RATE
	_anim_tree.set(
			&"parameters/%s/PlayRate/scale" % ("MantleHigh" if is_high else "MantleLow"),
			_mantle_play_rate)
	# Real ALS: MantleTimeline->SetTimelineLength(MaxTime - StartingPosition),
	# then plays it at PlayRate - so the real (unscaled) wall-clock duration
	# is that timeline length divided by PlayRate.
	var max_time: float = _mantle_active_curves["max_time"]
	_mantle_duration = minf(
			anim.length / _mantle_play_rate, (max_time - _mantle_starting_position) / _mantle_play_rate)
	# Face the wall for the duration of the mantle (facing_dir is already the
	# direction cast toward it) rather than leaving whatever yaw the
	# character had on approach, which could be visibly off during a
	# diagonal/running mantle.
	_mantle_start_yaw = _character.rotation.y
	_mantle_target_yaw = atan2(-facing_dir.x, -facing_dir.z)
	var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
	playback.travel(&"MantleHigh" if is_high else &"MantleLow")
	# KNOWN GAP, not silently fixed: real ALS explicitly starts the MONTAGE
	# itself at StartingPosition too (`Montage_Play(..., StartingPosition,
	# ...)`), not just the position-correction curve - a short ledge skips
	# ahead in BOTH together, since they were authored as a matched pair.
	# Tried `_anim_tree.advance(_mantle_starting_position)` right after
	# travel() to fast-forward the freshly-entered state by that offset in
	# one shot - measured directly against sampling the raw Animation
	# resource at the same time, and it does NOT work: the skeleton's pose
	# right after still matches t=0, not the sought time (most likely
	# because travel()'s own crossfade consumes that first advance() call
	# rather than the new state's own internal clock). Left un-seeked rather
	# than ship something that LOOKS like a fix but measurably isn't - only
	# affects the High mantle type (StartingPosition ~0.16s of a 2.2s clip
	# at the test ledge's height; the Low type's own real StartingPosition
	# is 0 at this test ledge's exact height, so this isn't what's causing
	# hand-tracking to look wrong on that one).
	return true


## Ports UALSMantleComponent::MantleUpdate's actual position-correction math
## (steps 2-4 of the real function), not an invented arc. Real ALS blends via
## FTransform algebra in the ledge's own local frame (TransformAdd/Sub); here
## it's done directly in world Cartesian space, which is equivalent for a
## target whose only real rotation component is yaw (matches how this
## prototype already handles mantle facing separately from position).
func _update_mantle(delta: float) -> void:
	_mantle_elapsed += delta
	# Real ALS samples the curve at StartingPosition + GetPlaybackPosition(),
	# where the timeline's own playback position advances at PlayRate x real
	# time - StartingPosition lets a short ledge skip ahead into the curve
	# instead of always playing it from the start, and PlayRate speeds the
	# whole thing up for the 2m asset. Not a normalized 0-1 fraction, which is
	# why Mantle_2m's curve has a real domain out to 2.1, not [0,1].
	var max_time: float = _mantle_active_curves["max_time"]
	var ct := minf(
			_mantle_starting_position + _mantle_elapsed * _mantle_play_rate, max_time)
	var pos_alpha: float = (_mantle_active_curves["pos_alpha"] as Curve).sample(ct)
	var xy_alpha: float = (_mantle_active_curves["xy_alpha"] as Curve).sample(ct)
	var z_alpha: float = (_mantle_active_curves["z_alpha"] as Curve).sample(ct)

	# Step 2: independently blend horizontal (XZ ground-plane) position from
	# the real approach point toward the animation-matched reference using
	# XYCorrectionAlpha, and vertical (Y) using ZCorrectionAlpha - these run
	# on their own real timing (XY arrives faster than Z for Mantle_1m),
	# which is the actual mechanism giving the climb its shape instead of a
	# single uniform lerp.
	var hz := Vector2(_mantle_start_pos.x, _mantle_start_pos.z).lerp(
			Vector2(_mantle_animated_start_pos.x, _mantle_animated_start_pos.z), xy_alpha)
	var vt := lerpf(_mantle_start_pos.y, _mantle_animated_start_pos.y, z_alpha)
	var offset_pos := Vector3(hz.x, vt, hz.y)

	# Step 3: blend the whole offset-based position toward the true final
	# landing spot as PositionAlpha rises - at pos_alpha=1 you're exactly on
	# the ledge, no offset remaining.
	var result := offset_pos.lerp(_mantle_target_pos, pos_alpha)

	# Real MantleTimelineCurve's BlendIn: eases from the player's exact
	# approach pose into the curve-corrected path over the first 0.2s, so a
	# mantle triggered from an off-axis approach doesn't pop.
	var blend_in := clampf(_mantle_elapsed / ALS_MANTLE_BLEND_IN_TIME, 0.0, 1.0)
	_body.global_position = _mantle_start_pos.lerp(result, blend_in)

	_character.rotation.y = lerp_angle(_mantle_start_yaw, _mantle_target_yaw,
			smoothstep(0.0, 1.0, minf(_mantle_elapsed / _mantle_duration * 3.0, 1.0)))

	# Prototype-only hand IK (not a real ALS mechanism - see the modifier's
	# own doc comment for why one is needed here at all): pins both hands to
	# the real ledge grip point while the body is still being corrected
	# toward it (xy/z alpha rising), fading out as pos_alpha commits the body
	# fully onto the ledge - by then the animation should be pushing up to
	# stand, and real climbing hands release the edge at that point too.
	if _mantle_hand_ik_modifier != null:
		_mantle_hand_ik_modifier.target_position = _mantle_target_pos
		_mantle_hand_ik_modifier.weight = maxf(xy_alpha, z_alpha) * (1.0 - pos_alpha) * blend_in

	if _mantle_elapsed >= _mantle_duration:
		_is_mantling = false
		_body.velocity = Vector3.ZERO
		if _mantle_hand_ik_modifier != null:
			_mantle_hand_ik_modifier.weight = 0.0
		# is_on_floor() only reflects the last move_and_slide() call - without
		# this, the frame right after a teleport-style position set would
		# read on_floor()=false (stale) and briefly re-trigger gravity/falling.
		_body.move_and_slide()
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
		playback.travel(&"Grounded")


## Rewrites every track's NodePath to point at new_skeleton_path, keeping each
## track's own bone-name subname intact - same fix als_retarget_preview.gd uses.
func _retarget_track_paths(anim: Animation, new_skeleton_path: NodePath) -> void:
	for t in anim.get_track_count():
		var old_path := anim.track_get_path(t)
		if old_path.get_subname_count() == 0:
			continue
		var bone_name := old_path.get_subname(0)
		anim.track_set_path(t, NodePath(String(new_skeleton_path) + ":" + String(bone_name)))


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if _is_mantling:
		# Fully procedural, like turn-in-place: no gravity/collision movement
		# while mantling, just an interpolated position toward the ledge-top
		# point over the clip's duration.
		_update_mantle(delta)
		return

	var input_dir := Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	input_dir = input_dir.limit_length(1.0)

	if not _body.is_on_floor():
		_body.velocity.y -= GRAVITY * delta
		# Captured here (not read at the landing edge itself) because
		# move_and_slide() zeroes velocity.y back toward 0 the instant it
		# resolves floor contact - by the time on_floor flips true this frame,
		# the real "how fast was I actually falling" value is already gone.
		_last_fall_velocity_y = _body.velocity.y
		# Running/jumping mantle: pressing jump again mid-air (e.g. right after
		# leaving the ground toward a ledge) can also trigger a mantle, not
		# just a standing jump-press - real ALS lets a running jump catch a
		# ledge the same way.
		if Input.is_action_just_pressed(&"jump"):
			_try_start_mantle(false)
	elif Input.is_action_just_pressed(CROUCH_ACTION):
		# Crouch is grounded-only in ALS, and toggled rather than held.
		_set_crouching(not _is_crouching)
	elif Input.is_action_just_pressed(&"jump"):
		# Jumping from a crouch stands up first, and is refused outright if
		# there's no headroom to stand into - matching crouch's own gate.
		if _is_crouching:
			_set_crouching(false)
		if not _is_crouching and not _try_start_mantle(true):
			_body.velocity.y = JUMP_VELOCITY
			_apply_jump_play_rate()

	# ALS's three real gaits (EALSGait Walking/Running/Sprinting). Running is
	# the baseline; walk and sprint are both held modifiers off it.
	var target_speed := CROUCH_RUN_SPEED if _is_crouching else RUN_SPEED
	if Input.is_action_pressed(&"sprint"):
		target_speed = CROUCH_SPRINT_SPEED if _is_crouching else SPRINT_SPEED
	elif Input.is_action_pressed(WALK_ACTION):
		target_speed = CROUCH_WALK_SPEED if _is_crouching else WALK_SPEED
	# Camera-relative movement (ALS standard third-person control): input is
	# always relative to where the camera is looking, in both rotation modes -
	# only the BODY's facing differs between the two modes, not which way
	# input actually moves it.
	var camera_yaw := _camera_pivot.rotation.y
	# ALSBaseCharacter.cpp caches AimYawRate once per tick, before anything
	# reads it - same here, since both the turn-in-place gate and the grounded
	# rotation rate consume it.
	_aim_yaw_rate_deg = (
			absf(rad_to_deg(wrapf(camera_yaw - _prev_camera_yaw, -PI, PI))) / delta
			if _has_prev_camera_yaw else 0.0)
	_prev_camera_yaw = camera_yaw
	_has_prev_camera_yaw = true
	var move_dir := Basis(Vector3.UP, camera_yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	var target_velocity := move_dir * target_speed
	var horizontal := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var accel := ACCELERATION if move_dir.length() > 0.01 else DECELERATION
	horizontal = horizontal.move_toward(target_velocity, accel * delta)
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z

	_update_air_lean_and_land_prediction(delta)

	var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")

	if _is_turning and move_dir.length() > 0.01:
		# Player started moving mid-turn - cancel back to normal Grounded
		# blending immediately rather than finishing the canned animation.
		_is_turning = false
		playback.travel(&"Grounded")

	if _is_landing and move_dir.length() > 0.01:
		# Same cancel-early idea as turn-in-place: don't force the player to
		# sit through the landing pose if they're already moving away.
		_is_landing = false
		playback.travel(&"Grounded")

	# ALSBaseCharacter.cpp's real bCanUpdateMovingRot gate: (bIsMoving &&
	# bHasMovementInput) || Speed > 150 cm/s (1.5 m/s) - shared by both
	# rotation modes for whether the body continuously chases a target yaw
	# at all this frame. While NOT moving, real ALS never continuously
	# rotates the body either way; Looking Direction instead runs the
	# delay-gated discrete TurnInPlaceCheck (see _update_turn_in_place_check)
	# so idle facing changes happen as a canned 90/180 clip, not a live spin.
	var moving_rot_gate := (
			move_dir.length() > 0.01 or horizontal.length() > ALS_MOVING_ROT_SPEED_THRESHOLD)
	if _is_turning:
		_update_turn_in_place(delta)
	elif _rotation_mode == RotationMode.LOOKING_DIRECTION:
		if moving_rot_gate:
			# Real ALS (ALSBaseCharacter.cpp::UpdateGroundedRotation, Looking
			# Direction branch - confirmed by reading the actual source, not
			# assumed): while sprinting the body SNAPS TO FACE VELOCITY, same
			# as Velocity Direction mode, not the camera. Non-sprint target is
			# AimingRotation.Yaw + a per-clip YawOffsetCurve (hip/lean offset
			# baked into the animation itself) - we have no such curve, so the
			# non-sprint target here is plain camera yaw.
			_turn_check_elapsed = 0.0
			if Input.is_action_pressed(&"sprint") and horizontal.length() > 0.1:
				var vel_yaw := atan2(-horizontal.x, -horizontal.z)
				_smooth_character_rotation(vel_yaw, ALS_TARGET_INTERP_VELOCITY_DEG, delta)
			else:
				_smooth_character_rotation(camera_yaw, ALS_TARGET_INTERP_LOOKING_DEG, delta)
		elif _body.is_on_floor():
			_update_turn_in_place_check(delta, camera_yaw, playback)
	elif moving_rot_gate:
		# Godot actor forward is local -Z: atan2(-x, -z) is the correct yaw
		# for a direction vector (see AGENTS.md). Confirmed backward before an
		# earlier fix via a headless test comparing actual velocity direction
		# against the character's resulting forward vector (dot product -1.0
		# i.e. facing exactly opposite its own travel direction).
		var target_yaw := atan2(-horizontal.x, -horizontal.z)
		_smooth_character_rotation(target_yaw, ALS_TARGET_INTERP_VELOCITY_DEG, delta)
	elif _body.is_on_floor():
		# Idle in Velocity Direction mode: real ALS leaves the body facing
		# wherever it last stopped (no idle facing-catch-up in this mode at
		# all) - this prototype still runs the same delay-gated turn-in-place
		# trigger here anyway, as a pragmatic UX addition so the camera can't
		# leave the body stuck facing away indefinitely. Not itself ported
		# behavior, just reuses the real trigger machinery.
		_update_turn_in_place_check(delta, camera_yaw, playback)

	_apply_stair_step_up(delta)
	_body.move_and_slide()

	var on_floor := _body.is_on_floor()
	if _foot_ik_modifier != null:
		_foot_ik_modifier.set_character_grounded(on_floor)
		# The solver is turned OFF entirely while crouched, not merely
		# pose-suppressed. Measured, not assumed: running it on ALS's crouch
		# pose drags the hips from the clip's authored 0.437m up to 0.966m -
		# almost fully standing - because it plants the bent crouch legs and
		# pushes the pelvis up to compensate" was a misdiagnosis - the crouch
		# clips' arms were broken by a wrong retarget argument (see the status
		# log), and that made the pose look wrong for an unrelated reason.
		# Confirmed by testing directly: with the retarget fixed, leaving the
		# modifier fully active still measures the crouch pose correctly
		# (head 1.446 -> 0.951m above the feet). Foot IK stays on throughout
		# crouch; only strafing suppresses the foot pose, matching PlayerBody's
		# own condition exactly.
		_foot_ik_modifier.set_pose_suppressed(
				_is_crouching and on_floor and absf(input_dir.x) > 0.5)
	if _spine_twist_modifier != null:
		# DISABLED, and that is the faithful behaviour - see below.
		#
		# The C++ (`UpdateAimingValues`) only gates SpineRotation on
		# `!RotationMode.VelocityDirection()`, which is what an earlier version
		# of this drove it from - and it looked wrong live: the torso swung
		# with the camera while the legs stayed planted, unbounded, at any
		# angle. Reading the AnimGraph rather than just the C++ shows why. The
		# node applying SpineRotation is alpha-gated by an ANIMATION CURVE,
		# `Enable_SpineRotation` (its AlphaCurveName), sitting under a comment
		# reading "Apply Aim Offsets or manual spine rotation" - it is the
		# either/or FALLBACK for when aim offsets are masked, not the mechanism
		# ordinary third-person uses. Third-person upper-body-follows-camera in
		# real ALS comes from the additive AIM OFFSET, which is bounded and
		# smooth; the manual twist is raw and unbounded.
		#
		# Our retargeted clips carry no curves at all (same reason
		# `Layering_*`/`Mask_*`/`BasePose_*` are unavailable), so
		# `Enable_SpineRotation` would evaluate to 0 here and real ALS would
		# apply no twist either. Driving it unconditionally was porting a real
		# mechanism onto the wrong condition.
		#
		# The modifier itself is kept, correct and verified (25/50/75 across
		# spine_01/02/03) - it becomes usable if an Aiming mode and a real aim
		# offset ever exist here.
		_spine_twist_modifier.twist_yaw = 0.0
	if not _anim_started:
		# The "parameters/playback" resource isn't live until the tree has
		# processed at least one frame - calling start() from _build_player
		# (before any frame ran) silently had no effect, confirmed via a
		# headless smoke test. Whatever the state machine's real default
		# initial state is otherwise (observed as Airborne, not the first- or
		# last-added node), this forces it explicitly on the first real frame.
		playback.start(&"Grounded" if on_floor else &"Airborne")
		_anim_started = true
		_visually_airborne = not on_floor
	else:
		_airborne_frames = 0 if on_floor else _airborne_frames + 1
		if _visually_airborne and on_floor:
			# Real landing - the animation had actually committed to Airborne.
			_is_turning = false
			_is_landing = true
			_land_elapsed = 0.0
			var use_heavy := absf(_last_fall_velocity_y) >= LAND_HEAVY_SPEED_THRESHOLD
			var land_clip_name := &"land_heavy" if use_heavy else &"land_light"
			_land_node.animation = StringName("clips/" + String(land_clip_name))
			var land_anim: Animation = _anim_player.get_animation_library(&"clips").get_animation(land_clip_name)
			_land_duration = land_anim.length
			playback.travel(&"Landing")
			_visually_airborne = false
		elif not _visually_airborne and not on_floor and _airborne_frames >= AIRBORNE_DEBOUNCE_FRAMES:
			# Off the floor long enough to treat as a real fall, not a
			# momentary stair-step snap gap.
			_is_turning = false
			playback.travel(&"Airborne")
			_visually_airborne = true
	if _is_landing:
		_update_landing(delta)
	# Character-LOCAL (right, forward) velocity - matches the blend space's
	# own points, which are placed by direction relative to the BODY's own
	# facing, not world space (this is what makes strafing in Looking
	# Direction mode play a strafe/backpedal clip instead of forward-walk).
	var local_velocity: Vector3 = _character.transform.basis.inverse() * horizontal
	var blend_position := Vector2(local_velocity.x, -local_velocity.z)
	# Each blendspace's OUTERMOST ring is its run ring, and sprint speed sits
	# well beyond it - a sprinting blend position would land outside the
	# triangulated hull entirely and stop resolving to the run clips (this is
	# exactly what broke sprint when the invented 3.0/6.0 speeds were replaced
	# by ALS's real 1.75/3.75/6.5, since sprint used to land ON the ring by
	# coincidence). ALS has no sprint clips: it clamps to the run cycle and
	# raises the play rate instead, which is what the TimeScale below does.
	_anim_tree.set(&"parameters/Grounded/StandBlend/blend_position",
			blend_position.limit_length(RUN_SPEED))
	_anim_tree.set(&"parameters/Grounded/CrouchBlend/blend_position",
			blend_position.limit_length(CROUCH_RUN_SPEED))

	# CalculateStandingPlayRate, simplified: real speed divided by the speed
	# the current gait's clips were AUTHORED at. ALS's full version lerps
	# between all three via the `W_Gait` animation curve, which our retargeted
	# clips don't carry, so the gait is selected discretely instead.
	var animated_speed := ALS_ANIMATED_RUN_SPEED
	if _is_crouching:
		animated_speed = ALS_ANIMATED_CROUCH_SPEED
	elif Input.is_action_pressed(&"sprint"):
		animated_speed = ALS_ANIMATED_SPRINT_SPEED
	elif Input.is_action_pressed(WALK_ACTION):
		animated_speed = ALS_ANIMATED_WALK_SPEED
	# Held at 1.0 when essentially stationary: ALS can clamp to 0 because its
	# idle is a separate state, but here idle shares the blendspace and a zero
	# rate would freeze it.
	var ground_speed := horizontal.length()
	_anim_tree.set(&"parameters/Grounded/GroundTimeScale/scale",
			1.0 if ground_speed < 0.1
			else clampf(ground_speed / animated_speed, 0.0, ALS_PLAY_RATE_MAX))

	# Sprint layer: only once actually moving at pace, so a stationary sprint
	# key-hold doesn't pop the character into a sprint pose on the spot.
	var sprinting := (
			SPRINT_CLIP_ENABLED
			and Input.is_action_pressed(&"sprint") and not _is_crouching
			and ground_speed > RUN_SPEED * 0.5)
	_sprint_blend = move_toward(
			_sprint_blend, 1.0 if sprinting else 0.0, SPRINT_BLEND_SPEED * delta)
	_anim_tree.set(&"parameters/Grounded/SprintBlend/blend_amount", _sprint_blend)
	# Eased rather than snapped so standing up / crouching down is a blend, not
	# a pop. ALS gets the same smoothing from its BasePose_N/BasePose_CLF
	# curves, which we have no equivalent of.
	_stance_blend = move_toward(_stance_blend, 1.0 if _is_crouching else 0.0, STANCE_BLEND_SPEED * delta)
	_anim_tree.set(&"parameters/Grounded/StanceBlend/blend_amount", _stance_blend)
	_anim_tree.set(&"parameters/Airborne/AirBlend/blend_position",
			clampf(_body.velocity.y, -AIR_BLEND_VELOCITY_RANGE, AIR_BLEND_VELOCITY_RANGE))

	# Last: the camera reads the character's final settled position and the
	# skeleton's current head location, so it has to run after move_and_slide
	# and after the animation tree has been driven for this frame.
	_update_camera(delta)


## Reuses foot_ik_ramp_matrix_check.gd's ramp shape/rotation math and
## foot_ik_stair_surfaces.gd's step-height parameterization, but built
## standalone here (no PlayerStairController/foot-IK layer coupling) so this
## prototype stays independent of actors/player/*.
func _build_terrain() -> void:
	var floor_mesh := CSGBox3D.new()
	floor_mesh.name = &"Floor"
	floor_mesh.size = Vector3(40.0, 0.2, 40.0)
	floor_mesh.position = Vector3(0.0, -0.1, 0.0)
	floor_mesh.use_collision = true
	add_child(floor_mesh)

	var ramp_angles := [15.0, 30.0, 45.0]
	for i in ramp_angles.size():
		_build_ramp(Vector3(-12.0 + i * 6.0, 0.0, -6.0), ramp_angles[i])

	_build_stairs(Vector3(6.0, 0.0, -6.0), 8, 0.15)
	_build_stairs(Vector3(12.0, 0.0, -6.0), 8, 0.3)

	_build_mantle_ledge(Vector3(0.0, 0.0, 4.0), 1.0)
	_build_mantle_ledge(Vector3(4.0, 0.0, 4.0), 1.8)


func _build_mantle_ledge(origin: Vector3, height: float) -> void:
	const LEDGE_WIDTH := 3.0
	const LEDGE_DEPTH := 2.0
	var ledge := CSGBox3D.new()
	ledge.name = &"MantleLedge"
	ledge.size = Vector3(LEDGE_WIDTH, height, LEDGE_DEPTH)
	ledge.use_collision = true
	ledge.position = origin + Vector3(0.0, height * 0.5, 0.0)
	add_child(ledge)


func _build_ramp(origin: Vector3, angle_degrees: float) -> void:
	const RAMP_WIDTH := 3.0
	const RAMP_LENGTH := 4.0
	const RAMP_THICKNESS := 0.3
	var ramp := CSGBox3D.new()
	ramp.name = StringName("Ramp%d" % roundi(angle_degrees))
	ramp.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH)
	ramp.use_collision = true
	ramp.rotation = Vector3(-deg_to_rad(angle_degrees), 0.0, 0.0)
	var half_length := ramp.basis * Vector3(0.0, 0.0, RAMP_LENGTH * 0.5)
	var half_thickness := ramp.basis * Vector3(0.0, -RAMP_THICKNESS * 0.5, 0.0)
	ramp.position = origin + half_length + half_thickness
	add_child(ramp)


func _build_stairs(origin: Vector3, step_count: int, step_height: float) -> void:
	# 0.9, not the original 0.3: the capsule collider is 0.7m in diameter
	# (radius 0.35), wider than a 0.3-deep tread - the character's own body
	# was permanently touching the NEXT riser even standing still on any
	# step, so _apply_stair_step_up()'s post-lift test_move() always still
	# read "blocked" and correctly (per its own logic) refused to climb.
	# Confirmed via a per-frame position/velocity trace showing the
	# character fully stuck (zero velocity) at the base of the stairs,
	# never even starting to climb - not a step-up logic bug, a tread-vs-
	# capsule geometry mismatch.
	const STEP_DEPTH := 0.9
	const STEP_WIDTH := 2.0
	var stairs := Node3D.new()
	stairs.name = StringName("Stairs_h%d" % roundi(step_height * 100.0))
	add_child(stairs)
	for i in step_count:
		var step := CSGBox3D.new()
		step.name = StringName("Step%d" % i)
		var rise := step_height * (i + 1)
		step.size = Vector3(STEP_WIDTH, rise, STEP_DEPTH)
		step.use_collision = true
		step.position = origin + Vector3(0.0, rise * 0.5, -STEP_DEPTH * i)
		stairs.add_child(step)
