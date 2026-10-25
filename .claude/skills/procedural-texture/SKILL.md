---
name: procedural-texture
description: Fit, judge and improve a procedural surface (bark, rock, soil, gravel, wood) against its Poly Haven photograph in this Godot project. Use when asked to make a procedural texture match a photo, refit a surface, or review how close one is.
---

# Procedural texture loop (agent workflow)

Everything is driven by `python tools/bark/pipeline.py <command> <surface>` (see `list` for the surface names). No API is called: YOU look at the pictures.
Python here is Anaconda's (the script picks it); Godot is `E:/Godot/4.7.2/...` (env `GODOT`). Pictures go to `E:/Temp/tx`. Read AGENT_TASKS/090 for the state of each surface.

## The loop
1. `pipeline.py list` -> pick the surface. `pipeline.py review <surface>` shows the last picture and the checklist. Read the png, answer the checklist, then
   `python tools/bark/review.py record <surface> <score> "<differences, most important first>" "<keep>"`. Score 7+ = passes for the photograph at a glance.
2. Decide the cause: a NUMBER (colour, size, density, contrast) or the GENERATOR (the structure cannot be made: pine plates, ash ridges, dark_rock courses).
   - Numbers: `pipeline.py fit-torch <surface> 120` (plates, flake barks; minutes) or edit the shader constants (`shaders/world/*_bake.gdshader`), then
     `pipeline.py export <surface>` (writes `systems/world_gen/*_fits.gd`; use `--check` first) and `pipeline.py match <surface>` (colour fit + new picture).
   - Generator: write a torch generator reusing `tools/bark/torch_plates.py` (integer hash, value noise), fit it with a script like `fit_courses_torch.py`,
     look with `compare_torch.py`. Port to GLSL only if the surface is wanted in the game, and parity-test it (`torch_*_parity.py`).
3. Change ONE thing, rebuild (`match`), `review` again, `record` again, `review.py history <surface>` shows the trend. Stop when the score fails to rise twice in a row.
4. Look in two views: the flat square AND the object (`square_compare --surface=N --object`; the plain square hides relief errors and the object hides colour).

## Rules learned (details in AGENT_TASKS/085 and 090)
- Cap scale parameters from `measure_scale.py` before a free fit: fits that lower the loss by making features bigger or simpler always looked wrong.
- The style loss is blind to a few thin cracks and to hard tone steps; bound `crack_depth` >= 0.5 and `z_var` <= 0.3 for plates, and LOOK.
- Hand edits to a generated `*_fits.gd` are lost on the next export: put them in the fit json (`tools/bark/fits/<surface>_*.json`) or the shader.
- `export --check` must say IDENTICAL before you rely on re-export (wood is STALE: do not export it).
- Shaders that round `tile / scale` can differ between the GPU and torch (the GPU divides as `x * (1/y)`); parity-test any new torch port.
- Commit with explicit paths only (never `git add -A tools`: the Poly Haven downloads and fit pictures are untracked on purpose).
