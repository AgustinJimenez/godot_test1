# CURRENT TASK: fix broken retargeted poses in UAL_EXTRA_CLIPS

Status: **checkpoint accepted for commit**. The crash, menu-close reset,
general body-pose retargeting, source loop modes, comparison camera, rest-facing
alignment, and swim preview height are fixed. The user confirmed this is good
progress worth saving. Exact hand/finger silhouettes are still unresolved in
some clips, notably `Pistol_Shoot`; do not describe that part as fixed. The
earlier hand-only, leg-swing, parent-relative swing, palm-frame, and finger-
direction attempts remain documented as failed approaches. One unrelated
pre-existing bug remains in the mirror double.

## Background

Added a debug menu (Esc → Debug → Animation Clips) that lazily retargets all 41
extra clips from the Universal Animation Library (`UAL1_Standard.glb`) onto
the player's MotusMan skeleton, grouped separately from the original
hand-picked "Default" clip set. User reported: "all of them have a weird
pose, in some the game even closes unexpectedly." Later also reported: after
picking a clip and closing the debug menu to look at it, it reverts to the
default idle animation instead of staying visible.

Three separate bugs were hiding under those reports. See below.

## Bug 1: engine crash — FIXED

Not a specific-clip bug. Godot 4.6.2 segfaults inside
`AnimationPlayer::_process_playback_data` when an `AnimationLibrary` already
attached to an `AnimationPlayer` is mutated (`add_animation`) while that
player is actively mid-crossfade. Reproduced reliably: clicking through **5
distinct new clips** in one live debug-menu session crashes every time,
regardless of which 5 clips (confirmed with several unrelated clip sets).
4 distinct clips never crashed; replaying the *same* clip 5x never crashed
(no new library mutation after the first). This points squarely at the
mutate-while-blending trigger, not clip content.

Root cause in `actors/player/player_body.gd`, `play_debug_anim()`: it called
`_lib.add_animation(...)` directly on the "moves" library that's already
registered on `anim_player` and playing/blending.

Tried and rejected: giving each clip its own fresh `AnimationLibrary` via
`add_animation_library()` instead of mutating the shared one — **still
crashed** at the 5th distinct clip. So it's not specifically about mutating
a *shared* library; adding *any* new library to a player that's mid-blend is
the trigger.

**Fix that worked:** call `anim_player.stop()` immediately before baking +
adding a new clip to the library, so the mutation always happens while the
player is idle, never mid-blend. Verified clean across all 43 clips
(Default + all UAL_EXTRA_CLIPS), several orderings, both `--headless` and
`--write-movie`. Trade-off: the *first* time a brand-new clip is requested
it hard-cuts instead of crossfading (tiny visual pop); every replay of an
already-cached clip still crossfades normally. Acceptable — debug-only
feature.

This is also noted in `CLAUDE.md` under Commands, since it's a genuine
engine-level gotcha worth not rediscovering.

## Bug 2: debug preview reverts when menu closes — FIXED

`update_motion()` (`player_body.gd`) runs every physics tick and drives
`anim_player.play(...)` based on real movement state. Closing the debug menu
overlay unpauses the tree, and on the very next physics tick `update_motion`
sees the player standing still/unarmed and stomps the preview clip back to
`relaxed_idle` — before the user gets a proper look at it.

**Fix:** added `var _debug_preview_active := false` to `player_body.gd`.
`play_debug_anim()` sets it true. `update_motion()` now checks it first: if
active AND the player is just standing still (not moving/crouched/armed),
it returns early and leaves the preview alone; the moment the player does
something that should visibly change the animation anyway (walks, crouches,
arms up), the flag clears and normal control resumes immediately. This
means closing the menu now keeps the debug clip looping until you actually
move, exactly what was asked for.

## Bug 3: broken/collapsed poses — ROOT CAUSE FOUND, FIX APPLIED, needs your confirm

### Methodology (useful for next time this kind of thing needs debugging)

First attempt used a side/rear demo camera holding each clip only 0.8s
before switching — **misleading**: most clips looked like a static "frozen"
idle because 0.8s only shows the transition-in, not the clip's actual
motion. Second attempt fixed that (front-facing camera, 2.4s hold) and is
what actually surfaced the real bug — the temporary `_anim_survey` harness
was deleted before the checkpoint commit.

The user's own suggestion mid-session — "debug it with an empty character" —
led to a further harness improvement: `_anim_survey.tscn` originally wrapped
the full `playground.tscn` (test room + a "fake mirror" double that puppets
a second `PlayerBody` copy, see `levels/debug_mirror.gd`). That mirror copy
doesn't get lazily-baked debug clips added to its own `AnimationPlayer`, so
every debug-clip preview was spamming `ERROR: Animation not found:
"moves/<clip>"` from `debug_mirror.gd`'s `_process` — a real, unrelated,
pre-existing bug, **not yet fixed** (see "Loose end" below), but confirmed
harmless to the retargeting investigation since it only affects the mirror
copy's own player, not the real one being screenshotted. Rebuilt
`_anim_survey.tscn` around just `player.tscn` + a plain floor (no room, no
mirror, no nav-mesh baking noise) — cleaner and faster to iterate on. Only
cosmetic downside: no `WorldEnvironment`, so captures are dim/moody. That's
fine for pose inspection.

Repro/capture commands (reusable — bare-player version):

```sh
CLIPS=(walk_relaxed A_TPose Idle Idle_Talking Idle_Torch Walk_Formal Jog_Fwd Sprint \
  Crouch_Idle Crouch_Fwd Jump Jump_Start Jump_Land Roll Pistol_Idle Pistol_Aim_Down \
  Pistol_Aim_Neutral Pistol_Aim_Up Pistol_Reload Pistol_Shoot Punch_Jab Punch_Cross \
  Hit_Chest Hit_Head Sword_Idle Sword_Attack Spell_Simple_Idle Spell_Simple_Enter \
  Spell_Simple_Exit Spell_Simple_Shoot Interact PickUp_Table Push Fixing_Kneeling \
  Sitting_Enter Sitting_Idle Sitting_Talking Sitting_Exit Driving Swim_Idle Swim_Fwd \
  Dance Death01)
godot --path . --write-movie /tmp/out/frame.png --fixed-fps 24 --resolution 960x540 \
  res://levels/_anim_survey.tscn -- "${CLIPS[@]}"
```

(zsh gotcha, bitten by this twice now: must be a real `CLIPS=(...)` array +
`"${CLIPS[@]}"`, a plain space-separated string does not word-split the way
it does in bash.)

Contact sheets assembled with a small Python/PIL script (no `drawtext`
ffmpeg filter on this machine, no `imagemagick montage` either — PIL is
what worked): resize each sampled frame to a thumbnail, paste into a grid,
`ImageDraw.text` the clip name underneath.

### What was wrong (confirmed, not just theorized)

Original leading theory ("`_swing_between`'s degenerate near-180° branch is
firing and picking a bogus fallback axis") was **tested and falsified**:
temporarily dumped `src_rest_dir.dot(src_pose_dir)` for `RightArm` across
`Pistol_Aim_Down`'s, `Pistol_Aim_Up`'s, `Pistol_Aim_Neutral`'s and
`Punch_Jab`'s full timelines. Dot product stayed in roughly the 0.0–0.4
range throughout (angle ~65–90°) for all of them — nowhere near ±1, so the
degenerate branch (`axis.length() < 0.0001`) never fires for these clips.
Also, per-clip variation was similar across Aim_Down/Aim_Neutral/Aim_Up,
meaning **the upper arm's swing barely differs between these three clips at
all** — pointing away from the arm-swing math entirely.

**Actual root cause:** `HELD_BONES = ["RightHand", "LeftHand"]` in
`player_body.gd` freezes the hand bones to a fixed pose (the walk cycle's
relaxed hand orientation) for every single UAL clip, no matter what that
clip is. This isn't an incidental choice — it's structural: the swing
retarget technique (`_swing_retarget`) needs a mapped *child* bone to
compute "which way does this bone point"; hands have no mapped child
(fingers are deliberately excluded from `BONE_MAP`), so there's nothing to
swing them by, and freezing was the fallback ("Not very noticeable at
typical camera distance for a walk cycle" — true for locomotion, false for
everything else). For a pistol-aim/punch/hit/spell-cast/death clip, the
**hand/wrist orientation is the primary visual content** of the clip (which
way the gun points, the fist angle, the impact reaction) — freezing it
erases exactly the part of the motion that made each clip distinct, which
is why Aim_Down/Aim_Neutral/Aim_Up/Reload/Shoot/Punch_Jab/Punch_Cross/
Hit_Chest/Hit_Head/Spell_Simple_Exit/Spell_Simple_Shoot/Death01 (13 clips)
all converged on looking like the same pose — the only part of them that
*was* being retargeted (shoulder/upper-arm/forearm swing) doesn't vary much
between these clips, and the part that does vary (the hand) was locked.

### Fix applied (not yet committed)

`const HELD_BONES: PackedStringArray = ["RightHand", "LeftHand"]` →
`const HELD_BONES: PackedStringArray = []` in `player_body.gd`. Since
`RightHand`/`LeftHand` were never entries in `SWING_BONES` to begin with,
removing them from `HELD_BONES` makes them fall through to the same
full-delta-rotation-transfer path already used for spine/legs (the `else`
branch in `_retarget_clip`'s pass 2) — no other code changes needed, this
was a one-line fix once the actual mechanism was understood.

**Verified via the front-facing/2.4s-hold contact-sheet survey (bare-player
scene) across all 43 clips:**
- The 13-clip broken cluster now shows meaningfully differentiated,
  plausible-looking poses (Aim_Up visibly more raised than Aim_Down/
  Neutral; Death01 shows a distinct collapsed/falling pose; Punch_Jab shows
  a fist-near-face punch pose; etc.) instead of one repeated pose.
- No regressions on the clips that were already working (locomotion,
  jump/roll, sword, dance, swim, A_TPose still shows a clean T-pose — the
  original "arms spread on full rotation transfer" failure mode that's why
  arms use swing in the first place does **not** reappear for hands, since
  the wrist has a much smaller rotational range than the shoulder/arm
  chain).
- No new crashes, no new "Animation not found" errors from the real
  player's own `AnimationPlayer`.

**This still needs your manual editor confirmation before it gets
committed** — automated frame review has been wrong before on this
project (see CLAUDE.md's standing rule).

## Bug 4 (separate, lower priority): Crouch_Idle/Crouch_Fwd/Sitting_* don't bend

Crouch_Idle, Crouch_Fwd, and all four Sitting_* clips still render as plain
standing in the survey, not crouched/seated. Not investigated yet. Likely
unrelated to the hand-freeze fix above — probably the Hips position
retarget (which only preserves a Y offset: `offset.x = 0; offset.z = 0`
computed from the source pelvis delta) isn't enough on its own, and/or these
particular UAL clips encode the crouch/sit mostly through leg-bone rotation
in a way that doesn't survive MotusMan's different leg proportions via the
plain delta-rotation transfer. Next step if picked up: dump the Hips Y
offset and RightUpLeg/RightLeg rotation delta across `Crouch_Idle`'s
timeline the same way the hand investigation did for `RightArm`, and see
whether the data is actually varying (bug is downstream/rendering) or flat
(bug is in what gets captured from the source).

## Loose end: `debug_mirror.gd` never gets lazily-baked clips (unrelated, not fixed)

Found while stripping the survey scene down (see Bug 3 methodology above).
`levels/debug_mirror.gd`'s `_process()` does
`dst_anim.play(src_anim.current_animation, 0.0)` on the mirror double's own
`AnimationPlayer`, assuming whatever the real player is playing already
exists there too. That's true for the original "Default" clip set (baked
into every `PlayerBody` at `_ready()`) but not for lazily-retargeted
UAL_EXTRA_CLIPS, which only ever get added to the *real* player's `_lib`.
Result: previewing any UAL debug clip while standing near test_room's mirror
prop spams `ERROR: Animation not found: "moves/<clip>"` every frame. Doesn't
crash, doesn't affect the real player's own animation — cosmetic/log-noise
bug on the mirror double only. Not fixed, not investigated further; flagging
so it doesn't look like a new regression if it shows up again. Likely fix
whenever it's tackled: either lazily retarget on `mirror_body` too when the
real body does, or have `debug_mirror.gd` guard the `.play()` call behind
`dst_anim.has_animation(src_anim.current_animation)`.

## Bug 3 update: user reports still broken live — built a 3-way live comparison rig

The DELTA_ROTATION fix looked right in offline `--write-movie` contact
sheets, but the user reports it's still broken when actually tested in the
editor. Rather than iterate on more screenshots (which have been misleading
before on this project), built a live side-by-side comparison instead, per
the user's own suggestion.

**`hand_retarget_mode` is now an `@export enum` on `PlayerBody`** (was a
`const HELD_BONES` array), so different scene instances of the same script
can run different retargeting behavior simultaneously:
- `FROZEN` (0) — original behavior, wrist locked to relaxed_idle's pose.
- `DELTA_ROTATION` (1) — the fix from earlier this session (full rest-relative
  global delta, same technique as spine/legs).
- `LOCAL_COPY` (2) — new third option: source hand's own LOCAL rotation
  applied directly under the target forearm's already-retargeted global
  pose, no rest-delta math at all.

`levels/_pose_compare.gd` + `.tscn` (retained in the checkpoint while the
remaining hand/contact mismatch is investigated):
three `PlayerBody` copies side by side (`res://levels/_pose_compare.tscn`),
one per mode, all playing the same clip at once. Free-fly camera (click to
capture mouse, WASD move, Q/E down/up, Esc to release), number keys 1-9
switch clip across a preset list biased toward the previously-broken
cluster: Pistol_Aim_Down/Up/Neutral, Pistol_Reload, Punch_Jab, Hit_Head,
Spell_Simple_Shoot, Death01, Crouch_Idle. Open the scene in the editor and
hit Play (F6) to try it interactively — this is what's pending the user's
judgment now.

**My own quick look at a `--write-movie` capture of it (Pistol_Aim_Down,
default clip) already shows something important, independent of whatever
the user decides between the two hand modes:**

- `LOCAL_COPY` is visibly *worse* than either alternative — the hand mesh
  clips badly into the head/helmet, clearly broken. Likely cause: the two
  rigs' local bone axis conventions for the wrist don't match closely
  enough for a raw local-rotation copy to be valid (same category of
  problem that pushed the arm chain to swing-based retargeting in the first
  place, just now hitting the hand instead). Not a promising direction
  without more work (e.g. a fixed corrective rotation offset between the
  two rigs' rest wrist orientations) — deprioritize unless FROZEN and
  DELTA_ROTATION both get rejected too.
- `FROZEN` and `DELTA_ROTATION` do show a real difference in hand
  position/orientation (frozen tucks the hand in near the collar;
  delta-rotation extends it up and out) — so the hand-freeze fix is doing
  *something* real, it may just not be the (or not the only) thing making
  the pose look wrong to the user.
- **Critically: all three variants show the identical body lean + one leg
  lifted off the ground.** Hand retargeting mode has zero effect on this.
  That means whatever's driving the sideways lean and the raised leg is a
  *separate* mechanism entirely — most likely the spine/hip delta-rotation
  transfer or the Hips Y-offset logic, not anything about the arms/hands at
  all. If none of the three hand modes look "right" to the user, this lean/
  leg-lift is probably the next thing worth isolating with its own
  live-comparison rig (e.g. vary how the Hips offset or spine delta is
  computed, the same way this rig varies hand_retarget_mode) rather than
  continuing to iterate on hands.

## Bug 3 update 2: found the real dominant cause - it's the legs, not the hands

User pushed back on the hand-only fix ("still broken") and asked to see the
skeleton, not the mesh - good call, it's much easier to read. Screenshot of
the 3-way rig (all still showing default leg_retarget_mode at the time)
confirmed: **all three hand-mode variants show the identical sideways lean
+ one leg lifted off the ground.** Hand mode has zero effect on this, so the
thing making the pose look "weird" was never primarily about hands.

**Verified the source data is fine first**, before touching any more code:
built `levels/_raw_ual_check.gd`/`.tscn` (temporary, deleted before checkpoint) -
plays a UAL clip on its own native (Unreal Mannequin) skeleton, completely
unretargeted. `Pistol_Aim_Down` on the raw skeleton is a normal, controlled
hunched-forward aim-down pose - no sideways lean, no leg lifted off the
ground. **So the lean/lift is being introduced by our retargeting, not
present in the source.**

Instrumented the spine/hip/leg delta-rotation path (the same `else` branch
in `_retarget_clip` that handles everything not on the swing path) with a
temporary print of each bone's delta rotation as Euler degrees. Hips/Spine1/
Spine2 deltas looked like reasonable bend angles. **`RightLeg` (the knee)
showed a delta of `(8.2, 58.9, 11.2)` degrees at the settled pose - a ~59
degree rotation on what should be a near-pure hinge axis.** A real knee
doesn't need 59 degrees of secondary-axis "twist" to bend forward; that's
the same rig-local-axis-mismatch problem that originally pushed arms onto
swing-based retargeting (see `SWING_BONES`'s doc comment: "full rotation
transfer kept spreading the arms into a T-pose"), just not exposed until a
clip bends the knee far more than a walk cycle ever does.

**Fix applied, mirrors the hand-mode pattern exactly:** added
`leg_retarget_mode` (`@export enum`, `DELTA_ROTATION` / `SWING`) and
`LEG_SWING_MAP` (`RightUpLeg`->`RightLeg`->`RightFoot`, mirrored for Left) to
`player_body.gd`. `SWING` reuses the exact same `_swing_retarget()` already
used for arms, just applied to the leg chain instead. Default is
`DELTA_ROTATION` (unchanged behavior) so nothing about default/real-gameplay
retargeting changed by adding this - it's opt-in per instance, same as hands.

`levels/_pose_compare.tscn` was reshuffled from "3 hand modes" to a clearer
before/after progression, all at `hand_retarget_mode = DELTA_ROTATION`
(the earlier fix) except the baseline:
- **ORIGINAL** - `hand=FROZEN, leg=DELTA_ROTATION` (fully original behavior)
- **HAND FIX ONLY** - `hand=DELTA_ROTATION, leg=DELTA_ROTATION` (what the
  user already said still looked broken)
- **HAND + LEG FIX** - `hand=DELTA_ROTATION, leg=SWING` (new)

Also fixed while rebuilding this: mesh is now hidden and each body's
skeleton is drawn as thick colored line segments (red=right, blue=left,
white=spine/other) via a per-frame `ImmediateMesh` rebuild, camera-facing
quads instead of 1px `PRIMITIVE_LINES` (Forward+ has no real line-width
control) - much easier to actually read joint rotations than squinting at
mesh silhouettes. Black floor/background. `cull_mode = CULL_DISABLED` on the
gizmo material was required - inconsistent winding relative to the camera
was making segments randomly invisible before that.

**My own quick look**: HAND+LEG FIX no longer shows the sideways lean/twist
- that specific artifact is gone. But the left leg now extends unusually
far back/down in a way I can't confirm is correct or a new artifact from a
single static screenshot - could be a genuine wide "shooting stance" foot
stagger in the source clip that just wasn't visible from the front-on raw
check angle, or could be swing exposing a different problem. **Needs the
user's live judgment in the editor, walking around it in 3D** - exactly why
this comparison rig exists instead of continuing to guess from screenshots.

To try it: open `res://levels/_pose_compare.tscn`, press F6 ("Play Current
Scene" - NOT the main F5 Play button, which runs the real game and won't
show this). Click to capture mouse, WASD to move, mouse to look, Q/E for
down/up, Esc to release, number keys 1-9 to switch clip (list is
`_pose_compare.gd`'s `CLIPS` constant, biased toward the previously-broken
cluster).

**Note (superseded):** the paragraph above about line-segment gizmos (thick
`ImmediateMesh` quads) describes an intermediate iteration that was later
replaced. See "Bug 3 update 3" below for the current, better approach (real
per-vertex mesh coloring) and the final state of `_pose_compare.tscn`.

## Bug 3 update 3: mesh limb coloring, a 5th ground-truth reference body, and the actual remaining bug

User asked to see actual mesh coloring (not line overlays - "they blend
together sometimes with the torso"), then asked for the raw/native pose to
be visible as a live reference character, then pushed on whether the fix
was real ("I don't see a fixed animation pose"). Each of these led somewhere
real:

**Mesh limb coloring, done properly.** First attempt: a custom vertex()
shader reading `BONE_INDICES`/`BONE_WEIGHTS` at draw time - came back empty
for most vertices (Godot 4.6 Forward+ appears to skin in a separate pass
before a custom vertex() runs). Working approach instead: bake a color into
every vertex once, in GDScript, from the mesh's own skin arrays
(`Mesh.ARRAY_BONES`/`ARRAY_WEIGHTS`, read via `surface_get_arrays()`), using
whichever bone influences each vertex most, then write it into
`Mesh.ARRAY_COLOR` and rebuild the surface with `add_surface_from_arrays()`.
Applied via a plain `StandardMaterial3D` with `vertex_color_use_as_albedo`.
Hit one real bug along the way: `ARRAY_BONES` values are indices into the
`MeshInstance3D`'s own `Skin` resource, not directly into the `Skeleton3D`'s
bone list, and this particular skin turned out to be **name-bound**
(`Skin.get_bind_bone()` returned -1 for every single entry) - had to resolve
via `Skin.get_bind_name(bind_idx)` + `Skeleton3D.find_bone(name)` instead.
Color scheme: red = right limbs, blue = left limbs, green = torso
(Hips/Spine/Spine1/Spine2), pink = head (Neck/Head), gray = anything else.
Also found and removed a "white pole" artifact - a stray tube/segment was
being drawn from Hips to ITS OWN parent (a root/control bone at ground
level), not a real body part.

**A 5th reference body was added: the raw UAL source, unretargeted, on its
own native skeleton**, playing the same clip as the other four
simultaneously (`levels/_pose_compare.gd`'s `raw_ref` / `_raw_ap` / `_play_raw_clip()`).
This is the actual ground truth the retargeted variants are trying to
reproduce - and comparing against it immediately showed something important:
**even HAND + LEG FIX doesn't match it.** The raw source is a controlled
forward hunch with legs nearly straight and together; HAND + LEG FIX produces
a wide lunging stance instead. So the leg-swing fix, while it removed a real
artifact (see update 2), is *overcorrecting* - there's still a genuine gap.

**Diagnosed the overcorrection, methodically, ruling out wrong theories
before landing on the right one:**

1. First checked whether `Pistol_Aim_Down` is actually a long, evolving
   animation (the earlier ~59 degree "settled" delta looked like it came from
   many samples). It's not - **`anim.length` is 0.1667s, `loop_mode = 0`
   (no loop)**. It's a quick snap into a held pose, not a multi-second clip.
   Checked directly: `var anim := lib.get_animation(clip_name); print(anim.length, anim.loop_mode)`.
2. Measured the *actual* relative knee-bend angle (angle between the
   thigh-to-knee direction and knee-to-ankle direction) using Godot's own
   **live, trusted** `Skeleton3D.get_bone_global_pose()` on the raw
   reference body while it's actually playing (not the offline bake) -
   **only ~14 degrees.** Confirms visually: the source leg is nearly
   straight, not deeply bent.
3. This seemed to contradict the ~59 degree *world-space* rotation delta
   `_swing_retarget` computes for the calf. Suspected a bug in
   `_manual_global_pose`'s hand-rolled parent-chain composition (used during
   offline baking to work around `get_bone_global_pose()`'s cache staleness -
   see that function's doc comment). **Tested directly: added
   `src_skeleton.force_update_all_bone_transforms()` after posing, then
   compared `_manual_global_pose()`'s output against the engine's own
   `get_bone_global_pose()` for the exact same bone/pose. They matched
   bit-for-bit** (`manual_origin=(-0.170273, 0.511209, -0.131942)` ==
   `engine_origin=(-0.170273, 0.511209, -0.131942)`, same for the basis
   euler angles). **`_manual_global_pose` is correct. Not the bug.**
4. So the ~59 degree number itself is *real* - it genuinely is how much the
   calf bone's world-space orientation changed from T-pose rest to this
   pose. It's just measuring something different from "relative knee bend":
   a **world-space delta compounds the whole parent chain** (hip lean +
   thigh rotation + any actual knee flex all add up into the calf's total
   change from rest), while the 14-degree number is purely the local joint
   angle. Both numbers are individually correct; they answer different
   questions.
5. **The actual bug is architectural, in `_swing_retarget` itself:**
   `target_basis = swing * target_rest.basis` applies the source bone's
   *absolute world-space* rotation delta directly onto the target's own
   rest basis, with no reference to what the target's *parent* bone actually
   ended up retargeted to. Compare to the non-swing branch used for
   spine/hips, which composes the opposite way -
   `target_rest.basis * delta` (local/rest-space, not world-space). For a
   bone low in a chain that's had a lot of *parent* rotation applied (hip
   hinge → thigh → calf), applying an absolute world delta instead of a
   parent-relative one loses the fact that the target skeleton's parent
   chain may have already absorbed part of that rotation differently than
   the source's did - the error doesn't show up for arms (where this
   session's testing never stressed a heavily pre-rotated parent chain hard
   enough to expose it) but does for a leg swinging under a hip that's bent
   forward significantly, like this clip.

**Not fixed yet.** This needs `_swing_retarget` reworked to compose relative
to the target parent's *already-retargeted* global orientation rather than
an absolute world-space delta - a real, nontrivial change to core
retargeting math, not a quick patch. Have not attempted this yet.

**Also researched: is Godot's own built-in humanoid retargeting
(`SkeletonProfileHumanoid` + `BoneMap`, added in 4.0) a way out of this
entire class of bug?** Yes, conceptually - it unifies both skeletons' rest
poses at import time, which is the root cause behind every bug found this
session (arm T-spread, hand freeze, this knee/world-space issue). But:
confirmed via web research that this is fundamentally an **interactive
Advanced-Import-Settings-dialog workflow**, and even the Godot community
reports that automating `BoneMap` assignment via `EditorScenePostImportPlugin`
in headless mode is unreliable as of 4.6. This agent only has headless CLI
access, no editor GUI, so it cannot drive that dialog directly. Checked for
a Godot MCP server that might bridge this gap - several community ones exist
(Coding-Solo/godot-mcp, mkdevkit/godot-mcp, Dokujaa/Godot-MCP, GDAI MCP,
Godot MCP Pro) but none were confirmed to expose that specific dialog's
functionality, and installing one is a real environment/trust decision that
needs the user's explicit go-ahead, not something to do speculatively.
**If the user wants to pursue the built-in system, it would need to be done
by them, interactively, in the editor** - this agent can write exact
step-by-step instructions for that (BoneMap on UAL as AnimationLibrary +
BoneMap on MotusMan as Scene, both mapped to `SkeletonProfileHumanoid`;
UAL is confirmed T-pose so "Fix Silhouette" shouldn't be needed) if that
path is chosen instead of continuing to fix the hand-rolled retargeting code.

`levels/_pose_compare.tscn` now has 5 bodies: ORIGINAL, HAND FIX ONLY,
HAND + LEG FIX, T-POSE (reference), RAW SOURCE (unretargeted, native
skeleton, ground truth). Mesh coloring (not line gizmos) on all of them.
Camera is close-in by request; T-pose arms and the raw reference's own body
shape may crop at the edges depending on which clip is selected - free-fly
camera lets the user reposition.

## Bug 3 update 4: tried the parent-relative swing rework - failed twice, reverted

User said go ahead with the fix from update 3's diagnosis. Two attempts,
both made things worse than the original world-space swing (not just
"still wrong" - actively broke poses that were previously fine, e.g. arms).
Both reverted. `_swing_retarget` is back to its exact original form
(world-space, no `target_global` parameter) - same code as at the start of
update 3.

**Attempt 1: algebraic decomposition.** Tried to isolate "the child's own
local rotation" by computing `src_parent_delta` (a `Basis` representing how
much the source parent rotated from rest to pose) and dividing it back out
of the full swing via `child_local_swing = swing * src_parent_delta.inverse()`,
then reapplying via `child_local_swing * target_parent_delta * target_rest.basis`.
**Broke immediately and badly** - arms that were previously fine (ORIGINAL,
HAND FIX ONLY - neither even uses leg swing) started shooting out sideways
past the frame edge. Root cause: `_swing_between()` only returns a rotation
guaranteed to satisfy the *one specific direction vector* it was built from
(that's the whole point of "swing," it has no defined twist/roll component).
Treating its output as a general `Basis` and algebraically composing/
decomposing it with other bases (`swing * src_parent_delta.inverse()`) is
not a valid operation - the equation `swing * v = child_local_swing * src_parent_delta * v`
holding for one vector `v` does NOT imply `swing = child_local_swing * src_parent_delta`
as bases (that only holds if fully constrained across 3 independent
directions, which a single-vector "shortest arc" rotation never is).

**Attempt 2: direction-vector reframing (more careful, still failed).**
Avoided the algebra bug above by working only with direction vectors
(always a valid operation): express the child's rest/pose direction "as
seen from inside its parent's own local frame" via
`parent_basis.inverse() * direction`, at rest-time and pose-time
respectively, using the SOURCE parent's rest and pose bases. Any difference
between those two "as-seen-from-parent" directions is the child's own joint
bend with the parent's rotation divided out. Reapplied that isolated bend
under the TARGET parent's own actual retargeted basis (read from
`target_global`, available since Pass 2 processes bones parent-first) the
same way. This is mathematically sound as *direction transforms*, but
**still broke the arms differently** (an arm shot straight up instead of
sideways this time) - because expressing a direction "in the source
parent's local frame" and then reapplying that same numeric result "in the
target parent's local frame" silently assumes **both skeletons' parent
bones share the same local axis convention** (which local axis is
"forward"/"toward the child" for that specific bone). They don't - that's
the exact same rig-authoring-convention mismatch that made full rotation
transfer spread the arms into a T-pose in the very first version of this
retargeting code, and made swing (position/direction-based, convention-
agnostic) necessary in the first place. Reintroducing a parent-local-frame
step reintroduces the same problem one level up the chain.

**Why this is a genuinely hard problem, not a quick fix:** the tension is
between two things that are each individually necessary but pull in
opposite directions - (a) swing needs to stay in WORLD space to avoid the
axis-convention-mismatch that breaks full rotation transfer, but (b) staying
in world space is exactly what causes a low-chain bone (knee) to inherit and
double-count its ancestors' own rotation when a clip pre-rotates the parent
chain a lot (hip hinge bend). Godot's own built-in retargeting system
(`SkeletonProfileHumanoid`/`BoneMap`, see update 3) solves this properly by
*unifying both skeletons' rest orientations to a common reference* before
any animation is applied, which eliminates the axis-convention mismatch at
its root instead of working around it per-bone at retarget time - which is
why that's still the more durable answer if the user wants to pursue it,
even though this agent can't drive that workflow itself (see update 3).

**Do not re-attempt a parent-relative rework of `_swing_retarget` with
either of these two exact approaches** - both are proven dead ends now, not
just untried ideas. A genuinely different approach would be needed (e.g.
one that only accounts for the parent's rotation along the specific axis
that's shared/meaningful between both rigs, rather than a full parent-local
reframing) - not attempted, not designed, would need real thought before
touching the code again.

## Bug 3 update 5: replaced hand-rolled transfer with Godot's retarget formula - candidate fix

The remaining failure was not a leg-specific swing problem. Wider checks
showed the same hand-rolled transfer also lost crouch/sitting depth and made
collapse poses float. Continuing to patch `_swing_retarget` bone-by-bone was
the wrong level of fix.

Godot 4.6 ships `RetargetModifier3D`. Its exact local-pose formula is public
in the engine source and can be run synchronously while this project bakes an
`Animation`, without changing import settings or renaming every MotusMan FBX:

```
target_pose = target_parent_global_rest^-1
              * source_parent_global_rest
              * source_pose
              * source_rest^-1
              * source_parent_global_rest^-1
              * target_parent_global_rest
              * target_rest
```

Implemented that formula in `_humanoid_retarget_local_pose()` and made it the
default `_retarget_clip()` path via `use_humanoid_retarget = true`. Position
deltas use the same parent-rest conversion and a target/source hip-height
ratio. The old delta/swing modes are temporarily retained only for the live
comparison rig; they should be removed after manual confirmation.

Why this works where the two update-4 attempts failed: it never assumes the
source and target parent bones share local axes. It explicitly moves the
source local pose through the source parent's global rest frame and then into
the target parent's global rest frame. This is the missing rest-pose
normalization the built-in importer/retargeter is designed to provide.

Verification completed:

- Headless main-scene smoke test passes (only the pre-existing ObjectDB leak
  warning on forced early exit).
- All 43 clips baked and played sequentially in one live AnimationPlayer
  session with no crash and no missing-animation errors.
- Recorded side-by-side checks against RAW SOURCE for Pistol_Aim_Down,
  Pistol_Aim_Up, Crouch_Idle, Sitting_Idle, Punch_Jab, Death01, and Walk:
  the new body preserves the source action and limb structure. Crouch and
  Sitting now bend/lower; Death01 collapses instead of floating; Walk and
  Punch_Jab retain the source pose rather than the repeated broken stance.
- The comparison scene was simplified to the two references that matter:
  `RETARGETED - MOTUSMAN` and `RAW SOURCE - UAL`, both using their normal
  materials. An on-screen dropdown lists every supported UAL animation and
  plays the selection on both bodies. `Walk` is translated to the gameplay
  animation name `walk_relaxed` on MotusMan while the source still plays
  UAL's original `Walk` clip. Click empty viewport space to capture the
  free-fly camera; use WASD, Q/E, mouse look, and Shift for faster movement;
  Esc releases the mouse so the dropdown can be used again.
- Retargeted debug clips preserve the raw source animation's `loop_mode`, so
  one-shot poses stop on both bodies and looping clips loop on both. Only the
  gameplay `walk_relaxed` bake explicitly forces `LOOP_LINEAR`. The comparison
  scene also uses a zero-second blend when switching, because several UAL pose
  clips are shorter than the normal debug menu's 0.2-second crossfade.
- Finger chains are now mapped joint-for-joint (`index`, `middle`, `ring`,
  `pinky`, and `thumb`, both hands). They were previously omitted, which made
  retargeted clips fall back to MotusMan's curled rest fingers even when UAL
  supplied open/pointing finger tracks. Representative UAL clips contain real
  finger motion (about 87-108 degrees from source rest) and now bake through
  `_humanoid_retarget_local_pose()` like every other mapped bone.
- `Pistol_Shoot` exposed a remaining hand-silhouette problem. Matching the
  source rotation delta produced different visible bends because the rigs have
  different rest geometry. A follow-up anatomical palm/finger-direction pass
  made measured joint bends match within 0.001 degrees and survived the full
  43-clip sweep, but the user confirmed the rendered hands still looked the
  same. That pass was removed before this checkpoint. Numeric skeleton
  agreement does not prove matching skinned-mesh silhouettes or preserve a
  two-hand/prop contact; a future fix needs bind-pose/skin inspection and
  likely explicit hand or prop contact constraints, not more rotation metrics.
- `Sword_Idle` exposed an apparent body-yaw mismatch in an oblique camera view.
  Numeric checks showed its settled animation-relative yaw differed by only
  about 1.31 degrees; the rigs' anatomical rest-facing directions were already
  7.42 degrees apart, while UAL's `root` tracks were static. The comparison
  scene now derives that baseline from hips/head/shoulder rest positions and
  rotates only `RAW SOURCE - UAL` to MotusMan's facing (verified 0-degree
  post-alignment error). Do not bake this offset into gameplay animation data.
- `Swim_Idle` and `Swim_Fwd` pose the body horizontally around a ground-level
  skeleton origin, which put most of both meshes below the comparison floor.
  `_pose_compare.gd` applies the same 1.35 m display-only lift to both swim
  models and counter-offsets their labels. This changes only presentation in
  the throwaway comparison scene, not either animation or gameplay transform.

The user authorized a checkpoint commit with the remaining hand limitation
documented. Keep `_pose_compare.tscn` available for continuing that work.

## Next steps (pick up here)

1. Open `res://levels/_pose_compare.tscn` and press F6. Use the animation
   dropdown to play the same clip on `RETARGETED - MOTUSMAN` and
   `RAW SOURCE - UAL`. Click empty viewport space and free-fly around them to
   compare each pose from multiple angles; press Esc to return to the menu.
2. Also test the main game live: unarmed walking uses the newly retargeted
   `walk_relaxed` path by default. Confirm it reads naturally at gameplay
   speed and from both first- and third-person debug cameras.
3. Continue the known hand mismatch with `Pistol_Shoot`. Inspect the source and
   target bind poses/skin weights and treat the two-hand grip as a contact or
   IK problem. Do not restore the rejected palm-frame/finger-direction pass or
   return to either failed parent-relative swing approach from update 4.
4. After the remaining poses are accepted, remove the legacy hand/leg mode
   enums and branches, leaving `_humanoid_retarget_local_pose()` as the sole
   retarget path. Delete `_pose_compare.gd`/`.tscn` only when it is no longer
   needed for manual comparison.
5. If the user wants it addressed: `debug_mirror.gd` loose end — see fix
   options above.

## Web research

- [Retargeting 3D Skeletons — Godot Engine (stable) docs](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html) -
  full workflow for `SkeletonProfileHumanoid` + `BoneMap`: import source
  animation as AnimationLibrary with BoneMap, import target mesh as Scene
  with its own BoneMap (same profile type), both get auto-mapped by common
  English bone names, "Overwrite Axis"/Unify Bone Rest is "the most
  important option for sharing animations in Godot 4". "Fix Silhouette"
  only needed for A-pose sources (UAL is T-pose, per `A_TPose` clip, so
  shouldn't be needed here).
- [SkeletonProfileHumanoid — Godot Engine (stable) docs](https://docs.godotengine.org/en/stable/classes/class_skeletonprofilehumanoid.html)
- [Animation Retargeting in Godot 4.0 – Godot Engine blog](https://godotengine.org/article/animation-retargeting-in-godot-4-0/)
- Community consensus (Godot forum, GitHub) as of 4.6: scripting `BoneMap`
  assignment through `EditorScenePostImportPlugin` in a headless pipeline is
  reported as difficult/unreliable - this is an interactive-editor-only
  workflow in practice.
- Godot MCP servers found to exist (not installed, not evaluated further):
  Coding-Solo/godot-mcp, mkdevkit/godot-mcp, Dokujaa/Godot-MCP, GDAI MCP,
  Godot MCP Pro. None confirmed to expose Advanced Import Settings /
  BoneMap assignment specifically.
before acting on them.
