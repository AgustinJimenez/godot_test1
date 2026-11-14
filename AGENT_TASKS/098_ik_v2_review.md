# 098 - Foot IK v2 review (independent, by a Fable 5.2 agent)

Status (2026-11-14): LAUNCHED. Request (user): "launch a fable 5.2 agent to review the ik implementation, to see what to improve, what's wrong, investigate online if we must".
Review only: no code changes, no commits. Findings go in the Findings section below and the agent's report.

## Scope
Foot IK v2 as it runs now: the native port (`native/planet_crust/src/foot_ik_*_native.{h,cpp}`: core, helpers, ledge, modifier, native), the GDScript glue
(`actors/player/foot_ik_v2/foot_ik_v2_install.gd`, `actors/player/foot_ik/foot_ik_recorder.gd`, `actors/player/climb/hand_hold_ik_modifier.gd`), the tests and probes in
`tests/manual/foot_ik_v2/`, and the history in `AGENT_TASKS/035*`, `036`, `037`, `091`, `093`, `docs/foot_ik_industry_review.md`, `docs/procedural_walk_experiment.md`.
Background: v2 is the reduced rewrite of v1 (preferred by the user: "looks so much better"); v1 is legacy and out of scope except as comparison.

## Questions
1. What is wrong: bugs, wrong maths, edge cases (stairs, slopes, ledges, turns, landings, steep or unstable ground, planet curvature / non-Y up), state that can fight itself,
   frame-rate or timestep dependence, double-precision issues, thread safety, memory or allocation per frame.
2. What to improve, ranked by how much smoother the animation would look (the user judges only by whether it looks smooth), then by cost.
3. How it compares with the state of the art: UE5 Control Rig / Full Body IK / Foot Placement, Unity Animation Rigging, Godot's own SkeletonIK/LookAtModifier, Motion
   Matching foot locking, inertialization, ground-reaction and pelvis-offset work, GDC talks (search online where useful: cite sources with links).
4. Whether the 037 "plant once" design is still the right next step, and what the cheapest path to it is.
5. Test coverage gaps: which scenarios have no check, and which checks pass trivially.

## Rules for the reviewer
- Read the code and tests; run the existing native check and solver check only if quick (`foot_ik_v2_native_check.gd`, `foot_ik_v2_solver_check.gd`); one game instance at a time;
  the user's editor (PID 20944, same exe name) must never be killed. Do not edit source files; write only to this file (the Findings section).
- Lead each finding with the outcome in plain words (smooth / not smooth, fast / slow, buggy / not), then the technical detail with file:line.
- Mark each finding CONFIRMED (reproduced or proven from the code), PLAUSIBLE, or SPECULATION.

## Findings
(pending)
