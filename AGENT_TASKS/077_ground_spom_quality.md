# 077 - Ground parallax quality (SPOM investigation)

Status (2026-10-20): **active; the speckle is reduced in captures, awaiting a live verdict.** The user explicitly asked for a
commit/push of the whole prior working tree, so the 20-sample checkpoint is in `c9d2964` despite the
usual live-verdict commit rule. The user then explicitly requested a commit/push of the later side-darkness change too.
The user chose quality first: make the close, nearly horizontal ground view look three-dimensional and free of visible bugs, then reduce GPU use. Work and tuning should happen in `tests/manual/ground/ground_lab.tscn` before judging the planet during ordinary play.

## Current handoff

- The shared planet ground shader (`shaders/world/planet_ground.gdshader` plus `planet_mosaic.gdshaderinc`) draws packed fragments with procedural heights. It ray-marches into those heights, refines the hit three times, moves the other ground layers with the hit, and applies plate self-shadowing to direct light. This is the POM core of the linked SPOM example, **not full SPOM**: silhouette clipping and horizon erosion are not implemented. The ground is continuous, so trimming a mesh edge or discarding the horizon could make holes; only try either with a demonstrated ground use case.
- The user liked the general look and saw it in the planet scene, but at a very low, close camera angle reported flat relief, duplicated shapes, stretched plate sides, and later a buggy/speckled view. The earlier "transparent layer over the rocks" was improved by moving all sampled layers to the parallax hit. Smaller, darker real stones and darker plate sides were committed; the side streaks were reduced, not eliminated.
- A committed ground-lab camera readout is copied with **C**. The reproduced troublesome view used `pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far` (about 0.11 m camera height); Claude also rendered it with `chips=0` to isolate the shader. Use the full readout and a matching screenshot for exact A/B comparisons. The last Claude render reported smooth far ground but a bright speckle in the middle distance; its source had not yet been isolated. Images #27/#28 and the exchange are in the Claude TrueLogic session `dad2674f-4c6c-49d2-a3c8-f6fb05411f7c` under the profile's `projects/E--repo-godot-projects-godot-test1/` directory.
- The live ground lab redraws only on changes and is capped at 60 fps. The planet remains a continuously rendered game scene. Claude's earlier claim that the lab was uncapped was corrected: the project already had a 60 fps limit. Its later estimate was about 15 ms GPU for the ground in a planet view, including roughly 4 ms for parallax; remeasure after quality is settled.

## Quality checkpoint in `c9d2964`

- `planet_ground.gdshader`: the march loop allows 32 iterations; `foot_m = length(fwidth(near_anchor))` fades the three fragment scales and fine grain when they become smaller than a pixel.
- `planet_mosaic.gdshaderinc`: the fixed sample count changes from 9 to 20. The shader currently uses `mosaic_pom_max_steps` as its fixed count; `mosaic_pom_min_steps` is still exposed but unused. A varying count previously made a visible ring, so the fixed count is deliberate for now.
- `tests/manual/ground/ground_lab.gd`: default and slider range updated for the 20-sample setting.
- These changes have **not** received a final user live-test verdict. The unrelated texture `.import` change
  was also committed because the user explicitly asked for all then-uncommitted files. Any new visual
  changes wait for live confirmation under the normal `AGENTS.md` rule.

## Current quality result

The 2026-10-20 render A/B used `pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far chips=0 size=1400x600`.
Setting `mosaic_height=0` removes the speckle but loses the depth. Removing scans, plate shadows, grain,
pebbles, or one plate scale does not. More march steps strengthen the artifact; a pixel-footprint fade
and a three-tap height prefilter did not clear it and were reverted. TAA smooths a still or slow turn,
but a 1-degree-per-frame turn still showed the bright speckle. Thus the earlier hypothesis that the
height *sampling alone* caused the visible contrast was incomplete.

The decisive A/B set `mosaic_side_dark=0`: the speckled field almost disappeared without turning
parallax off. The shader had darkened every deep ray hit as if it were a plate side. A deep hit can be
an ordinary gap, so this made most middle-distance ground dark and left isolated bright plate tops.
`mosaic_side_dark` is now a lab slider and a shader uniform, reduced from the hard-coded 0.8 to 0.35.
That keeps nearby plate shapes visible with much less false contrast in both AA-off and fast-turn TAA
captures. This changes the shading decision itself rather than adding another distance/angle guard.
The ground lab accepts layer switches and `sweep=DEGREES` for repeatable captures; PNGs are under
`E:/Temp/codex_spom_*.png` (`side0`, `side02`, `side04`, `reduced_default`, `reduced_fast_taa`).
The fixed lab readout string had an embedded newline that `gdlint` could not parse; it now uses `\n`.
Godot 4.7.2 compiled and rendered the low, macro, brown and sand lab views. The functional checks in
`scripts/planet_check.sh --quick` all passed (including native water, world, walk and swim); its final
status was FAIL solely because repository-wide `gdlint` 4.5.0 reports 294 style violations,
predominantly lines over 100 characters across the project. `git diff --check` passes. The user
authorized committing this visual checkpoint before a live quality verdict.

## Next steps

1. In the ground lab, reproduce the saved low-angle view and judge the new 0.35 side darkness during motion. Check nearby relief, the middle-distance field, plate-side streaks, and the transition to flat ground. Captures support improvement but cannot give the final live verdict.
2. If a defect remains, inspect its sampled height, hit depth and final shading separately before altering the ray march. The 0.35 shading change should not be mistaken for a geometry fix.
3. After quality is accepted, benchmark GPU time and tune sample/shadow cost without reintroducing the artifact. The 20-sample march is expected to cost more; no current benchmark establishes that cost as acceptable.

`AGENT_TASKS/076_forests_and_fields.md` records the earlier mosaic design and research, but its parallax sample counts and limits predate this task. This file is the current status for the quality pass.
