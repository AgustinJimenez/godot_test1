# Cloth contact decision — proposed, awaiting agreement

## Visible outcome

Loose sleeves now rest on both arms with open wrists. Small elbow penetrations remain during walking. Task 103's approved sleeve refinement is implemented; further collision changes pause here under AGENTS.md's repeated-bug rule.

## Shared cause and evidence

The current decision validates one particle against one nearest body triangle before projection. It does not establish that the final particle or the fabric between particles remains outside after all constraints. Smaller faces improved the original example but exposed failures elsewhere in the same walk.

- Both resting probes pass: full coverage, about 4–5 mm mean clearance.
- Male walking frame 90: vertices outside, four edge samples penetrate the rendered clearance; face-center minimum improved from -3.86 to -0.78 mm.
- Frame 150: seven male and three female free vertices fail the -1 mm tolerance. Some male failures sit exactly at the 40 mm travel limit; others do not. Therefore the travel clamp is not yet proven to explain every failure.
- Actual GPU collider and current CPU body agree exactly. Disabling friction does not clear the defect.
- A frozen, isolated GPU replay of the same contact shader moves all seven failing male points to +4 mm. The shader can recover them; the ordinary final simulation state does not guarantee recovery. Do not claim the exact remaining pipeline cause is established yet.

Evidence: `C:/Users/agus_/.codex/scratch/cloth_sleeves/` (`refined_suite.log`, `contact_diagnostic.log`, `predicted_diagnostic.log`, `friction_motion.log`, `replay.log`). No experimental friction or scheduling changes remain in production code.

## Proposed next stage

1. Capture the input and output of the final native contact dispatch and UPDATE for the same failing particles, within one GPU frame. Establish precisely which operation invalidates contact or which projected face loses ownership.
2. Give the final body-contact result one owner. Resolve its travel budget and body boundary together, replacing the invalidating decision rather than adding another offset, pin or per-frame exception. If nearest-face projection itself fails, replace that choice with a consistent surface contact; remove superseded guards.
3. Gate each stage on existing rest/lifecycle/normal checks plus walking vertex, edge and face samples for both bodies at frames 90 and 150. Review a short rendered walk and whole-frame cost before acceptance. Keep open wrists and the loose underside.

No new collision implementation has been made for this stage. User agreement on this diagnostic/design stage is needed before continuing it; the user explicitly requested committing/pushing the existing progress on 2026-11-26, without accepting this next implementation stage.
