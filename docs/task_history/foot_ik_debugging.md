# Foot IK: orientation bugs, a quantization bug, toe clipping, and a killed walk cycle

## Background

`PlayerFootIKModifier` (`actors/player/player_foot_ik_modifier.gd`) plants
each foot on the actual ground/step surface beneath it via raycast, then
bends the leg (closed-form two-bone IK) and reorients the foot to match the
surface normal. `tests/manual/foot_ik/foot_ik_preview.tscn` plus
`foot_ik_debug_overlay.gd` (test-scene-only debug tool: colored skeleton
ribbons, a live numeric readout grid, floating angle labels on each bone
segment) is the harness used to develop and diagnose it. This file covers
several real bugs found and fixed after the modifier was already "working"
by casual visual inspection - all of them only became visible once the
debug tooling could show *numbers*, not just a screenshot.

## Bug 1: foot orientation could spin 90+ degrees

The foot's corrective rotation was originally a single shortest-arc
quaternion: `Quaternion(current_sole_down, -smoothed_normal)`, applied to
the whole animated foot basis. This determines the "down" axis correctly,
but leaves the twist/roll *around* that axis to whatever the implicit
perpendicular axis happens to be - which becomes numerically unstable
whenever the two vectors end up close to antiparallel (a common case: an
idle pose's sole can already point close to "up" relative to where the
ground target wants "down"). The result looked exactly like a
hand/forearm instead of a shin/foot - the whole foot spinning
unpredictably around its own long axis.

**Fix**: build the foot's target orientation from two explicit reference
vectors (down + a toe-forward direction derived from the rest-pose toe
offset) instead of one. See `_compute_new_foot_basis_world()`. Two vectors
fully constrain the twist, so there's no unstable axis choice left.

## Bug 2: a rest-pose quantization bug masquerading as a rig imperfection

Even after fixing the twist, the toe-tip (`ball_leaf`) bone still showed a
visible, constant kink relative to the toe - readable via the debug
overlay's per-segment world-angle readout (`Foot°`/`Leaf°`, each segment's
own angle from `Vector3.DOWN`) as **exactly the same ~26.6 degrees in every
pose**, regardless of how differently the knee/ankle were bending. A
bend-relative angle stays constant across totally different poses whenever
a chain segment is rigidly rebuilt from a fixed rest-pose offset relative to
its parent's corrected basis; only an *absolute* world-space angle actually
reflects the live, corrected pose (this is why the debug overlay reports
segment angles from world-down, not the bend relative to the previous
segment - see `_compute_leg_angles()`'s own doc comment).

The root cause traced back to `_derive_sole_down_local()`: it picked the
foot bone's local axis *closest* to rest-pose down out of the six cardinal
candidates (±X/±Y/±Z), rather than the exact direction. For this rig the
nearest axis was still `~26.6 degrees off` (`dot ≈ 0.894`). Since the toe
and leaf rest offsets are expressed in that *same* (slightly wrong) local
frame and get carried through the corrected foot basis every frame, that
26.6-degree quantization error was reproduced exactly on the toe and leaf -
a kink that had nothing to do with the actual rig geometry and everything
to do with rounding to the nearest axis.

**Fix**: use the exact rest-pose local-space direction of world down
(`rest_basis.inverse() * Vector3.DOWN`, normalized) instead of snapping to
a cardinal axis. Verified against the true "without IK" reference (disable
the modifier, read the raw animated pose) - the fixed WITH-IK result now
produces the *exact same* segment angles as the natural animation
(`foot=63.4°, leaf=90.0°` in the reference case tested), confirming the fix
reproduces the rig's real geometry instead of an axis-rounding artifact.

**Lesson**: when debugging a rig/IK correction, don't assume "looks flat on
screen" means "is flat" - a quantized reference axis can produce a
plausible-looking but subtly wrong result that then contaminates every
downstream bone reconstructed relative to it. Compare against a *measured*
ground truth (here: the unmodified animated pose with IK off) rather than
an assumed one (here: "the foot should look perfectly horizontal").

## Bug 3: fixing Bug 2 reintroduced toe-floor clipping

Bug 2's fix correctly restored this idle clip's natural toe-down stance
(previously an earlier version of the code had forced foot+toe+leaf
artificially flat/coplanar specifically to avoid this). But `ankle_offset`
(the ground clearance constant) was only ever tuned to keep the *ankle*
clear of the raycast hit point - once the toe was allowed to droop
naturally again, it could sink *below* the ankle's own clearance, clipping
through the floor. Visually this showed as the toe mesh ending in an
abrupt straight edge (the floor plane slicing through it), and numerically
as a negative `Toe Tip Y` in the debug readout.

**Fix**: `_compute_new_foot_basis_world()` depends only on orientation (the
animated foot pose and the desired down direction), not on the IK target
position - so it's safe to call *before* the position solve to predict how
far the toe would droop below the ankle, purely from orientation. Each leg
now uses `max(ankle_offset, predicted_toe_drop)` as its actual ground
offset, so whichever point (ankle or toe) needs more clearance determines
it - no second full IK solve required. A further `toe_tip_margin` constant
accounts for the toe *bone*'s origin sitting at the joint, not at the
visual mesh tip (bone origins are never at the fingertip/toetip mesh
extreme) - mirroring the debug overlay's own `TOE_TIP_EXTRA_LENGTH`
heuristic for its toe-tip marker.

## Debug tooling built along the way (all test-scene-only,
`tests/manual/foot_ik/foot_ik_debug_overlay.gd` and
`actors/player/player_skeleton_debug_visualizer.gd`)

- A `SkeletonModifier3D`-based skeleton visualizer, added to the production
  debug menu ("Show Skeleton" toggle) - draws every bone-to-parent segment
  as a camera-facing colored ribbon (`ImmediateMesh` + `no_depth_test`, so
  it renders through the mesh). Plain `PRIMITIVE_LINES` renders at a fixed
  1px regardless of material settings in Forward+, so segments are actual
  thin ribbon quads instead, and each bone gets a deterministic distinct hue
  (golden-ratio hue step off bone index) so adjacent segments in a chain are
  visually distinguishable.
- A live numeric readout grid (field/left/right columns with padding,
  replacing an earlier single long `key=value key=value...` line that ran
  off the edge of the screen once enough fields were added) plus floating
  `Label3D` angle readouts positioned at each bone segment's own midpoint in
  the 3D view - same numbers as the grid, but directly on the bone they
  describe. `Label3D`'s default `pixel_size` (0.01) is tuned for room-scale
  scenes; at this character's ~2m scale it rendered almost 30cm tall before
  reducing `pixel_size` to ~0.0007.
- `_compute_leg_angles()` reports each segment's own absolute angle from
  `Vector3.DOWN`, not the bend relative to the previous segment - see Bug 2
  above for why the relative version actively hid the real bug.
- The "IK Active" `CheckButton`'s built-in toggle glyph doesn't render at
  all in `--write-movie` headless capture (confirmed via a direct property
  check: `_ik.active` and `checkbox.button_pressed` were both correctly
  `true` while the on-screen toggle was visually blank) - don't trust a
  checkbox's *appearance* in a headless capture as proof of its state;
  check the underlying properties directly. Also made the state
  unmissable either way: large "IK ENABLED"/"IK DISABLED" text in
  green/red instead of relying on the small toggle glyph.
- The debug panel's own Tab-to-toggle-mouse-capture shortcut collided with
  Tab already being the project-wide `inventory` action - this scene's
  `Player` is a real, fully-wired instance, so `player.gd`'s own
  `_unhandled_input` handled the same keypress and opened/paused the
  inventory overlay on every press. Moved the panel's own shortcut to
  backtick (`` ` ``, `KEY_QUOTELEFT`), which has no existing binding.

## Bug 4: walking never lifted the feet - no stance/swing distinction

Idle on stairs looked correct, but walking didn't - the character's feet
never moved up/down at all during the gait cycle, sliding rather than
stepping. Diagnosed exactly the way the user suggested: capture N frames of
a real foot bone's world Y position while walking, once with the modifier
disabled (raw animation) and once enabled, and compare (a disposable driver
script pressing `move_forward` via `Input.action_press()` for N physics
frames, logging through the debug overlay's existing `BoneAttachment3D`
probes - see the project convention for this in `AGENTS.md`). Result:

| | foot Y range over 120 frames |
|---|---|
| IK off (raw animation) | 0.085 -> 0.355 (27cm swing) |
| IK on | 0.087 -> 0.087 (perfectly flat) |

Root cause: the modifier applied full ground-correction unconditionally,
every single frame, with no concept of gait phase. On flat ground the
raycast finds essentially the same ground height under the foot on every
frame of the cycle, so the leg got bent to plant there even while the
animation was trying to lift the foot through the air for a step - the
correction was fighting the animation's own swing arc and always winning.

**Fix (`swing_speed_threshold`, `_prev_animated_foot_pos`)**: blend the
actual IK target between the animated foot position and the full ground
target, weighted by how fast the *animated* (pre-IK) foot is currently
moving vertically - near-zero velocity (standing still, or momentarily
planted mid-step) gets full correction; real swing-phase velocity fades the
correction toward zero, letting the animation's own arc show through. The
foot's *orientation* is blended the same way (slerped between the animated
and ground-corrected quaternion by the same weight), not just its position,
so the ankle doesn't visually snap flat while airborne.

Two more bugs surfaced while building this, both instructive on their own:

- **First attempt used height (clearance from ground target), not
  velocity, and broke static stair-idle.** The reasoning seemed sound -
  "how far is the animated foot from the ground" - but this conflates two
  unrelated things: standing still on a *tall* step legitimately needs a
  *large* one-time correction, and a foot mid-swing is *also* far from its
  eventual ground target. Height alone can't tell them apart. Concretely:
  on the "Stairs 0.10m" platform's straddle stance, the natural idle rest
  height for both feet is nearly identical, but the two feet's ground
  targets differ by the 10cm step height - so the foot needing to reach the
  *upper* tread had a "clearance" larger than the threshold and never got
  corrected, even standing perfectly still. Velocity is the actual
  distinguishing signal: a foot that isn't currently moving vertically is
  either standing still or momentarily planted, and either way should get
  full correction regardless of how tall that correction needs to be; a
  foot actually swinging through the air has real measured vertical speed.
  Verify any "is this bone moving vs. reaching far" heuristic against a
  case where reaching far and not moving happen at the same time (a tall
  static step is exactly that case) before trusting it.

- **`SkeletonModifier3D._process_modification_with_delta()` gets called
  twice per physics tick** - once with `delta=0.0` (some internal
  reset/pre-pass), once with the real fixed delta. A velocity calculation
  that updates its "previous sample" on every call (including the
  `delta=0` one) ends up comparing the real-delta call against a same-tick
  duplicate sample, measuring zero movement on every single tick regardless
  of how fast the bone is actually moving - this reintroduced the exact
  same "perfectly flat" symptom as the original bug, just from a different
  cause, and needed the same before/after frame-log comparison technique to
  catch. Only update a per-frame "previous value" reference on calls where
  `delta > 0.0`, so consecutive samples used for a rate/velocity
  calculation are actually one physics tick apart.

Also re-confirms a general debugging lesson: multi-character test scenes
can make a single debug `print()` misleading. An early diagnostic added a
print statement directly inside the modifier - it fired for the real
player's legs *and* the seven static idle dummy characters on the other
preview platforms (every `PlayerBody` gets its own `PlayerFootIKModifier`
instance), all interleaved in the console output, and looked exactly like
one character's foot height bouncing wildly and chaotically between 0.08m
and 2.15m. It wasn't one character misbehaving - it was eight different
characters at eight different fixed platform heights, printing every
frame. Filtering to the real player specifically (`player_body.get_parent()
is Player`, since the static dummies are bare `PlayerBody.new()` instances
with no `Player` wrapper) revealed the actual, much saner per-character
trace.
