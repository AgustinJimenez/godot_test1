# Procedural Room Generation Plan

Not yet implemented — this is the "agree on the algorithm before writing code"
step, following the same pattern as `docs/character_editor_mcp_plan.md`. Written
up from the user's initial design description plus open questions/recommendations
that need a decision before any code gets written.

## Goal

Generate a layout of connected rooms (starting with two unit types: `Room` and
`Corridor`) procedurally, room by room, each one attached to a previously
generated room through a walkable connection (a "door" opening in a shared
wall). Support a seed so a layout can be reproduced.

This is a known procedural-generation family — "agent-based dungeon growth":
pick an existing room, attach a new one through a doorway, validate for
collisions, retry or move to a different anchor on failure, repeat. Nothing
about the user's description is unusual for this genre; the open questions
below are about how to implement it cleanly in this project, not whether the
approach is sound.

The end goal is a maze that keeps growing as the player explores toward its
edges, with no fixed overall size — but that streaming/player-driven layer is
a distinct problem (world streaming) from the generation algorithm itself, so
this is split into two phases: **Phase 1** proves the core room/corridor/
connection algorithm on a large *finite* batch (a fixed `target_room_count`,
visualized via the 2D debug dump); **Phase 2** wraps that proven generator in
a player-proximity-triggered streaming layer with no fixed endpoint. Phase 1
is what the rest of this document (through "Non-goals") describes; Phase 2 is
its own section below.

## Proposed algorithm

```
generate(seed, target_room_count):
    rng = RandomNumberGenerator with the given seed (record it if auto-picked)
    rooms = [ first room, placed at the origin ]

    while rooms.size() < target_room_count and generation_attempts < MAX_ATTEMPTS:
        anchor = most recently placed room                 # see Q4
        room_type = weighted_random_type(rng)               # see Q1
        placed = false

        for connection_attempt in range(MAX_CONNECTION_ATTEMPTS):
            side = rng.pick one of anchor's 4 walls          # see Q2
            opening = random position + size along that wall
                      (size clamped to [human_width, wall_length])
            size = room_type.random_size(rng)                # see Q3
            candidate_rect = place candidate room so its near wall
                             lines up with `opening`

            if candidate_rect does not overlap any existing room
                    (excluding the intentional shared-wall touch):
                rooms.append(candidate_rect)
                record the connection (anchor, candidate, opening)
                placed = true
                break

        if not placed:
            anchor = random existing room from `rooms`        # exhaustion fallback
            # loop again; if this keeps failing, generation_attempts
            # eventually hits MAX_ATTEMPTS and generation stops early
            # with fewer than target_room_count rooms (see Q4)

    return rooms   # plain data: rects + connection records, no 3D nodes yet
```

A second, separate pass turns this plain-data layout into real geometry
(reusing the CSG wall/floor/ceiling/doorway patterns already established in
`levels/backrooms_level0.tscn` — see "Data vs. geometry" below).

## Open questions / recommendations

### Q1 — Weighted type selection, not a 0-1000 roll
A `[0, 1000)` roll compared against manually-tracked cutoffs works, but it's
an arbitrary magic number that has to be kept in sync by hand as types are
added. Recommend a small weight table instead:

```gdscript
const ROOM_TYPES := [
    {"id": &"room", "weight": 70, ...},
    {"id": &"corridor", "weight": 30, ...},
]
```

Pick by drawing `rng.randf() * total_weight` and walking the list — same
result, no magic constant, and adding a third type later is just one more
table row.

### Q2 — Axis-aligned rectangles only (recommend for v1)
The description doesn't say whether rooms can be rotated at arbitrary angles,
only which *wall* (one of 4 sides) a connection sits on. Recommend
constraining every room to an axis-aligned rectangle (0/90/180/270 only, i.e.
picking which wall is "the front" rather than free rotation):

- Collision reduces to simple AABB-vs-AABB overlap, not oriented-box math.
- A corridor's "one side longer than the other" still works fine — it's just
  an axis-aligned rect with a random long axis (X or Z).
- Rotated rooms could be a *future* room type if more organic layouts are
  wanted later; not needed to prove out the core loop.

### Q3 — Room type definitions
Starting with exactly the two the user specified:

- **Room**: fixed width and length (same every time it's picked). Simplest
  possible type — good for proving the loop works before adding variety.
- **Corridor**: one axis randomly longer than the other (e.g. length is a
  random range, width is fixed/narrow) — always elongated, direction (does
  the long axis point away from the anchor, or can it run parallel to the
  shared wall?) needs picking. Recommend: corridor's long axis always points
  *away* from the connection (i.e. it extends the path), since a corridor
  running parallel to its own doorway isn't really a corridor.

### Q4 — Anchor selection and the ultimate escape hatch
The user's design: try the most-recently-placed room as the anchor; if its
`MAX_CONNECTION_ATTEMPTS` connection attempts all collide, pick a *different*
already-placed room at random and retry there. That's a solid two-level retry
(connection-level, then anchor-level) and is used as-is above.

Missing piece: what happens if *no* anchor room can fit anything, no matter
how many anchors are tried? Recommend an outer `MAX_ATTEMPTS` cap on total
generation attempts (connection attempts across all anchors, not just per
anchor) — once hit, stop and return however many rooms were successfully
placed rather than looping forever or crashing when `target_room_count` turns
out to be geometrically unreachable in the space available.

### Q5 — Connection/opening geometry when room depths differ
When the anchor's opening and the new room's near wall don't have identical
length (e.g. a wide room connecting to a narrow corridor), the opening's
walkable width should be the *smaller* of what both walls can support at that
position, clamped to `[human_width, min(anchor_wall_length, new_room_wall_length)]`.
Recommend picking the opening position on the anchor's wall first, then
constraining the new room's placement so its own wall segment actually
contains that opening — not generating the two independently and hoping they
overlap.

### Q6 — Seeding mechanism
Use a dedicated `RandomNumberGenerator` instance (Godot 4's seedable RNG
object), not the global `randi()/randf()` functions — those share one
implicit global state that's awkward to reset in isolation for a single
generation run. Store the seed as an `@export var generation_seed: int` (0 or
-1 meaning "auto-randomize"); when auto-randomizing, log the actual seed used
so a specific run can be reproduced later by pasting it back in.

### Data vs. geometry (two-phase generation)
Recommend generating the full layout as plain data first — an array of
`{type, rect, rotation}` room records plus `{room_a, room_b, opening}`
connection records — with all collision/retry logic operating on that data,
*before* any 3D node is created. Only once a complete valid layout exists does
a second pass turn each room record into real CSG geometry (walls, floor,
ceiling, a `DoorCut`-style subtraction at each connection — reusing the
patterns already proven out in `levels/backrooms_level0.tscn`). This keeps the
generation algorithm fast to iterate/retry (plain rect math) and testable in
isolation from rendering.

## Additional considerations (agreed in discussion)

- **Minimum padding between unconnected rooms.** The collision check should
  reject not just overlap but near-touching too: require a small minimum gap
  (e.g. 0.5-1m) between any two rooms that aren't the deliberately-connected
  pair. Two rooms landing exactly flush without a door would read as an
  accidental merge or z-fight.
- **Opening must stay fully within its wall segment.** `opening_position >= 0`
  and `opening_position + opening_size <= wall_length`, so a doorway can never
  clip past a corner into empty air.
- **Dead-end rooms/corridors are expected, not a bug.** Nothing forces a
  second connection onto every room; some will just terminate. Normal for
  this generation family and fits the backrooms tone.
- **Full reachability is guaranteed by construction.** Every room except the
  first is only ever added via a validated connection to an already-placed
  room, so the whole layout is one connected tree rooted at the first room —
  no isolated/unreachable room is possible.
- **Deterministic draw order.** All randomized picks (type, side, position,
  retry anchor) must happen in a fixed sequence for a given seed to actually
  reproduce a layout — use ordered arrays, not dictionaries, anywhere
  iteration order could affect which random draw happens when.
- **Attempt-count constants are placeholders.** `MAX_CONNECTION_ATTEMPTS` and
  `MAX_ATTEMPTS` need empirical tuning once layouts can actually be seen (via
  the 2D debug dump below), not a value chosen analytically up front.

## Phase 2 — player-driven streaming expansion

Once Phase 1's core loop is proven, wrap it so the maze grows outward as the
player explores instead of being generated once up front with a fixed count:

- **Trigger, not target count.** Replace `target_room_count` with a
  proximity trigger: when the player gets near a **frontier** room (one that
  still has unused wall space — a wall segment not yet occupied by a
  connection or ruled out by a failed attempt), run another round of the
  Phase 1 loop anchored there. The trigger distance should be a **lookahead
  buffer**, not the frontier edge itself — start generating the next batch
  while the player is still some distance away so it's ready by the time they
  actually arrive, rather than a visible pop-in/wait at the boundary (same
  idea as Minecraft's chunk-loading radius).
- **Consecutive-failure attempt counting, not a lifetime total.** Phase 1's
  `MAX_ATTEMPTS` can be a simple total cap since the loop naturally ends at
  `target_room_count` anyway. Phase 2 has no such endpoint, so the cap needs
  to be reframed as *consecutive* failures: every successful placement resets
  the streak to zero, and only a run of consecutive failures ends that
  particular expansion round. This is what lets generation continue
  indefinitely without ever hitting an artificial lifetime ceiling.
- **Local, not global, anchor selection.** Phase 1's "pick a random existing
  room" fallback stops making sense once the maze could have hundreds or
  thousands of rooms — anchoring off a room clear across the map isn't useful
  for expanding near the player. Anchor candidates should be frontier rooms
  filtered to ones near the player's current position.
- **Layout data can be kept forever; instantiated geometry can't.** A room
  record (a rect + a bit of metadata) is cheap enough that keeping thousands
  of them in memory for the whole session is a non-issue. Real 3D geometry
  (meshes, collision shapes) is not — an ever-growing maze needs that
  windowed to near the player and freed further away, the same problem
  Minecraft-style chunk loading solves. This is a third tier on top of
  Phase 1's data/geometry split: **data** (kept forever) → **instantiated
  geometry** (streamed in/out near the player) → **rendering**.
- **Collision checks need a spatial index at scale.** Brute-force "check
  against every existing room" is fine for the dozens-to-low-hundreds of
  rooms in a Phase 1 batch, but not for an open-ended maze. Eventually this
  wants a spatial hash (grid buckets keyed by room position) so a collision
  check only examines nearby rooms — not needed to prove out Phase 1, but
  flagged now so it isn't a surprise later.

### Frame budgeting (avoiding hitches)

Generating a large batch of rooms in a single frame would spike frame time
badly once the maze gets into the hundreds of rooms — the same problem UE5's
PCG time-slicing / World Partition streaming solve. Three tools, in order of
how much complexity they're worth reaching for:

1. **Per-frame work budget (start here).** Turn generation into a coroutine
   using `await get_tree().process_frame`: do a capped amount of work per
   frame (either N placement attempts, or a microsecond budget via
   `Time.get_ticks_usec()`), yield for a frame, resume. Single-threaded, no
   synchronization to reason about — the right starting point for this
   project.
2. **Background thread for the data phase (only if (1) isn't enough).**
   Phase 1's layout generation (rect math + collision checks) never touches
   the scene tree, so it's safe to run on `WorkerThreadPool.add_task()`,
   freeing the main thread entirely while a batch of room *data* computes.
   Godot's scene tree is not thread-safe, so a completed batch must be handed
   back to the main thread via `call_deferred` before any Node/CSG is
   created from it.
3. **Geometry instantiation needs its own frame budget, separately from data
   generation.** CSG rebuild cost per room is often the actually expensive
   part, not the rect math — spawning many new rooms' worth of CSG nodes in
   one frame can hitch even when the layout math behind them was instant.
   Batch node creation across frames the same way as (1), independently of
   whichever strategy (1 or 2) produced the underlying data.

At startup, generating the first several rooms around the spawn point can
block synchronously (expected load time, player hasn't moved yet); rooms
generated afterward, while the player explores, should use the lookahead
trigger plus one of the above so the world stays ahead of the player without
a frame-time spike.

## Non-goals for v1 (Phase 1)
- No player-driven streaming yet — that's Phase 2, above. Phase 1 generates
  one finite batch given a `target_room_count` and stops.
- No loops/cycles in the connection graph (a new room always attaches to
  exactly one existing room; no "connect back to an earlier room" logic) —
  keeps collision reasoning simple; could be a later enhancement.
- No multi-story/vertical layouts.
- No room types beyond `Room` and `Corridor` yet — the weight table and type
  definition shape should make adding more later straightforward, but only
  two are being built and proven out first.
- No visual theming/material decisions here — this plan is purely about
  layout generation; once a layout exists, dressing it (walls, ceiling tiles,
  props) reuses everything already built for `backrooms_level0.tscn`.

## Verification plan
Per this project's standing rule (never commit gameplay/visual changes on
automated verification alone): once implemented, generate several seeds
headlessly and dump each as a simple 2D top-down debug image (rects +
connection markers) for a quick sanity look before ever instantiating real 3D
geometry, then confirm the actual in-game walkable result (can the player
really walk through every generated connection) via a live editor test before
this is considered done.
