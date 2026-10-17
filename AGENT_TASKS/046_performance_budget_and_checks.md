# 046 - Performance budget and one check script

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

One command that runs every planet check and the measurements, repeats the noisy ones, compares them to a
written budget, and fails when something regresses. Today the checks are separate commands in AGENTS.md and
the numbers live in prose.

## Where we are

- Checks: `species_check.tscn`, `world_lab.tscn -- --world-check`, `planet_lab.tscn -- --planet-check`
  (with `SAVE_CHECK` and the menu page), `--walk-check`, `--swim-check`, `--fly-check` (headless, fixed fps).
- Measurements (need a window): `--fps` (fps, draw calls, primitives, tiles, triangles by kind), `--hide=`,
  `--no-shadow`, `--climb=`, and the `HITCH` line of the walk and fly checks. The hitch numbers are noisy
  (4-38 slow frames between identical runs): use the median of three.
- `scripts/check.sh` is the project lint/import check; `gdlint` limits: line 100, 20 public methods.

## Plan

1. `scripts/planet_check.sh` (bash, works in Git Bash): lint, import, then each check, printing one line
   per check and a final PASS/FAIL; `--quick` skips the fly check (minutes).
2. `tests/manual/planet/budget.json`: for named scenes (ground at spawn, a dense forest, 700 m, 2.5 km,
   6 km, the sea) the maximum draw calls and primitives and the minimum fps *relative* to a reference run
   made on the same machine (store the reference in `user://`, not in git, since GPUs differ).
3. A lab mode `--budget` that runs those scenes in turn and prints `BUDGET scene ok|over (value / limit)`.
4. The hitch test: run three times, take the median, compare to a limit.
5. Screenshot checks: keep a few reference images (noon ground, dusk, orbit, storm, snow) outside git and
   compare by a small difference metric, to catch a shader or sky regression that no number shows.
6. Document how to run it in `AGENTS.md` (one paragraph) and `planet_lessons.md`.

## Done when

- `scripts/planet_check.sh` exits non-zero on a failure of any check or budget and is documented.
- A deliberate regression (tree range doubled) is caught by the budget.

## Risks and open questions

- Budgets in absolute fps are meaningless across machines; relative budgets need a stored reference.
- Screenshot comparison with animated clouds and TIME-based shaders needs a fixed time (`--shot-frame` and
  a fixed clock); the lab already has `--hour`, `--year`, `--weather`.
