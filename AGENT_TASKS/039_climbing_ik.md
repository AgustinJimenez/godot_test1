# 039 - Climbing and balance (Uncharted-style traversal), first pass

Built autonomously while the user was away (2026-10-13). Opt-in, not wired into the game: the Player
only runs it after `PlayerClimbInstall.install(player)` (the labs do). Nothing here is committed
unless the git log says so. No new animation was needed or made: the legs play the fall clip and the
arms are placed by hand IK, so it reads as a rough pass, not final polish.

## What exists (all under `actors/player/climb/`)

| Piece | Job |
|---|---|
| `climb_probe.gd` | Ray casts only: a wall face ahead of the chest + a flat top above it = a ledge `{point, normal, top}`; `follow()` re-finds it a step sideways (shimmy). |
| `hand_hold_ik_modifier.gd` | `PlayerHandHoldIKModifier`: two-bone arm AND leg IK (reuses `FootIKV2Solver`) to world hold points. `targets` + `weight` for hands (also the balance arms), `foot_targets` + `foot_weight` + `knee_way` for feet. |
| `player_climb.gd` | State machine FREE / HANG / MANTLE / WALL. A jump toward a ledge in reach catches it; hang; A/D shimmy; W or jump mantles; S lets go. |
| `climb_wall.gd` | Free climb on holds (any Node3D in group `climb_hold`, its +Z = out of the wall): stick picks the next hold for one hand, hands alternate; up, down, sideways, diagonal; at the top it hands over to the ledge hang. Jump = let go. |
| `player_balance.gd` | Narrow platform: no ground 0.45 m to either side under the feet -> walk slows to 1.1 m/s (no sprint) and the arms go out. |
| `player_climb_install.gd` | Puts the modifier + controller on a Player. |

Hook into the game: `player.gd` has `var climb` and one line at the top of `_physics_process`
(`if climb != null and climb.update(delta): return`).

## Checks

`scripts/check_climb.sh` (headless, three labs in `tests/manual/climb/`):
- `climb_lab`: run, jump, catch a 2.5 m ledge, hands within 6 cm of it (measured 1.3 cm), shimmy
  ~1 m, pull up, standing on top.
- `climb_wall_lab`: jump onto a brick wall, up 1.5 m, right 1.8 m, diagonal, down 1.9 m, then all the
  way over the 6 m ledge.
- `climb_balance_lab`: 0.3 m beam, slow on it (1.1 m/s), arms 1.5 m apart, full speed (3.2) after.

Screenshots: `-- --climb-check --climb-shots`, `-- --wall-check --wall-shots`,
`-- --balance-check --balance-shots` (run WITHOUT `--headless`; PNGs go to /tmp).

Lab gotcha: the skeleton is re-posed after the modifiers, so a bone read back from `_process` is
the animation again. Anything that must be graded is recorded by the modifier itself
(`debug_wrist`).

## Known gaps (the Uncharted list, what is not done)

1. Legs: on the hold wall each foot reaches the nearest hold under the hips (leg IK in the same modifier, `foot_targets`); when none is close the leg hangs in the fall clip. A ledge hang has no foot placement at all (no foot-on-wall contact).
2. No hang / shimmy / climb / mantle clips: the pose is the arm IK on top of a fall pose, the mantle
   is a position blend. Needs real animations (the GALS pack has almost none: only
   `idle_to_crouch-climb-up-1m-*` and wall-lean idles).
3. Not done: dropping from a ledge top into a hang, ledge-to-ledge leaps, corner (inside / outside)
   transitions, ropes / pipes / ladders, wall run, swing, free-climb jump between holds.
4. Narrow platform: only slowing + arms. No foot-on-line placement, no stumble / wobble, no
   `PlayerBalanceCounterLeanModifier` lean (that modifier is off by default).
5. The camera is not handled: first person swings with the body turning to the wall (the view
   offset is compensated like the player's own catch-up), third person is untouched.
6. Hold detection is a plain group scan each grab (fine for a lab, needs a spatial index for a level
   full of bricks). No level data marks holds yet: a real level needs a generator or a tagging tool.
7. Ledge probes assume a vertical wall and a flat top; slopes, rounded edges and thin ledges are
   not handled.

## Suggestions / questions for the user

- Do you want climbing in the game by default, or behind a debug toggle like Foot IK v2? (Now: only
  in the labs.)
- Hold authoring: tag brick meshes in the level scenes, or generate holds from a texture / mesh
  pattern? That decides whether the traversal is "any brick" or "marked handholds".
- Animation: are climb clips coming (Mixamo has hang / shimmy / climb-up / drop-to-hang), or should
  more be built procedurally (foot IK onto holds, torso lean)? Mixamo clips would replace the fall
  pose and the position-blend mantle, keeping the IK for the contact points.
- Ledge hang uses the jump button to mantle and S to let go: change to U4's (jump = leap, W =
  climb up, crouch = drop)?

## Decisions (user, 2026-10-13)

- Climbing is a debug toggle, off by default: **F8** in game (`ClimbToggle` node in `player.tscn`).
- Holds are generated from a pattern: `ClimbHoldWall` node (columns, rows, spacing), put on a wall face.
- Real climb clips later; keep going procedurally meanwhile.
- Buttons: **jump = leap** (from a hang or a hold: up, W toward the wall, S away, A / D sideways),
  **W = climb up**, **crouch = drop**. Crouch at a wall's edge, facing off it, lowers into a hang
  (drop-to-hang). Checked in `climb_lab` (drop-to-hang, leap 6.5 m/s, ledge re-caught, drop to ground).
- E near any edge (any facing) lowers into a hang; checked on the front, back and both side edges.
  Needs a drop of about 2 m (the hang length plus a margin); lower than that it is a step down.
- Shimmy is hand over hand (`ClimbHandShuffle`): the trailing hand hops ahead of the body, one at a
  time; at rest the hands settle either side. Note: `climb_lab --climb-check` run WITH a window
  reports hand_error 0.079 (headless 0.013): a read-timing difference in `_process`, the same with
  the old fixed hand placement, so not from the shuffle.
