# 077 - Ground parallax quality (SPOM investigation)

Status (2026-10-20): **active; visual bug remains; latest quality changes are uncommitted and need live review.**
The user chose quality first: make the close, nearly horizontal ground view look three-dimensional and free of visible bugs, then reduce GPU use. Work and tuning should happen in `tests/manual/ground/ground_lab.tscn` before judging the planet during ordinary play.

## Current handoff

- The shared planet ground shader (`shaders/world/planet_ground.gdshader` plus `planet_mosaic.gdshaderinc`) draws packed fragments with procedural heights. It ray-marches into those heights, refines the hit three times, moves the other ground layers with the hit, and applies plate self-shadowing to direct light. This is the POM core of the linked SPOM example, **not full SPOM**: silhouette clipping and horizon erosion are not implemented. The ground is continuous, so trimming a mesh edge or discarding the horizon could make holes; only try either with a demonstrated ground use case.
- The user liked the general look and saw it in the planet scene, but at a very low, close camera angle reported flat relief, duplicated shapes, stretched plate sides, and later a buggy/speckled view. The earlier "transparent layer over the rocks" was improved by moving all sampled layers to the parallax hit. Smaller, darker real stones and darker plate sides were committed; the side streaks were reduced, not eliminated.
- A committed ground-lab camera readout is copied with **C**. The reproduced troublesome view used `pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far` (about 0.11 m camera height); Claude also rendered it with `chips=0` to isolate the shader. Use the full readout and a matching screenshot for exact A/B comparisons. The last Claude render reported smooth far ground but a bright speckle in the middle distance; its source had not yet been isolated. Images #27/#28 and the exchange are in the Claude TrueLogic session `dad2674f-4c6c-49d2-a3c8-f6fb05411f7c` under the profile's `projects/E--repo-godot-projects-godot-test1/` directory.
- At `HEAD` (`eac1904`), the live ground lab redraws only on changes and is capped at 60 fps. The planet remains a continuously rendered game scene. Claude's earlier claim that the lab was uncapped was corrected: the project already had a 60 fps limit. Its later estimate was about 15 ms GPU for the ground in a planet view, including roughly 4 ms for parallax; remeasure after quality is settled.

## Uncommitted work found in the tree

- `planet_ground.gdshader`: the march loop allows 32 iterations; `foot_m = length(fwidth(near_anchor))` fades the three fragment scales and fine grain when they become smaller than a pixel.
- `planet_mosaic.gdshaderinc`: the fixed sample count changes from 9 to 20. The shader currently uses `mosaic_pom_max_steps` as its fixed count; `mosaic_pom_min_steps` is still exposed but unused. A varying count previously made a visible ring, so the fixed count is deliberate for now.
- `tests/manual/ground/ground_lab.gd`: default and slider range updated for the 20-sample setting.
- These changes have **not** received a final user live-test verdict. Preserve the unrelated modified `assets/models/kaykit_fantasy_weapons/weapons_bits_texture.png.import`. Do not commit the visual changes until the user tests and explicitly confirms them, per `AGENTS.md`.

## Next steps

1. In the ground lab, reproduce the last low-angle view using the C readout or its `pitch=... yaw=... dist=... fx=... fz=...` options. Check movement and still frames, close plate sides, middle-distance speckle, and the transition to flat ground. Ask for a fresh screenshot/readout only if the saved view cannot reproduce the remaining defect.
2. Isolate the speckle with the lab's layer checkboxes and the grain/pebble controls, then inspect the actual sampled values. Keep the fix in the responsible layer; avoid another angle-dependent transition that draws a ring. Judge the whole surface, including direct and ambient lighting, before calling the artifact fixed.
3. Run `scripts/check.sh` and a ground-lab render, then have the user judge about two or three close, low-angle views live. Only after quality is accepted, compare GPU time and tune sample/shadow cost or graphics settings without reintroducing the artifact. The 20-sample change is expected to cost more; no current benchmark or user approval establishes that cost as acceptable.

`AGENT_TASKS/076_forests_and_fields.md` records the earlier mosaic design and research, but its parallax sample counts and limits predate this task. This file is the current status for the quality pass.
