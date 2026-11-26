# Sleeve contact evidence (2026-11-26)

User verdict: sleeves did not wrap/rest on the arms; user selected **loose fabric resting on the arms**, with open wrists.

Baseline: upper sleeves had weight 0, stood 23.8 mm above the skin and moved 0 mm; forearms averaged weight 0.34, gap 21.9 mm, movement 2 mm. The update shader pulls partial weights toward their inflated rest shell every frame.

Freeing the sleeves alone exposed the old body approximation: round arm capsules omitted split-weight elbow vertices and underfilled parts of the visible arm by 11-15 mm. Enlarging them stopped clipping by holding fabric in the air. Native segmented/oval fits were tried and removed: enclosing irregular arm sections still stood too far above their skin. No rounded-shape shader/solver branches remain.

Final decision: keep the shoulder seam, fully free the hanging sleeve, and collide against the actual arm mesh. Native preparation keeps the exact triangles and all four bone weights (including shared elbows), blends the current body shapes, and compacts only arm vertices; per-frame native skinning returns packed GPU triangle bytes. No expensive per-triangle GDScript loop.

A two-sided triangle distance shell was also insufficient: a particle could settle inside the thin arm skin. The native path now picks the nearest outward-wound triangle, gates it to the animated target's configured reach, and projects to its outside. Contact runs after fishing/peer constraints too. Legacy mesh users keep the original two-sided path.

The acceptance probe first used nearest-rest-vertex gaps; clean averages hid skin poking through the elbow. It now casts from top arm-skin samples into actual GPU cloth triangles, reports mean/min clearance and checks hit coverage. Current base-body readings: about 4-7 mm mean, positive minima; original shell was ~22-24 mm. The open sleeve's underside still has room for hanging fabric, intentionally.

Local evidence (not repository assets): `C:/Users/agus_/.codex/scratch/cloth_sleeves/`. `before.png` is the body-lab baseline, `signed_female.png` the corrected rest view, `walk_Male.png` / `walk_Female.png` the corrected walk + turn. Logs preserve rejected results and exact ray clearances.

Final performance: repeating the nearest arm-surface query in four stretch iterations plus the final contact cost ~8 ms/frame. Keeping the native contact at its actual ownership boundary, once per substep after fishing/peer constraints, preserved the clearance checks and reduced the whole rig-lab frame to ~3.5 ms (static clothes ~0.6 ms). Native packing alone ~0.074 ms. The body contact reach stays separate from an optional/unlimited motion leash.

Moving-preview follow-up: small orange elbow patches remain with shader imperfections disabled. A frame-pre-draw scheduling trial did not change them and was removed. The scratch `motion_probe.gd` freezes walk frame 90 and reads both GPU buffers: body GPU/current CPU poses agree exactly; all fully free sleeve vertices are outside (minimum +3.665 mm), but eight triangle centers are inside (minimum -3.860 mm). User subsequently approved sleeve-only refinement, now implemented at 12 mm arm edges with shape layers preserved. Centers improve to -0.781 mm, but new edge/vertex checks expose remaining motion failures. Current evidence and the proposed next decision are in tasks 103 and 104; further collision patches are paused pending design agreement.
