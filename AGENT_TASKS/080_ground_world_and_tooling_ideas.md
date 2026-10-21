# 080 - Ground, terrain, water and tooling ideas (backlog; life is left out on purpose)

Status (2026-10-21): **ideas, not started.** Collected with the user after tasks 078 (sand) and 079 (light). Order within a group is
the order to try them in. Each idea needs its own look-and-measure step before it is built.

## Ground that reacts
- Visual regression first (tooling, below): it protects everything else.
- Weather on the ground: rain wets and darkens sand and soil, makes puddles, washes prints away; wind drifts sand and fills
  prints slowly; snow piles into drifts.
- Wind from the weather system (`planet_weather.gd`) for ripple and dune directions, instead of the fixed east axis.
- Footprints for everything that touches the ground: animals, rolling stones, falling objects (craters), rain pits; `PlanetImprinter.take`
  and `PlanetDents.add` are the API; snow and mud get the same imprints in place of the flat decals.
- Rocks shape the sand: scour round them, a heap behind them.

## Terrain
- Erosion look: gullies, dry riverbeds in deserts, crescent dunes (barchans).
- Tile geomorphing (the finer tile fades its vertices into the coarser one's): the ground rising and popping as you approach.
- Caves and overhangs need more than a height surface: a large piece of work, decide separately.
- Water: shore foam, wet sand at the waterline, waves.

## Tooling
- **DONE 2026-10-21: `scripts/visual_check.sh`** (5 views: desert dunes, close sand, far dunes, desert with plants, green country; compared at 640x360 with `tests/visual/baseline`, mean difference limit 4, 8 % of pixels; `--accept` stores new baselines after a look; differences in `$OUT_DIR/diff`). Add views for snow, coast, night as they become useful. Original idea: a render of fixed spots (desert, forest, snow, coast, night) after each change, compared with the last accepted
  one, so a regression such as the stretched columns on slopes is caught without the user.
- One ground-detail control that maps to what each effect costs (and a table of those costs, measured).
