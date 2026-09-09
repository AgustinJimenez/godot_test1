# 016: GASP animation assets and architecture reference

## Status and scope

Planned research task; implementation and asset import have not started. Requested by the
user after the Foot IK architecture discussion. Keep 013/014 as the active tasks until the
user chooses to start this work.

Evaluate Epic's Unreal Engine Game Animation Sample Project (GASP) in two independent tracks:
whether its animation assets may be used in this Godot project, and which architectural
principles are worth implementing independently here. This is not a decision to switch engines,
port Unreal code, or build a complete Motion Matching system.

## Track A: animation licensing and technical feasibility

- Identify the exact sample/engine version and record its applicable license and asset notices.
  Prior research found a UE-Only designation in Epic's indexed localized Fab listing, while the
  English listing did not clearly expose license terms. Treat Godot usage as unapproved until
  the version's terms or explicit permission from Epic establish otherwise.
- Distinguish export capability from permission: Unreal can export Animation Sequence assets,
  but conversion or retargeting does not remove license restrictions. Do not import or commit
  sample assets to this repository while cross-engine permission remains unresolved.
- If the terms are unclear, identify the exact question for Epic; do not assume that being free
  or available on Fab implies cross-engine use. Report the outcome as permitted, restricted,
  or unresolved, with sources and verification date.
- If restricted, keep the architecture study useful independently and identify an alternative
  animation source with explicit Godot-compatible terms rather than attempting a workaround.
- If permitted and the user approves a prototype, test a small representative selection first:
  idle, start/stop, turn/pivot, walk, and landing. Validate skeleton/rest-frame mapping, scale,
  axes, root motion versus in-place playback, loop modes, and final foot/toe contacts using the
  existing Character Editor/retargeting tools. Do not begin with a bulk import.
- Record what must be reconstructed separately: exported clips do not carry the sample's
  runtime Motion Matching, pose-warping, or Blueprint behavior into Godot.

## Track B: architecture reference

Inspect one pinned GASP version and distinguish documentation claims from behavior verified
in the actual project. Produce a small responsibility/data-flow map and compare it with
[015](015_foot_ik_architecture_direction.md) and the coordinator migration in
[010](010_foot_ik_target_coordinator_consolidation.md).

Focus on:

1. Movement snapshots, explicit gameplay states, and trajectory prediction: what is sampled,
   when state advances, and what animation consumers read.
2. Choosers and database filtering: separate eligibility/priority decisions from pose selection.
3. Visual root offsets versus collision-body movement: ownership, bounds, and release behavior.
4. Pose warping, transition blending, and leg IK: stage ordering, coordinate spaces, and which
   stage may change a target after another stage has evaluated it.
5. Pose history, per-stage debug toggles, and replay tools: how to explain a bad final pose from
   the decisions that produced it.

Do not assume GASP solves our terrain-contact problem. Its documented Leg IK stage pins feet to
IK-bone targets; that alone is not a stair-support planner. The documented experimental root
offset also has collision/transition limitations. Verify these details for the chosen version.
Study concepts and behavior; do not assume Unreal source, Blueprints, or assets can be copied
into a Godot implementation under the same terms.

## Deliverables and completion

- Version-specific, source-backed asset-license decision, including any unresolved permission.
- Architecture comparison: what to adopt, adapt, or avoid, and why it addresses our observed bugs.
- One bounded proposed prototype, its acceptance checks, and dependencies. Prefer something
  useful without Motion Matching, such as explicit pose-stage contracts or transition replay.
- User-facing recommendation before implementation. Asset reuse and architecture reuse are
  separate decisions; a negative licensing result does not block the architecture track.

No gameplay changes, engine migration, mass asset import, or full-system rewrite in this task's
research phase. Keep this document a concise current handoff, not an investigation transcript.

## Starting references

- [Epic GASP documentation](https://dev.epicgames.com/documentation/unreal-engine/game-animation-sample-project-in-unreal-engine)
- [Fab listing](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016)
- [Localized listing with previously indexed UE-Only notice](https://www.fab.com/it/listings/880e319a-a59e-4ed2-b268-b32dac7fa016)
- [Epic Content License Agreement, including UE-Only definition](https://www.unrealengine.com/eula/content)
- [Animation Sequence Editor/export documentation](https://dev.epicgames.com/documentation/unreal-engine/animation-sequence-editor-in-unreal-engine)

First action when activated: establish the exact sample version and license evidence, then
inspect its movement-to-pose flow. Recheck sources rather than treating this planning note as
permanent confirmation of current licensing or implementation details.
