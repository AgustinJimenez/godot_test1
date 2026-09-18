# Procedural walk experiment: findings and next steps

This is the focused record for the independent MotusMan walk prototype in
[`tests/manual/procedural_walk/procedural_walk_lab.tscn`](../tests/manual/procedural_walk/procedural_walk_lab.tscn).
For the broader Godot animation survey, see
[`PROCEDURAL_ANIMATION_RESEARCH.md`](PROCEDURAL_ANIMATION_RESEARCH.md). For the stair locomotion
decision and gameplay integration context, see
[`AGENT_TASKS/031_stair_locomotion_strategy.md`](../AGENT_TASKS/031_stair_locomotion_strategy.md).

## What exists now

The scene runs MotusMan with a separate `SkeletonModifier3D`. Its **Original** mode generates a
leg gait plus small pelvis, spine, and arm motions from a frozen relaxed-idle pose. Six new
reference-derived modes—UAL walk, MotusMan aim-walk, UAL sprint, UAL crouch-walk, Mixamo stair-up,
and Mixamo stair-down—sample the repository's existing clips on the MotusMan rig. All four flat
reference modes copy all 73 source bone poses and apply only a small whole-body vertical
floor-clearance shift. The two stair modes still apply an independent leg/plant solve because their
clips do not align with this scene's stairs. This is a **hybrid animation prototype**, not
fully generated whole-body motion or a new editable gait profile. A separate optional character
plays the raw source clip beside it for comparison. The UAL clips are retargeted onto a private
sampler rig; retargeting against the live lab skeleton had silently changed its frozen base pose.

The lab does **not** spawn `Player`, use gameplay Foot IK, or alter the other agent's stair work.
Its scripted moving path and visible staircase are visual test geometry, not a physics controller.
Flat moving modes continue indefinitely; stair traversals still stop where their finite stair
geometry ends. Flat reference gaits now derive forward speed from how fast a near-floor foot moves
backward through its planted phase, scaled by each clip's cadence. Sprint therefore moves much
faster than walk; the Original gait keeps its explicit world-space foot lock, while stair modes
keep their terrain-matched scripted path. These are measured in-place-clip estimates, not authored
root-motion data or a guarantee of zero shoe slide.

The camera starts beside the character and can still orbit freely. The controls are: mouse drag to
orbit, wheel to zoom, Space to pause, Left/Right to step frames,
and a 120-frame timeline to scrub two in-place cycles. Interactive launch now starts with the
**Original** gait moving forward; uncheck **Move forward + lock planted feet** for in-place playback.
Switching flat gaits keeps moving mode on and restarts the path. Reset walk also restarts it. The
control panel reserves space for changing joint/readout
numbers so its size does not jump during playback. In flat reference
modes it
explicitly says "no foot lock" because preserving the source leg pose takes priority over a
separate plant solve. The camera follows the moving character while an 80 m floor and one-meter grid
recenter in whole-meter increments; the world-space grid pattern remains visually continuous.
Moving mode can pause and step forward, but cannot scrub
backward because foot-plant history is stateful; switch back to in-place mode for arbitrary frame
scrubbing. The gait selector activates one source at a time; selecting stair-up/down automatically
starts a real-height stair traversal (four 0.18 m risers, 0.35 m tread depth). A checkbox reveals
the source actor for an A/B view. Colored hip/knee/ankle/toe markers, knee angles, the worst
per-frame joint rotation and the largest current source-pose difference are shown in the panel.
Step rate, foot travel, lift, blend, and arm swing have temporary sliders. Their settings are not
saved. The first 240 physics frames after each mode selection are also written to bounded
`user://procedural_walk_metrics_<mode>.jsonl` logs. Every record includes per-joint pose error,
procedural/source rotation step, knee flex, ankle target error, root position, and gait phase.

Current default parameters are approximately:

| Parameter | Value | Meaning |
| --- | ---: | --- |
| Step rate | 1 cycle/s | Two complete cycles in the 120-frame timeline at 60 fps |
| Foot travel | ±0.20 m | Front/back target relative to the body; moving stance uses a fixed world target |
| Maximum foot lift | 0.13 m | Swing-foot vertical arc |
| Swing fraction | 40% | Remaining 60% is the support/stance phase |
| Pelvis drop | 0.04 m | Keeps knees flexed at contact |
| Arm swing | 0.22 rad | Small opposing arm motion |

If we create many procedural gaits, these parameters and curves should become separate, editable
Godot `Resource` profiles (for example walk, sprint, crouch-walk), read by one shared gait system.
That profile system does **not** exist yet. Exact replay of a real animation remains an `Animation`
resource; extracting its foot/pelvis/arm trajectories into reusable gait curves would be a separate
tool. The six new modes currently depend directly on the sampled reference poses, especially for
upper-body motion.

## What the iterations taught us

1. **Direction depends on the source rig.** MotusMan's native forward is `+Z`; the scene rotates
   its visual root by 180 degrees, making its world forward `-Z`. The first foot trajectory ran
   backward until the swing travel was reversed. The lab check now verifies frontward travel.
2. **A knee can flip even when the ankle target is continuous.** The first solver projected the
   nearly straight idle knee onto the hip-to-ankle line to choose a bend direction. That projection
   crossed zero during the cycle, flipping the knee plane. The repeatable one-frame jump was about
   48–52 degrees. A stable anatomical forward bend direction removed it; the subsequent maximum
   was about 8.4 degrees/frame.
3. **Reach and landing timing are coupled.** The long initial stride and high pelvis drove the
   landing leg almost straight before the foot settled. A shorter default stride, a small pelvis
   drop, a swing arc with zero vertical speed at the endpoints, and a reachable ankle target brought
   the measured maximum down to about 3.3 degrees/frame. Reducing the jump alone was not enough:
   visually, the foot still seemed to arrive after the knee had extended.
4. **Contact needs its own phase, not just a sine wave.** The current gait reaches the front plant
   earlier (frame 24 for the left foot, frame 54 for the right), then holds the toe at the same
   vertical level during stance while the foot moves backward relative to the in-place body.
   At those frames the measured knee flex is about 27.8 degrees left and 21.6 degrees right;
   the largest joint rotation is about 4.3 degrees/frame and the largest knee-flex change about
   6.5 degrees/frame. Before touchdown the toe is measurably above its planted level.
5. **A flat local stance height is not a foot plant.** In moving mode, each foot captures a
   world-space ankle position at touchdown and retains it through stance. The next swing starts
   from that exact world point and aims ahead of the predicted root at the next touchdown. At the
   default settings, a three-second headless walk traveled 2.00 m, took 144 planted-foot samples,
   and measured zero ankle-to-plant drift at its printed precision; the worst joint change was
   4.58 degrees/frame. This shows the planted **ankle target** is stable, not that the rendered
   shoe is visually perfect or free of floor penetration.

Run the bounded headless check with:

```sh
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --lab-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --moving-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --reference-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --profile-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --stair-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --toe-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --pose-match-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --flat-mesh-check
godot --headless --path . res://tests/manual/procedural_walk/procedural_walk_lab.tscn -- --infinite-check
```

The in-place check covers direction, joint movement, the complete cycle including its seam, knee
bend at contact, contact target error, and toe height before/after contact. The moving check covers
forward root travel, planted-ankle world error, and joint continuity. The new checks verify all six
references have distinct arm motion, all six hybrid modes stay below 20 degrees of rotation per
frame across a full loop, and both stair paths traverse 0.72 m with planted ankles remaining on
target. The imported stair-down clip itself has a ~63-degree single-frame leg jump at mid-cycle;
smoothing the derived leg/shoe reference over nearby samples reduces the hybrid output's worst
frame from 43.4 to 14.4 degrees without altering the raw comparison actor. Upper-body pose
difference against the reference is under 1.1 degrees across the sampled cycles. `--contact-report`
prints a short per-frame toe/ankle/knee trace for diagnosis. `scripts/check.sh` also passes. These are
**headless measurements, not a confirmed visual verdict**. In particular, the reported `ToeBase`
position is a bone origin, not the lowest skinned shoe vertex; it cannot by itself prove that the
rendered sole touches or does not penetrate a tread. The surfaces are visual-only in this lab.
`--infinite-check` advances Original plus all four flat reference gaits beyond 15 cycles, verifies
their travel matches the extracted stride, Sprint is over twice Walk's speed at native cadence,
moving mode survives gait selection, the floor/reference follow, and the panel remains the same size.

For UAL walk, the initial independent leg gait left both shoes >0.09 m above the plane in some
frames, even after its toe penetration was fixed. It was a phase mismatch, not a clearance issue.
All four flat modes now preserve their complete source poses. `--pose-match-check` compares **all
73 joints on every frame** of the loop, both in-place and moving: UAL walk's worst rotation
difference is below 0.07°; aim-walk, sprint, and crouch remain under 1.8° with relative joint
positions within 0.007 m. Only Hips moves vertically for shoe clearance; the technical Root bone
remains at ground control. `--flat-mesh-check` skins 1209 actual shoe vertices per frame: neither
shoe penetrates the flat plane, walk/aim-walk/crouch have a near-floor sole throughout the loop,
and sprint retains its airborne phases (64–66 contact frames of 120). The raw UAL walk comparison
mesh itself reaches about 0.047 m below the plane. These flat-mode results still need a live
visual verdict; exact pose matching on a moving root may cause horizontal foot slide.

Stairs require more than this whole-body height correction. `--stair-source-report` finds the raw
stair-up shoe up to 0.313 m inside the current higher tread and the raw stair-down shoe up to
0.418 m above its support. The clip phase, root travel, and step geometry are not aligned. Simply
copying those poses would worsen the stair demo; they need a terrain-matched trajectory/contact
profile before exact-source matching is appropriate.

## Could clips be converted into procedural gaits?

Yes, **semi-automatically**. An offline importer can sample the entire source pose (already done
here), detect and label contact intervals, extract root travel/stride/foot arcs and pelvis/arm
curves, then fit those into editable gait-profile resources. Runtime code can combine a profile's
timing and style with target speed, terrain support, and IK constraints. A single clip is not enough
to determine how to climb a different staircase or turn at an arbitrary speed; contact semantics,
terrain scale, and transitions still need validation and sometimes hand tuning. This distinction
also appears in [Epic's motion-matching documentation](https://dev.epicgames.com/documentation/unreal-engine/motion-matching-in-unreal-engine): it indexes source poses and trajectories, then uses
procedural warping for gaps in coverage, rather than treating a source clip as a complete general
controller. The [phase-functioned locomotion research](https://www.research.ed.ac.uk/en/publications/phase-functioned-neural-networks-for-character-control/) likewise learns phase-conditioned
control from motion data and environmental information, not from one clip alone.

## Outside research and what it implies here

- [Kovar, Schreiner, and Gleicher, *Footskate Cleanup for Motion Capture Editing* (2002)](https://graphics.cs.wisc.edu/Papers/2002/KSG02/)
  treats a planted foot as a contact constraint, not a free-running periodic foot target. It also
  discusses avoiding knee pops while enforcing that contact. **Inference for this prototype:**
  merely keeping local foot height flat during stance will still look like sliding while the root
  is stationary; a real moving test needs a world-space foot plant.
- [Redfern and Schumann, *A model of foot placement during gait* (1994)](https://pubmed.ncbi.nlm.nih.gov/7798284/)
  reports that swing-foot velocity is near zero at heel contact and relates foot placement to the
  pelvis and opposite support foot. **Inference:** landing timing, pelvis travel, and support-foot
  position should be coordinated instead of tuned as unrelated sine curves.
- [Epic's Foot Placement plant settings](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/AnimationWarpingRuntime/FFootPlacementPlantSettings)
  expose separate controls for locking, ground distance, heel adjustment, and leg extension;
  [Epic's Game Animation Sample documentation](https://dev.epicgames.com/documentation/unreal-engine/game-animation-sample-project-in-unreal-engine)
  describes leg IK and offset-root/pelvis presentation. These are architectural references, **not
  permission to import Epic's UE-only sample assets into this Godot project** (see
  [the GASP asset review](../AGENT_TASKS/027_gasp_animation_assets_and_architecture_reference.md)).

## Recommended next experiment

First get a live visual verdict on the four flat modes, especially horizontal foot slide and any
pelvis bob introduced by clearance. Their mesh checks establish shoe-to-flat-plane clearance but
not convincing weight transfer. For stairs, align clip phase and root travel to real tread geometry
before copying a full source pose; then add a mesh-versus-tread check and a controlled correction.
Extracting compact editable curves and contact intervals from the sampled data, so the modes can
work without their source clips, remains future work. No gameplay integration is justified yet.

The scene still cannot validate general terrain adaptation, turning, or reliable stair-shoe
contact. The moving root is a scripted path, not `Player` movement. Do not mistake a clean headless
joint/mesh result for a finished walk animation.
